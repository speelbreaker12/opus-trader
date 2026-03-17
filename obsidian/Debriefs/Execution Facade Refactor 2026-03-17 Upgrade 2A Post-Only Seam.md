---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- 5c6f972c

## 0) What shipped
- Feature/behavior: `execution/post_only_guard.rs` now exposes a crate-private `check_post_only_with_events(...)` seam with `PostOnlyEvent`, while the legacy `check_post_only(...)` wrapper still routes through the production adapter and preserves the existing reject metric/counter behavior.
- Value (what problem it solves): This flips another Upgrade 2A leaf from direct telemetry mutation to an event-sink seam, so graybox tests can validate post-only behavior without mutating global observability state.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): `execution/post_only_guard.rs` still emitted reject counters and traced metric lines directly from the leaf guard; the Upgrade 2A checklist still showed `post-only` as `FAIL`; there was no graybox-safe way to prove AT-916 behavior without touching process-global telemetry.
- Time/token drain it caused: Each remaining leaf conversion would keep paying the same observability-coupling cost instead of moving mechanically down the checklist.
- Workaround I used this session (exploit): I mirrored the existing leaf pattern exactly: add a crate-private event enum, route production through a tiny adapter, and prove parity with one graybox reject test, one graybox success test, and one wrapper metric-line test.
- Next-agent default behavior (subordinate): For the next 2A leaf, add the seam first, keep the public wrapper as the telemetry adapter, and require both graybox side-effect isolation and wrapper parity before claiming `PASS`.
- Permanent fix proposal (elevate): Continue the same event-sink pattern across the remaining 2A leaf modules until the checklist is mechanically green before touching 2B orchestration telemetry.
- Smallest increment: Take `execution/inventory_skew.rs` next using the same adapter-plus-parity shape.
- Validation (proof it got better): `cargo fmt --all -- --check` passed, `cargo test -p soldier_core --lib post_only_guard` passed with the new graybox/parity coverage, `./plans/verify.sh quick` stopped on the pre-existing `docs/contract_kernel.json` drift (`artifacts/verify/20260317_121242`), and the post-only row in the Upgrade 2A checklist now reads `PASS`.

## 2) Best follow-up
- Single best next step: Convert `execution/inventory_skew.rs` next because it is the last execution-only leaf before the remaining 2A work shifts toward more stateful or orchestration-adjacent modules.
- 1-3 upgrades worth considering:
- What: Convert `execution/preflight.rs`. | Increment: isolate preflight reject telemetry behind an event sink while keeping the wrapper’s legacy metric line contract. | Validation: graybox tests emit no global metric lines and the wrapper parity test still does.
- What: Convert `risk/margin_gate.rs`. | Increment: add a crate-private event seam and parity-preserving adapter for its fail-closed reject telemetry. | Validation: the margin row flips from `FAIL` to `PASS` in the 2A checklist.
- What: Convert `risk/pending_exposure.rs`. | Increment: add a crate-private event seam and parity-preserving adapter for its reject telemetry. | Validation: the pending exposure row flips from `FAIL` to `PASS` in the 2A checklist.

## 3) Enforceable rules
- rule: Leaf Upgrade 2A conversions must keep the public function as the production telemetry adapter and move side effects into a crate-private event seam.
  trigger: Any edit to a 2A module that currently emits counters or metric lines directly.
  prevents: Graybox tests from mutating global telemetry or bypassing the legacy wrapper contract.
  enforce: `crates/soldier_core/src/execution/post_only_guard.rs`
- rule: Do not flip a 2A checklist row to `PASS` without both graybox isolation coverage and wrapper parity coverage.
  trigger: Any checklist edit that changes a 2A module from `FAIL` to `PASS`.
  prevents: PASS claims that prove the seam exists but not that the legacy observability contract still holds.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
- rule: When a previously pending commit hash becomes known, backfill the project note and debrief before adding a new pending batch.
  trigger: Any follow-on work on a project note that still contains stale `pending` entries for already-created commits.
  prevents: Obsidian tracking drift where old work stays unanchored and new pending work becomes ambiguous.
  enforce: `obsidian/Projects/Execution Facade Refactor.md`
