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

[[ -f "$prompt_file" ]] || fail "missing prompt file: $prompt_file"
[[ -f "$schema_file" ]] || fail "missing schema file: $schema_file"
[[ -f "$workflow_file" ]] || fail "missing workflow file: $workflow_file"

grep -Fq -- "- loss_mode" "$prompt_file" \
  || fail "auditor prompt missing loss_mode required field"

failure_mode_schema_line="$(grep -o 'failure_mode entries must be stall|hang|backpressure|missing|stale|parse_error' "$schema_file" | head -n 1)"
[[ -n "$failure_mode_schema_line" ]] || fail "missing failure_mode schema line"
grep -Fq "$failure_mode_schema_line" "$prompt_file" \
  || fail "auditor prompt failure_mode enum drifted from schema"

grep -Eq '^9\. ' "$workflow_file" \
  || fail "workflow guide missing step 9 in recommended story loop"
grep -Eq '^10\. ' "$workflow_file" \
  || fail "workflow guide missing step 10 in recommended story loop"

echo "test_prd_auditor_prompt.sh: ok"
