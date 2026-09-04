#!/usr/bin/env bash
# scripts/seed_r2_cache.sh: Seeds pre-built dependency closures into the binary cache in parallel
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CACHE_URL="${1:-s3://rustdesk-enve-cache}"
SIGNING_KEY="${ENVE_CACHE_SIGNING_KEY:-}"

if [[ -z "${SIGNING_KEY}" ]]; then
  echo "❌ Error: ENVE_CACHE_SIGNING_KEY environment variable is required." >&2
  echo "   Format: <name>:<base64-ed25519-secret-key>" >&2
  exit 1
fi

LOCKFILE="${ROOT_DIR}/enve.lock"
if [[ ! -f "${LOCKFILE}" ]]; then
  echo "❌ Error: Lockfile not found at ${LOCKFILE}" >&2
  exit 1
fi

echo "🔍 Extracting required store paths from ${LOCKFILE}..."
mapfile -t STORE_PATHS < <(grep -oE "/nix/store/[a-z0-9]{32}-[^\":/ ]+" "${LOCKFILE}" | sort -u)
TOTAL="${#STORE_PATHS[@]}"
echo "📦 Found ${TOTAL} unique store paths."

push_one() {
  local p="$1"
  local hash
  hash="$(basename "$p" | cut -d'-' -f1)"
  if [[ ! -e "$p" ]]; then
    return 0
  fi
  if enve cache query "$hash" --cache "$CACHE_URL" &>/dev/null; then
    echo "⏭️  Already cached: $(basename "$p")"
    return 0
  fi
  echo "🚀 Pushing $(basename "$p")..."
  if ! enve cache push "$p" --secret-key "$SIGNING_KEY" --cache "$CACHE_URL"; then
    echo "❌ Failed: $(basename "$p")" >&2
  fi
}
export -f push_one
export CACHE_URL SIGNING_KEY AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

echo "⚡ Uploading packages in parallel (concurrency: 16)..."
printf "%s\n" "${STORE_PATHS[@]}" | xargs -n 1 -P 16 -I {} bash -c 'push_one "$@"' _ {}

echo "======================================================================="
echo "🎉 Binary Cache Parallel Seeding Complete!"
echo "======================================================================="
