#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

OS_HOST="https://localhost:9200"
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"

echo "Waiting for OpenSearch cluster..."
until curl -sk -u "$AUTH" "$OS_HOST/_cluster/health" | grep -q '"status"'; do
  sleep 3
  echo "  still waiting..."
done

curl -sk -u "$AUTH" "$OS_HOST/_cluster/health" | jq .

echo "Registering trusted_connector_endpoints_regex..."
curl -sk -u "$AUTH" -X PUT "$OS_HOST/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{
    "persistent": {
      "plugins.ml_commons.trusted_connector_endpoints_regex": [
        "^https://api\\.openai\\.com/.*$",
        "^https://api\\.anthropic\\.com/.*$",
        "^http://ollama:11434/.*$"
      ]
    }
  }' | jq .

echo "OpenSearch is ready."
