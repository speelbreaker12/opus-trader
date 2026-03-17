---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- bdb1cec1

## 0) What shipped
- Feature/behavior: `execution/pricer.rs` now exposes a crate-private `compute_limit_price_with_events(...)` seam with `PricerEvent`, while the legacy `compute_limit_price(...)` wrapper still routes through the production adapter and preserves the existing reject metric/counter behavior.
- Value (what problem it solves): This flips another real Upgrade 2A leaf row from direct telemetry mutation to an event-sink seam, so graybox tests can validate pricer behavior without mutating global observability state.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): `execution/pricer.rs` still emitted reject counters and traced metric lines directly from leaf math; the Upgrade 2A checklist still showed `pricer` as `FAIL`; there was no graybox-safe way to prove leaf behavior without touching process-global telemetry.
- Time/token drain it caused: Each remaining leaf conversion would keep re-solving the same observability-coupling problem instead of moving cleanly down the checklist.
- Workaround I used this session (exploit): I mirrored the quantize pattern exactly: add a crate-private event enum, route production through a tiny adapter, and prove parity with one graybox reject test, one graybox success test, and one wrapper metric-line test.
- Next-agent default behavior (subordinate): For the next 2A leaf, add the seam first, keep the public wrapper as the telemetry adapter, and require both graybox side-effect isolation and wrapper parity before claiming `PASS`.
- Permanent fix proposal (elevate): Continue the same event-sink pattern across the remaining 2A leaf modules until the checklist is mechanically green before touching 2B orchestration telemetry.
- Smallest increment: Take `execution/post_only_guard.rs` or `execution/inventory_skew.rs` next using the same adapter-plus-parity shape.
- Validation (proof it got better): `cargo fmt --all -- --check` passed, `cargo test -p soldier_core --lib pricer` passed with 39 tests, and the pricer row in the Upgrade 2A checklist now reads `PASS`.

## 2) Best follow-up
- Single best next step: Convert `execution/post_only_guard.rs` next because it is still a pure 2A leaf and should be cheaper than jumping into the more stateful inventory-skew path.
- 1-3 upgrades worth considering:
- What: Convert `execution/inventory_skew.rs`. | Increment: add a crate-private event seam plus graybox/wrapper parity tests. | Validation: its row flips from `FAIL` to `PASS` in the 2A checklist.
- What: Convert `execution/preflight.rs`. | Increment: isolate reject telemetry behind an event sink while keeping the wrapper’s legacy metric line contract. | Validation: graybox tests emit no global metric lines and the wrapper parity test still does.
- What: Convert `execution/post_only_guard.rs`. | Increment: add the same crate-private event seam and graybox/wrapper parity coverage used in pricer. | Validation: its row flips from `FAIL` to `PASS` in the 2A checklist.

## 3) Enforceable rules
- rule: Leaf Upgrade 2A conversions must keep the public function as the production telemetry adapter and move side effects into a crate-private event seam.
  trigger: Any edit to a 2A module that currently emits counters or metric lines directly.
  prevents: Graybox tests from mutating global telemetry or bypassing the legacy wrapper contract.
  enforce: `crates/soldier_core/src/execution/pricer.rs`
- rule: Do not flip a 2A checklist row to `PASS` without both graybox isolation coverage and wrapper parity coverage.
  trigger: Any checklist edit that changes a 2A module from `FAIL` to `PASS`.
  prevents: PASS claims that prove the seam exists but not that the legacy observability contract still holds.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
- rule: When a previously pending commit hash becomes known, backfill the project note and debrief before adding a new pending batch.
  trigger: Any follow-on work on a project note that still contains stale `pending` entries for already-created commits.
  prevents: Obsidian tracking drift where old work stays unanchored and new pending work becomes ambiguous.
  enforce: `obsidian/Projects/Execution Facade Refactor.md`
