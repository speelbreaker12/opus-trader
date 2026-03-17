---
status: in-progress
priority: P3
branch:
pr:
started: "2026-03-05"
---

## Current State
PR1-PR4 done. Internal telemetry sink seam landed in `soldier_core`; the first typed leaf-event pilot is now live in `risk/fees.rs`. Orchestration consolidation and 1C (risk/venue/infra) remain open.

## Key Files
- crates/soldier_core/src/execution/
- crates/soldier_core/src/risk/fees.rs
- obsidian/Upgrades for AI/1/Status 2026-03-05.md

## Debriefs
- [[Execution Facade Refactor 2026-03-17 Telemetry Sink Seam]]
- [[Execution Facade Refactor 2026-03-17 Fee Staleness Event Pilot]]

## Log
### 2026-03-17
- Added a crate-private `soldier_core::telemetry` module with `EventSink`, `NoopEvents`, and `Vec<E>` support to create a minimal sink seam for graybox gate tests.
- Wired the telemetry module into `crates/soldier_core/src/lib.rs` without any public re-export or public API churn.
- Added a focused unit test proving the internal sink contract and verified it with a red-green loop before commit.
- Wrote and linked the session debrief for the telemetry sink seam.
- Converted `crates/soldier_core/src/risk/fees.rs` to a crate-private `evaluate_fee_staleness_with_events(...)` seam with `FeeEvent` and a parity-preserving production adapter.
- Added inline graybox coverage proving the fee event path stays free of global counter/metric side effects while the public wrapper still emits the traced hard-stale metric line.
- Verified the fee pilot with targeted red-green tests plus the existing fee staleness and rejection-counter suites; repo quick verify remained blocked by unrelated `docs/contract_kernel.json` drift.
- Committed the fee pilot as `0c5abc78` (`soldier_core: add fee staleness event seam`).

### 2026-03-05
- PR1-PR4 status documented
- PR4 cleanup landed, behavior consolidation follow-up pending
