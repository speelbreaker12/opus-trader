---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- `pending` (working-tree checkpoint)

## 0) What shipped
- Feature/behavior: `risk/margin_gate.rs` now routes margin decisions through a crate-private `evaluate_margin_headroom_gate_with_events(...)` seam with `MarginGateEvent`.
- Value (what problem it solves): removes direct global metric side effects from graybox margin seam tests while preserving the production wrapper’s existing metric tracing contract.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): margin path was still directly emitting reject counters/metrics from leaf logic, which blocked side-effect isolation in graybox validation.
- Time/token drain it caused: added test scaffolding was needed just to avoid global side-effect interference.
- Workaround I used this session (exploit): replicated the established 2A seam pattern with `EventSink`, a production adapter, graybox-only helper tests, and wrapper parity tests.
- Next-agent default behavior (subordinate): keep public wrappers as production telemetry adapters and never reintroduce shared-counter mutation in the seam path.
- Permanent fix proposal (elevate): replicate this shape for remaining Upgrade 2A and 2B leaves.
- Smallest increment: margin row in the checklist is now `PASS` with seam and parity evidence.
- Validation (proof it got better): checklist row `margin` is `PASS` and wrapper tests still assert legacy metric behavior.

## 2) Best follow-up
- Single best next step: convert `risk/pending_exposure.rs` using the same seam/parity pattern.
- 1-3 upgrades worth considering:
- What: Convert `risk/pending_exposure.rs`. | Increment: add `PendingExposureEvent` + `with_events` seam + production adapter + tests. | Validation: `pending exposure` row flips to `PASS`.
- What: Convert `risk/exposure_budget.rs`. | Increment: add `ExposureBudgetEvent` + `with_events` seam + production adapter + tests. | Validation: `exposure budget` row flips to `PASS`.
- What: Re-run clean-checkout `./plans/verify.sh full`. | Validation: verify artifacts show `status=ok`.

## 3) Enforceable rules
- rule: Keep 2A risk leaves side-effect free in graybox by routing through sink adapters.
  trigger: Any edit to `risk`-namespace leaf modules in `Upgrade 2A`.
  prevents: Graybox regressions from direct metric emission.
  enforce: [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)
- rule: Do not mark a seam row `PASS` without seam + parity test evidence.
  trigger: any `PASS` status transition in Upgrade 2A checklist.
  prevents: unverified closure claims.
  enforce: [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)
