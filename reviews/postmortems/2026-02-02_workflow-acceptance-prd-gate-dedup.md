# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: Removed redundant `prd_gate.sh` call from workflow acceptance preflight; added assertion that prd gate fixtures invoke `plans/prd_gate.sh`.
- What value it has (what problem it solves, upgrade provides): Cuts unnecessary work in acceptance, reducing wall time without dropping coverage.
- Governing contract: specs/WORKFLOW_CONTRACT.md

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): workflow acceptance runtime dominated by repeated gate work; preflight ran `prd_gate.sh` even though fixtures already cover it.
- Time/token drain it caused: extra gate execution per acceptance run (compounded in full verify).
- Workaround I used this PR (exploit): removed the duplicate call and added a fixture assertion to keep coverage explicit.
- Next-agent default behavior (subordinate): avoid calling `prd_gate.sh` in preflight when fixtures already cover it; prefer a fixture assertion.
- Permanent fix proposal (elevate): add a small acceptance-time budget check in CI that flags regressions and redundant calls.
- Smallest increment: record and compare `workflow_acceptance` duration in CI summaries.
- Validation (proof it got better): compare CI acceptance duration before/after; expect a small reduction (single gate run removed).

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: follow up by removing the other redundant subprocess-heavy checks in 0k via batched `awk` (smallest increment: batch 5-10 greps; validate via acceptance duration in CI).

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: none — current workflow rules already require acceptance coverage; performance work should stay case-by-case.
