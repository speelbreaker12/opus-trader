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

assert_contains_line 'run_logged_or_exit "rust_tests_smoke"'
assert_contains_line '--test test_execution_facade_public'
assert_contains_line '--test test_tlsm'

assert_absent_line '--test test_facade_completeness'
assert_absent_line '--test adversarial_gi_enforcement'
assert_absent_line '--test test_dispatch_chokepoint'
assert_absent_line '--test test_reject_reason'

echo "PASS: rust gates smoke targets"
