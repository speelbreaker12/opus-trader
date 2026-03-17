---
project: "[[Autoresearch]]"
date: "2026-03-17"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: Reviewed all 19 phase3 contract proposals. 16 accepted, 3 rejected. Rewrote P-208 Recovery Rule AT to bind to concrete producer (bunker_mode_active + bunker_exit_stable_s). Rendered accepted-only patch for CONTRACT.md.
- Value (what problem it solves): Moves autoresearch phase3 from "proposals generated" to "reviewed and ready to apply" — the accepted-only patch can now be applied to CONTRACT.md to close 2 P0 and 14 P1 contract gaps.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): REVIEW_DECISIONS JSON schema was undocumented — had to iterate 3 times to match the schema (missing contract_file_hash, missing proposals_file_hash, wrong structure for decisions array vs object, unexpected additional properties).
- Time/token drain it caused: ~4 iterations of trial-and-error against the validator.
- Workaround I used this session (exploit): Read the schema file directly after failures.
- Next-agent default behavior (subordinate): Always read review.schema.json before writing REVIEW_DECISIONS JSON.
- Permanent fix proposal (elevate): Add a `harness.sh contract scaffold-review --run-id <ID>` command that generates a skeleton REVIEW_DECISIONS JSON with the correct schema pre-filled.
- Smallest increment: Document the schema requirements in the review package header.
- Validation (proof it got better): Final render-review --accepted-only succeeded cleanly.

## 2) Best follow-up
- Single best next step: Apply the accepted-only patch to CONTRACT.md.
- 1-3 upgrades worth considering:
  - scaffold-review command to avoid schema iteration
  - P-400/P-401 fixture proposals should be auto-excluded from accepted-only CONTRACT.md patch (they target fixture text, not the contract)

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Always read `autoresearch/contract/phase2/review.schema.json` before writing REVIEW_DECISIONS JSON.
- Fixture-only proposals (sample_contract_patch) must be rejected in review decisions — their replace_span targets fixture text, not CONTRACT.md.
