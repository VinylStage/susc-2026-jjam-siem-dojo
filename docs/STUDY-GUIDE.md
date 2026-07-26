# STUDY GUIDE — 개념 학습 가이드 (Session 1 + 2 전체)

강의를 놓쳤거나 복습하고 싶은 분을 위한 자료입니다. 순서대로 읽으면 "검색엔진이 뭔지도 몰랐던 사람"이 "AI Agent가 알아서 로그를 분석하는 원리"까지 이해할 수 있도록 구성했습니다. 실제 명령은 이 레포의 인덱스/필드명(`jjam-siem-logs`, `advanced_metadata.risk_score` 등)을 그대로 사용하므로, [EXECUTION-GUIDE.md](EXECUTION-GUIDE.md)로 배포한 뒤 직접 실행해보면서 읽는 걸 권장합니다.

---

# Part 1 — Session 1: 검색엔진과 이상탐지

## 1-1. OpenSearch란 무엇인가

OpenSearch는 한 문장으로 "검색 + 분석 + 시각화"를 한 번에 하는 도구입니다.

| MySQL(관계형 DB)에 익숙하다면 | OpenSearch | 비유 |
|---|---|---|
| Database | Cluster | 학교 전체 |
| Table | Index | 과목 게시판 |
| Row | Document | 게시글 하나 |
| Column | Field | 제목, 내용, 작성일 |
| Schema | Mapping | 필드 타입 정의 |

이 레포에서는 `jjam-siem-logs`라는 인덱스가 "SIEM 로그가 쌓이는 테이블"입니다.

**SIEM이 뭔가요?** Security Information and Event Management — 여러 곳(방화벽, 서버, 네트워크 장비)에서 나오는 로그를 한곳에 모아 보는 "보안 CCTV 통합 모니터"라고 생각하면 됩니다. 로그를 한 곳에 모으는 것(수집) → 화면으로 보는 것(대시보드) → 이상을 판단하는 것(분석/탐지)까지가 SIEM의 역할이고, 이 레포는 그 전체 파이프라인을 작게 재현한 것입니다.

## 1-2. 검색의 원리 — 역인덱스(Inverted Index)

일반 데이터베이스처럼 "문서를 하나씩 열어보며 단어가 있는지 확인"하면 10만 건만 돼도 느립니다. 검색엔진은 반대로 동작합니다 — 미리 "이 단어는 어느 문서에 있다"는 색인을 만들어둡니다(교과서 뒤 찾아보기 페이지와 원리가 같음).

```
역인덱스 구조:
단어        → 문서 ID 목록
─────────────────────────
"error"     → [doc_1, doc_5, doc_12]
"timeout"   → [doc_3, doc_5, doc_8]
```

검색어를 받으면 문서를 뒤지는 게 아니라 이 색인표에서 바로 찾기 때문에, 10만 건이든 1억 건이든 밀리초 단위로 끝납니다. 단, **이 방식은 단어가 정확히 일치해야만 찾아진다는 한계**가 있습니다 — "서버가 죽었다"로 검색하면 "error"라는 단어가 들어간 로그는 찾지 못합니다. 이 한계를 벡터 검색(Part 2)이 해결합니다.

## 1-3. DSL 쿼리 — 실제로 써보는 검색

이 레포의 인덱스에서 바로 실행 가능한 예시들입니다(Dashboards의 Dev Tools 또는 `curl`로 실행).

**전체 건수 확인**
```
GET jjam-siem-logs/_count
```

**정확히 일치하는 값 찾기 — `term`**
```
GET jjam-siem-logs/_search
{ "query": { "term": { "severity": "critical" } }, "size": 5 }
```

**범위로 찾기 — `range`** (참고: `risk_score`는 `advanced_metadata` 객체 안에 중첩되어 있어 점 표기법 필요 — §1-6 참고)
```
GET jjam-siem-logs/_search
{
  "query": { "range": { "advanced_metadata.risk_score": { "gte": 80 } } },
  "sort": [{ "advanced_metadata.risk_score": "desc" }],
  "size": 10
}
```

**여러 조건 동시에 — `bool`/`must`**
```
GET jjam-siem-logs/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "alert_type": "DDoS" } },
        { "term": { "severity": "critical" } }
      ]
    }
  },
  "size": 5
}
```

**집계 — `aggs` (= MySQL의 `GROUP BY`)**
```
GET jjam-siem-logs/_search
{
  "size": 0,
  "aggs": { "심각도별": { "terms": { "field": "severity" } } }
}
```

**시간대별 추이 — `date_histogram`**
```
GET jjam-siem-logs/_search
{
  "size": 0,
  "aggs": {
    "monthly": {
      "date_histogram": { "field": "timestamp", "calendar_interval": "month" },
      "aggs": { "by_severity": { "terms": { "field": "severity" } } }
    }
  }
}
```

## 1-4. 대시보드 — 집계를 그림으로

집계(aggs) 결과를 화면으로 보여주는 게 Dashboards입니다. 자주 쓰는 시각화 타입: Metric(숫자 하나, 예: 전체 이벤트 수), Pie(비율, 예: severity 분포), Line(시간별 추이), Bar(TOP N, 예: 공격 유형 상위 10개). "critical 이벤트가 많으면 위험한가?"라는 질문에 대시보드 숫자만으로는 답할 수 없습니다 — 평소에도 매일 100건이면 정상이고, 갑자기 1000건이면 이상인 것이므로, "평소 대비 얼마나 튀는지"를 판단하는 건 사람의 감이 아니라 알고리즘(RCF)의 몫입니다. 그게 다음 절의 이상탐지입니다.

## 1-5. RCF 이상탐지 (Anomaly Detection)

**룰 기반 vs AI 기반**

| 룰 기반 (전통 방식) | RCF (AI 기반) |
|---|---|
| "트래픽이 100GB 넘으면 알림" | "평소 패턴"을 스스로 학습 |
| 낮엔 100GB가 정상인데 고정 임계값이라 못 잡음 | 새벽 2시에 80GB면 "평소 새벽엔 5~10GB인데 이상!" 자동 판단 |
| 임계값을 사람이 매번 설정/조정해야 함 | 임계값 설정 불필요, 새로운 유형의 공격도 탐지 가능(비지도 학습) |

**RCF(Random Cut Forest)**는 OpenSearch 1.0부터 내장된 비지도 학습 알고리즘입니다. 공식 설명: *"들어오는 데이터 스트림의 스케치(요약 모델)를 만들어서, 매 데이터 포인트마다 anomaly grade와 confidence를 계산하는 비지도 학습 알고리즘."* 미리 "정상/비정상" 라벨을 붙인 학습 데이터가 필요 없고, 데이터가 계속 들어오면서 "평소 패턴"에 대한 이해를 스스로 갱신합니다.

- **`anomaly_grade`**: 0~1 사이 값. 0이면 "이상 아님", 0보다 크면 클수록 이상 정도가 심함.
- **`confidence`**: 0~1 사이 값. "이 anomaly_grade 판단이 얼마나 신뢰할 만한가" — 모델이 데이터를 더 많이 볼수록 올라갑니다. **주의**: confidence는 모델의 정확도를 뜻하는 게 아니라 "판단의 성숙도"에 가깝습니다. Detector를 막 만든 직후(데이터를 적게 본 상태)는 anomaly_grade가 높게 나와도 confidence가 낮을 수 있으니 그런 초기 결과는 신중하게 해석해야 합니다.

**Historical Analysis vs Real-time Detection**

| 구분 | Historical Analysis | Real-time Detection |
|---|---|---|
| 용도 | 과거 데이터를 소급 분석("백테스트") | 신규로 들어오는 데이터를 실시간 감시 |
| API | `_start`에 `start_time`/`end_time` 지정 | `_start`를 시간 범위 없이 호출 |
| 동작 | 지정 기간에 대해 한 번만 배치 처리 | 백그라운드에서 계속(설정한 interval마다) 반복 |
| 이 레포에서 | ✅ 이걸 씀 — 고정 데이터셋을 검증하는 용도 | 실제 라이브 파이프라인 구축 후에 씀 |

이 레포의 `07-create-detectors.sh`는 등록 직후 Historical Analysis를 자동으로 걸어줍니다(조회 구간 30일 — 실제 데이터가 존재하는 구간(기본 24시간)보다 훨씬 넓게 잡아서, "데이터가 없다가 갑자기 생기는 경계"를 RCF가 자연스럽게 이상치로 잡도록 유도).

**멀티 피처 Detector와 `category_field`**: 이 레포의 severity-detector는 `critical_count`(critical 이벤트 수)와 `avg_risk_score`(평균 위험도) 두 피처를 동시에 봅니다. 공식 문서 주의사항: 피처가 많을수록 오히려 작은 이상을 놓치기 쉬워질 수 있습니다("차원의 저주") — 무조건 피처를 많이 넣는 게 좋은 게 아닙니다. `category_field`(이 레포는 `event_type`)는 전체를 하나로 뭉쳐 보지 않고 카테고리별로 각각 별도의 베이스라인/이상탐지를 하게 해줍니다 — 예를 들어 IP별, 사용자별로 "평소 이 IP/사용자의 패턴"을 따로 학습시키고 싶을 때 씁니다.

## 1-6. 필드 구조 — `advanced_metadata`, `behavioral_analytics`

이 레포가 쓰는 원본 데이터셋(HuggingFace `darkknight25/Advanced_SIEM_Dataset`)은 일부 필드가 중첩(nested object) 구조입니다:
- `risk_score`, `confidence`, `geo_location` → `advanced_metadata` 객체 안
- `baseline_deviation`, `entropy`, `frequency_anomaly`, `sequence_anomaly` → `behavioral_analytics` 객체 안

쿼리/집계/Detector 어디서든 `advanced_metadata.risk_score`처럼 점 표기법으로 접근해야 합니다. 최상위 `risk_score`로 검색하면 **에러 없이 조용히 빈 결과만 나오므로** 눈치채기 어렵습니다 — 결과가 이상하게 비어있으면 필드 경로부터 의심하세요. (참고: 이건 Elasticsearch/OpenSearch의 `nested` 타입이 아니라 그냥 `object` 타입이라, 복잡한 `nested` 쿼리 문법 없이 점 표기법만으로 충분합니다.)

전체 필드 목록(이벤트 타입별 전용 필드, `action` 값, 실제 문서 예시)은 [LOG-SCHEMA.md](LOG-SCHEMA.md)에 자세히 정리되어 있습니다.

---

# Part 2 — Session 2: 벡터 검색, RAG, AI Agent

## 2-1. 검색의 진화 — 3단계

```
Level 1: 키워드 검색 (Session 1에서 배운 것)
"error" 검색 → "error"라는 단어가 정확히 포함된 문서만 찾음

Level 2: 시맨틱(벡터) 검색
"서버가 죽었다" 검색 → "error", "timeout", "crash" 등 의미가 비슷한 문서도 찾음

Level 3: 에이전틱 검색
"지난달 위험한 공격 패턴 분석해줘" → AI가 알아서 쿼리를 계획하고 실행하고 분석까지 함
```

도서관 비유: 키워드 검색은 "경제학"이라는 카드만 찾는 카드 색인, 시맨틱 검색은 "돈이 어떻게 흘러가는지 알고 싶어요"라고 하면 사서가 경제학/금융/화폐론 관련 책을 다 추천해주는 것, 에이전틱 검색은 "투자할 만한 분야 찾아서 비교분석까지 해주세요"라고 하면 사서가 알아서 여러 서가를 돌며 조사하고 비교표까지 만들어주는 것.

## 2-2. 임베딩(Embedding) — 텍스트를 숫자로

임베딩은 텍스트를 숫자 배열(벡터)로 바꾸는 것입니다.

```
"고양이가 소파에서 자고 있다"        → [0.23, -0.15, 0.87, ..., -0.31]  (384개 숫자)
"cat sleeping on the couch"        → [0.22, -0.14, 0.86, ...]         ← 의미가 비슷해서 벡터도 비슷
"주식 시장이 폭락했다"               → [-0.71, 0.55, -0.23, ...]        ← 의미가 달라서 벡터도 다름
```

이 레포는 `huggingface/sentence-transformers/all-MiniLM-L12-v2` 모델을 써서 384차원 벡터를 만듭니다. 이 모델은 LLM(질문에 답하는 모델)과는 완전히 다른, 훨씬 작은 모델이고 외부 API 호출 없이 컨테이너 안에서 돕니다.

**벡터 검색이 되는 과정** (이 레포 기준):
1. `jjam-siem-vector` 인덱스의 `description_embedding` 필드는 `knn_vector` 타입(`dimension: 384`, `method: {name: hnsw, engine: lucene}`)
2. `text_embedding` ingest processor가 인덱스의 기본 파이프라인으로 걸려있어서, 문서가 들어올 때마다 `description`(텍스트) → `description_embedding`(벡터) 자동 변환
3. 검색할 때는 `neural` 쿼리로 질문 텍스트를 넣으면, 같은 임베딩 모델로 변환한 뒤 벡터 거리가 가까운 문서를 찾음

```
GET jjam-siem-vector/_search
{
  "query": {
    "neural": {
      "description_embedding": {
        "query_text": "데이터를 몰래 빼돌리는 시도",
        "model_id": "<embedding_model_id, ids.json 참고>",
        "k": 5
      }
    }
  }
}
```

`k`는 몇 개까지 가까운 결과를 가져올지(기본 10). `model_id`는 반드시 **임베딩 모델**의 ID여야 합니다(LLM 모델 ID와 헷갈리지 말 것 — `ids.json`에서 `embedding_model_id` vs `llm_model_id`로 구분됨).

**`hnsw`/`lucene`이 뭔가요?** `hnsw`(Hierarchical Navigable Small World)는 벡터를 빠르게 찾기 위한 그래프 기반 탐색 알고리즘, `engine: lucene`은 그걸 계산하는 엔진 종류(다른 선택지로 `faiss`가 있고, `nmslib`는 공식적으로 deprecated). 공식 가이드: "소규모 배포에는 Lucene, 대규모 배포에는 Faiss 권장" — 이 레포는 실습용 소규모라 Lucene을 씁니다.

**키워드 검색과 벡터 검색, 뭘 언제 쓰나요?** 둘 다 필요합니다. "정확히 이 IP를 찾아줘"류는 키워드 검색이 빠르고 정확하고, "이런 느낌의 사건을 찾아줘"류는 벡터 검색이 맞습니다. 참고로 둘을 합친 **하이브리드 검색**(`hybrid` 쿼리 + search pipeline 정규화)도 OpenSearch 2.10부터 정식(GA) 기능으로 존재합니다(이 레포 범위 밖).

## 2-3. RAG — 검색으로 찾고, LLM이 답하기

RAG(Retrieval-Augmented Generation)는 "검색으로 관련 자료를 먼저 찾고(Retrieval) → 그걸 근거로 LLM이 답을 생성(Generation)"하는 방식입니다. 이 레포의 RAG Agent는 **Flow Agent**(`"type": "flow"`) — 정해진 순서대로 도구를 실행하는 가장 단순한 형태:

```
질문 → VectorDBTool(벡터검색으로 관련 로그 찾기) → MLModelTool(LLM한테 그 로그를 근거로 분석시키기) → 답변
```

고정된 2단계라서 안정적입니다(LLM이 "다음에 뭘 할지" 스스로 판단할 필요가 없음). 대신 대화 기록을 저장하지 않아 질문 하나에 답 하나로 끝납니다.

```
POST _plugins/_ml/agents/<rag_agent_id>/_execute
{ "parameters": { "question": "지난달 가장 위험한 공격 패턴을 분석하고, 의심스러운 IP 목록과 대응 방안을 알려줘" } }
```

## 2-4. Conversational Agent — AI가 스스로 도구를 고른다

Flow Agent와 달리 **Conversational Agent**(`"type": "conversational"`)는 LLM이 질문을 보고 "이번엔 어떤 도구를 써야겠다"를 스스로 판단합니다(Chain-of-Thought/ReAct 방식). 이 레포가 등록하는 도구 4가지:

| 도구 | 역할 |
|---|---|
| `SearchIndexTool` | 키워드 검색(DSL 쿼리 실행) |
| `IndexMappingTool` | 인덱스 필드 구조 조회 |
| `VectorDBTool` | 의미 기반(벡터) 검색 |
| `ListIndexTool` | 인덱스 목록 조회 (⚠️ OpenSearch 3.0부터 `CatIndexTool`이 이 이름으로 바뀜 — 예전 문서를 보면 `CatIndexTool`로 나올 수 있음) |

```
POST _plugins/_ml/agents/<conversational_agent_id>/_execute
{ "parameters": { "question": "지금 critical severity 이벤트가 몇 건이야?" }, "verbose": true }
```

`verbose: true`를 주면 AI가 어떤 도구를 골랐는지 그 판단 과정까지 볼 수 있습니다. `max_iteration`(이 레포는 8)은 이 판단→실행 반복을 최대 몇 번까지 허용할지 — 너무 낮으면 복잡한 질문에서 답을 다 못 내고 끝나고, 너무 높으면 비용/시간이 늘어납니다. 공식 문서에도 정해진 권장값은 없고, 다루는 도구가 많을수록 여유 있게 잡으라는 정도로만 안내되어 있습니다.

**참고 — OpenSearch Agent 종류는 몇 가지?** 공식 문서 기준 현재 6가지입니다: Flow, Conversational Flow, Conversational, Conversational V2(3.7.0부터 정식 기능), Plan-Execute-Reflect(복잡한 다단계 작업을 스스로 계획→실행→반성), AG-UI(프론트엔드 연동용). 이 레포는 그중 **Flow**와 **Conversational** 두 가지만 사용합니다.

## 2-5. Agentic Search — 자연어를 쿼리로 자동 변환

여기까지는 AI가 "미리 정해진 도구"(SearchIndexTool 등)를 썼습니다. Agentic Search는 한 단계 더 나아가 자연어 질문을 **OpenSearch DSL 쿼리 자체로 자동 생성**하는 기능(`QueryPlanningTool`, OpenSearch 3.2에서 기능 도입, 3.3부터 Dashboards UI 지원):

```
POST /_plugins/_ml/agents/_register
{
  "name": "agentic_search_agent",
  "type": "flow",
  "tools": [{ "type": "QueryPlanningTool", "parameters": { "model_id": "<llm_model_id>" } }]
}
```

**⚠️ 지원 프로바이더 제한 (공식 문서 확인, 중요)**: QueryPlanningTool은 공식적으로 "Converse API를 지원하는 모델"과 작동한다고 명시되어 있고, 문서에 실제 예시로 나오는 건 **OpenAI**와 **Amazon Bedrock Converse API(이걸 통한 Claude 포함)** 뿐입니다. 즉:
- **Option A(OpenAI)**: 공식 지원.
- **Option C(Claude, 이 레포는 Anthropic 직접 API 사용)**: Bedrock을 거치지 않은 **Anthropic 직접 API 커넥터로는 공식 지원 대상이 아닙니다.** Claude 자체가 안 되는 게 아니라, "Bedrock Converse API를 통한" 경로만 검증되어 있다는 뜻 — 이 레포처럼 `api.anthropic.com`에 직접 붙는 커넥터 구조로는 동작이 확인되지 않았고, 구조적으로 안 될 가능성이 있습니다.
- **Option B(Ollama)**: 문서에 로컬/일반 프로바이더 지원 예시가 없어 마찬가지로 미지원 가능성이 높습니다.

이 기능은 이 레포의 핸즈온 "클라이맥스"로 소개되지만, Option B/C 사용자는 안 될 수 있다는 점을 미리 인지하고, 강사가 강의 전 직접 3옵션 모두 테스트해서 안내하는 게 원칙입니다(`session2-local-execution-checklist.md` 참고 — 이 파일은 강사용).

---

## 다음에 더 볼 것

- 하이브리드 검색(키워드+벡터 동시): [공식 문서](https://docs.opensearch.org/latest/vector-search/ai-search/hybrid-search/index/)
- Plan-Execute-Reflect Agent(복잡한 다단계 조사): [공식 문서](https://docs.opensearch.org/latest/ml-commons-plugin/agents-tools/agents/plan-execute-reflect/)
- 이 레포의 실제 설정값 근거: [CONFIGURATION.md](CONFIGURATION.md)
- 실행 방법: [EXECUTION-GUIDE.md](EXECUTION-GUIDE.md)
