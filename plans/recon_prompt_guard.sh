#!/usr/bin/env bash
set -euo pipefail

ROOT="${RECON_PROMPT_GUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

r1_prompt="$ROOT/plans/step_prompts/recon/r1_audit.md"
r1_appendix_prompt="$ROOT/plans/prompts/slice_reconcile_r1_audit.md"
recon_index="$ROOT/plans/step_prompts/recon/INDEX.md"
recon_redirect="$ROOT/plans/prompts/reconcil.md"
slice_execute_skill="$ROOT/SKILLS/slice-execute.md"

legacy_re='RUNBOOK_PREMORTEM_RECON|PREMORTEM_RECON_POLICY|PREMORTEM_RECON_ANTIPATTERNS|PREMORTEM_RECON_METRICS|PREMORTEM_RECONCILIATION_PROCESS'

fail() {
  local code="$1"
  local message="$2"
  echo "FAIL: ${code}: ${message}" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "MISSING_TOOL" "$tool"
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

scan_rg() {
  local pattern="$1"
  shift
  local output=""
  local rc=0

  set +e
  output="$(rg -n "$pattern" "$@" 2>&1)"
  rc=$?
  set -e

  case "$rc" in
    0|1)
      printf '%s' "$output"
      ;;
    *)
      fail "SCANNER_ERROR" "rg rc=$rc pattern=$pattern output=$output"
      ;;
  esac
}

require_file "$r1_prompt"
require_file "$r1_appendix_prompt"
require_file "$recon_index"
require_file "$recon_redirect"
require_file "$slice_execute_skill"
require_tool rg

# Canonical source references must remain anchored to PROTOCOL/REFERENCE.
require_contains "$recon_index" "reviews/reconciliations/PROTOCOL.md" "CANONICAL_REFERENCE_MISSING"
require_contains "$recon_index" "reviews/reconciliations/REFERENCE.md" "CANONICAL_REFERENCE_MISSING"
require_contains "$recon_redirect" "reviews/reconciliations/PROTOCOL.md" "CANONICAL_REFERENCE_MISSING"
require_contains "$recon_redirect" "reviews/reconciliations/REFERENCE.md" "CANONICAL_REFERENCE_MISSING"

legacy_ref_hits="$(scan_rg "$legacy_re" "$recon_index" "$recon_redirect")"
if [[ -n "$legacy_ref_hits" ]]; then
  fail "LEGACY_REFERENCE_DRIFT" "$legacy_ref_hits"
fi

# R1 prompts must remain explicitly read-only.
require_contains "$r1_prompt" "R1 READ-ONLY AUDIT" "READ_ONLY_LABEL_MISSING"
require_contains "$r1_prompt" "No code edits in this step." "READ_ONLY_GUARD_MISSING"
require_contains "$r1_prompt" "TASK (read-only" "READ_ONLY_TASK_MISSING"
require_contains "$r1_prompt" "Do NOT edit production code or tests" "READ_ONLY_PROHIBITION_MISSING"
require_contains "$r1_prompt" "Read the premortem §10 STOPLIGHT first." "PREMORTEM_STOPLIGHT_DRIFT"
require_contains "$r1_prompt" "READY FOR IMPLEMENT GATE" "NEXT_STEP_DRIFT"

require_contains "$r1_appendix_prompt" "read-only implementation audit" "READ_ONLY_LABEL_MISSING"
require_contains "$r1_appendix_prompt" "Do NOT write or modify production code, tests, PRD, or review artifacts in this step." "READ_ONLY_PROHIBITION_MISSING"
require_contains "$r1_appendix_prompt" "TASK (READ-ONLY AUDIT)" "READ_ONLY_TASK_MISSING"
require_contains "$r1_appendix_prompt" "READY FOR IMPLEMENT GATE" "NEXT_STEP_DRIFT"
require_contains "$r1_appendix_prompt" 'Trading lens = `BLOCKING` requires `GATE: NO-GO`.' "TRADING_LENS_GATE_BINDING_MISSING"
require_contains "$r1_appendix_prompt" 'temporary files under `/tmp` for the read-only integrity check are allowed' "TMP_FILE_ALLOWANCE_MISSING"

# R1 surrogate fallback to legacy premortem docs must stay disallowed.
require_contains "$r1_appendix_prompt" "There is no surrogate or fallback path for R1." "SURROGATE_POLICY_MISSING"

require_contains "$slice_execute_skill" "At least one case from the premortem §5 (wrong impl gate) — the tightened AT" "WRONG_IMPL_SECTION_DRIFT"
require_contains "$slice_execute_skill" "Premortem §5 wrong impls are blocked by tightened ATs?" "WRONG_IMPL_SELFCHECK_DRIFT"
require_contains "$slice_execute_skill" "GO (premortem STOPLIGHT was GREEN/YELLOW-addressed)" "PREMORTEM_OUTPUT_DRIFT"
require_contains "$slice_execute_skill" "if the premortem is missing, mechanically invalid, or RED, stop" "PREMORTEM_HARD_CONSTRAINT_DRIFT"

next_step_hits="$(scan_rg "READY FOR SELF_REVIEW" "$r1_prompt" "$r1_appendix_prompt")"
if [[ -n "$next_step_hits" ]]; then
  fail "NEXT_STEP_DRIFT" "$next_step_hits"
fi

r1_legacy_hits="$(scan_rg "$legacy_re" "$r1_prompt" "$r1_appendix_prompt")"
if [[ -n "$r1_legacy_hits" ]]; then
  fail "R1_SURROGATE_PATH_FOUND" "$r1_legacy_hits"
fi

preflight_wording_hits="$(scan_rg \
  "preflight was GREEN/YELLOW-addressed|if preflight is missing or RED|Fix preflight gaps first|Do NOT create new files in any directory" \
  "$slice_execute_skill" "$r1_prompt" "$r1_appendix_prompt")"
if [[ -n "$preflight_wording_hits" ]]; then
  fail "PREMORTEM_WORDING_DRIFT" "$preflight_wording_hits"
fi

echo "PASS: recon prompt guard"
