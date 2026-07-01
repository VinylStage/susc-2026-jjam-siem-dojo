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

EMBEDDING_MODEL_ID=$(jq -r '.embedding_model_id' "$IDS_FILE")
LLM_MODEL_ID=$(jq -r '.llm_model_id' "$IDS_FILE")
RESPONSE_FILTER=$(jq -r '.response_filter' "$IDS_FILE")

echo "Registering RAG agent..."
jq --arg emb "$EMBEDDING_MODEL_ID" --arg llm "$LLM_MODEL_ID" \
  '(.tools[] | select(.type=="VectorDBTool") | .parameters.model_id) = $emb
   | (.tools[] | select(.type=="MLModelTool") | .parameters.model_id) = $llm' \
  requests/agents/rag-agent.json > /tmp/jjam-rag-agent.json

RAG_AGENT_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/agents/_register" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/jjam-rag-agent.json | jq -r '.agent_id')

echo "rag_agent_id: $RAG_AGENT_ID"
jq --arg id "$RAG_AGENT_ID" '.rag_agent_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

echo "Registering conversational agent..."
jq --arg emb "$EMBEDDING_MODEL_ID" --arg llm "$LLM_MODEL_ID" --arg rf "$RESPONSE_FILTER" \
  '.llm.model_id = $llm
   | .llm.parameters.response_filter = $rf
   | (.tools[] | select(.type=="VectorDBTool") | .parameters.model_id) = $emb' \
  requests/agents/conversational-agent.json > /tmp/jjam-conv-agent.json

CONV_AGENT_ID=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_ml/agents/_register" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/jjam-conv-agent.json | jq -r '.agent_id')

echo "conversational_agent_id: $CONV_AGENT_ID"
jq --arg id "$CONV_AGENT_ID" '.conversational_agent_id = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

echo "Agents registered (option $OPTION)."
