#!/usr/bin/env bash
# 전체 배포 오케스트레이터 — toolkit clone부터 detector 생성까지 전 과정(단계 01~07)을 순서대로 실행.
# 중간에 실패하면 이 스크립트를 처음부터 재실행하지 말고, 실패한 단계부터 개별 스크립트를 직접 실행할 것.
# 예: 05-register-llm-connector.sh에서 실패했다면 -> bash scripts/05-register-llm-connector.sh --option "$LLM_OPTION" 부터 이어서.
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

echo "=== 컨테이너 기동 (LLM_OPTION=$LLM_OPTION) ==="
if [ "$LLM_OPTION" = "b" ]; then
  docker compose --profile ollama up -d
else
  docker compose up -d
fi

echo "=== [1/7] OpenSearch 기동 대기 + 클러스터 설정 ==="
bash scripts/01-wait-for-opensearch.sh

echo "=== [2/7] 데이터 생성 + 적재 ==="
bash scripts/02-generate-and-ingest.sh

echo "=== [3/7] 임베딩 모델 등록 ==="
bash scripts/03-register-embedding-model.sh

echo "=== [4/7] 벡터 인덱스 생성 + 재인덱싱 ==="
bash scripts/04-create-vector-index.sh

echo "=== [5/7] LLM 커넥터 등록 ==="
bash scripts/05-register-llm-connector.sh --option "$LLM_OPTION"

echo "=== [6/7] RAG + Conversational 에이전트 등록 ==="
bash scripts/06-register-agents.sh --option "$LLM_OPTION"

echo "=== [7/7] Anomaly Detector 등록 ==="
bash scripts/07-create-detectors.sh

echo ""
echo "=== 배포 완료. Summary (ids.json) ==="
cat ids.json | jq .
echo ""
echo "API:        http://localhost:9200"
echo "Dashboards: http://localhost:5601"
