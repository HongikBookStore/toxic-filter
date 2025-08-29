#!/usr/bin/env bash
set -euo pipefail

# Download and extract a model tar.gz into kcbert_slang_filter_model for local dev.
# Usage: MODEL_TARBALL_URL=<signed-or-public-url> bash scripts/fetch_model.sh

MODEL_TARBALL_URL=${MODEL_TARBALL_URL:-}
DEST_DIR=${DEST_DIR:-kcbert_slang_filter_model}

if [[ -z "$MODEL_TARBALL_URL" ]]; then
  echo "ERROR: Set MODEL_TARBALL_URL to a tar.gz URL." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
curl -fSL "$MODEL_TARBALL_URL" -o /tmp/model.tar.gz
tar -xzf /tmp/model.tar.gz -C .
rm -f /tmp/model.tar.gz

test -f "$DEST_DIR/config.json" || { echo "ERROR: Model not found at $DEST_DIR" >&2; exit 2; }
echo "Model extracted to $DEST_DIR"

