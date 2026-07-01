#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

OS_HOST="https://localhost:9200"
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
IDS_FILE="ids.json"
WINDOW_SECONDS="${WINDOW_SECONDS:-86400}"
BUFFER_SECONDS=3600

NOW_MS=$(date +%s%3N)
START_MS=$(( NOW_MS - (WINDOW_SECONDS + BUFFER_SECONDS) * 1000 ))
END_MS=$(( NOW_MS + BUFFER_SECONDS * 1000 ))

echo "Historical Analysis range: $START_MS ~ $END_MS (window=${WINDOW_SECONDS}s + ${BUFFER_SECONDS}s buffer)"

register_and_run() {
  FILE="$1"
  KEY="$2"

  DETECTOR_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_anomaly_detection/detectors" \
    -H "Content-Type: application/json" \
    --data-binary @"$FILE" | jq -r '._id')

  echo "$KEY detector_id: $DETECTOR_ID"
  jq --arg id "$DETECTOR_ID" --arg key "$KEY" '.[$key] = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

  echo "Starting historical analysis for $KEY..."
  curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_anomaly_detection/detectors/$DETECTOR_ID/_start" \
    -H "Content-Type: application/json" \
    -d "{ \"start_time\": $START_MS, \"end_time\": $END_MS }" | jq .
}

register_and_run requests/detectors/severity-detector.json severity_detector_id
register_and_run requests/detectors/network-detector.json network_detector_id

echo "Detectors created and historical analysis started."
