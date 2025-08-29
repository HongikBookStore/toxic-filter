#!/usr/bin/env bash
set -euo pipefail

# 로컬 개발용: tar.gz를 다운로드/복사하여 kcbert_model 폴더로 압축 해제합니다.
# 우선순위: MODEL_GCS_URI(권장, 비공개 GCS) → MODEL_TARBALL_URL(https: 퍼블릭/서명 URL)
# 사용법 예시:
#   MODEL_GCS_URI=gs://bucket/models/kcbert_model.tar.gz bash scripts/fetch_model.sh
#   또는
#   MODEL_TARBALL_URL=https://.../kcbert_model.tar.gz bash scripts/fetch_model.sh

MODEL_GCS_URI=${MODEL_GCS_URI:-}
MODEL_TARBALL_URL=${MODEL_TARBALL_URL:-}
DEST_DIR=${DEST_DIR:-kcbert_model}

mkdir -p "$DEST_DIR"

TMP_TAR=/tmp/model.$$.$RANDOM.tar.gz

if [[ -n "$MODEL_GCS_URI" ]]; then
  echo "Fetching from GCS: $MODEL_GCS_URI"
  gcloud storage cp "$MODEL_GCS_URI" "$TMP_TAR" >/dev/null
elif [[ -n "$MODEL_TARBALL_URL" ]]; then
  echo "Fetching from URL: $MODEL_TARBALL_URL"
  curl -fSL "$MODEL_TARBALL_URL" -o "$TMP_TAR"
else
  echo "ERROR: Provide MODEL_GCS_URI or MODEL_TARBALL_URL." >&2
  exit 1
fi

tar -xzf "$TMP_TAR" -C .
rm -f "$TMP_TAR"

test -f "$DEST_DIR/config.json" || { echo "ERROR: Model not found at $DEST_DIR" >&2; exit 2; }
echo "Model extracted to $DEST_DIR"
