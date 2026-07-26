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

## 스크립트 실행 환경

### `.env` 로드 시 `export: '-Xmx2g': not a valid identifier`

`export $(grep -v '^#' .env | xargs)` 패턴은 값에 공백이 들어간 변수(`OPENSEARCH_JAVA_OPTS="-Xms2g -Xmx2g"` 등)를 만나면 unquoted 명령치환 때문에 다시 word-split되어 깨집니다. 모든 스크립트는 `set -a; source .env; set +a` 방식으로 로드하므로 이 문제는 없지만, 스크립트를 직접 수정/복제할 때 예전 패턴을 다시 쓰지 마세요. `.env`/`.env.example`의 공백 포함 값은 반드시 quote(`"..."`)로 감싸야 합니다 — quote 없이 `source`하면 뒤쪽 토큰이 별도 명령으로 실행되려다 실패합니다.

### bulk 인제스트가 `Expecting value: line 1 column 1 (char 0)`로 실패

단일 `_bulk` 요청이 OpenSearch 기본 `http.max_content_length`(100MB)를 넘으면 연결이 끊기고 빈 응답이 옵니다(HTTP 에러 바디조차 안 옴). `VARIATIONS`가 크면(기본 5) 파일마다 각각 100k건 전체 분량(약 135MB)이라 100MB를 넘습니다 — "5개로 분할"이 아니라 "5개의 독립된 전체 변형본"이라는 점에 주의하세요. `scripts/02-generate-and-ingest.sh`는 파일당 20,000줄 단위로 쪼개서 여러 번 나눠 보냅니다.

### macOS에서 `split: illegal option --`

`--numeric-suffixes`, `--additional-suffix`는 GNU coreutils 전용 옵션이라 macOS 기본 `split`(BSD)에서 깨집니다. `split -l 20000 "$f" "$SPLIT_DIR/part_"` 처럼 macOS/Linux 공통 옵션만 사용하세요(파일명 글롭도 확장자 없이 `part_*`로).

### macOS에서 `value too great for base (error token is "...N")`

`date +%s%3N`(밀리초 계산)은 GNU date 전용입니다. macOS 기본 `date`(BSD)는 `%N`을 모르는 포맷 지시자로 취급해서 문자 그대로 끼워넣고(`1783096223` 뒤에 `3N`이 붙는 식), 그 결과를 산술 컨텍스트에 넣으면 이 에러가 납니다. `scripts/07-create-detectors.sh`는 `NOW_MS=$(( $(date +%s) * 1000 ))`처럼 초 단위만 쓰고 밀리초로 변환합니다(Historical Analysis 윈도우 계산엔 서브초 정밀도가 필요 없음).

## OpenSearch 클러스터 / 보안

### 이 레포는 보안 플러그인을 비활성화합니다 (2026-07-24 변경)

실습 난이도를 낮추기 위해 `docker-compose.yml`의 `opensearch` 서비스에 `DISABLE_SECURITY_PLUGIN=true`를 설정했습니다(이전엔 `OPENSEARCH_INITIAL_ADMIN_PASSWORD`만 설정해 보안 플러그인을 기본값(활성화)으로 뒀었는데, 그 방식은 폐기됨). 즉 API는 `http://localhost:9200`으로 인증 없이 바로 접근 가능하고, `curl`에 `-k`나 `-u admin:...`을 붙일 필요가 없습니다. `plugins.ml_commons.model_access_control_enabled`도 `false`로 같이 꺼져 있습니다(보안 플러그인이 꺼진 상태에서 모델 접근제어만 켜두면 의미도 없고 오히려 권한 에러를 유발할 수 있음). **이건 실습 편의를 위한 설정이라 프로덕션에서는 절대 이렇게 쓰면 안 됩니다.** **(2026-07-25 버그 수정)** `DISABLE_SECURITY_PLUGIN=true`는 OpenSearch 노드 쪽만 끄는 설정이고, Dashboards 컨테이너는 자체 보안 플러그인을 따로 갖고 있어서 이것만으로는 Dashboards 로그인 화면이 그대로 뜸(백엔드가 보안 API를 더 이상 안 갖고 있는데 Dashboards만 로그인을 요구하는 상태). `dashboards` 서비스에도 `DISABLE_SECURITY_DASHBOARDS_PLUGIN=true`를 추가해야 완전히 꺼짐 — 둘 다 있어야 함.

### ML 요청이 이유 없이 실패/타임아웃 (메모리 서킷브레이커)

ml-commons는 두 가지 메모리 서킷브레이커를 갖고 있습니다: `plugins.ml_commons.native_memory_threshold`(네이티브/OS 메모리, 공식 기본값 90%)와 `plugins.ml_commons.jvm_heap_memory_threshold`(JVM 힙, 공식 기본값 85%). 사용률이 이 값을 넘으면 임베딩/LLM 요청이 조용히 차단됩니다(에러 메시지가 명확하지 않을 수 있음). 이 레포는 작은 실습 환경에서 서킷브레이커가 자꾸 걸리는 걸 막기 위해 두 값을 각각 `100`/`95`로 올려뒀습니다(`docker-compose.yml`의 `opensearch` 서비스 환경변수, [CONFIGURATION.md](CONFIGURATION.md) §1-1 참고) — 즉 이 레포 기본 설정에서는 이 문제가 거의 발생하지 않아야 정상입니다. 그래도 ML 요청이 이상하게 실패하면 `docker stats jjam-opensearch`로 실제 메모리 사용률부터 확인하세요.

### Connector 호출이 막힘 (trusted_connector_endpoints_regex)

OpenAI/Anthropic/Ollama 엔드포인트가 `plugins.ml_commons.trusted_connector_endpoints_regex`에 등록되어 있지 않으면 Connector의 `_predict` 호출이 차단됩니다. `scripts/01-wait-for-opensearch.sh`가 3개 패턴을 모두 등록하므로, `deploy-all.sh` 없이 스크립트를 개별 실행할 경우 이 단계를 빠뜨리지 마세요.

### 임베딩 모델 등록이 `COMPLETED`로 안 넘어감

Pretrained 모델(`huggingface/sentence-transformers/all-MiniLM-L12-v2`) 등록은 OpenSearch가 `artifacts.opensearch.org`에서 모델을 자동 다운로드합니다. 서버가 외부 인터넷에 접근 가능한지 확인하세요. 사내망/방화벽 환경에서는 실패할 수 있습니다.

## Anomaly Detection

### Historical Analysis 결과가 비어있음

`siem-vary`는 원본 타임스탬프를 실행 시점(`now`) 기준 `--window`(기본 86400초=24시간) 범위 안으로 슬라이딩합니다. 즉 데이터의 실제 시간 범위는 "고정된 과거 날짜"가 아니라 "스크립트를 돌린 시점 기준 최근 24시간"입니다. `scripts/07-create-detectors.sh`는 Historical Analysis 조회 범위를 `HISTORICAL_LOOKBACK_SECONDS`(기본 30일)만큼 넉넉하게 잡아서 `now`까지 조회하므로(아래 항목 참고) 데이터 인제스트와 Detector 등록 사이에 시간이 좀 벌어져도(예: 인제스트 다음날 Detector 등록) 문제없습니다. 그래도 결과가 비어있다면 `curl jjam-siem-logs/_count`로 실제 문서 수부터 확인하세요.

### Detector validation failed

`indices`에 지정한 인덱스(`jjam-siem-logs`)가 아직 생성되지 않았거나 문서가 0건인 상태에서 Detector를 등록하면 validation이 실패할 수 있습니다. `scripts/02-generate-and-ingest.sh`가 완료된 이후에 `07-create-detectors.sh`를 실행하는 순서를 지키세요.

### Historical Analysis 결과가 거의 다 `anomaly_grade: 0.0`으로만 나옴

고장 아닙니다 — `advanced_siem` 샘플 데이터는 실제로 튀는 패턴 없이 랜덤하게만 분포돼 있어서, 조회 기간이 데이터 실제 범위(기본 24h)와 딱 맞으면 RCF가 이상하다고 판단할 게 없어 grade가 계속 0으로 나옵니다(confidence는 0.9대로 높게 나와서 모델 자체는 정상 학습된 상태). 확실하게 grade가 튀는 걸 보려면 조회 기간을 데이터 실제 범위보다 훨씬 넓게(예: 1개월) 잡으세요 — 데이터가 없던 긴 구간에서 갑자기 데이터가 생기는 구간의 경계를 RCF가 자연스럽게 이상치로 잡습니다. `scripts/07-create-detectors.sh`는 `HISTORICAL_LOOKBACK_SECONDS`(기본 2592000초=30일)로 이미 이렇게 동작합니다. Dashboards UI에서 수동으로 조회할 땐 detector 상세 화면의 "Modify historical analysis range"로 기간을 넓히면 됩니다.

### 두 번째 Detector의 Historical Analysis가 `"No available task slot"` (400)로 실패

`07-create-detectors.sh`는 `severity_detector_id`를 만들고 바로 Historical Analysis를 `_start`한 다음, 완료를 기다리지 않고 곧바로 `network_detector_id`도 만들어서 `_start`합니다. 첫 번째 detector(위 로그에서 `severity_detector_id`)는 정상적으로 등록·시작됐고, 두 번째(`network_detector_id`)만 Historical Analysis 시작에 실패한 상태입니다(detector 자체는 만들어졌으니 아래 재시도만 하면 됨).

**진짜 원인(2026-07-26, AD 플러그인 소스코드 `ADTaskManager.java`까지 확인해서 정정)**: 처음엔 `plugins.anomaly_detection.max_batch_task_per_node`(노드당 동시 batch task 수, 기본값 **1**)만 올리면 될 줄 알았는데, **그것만으론 부족했습니다**. 이유: 이 레포의 두 detector는 둘 다 `category_field`가 있는 **HC(high-cardinality/multi-entity) detector**인데, HC detector가 Historical Analysis를 시작할 때는 슬롯 1개가 아니라

```
min(plugins.anomaly_detection.max_running_entities_per_detector_for_historical_analysis, 그 시점의 가용 슬롯)
```

개를 **한 번에 예약**합니다. 이 설정의 기본값은 **10**입니다. 즉 `max_batch_task_per_node`를 2로만 올려도, 먼저 시작하는 detector가 그 순간의 가용 슬롯(2)을 `min(10, 2)=2`로 **전부** 선점해버려서 두 번째 detector 몫이 0이 됩니다 — `max_batch_task_per_node`를 10 이하 어떤 값으로 올려도 첫 detector가 항상 전부 가져가므로, 총량만 올리는 접근 자체가 구조적으로 안 통합니다.

**정정된 조치**: `max_running_entities_per_detector_for_historical_analysis`를 `2`로 낮춰서 detector 하나당 최대 2슬롯까지만 선점하게 하고, `max_batch_task_per_node`는 `4`(=detector 2개 × 슬롯 cap 2)로 맞춰서 두 detector가 동시에 각자 슬롯을 확보할 수 있도록 했습니다. `scripts/01-wait-for-opensearch.sh`와 `scripts/07-create-detectors.sh`(teardown으로 volume이 지워진 경우를 위한 방어적 재등록) 둘 다 이 두 설정을 같이 등록합니다.

**이미 이 에러를 겪었다면**: 컨테이너를 처음부터 다시 올릴 필요 없이, 클러스터 설정 두 개를 올리고 실패한 detector만 재시작하면 됩니다:
```bash
curl -s -X PUT "http://localhost:9200/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{"persistent": {
    "plugins.anomaly_detection.max_batch_task_per_node": 4,
    "plugins.anomaly_detection.max_running_entities_per_detector_for_historical_analysis": 2
  }}'

NETWORK_DETECTOR_ID=$(jq -r '.network_detector_id' ids.json)
curl -s -X POST "http://localhost:9200/_plugins/_anomaly_detection/detectors/$NETWORK_DETECTOR_ID/_start" \
  -H "Content-Type: application/json" \
  -d '{"start_time": <07 실행 시 출력된 START_MS>, "end_time": <같은 END_MS>}'
```

**detector를 더 추가한다면**: `max_batch_task_per_node`가 최소 `(detector 개수) × max_running_entities_per_detector_for_historical_analysis` 이상이어야 전부 동시에 돌 수 있습니다.

### Historical Analysis 진행 상태를 API로 확인하려면 (`_profile/ad_task`)

```bash
DETECTOR_ID=<detector_id>
curl -s "http://localhost:9200/_plugins/_anomaly_detection/detectors/$DETECTOR_ID/_profile/ad_task" \
  | jq '{state: .ad_task.ad_task.state, task_progress: .ad_task.ad_task.task_progress, pending_entities: .ad_task.pending_entities_count, running_entities: .ad_task.running_entities_count}'
```

**주의**: 응답이 `.ad_task.state`가 아니라 **`.ad_task.ad_task.state`로 한 번 더 중첩**되어 있습니다(공식 문서 예시로 확인, 2026-07-26) — `ad_task` 필드 안에 또 `ad_task`라는 키가 있는 구조라 헷갈리기 쉽습니다. 이 레포의 두 detector는 `category_field`가 있는 HC(High-Cardinality/multi-entity) detector라서 `task_type`이 `HISTORICAL_HC_DETECTOR`로 나오고, `pending_entities_count`/`running_entities_count`로 카테고리별(예: `event_type`, `protocol`) 진행 상황도 같이 볼 수 있습니다. `state`가 `FINISHED`면 완료.

### Dashboards에서 detector "Start" 버튼을 눌렀더니 `"Anomaly detector job is already running: <detector_id>"` 에러

Dashboards 목록/상세 화면의 **"Start"는 Historical Analysis가 아니라 실시간(real-time) 감지 job을 켜는 버튼**입니다(`07-create-detectors.sh`가 미리 걸어둔 건 Historical Analysis — 서로 다른 기능, `STUDY-GUIDE.md` §1-5 표 참고). 해당 detector에 이미 Historical Analysis 작업이 돌고 있는 상태에서 실시간 job을 또 걸려고 하면(같은 job 스케줄링 메커니즘을 공유하기 때문에) 이 에러가 납니다. 에러 자체는 정상 동작이고, Historical Analysis가 끝난 detector는 실시간 job도 충돌 없이 걸립니다.

**다만 이 실시간 job을 켤 필요가 이 실습에는 없습니다** — 아래 항목 참고.

### 실시간(Real-time) 감지를 켜면 `INIT` 상태에서 계속 멈춰있음 / 결과가 안 나옴

**정상입니다, 버그 아닙니다.** 이 레포의 데이터는 `siem-vary`가 배포 시점에 딱 한 번만 생성해서 넣는 정적 스냅샷이지, 계속 새로 흘러 들어오는 라이브 인덱스가 아닙니다. 실시간 감지는 `detection_interval`(이 레포는 10분)마다 "방금 들어온 새 문서"를 계속 집계해야 하는데:
- Cold start(공식 문서: 최대 10,000개의 과거 데이터 포인트로 초기 모델을 미리 학습하는 기능) 자체는 기존 백필 데이터로 일부 진행될 수 있지만,
- `shingle_size`(기본 8) 개의 **연속된 구간에 데이터가 계속 있어야** 초기화가 끝나는데, 배포 시점 이후로는 새 문서가 안 들어오니 그 다음 구간부터는 빈 버킷만 쌓입니다.
- 공식 문서도 "`initialization` 상태로 하루 넘게 있으면 데이터 누락 구간부터 의심하라"고 안내할 정도로 흔한 현상이라고 확인됩니다.

**대응**: 그냥 두거나 Stop 시키면 됩니다 — 이 실습에서 필요한 건 `07-create-detectors.sh`가 이미 돌려준 Historical Analysis 결과뿐입니다. 실시간 감지를 실제로 보여주려면 `02-generate-and-ingest.sh`를 주기적으로 반복 실행해서 데이터가 계속 들어오는 것처럼 흉내내야 하는데, 이건 이 강의 범위 밖입니다.

## LLM Connector

### 모델 등록이 `until` 루프에서 `state: null`을 반복하며 안 끝남(Ctrl+C 필요)

Connector 생성이나 모델 등록 요청 자체가 실패하면(잘못된 payload, credential 누락 등) `connector_id`/`task_id`가 `null`이 되는데, 예전 버전 스크립트는 이걸 실패로 인식하지 못하고 `until [ "$STATE" = "COMPLETED" ]`가 영원히 `state: null`만 반복했습니다. 지금 스크립트는 각 ID를 받은 직후 null/빈값을 체크해서 실패 시 원본 에러 응답을 출력하고 즉시 종료합니다. 만약 커스텀 스크립트를 짠다면 이 패턴을 반드시 넣으세요 — 안 그러면 무한 대기에 빠집니다.

### `IllegalArgumentException: The name you provided is already being used by a model group with ID: ...`

`model_group_id`를 응답에서 `null`로 읽었을 때 등장하는 진짜 원인입니다. `model_access_control_enabled: false` 상태에서도 model group 이름은 유일해야 해서, 스크립트를 재실행하면(디버깅 중 흔함) 같은 이름(`jjam-siem-model-group`)으로 다시 등록하려다 거부당하고, 그 실패 응답에는 `model_group_id` 필드가 없어 이후 임베딩 모델 등록이 `"Model group not found"`(reason에 "for null" 포함)로 연쇄 실패합니다. 지금 스크립트는 등록 전에 이름으로 기존 그룹을 먼저 검색해서 있으면 재사용합니다(`_plugins/_ml/model_groups/_search`) — 몇 번을 재실행해도 안전합니다.

### `Connector credential is null or empty list`

ml-commons는 Connector에 `credential` 필드가 무조건 있어야 통과시킵니다. Ollama는 API 키가 필요 없지만, 이 검증 때문에 최소 1개 키라도(`{"dummy_key": "dummy_value"}`) 넣어줘야 합니다 — `requests/connectors/ollama-connector.json`에 이미 반영되어 있습니다. 커넥터 JSON을 직접 만질 때 이 필드를 빼먹지 마세요.

### `Remote inference host name has private ip address: host.docker.internal` (또는 LAN IP)

ml-commons는 기본적으로 사설 IP/루프백 계열 호스트로의 아웃바운드 호출을 막습니다(SSRF 방지). `plugins.ml_commons.connector.private_ip_enabled: true`를 클러스터 설정에 추가해야 하며(이미 `01-wait-for-opensearch.sh`에 포함됨), **이미 컨테이너가 떠 있는 상태에서 이 설정을 나중에 켰다면 컨테이너를 재시작해야 반영되는 것으로 확인됐습니다**(OpenSearch 3.7.0에서 실측 — 설정 자체는 `acknowledged: true`로 성공하고 클러스터 로그에도 반영되는데, 이미 초기화된 HTTP 클라이언트 경로에는 실시간 반영이 안 됨). 처음부터 `deploy-all.sh`(내부적으로 `00-start-containers.sh` → `01-wait-for-opensearch.sh` 순서)로 컨테이너를 켜는 정상 플로우라면 이 설정이 커넥터 사용 전에 이미 적용되어 있으니 문제 없지만, 디버깅 중 설정을 나중에 바꿨다면 `docker compose restart` 후 모델을 다시 `_deploy`하고 재시도하세요.

### Option B(Ollama) 응답이 없거나 매우 느림

기본값 `qwen2.5:7b`는 16GB 서버 기준입니다. 그보다 큰 모델(예: `qwen2.5:32b`, Q4 양자화 기준 최소 20GB+ 필요)을 서버 RAM에 안 맞는데 그대로 쓰면 메모리 부족으로 응답이 아예 안 오거나 스왑으로 매우 느려집니다. `.env`의 `OLLAMA_MODEL`을 서버 RAM에 맞게 낮추세요([OPTION-B-OLLAMA.md](OPTION-B-OLLAMA.md) 참고).

### Option C(Claude API) 모델명 오류

`claude-sonnet-4-6`은 실재하지 않는 모델명입니다(과거 문서의 오기). 이 레포의 `requests/connectors/claude-connector.json`은 `claude-sonnet-5`로 정정되어 있습니다.

### Option별 response_filter를 헷갈림

Option A/B(OpenAI 호환)는 `$.choices[0].message.content`, Option C(Claude)는 `$.content[0].text`를 써야 합니다. `scripts/05-register-llm-connector.sh`가 옵션에 맞춰 자동 설정하므로 수동으로 Connector를 재등록할 때만 주의하면 됩니다.

### conversational agent 실행 시 `400 IllegalArgumentException: "Tool type not found"`

`CatIndexTool`이 원인입니다. OpenSearch 3.0부터 `CatIndexTool`이 `ListIndexTool`로 이름이 바뀌었습니다(공식 문서 확인). `requests/agents/conversational-agent.json`은 이미 `ListIndexTool`로 수정되어 있습니다 — 이미 등록된 agent에는 소급 반영이 안 되니 재배포(또는 agent 재등록) 필요합니다.

### RAG agent 실행 시 `500 "Error communicating with remote model: Read timed out"` (Option B/Ollama)

Ollama 응답이 커넥터 기본 타임아웃(30초)을 넘긴 경우입니다. 큰 모델 + RAG 프롬프트 조합이면 흔히 발생. `requests/connectors/ollama-connector.json`에 `client_config`(`read_timeout: 120000`ms 등)를 추가해뒀습니다 — 이미 등록된 커넥터에는 소급 반영 안 되므로 재배포 필요. (`client_config`의 정확한 필드명은 공식 문서 원문 확인이 안 돼서 100% 확신은 아님 — 재배포 후 로그의 `readTimeout: Xs` 값으로 실제 반영됐는지 확인할 것.) 이 설정 반영 후 RAG agent 정상 응답 확인됨.

### conversational agent가 `"Agent reached maximum iterations (5) without completing the task"`로 끝남

`SearchIndexTool`의 정확한 입력 스키마를 LLM이 못 맞춰서 반복 실패하는 증상입니다. `SearchIndexTool`은 `input` 파라미터 하나만 받는데, `{"index": "...", "query": {...}}` 형태의 JSON 문자열이어야 하고 `query`는 완전한 `_search` 요청 바디(size/query/aggs 포함)여야 합니다(공식 문서 `search-index-tool.md` 확인). 라이브 테스트에서 모델이 `event_type.keyword`처럼 근거 없는 서브필드를 임의로 붙이는 것도 관찰됨(이 매핑은 `event_type`이 이미 `keyword` 타입). `requests/agents/conversational-agent.json`의 `SearchIndexTool` description에 정확한 입력 예시와 "`.keyword` 붙이지 말 것" 경고를 명시했고 `max_iteration`도 5→8로 늘렸습니다. 재배포 필요.

## 재인덱싱

### 벡터 재인덱싱이 너무 오래 걸림

`scripts/04-create-vector-index.sh`는 기본적으로 1만건만 테스트로 재인덱싱합니다(`max_docs: 10000`). 전체 10만건 재인덱싱은 CPU 바운드 작업이라 서버 사양에 따라 수십 분~수시간 걸릴 수 있으므로, 강의 전날 밤 미리 돌려놓으세요([QUICKSTART.md](QUICKSTART.md) 6번 항목 참고).
