#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_GATES="$ROOT/plans/lib/rust_gates.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains_line() {
  local needle="$1"
  if ! grep -Fq -- "$needle" "$RUST_GATES"; then
    fail "missing expected smoke target line: $needle"
  fi
}

assert_absent_line() {
  local needle="$1"
  if grep -Fq -- "$needle" "$RUST_GATES"; then
    fail "stale smoke target still present: $needle"
  fi
}

[[ -f "$RUST_GATES" ]] || fail "missing rust gates script: $RUST_GATES"

assert_contains_line 'run_smoke_cargo_test_gate "rust_tests_smoke"'
assert_contains_line '--test test_execution_facade_public'
assert_contains_line '--test test_risk_facade_public'
assert_contains_line '--test test_venue_facade_public'
assert_contains_line '--test test_soldier_infra_facade_public'
assert_contains_line '--test test_tlsm'
assert_contains_line 'run_logged_or_exit "execution_facade_lint"'
assert_contains_line 'run_logged_or_exit "risk_facade_lint"'
assert_contains_line 'run_logged_or_exit "venue_facade_lint"'
assert_contains_line 'run_logged_or_exit "soldier_infra_facade_lint"'

line_tests_full="$(grep -nF 'run_rust_logged_or_exit "rust_tests_full"' "$RUST_GATES" | head -n1 | cut -d: -f1)"
line_branch_fi="$(awk -v start="$line_tests_full" 'NR > start && $0 ~ /^[[:space:]]*fi$/ { print NR; exit }' "$RUST_GATES")"
line_smoke="$(grep -nF 'run_smoke_cargo_test_gate "rust_tests_smoke"' "$RUST_GATES" | head -n1 | cut -d: -f1)"
line_facade_lint="$(grep -nF 'run_logged_or_exit "execution_facade_lint"' "$RUST_GATES" | head -n1 | cut -d: -f1)"

[[ -n "$line_tests_full" && -n "$line_branch_fi" && -n "$line_smoke" && -n "$line_facade_lint" ]] \
  || fail "unable to determine rust test branch boundaries"
[[ "$line_smoke" -gt "$line_branch_fi" ]] \
  || fail "rust_tests_smoke must run after the mode-specific rust test branch"
[[ "$line_facade_lint" -gt "$line_branch_fi" ]] \
  || fail "execution_facade_lint must run after the mode-specific rust test branch"

assert_absent_line '--test test_facade_completeness'
assert_absent_line '--test adversarial_gi_enforcement'
assert_absent_line '--test test_dispatch_chokepoint'
assert_absent_line '--test test_reject_reason'

echo "PASS: rust gates smoke targets"
