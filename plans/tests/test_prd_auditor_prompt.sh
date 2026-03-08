#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
prompt_file="$repo_root/prompts/auditor.md"
schema_file="$repo_root/plans/prd_schema_check.sh"
workflow_file="$repo_root/plans/PRD_WORKFLOW.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$prompt_file" ]] || fail "auditor prompt not found at $prompt_file"
[[ -f "$schema_file" ]] || fail "prd schema check not found at $schema_file"
[[ -f "$workflow_file" ]] || fail "PRD workflow doc not found at $workflow_file"

grep -Fq -- '- loss_mode ' "$prompt_file" \
  || fail "auditor prompt must list loss_mode in required item fields"

schema_failure_enum="$(sed -n 's/.*failure_mode entries must be \([^\"]*\)\".*/\1/p' "$schema_file" | tail -n 1)"
[[ -n "$schema_failure_enum" ]] || fail "could not extract failure_mode enum from schema"

expected_prompt_line="- failure_mode (string[]; entries must be $schema_failure_enum)"
grep -Fq -- "$expected_prompt_line" "$prompt_file" \
  || fail "auditor prompt failure_mode line must match schema enum"

rg -q '^9\. .*verify\.sh quick' "$workflow_file" \
  || fail "workflow recommended story loop is missing step 9"
rg -q '^10\. Sync with integration branch\.$' "$workflow_file" \
  || fail "workflow recommended story loop is missing step 10"

echo "test_prd_auditor_prompt.sh: ok"
