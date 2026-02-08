#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOC="specs/WORKFLOW_CONTRACT.md"
VERIFY="plans/verify_fork.sh"
RUST_GATES="plans/lib/rust_gates.sh"
PY_GATES="plans/lib/python_gates.sh"
NODE_GATES="plans/lib/node_gates.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for f in "$DOC" "$VERIFY" "$RUST_GATES" "$PY_GATES" "$NODE_GATES"; do
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
  if ! printf '%s\n' "$section_text" | grep -Fq "$token"; then
    fail "workflow contract missing token '$token' in expected gate section"
  fi
}

require_code_token() {
  local file="$1"
  local token="$2"
  if ! grep -Fq "$token" "$file"; then
    fail "missing code token '$token' in $file"
  fi
}

quick_section="$(extract_section "$DOC" "#### QUICK (developer iteration)" "#### FULL (story completion)")"
full_section="$(extract_section "$DOC" "#### FULL (story completion)" "### 7.5 Local full is allowed")"

[[ -n "$quick_section" ]] || fail "unable to parse QUICK gate section from $DOC"
[[ -n "$full_section" ]] || fail "unable to parse FULL gate section from $DOC"

# Docs: quick gate coverage.
quick_tokens=(
  preflight
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
  rust_fmt
  rust_tests_quick
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
  'run_logged_or_exit "preflight"'
  'run_logged_or_exit "contract_crossrefs"'
  'run_logged_or_exit "arch_flows"'
  'run_logged_or_exit "state_machines"'
  'run_logged_or_exit "global_invariants"'
  'run_logged_or_exit "time_freshness"'
  'run_logged_or_exit "crash_matrix"'
  'run_logged_or_exit "crash_replay_idempotency"'
  'run_logged_or_exit "reconciliation_matrix"'
  'run_logged_or_exit "csp_trace"'
  'status_fixture_'
)

for token in "${verify_tokens[@]}"; do
  require_code_token "$VERIFY" "$token"
done

require_code_token "$VERIFY" 'run_logged_or_exit "contract_coverage"'
require_code_token "$VERIFY" 'Skipping contract_coverage in quick mode (full-only gate)'

# Stack gate scripts: ensure quick/full gate names are present.
rust_tokens=(
  'run_logged_or_exit "rust_fmt"'
  'run_logged_or_exit "rust_clippy"'
  'run_logged_or_exit "rust_tests_full"'
  'run_logged_or_exit "rust_tests_quick"'
)
for token in "${rust_tokens[@]}"; do
  require_code_token "$RUST_GATES" "$token"
done

py_tokens=(
  'run_logged_or_exit "python_ruff_check"'
  'run_logged "python_pytest_quick"'
  'run_logged_or_exit "python_pytest_full"'
  'run_logged "python_mypy"'
)
for token in "${py_tokens[@]}"; do
  require_code_token "$PY_GATES" "$token"
done

node_tokens=(
  'run_logged_or_exit "node_lint"'
  'run_logged_or_exit "node_typecheck"'
  'run_logged_or_exit "node_test"'
)
for token in "${node_tokens[@]}"; do
  require_code_token "$NODE_GATES" "$token"
done

echo "PASS: verify gate contract check"
