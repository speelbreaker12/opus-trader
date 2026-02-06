# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: Added phase timing breakdowns to Ralph iterations and introduced minimal log-level helpers for top-level warnings.
- What value it has (what problem it solves, upgrade provides): Improves observability for iteration bottlenecks and makes key warnings easier to scan.
- Governing contract: specs/WORKFLOW_CONTRACT.md

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Limited visibility into where time is spent per iteration; warnings buried in verbose logs.
- Time/token drain it caused: Manual log scanning to find bottlenecks and warnings.
- Workaround I used this PR (exploit): Added phase timing capture and log-level helpers for top-level warnings.
- Next-agent default behavior (subordinate): Use phase timings from state/metrics to pinpoint slow phases before optimizing further.
- Permanent fix proposal (elevate): Add a small report summary (top 3 slow phases) at iteration end.
- Smallest increment: Append a log_info summary line listing the slowest phase.
- Validation (proof it got better): phase_timings_ms present in metrics/state; warnings tagged with level.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add a summary line of the slowest phase at iteration end; validate via workflow_acceptance grep + sample run.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response:
  - SHOULD: If adding new harness metrics, add acceptance coverage to assert the new field is written (Trigger: edits to plans/ralph.sh metrics). Prevents silent regressions; enforce via workflow_acceptance.
