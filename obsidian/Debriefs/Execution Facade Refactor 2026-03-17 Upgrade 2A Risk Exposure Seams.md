---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- pending (working-tree checkpoint)

## 0) What shipped
- Feature/behavior: converted `risk/pending_exposure.rs` to a crate-private reject seam and `risk/exposure_budget.rs` to a crate-private evaluate seam, each with `EventSink` adapters and production wrappers.
- Value (what problem it solves): both leaves now keep graybox tests side-effect-free while preserving legacy wrapper metric/tracing behavior through seam adapters.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Upgrade 2A could not close because pending exposure and exposure budget still emitted global metrics directly from leaf paths, blocking clean graybox assertions.
- Time/token drain it caused: each blocked graybox seam required ad hoc handling of shared global side effects and repeated workaround scaffolding.
- Workaround I used this session (exploit): replicate the established two-file pattern used in prior risk seams (internal event enum + `Noop`/`Vec` sinks + production adapter) with paired graybox and wrapper-parity tests.
- Next-agent default behavior (subordinate): keep this conversion shape for remaining 2B leaves and avoid changing scope rows until adapter parity is recorded.
- Permanent fix proposal (elevate): apply the same event-seam conversion to `execution/group.rs` and `execution/build_order_intent.rs`, then rerun full verify on a clean checkout.
- Smallest increment: two remaining Upgrade 2A leaves were converted and marked `PASS` in the checklist.
- Validation (proof it got better): `docs/codebase/upgrade2_graybox_telemetry_checklist.md` rows `pending exposure` and `exposure budget` are now `PASS`.

## 2) Best follow-up
- Single best next step: finish Upgrade 2B (`execution/group.rs`, `execution/build_order_intent.rs`) using the same seam/parity pattern.
- 1-3 upgrades worth considering:
- What: Convert `execution/group.rs`. | Increment: introduce `with_events` seam + production adapter + graybox/parity tests. | Validation: `group` row in Upgrade 2B flips to `PASS`.
- What: Convert `execution/build_order_intent.rs`. | Increment: introduce `with_events` seam + production adapter + graybox/parity tests for chokepoint metrics. | Validation: 2B `gate sequence` and `WAL-nonblocking` rows flip to `PASS`.
- What: Re-run clean-checkout `./plans/verify.sh full`. | Validation: verify artifacts show `status=ok` and all workflow gates pass.

## 3) Enforceable rules
- rule: Keep 2A risk and 2B orchestration risk leaves using sink-based graybox paths.
  trigger: Any edit to `crates/soldier_core/src/risk/pending_exposure.rs`, `crates/soldier_core/src/risk/exposure_budget.rs`, or 2B-target modules.
  prevents: regressions to shared-metric side effects in leaf decision logic.
  enforce: [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)
- rule: Do not close Upgrade 2A rows without both graybox isolation and wrapper-parity tests.
  trigger: Any Upgrade 2A status transition to `PASS` in the checklist.
  prevents: checklist drift without test evidence.
  enforce: [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)
