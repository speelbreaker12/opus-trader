---
status: in-progress
priority: P3
branch: project/execution-facade-refactor
pr:
started: "2026-03-05"
worktree: .worktrees/execution-facade-refactor
---

## Current State
PR1-PR4 done. Internal telemetry sink seams are now live in `risk/fees.rs`, `execution/gate.rs`, `execution/gates.rs`, `execution/quantize.rs`, `execution/pricer.rs`, `execution/inventory_skew.rs`, `execution/post_only_guard.rs`, `execution/preflight.rs`, `risk/margin_gate.rs`, `risk/pending_exposure.rs`, and `risk/exposure_budget.rs`, with a shared metrics-test isolation helper guarding graybox parity tests. The Upgrade 2 graybox telemetry coverage checklist now lives at [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) and is now split into Upgrade 2A (leaf event-sink rollout) and Upgrade 2B (orchestration/chokepoint event-sink rollout). Upgrade 2A is now PASS by checklist; 2B and remaining 1C (risk/venue/infra) remain open.

## Commits
- `pending` — 2026-03-17 — add preflight event-sink seam with `PreflightEvent` and graybox/wrapper parity coverage.
- `94f5e639` — 2026-03-17 — add the inventory skew event seam, graybox/wrapper parity coverage, and flip the Upgrade 2A checklist row to `PASS`.
- `5c6f972c` — 2026-03-17 — add the post-only event seam, graybox/wrapper parity coverage, and flip the Upgrade 2A checklist row to `PASS`.
- `bdb1cec1` — 2026-03-17 — add the pricer event seam, graybox/wrapper parity coverage, and flip the Upgrade 2A checklist row to `PASS`.
- `5ebf6b2d` — 2026-03-17 — split Upgrade 2 into 2A/2B, add the quantize event seam, and unblock commits by excluding test fixtures from `ssot_lint`.
- `1e0eccc6` — 2026-03-17 — add execution gate event seams for liquidity and net-edge, plus graybox/parity test coverage and shared metrics-test isolation helpers.
- `429fe236` — 2026-03-17 — record the fee pilot commit hash in the Execution Facade Refactor project tracking notes.
- `0c5abc78` — 2026-03-17 — add the fee staleness event seam with typed events and parity-preserving production adapter coverage.
- `523a6434` — 2026-03-17 — add the crate-private telemetry sink seam used by graybox gate tests.
- `pending` — 2026-03-17 — add margin event seam with graybox + wrapper parity coverage in `risk/margin_gate.rs`.
- `pending` — 2026-03-17 — add risk leaf event seams in `risk/pending_exposure.rs` and `risk/exposure_budget.rs` with graybox + wrapper parity coverage.

## Key Files
- crates/soldier_core/src/execution/
- crates/soldier_core/src/execution/preflight.rs
- crates/soldier_core/src/execution/preflight_tests.rs
- crates/soldier_core/src/risk/fees.rs
- crates/soldier_core/src/risk/margin_gate.rs
- crates/soldier_core/src/risk/margin_gate_tests.rs
- crates/soldier_core/src/risk/pending_exposure.rs
- crates/soldier_core/src/risk/exposure_budget.rs
- [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)
- obsidian/Upgrades for AI/1/Status 2026-03-05.md

## Debriefs
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Preflight Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Inventory Skew Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Post-Only Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Pricer Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Quantize Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2 Acceptance Gate]]
- [[Execution Facade Refactor 2026-03-17 Telemetry Sink Seam]]
- [[Execution Facade Refactor 2026-03-17 Fee Staleness Event Pilot]]
- [[Execution Facade Refactor 2026-03-17 Execution Gate Event Pilots]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Risk Exposure Seams]]

## Handoffs
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Inventory Skew Handoff]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Post-Only Handoff]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Handoff]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Risk Exposure Seams Handoff]]

## Log
### 2026-03-17
- Converted `crates/soldier_core/src/risk/pending_exposure.rs` to a crate-private `bump_pending_exposure_with_events(...)` seam with `PendingExposureEvent` and `ProductionPendingExposureEvents`, plus graybox and wrapper parity coverage.
- Converted `crates/soldier_core/src/risk/exposure_budget.rs` to a crate-private `evaluate_global_exposure_budget_with_events(...)` seam with `ExposureBudgetEvent` and `ProductionExposureBudgetEvents`, plus graybox and wrapper parity coverage.
- Flipped both `pending exposure` and `exposure budget` rows in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) from `FAIL` to `PASS`.
- Verified the inventory-skew seam with `cargo test -p soldier_core --lib inventory_skew`, `cargo fmt --all`, and `cargo fmt --all -- --check`; `./plans/verify.sh quick` was not rerun in this session because the branch still carries the previously noted unrelated contract-kernel drift.
- Converted `crates/soldier_core/src/execution/inventory_skew.rs` to a crate-private `evaluate_inventory_skew_with_events(...)` seam with `InventorySkewEvent` and a parity-preserving production adapter.
- Added graybox and wrapper parity tests for inventory skew proving the sink path stays free of global counter/metric side effects while the public wrapper still emits the legacy reject metric line.
- Flipped the inventory-skew row in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) from `FAIL` to `PASS`.
- Verified the post-only seam with `cargo fmt --all -- --check` plus `cargo test -p soldier_core --lib post_only_guard`; `./plans/verify.sh quick` remains blocked by the unrelated `docs/contract_kernel.json` drift (`artifacts/verify/20260317_121242`).
- Converted `crates/soldier_core/src/execution/post_only_guard.rs` to a crate-private `check_post_only_with_events(...)` seam with `PostOnlyEvent` and a parity-preserving production adapter.
- Added graybox and wrapper parity tests for post-only guard proving the sink path stays free of global counter/metric side effects while the public wrapper still emits the legacy reject metric line.
- Flipped the post-only row in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) from `FAIL` to `PASS`.
- Converted `crates/soldier_core/src/execution/pricer.rs` to a crate-private `compute_limit_price_with_events(...)` seam with `PricerEvent` and a parity-preserving production adapter.
- Added graybox and wrapper parity tests for pricer proving the sink path stays free of global counter/metric side effects while the public wrapper still emits the legacy reject metric line.
- Flipped the pricer row in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) from `FAIL` to `PASS`.
- Fixed `plans/ssot_lint.sh` to ignore `plans/tests/fixtures/` and added workflow regression coverage so the repo guard stops treating doc-sync fixtures as canonical duplicates.
- Converted `crates/soldier_core/src/execution/quantize.rs` to a crate-private `quantize_with_events(...)` seam with `QuantizeEvent` and a parity-preserving production adapter.
- Added graybox and wrapper parity tests for quantize proving the sink path stays free of global counter/metric side effects while the public wrapper still emits the legacy reject metric line.
- Clarified the canonical Upgrade 2 checklist boundary: 2A is leaf-only, 2B covers `execution/group.rs` plus chokepoint `gate_sequence_total` / `wal_nonblocking_allowed_total`, and Upgrade 2 cannot close until both sections pass.
- Pointed the Upgrade status note at [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) and tightened the checklist so Upgrade 2 scope and closure stay row-driven instead of narrative.
- Added [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) as the mechanical pass/fail gate for Upgrade 2 graybox telemetry coverage and recorded that the checklist is still red outside liquidity, net-edge, fee staleness, and expected slippage-via-liquidity.
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
- Converted `crates/soldier_core/src/execution/preflight.rs` to a crate-private `preflight_intent_with_events(...)` seam with `PreflightEvent` and a parity-preserving production adapter.
- Added graybox and wrapper parity tests for preflight proving the sink path stays free of global counter/metric side effects while the public wrapper still emits the legacy reject metric line.
- Flipped the preflight row in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) from `FAIL` to `PASS`.
- Converted `crates/soldier_core/src/risk/fees.rs` to a crate-private `evaluate_fee_staleness_with_events(...)` seam with `FeeEvent` and a parity-preserving production adapter.
- Added inline graybox coverage proving the fee event path stays free of global counter/metric side effects while the public wrapper still emits the traced hard-stale metric line.
- Verified the fee pilot with targeted red-green tests plus the existing fee staleness and rejection-counter suites; repo quick verify remained blocked by unrelated `docs/contract_kernel.json` drift.
- Committed the fee pilot as `0c5abc78` (`soldier_core: add fee staleness event seam`).
- Converted `crates/soldier_core/src/risk/margin_gate.rs` to a crate-private `evaluate_margin_headroom_gate_with_events(...)` seam with `MarginGateEvent` and a parity-preserving `ProductionMarginGateEvents` adapter.
- Added graybox and wrapper parity tests in `crates/soldier_core/src/risk/margin_gate.rs` and `crates/soldier_core/src/risk/margin_gate_tests.rs` proving the graybox path has no global metric side effects and wrapper calls still emit a legacy reject metric line.
- Flipped the margin row in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) from `FAIL` to `PASS`.

### 2026-03-05
- PR1-PR4 status documented
- PR4 cleanup landed, behavior consolidation follow-up pending
