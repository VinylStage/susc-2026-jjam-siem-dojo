#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

LLM_OPTION="${LLM_OPTION:-a}"

if [ ! -d toolkit ]; then
  echo "Cloning opensearch-siem-toolkit..."
  git clone --depth 1 https://github.com/VinylStage/opensearch-siem-toolkit.git toolkit
fi

echo '{}' > ids.json

echo "Starting containers (LLM_OPTION=$LLM_OPTION)..."
if [ "$LLM_OPTION" = "b" ]; then
  docker compose --profile ollama up -d
else
  docker compose up -d
fi

bash scripts/01-wait-for-opensearch.sh
bash scripts/02-generate-and-ingest.sh
bash scripts/03-register-embedding-model.sh
bash scripts/04-create-vector-index.sh
bash scripts/05-register-llm-connector.sh --option "$LLM_OPTION"
bash scripts/06-register-agents.sh --option "$LLM_OPTION"
bash scripts/07-create-detectors.sh

echo "Setup complete. IDs saved in ids.json"
