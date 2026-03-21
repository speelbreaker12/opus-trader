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

compute_csp_strict_changed_files() {
  local base_ref="$1"
  local changed=""
  if ! command -v git >/dev/null 2>&1; then
    printf '%s\n' "__CSP_STRICT_STATE__:git_unavailable"
    return 0
  fi

  if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    changed="$(
      {
        git diff --name-only "$base_ref"...HEAD 2>/dev/null || true
        git diff --name-only --cached 2>/dev/null || true
        git diff --name-only 2>/dev/null || true
      } | sed '/^$/d' | sort -u
    )"
  else
    changed="$(
      {
        git diff --name-only --cached 2>/dev/null || true
        git diff --name-only 2>/dev/null || true
      } | sed '/^$/d' | sort -u
    )"
  fi

  if [[ -z "$changed" ]]; then
    printf '%s\n' "__CSP_STRICT_STATE__:no_changes"
    return 0
  fi

  printf '%s\n' "__CSP_STRICT_STATE__:changes_present"
  printf '%s\n' "$changed"
}

CSP_STRICT_CHANGED_FILES_CACHE_READY=0
CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF=""
CSP_STRICT_CHANGED_FILES_CACHE=""

should_enable_csp_strict() {
  local base_ref="$1"
  local cache_state_line=""

  if [[ "$CSP_STRICT_CHANGED_FILES_CACHE_READY" == "0" || "$CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF" != "$base_ref" ]]; then
    CSP_STRICT_CHANGED_FILES_CACHE="$(compute_csp_strict_changed_files "$base_ref")"
    CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF="$base_ref"
    CSP_STRICT_CHANGED_FILES_CACHE_READY=1
  fi

  if [[ -z "$CSP_STRICT_CHANGED_FILES_CACHE" ]]; then
    return 1
  fi

  cache_state_line="${CSP_STRICT_CHANGED_FILES_CACHE%%$'\n'*}"
  case "$cache_state_line" in
    "__CSP_STRICT_STATE__:git_unavailable"|"__CSP_STRICT_STATE__:no_changes")
      return 1
      ;;
  esac

  if grep -Eq '(^|/)specs/CONTRACT\.md$|(^|/)specs/TRACE\.yaml$' <<< "$CSP_STRICT_CHANGED_FILES_CACHE"; then
    return 0
  fi

  return 1
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
      if should_enable_csp_strict "$VERIFY_BASE_REF"; then
        CSP_TRACE_CMD+=(--strict)
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
  run_workflow_integration_test_gate "plans/tests/test_pr_review_gate_hook.sh"
  run_workflow_integration_test_gate "plans/tests/test_review_command_wrappers.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_accelerators.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_timeout_policy.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_gate_contract_check_batching.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_fork_guardrails.sh"
  run_workflow_integration_test_gate "plans/tests/test_verify_scope.sh"
}
