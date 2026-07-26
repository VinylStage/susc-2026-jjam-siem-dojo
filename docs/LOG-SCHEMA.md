# LOG SCHEMA — 수집되는 로그 필드 전체 설명

이 레포가 인덱싱하는 데이터가 정확히 무엇인지, 각 필드가 뭘 의미하는지 설명합니다. 원본 데이터셋은 HuggingFace [`darkknight25/Advanced_SIEM_Dataset`](https://huggingface.co/datasets/darkknight25/Advanced_SIEM_Dataset)이고, `opensearch-siem-toolkit`의 `siem-download`(원본 다운로드) → `siem-vary`(타임스탬프/IP/유저 값 변형, `VARIATIONS`/`WINDOW_SECONDS` 옵션)를 거쳐 `jjam-siem-logs` 인덱스로 들어갑니다. 이 레포의 실제 매핑은 [`requests/mappings/jjam-siem-logs-mapping.json`](../requests/mappings/jjam-siem-logs-mapping.json)이 원본이므로, 이 문서와 다르면 그 파일이 우선입니다.

## 개요

- 원본 10만 건, CEF(Common Event Format) 스타일 로그 기반, MIT 라이선스
- **8개 이벤트 카테고리**를 아우르는 게 이 데이터셋의 핵심 특징 — 전통적인 네트워크/엔드포인트 로그뿐 아니라 **AI 시스템 공격 로그(`event_type: ai`)까지 포함**되어 있어서, "보안관제 AI" 강의 취지와 잘 맞습니다: `endpoint`, `network`, `firewall`, `ids_alert`, `cloud`, `iot`, `auth`, `ai`
- 원본 타임스탬프 범위는 2020~2030년이지만, `siem-vary --window`가 실행 시점(`now`) 기준 최근 N초(기본 86400=24시간)로 슬라이딩하므로 실제로 인덱스에 들어가는 값은 "배포한 시점 기준 최근 하루" 안입니다.

## 공통 필드 (거의 모든 이벤트에 존재)

| 필드 | 타입 | 의미 | 값 예시 |
|---|---|---|---|
| `event_id` | keyword | 이벤트 고유 ID | UUID (`8e785e09-5213-...`) |
| `timestamp` | date (`yyyy-MM-dd HH:mm:ss`) | 이벤트 발생 시각 | `siem-vary` 변형 후 최근 24시간 내, 예: `2026-07-25 10:45:52` (ISO `T` 구분자 아님 — 실제 데이터 실측 확인, 매핑의 `format`과 일치) |
| `event_type` | keyword | 이벤트 대분류 | `endpoint`/`network`/`firewall`/`ids_alert`/`cloud`/`iot`/`auth`/`ai` |
| `source` | keyword | 이 이벤트를 만들어낸(탐지한) 가상의 SIEM/보안 도구 — 실측 결과 `벤더명 vX.X.X` 형태로 버전까지 포함된 문자열 | `CrowdStrike v6.45.0`, `Splunk v9.0.2`, `Wazuh v4.5.0`, `QRadar v7.5.0`, `Suricata v6.0.10`, `Snort v2.9.20` 등 정확히 20종 (실측 확인) |
| `severity` | keyword | 심각도 | `critical`/`high`/`medium`/`low`/`info` |
| `raw_log` | text | CEF 형식 원본 로그 문자열 | `CEF:0|벤더|SIEM|1.0|100|이벤트타입|심각도|상세...` |
| `user` | keyword (nullable) | 관련 사용자명 | `deannataylor` 등, 없을 수 있음 |
| `action` | keyword | 이 이벤트를 유발한 구체적 동작 | 아래 §"action 값" 참고 (약 55종) |
| `object` | keyword (nullable) | 대상 리소스/파일 | 파일 경로(`/I/fear.ppt`), 장치명, 또는 없음 |
| `additional_info` | text | 부가 설명 | "No additional info" 또는 MITRE ATT&CK 기법/위협 행위자 참조 |
| `description` | text (+`description.keyword`) | 사람이 읽는 이벤트 요약 — **벡터 검색(§Session2)의 임베딩 대상** | 여러 필드를 조합한 서술형 문장 |
| `advanced_metadata.risk_score` | float | 위험도 점수 | 대략 9~97 범위 |
| `advanced_metadata.confidence` | float | 판단 신뢰도 | 0.0~1.0 |
| `advanced_metadata.geo_location` | keyword | 지리적 위치 | 국가/지역 코드 등 |
| `behavioral_analytics.baseline_deviation` | float (nullable) | 평소 패턴 대비 편차 | — |
| `behavioral_analytics.entropy` | float (nullable) | 엔트로피(무작위성) 지표 | — |
| `behavioral_analytics.frequency_anomaly` | boolean (nullable) | 빈도 이상 여부 | true/false |
| `behavioral_analytics.sequence_anomaly` | boolean (nullable) | 순서 이상 여부 | true/false |

**참고**: 원본 데이터셋의 `advanced_metadata` 객체는 실제로 `device_hash`/`user_agent`/`session_id` 서브필드도 갖고 있는데(실측 확인), 이 레포의 매핑은 `risk_score`/`confidence`/`geo_location` 세 개만 명시적으로 정의합니다. 나머지는 들어오면 OpenSearch 동적 매핑으로 자동 처리되지만(에러는 안 남), 타입이 보장되지 않으므로 집계/정렬 용도로는 명시적으로 매핑을 추가하는 게 안전합니다(이 레포는 강의 범위상 안 씀).

## 이벤트 타입별 전용 필드

`event_type` 값에 따라 아래 필드들이 채워집니다. **주의: 관련 없는 문서에서 이 필드들이 아예 빠지는 게 아니라, JSON `null` 값으로 명시적으로 채워져 있습니다** (실측 확인 — 예: `event_type: iot` 문서에도 `src_ip`/`alert_type`/`model_id` 등 다른 카테고리 필드가 전부 `null` 키로 존재). 그래서 고정 매핑을 써도 동적 매핑 충돌이 안 나는 것:

| `event_type` | 전용 필드 |
|---|---|
| `endpoint` | `process_id`(정수), `parent_process`(예: `explorer.exe`), `object`(파일 경로) |
| `network` / `firewall` | `src_ip`, `dst_ip`(IPv4), `src_port`, `dst_port`, `protocol`(TCP/UDP/HTTP/HTTPS/SSH), `bytes`, `duration`(초) |
| `ids_alert` | `alert_type`(예: Credential Stuffing, Fileless Attack, Container Escape, DNS Tunneling, AI Model Poisoning 등 17종), `signature_id`(`SIG-####`), `category`(Exploit/Recon/Policy/Malware) |
| `cloud` | `cloud_service`(GCP/AWS/OCI), `resource_id`(`res-xxxxxxxx`) |
| `iot` | `device_type`(HVAC/Thermostat/Medical/Sensor), `device_id`(`iot-xxxxxxxx`), `firmware_version`, `mac_address` |
| `auth` | `method`(password/key) |
| `ai` | `model_id`(`model-xxxxxxxx`), `input_hash`, `output_hash`(SHA256/MD5) — 모델 입출력에 대한 해시. `action`이 `model_inversion`/`adversarial_input`/`prompt_injection`/`fine_tuning`/`api_abuse` 등일 때 이 카테고리 |

**⚠️ 참고 (실측 완료, 2026-07-26)**: 원본 HuggingFace 데이터셋 카드에는 `dst_ip`가 IPv4 값 또는 문자열 `"N/A"`를 가질 수 있다고 되어 있어, 이 레포 매핑(`dst_ip: type: ip`)과 충돌해 인덱싱 에러가 날 위험이 있다고 봤습니다. 실제로 `toolkit/siem_data/variations/advanced_siem/*.ndjson`(5개 variation 파일, 총 100만 건)을 전수 `grep`해본 결과 `dst_ip`에 `"N/A"` 값은 **0건** — `siem-vary`가 변형하는 과정에서 `dst_ip`를 사설 IP(`10.0.x.x` 등) 아니면 `null`로만 채우고, 문자열 `"N/A"`는 생성하지 않는 것으로 확인됩니다. 즉 이 레포 기준으로는 실질적인 인덱싱 리스크 없음. 다만 데이터셋이 업데이트되거나 `siem-download`로 원본을 새로 받으면 재확인 권장 — `grep -c '"dst_ip": "N/A"' toolkit/siem_data/variations/advanced_siem/*.ndjson`로 즉시 재검증 가능합니다.

## `action` 값 (58종 중 예시)

카테고리를 넘나드는 값들이라 `event_type`과 조합해서 봐야 의미가 명확합니다:

- 엔드포인트/일반: `file_access`, `scheduled_task`, `unusual_activity`
- 네트워크: `connection`, `drop`, `deny`, `bandwidth_usage`, `covert_channel`
- 인증: `success`, `locked`, `timeout`
- IoT/사이드채널: `sensor_spoofing`, `side_channel`, `crypto_mining`
- 고급 공격기법: `container_escape`
- **AI 전용**: `model_inversion`, `adversarial_input`, `prompt_injection`, `fine_tuning`, `api_abuse`

전체 목록은 `curl -s "http://localhost:9200/jjam-siem-logs/_search" -d '{"size":0,"aggs":{"actions":{"terms":{"field":"action","size":100}}}}' | jq '.aggregations.actions.buckets[].key'`로 직접 뽑아보는 게 가장 정확합니다.

## 실제 문서 예시

```json
{
  "event_id": "8e785e09-5213-46b1-a6eb-b7e40998905b",
  "timestamp": "2026-07-25 10:45:52",
  "event_type": "endpoint",
  "source": "Microsoft Sentinel v1.0.0",
  "severity": "critical",
  "raw_log": "CEF:0|Microsoft Sentinel v1.0.0|SIEM|1.0|100|endpoint|critical| desc=Endpoint file_access /I/fear.ppt by deannataylor No additional info",
  "advanced_metadata": {
    "geo_location": "Isle of Man",
    "device_hash": "d8595a4fb801a5ac7fcfe0987f50b16af71d52b2",
    "user_agent": "Mozilla/5.0 (compatible; MSIE 8.0; Windows NT 5.01; Trident/5.0)",
    "session_id": "c1a4c54e-e3c9-459f-88af-afb52bd1f220",
    "risk_score": 61.04,
    "confidence": 0.33
  },
  "user": "user_0001",
  "action": "file_access",
  "object": "/I/fear.ppt",
  "process_id": 8141,
  "parent_process": "explorer.exe",
  "additional_info": "No additional info",
  "description": "Endpoint file_access /I/fear.ppt by deannataylor No additional info",
  "behavioral_analytics": {
    "baseline_deviation": 1.84,
    "entropy": 3.6,
    "frequency_anomaly": false,
    "sequence_anomaly": false
  },
  "device_type": null, "device_id": null, "firmware_version": null,
  "src_ip": null, "dst_ip": null,
  "alert_type": null, "signature_id": null, "category": null,
  "cloud_service": null, "resource_id": null,
  "model_id": null, "input_hash": null, "output_hash": null,
  "src_port": null, "dst_port": null, "protocol": null, "bytes": null, "duration": null,
  "method": null, "mac_address": null
}
```
(2026-07-26 기준 `toolkit/siem_data/variations/advanced_siem/advanced_siem_v1.ndjson`의 실제 첫 문서 — 가공 없이 그대로. `event_type: endpoint`가 아닌 카테고리 전용 필드는 전부 `null`로 채워져 있는 걸 확인할 수 있습니다.)

## 참고 문서

- 매핑 원본: [`requests/mappings/jjam-siem-logs-mapping.json`](../requests/mappings/jjam-siem-logs-mapping.json)
- 벡터 인덱스(`description` → `description_embedding`) 매핑: [`requests/mappings/jjam-siem-vector-mapping.json`](../requests/mappings/jjam-siem-vector-mapping.json)
- 필드 중첩 구조(`advanced_metadata.risk_score` 등)를 왜 그대로 쓰는지: [CONFIGURATION.md](CONFIGURATION.md), [STUDY-GUIDE.md](STUDY-GUIDE.md) §1-6
- 데이터셋 카드(공식): [huggingface.co/datasets/darkknight25/Advanced_SIEM_Dataset](https://huggingface.co/datasets/darkknight25/Advanced_SIEM_Dataset)
