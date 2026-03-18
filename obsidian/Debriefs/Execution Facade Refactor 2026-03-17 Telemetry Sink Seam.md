---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- `523a6434` `soldier_core: add crate-private telemetry sink seam`

## 0) What shipped
- Feature/behavior: Added a crate-private `soldier_core::telemetry` module with `EventSink`, `NoopEvents`, and `Vec<E>` support, wired into the crate root without public re-export.
- Value (what problem it solves): Creates the minimal internal seam needed for typed leaf-event pilots and graybox tests without disturbing current metric names or trace-enriched execution telemetry.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Execution and risk leaves still mutate global telemetry directly; graybox tests had to use shared metric buffers and process-lifetime counters; even a tiny seam required careful isolation from public facade churn.
- Time/token drain it caused: Extra review and verification passes to keep the change minimal and contract-safe.
- Workaround I used this session (exploit): Landed only the internal sink primitive and a focused unit test, leaving execution metric helpers and public wrappers untouched.
- Next-agent default behavior (subordinate): Start leaf conversions with `*_with_events` wrappers and keep the current production metric adapters in place until parity is proven.
- Permanent fix proposal (elevate): Move each leaf gate to typed event emission behind compatibility wrappers, then revisit shared execution telemetry ownership once the leaf pattern is stable.
- Smallest increment: Convert `risk/fees.rs` to a typed event path with a parity-preserving production adapter.
- Validation (proof it got better): Logic tests for converted leaves stop depending on global metric buffers while the public wrappers preserve current counter deltas and metric-line strings.

## 2) Best follow-up
- Single best next step: Convert `risk/fees.rs` to `evaluate_fee_staleness_with_events(...)` plus a compatibility wrapper.
- 1-3 upgrades worth considering:
- Convert `execution/gate.rs` after the fee pilot to prove the richer event shape.
- Standardize a leaf refactor template for `*_with_events` plus `Production*Events` wrappers.
- Keep orchestration-level telemetry changes for a later batch after leaf parity is stable.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Keep new telemetry seams crate-private until a public consumer is proven necessary.
- Preserve exact metric-line names and formats in compatibility wrappers during leaf eventification.
- Split logic-event tests from observability-parity tests so only adapter tests touch global telemetry state.
