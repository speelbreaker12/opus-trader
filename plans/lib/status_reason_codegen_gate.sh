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

ensure_python

STATUS_REASON_CODEGEN_TIMEOUT="${STATUS_REASON_CODEGEN_TIMEOUT:-${SPEC_LINT_TIMEOUT:-2m}}"

log "status reason-code generation drift"
run_logged_or_exit "status_reason_codegen" "$STATUS_REASON_CODEGEN_TIMEOUT" \
  "$PYTHON_BIN" "$ROOT/tools/generate_reason_codes.py" --check

echo "✓ status reason-code generation gate passed"
