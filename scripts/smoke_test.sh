#!/usr/bin/env bash
set -euo pipefail

# Simple smoke test for the slang-filter API
# Usage: BASE_URL=https://<cloud-run-url> [API_KEY=...] bash scripts/smoke_test.sh

BASE_URL=${BASE_URL:-}
API_KEY=${API_KEY:-}

if [[ -z "${BASE_URL}" ]]; then
  echo "ERROR: Set BASE_URL to your service URL (e.g. https://slang-filter-xxxx.run.app)" >&2
  exit 1
fi

hdrs=("-H" "Content-Type: application/json")
if [[ -n "${API_KEY}" ]]; then
  hdrs+=("-H" "X-API-Key: ${API_KEY}")
fi

echo "[1/2] Health check: ${BASE_URL}/health"
curl -sS "${BASE_URL}/health" | jq . || true

echo "[2/2] Prediction checks"
declare -a tests=(
  "일안하는 시간은 쉬고싶어서 그런게 아닐까"
  "예수 십새끼 개새끼 창녀아들 애비실종 가정교육 못받은 무뇌충"
  "나이쳐먹고 피시방가는 놈들은 대가리에 똥만찬 놈들임"
  "원 리더십, 원 메시지로 내부 결속을 더 강화하고 다시 교회로 모일수 있기를"
  "협박스킬은 패시브랑께"
)

for t in "${tests[@]}"; do
  echo "----"
  echo "Text: ${t}"
  curl -sS -X POST "${BASE_URL}/predict" "${hdrs[@]}" \
    -d "$(jq -n --arg text "$t" '{text:$text}')" | jq .
done

echo "Done."

