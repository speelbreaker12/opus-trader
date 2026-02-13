#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

README="README.md"
CI_WORKFLOW=".github/workflows/ci.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
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
    fail "$file contains forbidden reference ($reason): $pattern"
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

verify_section="$(
  awk '
    /^  verify:/ {in_verify=1}
    in_verify && /^  [A-Za-z0-9_-]+:/ && $0 !~ /^  verify:/ {exit}
    in_verify {print}
  ' "$CI_WORKFLOW"
)"

[[ -n "$verify_section" ]] || fail "unable to parse verify job from $CI_WORKFLOW"

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
    fail "$CI_WORKFLOW verify job contains forbidden reference ($reason): $pattern"
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

pr_gate_section="$(
  awk '
    /^  pr-gate-enforced:/ {in_gate=1}
    in_gate && /^  [A-Za-z0-9_-]+:/ && $0 !~ /^  pr-gate-enforced:/ {exit}
    in_gate {print}
  ' "$CI_WORKFLOW"
)"

[[ -n "$pr_gate_section" ]] || fail "unable to parse pr-gate-enforced job from $CI_WORKFLOW"

require_pr_gate_token() {
  local token="$1"
  if ! printf '%s\n' "$pr_gate_section" | grep -Fq -- "$token"; then
    fail "$CI_WORKFLOW pr-gate-enforced job missing required token: $token"
  fi
}

forbid_pr_gate_regex() {
  local pattern="$1"
  local reason="$2"
  if printf '%s\n' "$pr_gate_section" | grep -Eq "$pattern"; then
    fail "$CI_WORKFLOW pr-gate-enforced job contains forbidden reference ($reason): $pattern"
  fi
}

require_pr_gate_token "github.event_name == 'pull_request_review'"
require_pr_gate_token "github.event_name == 'pull_request_review_comment'"
require_pr_gate_token "github.event_name == 'issue_comment' && github.event.issue.pull_request"
require_pr_gate_token 'PR_NUMBER: ${{ github.event.pull_request.number || github.event.issue.number }}'
require_pr_gate_token '--pr "${PR_NUMBER}"'
require_pr_gate_token "--bot-comments-mode block"
require_pr_gate_token "--require-aftercare-ack"
require_pr_gate_token "--require-copilot-review"

# needs can skip this job on comment/review events when upstream jobs are pull_request-only.
forbid_pr_gate_regex '^[[:space:]]+needs:' "pr-gate must not depend on pull_request-only jobs"

echo "PASS: README/CI verify parity check"
