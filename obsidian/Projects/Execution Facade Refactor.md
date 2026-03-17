---
status: in-progress
priority: P3
branch: main
pr:
started: "2026-03-05"
---

## Current State
PR1-PR4 done. Internal telemetry sink seams are now live in `risk/fees.rs`, `execution/gate.rs`, and `execution/gates.rs`, with a shared metrics-test isolation helper guarding graybox parity tests. Orchestration consolidation and 1C (risk/venue/infra) remain open.

## Commits
- `1e0eccc6` — 2026-03-17 — add execution gate event seams for liquidity and net-edge, plus graybox/parity test coverage and shared metrics-test isolation helpers.
- `429fe236` — 2026-03-17 — record the fee pilot commit hash in the Execution Facade Refactor project tracking notes.
- `0c5abc78` — 2026-03-17 — add the fee staleness event seam with typed events and parity-preserving production adapter coverage.
- `523a6434` — 2026-03-17 — add the crate-private telemetry sink seam used by graybox gate tests.

## Key Files
- crates/soldier_core/src/execution/
- crates/soldier_core/src/risk/fees.rs
- obsidian/Upgrades for AI/1/Status 2026-03-05.md

## Debriefs
- [[Execution Facade Refactor 2026-03-17 Telemetry Sink Seam]]
- [[Execution Facade Refactor 2026-03-17 Fee Staleness Event Pilot]]
- [[Execution Facade Refactor 2026-03-17 Execution Gate Event Pilots]]

## Log
### 2026-03-17
- Added a top-level `## Commits` history section to this project note and backfilled the execution gate pilot debrief with commit `1e0eccc6`.
- Converted `crates/soldier_core/src/execution/gate.rs` to a crate-private `evaluate_liquidity_gate_with_events(...)` seam with `LiquidityGateEvent` and a parity-preserving production adapter.
- Converted `crates/soldier_core/src/execution/gates.rs` to a crate-private `evaluate_net_edge_with_events(...)` seam with `NetEdgeEvent` and a parity-preserving production adapter.
- Added graybox tests for the liquidity gate and net-edge gate proving the event paths do not mutate global counters or traced metric lines, while the wrapper parity tests still prove the production metrics contract.
- Added a shared `execution::begin_metrics_test()` / `with_metrics_update_lock(...)` test helper so global execution metric updates serialize correctly under graybox assertions instead of racing other tests.
- Verified the execution gate pilots with targeted red-green tests for liquidity, net-edge, and fee paths; `./plans/verify.sh quick` remains blocked by unrelated `docs/contract_kernel.json` drift.
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
