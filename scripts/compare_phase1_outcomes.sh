#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OPUS_REPO="${OPUS_REPO:-/Users/admin/Desktop/opus-trader}"
RALPH_REPO="${RALPH_REPO:-/Users/admin/Desktop/ralph}"

# Optional positional overrides:
#   1st arg -> opus path
#   2nd arg -> ralph path
if [[ $# -ge 1 && "${1#-}" == "$1" ]]; then
  OPUS_REPO="$1"
  shift
fi
if [[ $# -ge 1 && "${1#-}" == "$1" ]]; then
  RALPH_REPO="$1"
  shift
fi

exec python3 "${REPO_ROOT}/tools/phase1_compare.py" \
  --opus "${OPUS_REPO}" \
  --ralph "${RALPH_REPO}" \
  "$@"
