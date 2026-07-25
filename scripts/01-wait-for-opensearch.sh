#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

OS_HOST="http://localhost:9200"

echo "Waiting for OpenSearch cluster..."
until curl -s "$OS_HOST/_cluster/health" | grep -q '"status"'; do
  sleep 3
  echo "  still waiting..."
done

curl -s "$OS_HOST/_cluster/health" | jq .

echo "Registering trusted_connector_endpoints_regex..."
curl -s -X PUT "$OS_HOST/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{
    "persistent": {
      "plugins.ml_commons.connector.private_ip_enabled": true,
      "plugins.ml_commons.trusted_connector_endpoints_regex": [
        "^https://api\\.openai\\.com/.*$",
        "^https://api\\.anthropic\\.com/.*$",
        "^http://ollama:11434/.*$"
      ]
    }
  }' | jq .

echo "OpenSearch is ready."
