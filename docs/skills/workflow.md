# Workflow Skill Memory (Manual)

Purpose
- Capture recurring corrections and preferred patterns for the workflow harness.
- Manual-only; no automation. Update when a pattern repeats.
- For prompt-backed skill catalog, see `docs/skills/index.md`.

Usage policy
- Read before starting any task.
- Update only when a new repeated pattern is discovered (manual judgment).
- Keep it versioned and lightweight; no new gates or automation.

How to use
- Add an entry only after it has happened at least twice.
- Keep entries short, specific, and testable.
- Prefer “Do/Don’t” phrasing with an example.

## Rules (Stable)
- [x] Rule:
  - Do: Use `docs/PHASE1_CHECKLIST_BLOCK.md` first and `docs/ROADMAP.md` second for Phase 1 gating decisions.
  - Don't: Treat excerpt/reference docs as decision authority for pass/block calls.
  - Example: Before marking a P1 gate complete, check unblock conditions in `docs/PHASE1_CHECKLIST_BLOCK.md`, then use `docs/ROADMAP.md` for context wording only.
  - Related files: `docs/PHASE1_CHECKLIST_BLOCK.md`, `docs/ROADMAP.md`, `docs/phase1_acceptance.md`, `docs/phase1_index.md`
  - Added: 2026-02-11
- [x] Rule:
  - Do: Use tokenized or anchor-style `contract_refs` in PRD stories, such as `CONTRACT.md AT-132`, `CONTRACT.md LiquidityGateNoL2`, `CONTRACT.md §1.3 Pre-Trade Liquidity Gate (Do Not Sweep the Book)`, `Anchor-###`, or `VR-###`.
  - Don't: Put slash-heavy prose sentences in `contract_refs`; keep detailed wording in `acceptance`, `steps`, or `contract_must_evidence`.
  - Example: Prefer `CONTRACT.md LiquidityGateNoL2` over `CONTRACT.md OPEN rejections due to missing/unparseable/stale L2 MUST use Rejected(LiquidityGateNoL2).`
  - Related files: `plans/prd_gate_help.md`, `plans/prd_ref_check.sh`, `plans/prd.json`
  - Added: 2026-03-07

## Pitfalls (Recent)
- [ ] Pitfall:
  - Symptom:
  - Root cause:
  - Fix:
  - Added:

## Test Harness Notes
- [ ] Note:
  - Context:
  - Expected behavior:
  - Assertion:
  - Added:

## Terminology (Local)
- [ ] Term:
  - Definition:
  - Source:
  - Added:

## Retired
- [ ] Entry:
  - Reason for retirement:
  - Retired:
