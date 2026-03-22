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
assert_contains_line 'PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-600s}"'
assert_contains_line 'if [[ "$MODE" == "full" && "$PREFLIGHT_TIMEOUT_WAS_SET" -eq 0 ]]; then'
assert_contains_line 'PREFLIGHT_TIMEOUT="1800s"'
assert_contains_line 'if [[ "$MODE" == "quick" ]]; then'
assert_contains_line 'RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-5m}"'
assert_contains_line 'RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-15m}"'
assert_contains_line 'RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-5m}"'
assert_contains_line 'RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-45m}"'
assert_contains_line 'MECHANICAL_TIMEOUT="${MECHANICAL_TIMEOUT:-10m}"'

line_default="$(grep -nF 'PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-600s}"' "$VERIFY" | head -n1 | cut -d: -f1)"
line_full_override="$(grep -nF 'if [[ "$MODE" == "full" && "$PREFLIGHT_TIMEOUT_WAS_SET" -eq 0 ]]; then' "$VERIFY" | head -n1 | cut -d: -f1)"
line_mode_aware_start="$(grep -nF 'if [[ "$MODE" == "quick" ]]; then' "$VERIFY" | head -n1 | cut -d: -f1)"
line_clippy_quick="$(grep -nF 'RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-5m}"' "$VERIFY" | head -n1 | cut -d: -f1)"
line_clippy_full="$(grep -nF 'RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-15m}"' "$VERIFY" | head -n1 | cut -d: -f1)"
line_test_quick="$(grep -nF 'RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-5m}"' "$VERIFY" | head -n1 | cut -d: -f1)"
line_test_full="$(grep -nF 'RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-45m}"' "$VERIFY" | head -n1 | cut -d: -f1)"

[[ -n "$line_default" && -n "$line_full_override" ]] || fail "unable to determine timeout line ordering"
if [[ "$line_default" -ge "$line_full_override" ]]; then
  fail "default timeout assignment must appear before full-mode override"
fi

[[ -n "$line_mode_aware_start" && -n "$line_clippy_quick" && -n "$line_clippy_full" && -n "$line_test_quick" && -n "$line_test_full" ]] \
  || fail "unable to determine mode-aware rust timeout line ordering"
if [[ "$line_mode_aware_start" -ge "$line_clippy_quick" ]]; then
  fail "quick-mode branch must begin before quick rust clippy timeout assignment"
fi
if [[ "$line_clippy_quick" -ge "$line_test_quick" ]]; then
  fail "quick rust clippy timeout must be assigned before quick rust test timeout"
fi
if [[ "$line_test_quick" -ge "$line_clippy_full" ]]; then
  fail "full rust clippy timeout must appear after the quick-mode timeout block"
fi
if [[ "$line_clippy_full" -ge "$line_test_full" ]]; then
  fail "full rust clippy timeout must be assigned before full rust test timeout"
fi

echo "PASS: verify timeout policy tokens"
