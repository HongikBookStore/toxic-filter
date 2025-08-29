#!/usr/bin/env bash
set -euo pipefail

# Package local model, upload to GCS, and print a signed URL.
# Requirements: gcloud, gsutil, and a service account with storage admin or writer.
#
# Usage:
#   BUCKET=my-bucket REGION=asia-northeast3 DURATION=1h bash scripts/gcs_model_publish.sh
# Optional:
#   MODEL_DIR=kcbert_slang_filter_model OUTPUT=kcbert_slang_filter_model.tar.gz KEY_JSON=key.json
#

MODEL_DIR=${MODEL_DIR:-kcbert_slang_filter_model}
OUTPUT=${OUTPUT:-kcbert_slang_filter_model.tar.gz}
BUCKET=${BUCKET:-}
REGION=${REGION:-asia-northeast3}
DURATION=${DURATION:-1h}
KEY_JSON=${KEY_JSON:-key.json}

if [[ -z "$BUCKET" ]]; then
  echo "ERROR: Set BUCKET env var (GCS bucket name)." >&2
  exit 1
fi

if [[ ! -d "$MODEL_DIR" ]]; then
  echo "ERROR: Model directory '$MODEL_DIR' not found." >&2
  exit 1
fi

echo "[1/4] Ensure bucket gs://$BUCKET exists (region=$REGION)"
gsutil ls -b "gs://$BUCKET" >/dev/null 2>&1 || gsutil mb -l "$REGION" "gs://$BUCKET"

echo "[2/4] Package model -> $OUTPUT"
tar -czf "$OUTPUT" -C . "$MODEL_DIR"

DEST="gs://$BUCKET/models/$OUTPUT"
echo "[3/4] Upload to $DEST"
gsutil cp "$OUTPUT" "$DEST"

echo "[4/4] Generate signed URL (duration=$DURATION)"
SIGNED_URL=$(gsutil signurl -d "$DURATION" "$KEY_JSON" "$DEST" | awk 'NR==2{print $5}')

echo
echo "MODEL_TARBALL_URL=$SIGNED_URL"
echo "Use this URL in Cloud Build or GitHub Actions input (model_tarball_url)."
echo

