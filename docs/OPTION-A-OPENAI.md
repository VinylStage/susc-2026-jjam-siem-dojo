# Option A: OpenAI API (학생 기본 권장)

## 왜 기본 권장인가

RAM 8GB로 전체 파이프라인(임베딩+LLM+Agent+이상탐지)을 GPU 없이 실습할 수 있는 유일한 옵션입니다. Ollama(Option B)는 16GB+ 필요, Claude API(Option C)는 강사 검증용입니다.

## 준비

1. https://platform.openai.com 에서 API 키 발급
2. 결제 수단 등록 + 소액 크레딧 확인 (`gpt-4o-mini` 기준 실습 1회당 비용은 매우 낮음, 수십~수백 원 수준)
3. `.env`에 설정

```
LLM_OPTION=a
OPENAI_API_KEY=sk-...
```

## 실행

```bash
bash scripts/05-register-llm-connector.sh --option a
bash scripts/06-register-agents.sh --option a
```

또는 `scripts/00-setup.sh` 전체 실행 시 `.env`의 `LLM_OPTION=a`만 맞춰두면 자동으로 이 경로를 탑니다.

## 사용 모델

`gpt-4o-mini` — 비용 대비 품질이 좋아 실습용으로 적합. 필요 시 `requests/connectors/openai-connector.json`의 `parameters.model` 값을 변경해 다른 모델로 교체 가능(비용 상승 유의).

## 연결 테스트

```bash
source .env
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
LLM_MODEL_ID=$(jq -r '.llm_model_id' ids.json)

curl -sk -u "$AUTH" -X POST "https://localhost:9200/_plugins/_ml/models/$LLM_MODEL_ID/_predict" \
  -H "Content-Type: application/json" \
  -d '{"parameters": {"prompt": "Briefly explain what a DDoS attack is."}}' | jq .
```

## 검증 상태

이 옵션은 아직 강사 계정에 OpenAI 크레딧이 없어 실측 테스트가 완료되지 않았습니다(문서화만 완료, 미검증). 강의 전 반드시 직접 실행해 응답 확인 필요.

## 트러블슈팅

- `trusted_connector_endpoints_regex` 미등록 시 Connector 호출이 차단됩니다 — `scripts/01-wait-for-opensearch.sh`가 자동 등록하므로 순서를 건너뛰지 마세요.
- 401 에러: API 키 오타 또는 결제 수단 미등록 여부 확인.
