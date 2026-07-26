#!/usr/bin/env bash
# OpenSearch 배포 단계 — 컨테이너를 실제로 띄우는 스크립트.
# 01번부터는 전부 이 컨테이너들한테 API(curl)로 말 거는 것뿐이라, 이 단계가 실패하면 뒤는 전부 실패함.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  source .env
  set +a
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

echo ""
echo "Containers started. Verify with: docker ps"
echo "Next: bash scripts/01-wait-for-opensearch.sh"
