#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
allowlist="$ROOT/plans/workflow_files_allowlist.txt"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$allowlist" ]] || fail "missing allowlist"
[[ -s "$allowlist" ]] || fail "allowlist empty"

if grep -nE '^[[:space:]]*$|^[[:space:]]*#' "$allowlist"; then
  fail "blank/comment line"
fi
if grep -nE '^[[:space:]]+|[[:space:]]+$' "$allowlist"; then
  fail "leading/trailing whitespace"
fi
if grep -nE '^\./|/$|^/|\.\.' "$allowlist"; then
  fail "invalid path"
fi

LC_ALL=C sort -c "$allowlist" || fail "allowlist not sorted"
dupes="$(sort "$allowlist" | uniq -d || true)"
[[ -z "$dupes" ]] || fail "duplicate entries: $dupes"

required=(
  .githooks/pre-commit
  .githooks/pre-push
  .github/pull_request_template.md
  .github/workflows/ci.yml
  AGENTS.md
  IMPLEMENTATION_PLAN.md
  POLICY.md
  docs/contract_anchors.md
  docs/contract_kernel.json
  docs/validation_rules.md
  plans/autofix.sh
  plans/artifact_lint.sh
  plans/bidi_control_guard.sh
  plans/check_contract_at_wording_drift.sh
  plans/check_contract_change_ledger.sh
  plans/check_skip_entrypoint.sh
  plans/code_review_expert_attest.sh
  plans/code_review_expert_guard.sh
  plans/codex_review_digest.sh
  plans/codex_review_let_pass.sh
  plans/codex_review_logged.sh
  plans/config/gate_sunsets.sh
  plans/contract_check.sh
  plans/contract_coverage_matrix.py
  plans/contract_coverage_promote.sh
  plans/contract_review_emit.sh
  plans/contract_review_validate.sh
  plans/execution_facade_symbols.txt
  plans/external_review_generic.sh
  plans/fork_attestation_mirror.sh
  plans/fork_attestation_remediation_verify.sh
  plans/init.sh
  plans/legacy_layout_guard.sh
  plans/lint_execution_facade.sh
  plans/live_enable_preflight.sh
  plans/lib/adversarial_gate.sh
  plans/lib/hash_utils.sh
  plans/pr_gate.sh
  plans/prd_audit_check.sh
  plans/prd_audit_merge.py
  plans/prd_audit_merge.sh
  plans/prd_cache_check.py
  plans/prd_cache_update.py
  plans/prd_gate.sh
  plans/prd_preflight.sh
  plans/postmortem_template.md
  plans/prd_set_pass.sh
  plans/pre_pr_review_gate.sh
  plans/preflight.sh
  plans/premortem_path_guard.sh
  plans/readme_ci_parity_check.sh
  plans/recon_bundle.sh
  plans/recon_doc_budget.sh
  plans/recon_evidence_ledger.sh
  plans/recon_operator_run.sh
  plans/recon_run_card_template.md
  plans/recon_trace.sh
  plans/recon_precheck.sh
  plans/recon_prompt_guard.sh
  plans/slice_execute_guard.sh
  plans/review_logged.sh
  plans/review_resolution_template.md
  plans/schemas/fork_attestation_remediation.schema.json
  plans/self_review_logged.sh
  plans/slice_completion_enforce.sh
  plans/slice_completion_review_guard.sh
  plans/slice_review_gate.sh
  plans/stoic_cli_invariant_check.sh
  plans/toggle_policy_check.sh
  plans/ssot_lint.sh
  plans/story_postmortem_logged.sh
  plans/story_review_findings_guard.sh
  plans/story_verify_allowlist.txt
  plans/story_verify_allowlist_check.sh
  plans/story_verify_allowlist_lint.sh
  plans/story_verify_allowlist_suggest.sh
  plans/tests/test_audit_parallel_empty_cache_arrays.sh
  plans/tests/test_codex_review_digest.sh
  plans/tests/test_codex_review_logged.sh
  plans/tests/test_contract_at_parity_invalid_refs.sh
  plans/tests/test_contract_at_wording_drift.sh
  plans/tests/test_contract_change_ledger.sh
  plans/tests/test_contract_kernel_drift_message.sh
  plans/tests/test_contract_profile_parity.sh
  plans/tests/test_contract_at_parity_invalid_refs.sh
  plans/tests/test_contract_review_emit.sh
  plans/tests/test_adversarial_gate.sh
  plans/tests/test_artifact_lint.sh
  plans/tests/test_bidi_control_guard.sh
  plans/tests/test_code_review_expert_guard.sh
  plans/tests/test_external_review_generic.sh
  plans/tests/test_fail_closed_gate_map_paths.sh
  plans/tests/test_guard_no_command_substitution.sh
  plans/tests/test_fork_attestation_mirror.sh
  plans/tests/test_fork_attestation_remediation_verify.sh
  plans/tests/test_lint_execution_facade.sh
  plans/tests/test_live_enable_preflight.sh
  plans/tests/test_pr_gate.sh
  plans/tests/test_prd_cache.sh
  plans/tests/test_prd_set_pass.sh
  plans/tests/test_preflight_fixture_profiles.sh
  plans/tests/test_preflight_diagnostics.sh
  plans/tests/test_preflight_shell_syntax_cross_file_masking.sh
  plans/tests/test_preflight_shell_syntax_setup_failure.sh
  plans/tests/test_pre_pr_review_gate.sh
  plans/tests/test_recon_bundle.sh
  plans/tests/test_recon_doc_budget.sh
  plans/tests/test_recon_evidence_ledger.sh
  plans/tests/test_recon_handoff_sources.sh
  plans/tests/test_preflight_fixture_timeout_controls.sh
  plans/tests/test_premortem_gate_trading_hard_gate.sh
  plans/tests/test_premortem_path_guard.sh
  plans/tests/test_premortem_ready_ownership_conflict.sh
  plans/tests/test_recon_operator_runner.sh
  plans/tests/test_recon_operator_trace.sh
  plans/tests/test_recon_scoreboard.sh
  plans/tests/test_recon_precheck.sh
  plans/tests/test_recon_prompt_guard.sh
  plans/tests/test_review_logged_prompt_literalization.sh
  plans/tests/test_run_prd_auditor_invocation.sh
  plans/tests/test_run_prd_auditor_timeout_fallback.sh
  plans/tests/test_slice_execute_guard.sh
  plans/tests/test_review_logged_timeout_binary_unavailable.sh
  plans/tests/test_review_logged_timeout_fallback.sh
  plans/tests/test_review_logged_timeout_retry_noncodex.sh
  plans/tests/test_rust_gates_quick_clippy.sh
  plans/tests/test_slice_completion_enforce.sh
  plans/tests/test_slice_completion_review_guard.sh
  plans/tests/test_slice_review_gate.sh
  plans/tests/test_stoic_cli_invariant_check.sh
  plans/tests/test_story_review_gate.sh
  plans/tests/test_story_review_findings_guard.sh
  plans/tests/test_verify_timeout_policy.sh
  plans/tests/test_verify_fork_guardrails.sh
  plans/tests/test_verify_gate_contract_check_batching.sh
  plans/tests/test_rust_gates_smoke_targets.sh
  plans/tests/test_wf_step_path_signal_scan.sh
  plans/tests/test_wf_step_review_provenance.sh
  plans/tests/test_wf_step_stop_on_blocker.sh
  plans/tests/test_workflow_quick_step.sh
  plans/tests/test_toggle_policy_check.sh
  plans/verify.sh
  plans/verify_day.sh
  plans/verify_gate_contract_check.sh
  plans/wf_step.sh
  plans/workflow_contract_gate.sh
  plans/workflow_contract_map.json
  plans/workflow_quick_step.sh
  plans/workflow_verify.sh
  plans/workflow_files_allowlist.txt
  plans/tests/test_workflow_allowlist_coverage.sh
  plans/lib/node_gates.sh
  plans/lib/python_gates.sh
  plans/lib/rust_gates.sh
  plans/lib/status_reason_codegen_gate.sh
  plans/lib/verify_checkpoint.sh
  plans/ci/requirements-crossref.txt
  plans/ci/requirements-verify.txt
  plans/crossref_burnin_check.sh
  plans/crossref_ci_strict
  plans/crossref_execution_invariants.yaml
  plans/crossref_gate.sh
  plans/evidence_sources.txt
  plans/global_manual_allowlist.json
  plans/lib/verify_utils.sh
  plans/schemas/crossref_execution_invariants.schema.json
  plans/schemas/verify_checkpoint.schema.json
  plans/tests/test_crossref_gate.sh
  plans/tests/test_crossref_invariants.sh
  plans/tests/test_roadmap_evidence_audit.sh
  plans/validate_recon_step_report.py
  plans/validate_crossref_invariants.py
  tools/at_coverage_report.py
  tools/at_parser.py
  tools/check_lag_ids.py
  tools/check_status_reason_string_leaks.py
  tools/roadmap_evidence_audit.py
  tools/tests/test_check_lag_ids.py
  tools/tests/test_status_reason_string_leaks.py
  scripts/build_contract_kernel.py
  scripts/check_arch_flows.py
  scripts/check_contract_crossrefs.py
  scripts/check_contract_kernel.py
  scripts/check_crash_matrix.py
  scripts/check_crash_replay_idempotency.py
  scripts/check_csp_trace.py
  scripts/check_global_invariants.py
  scripts/check_reconciliation_matrix.py
  scripts/check_state_machines.py
  scripts/check_time_freshness.py
  scripts/check_vq_evidence.py
  scripts/contract_kernel_lib.py
  scripts/extract_contract_excerpts.py
  scripts/generate_impact_report.py
  scripts/test_contract_kernel.py
  specs/CONTRACT.md
  specs/IMPLEMENTATION_PLAN.md
  specs/POLICY.md
  specs/SOURCE_OF_TRUTH.md
  specs/TRACE.yaml
  specs/WORKFLOW_CONTRACT.md
  specs/schemas/recon/recon_step_report.schema.json
  specs/schemas/recon/recon_trace_receipt.schema.json
  specs/vendor_docs/rust/CRATES_OF_INTEREST.yaml
  tools/ci/check_contract_profile_map_parity.py
  tools/ci/check_contract_profiles.py
  tools/ci/lint_pr_template_sections.py
  tools/vendor_docs_lint_rust.py
  verify.sh
)

for path in "${required[@]}"; do
  grep -Fxq "$path" "$allowlist" || fail "missing $path"
done
