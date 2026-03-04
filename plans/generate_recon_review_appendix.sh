#!/usr/bin/env bash
set -euo pipefail

commit_ref="origin/main"
as_of_date="$(date -u +%F)"
doc_path=""

usage() {
  cat <<USAGE
Usage:
  plans/generate_recon_review_appendix.sh [--commit <git-ref>] [--date YYYY-MM-DD] [--update-doc <path>]

Examples:
  plans/generate_recon_review_appendix.sh --commit origin/main
  plans/generate_recon_review_appendix.sh --commit 4891fb8 --date 2026-03-04 --update-doc /Users/admin/Desktop/opus-trader/reviews/reconciliations/RECON_PROCESS_REVIEW.md
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      commit_ref="$2"
      shift 2
      ;;
    --date)
      as_of_date="$2"
      shift 2
      ;;
    --update-doc)
      doc_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
commit_sha="$(git rev-parse "$commit_ref")"
short_sha="${commit_sha:0:12}"

find_line() {
  local file_path="$1"
  local pattern="$2"
  local line
  line="$(git show "$commit_sha:$file_path" | nl -ba | rg -n -m1 "$pattern" | cut -d: -f1 || true)"
  if [[ -n "$line" ]]; then
    printf "%s:%s" "$file_path" "$line"
  else
    printf "%s:?" "$file_path"
  fi
}

line_count() {
  local file_path="$1"
  git show "$commit_sha:$file_path" | wc -l | tr -d ' '
}

# Normalized numeric counts
runbook_lines="$(line_count reviews/premortems/RUNBOOK_PREMORTEM_RECON.md)"
policy_lines="$(line_count reviews/premortems/PREMORTEM_RECON_POLICY.md)"
antip_lines="$(line_count reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md)"
metrics_lines="$(line_count reviews/premortems/PREMORTEM_RECON_METRICS.md)"
process_lines="$(line_count reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md)"
handoff_lines="$(line_count reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md)"
doc_total="$((runbook_lines + policy_lines + antip_lines + metrics_lines + process_lines + handoff_lines))"

recon_count="$(git ls-tree -r --name-only "$commit_sha" reviews/reconciliations | wc -l | tr -d ' ')"
prem_count="$(git ls-tree -r --name-only "$commit_sha" reviews/premortems | wc -l | tr -d ' ')"
total_count="$((recon_count + prem_count))"
prompt_cards_count="$(git ls-tree -r --name-only "$commit_sha" plans/step_prompts/recon | rg -v '/INDEX\.md$' | wc -l | tr -d ' ')"

c15_status="CONFIRMED"
if [[ "$doc_total" -lt 3920 || "$doc_total" -gt 4010 ]]; then
  c15_status="PARTIAL"
fi

c16_status="CONFIRMED"
if [[ "$prompt_cards_count" -ne 9 ]]; then
  c16_status="CONTRADICTED"
fi

c17_status="CONTRADICTED"
if [[ "$recon_count" -eq 162 && "$prem_count" -eq 41 ]]; then
  c17_status="CONFIRMED"
fi

c26_status="CONTRADICTED"
if git show "$commit_sha:plans/prd_set_pass.sh" | rg -q -- '--dry-run'; then
  c26_status="CONFIRMED"
fi

# Evidence anchors
c01_ev="$(find_line reviews/reconciliations/S2/SUMMARY.md '\\*\\*TOTAL\\*\\*'); $(find_line reviews/reconciliations/S2/SUMMARY.md 'Estimated wall time')"
c02_ev="$(find_line reviews/reconciliations/S2/SUMMARY.md 'Process:code ratio')"
c03_ev="$(find_line reviews/reconciliations/slice1/STRATEGIC_REVIEW_R5.md 'H2:'); $(find_line reviews/reconciliations/slice1/SUMMARY.md 'R7b H2')"
c04_ev="$(find_line reviews/reconciliations/slice1/LSP_CALL_CHAIN_CHECK.md '58%')"
c05_ev="$(find_line reviews/reconciliations/slice1/LSP_CALL_CHAIN_CHECK.md 'Conclusion'); $(find_line reviews/premortems/PREMORTEM_RECON_METRICS.md 'R7b strategic review findings')"
c06_ev="$(find_line reviews/reconciliations/S2/SUMMARY.md 'highest-signal')"
c07_ev="$(find_line reviews/reconciliations/S2/SUMMARY.md '6/6 mutants'); $(find_line reviews/reconciliations/S2/R7_POST_RECON_VALIDATION.md '100% mutation kill')"
c08_ev="$(find_line reviews/reconciliations/S2/SUMMARY.md '5 FIXED in R5')"
c09_ev="$(find_line reviews/premortems/PREMORTEM_RECON_POLICY.md 'CLAIMED_NOT_PROVEN'); $(find_line reviews/premortems/PREMORTEM_RECON_POLICY.md 'WRONG_IMPL_UNBLOCKED')"
c10_ev="$(find_line plans/wf_step.sh 'head_sha'); $(find_line plans/prd_set_pass.sh 'timestamp_utc')"
c11_ev="$(find_line plans/prd_set_pass.sh '[Uu]sage:'); $(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md 'Pass-Flip Gate'); $(find_line reviews/premortems/PREMORTEM_RECON_POLICY.md 'Fifteen checks')"
c12_ev="$(find_line plans/wf_step.sh 'STEPS='); $(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md 'cycle1')"
c13_ev="$(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md 'phase_equivalent'); $(find_line reviews/premortems/PREMORTEM_RECON_METRICS.md '8 phases')"
c14_ev="$(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md 'cycle1'); $(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md '### R3A'); $(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md '### R3B')"
c15_ev="docs_total=$doc_total (RUNBOOK=$runbook_lines POLICY=$policy_lines ANTIPATTERNS=$antip_lines METRICS=$metrics_lines PROCESS=$process_lines HANDOFF=$handoff_lines)"
c16_ev="plans/step_prompts/recon/* (excluding INDEX) count=$prompt_cards_count"
c17_ev="reconciliations=$recon_count premortems=$prem_count total=$total_count"
c18_ev="$(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md '99 debrief fields'); $(find_line reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md '§0')"
c19_ev="$(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md 'P0-A'); $(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md 'P0-B'); $(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md 'P1-D')"
c20_ev="$(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md 'I-3'); $(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md 'I-5')"
c21_ev="$(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md 'Status'); $(find_line plans/prompts/slice_reconcile_r1_audit.md 'READ-ONLY')"
c22_ev="$(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md 'Prioritized Action List'); $(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md '### P1-A')"
c23_ev="$(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md 'Stories × tools in parallel'); $(find_line plans/step_prompts/recon/cycle1.md 'enriched')"
c24_ev="$(find_line plans/prd.json '\"risk\"'); $(find_line plans/prd.json '\"scope\"'); $(find_line plans/prd.json '\"worst_case\"')"
c25_ev="$(find_line reviews/premortems/RUNBOOK_PREMORTEM_RECON.md 'No surrogate path'); $(find_line reviews/premortems/PREMORTEM_RECON_POLICY.md 'No surrogate path')"
c26_ev="$(find_line reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md 'O-2'); $(find_line plans/prd_set_pass.sh '[Uu]sage:')"

appendix_body() {
  cat <<TABLE
## Appendix A — Claim-by-Claim Evidence (origin/main @ ${short_sha})

> Generated by plans/generate_recon_review_appendix.sh --commit ${commit_ref} --date ${as_of_date}

| ID | Claim (short) | Status | As-of Date | As-of Commit | Evidence |
|----|---------------|--------|------------|--------------|----------|
| C-01 | S2 took ~3.5h and 27 artifacts | CONFIRMED | ${as_of_date} | ${short_sha} | ${c01_ev} |
| C-02 | S2 40:1 process-to-code ratio | PARTIAL | ${as_of_date} | ${short_sha} | ${c02_ev} |
| C-03 | TRIP/NON-TRIP directly caught dispatch_consistency_passed bypass | CONTRADICTED | ${as_of_date} | ${short_sha} | ${c03_ev} |
| C-04 | R7c found 58% island-of-guards | CONFIRMED | ${as_of_date} | ${short_sha} | ${c04_ev} |
| C-05 | No other layer caught island-of-guards | CONTRADICTED | ${as_of_date} | ${short_sha} | ${c05_ev} |
| C-06 | Mutation is highest-signal in S2 | CONFIRMED | ${as_of_date} | ${short_sha} | ${c06_ev} |
| C-07 | 100% mutation kill on S2-001 | CONFIRMED | ${as_of_date} | ${short_sha} | ${c07_ev} |
| C-08 | 5 test gaps applies to S2-001 | PARTIAL | ${as_of_date} | ${short_sha} | ${c08_ev} |
| C-09 | CLAIMED_NOT_PROVEN and WRONG_IMPL_UNBLOCKED are first-class fail-closed outcomes | CONFIRMED | ${as_of_date} | ${short_sha} | ${c09_ev} |
| C-10 | wf_step receipt chain is tamper-evident | PARTIAL | ${as_of_date} | ${short_sha} | ${c10_ev} |
| C-11 | prd_set_pass.sh is a 12-check gate | CONTRADICTED | ${as_of_date} | ${short_sha} | ${c11_ev} |
| C-12 | Same 9-step pipeline for stories | CONFIRMED | ${as_of_date} | ${short_sha} | ${c12_ev} |
| C-13 | 16-R-phase framing is canonical | PARTIAL | ${as_of_date} | ${short_sha} | ${c13_ev} |
| C-14 | cycle1 maps to R2+R3A+R3B+R4+R4b | PARTIAL | ${as_of_date} | ${short_sha} | ${c14_ev} |
| C-15 | Doc corpus is ~3960 lines | ${c15_status} | ${as_of_date} | ${short_sha} | ${c15_ev} |
| C-16 | 9 step prompt cards exist | ${c16_status} | ${as_of_date} | ${short_sha} | ${c16_ev} |
| C-17 | 162 + 41 = 203 current file counts | ${c17_status} | ${as_of_date} | ${short_sha} | ${c17_ev} |
| C-18 | 99 fields/story debrief tax | PARTIAL | ${as_of_date} | ${short_sha} | ${c18_ev} |
| C-19 | Round2 includes P0-A, P0-B, P1-D | CONFIRMED | ${as_of_date} | ${short_sha} | ${c19_ev} |
| C-20 | Round1 includes I-3/I-5 as P0 | CONFIRMED | ${as_of_date} | ${short_sha} | ${c20_ev} |
| C-21 | Still backlog/not implemented applies uniformly now | STALE | ${as_of_date} | ${short_sha} | ${c21_ev} |
| C-22 | Aggregate 2 P0 and 6 P1 from two audits | CONTRADICTED | ${as_of_date} | ${short_sha} | ${c22_ev} |
| C-23 | External reviews run sequential only | CONTRADICTED | ${as_of_date} | ${short_sha} | ${c23_ev} |
| C-24 | Tier routing can use risk, scope.touch, loss_mode.worst_case | CONFIRMED | ${as_of_date} | ${short_sha} | ${c24_ev} |
| C-25 | Tier-1 no-premortem is contract-compliant today | PROPOSAL_REQUIRES_CONTRACT_CHANGE | ${as_of_date} | ${short_sha} | ${c25_ev} |
| C-26 | prd_set_pass.sh --dry-run exists today | ${c26_status} | ${as_of_date} | ${short_sha} | ${c26_ev} |
TABLE
}

execution_authority_body() {
  cat <<'SECTION'
## Execution Authority (Current)

This document is an analysis/review artifact. It is **not** an execution authority.

For live reconciliation execution, use these canonical sources:

1. `reviews/reconciliations/PROTOCOL.md` — execution order, gates, handoff cadence.
2. `reviews/reconciliations/REFERENCE.md` — anti-patterns, escalation, troubleshooting.
3. `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` — required handoff format.
4. `specs/WORKFLOW_CONTRACT.md` — workflow contract authority.
5. `plans/wf_step.sh` — canonical step order and receipt enforcement.
6. `plans/verify.sh` — canonical verify entrypoint.
7. `plans/prd_set_pass.sh` — canonical pass-flip gate.

Related execution prompts (step-local):
- `plans/step_prompts/recon/*.md`

Legacy-to-current mapping:

| Legacy doc | Current source |
|---|---|
| `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | `reviews/reconciliations/PROTOCOL.md` + `REFERENCE.md` |
| `reviews/premortems/PREMORTEM_RECON_POLICY.md` | `reviews/reconciliations/PROTOCOL.md` |
| `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` | `reviews/reconciliations/REFERENCE.md` |
| `reviews/premortems/PREMORTEM_RECON_METRICS.md` | `reviews/reconciliations/REFERENCE.md` |
| `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` | `reviews/reconciliations/PROTOCOL.md` + step prompts |
SECTION
}

upsert_execution_authority_section() {
  local input_file="$1"
  local output_file="$2"
  local section_file
  section_file="$(mktemp)"
  execution_authority_body > "$section_file"

  if rg -q '^## Execution Authority \(Current\)' "$input_file"; then
    awk -v section_file="$section_file" '
      function print_block(   line) {
        while ((getline line < section_file) > 0) print line
        close(section_file)
      }
      BEGIN { in_section = 0 }
      {
        if ($0 ~ /^## Execution Authority \(Current\)/) {
          in_section = 1
          print_block()
          next
        }
        if (in_section == 1) {
          if ($0 ~ /^## /) {
            in_section = 0
            print
          }
          next
        }
        print
      }
    ' "$input_file" > "$output_file"
  else
    awk -v section_file="$section_file" '
      function print_block(   line) {
        while ((getline line < section_file) > 0) print line
        close(section_file)
      }
      BEGIN { inserted = 0 }
      {
        if (!inserted && $0 ~ /^## Numeric Methodology \(Normalized\)/) {
          print_block()
          print ""
          inserted = 1
        }
        print
      }
      END {
        if (!inserted) {
          print ""
          print_block()
        }
      }
    ' "$input_file" > "$output_file"
  fi

  rm -f "$section_file"
}

if [[ -n "$doc_path" ]]; then
  tmp_section="$(mktemp)"
  tmp_file="$(mktemp)"
  upsert_execution_authority_section "$doc_path" "$tmp_section"
  awk '/^## Appendix A — Claim-by-Claim Evidence/{exit} {print}' "$tmp_section" > "$tmp_file"
  printf "\n" >> "$tmp_file"
  appendix_body >> "$tmp_file"
  mv "$tmp_file" "$doc_path"
  rm -f "$tmp_section"
else
  appendix_body
fi
