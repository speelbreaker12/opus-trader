#!/usr/bin/env bash
set -euo pipefail

# Local convenience for workflow maintenance. CI still runs ./plans/verify.sh.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

check_script() {
  local path="$1"
  if [[ -f "$path" ]]; then
    bash -n "$path"
  fi
}

check_script "plans/verify.sh"
check_script "plans/verify_fork.sh"
check_script "plans/verify_gate_contract_check.sh"
check_script "plans/preflight.sh"
check_script "plans/legacy_layout_guard.sh"
check_script "plans/readme_ci_parity_check.sh"
check_script "plans/slice_completion_review_guard.sh"
check_script "plans/slice_completion_enforce.sh"
check_script "plans/slice_review_gate.sh"
check_script "plans/story_review_findings_guard.sh"
check_script "plans/codex_review_logged.sh"
check_script "plans/kimi_review_logged.sh"
check_script "plans/code_review_expert_logged.sh"
check_script "plans/thinking_review_logged.sh"
check_script "plans/codex_review_digest.sh"
check_script "plans/pr_gate.sh"
check_script "plans/pre_pr_review_gate.sh"
check_script "plans/prd_set_pass.sh"
check_script "plans/self_review_logged.sh"
check_script "plans/story_postmortem_logged.sh"
check_script "plans/story_review_gate.sh"
check_script "plans/stoic_cli_invariant_check.sh"
check_script "plans/workflow_quick_step.sh"

./plans/workflow_contract_gate.sh
./plans/verify.sh quick

if [[ "${RUN_REPO_VERIFY_FULL:-0}" == "1" ]]; then
  ./plans/verify.sh full
fi
