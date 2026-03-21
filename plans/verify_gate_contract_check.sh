#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOC="specs/WORKFLOW_CONTRACT.md"
VERIFY="plans/verify_fork.sh"
VERIFY_ENV="plans/lib/verify_env.sh"
VERIFY_SCOPE_GATES="plans/lib/verify_scope_gates.sh"
RUST_GATES="plans/lib/rust_gates.sh"
PY_GATES="plans/lib/python_gates.sh"
NODE_GATES="plans/lib/node_gates.sh"
STATUS_REASON_CODEGEN_GATE="plans/lib/status_reason_codegen_gate.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for f in "$DOC" "$VERIFY" "$VERIFY_ENV" "$VERIFY_SCOPE_GATES" "$RUST_GATES" "$PY_GATES" "$NODE_GATES" "$STATUS_REASON_CODEGEN_GATE"; do
  [[ -f "$f" ]] || fail "missing required file: $f"
done

extract_section() {
  local file="$1"
  local start_line="$2"
  local end_line="$3"

  awk -v start="$start_line" -v end="$end_line" '
    $0 == start {capture=1; next}
    capture && $0 == end {exit}
    capture {print}
  ' "$file"
}

require_doc_token() {
  local section_text="$1"
  local token="$2"
  if ! grep -Fq -- "$token" <<< "$section_text"; then
    fail "workflow contract missing token '$token' in expected gate section"
  fi
}

require_code_token() {
  local file_content="$1"
  local file="$2"
  local token="$3"
  if ! contains_literal_token "$file_content" "$token"; then
    fail "missing code token '$token' in $file"
  fi
}

contains_literal_token() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]]
}

quick_section="$(extract_section "$DOC" "#### QUICK (developer iteration)" "#### FULL (story completion)")"
full_section="$(extract_section "$DOC" "#### FULL (story completion)" "### 7.5 Local full is allowed")"

[[ -n "$quick_section" ]] || fail "unable to parse QUICK gate section from $DOC"
[[ -n "$full_section" ]] || fail "unable to parse FULL gate section from $DOC"

# Docs: quick gate coverage.
quick_tokens=(
  preflight
  artifact_lint
  contract_profiles
  at_profile_parity
  at_coverage_report
  crossref_invariants
  contract_crossrefs
  arch_flows
  state_machines
  global_invariants
  time_freshness
  crash_matrix
  crash_replay_idempotency
  reconciliation_matrix
  csp_trace
  status_fixture_*
  doc_sync_check
  rust_fmt
  rust_clippy
  rust_tests_quick
  rust_tests_smoke
  execution_facade_lint
  python_ruff_check
  python_pytest_quick
  node_lint
  node_typecheck
  node_test
)

for token in "${quick_tokens[@]}"; do
  require_doc_token "$quick_section" "$token"
done

# Docs: full-only gate coverage.
full_tokens=(
  contract_review_generate
  contract_review_validate
  artifact_lint
  crossref_gate
  contract_coverage
  rust_clippy
  rust_tests_full
  python_mypy
  python_pytest_full
  python_ruff_format
)

for token in "${full_tokens[@]}"; do
  require_doc_token "$full_section" "$token"
done

# Verify implementation: contract/spec/status gates.
verify_tokens=(
  'run_logged_or_exit "contract_review_generate"'
  'run_logged_or_exit "contract_review_validate"'
  'run_logged_or_exit "preflight"'
  'run_logged_or_exit "artifact_lint"'
  'run_logged_or_exit "contract_profiles"'
  'run_logged_or_exit "at_profile_parity"'
  'run_logged_or_exit "at_coverage_report"'
  'run_logged_or_exit "crossref_invariants"'
  'run_logged_or_exit "crossref_gate"'
  'source "$ROOT/plans/lib/verify_scope_gates.sh"'
  'run_contract_kernel_gate'
  'run_contract_change_ledger_gate'
  'start_parallel_contract_crossrefs_gate'
  'run_contract_crossrefs_gate'
  'start_parallel_csp_trace_gate'
  'run_csp_trace_gate'
  'start_parallel_gate "contract_impl_lag_ids"'
  'run_logged_or_exit "contract_impl_lag_ids"'
  'run_logged_or_exit "arch_flows"'
  'run_logged_or_exit "state_machines"'
  'run_logged_or_exit "global_invariants"'
  'run_logged_or_exit "time_freshness"'
  'run_logged_or_exit "crash_matrix"'
  'run_logged_or_exit "crash_replay_idempotency"'
  'run_logged_or_exit "reconciliation_matrix"'
  'start_parallel_workflow_integration_test_gate'
  'run_workflow_integration_test_gate'
  'status_fixture_'
  'log "12f) status reason codegen"'
  'bash "$ROOT/plans/lib/status_reason_codegen_gate.sh"'
  'run_logged_or_exit "doc_sync_check"'
)

VERIFY_CONTENT="$(<"$VERIFY")"
VERIFY_ENV_CONTENT="$(<"$VERIFY_ENV")"
for token in "${verify_tokens[@]}"; do
  require_code_token "$VERIFY_CONTENT" "$VERIFY" "$token"
done

verify_scope_gate_tokens=(
  'run_logged_or_exit "contract_kernel"'
  'run_logged_or_exit "contract_change_ledger"'
  'run_logged_or_exit "contract_crossrefs"'
  'start_parallel_gate "contract_crossrefs"'
  'run_logged_or_exit "csp_trace"'
  'start_parallel_gate "csp_trace"'
  'run_logged_or_exit "workflow_contract_gate"'
  'local gate_name="wf_${test_name%.sh}"'
  'run_logged_or_exit "$gate_name"'
  'start_parallel_gate "$gate_name" "$WORKFLOW_TEST_TIMEOUT"'
)
VERIFY_SCOPE_GATES_CONTENT="$(<"$VERIFY_SCOPE_GATES")"
for token in "${verify_scope_gate_tokens[@]}"; do
  require_code_token "$VERIFY_SCOPE_GATES_CONTENT" "$VERIFY_SCOPE_GATES" "$token"
done

verify_extra_tokens=(
  'run_logged_or_exit "contract_coverage"'
  './plans/contract_review_emit.sh --out "$VERIFY_ARTIFACTS_DIR/contract_review.json"'
  './plans/contract_review_validate.sh "$VERIFY_ARTIFACTS_DIR/contract_review.json"'
  'tools/ci/check_contract_profiles.py'
  'tools/ci/check_contract_profile_map_parity.py'
  'tools/at_coverage_report.py'
  'plans/validate_crossref_invariants.py'
  './plans/crossref_gate.sh'
  'tools/check_lag_ids.py --file docs/CONTRACT_IMPL_LAG.md'
  'Skipping contract_coverage in quick mode (full-only gate)'
  'CONTRACT_COVERAGE_CI_SENTINEL'
  'CONTRACT_COVERAGE_STRICT_EFFECTIVE'
  'CROSSREF_CI_STRICT_SENTINEL'
  'CROSSREF_STRICT_EFFECTIVE'
  'crossref_strict=1 (sentinel/env enabled)'
  'Skipping crossref_gate in quick mode (full-only gate)'
  'env CONTRACT_COVERAGE_STRICT="$CONTRACT_COVERAGE_STRICT_EFFECTIVE"'
  'source "$ROOT/plans/lib/verify_env.sh"'
  'init_verify_env "verify"'
  'source "$ROOT/plans/lib/verify_scope_gates.sh"'
  'run_logged_or_exit "slice_completion_enforce"'
)
for token in "${verify_extra_tokens[@]}"; do
  require_code_token "$VERIFY_CONTENT" "$VERIFY" "$token"
done

verify_env_tokens=(
  'PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-600s}"'
  'local preflight_timeout_was_set=0'
  'if [[ -n "${PREFLIGHT_TIMEOUT:-}" ]]; then'
  'if [[ "${MODE:-quick}" == "full" && "$preflight_timeout_was_set" -eq 0 ]]; then'
  'RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-5m}"'
  'RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-15m}"'
  'RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-5m}"'
  'RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-45m}"'
)
for token in "${verify_env_tokens[@]}"; do
  require_code_token "$VERIFY_ENV_CONTENT" "$VERIFY_ENV" "$token"
done

# Stack gate scripts: ensure quick/full Rust gate names are present.
rust_quick_tokens=(
  'run_rust_logged_or_exit "rust_fmt"'
  'run_rust_logged_or_exit "rust_clippy"'
  'cargo clippy --workspace --lib -- -D warnings'
  'run_mode_selected_rust_tests'
  'run_smoke_cargo_test_gate "rust_tests_smoke"'
  'run_logged_or_exit "execution_facade_lint"'
)
RUST_GATES_CONTENT="$(<"$RUST_GATES")"
for token in "${rust_quick_tokens[@]}"; do
  require_code_token "$RUST_GATES_CONTENT" "$RUST_GATES" "$token"
done

rust_full_tokens=(
  'run_rust_logged_or_exit "rust_clippy"'
  'cargo clippy --workspace --all-targets --all-features -- -D warnings'
  'record_rust_test_runner_fallback \'
  '"repo_contract_requires_cargo_doctests_and_shared_state"'
  'run_smoke_cargo_test_gate "rust_tests_smoke"'
  'run_logged_or_exit "execution_facade_lint"'
)
for token in "${rust_full_tokens[@]}"; do
  require_code_token "$RUST_GATES_CONTENT" "$RUST_GATES" "$token"
done

if contains_literal_token "$RUST_GATES_CONTENT" 'warn "Skipping clippy in quick mode"'; then
  fail "quick Rust gates must not skip rust_clippy"
fi

if contains_literal_token "$RUST_GATES_CONTENT" 'cargo nextest run --workspace --all-features --locked'; then
  fail "rust gates must not treat cargo nextest run as an authoritative full-test path"
fi

if contains_literal_token "$RUST_GATES_CONTENT" 'cargo nextest run --workspace --lib --locked'; then
  fail "rust gates must not treat cargo nextest run as an authoritative quick-test path"
fi

py_tokens=(
  'run_logged_or_exit "python_ruff_check"'
  'run_logged "python_pytest_quick"'
  'run_logged_or_exit "python_pytest_full"'
  'run_logged "python_mypy"'
)
PY_GATES_CONTENT="$(<"$PY_GATES")"
for token in "${py_tokens[@]}"; do
  require_code_token "$PY_GATES_CONTENT" "$PY_GATES" "$token"
done

node_tokens=(
  'run_logged_or_exit "node_lint"'
  'run_logged_or_exit "node_typecheck"'
  'run_logged_or_exit "node_test"'
)
NODE_GATES_CONTENT="$(<"$NODE_GATES")"
for token in "${node_tokens[@]}"; do
  require_code_token "$NODE_GATES_CONTENT" "$NODE_GATES" "$token"
done

echo "PASS: verify gate contract check"
