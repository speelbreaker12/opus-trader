#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

source "$ROOT/plans/lib/verify_utils.sh"
source "$ROOT/plans/lib/verify_env.sh"

VERIFY_USE_SCCACHE="${VERIFY_USE_SCCACHE:-0}"
VERIFY_TEST_RUNNER="${VERIFY_TEST_RUNNER:-cargo}"
RUN_LOGGED_SUPPRESS_EXCERPT="${RUN_LOGGED_SUPPRESS_EXCERPT:-}"
RUN_LOGGED_SKIP_FAILED_GATE="${RUN_LOGGED_SKIP_FAILED_GATE:-}"
RUN_LOGGED_SUPPRESS_TIMEOUT_FAIL="${RUN_LOGGED_SUPPRESS_TIMEOUT_FAIL:-}"
RUST_RUNNER_CONFIG_READY="${RUST_RUNNER_CONFIG_READY:-0}"
RUST_SCCACHE_REQUESTED="${RUST_SCCACHE_REQUESTED:-false}"
RUST_SCCACHE_AVAILABLE="${RUST_SCCACHE_AVAILABLE:-false}"
RUST_SCCACHE_ACTIVE="${RUST_SCCACHE_ACTIVE:-false}"
RUSTC_WRAPPER_BIN="${RUSTC_WRAPPER_BIN:-}"
RUST_TEST_RUNNER_EFFECTIVE="${RUST_TEST_RUNNER_EFFECTIVE:-cargo}"
RUST_TEST_RUNNER_FALLBACKS=()

json_string_array() {
  local item
  local first=1
  printf '['
  for item in "$@"; do
    if [[ "$first" == "0" ]]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$item"
  done
  printf ']'
}

rust_runner_meta_file() {
  printf '%s\n' "$VERIFY_ARTIFACTS_DIR/rust_runner.meta.json"
}

rust_test_runner_fallback_log_file() {
  printf '%s\n' "$VERIFY_ARTIFACTS_DIR/rust_test_runner_fallbacks.log"
}

write_rust_runner_meta() {
  local fallbacks_json

  if [[ "${#RUST_TEST_RUNNER_FALLBACKS[@]}" -eq 0 ]]; then
    fallbacks_json='[]'
  else
    fallbacks_json="$(json_string_array "${RUST_TEST_RUNNER_FALLBACKS[@]}")"
  fi

  cat > "$(rust_runner_meta_file)" <<META
{
  "schema_version": 1,
  "sccache": {
    "requested": $RUST_SCCACHE_REQUESTED,
    "available": $RUST_SCCACHE_AVAILABLE,
    "active": $RUST_SCCACHE_ACTIVE
  },
  "test_runner": {
    "requested": "$VERIFY_TEST_RUNNER",
    "effective": "$RUST_TEST_RUNNER_EFFECTIVE",
    "fallbacks": $fallbacks_json
  }
}
META
}

record_rust_test_runner_fallback() {
  local gate_name="$1"
  local reason="$2"
  local note="${gate_name}:${reason}"

  printf '%s\n' "$note" >> "$(rust_test_runner_fallback_log_file)"
  RUST_TEST_RUNNER_FALLBACKS+=("$note")
  write_rust_runner_meta
  echo "INFO: ${gate_name} falling back to cargo test (${reason})"
}

ensure_rust_runner_config() {
  if [[ -z "${VERIFY_ARTIFACTS_DIR:-}" ]]; then
    fail "VERIFY_ARTIFACTS_DIR is not set; run init_verify_env first or execute plans/lib/rust_gates.sh directly"
  fi

  if [[ "$RUST_RUNNER_CONFIG_READY" == "1" ]]; then
    return 0
  fi

  case "$VERIFY_USE_SCCACHE" in
    0|1) ;;
    *)
      fail "VERIFY_USE_SCCACHE=$VERIFY_USE_SCCACHE must be 0 or 1"
      ;;
  esac

  case "$VERIFY_TEST_RUNNER" in
    cargo|nextest) ;;
    *)
      fail "VERIFY_TEST_RUNNER=$VERIFY_TEST_RUNNER must be cargo or nextest"
      ;;
  esac

  if [[ "$VERIFY_USE_SCCACHE" == "1" ]]; then
    RUST_SCCACHE_REQUESTED=true
    if command -v sccache >/dev/null 2>&1; then
      RUST_SCCACHE_AVAILABLE=true
      RUST_SCCACHE_ACTIVE=true
      RUSTC_WRAPPER_BIN="$(command -v sccache)"
    else
      write_rust_runner_meta
      fail "VERIFY_USE_SCCACHE=1 requires sccache"
    fi
  fi

  if [[ "$VERIFY_TEST_RUNNER" == "nextest" ]]; then
    if command -v cargo-nextest >/dev/null 2>&1; then
      RUST_TEST_RUNNER_EFFECTIVE="nextest"
    else
      write_rust_runner_meta
      fail "VERIFY_TEST_RUNNER=nextest requires cargo-nextest"
    fi
  else
    RUST_TEST_RUNNER_EFFECTIVE="cargo"
  fi

  write_rust_runner_meta
  RUST_RUNNER_CONFIG_READY=1
}

run_rust_logged_or_exit() {
  local gate_name="$1"
  local timeout="$2"
  shift 2

  ensure_rust_runner_config

  if [[ "$RUST_SCCACHE_ACTIVE" == "true" ]]; then
    run_logged_or_exit "$gate_name" "$timeout" env RUSTC_WRAPPER="$RUSTC_WRAPPER_BIN" "$@"
  else
    run_logged_or_exit "$gate_name" "$timeout" "$@"
  fi
}

configure_rust_proptest_cases() {
  if [[ "${MODE:-}" == "full" ]]; then
    # Property tests (proptest) run more cases in full mode.
    PROPTEST_CASES="${PROPTEST_CASES:-1000}"
    if [[ ! "$PROPTEST_CASES" =~ ^[0-9]+$ ]]; then
      warn "PROPTEST_CASES=$PROPTEST_CASES is not numeric, defaulting to 256"
      PROPTEST_CASES=256
    elif [[ "$PROPTEST_CASES" -gt 10000 ]]; then
      warn "PROPTEST_CASES=$PROPTEST_CASES exceeds recommended max (10000), capping"
      PROPTEST_CASES=10000
    fi
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
  fi

  export PROPTEST_CASES
}

run_mode_selected_rust_tests() {
  if [[ "${MODE:-}" == "full" ]]; then
    if [[ "$RUST_TEST_RUNNER_EFFECTIVE" == "nextest" ]]; then
      run_rust_logged_or_exit "rust_tests_full" "$RUST_TEST_TIMEOUT" cargo nextest run --workspace --all-features --locked
    else
      run_rust_logged_or_exit "rust_tests_full" "$RUST_TEST_TIMEOUT" cargo test --workspace --all-features --locked
    fi
  else
    if [[ "$RUST_TEST_RUNNER_EFFECTIVE" == "nextest" ]]; then
      run_rust_logged_or_exit "rust_tests_quick" "$RUST_TEST_TIMEOUT" cargo nextest run --workspace --lib --locked
    else
      run_rust_logged_or_exit "rust_tests_quick" "$RUST_TEST_TIMEOUT" cargo test --workspace --lib --locked
    fi
  fi
}

run_smoke_cargo_test_gate() {
  local gate_name="$1"
  shift

  if [[ "$RUST_TEST_RUNNER_EFFECTIVE" == "nextest" ]]; then
    record_rust_test_runner_fallback "$gate_name" "smoke_suite_requires_cargo_test"
  fi

  run_rust_logged_or_exit "$gate_name" "$RUST_TEST_TIMEOUT" cargo test "$@"
}

run_rust_fmt_gate() {
  ensure_rust_runner_config
  log "2a) Rust format"
  run_rust_logged_or_exit "rust_fmt" "$RUST_FMT_TIMEOUT" cargo fmt --all -- --check
}

run_rust_clippy_gate() {
  ensure_rust_runner_config
  if [[ "${MODE:-}" == "full" ]]; then
    log "2b) Rust clippy (full)"
    run_rust_logged_or_exit "rust_clippy" "$RUST_CLIPPY_TIMEOUT" cargo clippy --workspace --all-targets --all-features -- -D warnings
  else
    # Quick mode keeps clippy on lib targets only for fast feedback.
    # Full mode retains broader all-target coverage.
    log "2b) Rust clippy (quick)"
    run_rust_logged_or_exit "rust_clippy" "$RUST_CLIPPY_TIMEOUT" cargo clippy --workspace --lib -- -D warnings
  fi
}

run_rust_tests_gate() {
  ensure_rust_runner_config
  log "2c) Rust tests"
  configure_rust_proptest_cases
  run_mode_selected_rust_tests
}

run_rust_smoke_and_facade_lints_gate() {
  ensure_rust_runner_config
  # Smoke contract tests: ensure facade-level integration contracts remain green in both modes.
  run_smoke_cargo_test_gate "rust_tests_smoke" \
    -p soldier_core --locked \
    --test test_execution_facade_public \
    --test test_risk_facade_public \
    --test test_venue_facade_public \
    --test test_tlsm

  run_smoke_cargo_test_gate "soldier_infra_facade_smoke" \
    -p soldier_infra --locked \
    --test test_soldier_infra_facade_public

  run_logged_or_exit "execution_facade_lint" "$RUST_TEST_TIMEOUT" bash plans/lint_execution_facade.sh
  run_logged_or_exit "risk_facade_lint" "$RUST_TEST_TIMEOUT" bash plans/lint_risk_facade.sh
  run_logged_or_exit "venue_facade_lint" "$RUST_TEST_TIMEOUT" bash plans/lint_venue_facade.sh
  run_logged_or_exit "soldier_infra_facade_lint" "$RUST_TEST_TIMEOUT" bash plans/lint_soldier_infra_facade.sh
}

run_rust_gates() {
  ensure_rust_runner_config
  need cargo
  run_rust_fmt_gate
  run_rust_clippy_gate
  run_rust_tests_gate
  run_rust_smoke_and_facade_lints_gate
  echo "✓ rust gates passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  init_verify_env "${VERIFY_RUN_ROOT:-verify}"
  run_rust_gates "$@"
fi
