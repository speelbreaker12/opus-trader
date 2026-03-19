---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- pending (working-tree checkpoint)

## 0) What shipped
- Feature/behavior: `execution/preflight.rs` now routes decision logic through a crate-private `preflight_intent_with_events(...)` seam with a `PreflightEvent` enum; the public `preflight_intent(...)` function remains the production adapter via `ProductionPreflightEvents`.
- Value (what problem it solves): This removes global counter/metric side effects from graybox-level preflight assertions and keeps the legacy metric contract intact on the wrapper path.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): `execution/preflight.rs` still emitted reject counters/metric lines directly from leaf validation, so preflight graybox assertions could only test behavior by mutating shared telemetry state; `preflight` was still `FAIL` in the Upgrade 2A checklist.
- Time/token drain it caused: Every remaining 2A leaf would have required the same observability-decoupling refactor while still honoring legacy wrapper metric behavior, slowing mechanical checklist closure.
- Workaround I used this session (exploit): Reused the proven Upgrade 2A leaf pattern (event enum + production adapter + local sink-local event assertions) and added dedicated graybox and wrapper-parity tests.
- Next-agent default behavior (subordinate): Keep 2A leaf-work boundary and keep `preflight_intent(...)` as the production adapter while validating both side-effect isolation and metric-parity in tests before flipping checklist status.
- Permanent fix proposal (elevate): Extend the same event-seam pattern to 2A risk leaves (`margin`, `pending exposure`, `exposure budget`) so no additional preflight-style coupling is reintroduced.
- Smallest increment: `crates/soldier_core/src/risk/margin_gate.rs` with an event seam and parity-preserving wrapper.
- Validation (proof it got better): `cargo test -p soldier_core --lib preflight` passed; `crates/soldier_core/src/execution/preflight.rs` and `preflight_tests.rs` now expose no global metric side effects on the graybox path.

## 2) Best follow-up
- Single best next step: Convert `risk/margin_gate.rs` to the same event-sink pattern first because it is the highest-priority red 2A risk leaf.
- 1-3 upgrades worth considering:
- What: Convert `risk/margin_gate.rs`. | Increment: add `MarginGateEvent` + `with_events` seam + `Production` adapter. | Validation: margin row flips to `PASS` in checklist.
- What: Convert `risk/pending_exposure.rs`. | Increment: add `PendingExposureEvent` + graybox parity suite. | Validation: pending exposure row flips to `PASS` in checklist.
- What: Convert `risk/exposure_budget.rs`. | Increment: add `ExposureBudgetEvent` + wrapper parity suite. | Validation: exposure budget row flips to `PASS` in checklist.

## 3) Enforceable rules
- rule: Keep `execution/*` and `risk/*` 2A edits scoped to leaf event-seam wrappers only unless specifically migrating orchestration metrics in 2B.
  trigger: Any preflight-to-metrics refactor in remaining Upgrade 2A rows.
  prevents: Dragging 2B chokepoint/ orchestration changes into Upgrade 2A and losing scope isolation.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
- rule: Do not flip a 2A checklist row to `PASS` without graybox-side-effect isolation and wrapper parity assertions.
  trigger: Any checklist status change from `FAIL` to `PASS` under `## Upgrade 2A Checklist`.
  prevents: Passing rows without test evidence of legacy metric contract preservation.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
