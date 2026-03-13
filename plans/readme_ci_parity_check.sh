#!/usr/bin/env bash
set -euo pipefail

ROOT="${README_CI_PARITY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

README="README.md"
CI_WORKFLOW=".github/workflows/ci.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

emit_pattern_hits() {
  local file="$1"
  local pattern="$2"

  grep -HEn -- "$pattern" "$file" >&2 || true
}

fail_with_pattern_hits() {
  local message="$1"
  local file="$2"
  local pattern="$3"

  echo "FAIL: $message" >&2
  emit_pattern_hits "$file" "$pattern"
  exit 1
}

list_ci_jobs() {
  local jobs=""

  jobs="$(
    awk '
      /^jobs:/ {in_jobs=1; next}
      in_jobs && /^[^[:space:]]/ {exit}
      in_jobs && /^  [A-Za-z0-9_-]+:/ {
        job=$1
        sub(/:$/, "", job)
        print job
      }
    ' "$CI_WORKFLOW" | paste -sd' ' -
  )"

  if [[ -n "$jobs" ]]; then
    echo "$jobs"
  else
    echo "<none>"
  fi
}

fail_missing_job_section() {
  local job_name="$1"

  echo "FAIL: unable to parse $job_name job from $CI_WORKFLOW" >&2
  echo "discovered jobs: $(list_ci_jobs)" >&2
  exit 1
}

extract_job_section() {
  local job_name="$1"

  awk -v job_name="$job_name" '
    $0 ~ ("^  " job_name ":") {in_job=1}
    in_job && $0 ~ /^  [A-Za-z0-9_-]+:/ && $0 !~ ("^  " job_name ":") {exit}
    in_job {print}
  ' "$CI_WORKFLOW"
}

require_file_token() {
  local file="$1"
  local token="$2"
  if ! grep -Fq -- "$token" "$file"; then
    fail "$file missing required token: $token"
  fi
}

forbid_file_regex() {
  local file="$1"
  local pattern="$2"
  local reason="$3"
  if grep -Eq "$pattern" "$file"; then
    fail_with_pattern_hits "$file contains forbidden reference ($reason): $pattern" "$file" "$pattern"
  fi
}

for path in "$README" "$CI_WORKFLOW"; do
  [[ -f "$path" ]] || fail "missing required file: $path"
done

# README must advertise canonical verify entrypoints and review step.
require_file_token "$README" "# opus-trader"
require_file_token "$README" "./plans/verify.sh quick"
require_file_token "$README" "./plans/verify.sh full"
require_file_token "$README" "./plans/codex_review_let_pass.sh"

# README must not advertise legacy or non-canonical workflow commands.
forbid_file_regex "$README" '(^|[^.[:alnum:]_])\./verify\.sh([[:space:]]|$)' "non-canonical verify entrypoint"
forbid_file_regex "$README" 'ralph-verify-push|workflow_acceptance|(^|[^[:alnum:]_])ralph([^[:alnum:]_]|$)' "legacy workflow command"
forbid_file_regex "$README" '(^|[^[:alnum:]_])bootstrap([^[:alnum:]_]|$)' "legacy bootstrap flow"

verify_section="$(extract_job_section verify)"

[[ -n "$verify_section" ]] || fail_missing_job_section "verify"

require_section_token() {
  local token="$1"
  if ! printf '%s\n' "$verify_section" | grep -Fq -- "$token"; then
    fail "$CI_WORKFLOW verify job missing required token: $token"
  fi
}

forbid_section_regex() {
  local pattern="$1"
  local reason="$2"
  if printf '%s\n' "$verify_section" | grep -Eq "$pattern"; then
    fail_with_pattern_hits "$CI_WORKFLOW verify job contains forbidden reference ($reason): $pattern" "$CI_WORKFLOW" "$pattern"
  fi
}

# Verify job must execute canonical full verify and upload log artifacts.
require_section_token "name: Verify (single source of truth)"
require_section_token "./plans/verify.sh full"
require_section_token "verify_output.log"
require_section_token "name: Upload verify log"

# Verify job must not invoke legacy/non-canonical checks directly.
forbid_section_regex '(^|[^.[:alnum:]_])\./verify\.sh([[:space:]]|$)' "non-canonical verify entrypoint"
forbid_section_regex '\./plans/verify\.sh[[:space:]]+quick' "quick mode in CI verify job"
forbid_section_regex 'ralph-verify-push|workflow_acceptance|(^|[^[:alnum:]_])ralph([^[:alnum:]_]|$)' "legacy workflow command"
forbid_section_regex 'scripts/check_(contract_crossrefs|arch_flows|state_machines|global_invariants|time_freshness|crash_matrix|crash_replay_idempotency|reconciliation_matrix|csp_trace)\.py' "duplicate contract checks outside verify"

# Workflow must re-run gate checks when review/comment activity lands after gate pass.
require_file_token "$CI_WORKFLOW" "pull_request_review:"
require_file_token "$CI_WORKFLOW" "pull_request_review_comment:"
require_file_token "$CI_WORKFLOW" "issue_comment:"

prd_story_gate_section="$(extract_job_section prd-story-gate)"

[[ -n "$prd_story_gate_section" ]] || fail_missing_job_section "prd-story-gate"

require_prd_story_gate_token() {
  local token="$1"
  if ! printf '%s\n' "$prd_story_gate_section" | grep -Fq -- "$token"; then
    fail "$CI_WORKFLOW prd-story-gate job missing required token: $token"
  fi
}

forbid_prd_story_gate_regex() {
  local pattern="$1"
  local reason="$2"
  if printf '%s\n' "$prd_story_gate_section" | grep -Eq -- "$pattern"; then
    fail_with_pattern_hits "$CI_WORKFLOW prd-story-gate job contains forbidden reference ($reason): $pattern" "$CI_WORKFLOW" "$pattern"
  fi
}

# prd-story-gate must be event-driven and target PR comments/reviews.
require_prd_story_gate_token "github.event_name == 'pull_request_review'"
require_prd_story_gate_token "github.event_name == 'pull_request_review_comment'"
require_prd_story_gate_token "github.event_name == 'issue_comment' && github.event.issue.pull_request"
require_prd_story_gate_token 'PR_NUMBER: ${{ github.event.pull_request.number || github.event.issue.number }}'
require_prd_story_gate_token '--pr "${PR_NUMBER}"'
require_prd_story_gate_token "--bot-comments-mode block"
require_prd_story_gate_token "--require-copilot-review"
require_prd_story_gate_token "--aftercare-ack-mode \"\${aftercare_ack_mode}\""

# PRD gate flow requires explicit story context and dedicated post-pass check.
require_prd_story_gate_token '--story "${story_id}"'

# needs can skip this job on comment/review events when upstream jobs are pull_request-only.
forbid_prd_story_gate_regex '^[[:space:]]+needs:' "prd-story-gate must not depend on pull_request-only jobs"

echo "PASS: README/CI verify parity check"
