# Option C: Claude API (강사 검증용, 신규 추가)

## 목적

OpenAI 크레딧이 없는 상황에서 강사가 직접 파이프라인을 검증하기 위해 추가된 옵션입니다. 수강생 기본 권장은 아니며, Option A(OpenAI)가 검증 완료되면 그쪽이 계속 기본입니다.

## API 스펙 (2026-07 기준)

| 항목 | 값 |
|---|---|
| 엔드포인트 | `POST https://api.anthropic.com/v1/messages` |
| 인증 헤더 | `x-api-key` (OpenAI/Ollama의 `Authorization: Bearer`와 다름) |
| 필수 헤더 | `anthropic-version: 2023-06-01` |
| 응답 구조 | `content[0].text` (OpenAI의 `choices[0].message.content`와 다름) |
| 모델명 | `claude-sonnet-5` |

`requests/connectors/claude-connector.json`의 모델명은 원래 HANDOFF 문서에 `claude-sonnet-4-6`으로 기재되어 있었으나, 실제 존재하지 않는 모델명이라 웹 검색으로 재확인한 `claude-sonnet-5`로 정정했습니다.

## 준비

1. https://console.anthropic.com 에서 API 키 발급
2. 소액 크레딧 확인 (사용량 기반 과금)
3. `.env`에 설정

```
LLM_OPTION=c
ANTHROPIC_API_KEY=sk-ant-...
```

## 실행

```bash
bash scripts/05-register-llm-connector.sh --option c
bash scripts/06-register-agents.sh --option c
```

`scripts/05-register-llm-connector.sh`는 옵션 `c`일 때 `response_filter`를 자동으로 `$.content[0].text`로 설정합니다(Option A/B의 `$.choices[0].message.content`와 다름).

## 연결 테스트

```bash
source .env
AUTH="admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
LLM_MODEL_ID=$(jq -r '.llm_model_id' ids.json)

curl -sk -u "$AUTH" -X POST "https://localhost:9200/_plugins/_ml/models/$LLM_MODEL_ID/_predict" \
  -H "Content-Type: application/json" \
  -d '{"parameters": {"prompt": "Reply with OK if you can read this."}}' | jq .
```

## 남은 오픈 이슈

- `system` 프롬프트를 별도 필드로 분리할지 여부는 미결정 — 현재는 Option A/B와 동일하게 `messages[0].content`에 통째로 넣는 방식으로 통일. Agent 응답 품질에 문제가 있으면 `system` 필드 분리 리팩토링 필요.
- 강사가 실제 테스트 완료 후 이 문서에 실측 응답시간/품질을 기록할 것.
