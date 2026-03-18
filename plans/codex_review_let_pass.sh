#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/plans/codex_review_logged.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "ERROR: missing executable $TARGET" >&2
  exit 2
fi

exec "$TARGET" "$@"
