# CONFIGURATION — 설정 완전 참고서

이 문서는 이 레포의 모든 설정(`docker-compose.yml`, `.env`, 클러스터 설정 API)이 **무엇을 하고 왜 이렇게 되어 있는지**를 하나씩 설명합니다. "어떻게 실행하는지"는 [EXECUTION-GUIDE.md](EXECUTION-GUIDE.md), 개념 자체를 배우고 싶으면 [STUDY-GUIDE.md](STUDY-GUIDE.md)를 참고하세요.

> 표기: 각 항목에 (공식 문서 확인) / (실측, 이 레포에서 직접 확인) / (권장, 공식 근거 약함) 중 하나를 표시합니다.

---

## 1. `docker-compose.yml`

### 1-1. `opensearch` 서비스

```yaml
image: opensearchproject/opensearch:3.7.0
environment:
  - discovery.type=single-node
  - DISABLE_SECURITY_PLUGIN=true
  - OPENSEARCH_JAVA_OPTS=${OPENSEARCH_JAVA_OPTS}
  - plugins.ml_commons.only_run_on_ml_node=false
  - plugins.ml_commons.model_access_control_enabled=false
  - plugins.ml_commons.native_memory_threshold=100
  - plugins.ml_commons.jvm_heap_memory_threshold=95
```

| 설정 | 값 | 설명 |
|---|---|---|
| `discovery.type` | `single-node` | 클러스터 디스커버리(다른 노드 찾기) 과정을 생략하고 혼자 마스터 역할까지 겸함. 실습용 1노드 구성의 표준 설정. |
| `DISABLE_SECURITY_PLUGIN` | `true` | Security 플러그인 자체를 끔 — 인증서, 관리자 비밀번호 설정 없이 바로 API 호출 가능(공식 문서 확인, [Docker 설치 가이드](https://docs.opensearch.org/latest/install-and-configure/install-opensearch/docker/)). **공식 경고**: "인터넷에서 접근 가능한 호스트에서는 보안 설정을 직접 구성하기 전까지 이 설정을 쓰지 말 것." 이 레포는 로컬 실습 전용이라 의도적으로 껐지만, 실무/프로덕션에는 절대 쓰면 안 됩니다. |
| `plugins.ml_commons.only_run_on_ml_node` | `false` | ML 작업(모델 추론 등)을 ML 전용 노드에서만 돌리는 제약을 해제. 기본값은 `true`이지만, 우리는 노드가 1개뿐이라 그 노드가 ML 작업까지 겸해야 해서 꺼둠(공식 문서 확인, [cluster-settings](https://docs.opensearch.org/latest/ml-commons-plugin/cluster-settings/)). 다중 노드 클러스터라면 기본값(`true`)대로 두고 ML 전용 노드 role을 따로 부여하는 게 정석. |
| `plugins.ml_commons.model_access_control_enabled` | `false` | 모델별 접근권한 제어(누가 어떤 모델을 쓸 수 있는지) 기능. **공식 문서에 이 기능은 Security 플러그인이 켜져 있어야 의미가 있다고 명시**되어 있음([model-access-control](https://docs.opensearch.org/latest/ml-commons-plugin/model-access-control/)) — 우리는 Security 자체를 껐으므로 이 값과 무관하게 어차피 전부 공개 상태. `false`로 명시해서 혼란을 줄임. |
| `plugins.ml_commons.native_memory_threshold` | `100` | ML 작업 실행 전 "네이티브(OS) 메모리 사용률이 이 값을 넘으면 차단"하는 서킷브레이커. **기본값은 90**(공식 문서 확인) — 이 레포는 100(=사실상 차단 비활성화)으로 올려놨습니다. 이유: 작은 랩탑/실습 환경에서는 메모리 사용률이 90% 근처를 왔다갔다 하기 쉬운데, 그때마다 임베딩/LLM 요청이 서킷브레이커에 걸려 실패하면 실습이 자꾸 끊깁니다. **트레이드오프**: 실제 메모리 부족(OOM)에 대한 보호장치가 약해진다는 뜻이므로, 프로덕션에서는 기본값(90) 근처를 쓰는 게 맞습니다. |
| `plugins.ml_commons.jvm_heap_memory_threshold` | `95` | 위와 같은 개념인데 JVM 힙 메모리 기준. **기본값은 85**(공식 문서 확인) — 같은 이유로 95로 올려둠. ML 요청이 이유 없이 실패하면 이 두 값과 실제 메모리 사용률부터 의심하세요(`docker stats jjam-opensearch`로 확인). |

### 1-2. `dashboards` 서비스

```yaml
image: opensearchproject/opensearch-dashboards:3.7.0
environment:
  - OPENSEARCH_HOSTS=["http://opensearch:9200"]
  - DISABLE_SECURITY_DASHBOARDS_PLUGIN=true
```

| 설정 | 설명 |
|---|---|
| `OPENSEARCH_HOSTS` | Dashboards가 연결할 OpenSearch 주소. Docker Compose 네트워크 안에서는 서비스명(`opensearch`)이 곧 호스트명. 보안이 꺼져 있으니 `http`(⚠️ `https` 아님). |
| `DISABLE_SECURITY_DASHBOARDS_PLUGIN` | **`opensearch`의 `DISABLE_SECURITY_PLUGIN`과는 별개의 설정**입니다. Dashboards는 자기 자신의 임베디드 Security 플러그인을 따로 갖고 있어서, 백엔드(OpenSearch 노드) 보안만 끄면 Dashboards는 여전히 로그인 화면을 띄웁니다. 이 값도 같이 꺼야 완전히 로그인 없이 접근됩니다(2026-07-25 실측으로 발견된 이슈, 이후 수정됨). 공식 문서 출처는 `docs.opensearch.org`가 아니라 [opensearch-build 저장소의 Docker 이미지 README](https://github.com/opensearch-project/opensearch-build/blob/main/docker/release/README.md)입니다 — *"Default to null, set to true disables Security Dashboards Plugin... by removing securityDashboards plugin folder"* (한 번 껐다 다시 켜려면 컨테이너를 재생성해야 함, 되돌릴 수 없는 방식). |

### 1-3. `ollama` 서비스

```yaml
image: ollama/ollama
profiles: ["ollama"]
environment:
  - OLLAMA_HOST=0.0.0.0
```

`profiles: [ollama]`가 핵심 — Docker Compose의 프로필 기능으로, `docker compose up -d`만 실행하면 이 서비스는 **뜨지 않습니다**. `docker compose --profile ollama up -d`처럼 프로필을 명시해야만 같이 뜹니다. 이 레포에서는 `.env`의 `LLM_OPTION=b`(Ollama)를 선택한 사람만 이 컨테이너가 필요하므로, `scripts/00-start-containers.sh`가 `LLM_OPTION` 값을 보고 자동으로 `--profile ollama` 여부를 결정합니다. `OLLAMA_HOST=0.0.0.0`은 Ollama가 컨테이너 내부 어느 인터페이스에서든 요청을 받게 하는 설정(컨테이너 기본값은 localhost만 바인딩이라 다른 컨테이너에서 접근이 안 될 수 있음).

---

## 2. `.env` / `.env.example` — 환경변수 전체

```
OPENSEARCH_JAVA_OPTS="-Xms2g -Xmx2g"
LLM_OPTION=a
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OLLAMA_MODEL=qwen2.5:7b
VARIATIONS=5
WINDOW_SECONDS=86400
```

| 변수 | 기본값 | 어디서 쓰이나 | 설명 |
|---|---|---|---|
| `OPENSEARCH_JAVA_OPTS` | `"-Xms2g -Xmx2g"` | `docker-compose.yml`의 `opensearch` 서비스 | JVM 힙 최소/최대 크기. **반드시 따옴표로 감쌀 것** — 공백 포함 값을 따옴표 없이 `export`하면 뒤 토큰이 별도 명령으로 실행되려다 실패합니다(`docs/TROUBLESHOOTING.md` 참고). 컴퓨터 메모리가 넉넉하면 `-Xms4g -Xmx4g`처럼 올려도 됩니다(호스트 RAM의 절반 이하 권장, OpenSearch 공식 가이드라인). |
| `LLM_OPTION` | `a` | `00`(컨테이너 profile 결정), `05`,`06`(--option 값, 플래그 생략 시 이 값으로 폴백), `deploy-all.sh`(전달만) | `a`=OpenAI, `b`=Ollama, `c`=Claude API. 어느 LLM Connector/모델을 등록할지 결정. `01`은 이 값과 무관하게 3개 프로바이더 패턴을 전부 등록함. **05/06을 개별 실행할 땐 여전히 `--option`을 명시하는 걸 권장** — 플래그 없이 실행하면 `.env`의 이 값을 자동으로 쓰지만(2026-07-26 수정 전에는 무조건 `a`로 고정되는 버그가 있었음), 명시하는 쪽이 실수를 줄임. |
| `OPENAI_API_KEY` | (비어있음) | `05-register-llm-connector.sh --option a` | Option A 사용 시 필수. |
| `ANTHROPIC_API_KEY` | (비어있음) | `05-register-llm-connector.sh --option c` | Option C 사용 시 필수. |
| `OLLAMA_MODEL` | `qwen2.5:7b` | `05-register-llm-connector.sh --option b` | Option B 사용 시 어떤 모델을 커넥터에 연결할지. RAM에 맞게 조정([docs/OPTION-B-OLLAMA.md](OPTION-B-OLLAMA.md) 표 참고). |
| `VARIATIONS` | `5` | `02-generate-and-ingest.sh` | `siem-vary`가 원본 데이터셋을 몇 개의 "변형본"으로 만들지. 값이 크면 인제스트할 데이터량이 그만큼 늘어나 시간이 더 걸림 — 5개 변형본이면 이미 각각 10만 건(원본 전체 크기)이라 "5개로 쪼갠다"가 아니라 "5개의 독립된 전체 사본"이라는 점 주의. |
| `WINDOW_SECONDS` | `86400`(24시간) | `02-generate-and-ingest.sh` | `siem-vary`가 원본 타임스탬프를 실행 시점(`now`) 기준 이 범위 안으로 슬라이딩. 즉 데이터의 실제 시간 범위는 "스크립트를 돌린 시점 기준 최근 N초"가 됩니다. |

---

## 3. 클러스터 설정 API (컨테이너 환경변수가 아니라 `PUT _cluster/settings`로 등록되는 것)

`scripts/01-wait-for-opensearch.sh`가 컨테이너가 뜬 뒤 자동으로 등록합니다:

```json
PUT _cluster/settings
{
  "persistent": {
    "plugins.ml_commons.connector.private_ip_enabled": true,
    "plugins.ml_commons.trusted_connector_endpoints_regex": [
      "^https://api\\.openai\\.com/.*$",
      "^https://api\\.anthropic\\.com/.*$",
      "^http://ollama:11434/.*$"
    ],
    "plugins.anomaly_detection.max_batch_task_per_node": 2
  }
}
```

| 설정 | 기본값 | 설명 |
|---|---|---|
| `plugins.ml_commons.connector.private_ip_enabled` | `false`(공식 문서 확인) | ML 커넥터가 사설 IP/루프백 주소로 나가는 요청을 막는 SSRF 방지 장치. 우리 Ollama가 `ollama:11434`라는 컨테이너 내부(사설) 주소라서, 이 값을 `true`로 켜야 접근이 허용됩니다. Option A/C(외부 공인 API)만 쓴다면 이론상 몰라도 되지만, 이 레포는 세 옵션을 다 지원해야 해서 항상 켜둡니다. |
| `plugins.ml_commons.trusted_connector_endpoints_regex` | 기본 내장 리스트(AWS/OpenAI/Cohere 패턴 등, 비어있지 않음 — 공식 문서 확인) | ML 커넥터가 호출을 허용받는 외부 엔드포인트의 정규식 화이트리스트. 기본 리스트에 Anthropic·로컬 Ollama 패턴이 없기 때문에, 이 레포는 3개 패턴(OpenAI/Anthropic/Ollama)을 명시적으로 등록합니다. **이 등록이 없으면 05번 Connector 단계 이후 `_predict` 호출이 조용히 막힙니다** — Connector 자체는 등록에 성공하는데 실제 호출만 거부되는 형태라 헷갈리기 쉬운 실패 패턴. |
| `plugins.anomaly_detection.max_batch_task_per_node` | `1`(공식 소스 코드 확인, `AnomalyDetectorSettings.java`) | 노드 하나당 동시에 돌릴 수 있는 Historical Analysis(batch task) 개수 제한. 기본값 1이면 `07-create-detectors.sh`가 만드는 2개 detector(`severity`, `network`)의 Historical Analysis를 연달아 `_start`할 때, 첫 번째가 끝나기 전에 두 번째를 시작하려다 `"No available task slot"` 400 에러가 납니다(2026-07-26 실측 확인). 이 레포는 detector가 정확히 2개라서 `2`로 올려 둘 다 동시에 돌게 했습니다. detector를 더 추가한다면 이 값도 같이 올려야 합니다. |

**참고 — `agent_framework_enabled` / `rag_pipeline_feature_enabled`를 왜 이 레포는 안 켜나요?**
공식 [OpenSearch Assistant Toolkit 가이드](https://docs.opensearch.org/latest/ml-commons-plugin/opensearch-assistant/)는 이 두 설정을 `true`로 켜는 걸 사전 준비 단계로 안내합니다. 하지만 **OpenSearch 3.7.0 기준 두 설정의 실제 기본값은 이미 `true`**입니다(ml-commons 소스 코드 확인) — 즉 이 레포처럼 아무것도 설정하지 않아도 Agent Framework와 RAG 파이프라인은 이미 켜져 있는 상태입니다. `homelab-two-node`(강사 환경)는 이 두 값을 방어적으로 명시하는데, 이는 안전을 위한 관례이지 우리 레포에 기능적 결함이 있다는 뜻은 아닙니다.

---

## 4. `ids.json` — 스크립트 간 상태 전달 파일

각 스크립트가 생성한 ID를 다음 스크립트가 읽어 쓸 수 있도록 저장하는 파일입니다. `scripts/00-start-containers.sh`가 컨테이너를 띄우기 직전에 `{}`로 초기화합니다.

| 키 | 어느 스크립트가 쓰나 | 어느 스크립트가 읽나 |
|---|---|---|
| `model_group_id` | 03 | 05 |
| `embedding_model_id` | 03 | 04, 06 |
| `reindex_task_id` | 04 | (진행 확인용, 사람이 직접 조회) |
| `connector_id` | 05 | (직접 사용하는 스크립트 없음, 참고용) |
| `llm_option` | 05 | (참고용) |
| `response_filter` | 05 | 06 |
| `llm_model_id` | 05 | 06 |
| `rag_agent_id` | 06 | (핸즈온 실습에서 사용) |
| `conversational_agent_id` | 06 | (핸즈온 실습에서 사용) |
| `severity_detector_id` / `network_detector_id` | 07 | (Dashboards UI에서 확인) |

`cat ids.json | jq .`로 언제든 현재 상태를 확인할 수 있습니다. 이 파일이 꼬이면(예: 스크립트를 순서 무시하고 실행) 뒷 단계가 필요한 ID를 못 찾아 실패하므로, 문제가 생기면 이 파일부터 확인하세요.

---

## 참고 문서

- 실행 방법: [EXECUTION-GUIDE.md](EXECUTION-GUIDE.md)
- 개념 학습: [STUDY-GUIDE.md](STUDY-GUIDE.md)
- 문제 해결: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
