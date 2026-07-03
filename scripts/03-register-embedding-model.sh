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

echo "Checking for existing model group (재실행해도 이름 중복 에러 안 나게)..."
MODEL_GROUP_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/model_groups/_search" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"name": "jjam-siem-model-group"}}}' \
  | jq -r '.hits.hits[0]._id // empty')

if [ -n "$MODEL_GROUP_ID" ]; then
  echo "Reusing existing model_group_id: $MODEL_GROUP_ID"
else
  echo "Registering model group..."
  GROUP_RESPONSE=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/model_groups/_register" \
    -H "Content-Type: application/json" \
    -d '{"name":"jjam-siem-model-group","description":"jjam-siem-dojo models"}')
  MODEL_GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.model_group_id')
  if [ -z "$MODEL_GROUP_ID" ] || [ "$MODEL_GROUP_ID" = "null" ]; then
    echo "Model group registration failed. Full response:"
    echo "$GROUP_RESPONSE" | jq .
    exit 1
  fi
  echo "model_group_id: $MODEL_GROUP_ID"
fi
jq --arg id "$MODEL_GROUP_ID" '.model_group_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

echo "Registering embedding model..."
REGISTER_RESPONSE=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/_register" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"huggingface/sentence-transformers/all-MiniLM-L12-v2\",
    \"version\": \"1.0.1\",
    \"model_group_id\": \"$MODEL_GROUP_ID\",
    \"model_format\": \"TORCH_SCRIPT\"
  }")
TASK_ID=$(echo "$REGISTER_RESPONSE" | jq -r '.task_id')
echo "task_id: $TASK_ID"
if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
  echo "Model registration request failed. Full response:"
  echo "$REGISTER_RESPONSE" | jq .
  exit 1
fi

echo "Waiting for model registration..."
STATE=""
until [ "$STATE" = "COMPLETED" ]; do
  sleep 5
  STATE=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq -r '.state')
  echo "  state: $STATE"
  if [ "$STATE" = "FAILED" ] || [ "$STATE" = "null" ]; then
    echo "Model registration failed."
    curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq .
    exit 1
  fi
done

EMBEDDING_MODEL_ID=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq -r '.model_id')
if [ -z "$EMBEDDING_MODEL_ID" ] || [ "$EMBEDDING_MODEL_ID" = "null" ]; then
  echo "Could not read model_id from completed task."
  curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/tasks/$TASK_ID" | jq .
  exit 1
fi
jq --arg id "$EMBEDDING_MODEL_ID" '.embedding_model_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"
echo "embedding_model_id: $EMBEDDING_MODEL_ID"

echo "Deploying embedding model..."
curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/models/$EMBEDDING_MODEL_ID/_deploy" | jq .

STATE=""
RETRIES=0
until [ "$STATE" = "DEPLOYED" ]; do
  sleep 5
  STATE=$(curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/models/$EMBEDDING_MODEL_ID" | jq -r '.model_state')
  echo "  model_state: $STATE"
  if [ "$STATE" = "DEPLOY_FAILED" ] || [ "$STATE" = "null" ]; then
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge 5 ]; then
      echo "Embedding model deploy failed or model not found after retries."
      curl -sk -u "$AUTH" "$OS_HOST/_plugins/_ml/models/$EMBEDDING_MODEL_ID" | jq .
      exit 1
    fi
  fi
done

echo "Embedding model deployed: $EMBEDDING_MODEL_ID"
