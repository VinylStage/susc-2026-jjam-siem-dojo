# TROUBLESHOOTING

## 인제스트 / 매핑

### `risk_score`, `entropy` 등 필드가 집계에서 안 잡힘

`advanced_siem` 원본 HuggingFace 데이터셋은 `risk_score`/`confidence`/`geo_location`을 `advanced_metadata` 객체 안에, `baseline_deviation`/`entropy`/`frequency_anomaly`/`sequence_anomaly`를 `behavioral_analytics` 객체 안에 중첩해서 제공합니다. `opensearch-siem-toolkit`의 `siem-vary`는 timestamp/src_ip/dst_ip/user만 in-place로 바꿀 뿐 구조를 평탄화하지 않으므로, 최종 NDJSON에도 이 중첩 구조가 그대로 남습니다.

쿼리/집계/Detector에서는 반드시 `advanced_metadata.risk_score`처럼 점 표기법으로 접근해야 합니다. 최상위 `risk_score`로 집계하면 에러 없이 조용히 빈 결과(0 또는 null)만 나오므로 눈치채기 어렵습니다.

### bulk 인제스트 전 매핑을 먼저 만들지 않으면

동적 매핑에 맡기면 `timestamp`가 `text`로, `risk_score`가 `long`으로 잘못 추론되는 등 타입 불일치가 발생합니다. `scripts/02-generate-and-ingest.sh`는 `requests/mappings/jjam-siem-logs-mapping.json`을 bulk 인제스트 전에 PUT합니다 — 이 순서를 절대 바꾸지 마세요.

### `siem-download`가 예상보다 오래 걸림 / `--dataset` 옵션이 안 먹음

`opensearch-siem-toolkit`의 `siem-download`는 `--dataset` 인자를 받지 않습니다. 실행하면 advanced_siem 포함 12개 데이터셋을 전부 내려받으며 최초 실행 시 10~20분 걸립니다(이미 받은 파일은 캐시로 스킵). 특정 데이터셋만 받는 옵션은 없으므로 대기가 정상입니다.

### `[SKIP] 파일 없음` 에러

`siem-vary` 실행 전에 `siem-download`가 완료되지 않은 상태입니다. `toolkit/siem_data/advanced_siem/advanced_siem_full.json` 존재 여부를 확인하세요.

## OpenSearch 클러스터 / 보안

### 이 레포는 보안 플러그인을 비활성화하지 않습니다

이전 검증 가이드(`DISABLE_SECURITY_PLUGIN=true`)와 달리, 이 학생용 레포는 `OPENSEARCH_INITIAL_ADMIN_PASSWORD`만 설정해 보안 플러그인을 기본값(활성화) 그대로 둡니다. 즉 API는 `https://localhost:9200`으로만 접근 가능하고, 자체 서명 인증서라 `curl`에는 항상 `-k`(insecure) 플래그가 필요합니다. `-k` 없이 호출하면 인증서 검증 실패로 연결이 끊깁니다.

### Connector 호출이 막힘 (trusted_connector_endpoints_regex)

OpenAI/Anthropic/Ollama 엔드포인트가 `plugins.ml_commons.trusted_connector_endpoints_regex`에 등록되어 있지 않으면 Connector의 `_predict` 호출이 차단됩니다. `scripts/01-wait-for-opensearch.sh`가 3개 패턴을 모두 등록하므로, `00-setup.sh` 없이 스크립트를 개별 실행할 경우 이 단계를 빠뜨리지 마세요.

### 임베딩 모델 등록이 `COMPLETED`로 안 넘어감

Pretrained 모델(`huggingface/sentence-transformers/all-MiniLM-L12-v2`) 등록은 OpenSearch가 `artifacts.opensearch.org`에서 모델을 자동 다운로드합니다. 서버가 외부 인터넷에 접근 가능한지 확인하세요. 사내망/방화벽 환경에서는 실패할 수 있습니다.

## Anomaly Detection

### Historical Analysis 결과가 비어있음

`siem-vary`는 원본 타임스탬프를 실행 시점(`now`) 기준 `--window`(기본 86400초=24시간) 범위 안으로 슬라이딩합니다. 즉 데이터의 실제 시간 범위는 "고정된 과거 날짜"가 아니라 "스크립트를 돌린 시점 기준 최근 24시간"입니다. `scripts/07-create-detectors.sh`는 이를 반영해 Historical Analysis 범위를 `date` 커맨드로 동적 계산합니다(`now - (WINDOW_SECONDS + 3600초 버퍼)` ~ `now + 3600초`). 만약 데이터 인제스트와 Detector 등록 사이에 시간이 많이 벌어지면(예: 인제스트 다음날 Detector 등록) 이 범위를 벗어날 수 있으니, 가급적 `00-setup.sh` 전체를 한 번에 실행하세요.

### Detector validation failed

`indices`에 지정한 인덱스(`jjam-siem-logs`)가 아직 생성되지 않았거나 문서가 0건인 상태에서 Detector를 등록하면 validation이 실패할 수 있습니다. `scripts/02-generate-and-ingest.sh`가 완료된 이후에 `07-create-detectors.sh`를 실행하는 순서를 지키세요.

## LLM Connector

### Option B(Ollama) 응답이 없거나 매우 느림

기본값 `qwen2.5:7b`는 16GB 서버 기준입니다. 강사 검증 환경(MacBook M4 48GB)에서 쓰던 `qwen2.5:32b`를 그대로 학생 환경에 적용하면 메모리 부족으로 응답이 아예 안 오거나 스왑으로 매우 느려집니다. `.env`의 `OLLAMA_MODEL`을 서버 RAM에 맞게 낮추세요([OPTION-B-OLLAMA.md](OPTION-B-OLLAMA.md) 참고).

### Option C(Claude API) 모델명 오류

`claude-sonnet-4-6`은 실재하지 않는 모델명입니다(과거 문서의 오기). 이 레포의 `requests/connectors/claude-connector.json`은 `claude-sonnet-5`로 정정되어 있습니다.

### Option별 response_filter를 헷갈림

Option A/B(OpenAI 호환)는 `$.choices[0].message.content`, Option C(Claude)는 `$.content[0].text`를 써야 합니다. `scripts/05-register-llm-connector.sh`가 옵션에 맞춰 자동 설정하므로 수동으로 Connector를 재등록할 때만 주의하면 됩니다.

## 재인덱싱

### 벡터 재인덱싱이 너무 오래 걸림

`scripts/04-create-vector-index.sh`는 기본적으로 1만건만 테스트로 재인덱싱합니다(`max_docs: 10000`). 전체 10만건 재인덱싱은 CPU 바운드 작업이라 서버 사양에 따라 수십 분~수시간 걸릴 수 있으므로, 강의 전날 밤 미리 돌려놓으세요([QUICKSTART.md](QUICKSTART.md) 6번 항목 참고).
