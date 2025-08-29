#!/usr/bin/env bash
set -euo pipefail

# Setup Workload Identity Federation (OIDC) for GitHub Actions -> GCP
# This script creates a Workload Identity Pool + Provider and binds a
# service account so GitHub Actions in a specific repo can impersonate it.
#
# Required env vars:
#   PROJECT_ID           GCP project ID
#   SERVICE_ACCOUNT      Service account email (e.g. ci-deployer@PROJECT_ID.iam.gserviceaccount.com)
#   REPO                 GitHub repo in the form OWNER/REPO (e.g. team/hongbookstore)
# Optional env vars:
#   POOL_ID              (default: github-oidc)
#   PROVIDER_ID          (default: github)
#   POOL_DISPLAY_NAME    (default: GitHub OIDC Pool)
#   PROVIDER_DISPLAY_NAME(default: GitHub OIDC Provider)

PROJECT_ID=${PROJECT_ID:-}
SERVICE_ACCOUNT=${SERVICE_ACCOUNT:-}
REPO=${REPO:-}

POOL_ID=${POOL_ID:-github-oidc}
PROVIDER_ID=${PROVIDER_ID:-github}
POOL_DISPLAY_NAME=${POOL_DISPLAY_NAME:-"GitHub OIDC Pool"}
PROVIDER_DISPLAY_NAME=${PROVIDER_DISPLAY_NAME:-"GitHub OIDC Provider"}

if [[ -z "${PROJECT_ID}" || -z "${SERVICE_ACCOUNT}" || -z "${REPO}" ]]; then
  echo "ERROR: Set PROJECT_ID, SERVICE_ACCOUNT, and REPO (OWNER/REPO)." >&2
  exit 1
fi

echo "Setting up WIF for project=${PROJECT_ID}, repo=${REPO}, sa=${SERVICE_ACCOUNT}"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# Create pool if not exists
if ! gcloud iam workload-identity-pools describe "$POOL_ID" --project="$PROJECT_ID" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT_ID" \
    --location=global \
    --display-name="$POOL_DISPLAY_NAME"
else
  echo "Workload Identity Pool '$POOL_ID' already exists. Skipping."
fi

# Create provider if not exists
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" --location=global --workload-identity-pool="$POOL_ID" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --project="$PROJECT_ID" \
    --location=global \
    --workload-identity-pool="$POOL_ID" \
    --display-name="$PROVIDER_DISPLAY_NAME" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor,attribute.aud=assertion.aud" \
    --attribute-condition="assertion.repository == '${REPO}'"
else
  echo "Provider '$PROVIDER_ID' already exists. Skipping."
fi

PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

# Allow GitHub repo to impersonate the service account via principalSet
gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO}"

echo "Granting deployment roles to service account (Cloud Run, Cloud Build, Artifact Registry)"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/cloudbuild.builds.editor"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/artifactregistry.writer"

echo "\nSuccess! Configure these GitHub secrets:"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: ${PROVIDER_RESOURCE}"
echo "  GCP_SERVICE_ACCOUNT: ${SERVICE_ACCOUNT}"
echo "Optionally set SLANG_API_KEY to inject API_KEY env into Cloud Run."

