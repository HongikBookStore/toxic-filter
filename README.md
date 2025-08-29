# 비속어 탐지 API (KCBERT)

Flask + HuggingFace Transformers(토치)로 구현한 한글 비속어 탐지 API입니다. </br>
파인튜닝된 `beomi/kcbert-base` 모델을 사용하며, Google Cloud Run 무료 티어에서 동작하도록 경량화되어 있습니다.

## 주요 기능

- `POST /predict`: 문장 비속어 판정(확실/애매/아님)과 확률 반환
- `GET /health`: 상태/임계치/버전 확인
- 간단 API 키 인증(`X-API-Key`) 및 CORS 제어

## 디렉토리 구조

- `app.py`: API 서버(모델 로드/추론)
- `Dockerfile`: 원격 모델 다운로드 방식
- `scripts/`: 배포/스모크/WIF 스크립트
- `.github/workflows/deploy-cloud-run.yml`: Cloud Run 배포 워크플로우

## 빠른 시작(로컬)

```bash
# 1) 모델 내려받기(GCS 권장)
MODEL_GCS_URI=gs://hongbookstore-toxicfilter/models/kcbert_slang_filter_model.tar.gz bash scripts/fetch_model.sh

# 2) 가상환경 및 의존성 설치
python -m venv .venv && source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 3) 예제/서버 실행
python example_prediction.py    # 모델/토크나이저 로드 예시
python app.py                   # API 서버 실행 (기본 8080)

# 4) 테스트
curl -sS http://localhost:8080/health | jq .
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"text":"예시 문장"}' http://localhost:8080/predict | jq .
```

## API 사양

- `GET /health`
  - 응답: `{ status, model_ready, model_path, thresholds: {certain, ambiguous}, version }`
- `POST /predict`
  - 요청: `{"text":"문장"}` (빈 문자열/비문자열/2000자 초과 거부)
  - 응답: `{ text, prediction_level: "확실한 비속어|애매한 비속어|비속어 아님", probabilities: { malicious, clean } }`
  - 인증(선택): `API_KEY` 설정 시 `X-API-Key` 헤더 필요(401 반환)

## 환경변수

- `MODEL_PATH`(기본 `./kcbert_slang_filter_model`)
- `MALICIOUS_THRESHOLD_CERTAIN`(기본 `0.999`), `MALICIOUS_THRESHOLD_AMBIGUOUS`(기본 `0.9`)
- `API_KEY`(선택): 간단 키 인증 활성화
- `CORS_ORIGINS`(선택): `https://a.com,https://b.com` 형태. 미설정 시 전체 허용
- `TORCH_INTRA_OP_THREADS`, `TORCH_INTER_OP_THREADS`(선택): CPU 스레드 튜닝
- `RELEASE`(선택): /health 표시 버전 문자열

## 컨테이너 실행

```bash
docker build -t slang-filter:local --build-arg MODEL_TARBALL_URL=<signed-or-public-url> .
docker run --rm -p 8080:8080 slang-filter:local
```

## 배포(Cloud Run, 무료 티어)

권장 배포 흐름은 원격 모델 tar.gz를 GCS에 두고 `Dockerfile.remote`를 사용하는 방식입니다. 상세 절차와 GitHub Actions 자동 배포는 DEPLOYMENT.md를 참고하세요.

요약:

1) 모델 패키징/업로드/서명 URL 발급

```bash
BUCKET=<버킷> REGION=asia-northeast3 DURATION=1h \
  bash scripts/gcs_model_publish.sh
# 출력된 MODEL_TARBALL_URL 복사
```

2) GitHub Actions 실행 → inputs에 `model_tarball_url` 지정

3) Cloud Run URL로 `/health`, `/predict` 스모크 테스트

## Spring(WebClient) 연동 예시

```java
WebClient client = WebClient.builder()
    .baseUrl(System.getenv("SLANG_API_BASE"))
    .defaultHeader("X-API-Key", System.getenv("SLANG_API_KEY")) // 선택
    .build();

Mono<Map> resp = client.post()
    .uri("/predict")
    .contentType(MediaType.APPLICATION_JSON)
    .bodyValue(Map.of("text", content))
    .retrieve()
    .bodyToMono(Map.class);

Map result = resp.block(Duration.ofSeconds(60));
String level = (String) result.get("prediction_level");
```

권장 정책

- 확실한 비속어: 저장 차단 + 안내
- 애매한 비속어: 경고(서비스정책에 따라 처리)
- 비속어 아님: 통과

## 참고

- 스모크 테스트: `scripts/smoke_test.sh`
- 모델 tar.gz 발급: `scripts/gcs_model_publish.sh`
