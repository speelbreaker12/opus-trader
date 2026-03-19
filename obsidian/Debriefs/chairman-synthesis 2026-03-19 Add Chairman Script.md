---
project: "[[chairman-synthesis]]"
date: "2026-03-19"
---

## Commits
- pending — 2026-03-19 — plans: add chairman_synthesis.sh multi-model review council script

## 0) What shipped
- Feature/behavior: `plans/chairman_synthesis.sh` — synthesizes parallel reviewer artifacts (codex/sonnet/opus/kimi/gemini) from a review run directory into one deduplicated, severity-ordered finding list via a chairman model.
- Value (what problem it solves): Multi-model review runs previously produced N independent reports with no systematic deduplication or prioritization; chairman script collapses them into one authoritative list with consensus counts.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): No mechanism existed to cross-reference findings across reviewer tools; operators had to manually read 3-5 reports and deduplicate by eye.
- Time/token drain it caused: Manual synthesis of a 5-reviewer run typically consumes 20-30 minutes of operator time and introduces subjective prioritization inconsistency.
- Workaround I used this session (exploit): Script written fresh — no prior workaround.
- Next-agent default behavior (subordinate): Run `plans/chairman_synthesis.sh <run_dir>` after any parallel_review.sh run to produce `chairman/chairman.md` and `chairman/chairman.sidecar.json`.
- Permanent fix proposal (elevate): Integrate chairman invocation as a final step in `plans/parallel_review.sh` so synthesis is automatic.
- Smallest increment: The script as committed.
- Validation (proof it got better): Script reviewed manually; --dry-run path tested in isolation. No automated test harness exists yet for this script.

## 2) Best follow-up
- Single best next step: Add chairman step to `plans/parallel_review.sh` so it runs automatically after all reviewers complete.
- 1-3 upgrades worth considering:
  - Add a `plans/tests/` smoke test for chairman_synthesis.sh using fixture artifacts
  - Extend sidecar schema to include `citation_file` and `citation_line` as separate fields for machine-readable querying

## 3) Enforceable rules
- Always run `chairman_synthesis.sh` after `parallel_review.sh` — do not deliver raw per-reviewer artifacts without a synthesized view.
- The `--dry-run` flag is the safe default for verifying prompt construction before spending tokens on the chairman model call.
