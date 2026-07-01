#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

OS_HOST="https://localhost:9200"
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
IDS_FILE="ids.json"
VECTOR_INDEX="jjam-siem-vector"
SOURCE_INDEX="jjam-siem-logs"
PIPELINE_NAME="jjam-siem-embedding-pipeline"

EMBEDDING_MODEL_ID=$(jq -r '.embedding_model_id' "$IDS_FILE")

echo "Creating ingest pipeline: $PIPELINE_NAME"
jq --arg id "$EMBEDDING_MODEL_ID" '.processors[0].text_embedding.model_id = $id' \
  requests/pipelines/jjam-siem-embedding-pipeline.json > /tmp/jjam-embedding-pipeline.json

curl -sk -u "$AUTH" -X PUT "$OS_HOST/_ingest/pipeline/$PIPELINE_NAME" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/jjam-embedding-pipeline.json | jq .

echo "Creating vector index: $VECTOR_INDEX"
curl -sk -u "$AUTH" -X PUT "$OS_HOST/$VECTOR_INDEX" \
  -H "Content-Type: application/json" \
  --data-binary @requests/mappings/jjam-siem-vector-mapping.json | jq .

echo "Reindexing (test batch, max_docs=10000)..."
TASK=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_reindex?wait_for_completion=false" \
  -H "Content-Type: application/json" \
  -d "{
    \"source\": { \"index\": \"$SOURCE_INDEX\" },
    \"dest\":   { \"index\": \"$VECTOR_INDEX\" },
    \"max_docs\": 10000
  }" | jq -r '.task')

echo "Reindex task: $TASK"
jq --arg t "$TASK" '.reindex_task_id = $t' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"
echo "Check progress: curl -sk -u \"$AUTH\" \"$OS_HOST/_tasks/$TASK\" | jq '.task.status'"
echo "Before the lecture, re-run full reindex without max_docs to cover all 100k documents."
