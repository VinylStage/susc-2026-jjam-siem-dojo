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
WINDOW_SECONDS="${WINDOW_SECONDS:-86400}"
BUFFER_SECONDS=3600

# macOS(BSD date)는 %N(나노초)을 지원 안 해서 %s%3N이 깨짐 — 초 단위만 쓰고 *1000으로 밀리초 변환(이 용도엔 서브초 정밀도 불필요)
NOW_MS=$(( $(date +%s) * 1000 ))
START_MS=$(( NOW_MS - (WINDOW_SECONDS + BUFFER_SECONDS) * 1000 ))
END_MS=$(( NOW_MS + BUFFER_SECONDS * 1000 ))

echo "Historical Analysis range: $START_MS ~ $END_MS (window=${WINDOW_SECONDS}s + ${BUFFER_SECONDS}s buffer)"

register_and_run() {
  FILE="$1"
  KEY="$2"

  CREATE_RESPONSE=$(curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_anomaly_detection/detectors" \
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
  curl -sk -u "$AUTH" -X POST "$OS_HOST/_plugins/_anomaly_detection/detectors/$DETECTOR_ID/_start" \
    -H "Content-Type: application/json" \
    -d "{ \"start_time\": $START_MS, \"end_time\": $END_MS }" | jq .
}

register_and_run requests/detectors/severity-detector.json severity_detector_id
register_and_run requests/detectors/network-detector.json network_detector_id

echo "Detectors created and historical analysis started."
