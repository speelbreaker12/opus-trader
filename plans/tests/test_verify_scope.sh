#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCOPE="$ROOT/plans/verify_scope.sh"
VERIFY_FORK="$ROOT/plans/verify_fork.sh"
VERIFY_SCOPE_GATES="$ROOT/plans/lib/verify_scope_gates.sh"
WORKFLOW_VERIFY="$ROOT/plans/workflow_verify.sh"
WORKFLOW_ALLOWLIST="$ROOT/plans/workflow_files_allowlist.txt"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    fail "missing expected token in ${file##*/}: $needle"
  fi
}

[[ -f "$VERIFY_SCOPE" ]] || fail "missing verify scope script: $VERIFY_SCOPE"
[[ -x "$VERIFY_SCOPE" ]] || fail "verify scope script must be executable: $VERIFY_SCOPE"
[[ -f "$VERIFY_FORK" ]] || fail "missing verify fork script: $VERIFY_FORK"
[[ -f "$VERIFY_SCOPE_GATES" ]] || fail "missing verify scope gates helper: $VERIFY_SCOPE_GATES"
[[ -f "$WORKFLOW_VERIFY" ]] || fail "missing workflow verify script: $WORKFLOW_VERIFY"
[[ -f "$WORKFLOW_ALLOWLIST" ]] || fail "missing workflow allowlist: $WORKFLOW_ALLOWLIST"

assert_contains "$VERIFY_SCOPE" 'source "$ROOT/plans/lib/verify_env.sh"'
assert_contains "$VERIFY_SCOPE" 'source "$ROOT/plans/lib/verify_scope_gates.sh"'
assert_contains "$VERIFY_SCOPE" 'init_verify_env "verify_scope"'
assert_contains "$VERIFY_SCOPE" 'source "$ROOT/plans/lib/rust_gates.sh"'
assert_contains "$VERIFY_SCOPE" '"authoritative": false'
assert_contains "$VERIFY_SCOPE" '"scope": "$VERIFY_SCOPE_SLICE"'
assert_contains "$VERIFY_SCOPE" '"run_root": "$VERIFY_RUN_ROOT"'
assert_contains "$VERIFY_SCOPE" 'artifacts/verify_scope'
assert_contains "$VERIFY_SCOPE" './plans/verify_scope.sh contract'
assert_contains "$VERIFY_SCOPE" './plans/verify_scope.sh workflow'
assert_contains "$VERIFY_SCOPE" './plans/verify_scope.sh rust clippy'
assert_contains "$VERIFY_SCOPE" './plans/verify_scope.sh rust tests'
assert_contains "$VERIFY_SCOPE" 'contract)'
assert_contains "$VERIFY_SCOPE" 'workflow)'
assert_contains "$VERIFY_SCOPE" 'clippy)'
assert_contains "$VERIFY_SCOPE" 'tests)'
assert_contains "$VERIFY_SCOPE" 'run_rust_clippy_gate'
assert_contains "$VERIFY_SCOPE" 'run_rust_tests_gate'
assert_contains "$VERIFY_SCOPE" 'run_contract_scope_gates'
assert_contains "$VERIFY_SCOPE" 'run_workflow_scope_gates'

assert_contains "$VERIFY_FORK" 'source "$ROOT/plans/lib/verify_scope_gates.sh"'
assert_contains "$VERIFY_FORK" 'run_contract_kernel_gate'
assert_contains "$VERIFY_FORK" 'run_contract_change_ledger_gate'
assert_contains "$VERIFY_FORK" 'start_parallel_contract_crossrefs_gate'
assert_contains "$VERIFY_FORK" 'run_contract_crossrefs_gate'
assert_contains "$VERIFY_FORK" 'run_csp_trace_gate'
assert_contains "$VERIFY_FORK" 'start_parallel_workflow_integration_test_gate'
assert_contains "$VERIFY_FORK" 'run_workflow_integration_test_gate'
assert_contains "$VERIFY_SCOPE_GATES" 'local gate_name="wf_${test_name%.sh}"'
assert_contains "$VERIFY_SCOPE_GATES" 'run_logged_or_exit "$gate_name" "$WORKFLOW_TEST_TIMEOUT"'
assert_contains "$VERIFY_SCOPE_GATES" 'start_parallel_gate "$gate_name" "$WORKFLOW_TEST_TIMEOUT"'

assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/lib/verify_scope_gates.sh"'
assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/verify_scope.sh"'
assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/tests/test_verify_scope.sh"'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/lib/verify_scope_gates.sh'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/verify_scope.sh'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/tests/test_verify_scope.sh'

echo "PASS: verify scope wiring"
