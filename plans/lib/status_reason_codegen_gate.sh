#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$ROOT/plans/lib/verify_utils.sh"
ensure_python

SPEC_LINT_TIMEOUT="${SPEC_LINT_TIMEOUT:-2m}"
VERIFY_ARTIFACTS_DIR="${VERIFY_ARTIFACTS_DIR:-$ROOT/artifacts/verify/status_reason_codegen_$(date +%Y%m%d_%H%M%S)}"
VERIFY_CONSOLE="${VERIFY_CONSOLE:-verbose}"
VERIFY_LOG_CAPTURE="${VERIFY_LOG_CAPTURE:-1}"
ENABLE_TIMEOUTS="${ENABLE_TIMEOUTS:-1}"
TIMEOUT_WARNED="${TIMEOUT_WARNED:-0}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"

if [[ -z "$TIMEOUT_BIN" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
  fi
fi

mkdir -p "$VERIFY_ARTIFACTS_DIR"

if [[ "${STATUS_REASON_CODEGEN_DIRECT:-0}" == "1" ]]; then
  "$PYTHON_BIN" "$ROOT/tools/generate_reason_codes.py" --check
  exit 0
fi

log "status reason-code generation drift"
run_logged_or_exit "status_reason_codegen" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" "$ROOT/tools/generate_reason_codes.py" --check

echo "PASS: status reason-code generation gate"
