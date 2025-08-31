# 배포 가이드 (Cloud Run, WIF + GCS 비공개)

이 문서는 GitHub Actions + Workload Identity Federation(WIF)로 비밀키 없이 Cloud Run에 배포하고, 모델은 비공개 GCS에서 Cloud Build가 직접 복사해 사용하는 방법을 정리합니다.

## 요약

- 모델 tar.gz는 비공개 GCS 객체로 보관(예: `gs://<버킷>/models/kcbert_model.tar.gz`).
- GitHub Actions가 WIF로 GCP 인증 → Cloud Build 실행 → 빌드 첫 단계에서 GCS에서 tar.gz 복사 → Docker가 로컬 tar.gz를 이미지에 포함.
- Cloud Run은 `--min-instances 0` 등 무료 지향 설정.

---

## 선행 준비

- 프로젝트: `<PROJECT_ID>`
- 리전: `us-west1`(예시, 일관되게 사용 권장)
- Artifact Registry 리포지토리: `toxic-filter`(이 워크플로우에서 자동 생성)
- 서비스 이름(Cloud Run): `toxic-filter`
- 모델 tar.gz 업로드: `gsutil cp kcbert_model.tar.gz gs://<버킷>/models/`

## 버킷/객체 접근 권한

- Cloud Build가 모델을 읽을 수 있도록, Cloud Build 실행 계정(일반적으로 `PROJECT_NUMBER@cloudbuild.gserviceaccount.com`) 또는 빌드에 사용되는 SA에 최소 `roles/storage.objectViewer`를 버킷에 부여하세요.
  - 버킷 단위 바인딩 예시:

    ```bash
    gcloud storage buckets add-iam-policy-binding gs://<버킷> \
      --member=serviceAccount:PROJECT_NUMBER@cloudbuild.gserviceaccount.com \
      --role=roles/storage.objectViewer
    ```

---

## [1] GitHub Actions(WIF) 설정

1. 배포용 SA 생성(없으면):

   ```bash
   gcloud iam service-accounts create ci-deployer --display-name="CI Deployer"
   ```

2. WIF 설정 스크립트 실행(OWNER/REPO 교체):

   ```bash
   PROJECT_ID=<PROJECT_ID> \
   SERVICE_ACCOUNT=<SA_EMAIL> \
   REPO=<GITHUB_OWNER>/<GITHUB_REPO> \
   bash scripts/setup_wif_github_oidc.sh
   ```

3. GitHub Secrets 등록:
   - `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `GCP_PROJECT_ID`
   - (선택) `MODEL_GCS_URI` 또는 `MODEL_GCS_BUCKET`/`MODEL_GCS_PREFIX`, `MODEL_TARBALL_URL`, `API_KEY`

4. 서비스 계정 권한(IAM) 권장 셋업:
   - 대상 SA에 GitHub OIDC 주체에 대한 `roles/iam.workloadIdentityUser` 바인딩
   - 프로젝트 레벨: `roles/run.developer`, `roles/artifactregistry.admin`, `roles/cloudbuild.builds.editor`, `roles/serviceusage.serviceUsageConsumer`
   - 모델 버킷 읽기: `roles/storage.objectViewer`(버킷 레벨)
   - 기본 Cloud Build 소스 버킷(`<PROJECT>_cloudbuild`) 쓰기 필요 시: 해당 버킷에 `roles/storage.objectAdmin`

---

## [2] Actions로 배포 실행

1. GitHub → Actions → “Build and Deploy to Cloud Run” → “Run workflow”
2. inputs:
   - `image_tag`: 예 `v1`
   - `model_gcs_uri`: 예 `gs://<버킷>/models/kcbert_model.tar.gz`
3. 워크플로우는 자동으로 Cloud Build에 다음 단계를 수행합니다:
   - `gsutil cp <model_gcs_uri> kcbert_model.tar.gz`
   - `docker build -f Dockerfile -t <IMAGE_URI> .` (Dockerfile이 로컬 tar.gz를 ADD/추출)
   - Cloud Run에 배포(무료 지향 플래그)

참고: 조직 정책/VPC-SC로 Cloud Build 로그 스트리밍이 제한될 수 있습니다. 본 워크플로우는 `--async` 제출 후 `gcloud builds describe`로 상태를 폴링하여 로그 스트리밍 없이 성공/실패를 판별합니다(콘솔 링크 출력).

---

## [3] 수동 배포(옵션)

스크립트 없이 gcloud만으로 배포하려면 아래 명령을 사용하세요.

1. 변수 설정(필요에 맞게 수정)

```bash
PROJECT_ID=<PROJECT_ID>
REGION=us-west1
REPO=toxic-filter
SERVICE_NAME=toxic-filter
IMAGE_TAG=v1
MODEL_GCS_URI=gs://<버킷>/models/kcbert_model.tar.gz
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${SERVICE_NAME}:${IMAGE_TAG}"
```

2. Artifact Registry 리포지토리 준비(최초 1회)

```bash
gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1 || \
gcloud artifacts repositories create "$REPO" --repository-format=docker --location "$REGION"
```

3. Cloud Build로 이미지 빌드/푸시(GCS → 로컬 tar.gz → Dockerfile)

```bash
gcloud builds submit --config - . <<EOF
steps:
- name: 'gcr.io/cloud-builders/gsutil'
  args: ['cp','${MODEL_GCS_URI}','kcbert_model.tar.gz']
- name: 'gcr.io/cloud-builders/docker'
  args: ['build','-f','Dockerfile','-t','${IMAGE_URI}','.']
images: ['${IMAGE_URI}']
EOF
```

4. Cloud Run 배포(무료 지향 설정)

```bash
gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE_URI" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --cpu 1 --memory 2Gi \
  --concurrency 80 --timeout 120 \
  --min-instances 0 --max-instances 3 \
  --port 9090 \
  --set-env-vars API_KEY=,CORS_ORIGINS=,MALICIOUS_THRESHOLD_CERTAIN=0.999,MALICIOUS_THRESHOLD_AMBIGUOUS=0.9

참고: Cloud Run은 `PORT` 환경변수를 예약해 서비스가 리스닝해야 할 포트를 컨테이너에 주입합니다. `PORT`를 `--set-env-vars`로 설정하면 배포가 실패합니다. 컨테이너는 `$PORT`에 바인드하거나, 서비스 수준의 `--port` 플래그로 컨테이너 포트를 지정하세요.
```

---

## [4] 확인/테스트

서비스 URL 확인:

```bash
gcloud run services describe toxic-filter --region us-west1 --format='value(status.url)'
```

스모크 테스트:

```bash
BASE_URL=https://<service-url> [API_KEY=...] bash scripts/smoke_test.sh
```

---

## [5] 운영 팁

- 무료 지향: `--min-instances 0`, `--max-instances 1` 유지(콜드스타트 감수)
- CORS 제한: `CORS_ORIGINS` 환경변수로 필요한 오리진만 허용
- 임계치 튜닝: `MALICIOUS_THRESHOLD_CERTAIN/AMBIGUOUS`
- 모니터링: `monitoring/cloud_run_dashboard.json`로 대시보드 적용
