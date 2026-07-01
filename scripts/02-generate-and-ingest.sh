#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

OS_HOST="https://localhost:9200"
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
INDEX_NAME="jjam-siem-logs"
VARIATIONS="${VARIATIONS:-5}"
WINDOW_SECONDS="${WINDOW_SECONDS:-86400}"

echo "Creating index: $INDEX_NAME"
curl -sk -u "$AUTH" -X PUT "$OS_HOST/$INDEX_NAME" \
  -H "Content-Type: application/json" \
  --data-binary @requests/mappings/jjam-siem-logs-mapping.json | jq .

cd toolkit
poetry install --no-interaction

echo "Downloading datasets (all datasets, first run takes 10-20 minutes)..."
poetry run siem-download

echo "Generating $VARIATIONS variations for advanced_siem..."
poetry run siem-vary --dataset advanced_siem --variations "$VARIATIONS" --ndjson --index "$INDEX_NAME" --window "$WINDOW_SECONDS"

cd ..

for f in toolkit/siem_data/variations/advanced_siem/*.ndjson; do
  echo "Ingesting: $f"
  curl -sk -u "$AUTH" -X POST "$OS_HOST/_bulk" \
    -H "Content-Type: application/x-ndjson" \
    --data-binary @"$f" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('errors:', r['errors'], '| took:', r['took'], 'ms')"
done

echo "Document count:"
curl -sk -u "$AUTH" "$OS_HOST/$INDEX_NAME/_count" | jq .
