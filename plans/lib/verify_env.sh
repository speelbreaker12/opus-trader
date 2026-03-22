#!/usr/bin/env bash

if [[ -n "${__VERIFY_ENV_SOURCED:-}" ]]; then
  return 0
fi
__VERIFY_ENV_SOURCED=1

if [[ -z "${ROOT:-}" ]]; then
  VERIFY_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$VERIFY_ENV_DIR/../.." && pwd)"
fi

source "$ROOT/plans/lib/verify_utils.sh"

resolve_verify_console() {
  VERIFY_CONSOLE="${VERIFY_CONSOLE:-auto}"
  case "$VERIFY_CONSOLE" in
    auto)
      if is_ci; then
        VERIFY_CONSOLE="quiet"
      else
        VERIFY_CONSOLE="verbose"
      fi
      ;;
    quiet|verbose) ;;
    *)
      warn "Unknown VERIFY_CONSOLE=$VERIFY_CONSOLE (expected auto|quiet|verbose); defaulting to verbose"
      VERIFY_CONSOLE="verbose"
      ;;
  esac
}

detect_verify_timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    printf '%s\n' "timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    printf '%s\n' "gtimeout"
  fi
}

init_verify_timeouts() {
  local preflight_timeout_was_set=0

  if [[ -n "${PREFLIGHT_TIMEOUT:-}" ]]; then
    preflight_timeout_was_set=1
  fi

  PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-600s}"
  if [[ "${MODE:-quick}" == "full" && "$preflight_timeout_was_set" -eq 0 ]]; then
    PREFLIGHT_TIMEOUT="1800s"
  fi

  CONTRACT_KERNEL_TIMEOUT="${CONTRACT_KERNEL_TIMEOUT:-30s}"
  CONTRACT_PROFILE_TIMEOUT="${CONTRACT_PROFILE_TIMEOUT:-30s}"
  CONTRACT_COVERAGE_TIMEOUT="${CONTRACT_COVERAGE_TIMEOUT:-2m}"
  SPEC_LINT_TIMEOUT="${SPEC_LINT_TIMEOUT:-2m}"
  CSP_TRACE_TIMEOUT="${CSP_TRACE_TIMEOUT:-2m}"
  STATUS_FIXTURE_TIMEOUT="${STATUS_FIXTURE_TIMEOUT:-30s}"
  STATUS_REASON_CODEGEN_TIMEOUT="${STATUS_REASON_CODEGEN_TIMEOUT:-$SPEC_LINT_TIMEOUT}"
  VENDOR_DOCS_LINT_TIMEOUT="${VENDOR_DOCS_LINT_TIMEOUT:-1m}"
  RUST_FMT_TIMEOUT="${RUST_FMT_TIMEOUT:-2m}"

  if [[ "${MODE:-quick}" == "quick" ]]; then
    RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-5m}"
    RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-5m}"
  else
    RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-15m}"
    RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-45m}"
  fi

  RUFF_TIMEOUT="${RUFF_TIMEOUT:-2m}"
  PYTEST_TIMEOUT="${PYTEST_TIMEOUT:-15m}"
  MYPY_TIMEOUT="${MYPY_TIMEOUT:-10m}"
  NODE_LINT_TIMEOUT="${NODE_LINT_TIMEOUT:-5m}"
  NODE_TYPECHECK_TIMEOUT="${NODE_TYPECHECK_TIMEOUT:-10m}"
  NODE_TEST_TIMEOUT="${NODE_TEST_TIMEOUT:-10m}"
  ADVERSARIAL_GATE_TIMEOUT="${ADVERSARIAL_GATE_TIMEOUT:-2m}"
  GATE_INTEGRITY_TIMEOUT="${GATE_INTEGRITY_TIMEOUT:-30s}"
  DOC_SYNC_TIMEOUT="${DOC_SYNC_TIMEOUT:-30s}"
  WORKFLOW_TEST_TIMEOUT="${WORKFLOW_TEST_TIMEOUT:-15m}"
  ARTIFACT_LINT_TIMEOUT="${ARTIFACT_LINT_TIMEOUT:-45s}"
  CONTRACT_REVIEW_TIMEOUT="${CONTRACT_REVIEW_TIMEOUT:-30s}"
}

init_verify_run_context() {
  local run_root="${1:-verify}"

  VERIFY_RUN_ROOT="$run_root"
  VERIFY_RUN_ID="${VERIFY_RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
  VERIFY_ARTIFACTS_DIR="${VERIFY_ARTIFACTS_DIR:-$ROOT/artifacts/$VERIFY_RUN_ROOT/$VERIFY_RUN_ID}"
  mkdir -p "$VERIFY_ARTIFACTS_DIR"
  VERIFY_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  VERIFY_BASE_REF="${BASE_REF:-origin/main}"
}

init_verify_env() {
  local run_root="${1:-verify}"

  cd "$ROOT"

  resolve_verify_console
  VERIFY_LOG_CAPTURE="${VERIFY_LOG_CAPTURE:-1}"
  VERIFY_FAIL_TAIL_LINES="${VERIFY_FAIL_TAIL_LINES:-80}"
  VERIFY_FAIL_SUMMARY_LINES="${VERIFY_FAIL_SUMMARY_LINES:-20}"
  ENABLE_TIMEOUTS="${ENABLE_TIMEOUTS:-1}"
  TIMEOUT_WARNED=0
  TIMEOUT_BIN="${TIMEOUT_BIN:-$(detect_verify_timeout_bin)}"

  init_verify_timeouts
  init_verify_run_context "$run_root"
}
