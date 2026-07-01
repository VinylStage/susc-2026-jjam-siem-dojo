# Option B: Ollama 로컬 (고사양 대안)

## 대상

API 비용 없이 완전 오프라인으로 실습하고 싶거나, 16GB 이상 RAM을 가진 수강생 대상 옵션입니다.

## 모델 선택에 대한 정정

기존 강사 검증 환경(MacBook M4 48GB)에서는 `qwen2.5:32b`를 사용했지만, 이 값을 그대로 학생 기본값으로 두면 16GB 서버에서는 사실상 구동 불가능합니다(Q4 양자화 기준 32B 모델은 최소 20GB+ 필요). 이 레포의 기본값은 `qwen2.5:7b`(약 4~5GB)로 낮춰뒀습니다. RAM 여유가 있다면 `.env`의 `OLLAMA_MODEL`을 `qwen2.5:32b` 등으로 올려 쓰세요.

| RAM | 권장 모델 |
|---|---|
| 16GB | `qwen2.5:7b` (기본값) |
| 32GB+ | `qwen2.5:14b` |
| 48GB+ | `qwen2.5:32b` (강사 검증 환경) |

## 준비

```
LLM_OPTION=b
OLLAMA_MODEL=qwen2.5:7b
```

## 실행

```bash
docker compose --profile ollama up -d
docker exec jjam-ollama ollama pull qwen2.5:7b

bash scripts/05-register-llm-connector.sh --option b
bash scripts/06-register-agents.sh --option b
```

`scripts/00-setup.sh`는 `LLM_OPTION=b`일 때 자동으로 `--profile ollama`를 붙여 컨테이너를 띄우지만, 모델 pull은 최초 1회 수동으로 실행해야 합니다(위 `docker exec` 명령).

## Connector 구조

`requests/connectors/ollama-connector.json`은 `http://ollama:11434/v1/chat/completions`(OpenAI 호환 엔드포인트)를 호출합니다. 단일 서버 배포이므로 컨테이너 간 통신은 Docker Compose 네트워크의 서비스명(`ollama`)으로 이뤄집니다 — 별도 IP 설정 불필요.

## 연결 테스트

```bash
docker exec jjam-ollama ollama list
curl http://localhost:11434/api/tags
```

## 트러블슈팅

- 최초 모델 pull 전에 Connector를 등록하면 `_predict` 호출이 타임아웃됩니다 — pull 완료 후 진행하세요.
- 응답이 느리면(30초+) 더 작은 모델(`qwen2.5:7b` → `llama3.2:3b`)로 교체 고려.
