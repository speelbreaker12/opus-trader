---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: `execution/inventory_skew.rs` now exposes a crate-private `evaluate_inventory_skew_with_events(...)` seam with `InventorySkewEvent`, while the legacy `evaluate_inventory_skew(...)` wrapper still routes through the production adapter and preserves the existing reject metric/counter behavior.
- Value (what problem it solves): This flips another Upgrade 2A leaf from direct telemetry mutation to an event-sink seam, so graybox tests can validate inventory-skew behavior without mutating global observability state.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): `execution/inventory_skew.rs` still emitted reject counters and traced metric lines directly from leaf logic; the Upgrade 2A checklist still showed `inventory skew` as `FAIL`; there was no graybox-safe way to prove the missing-delta-limit and success paths without touching process-global telemetry.
- Time/token drain it caused: Each remaining 2A leaf would keep paying the same observability-coupling cost instead of moving mechanically down the checklist.
- Workaround I used this session (exploit): I mirrored the post-only/pricer leaf pattern exactly: add a crate-private event enum, route production through a tiny adapter, and prove parity with one graybox reject test, one graybox success test, and one wrapper metric-line test.
- Next-agent default behavior (subordinate): For the next 2A leaf, add the seam first, keep the public wrapper as the telemetry adapter, and require both graybox side-effect isolation and wrapper parity before claiming `PASS`.
- Permanent fix proposal (elevate): Continue the same event-sink pattern across the remaining 2A leaf modules until the checklist is mechanically green before touching 2B orchestration telemetry.
- Smallest increment: Take `execution/preflight.rs` next using the same adapter-plus-parity shape.
- Validation (proof it got better): `cargo test -p soldier_core --lib inventory_skew` passed with 21 tests, `cargo fmt --all` passed, `cargo fmt --all -- --check` passed, `git diff --check` passed, and the inventory-skew row in the Upgrade 2A checklist now reads `PASS`.

## 2) Best follow-up
- Single best next step: Convert `execution/preflight.rs` next because it is the next execution-only 2A leaf and uses the same low-ceremony seam pattern without dragging in the risk modules yet.
- 1-3 upgrades worth considering:
- What: Convert `risk/margin_gate.rs`. | Increment: add a crate-private event seam and parity-preserving adapter for its fail-closed reject telemetry. | Validation: the margin row flips from `FAIL` to `PASS` in the 2A checklist.
- What: Convert `risk/pending_exposure.rs`. | Increment: add a crate-private event seam and parity-preserving adapter for its reject telemetry. | Validation: the pending exposure row flips from `FAIL` to `PASS` in the 2A checklist.
- What: Re-run `./plans/verify.sh quick` from a clean checkout once the unrelated contract-kernel drift is resolved. | Increment: restore repo-level quick-verify evidence for this branch. | Validation: a new `artifacts/verify/<run_id>/verify.meta.json` reports `status=ok`.

## 3) Enforceable rules
- rule: Leaf Upgrade 2A conversions must keep the public function as the production telemetry adapter and move side effects into a crate-private event seam.
  trigger: Any edit to a 2A module that currently emits counters or metric lines directly.
  prevents: Graybox tests from mutating global telemetry or bypassing the legacy wrapper contract.
  enforce: `crates/soldier_core/src/execution/inventory_skew.rs`
- rule: Do not flip a 2A checklist row to `PASS` without both graybox isolation coverage and wrapper parity coverage.
  trigger: Any checklist edit that changes a 2A module from `FAIL` to `PASS`.
  prevents: PASS claims that prove the seam exists but not that the legacy observability contract still holds.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
- rule: When a handoff is requested mid-upgrade, point the new handoff at the next unchecked leaf instead of reopening already-passed rows.
  trigger: Any pause or explicit handoff request on the execution-facade-refactor branch.
  prevents: Resume churn where the next agent re-reads passed leaves instead of consuming the remaining red checklist rows.
  enforce: `obsidian/Handoffs/Execution Facade Refactor 2026-03-17 Upgrade 2A Inventory Skew Handoff.md`
