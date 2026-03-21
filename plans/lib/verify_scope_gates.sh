#!/usr/bin/env bash

if [[ -n "${__VERIFY_SCOPE_GATES_SOURCED:-}" ]]; then
  return 0
fi
__VERIFY_SCOPE_GATES_SOURCED=1

build_contract_crossrefs_cmd() {
  CONTRACT_CROSSREFS_CMD=(
    "$PYTHON_BIN" scripts/check_contract_crossrefs.py
    --contract specs/CONTRACT.md
    --check-at
    --strict
    --include-bare-section-refs
  )
}

build_csp_trace_cmd() {
  local strict_mode="${1:-auto}"

  CSP_TRACE_CMD=(
    "$PYTHON_BIN" scripts/check_csp_trace.py
    --contract specs/CONTRACT.md
    --trace specs/TRACE.yaml
  )

  case "$strict_mode" in
    auto)
      if declare -F should_enable_csp_strict >/dev/null 2>&1; then
        if should_enable_csp_strict "$VERIFY_BASE_REF"; then
          CSP_TRACE_CMD+=(--strict)
        fi
      fi
      ;;
    strict)
      CSP_TRACE_CMD+=(--strict)
      ;;
    relaxed) ;;
    *)
      fail "unknown csp trace strict mode: $strict_mode"
      ;;
  esac
}

run_contract_kernel_gate() {
  ensure_python
  if [[ -f "docs/contract_kernel.json" ]]; then
    run_logged_or_exit "contract_kernel" "$CONTRACT_KERNEL_TIMEOUT" \
      "$PYTHON_BIN" scripts/check_contract_kernel.py --kernel docs/contract_kernel.json
  fi
}

run_contract_change_ledger_gate() {
  run_logged_or_exit "contract_change_ledger" "$CONTRACT_KERNEL_TIMEOUT" \
    bash "$ROOT/plans/check_contract_change_ledger.sh" --base-ref "$VERIFY_BASE_REF" --contract specs/CONTRACT.md
}

start_parallel_contract_crossrefs_gate() {
  build_contract_crossrefs_cmd
  start_parallel_gate "contract_crossrefs" "$SPEC_LINT_TIMEOUT" "${CONTRACT_CROSSREFS_CMD[@]}"
}

run_contract_crossrefs_gate() {
  build_contract_crossrefs_cmd
  run_logged_or_exit "contract_crossrefs" "$SPEC_LINT_TIMEOUT" "${CONTRACT_CROSSREFS_CMD[@]}"
}

start_parallel_csp_trace_gate() {
  local strict_mode="${1:-auto}"
  build_csp_trace_cmd "$strict_mode"
  start_parallel_gate "csp_trace" "$CSP_TRACE_TIMEOUT" "${CSP_TRACE_CMD[@]}"
}

run_csp_trace_gate() {
  local strict_mode="${1:-auto}"
  build_csp_trace_cmd "$strict_mode"
  run_logged_or_exit "csp_trace" "$CSP_TRACE_TIMEOUT" "${CSP_TRACE_CMD[@]}"
}

check_workflow_scope_script_syntax() {
  local path="$1"
  if [[ -f "$path" ]]; then
    run_logged_or_exit "syntax_${path##*/}" "$SPEC_LINT_TIMEOUT" bash -n "$path"
  fi
}

run_workflow_contract_gate() {
  run_logged_or_exit "workflow_contract_gate" "$SPEC_LINT_TIMEOUT" \
    ./plans/workflow_contract_gate.sh
}

run_workflow_integration_test_gate() {
  local workflow_test="$1"
  local test_name="${workflow_test##*/}"
  local gate_name="wf_${test_name%.sh}"
  run_logged_or_exit "$gate_name" "$WORKFLOW_TEST_TIMEOUT" \
    bash "$workflow_test"
}

start_parallel_workflow_integration_test_gate() {
  local workflow_test="$1"
  local test_name="${workflow_test##*/}"
  local gate_name="wf_${test_name%.sh}"
  start_parallel_gate "$gate_name" "$WORKFLOW_TEST_TIMEOUT" \
    bash "$workflow_test"
}

run_workflow_allowlist_coverage_gate() {
  run_logged_or_exit "workflow_allowlist_coverage" "$WORKFLOW_TEST_TIMEOUT" \
    bash plans/tests/test_workflow_allowlist_coverage.sh
}

run_verify_accelerators_gate() {
  run_logged_or_exit "verify_accelerators" "$WORKFLOW_TEST_TIMEOUT" \
    bash plans/tests/test_verify_accelerators.sh
}

run_verify_timeout_policy_gate() {
  run_logged_or_exit "verify_timeout_policy" "$WORKFLOW_TEST_TIMEOUT" \
    bash plans/tests/test_verify_timeout_policy.sh
}

run_verify_gate_contract_check_batching_gate() {
  run_logged_or_exit "verify_gate_contract_check_batching" "$WORKFLOW_TEST_TIMEOUT" \
    bash plans/tests/test_verify_gate_contract_check_batching.sh
}

run_verify_fork_guardrails_gate() {
  run_logged_or_exit "verify_fork_guardrails" "$WORKFLOW_TEST_TIMEOUT" \
    bash plans/tests/test_verify_fork_guardrails.sh
}

run_verify_scope_gate() {
  run_logged_or_exit "verify_scope" "$WORKFLOW_TEST_TIMEOUT" \
    bash plans/tests/test_verify_scope.sh
}

run_workflow_scope_control_surface_checks() {
  check_workflow_scope_script_syntax "plans/verify.sh"
  check_workflow_scope_script_syntax "plans/verify_fork.sh"
  check_workflow_scope_script_syntax "plans/verify_scope.sh"
  check_workflow_scope_script_syntax "plans/workflow_verify.sh"
  check_workflow_scope_script_syntax "plans/lib/verify_env.sh"
  check_workflow_scope_script_syntax "plans/lib/verify_scope_gates.sh"
  check_workflow_scope_script_syntax "plans/lib/rust_gates.sh"
  check_workflow_scope_script_syntax "plans/tests/test_verify_scope.sh"
}

run_contract_scope_gates() {
  run_contract_kernel_gate
  run_contract_change_ledger_gate
  run_contract_crossrefs_gate
  run_csp_trace_gate auto
}

run_workflow_scope_gates() {
  run_workflow_scope_control_surface_checks
  run_workflow_contract_gate
  run_workflow_integration_test_gate "plans/tests/test_workflow_allowlist_coverage.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_accelerators.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_timeout_policy.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_gate_contract_check_batching.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_fork_guardrails.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_scope.sh"
}
