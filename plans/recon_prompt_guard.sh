#!/usr/bin/env bash
set -euo pipefail

ROOT="${RECON_PROMPT_GUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

r1_prompt="$ROOT/plans/step_prompts/recon/r1_audit.md"
r1_appendix_prompt="$ROOT/plans/prompts/slice_reconcile_r1_audit.md"
recon_index="$ROOT/plans/step_prompts/recon/INDEX.md"
recon_redirect="$ROOT/plans/prompts/reconcil.md"

legacy_re='RUNBOOK_PREMORTEM_RECON|PREMORTEM_RECON_POLICY|PREMORTEM_RECON_ANTIPATTERNS|PREMORTEM_RECON_METRICS|PREMORTEM_RECONCILIATION_PROCESS'

fail() {
  local code="$1"
  local message="$2"
  echo "FAIL: ${code}: ${message}" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "MISSING_FILE" "$path"
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local code="$3"
  grep -Fq "$pattern" "$path" || fail "$code" "$path missing required token: $pattern"
}

require_file "$r1_prompt"
require_file "$r1_appendix_prompt"
require_file "$recon_index"
require_file "$recon_redirect"

# Canonical source references must remain anchored to PROTOCOL/REFERENCE.
require_contains "$recon_index" "reviews/reconciliations/PROTOCOL.md" "CANONICAL_REFERENCE_MISSING"
require_contains "$recon_index" "reviews/reconciliations/REFERENCE.md" "CANONICAL_REFERENCE_MISSING"
require_contains "$recon_redirect" "reviews/reconciliations/PROTOCOL.md" "CANONICAL_REFERENCE_MISSING"
require_contains "$recon_redirect" "reviews/reconciliations/REFERENCE.md" "CANONICAL_REFERENCE_MISSING"

legacy_ref_hits="$(rg -n "$legacy_re" "$recon_index" "$recon_redirect" || true)"
if [[ -n "$legacy_ref_hits" ]]; then
  fail "LEGACY_REFERENCE_DRIFT" "$legacy_ref_hits"
fi

# R1 prompts must remain explicitly read-only.
require_contains "$r1_prompt" "R1 READ-ONLY AUDIT" "READ_ONLY_LABEL_MISSING"
require_contains "$r1_prompt" "No code edits in this step." "READ_ONLY_GUARD_MISSING"
require_contains "$r1_prompt" "TASK (read-only" "READ_ONLY_TASK_MISSING"
require_contains "$r1_prompt" "Do NOT edit production code or tests" "READ_ONLY_PROHIBITION_MISSING"

require_contains "$r1_appendix_prompt" "read-only implementation audit" "READ_ONLY_LABEL_MISSING"
require_contains "$r1_appendix_prompt" "Do NOT write or modify production code, tests, PRD, or review artifacts in this step." "READ_ONLY_PROHIBITION_MISSING"
require_contains "$r1_appendix_prompt" "TASK (READ-ONLY AUDIT)" "READ_ONLY_TASK_MISSING"

# R1 surrogate fallback to legacy premortem docs must stay disallowed.
require_contains "$r1_appendix_prompt" "There is no surrogate or fallback path for R1." "SURROGATE_POLICY_MISSING"

r1_legacy_hits="$(rg -n "$legacy_re" "$r1_prompt" "$r1_appendix_prompt" || true)"
if [[ -n "$r1_legacy_hits" ]]; then
  fail "R1_SURROGATE_PATH_FOUND" "$r1_legacy_hits"
fi

echo "PASS: recon prompt guard"
