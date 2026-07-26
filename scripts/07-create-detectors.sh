#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

OS_HOST="http://localhost:9200"
IDS_FILE="ids.json"
BUFFER_SECONDS=3600

# 방어적 재등록: teardown(docker compose down -v)은 볼륨을 지우므로 01-wait-for-opensearch.sh가
# 등록해둔 persistent 클러스터 설정도 같이 날아감. 01을 다시 안 거치고 02~07만 재실행하는 경우에도
# 이 값이 기본 1로 돌아가 있으면 아래 두 detector 중 두 번째가 "No available task slot"로 실패하므로
# (2026-07-26 실측) 07 자신도 방어적으로 한 번 더 등록해둠. 이미 2로 되어 있으면 그냥 덮어쓸 뿐 무해.
curl -s -X PUT "$OS_HOST/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{"persistent": {"plugins.anomaly_detection.max_batch_task_per_node": 2}}' > /dev/null
# 2026-07-04 실측: historical analysis 조회 구간을 실제 데이터 범위(siem-vary --window, 기본 24h)보다
# 훨씬 넓게 잡으면(데이터 없는 구간 -> 갑자기 데이터 있는 구간 전환) RCF가 그 경계를 자연스럽게 anomaly로 잡음.
# 라이브 데모에서 "데이터가 없다가 갑자기 생기는 지점"이 grade 1.0으로 튀는 걸 보여주는 용도 — 별도 스파이크 주입 없이도 재현됨.
HISTORICAL_LOOKBACK_SECONDS="${HISTORICAL_LOOKBACK_SECONDS:-2592000}"  # 기본 30일

# macOS(BSD date)는 %N(나노초)을 지원 안 해서 %s%3N이 깨짐 — 초 단위만 쓰고 *1000으로 밀리초 변환(이 용도엔 서브초 정밀도 불필요)
NOW_MS=$(( $(date +%s) * 1000 ))
START_MS=$(( NOW_MS - HISTORICAL_LOOKBACK_SECONDS * 1000 ))
END_MS=$(( NOW_MS + BUFFER_SECONDS * 1000 ))

echo "Historical Analysis range: $START_MS ~ $END_MS (lookback=${HISTORICAL_LOOKBACK_SECONDS}s, 실제 데이터 범위보다 넓게 잡아 자연 anomaly 유도)"

register_and_run() {
  FILE="$1"
  KEY="$2"

  CREATE_RESPONSE=$(curl -s -X POST "$OS_HOST/_plugins/_anomaly_detection/detectors" \
    -H "Content-Type: application/json" \
    --data-binary @"$FILE")
  DETECTOR_ID=$(echo "$CREATE_RESPONSE" | jq -r '._id')
  if [ -z "$DETECTOR_ID" ] || [ "$DETECTOR_ID" = "null" ]; then
    echo "$KEY 생성 실패. 원본 응답:"
    echo "$CREATE_RESPONSE" | jq .
    return 1
  fi

  echo "$KEY detector_id: $DETECTOR_ID"
  jq --arg id "$DETECTOR_ID" --arg key "$KEY" '.[$key] = $id' "$IDS_FILE" > "$IDS_FILE.tmp" && mv "$IDS_FILE.tmp" "$IDS_FILE"

  echo "Starting historical analysis for $KEY..."
  curl -s -X POST "$OS_HOST/_plugins/_anomaly_detection/detectors/$DETECTOR_ID/_start" \
    -H "Content-Type: application/json" \
    -d "{ \"start_time\": $START_MS, \"end_time\": $END_MS }" | jq .
}

register_and_run requests/detectors/severity-detector.json severity_detector_id
register_and_run requests/detectors/network-detector.json network_detector_id

echo "Detectors created and historical analysis started."
