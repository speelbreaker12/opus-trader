#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$ROOT/plans/verify_fork.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$VERIFY"; then
    fail "missing expected verify timeout token: $needle"
  fi
}

[[ -f "$VERIFY" ]] || fail "missing verify script: $VERIFY"

assert_contains_line 'PREFLIGHT_TIMEOUT_WAS_SET=0'
assert_contains_line 'if [[ -n "${PREFLIGHT_TIMEOUT:-}" ]]; then'
assert_contains_line 'PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-300s}"'
assert_contains_line 'if [[ "$MODE" == "full" && "$PREFLIGHT_TIMEOUT_WAS_SET" -eq 0 ]]; then'
assert_contains_line 'PREFLIGHT_TIMEOUT="900s"'

line_default="$(grep -nF 'PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-300s}"' "$VERIFY" | head -n1 | cut -d: -f1)"
line_full_override="$(grep -nF 'if [[ "$MODE" == "full" && "$PREFLIGHT_TIMEOUT_WAS_SET" -eq 0 ]]; then' "$VERIFY" | head -n1 | cut -d: -f1)"

[[ -n "$line_default" && -n "$line_full_override" ]] || fail "unable to determine timeout line ordering"
if [[ "$line_default" -ge "$line_full_override" ]]; then
  fail "default timeout assignment must appear before full-mode override"
fi

echo "PASS: verify timeout policy tokens"
