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
IDS_FILE="ids.json"

echo "Registering model group..."
MODEL_GROUP_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/model_groups/_register" \
  -H "Content-Type: application/json" \
  -d '{"name":"jjam-siem-model-group","description":"jjam-siem-dojo models"}' \
  | jq -r '.model_group_id')

jq --arg id "$MODEL_GROUP_ID" '.model_group_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"
echo "model_group_id: $MODEL_GROUP_ID"

echo "Registering embedding model..."
TASK_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/_register" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"huggingface/sentence-transformers/all-MiniLM-L12-v2\",
    \"version\": \"1.0.1\",
    \"model_group_id\": \"$MODEL_GROUP_ID\",
    \"model_format\": \"TORCH_SCRIPT\"
  }" | jq -r '.task_id')

echo "task_id: $TASK_ID"
echo "Waiting for model registration..."
STATE=""
until [ "$STATE" = "COMPLETED" ]; do
  sleep 5
  STATE=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq -r '.state')
  echo "  state: $STATE"
  if [ "$STATE" = "FAILED" ]; then
    echo "Model registration failed."
    exit 1
  fi
done

EMBEDDING_MODEL_ID=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq -r '.model_id')
jq --arg id "$EMBEDDING_MODEL_ID" '.embedding_model_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"
echo "embedding_model_id: $EMBEDDING_MODEL_ID"

echo "Deploying embedding model..."
curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/$EMBEDDING_MODEL_ID/_deploy" | jq .

STATE=""
until [ "$STATE" = "DEPLOYED" ]; do
  sleep 5
  STATE=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/models/$EMBEDDING_MODEL_ID" | jq -r '.model_state')
  echo "  model_state: $STATE"
done

echo "Embedding model deployed: $EMBEDDING_MODEL_ID"
