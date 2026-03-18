#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

guards=(
  "$ROOT/plans/story_review_findings_guard.sh"
  "$ROOT/plans/slice_completion_review_guard.sh"
)

for guard in "${guards[@]}"; do
  [[ -f "$guard" ]] || fail "missing guard: $guard"
  if grep -nE '^require_token[[:space:]]+"[^"]*`[^"]*`' "$guard" >/dev/null; then
    fail "guard uses backticks in require_token (command substitution risk): $guard"
  fi
done

echo "PASS: guard command substitution lint"
