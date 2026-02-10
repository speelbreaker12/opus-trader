#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/plans/run_prd_auditor.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$script" ]] || fail "run_prd_auditor.sh not found at $script"

# Regression guard: timeout execution must not shell out through `bash -c` + function export,
# which drops non-exported state (e.g., AUDIT_META_FILE / parsed args arrays).
if grep -Eq 'declare -f run_auditor|bash -c .*run_auditor' "$script"; then
  fail "legacy timeout subshell invocation detected"
fi

grep -Eq 'auditor_cmd=\(' "$script" \
  || fail "missing auditor_cmd array assembly"
grep -Eq 'timeout "\$AUDITOR_TIMEOUT" "\$\{auditor_cmd\[@\]\}"' "$script" \
  || fail "timeout invocation must execute auditor_cmd array directly"
grep -Eq 'gtimeout "\$AUDITOR_TIMEOUT" "\$\{auditor_cmd\[@\]\}"' "$script" \
  || fail "gtimeout invocation must execute auditor_cmd array directly"
grep -Eq '"\$\{auditor_cmd\[@\]\}" > "\$AUDIT_STDOUT_LOG" 2>&1 \|\| auditor_rc=\$\?' "$script" \
  || fail "non-timeout invocation must execute auditor_cmd array directly"

echo "test_run_prd_auditor_invocation.sh: ok"
