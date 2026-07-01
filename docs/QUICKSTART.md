# QUICKSTART

## 1. 준비물 확인

```bash
docker --version
docker compose version
poetry --version
jq --version
```

## 2. 환경변수 설정

```bash
cp .env.example .env
```

`.env`를 열어 아래 값을 채웁니다.

| 변수 | 설명 |
|---|---|
| `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | OpenSearch 3.x 보안 플러그인 admin 계정 비밀번호 (대문자/숫자/특수문자 포함 8자 이상) |
| `LLM_OPTION` | `a`(OpenAI, 기본) / `b`(Ollama) / `c`(Claude API) |
| `OPENAI_API_KEY` | Option A 사용 시 |
| `ANTHROPIC_API_KEY` | Option C 사용 시 |
| `OLLAMA_MODEL` | Option B 사용 시, 기본 `qwen2.5:7b` |
| `VARIATIONS` | 생성할 데이터 베리에이션 수 (수강생 규모에 따라 조정, 기본 5) |
| `WINDOW_SECONDS` | 타임스탬프 슬라이딩 범위(초), 기본 86400(24시간) |

옵션별 상세 설정은 [OPTION-A-OPENAI.md](OPTION-A-OPENAI.md), [OPTION-B-OLLAMA.md](OPTION-B-OLLAMA.md), [OPTION-C-CLAUDE.md](OPTION-C-CLAUDE.md) 참고.

## 3. 전체 파이프라인 실행

```bash
bash scripts/00-setup.sh
```

내부적으로 아래 순서가 자동 실행됩니다.

1. `opensearch-siem-toolkit` clone
2. 컨테이너 기동 (Option B는 `--profile ollama`)
3. OpenSearch 헬스체크 + `trusted_connector_endpoints_regex` 등록
4. `jjam-siem-logs` 매핑 생성 → `siem-download` → `siem-vary` → bulk 인제스트
5. 임베딩 모델 등록/배포
6. `jjam-siem-vector` 생성 + reindex (테스트 1만건)
7. LLM Connector 등록 (옵션별) + 모델 배포
8. RAG/Conversational Agent 등록
9. Anomaly Detector 2종 등록 + Historical Analysis 시작

첫 실행 시 `siem-download`가 전체 데이터셋(advanced_siem 포함 12종)을 내려받기 때문에 10~20분 정도 걸립니다. 이후 재실행 시 캐시된 파일은 자동으로 스킵됩니다.

## 4. 접속 확인

- Dashboards: http://localhost:5601 (admin / `.env`에 설정한 비밀번호)
- OpenSearch API: https://localhost:9200 (자체 서명 인증서 사용 — `curl -k`)

## 5. 동작 확인 쿼리

```bash
source .env
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"

curl -sk -u "$AUTH" "https://localhost:9200/jjam-siem-logs/_count" | jq .

curl -sk -u "$AUTH" -X POST "https://localhost:9200/jjam-siem-logs/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": { "range": { "advanced_metadata.risk_score": { "gte": 80 } } },
    "sort": [{ "advanced_metadata.risk_score": "desc" }],
    "_source": ["timestamp", "event_type", "severity", "advanced_metadata"],
    "size": 5
  }' | jq .
```

Agent 테스트:

```bash
CONV_AGENT_ID=$(jq -r '.conversational_agent_id' ids.json)

curl -sk -u "$AUTH" -X POST "https://localhost:9200/_plugins/_ml/agents/$CONV_AGENT_ID/_execute" \
  -H "Content-Type: application/json" \
  -d '{ "parameters": { "question": "What are the top 5 most common alert types?" } }' | jq .
```

## 6. 강의 전날 밤 — 전체 재인덱싱

Session 1에서는 1만건 벡터 재인덱싱만 테스트로 돌아갑니다. 강의 전날 밤, 전체 10만건 재인덱싱을 미리 돌려놓으세요.

```bash
source .env
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"

curl -sk -u "$AUTH" -X POST "https://localhost:9200/_reindex?wait_for_completion=false" \
  -H "Content-Type: application/json" \
  -d '{ "source": { "index": "jjam-siem-logs" }, "dest": { "index": "jjam-siem-vector" } }'
```
