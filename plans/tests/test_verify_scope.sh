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
assert_contains "$VERIFY_SCOPE" 'verify_scope_json_escape()'
assert_contains "$VERIFY_SCOPE" '"worktree": "$(verify_scope_json_escape "$worktree_path")"'
assert_contains "$VERIFY_SCOPE" '"scope": "$(verify_scope_json_escape "$VERIFY_SCOPE_SLICE")"'
assert_contains "$VERIFY_SCOPE" '"authoritative": false'
assert_contains "$VERIFY_SCOPE" '"run_root": "$(verify_scope_json_escape "$VERIFY_RUN_ROOT")"'
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
assert_contains "$VERIFY_SCOPE_GATES" 'run_workflow_integration_test_gate "plans/tests/test_pr_review_gate_hook.sh"'
assert_contains "$VERIFY_SCOPE_GATES" 'run_workflow_integration_test_gate "plans/tests/test_review_command_wrappers.sh"'

assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/lib/verify_scope_gates.sh"'
assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/verify_scope.sh"'
assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/tests/test_verify_scope.sh"'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/lib/verify_scope_gates.sh'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/verify_scope.sh'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/tests/test_verify_scope.sh'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workflow_scope_probe="$tmp_dir/workflow_scope_probe.sh"
cat > "$workflow_scope_probe" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
WORKFLOW_TEST_TIMEOUT=1s
SPEC_LINT_TIMEOUT=1s
source "$VERIFY_SCOPE_GATES"
RECORDED_GATES=()
run_logged_or_exit() {
  local gate_name="\$1"
  shift 2
  RECORDED_GATES+=("\$gate_name:\$*")
}
run_workflow_scope_gates
printf '%s\n' "\${RECORDED_GATES[@]}"
EOF
chmod +x "$workflow_scope_probe"
workflow_scope_calls="$(bash "$workflow_scope_probe")"
printf '%s\n' "$workflow_scope_calls" | grep -Fq 'wf_test_pr_review_gate_hook:bash plans/tests/test_pr_review_gate_hook.sh' \
  || fail "workflow scope must execute the PR review gate hook regression"
printf '%s\n' "$workflow_scope_calls" | grep -Fq 'wf_test_review_command_wrappers:bash plans/tests/test_review_command_wrappers.sh' \
  || fail "workflow scope must execute the review command wrapper regression"

mock_bin="$tmp_dir/mock_bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--verify" ]]; then
  exit 0
fi

if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
  if [[ "${3:-}" == "origin/main...HEAD" ]]; then
    printf '%s\n' "specs/TRACE.yaml"
  fi
  exit 0
fi

exit 0
EOF
chmod +x "$mock_bin/git"

contract_scope_probe="$tmp_dir/contract_scope_probe.sh"
cat > "$contract_scope_probe" <<EOF
#!/usr/bin/env bash
set -euo pipefail
PATH="$mock_bin:\$PATH"
ROOT="$ROOT"
VERIFY_BASE_REF="origin/main"
PYTHON_BIN="python3"
source "$VERIFY_SCOPE_GATES"
build_csp_trace_cmd auto
printf '%s\n' "\${CSP_TRACE_CMD[@]}"
EOF
chmod +x "$contract_scope_probe"
contract_scope_cmd="$(bash "$contract_scope_probe")"
printf '%s\n' "$contract_scope_cmd" | grep -Fxq -- '--strict' \
  || fail "contract scope auto strict must enable --strict when contract/trace files changed"

echo "PASS: verify scope wiring"
