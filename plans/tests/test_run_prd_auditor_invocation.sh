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
grep -Eq -- '--arg roadmap_sha "\$roadmap_sha"' "$script" \
  || fail "cache predicate must include roadmap hash"
grep -Eq '\.roadmap_sha256 == \$roadmap_sha and' "$script" \
  || fail "cache predicate must validate roadmap hash"
grep -Eq '\.audited_scope == \$audit_scope and' "$script" \
  || fail "cache predicate must match requested scope"
grep -Eq '\(\$audit_scope != "slice" or \.slice == \$audit_slice\) and' "$script" \
  || fail "cache predicate must scope slice cache hits to the requested slice"
grep -Eq -- '--arg slice_sha "\$slice_cache_sha"' "$script" \
  || fail "cache predicate must include slice hash argument"
grep -Eq '\(\.prd_sha256 == \$prd_sha or \(\$audit_scope == "slice" and \$slice_sha != "" and \.prd_sha256 == \$slice_sha\)\) and' "$script" \
  || fail "slice scope cache must accept either full or slice prd hash"
grep -Eq 'AUDITOR_TIMEOUT_FALLBACK_PARALLEL="\$\{AUDITOR_TIMEOUT_FALLBACK_PARALLEL:-1\}"' "$script" \
  || fail "missing timeout fallback config"
grep -Eq '\[\[ "\$AUDIT_SCOPE" == "full" && "\$AUDITOR_TIMEOUT_FALLBACK_PARALLEL" == "1" && -x "\./plans/audit_parallel.sh" \]\]' "$script" \
  || fail "missing full-scope timeout fallback guard"
grep -Eq 'MERGED_AUDIT_FILE="\$AUDIT_OUTPUT_JSON"' "$script" \
  || fail "parallel fallback must honor AUDIT_OUTPUT_JSON"
grep -Eq 'echo "<promise>AUDIT_COMPLETE</promise>" >> "\$AUDIT_STDOUT_LOG"' "$script" \
  || fail "fallback must restore promise marker in stdout log"

echo "test_run_prd_auditor_invocation.sh: ok"
