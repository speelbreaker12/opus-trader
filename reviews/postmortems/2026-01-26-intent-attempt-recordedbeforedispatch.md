# PR Postmortem (Agent-Filled)

Governing contract: workflow (specs/WORKFLOW_CONTRACT.md)

## 0) What shipped
- Feature/behavior: Added IntentID/AttemptNo + UNKNOWN_AT_VENUE + venue idempotency class definitions; RecordedBeforeDispatch for OPEN now requires commit-visible WAL; added acceptance tests for commit-visible gating and retry policy; fixed workflow acceptance mode collision (suite vs worktree) and updated PRD contract_refs to satisfy coverage gating.
- What value it has (what problem it solves, upgrade provides): Removes ambiguity between enqueue-only vs restart-visible WAL records, clarifies retry behavior after ambiguous sends, and restores verify by aligning workflow acceptance and contract coverage gates.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Contract lacked explicit intent-vs-attempt model; RecordedBeforeDispatch allowed enqueue-only semantics; workflow acceptance failed due to mode collision; contract coverage gate failed due to missing PRD refs.
- Time/token drain it caused: Repeated interpretation debates, failed verify runs, and harness churn.
- Workaround I used this PR (exploit): Added minimal contract section + ATs and corrected workflow acceptance mode handling; mapped missing contract IDs to PRD items.
- Next-agent default behavior (subordinate): When introducing safety-critical semantics, add explicit definitions + ATs, and ensure PRD contract_refs cover new anchor/rule IDs.
- Permanent fix proposal (elevate): Add a contract lint to ensure new CSP invariants have matching AT coverage and glossary anchors.
- Smallest increment: Define IntentID/AttemptNo and commit-visible RecordedBeforeDispatch for OPENs with a handful of ATs plus minimal PRD coverage refs.
- Validation (proof it got better): `VERIFY_ALLOW_DIRTY=1 ./plans/verify.sh full` (passed; warning: workflow acceptance emitted a syntax error line message; see artifacts/verify/20260126_175604).

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add a contract lint step that verifies new anchors referenced by ATs exist (smallest increment: extend existing contract check script; validate via `./plans/verify.sh full`).

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: Require at least one crash/restart AT and one retry-policy AT for any idempotency/WAL semantic change.
