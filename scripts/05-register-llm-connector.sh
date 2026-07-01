#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

OPTION="a"
while [ $# -gt 0 ]; do
  case "$1" in
    --option) OPTION="$2"; shift 2 ;;
    *) shift ;;
  esac
done

OS_HOST="https://localhost:9200"
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
IDS_FILE="ids.json"
MODEL_GROUP_ID=$(jq -r '.model_group_id' "$IDS_FILE")

case "$OPTION" in
  a)
    jq --arg key "${OPENAI_API_KEY:-}" '.credential.openAI_key = $key' \
      requests/connectors/openai-connector.json > /tmp/jjam-connector.json
    RESPONSE_FILTER='$.choices[0].message.content'
    ;;
  b)
    jq --arg model "${OLLAMA_MODEL:-qwen2.5:7b}" '.parameters.model = $model' \
      requests/connectors/ollama-connector.json > /tmp/jjam-connector.json
    RESPONSE_FILTER='$.choices[0].message.content'
    ;;
  c)
    jq --arg key "${ANTHROPIC_API_KEY:-}" '.credential.anthropic_key = $key' \
      requests/connectors/claude-connector.json > /tmp/jjam-connector.json
    RESPONSE_FILTER='$.content[0].text'
    ;;
  *)
    echo "Unknown option: $OPTION (use a, b, or c)"
    exit 1
    ;;
esac

echo "Registering connector (option $OPTION)..."
CONNECTOR_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/connectors/_create" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/jjam-connector.json | jq -r '.connector_id')

echo "connector_id: $CONNECTOR_ID"
jq --arg id "$CONNECTOR_ID" --arg opt "$OPTION" --arg rf "$RESPONSE_FILTER" \
  '.connector_id = $id | .llm_option = $opt | .response_filter = $rf' \
  "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

echo "Registering LLM model..."
TASK_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/_register" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"jjam-siem-llm-option-$OPTION\",
    \"function_name\": \"remote\",
    \"model_group_id\": \"$MODEL_GROUP_ID\",
    \"connector_id\": \"$CONNECTOR_ID\"
  }" | jq -r '.task_id')

echo "task_id: $TASK_ID"
STATE=""
until [ "$STATE" = "COMPLETED" ]; do
  sleep 3
  STATE=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq -r '.state')
  echo "  state: $STATE"
  if [ "$STATE" = "FAILED" ]; then
    echo "LLM model registration failed."
    exit 1
  fi
done

LLM_MODEL_ID=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq -r '.model_id')
jq --arg id "$LLM_MODEL_ID" '.llm_model_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

echo "Deploying LLM model..."
curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/$LLM_MODEL_ID/_deploy" | jq .

STATE=""
until [ "$STATE" = "DEPLOYED" ]; do
  sleep 3
  STATE=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/models/$LLM_MODEL_ID" | jq -r '.model_state')
  echo "  model_state: $STATE"
done

echo "LLM model deployed (option $OPTION): $LLM_MODEL_ID"

echo "Testing connection..."
curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/$LLM_MODEL_ID/_predict" \
  -H "Content-Type: application/json" \
  -d '{"parameters": {"prompt": "Reply with OK if you can read this."}}' | jq .
