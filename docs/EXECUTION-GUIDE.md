# EXECUTION GUIDE — 실행 가이드 (단계별 상세판)

`docs/QUICKSTART.md`가 "복붙해서 빨리 띄우기"용이라면, 이 문서는 **각 단계에서 실제로 무슨 일이 일어나는지, 뭐가 정상 출력인지, 얼마나 걸리는지**까지 다루는 상세 실행 가이드입니다. 설정값의 의미 자체는 [CONFIGURATION.md](CONFIGURATION.md), 개념 학습은 [STUDY-GUIDE.md](STUDY-GUIDE.md) 참고.

## 사전 준비

```bash
docker --version          # Docker + Compose V2
docker compose version
poetry --version           # opensearch-siem-toolkit 실행에 필요
jq --version                # JSON 파싱에 전 스크립트가 사용
cp .env.example .env
```

`.env`를 열어 최소한 아래를 채우세요:
- `LLM_OPTION` — `a`(OpenAI) / `b`(Ollama) / `c`(Claude API) 중 선택
- 선택한 옵션에 맞는 API 키(`OPENAI_API_KEY` 또는 `ANTHROPIC_API_KEY`) — Option B는 키 불필요

각 값의 의미는 [CONFIGURATION.md §2](CONFIGURATION.md#2-env--envexample--환경변수-전체) 참고.

---

## 두 가지 실행 방법

### 방법 A — 한 번에 전부 (빠르게 띄우고 싶을 때)

```bash
bash scripts/deploy-all.sh
```

내부적으로 아래 "방법 B"의 모든 단계를 순서대로 실행합니다. 중간에 실패하면 **이 스크립트를 처음부터 재실행하지 말고**, 아래 표에서 실패한 단계 번호를 찾아 그 스크립트만 단독으로 재실행하세요.

### 방법 B — 한 단계씩 (뭘 하는지 보면서 배우고 싶을 때)

```bash
bash scripts/00-start-containers.sh
bash scripts/01-wait-for-opensearch.sh
bash scripts/02-generate-and-ingest.sh
bash scripts/03-register-embedding-model.sh
bash scripts/04-create-vector-index.sh
bash scripts/05-register-llm-connector.sh --option a   # a/b/c 중 본인 옵션
bash scripts/06-register-agents.sh --option a          # 05와 동일한 옵션
bash scripts/07-create-detectors.sh
```

---

## 단계별 상세

### 0단계 — `00-start-containers.sh`

| 항목 | 내용 |
|---|---|
| 명령 | `bash scripts/00-start-containers.sh` |
| 하는 일 | `toolkit/` 클론 여부 확인 → `ids.json` 초기화(`{}`) → `.env`의 `LLM_OPTION`을 읽어 `opensearch`/`dashboards` 컨테이너 기동(Option B는 `ollama`도 `--profile ollama`로 같이 기동) |
| 확인 | `docker ps` — `jjam-opensearch`, `jjam-dashboards`가 `Up` 상태(Option B는 `jjam-ollama`도) |
| 소요 | 10~30초 |

### 1단계 — `01-wait-for-opensearch.sh`

| 항목 | 내용 |
|---|---|
| 하는 일 | 클러스터가 요청 받을 준비될 때까지 대기 → ML Commons 클러스터 설정(`trusted_connector_endpoints_regex` 등) 등록 |
| 예상 출력 | `Waiting for OpenSearch cluster...` → 헬스체크 JSON(`"status":"yellow"`가 싱글노드 정상) → 설정 등록 결과(`"acknowledged":true`) → `OpenSearch is ready.` |
| 소요 | 10초~1분(컨테이너가 이미 안정되어 있으면 바로 통과) |
| 실패 시 | 계속 "still waiting..."만 나오면 `docker logs jjam-opensearch`로 컨테이너 자체가 뜨는지 확인 |

### 2단계 — `02-generate-and-ingest.sh` ⚠️ 시간이 오래 걸림

| 항목 | 내용 |
|---|---|
| 하는 일 | `jjam-siem-logs` 인덱스 매핑 생성 → `toolkit/`(opensearch-siem-toolkit) 설치 → 전체 SIEM 데이터셋 다운로드(`siem-download`) → 데이터 변형 생성(`siem-vary`) → bulk 인제스트 |
| **최초 실행 소요** | **10~20분** (12개 데이터셋 전체 다운로드, 이후 캐시됨) |
| 재실행 시 소요 | 1~5분(다운로드 캐시 스킵, `VARIATIONS` 값에 따라 다름) |
| 확인 | `curl -s http://localhost:9200/jjam-siem-logs/_count \| jq .` → `count` 값이 `VARIATIONS × 100000`에 근접해야 함(기본 5 → 약 50만 건) |
| 실패 시 | `docs/TROUBLESHOOTING.md`의 "bulk 인제스트가 실패" / "siem-download가 오래 걸림" 항목 참고 |

### 3단계 — `03-register-embedding-model.sh`

| 항목 | 내용 |
|---|---|
| 하는 일 | `huggingface/sentence-transformers/all-MiniLM-L12-v2` 임베딩 모델을 OpenSearch가 자동 다운로드·등록·배포 |
| 예상 출력 | `Registering model group...` → `Registering embedding model...` → `state: REGISTERING` 반복 → `COMPLETED` → `Deploying embedding model...` → `model_state: DEPLOYING` → `DEPLOYED` |
| 소요 | 1~3분 (모델 다운로드 포함) |
| 실패 시 | `model_state: DEPLOY_FAILED`가 반복되면 서버가 `artifacts.opensearch.org`에 접근 가능한지(외부 인터넷) 확인 |

### 4단계 — `04-create-vector-index.sh`

| 항목 | 내용 |
|---|---|
| 하는 일 | 임베딩 파이프라인 생성 → `jjam-siem-vector` 인덱스 생성 → `jjam-siem-logs`에서 1만 건(테스트용)을 벡터 인덱스로 재인덱싱 |
| 소요 | 1~3분 (1만 건 기준) |
| 확인 | `curl -s "http://localhost:9200/_tasks/$(jq -r '.reindex_task_id' ids.json)" \| jq '.task.status'` |
| 강의 전날 밤 할 일 | 전체 10만~50만 건 재인덱싱은 CPU 바운드라 수십 분~수시간 걸릴 수 있음 — `max_docs` 없이 `_reindex`를 다시 걸어 미리 돌려둘 것([QUICKSTART.md](QUICKSTART.md) 6번 참고) |

### 5단계 — `05-register-llm-connector.sh --option {a|b|c}`

| 항목 | 내용 |
|---|---|
| 하는 일 | 선택한 옵션의 Connector 등록 → LLM 모델 등록(`function_name: remote`) → 배포 → 테스트 `_predict` 호출까지 자동 실행 |
| 예상 출력 | `connector_id: <ID>` → `task_id: <ID>` → `state: COMPLETED` → `model_state: DEPLOYED` → 마지막에 테스트 응답 JSON(`"Reply with OK..."` 질문에 대한 실제 응답) |
| 소요 | 10초~1분(Option B는 로컬 모델 크기에 따라 더 걸릴 수 있음) |
| 실패 시 | 401/403이면 API 키 확인. 타임아웃이면 `docs/TROUBLESHOOTING.md`의 옵션별 항목 참고 |

### 6단계 — `06-register-agents.sh --option {a|b|c}`

| 항목 | 내용 |
|---|---|
| 하는 일 | RAG(Flow) Agent와 Conversational Agent를 순서대로 등록. 05번의 결과(임베딩/LLM 모델 ID, response_filter)를 자동으로 채워 넣음 |
| 예상 출력 | `rag_agent_id: <ID>` → `conversational_agent_id: <ID>` → `Agents registered.` |
| 소요 | 몇 초 |
| **주의** | 05번과 **반드시 같은 `--option` 값**을 줘야 함(다르면 `response_filter`가 안 맞아 응답 파싱이 깨짐) |

### 7단계 — `07-create-detectors.sh`

| 항목 | 내용 |
|---|---|
| 하는 일 | severity/network 이상탐지 Detector 2종 등록 → 각각 Historical Analysis 자동 시작(조회 구간 기본 30일) |
| 예상 출력 | `severity_detector_id: <ID>` → 시작 결과 JSON → `network_detector_id: <ID>` → 시작 결과 JSON → `Detectors created and historical analysis started.` |
| 소요 | 몇 초(분석 자체는 백그라운드에서 계속 진행) |
| 확인 | Dashboards(`http://localhost:5601`) → Anomaly Detection → 두 detector가 목록에 보이고 Historical Analysis 진행 중/완료 상태인지 |

---

## 전체 완료 후 최종 확인

```bash
cat ids.json | jq .
```
아래 키가 전부 채워져 있어야 정상: `model_group_id`, `embedding_model_id`, `reindex_task_id`, `connector_id`, `llm_option`, `response_filter`, `llm_model_id`, `rag_agent_id`, `conversational_agent_id`, `severity_detector_id`, `network_detector_id`.

접속 확인:
- Dashboards: http://localhost:5601 (로그인 없이 바로 접근되어야 정상)
- OpenSearch API: http://localhost:9200

---

## 정리(재실행하고 싶을 때)

```bash
bash scripts/99-teardown.sh
```
볼륨까지 삭제되므로 데이터가 전부 사라집니다. 컨테이너만 껐다 다시 켜고 싶다면(데이터 유지) `docker compose down`(볼륨 옵션 없이) 또는 `docker compose stop`을 쓰세요.

## 문제가 생기면

[TROUBLESHOOTING.md](TROUBLESHOOTING.md)를 먼저 확인하세요 — 이 레포에서 실제로 발생했던 문제와 원인/해결법이 전부 기록되어 있습니다.
