#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

source "$ROOT/plans/lib/verify_utils.sh"

RUN_LOGGED_SUPPRESS_EXCERPT="${RUN_LOGGED_SUPPRESS_EXCERPT:-}"
RUN_LOGGED_SKIP_FAILED_GATE="${RUN_LOGGED_SKIP_FAILED_GATE:-}"
RUN_LOGGED_SUPPRESS_TIMEOUT_FAIL="${RUN_LOGGED_SUPPRESS_TIMEOUT_FAIL:-}"

need cargo

log "2a) Rust format"
run_logged_or_exit "rust_fmt" "$RUST_FMT_TIMEOUT" cargo fmt --all -- --check

if [[ "${MODE:-}" == "full" ]]; then
  log "2b) Rust clippy (full)"
  run_logged_or_exit "rust_clippy" "$RUST_CLIPPY_TIMEOUT" cargo clippy --workspace --all-targets --all-features -- -D warnings
else
  # Quick mode keeps clippy on lib targets only for fast feedback.
  # Full mode retains broader all-target coverage.
  log "2b) Rust clippy (quick)"
  run_logged_or_exit "rust_clippy" "$RUST_CLIPPY_TIMEOUT" cargo clippy --workspace --lib -- -D warnings
fi

log "2c) Rust tests"
if [[ "${MODE:-}" == "full" ]]; then
  # Property tests (proptest) run more cases in full mode
  PROPTEST_CASES="${PROPTEST_CASES:-1000}"
  if [[ ! "$PROPTEST_CASES" =~ ^[0-9]+$ ]]; then
    warn "PROPTEST_CASES=$PROPTEST_CASES is not numeric, defaulting to 256"
    PROPTEST_CASES=256
  elif [[ "$PROPTEST_CASES" -gt 10000 ]]; then
    warn "PROPTEST_CASES=$PROPTEST_CASES exceeds recommended max (10000), capping"
    PROPTEST_CASES=10000
  fi
  export PROPTEST_CASES
  run_logged_or_exit "rust_tests_full" "$RUST_TEST_TIMEOUT" cargo test --workspace --all-features --locked
else
  # In quick mode, keep proptests lightweight for fast feedback.
  PROPTEST_CASES="${PROPTEST_CASES:-32}"
  if [[ ! "$PROPTEST_CASES" =~ ^[0-9]+$ ]]; then
    warn "PROPTEST_CASES=$PROPTEST_CASES is not numeric, defaulting to 32"
    PROPTEST_CASES=32
  elif [[ "$PROPTEST_CASES" -gt 1000 ]]; then
    warn "PROPTEST_CASES=$PROPTEST_CASES exceeds quick-mode max (1000), capping"
    PROPTEST_CASES=1000
  fi
  export PROPTEST_CASES

  run_logged_or_exit "rust_tests_quick" "$RUST_TEST_TIMEOUT" cargo test --workspace --lib --locked

fi

# Smoke contract tests: ensure facade-level integration contracts remain green in both modes.
run_logged_or_exit "rust_tests_smoke" "$RUST_TEST_TIMEOUT" \
  cargo test -p soldier_core --locked \
    --test test_execution_facade_public \
    --test test_tlsm

run_logged_or_exit "execution_facade_lint" "$RUST_TEST_TIMEOUT" bash plans/lint_execution_facade.sh

echo "✓ rust gates passed"
