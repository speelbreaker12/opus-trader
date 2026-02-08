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
check_script "plans/prd_set_pass.sh"

./plans/workflow_contract_gate.sh
./plans/verify.sh quick

if [[ "${RUN_REPO_VERIFY_FULL:-0}" == "1" ]]; then
  ./plans/verify.sh full
fi
