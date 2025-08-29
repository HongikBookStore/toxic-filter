#!/usr/bin/env bash
set -euo pipefail

# Quick Cloud Run deploy script for slang-filter API
# Usage:
#   PROJECT_ID=your-project REGION=asia-northeast3 bash scripts/deploy_cloud_run.sh
# Optional overrides:
#   SERVICE_NAME, REPO, IMAGE_TAG, API_KEY

PROJECT_ID=${PROJECT_ID:-}
REGION=${REGION:-}
SERVICE_NAME=${SERVICE_NAME:-slang-filter}
REPO=${REPO:-slang}
IMAGE_TAG=${IMAGE_TAG:-v1}
MODEL_TARBALL_URL=${MODEL_TARBALL_URL:-}
API_KEY=${API_KEY:-}

if [[ -z "${PROJECT_ID}" || -z "${REGION}" ]]; then
  echo "ERROR: Set PROJECT_ID and REGION env vars."
  exit 1
fi

set -x

gcloud config set project "${PROJECT_ID}"

# Enable required services
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com --quiet

# Create Artifact Registry repo if it doesn't exist
gcloud artifacts repositories describe "${REPO}" --location "${REGION}" >/dev/null 2>&1 || \
gcloud artifacts repositories create "${REPO}" --repository-format=docker --location "${REGION}" --quiet

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${SERVICE_NAME}:${IMAGE_TAG}"

# Build + push with Cloud Build (remote model required)
if [[ -z "${MODEL_TARBALL_URL}" ]]; then
  echo "ERROR: MODEL_TARBALL_URL is required for remote model build."
  exit 2
fi

gcloud builds submit --tag "${IMAGE_URI}" --quiet \
  --config=- <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-f', 'Dockerfile', '--build-arg', 'MODEL_TARBALL_URL=${MODEL_TARBALL_URL}', '-t', '${IMAGE_URI}', '.' ]
images: ['${IMAGE_URI}']
EOF

# Base deploy flags (free-tier leaning: min 0, max 1, 2GiB, 1 CPU)
COMMON_FLAGS=(
  --image "${IMAGE_URI}"
  --region "${REGION}"
  --platform managed
  --allow-unauthenticated
  --cpu 1
  --memory 2Gi
  --concurrency 1
  --timeout 120
  --min-instances 0
  --max-instances 1
)

if [[ -n "${API_KEY}" ]]; then
  gcloud run deploy "${SERVICE_NAME}" "${COMMON_FLAGS[@]}" --set-env-vars API_KEY="${API_KEY}" --quiet
else
  gcloud run deploy "${SERVICE_NAME}" "${COMMON_FLAGS[@]}" --quiet
fi

echo "Deployed service: ${SERVICE_NAME}"
gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)'

set +x
echo "Tip: test with curl"
echo "  curl -sS \"
$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)')/health\""
echo "  curl -sS -X POST -H 'Content-Type: application/json' ${API_KEY:+-H 'X-API-Key: '"${API_KEY}"} \\
    -d '{"text":"예시 문장"}' \"$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)')/predict\" | jq ."
