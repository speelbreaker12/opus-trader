---
status: in-progress
priority: P3
branch: project/execution-facade-refactor
pr:
started: "2026-03-05"
worktree: .worktrees/execution-facade-refactor
---

## Current State
PR1-PR4 done. Internal telemetry sink seams are now live in `risk/fees.rs`, `execution/gate.rs`, `execution/gates.rs`, `execution/quantize.rs`, `execution/pricer.rs`, `execution/inventory_skew.rs`, `execution/post_only_guard.rs`, `execution/preflight.rs`, `risk/margin_gate.rs`, `risk/pending_exposure.rs`, `risk/exposure_budget.rs`, `execution/group.rs`, `execution/build_order_intent.rs`. The Upgrade 2 graybox telemetry coverage checklist now lives at [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md) and is now split into Upgrade 2A (leaf event-sink rollout) and Upgrade 2B (orchestration/chokepoint event-sink rollout). Upgrade 2A and 2B are PASS by checklist (status flipped 2026-03-18); remaining 1C (risk/venue/infra) remains open.

## Commits
- `pending` — 2026-03-19 — review-stack fix + rustfmt: preflight calls check_post_only() production wrapper (P1-1), margin gate includes reason in metric line (P1-2), liquidity gate aligned to (input, metrics, events) signature (P1-3), bump functions refactored to _inner pattern (P2-1), upgrade2 checklist 4 stale FAIL rows corrected (P2-3), rustfmt applied.
- `pending` — 2026-03-18 — remove dead code, duplicate warn, 15x clippy needless_return, test deadlock fix (raw METRICS_TEST_LOCK→begin_metrics_test), add 3 graybox tests for build_order_intent chokepoint, flip Upgrade 2 checklist PASS, close stale handoff.
- `pending` — 2026-03-17 — migrate `execution/group.rs` and `execution/build_order_intent.rs` instrumentation to crate-private `EventSink` seams with graybox parity coverage; mark Upgrade 2B rows PASS in checklist.
- `pending` — 2026-03-17 — add preflight event-sink seam with `PreflightEvent` and graybox/wrapper parity coverage.
- `pending` — 2026-03-17 — add `CSP-063` to `specs/TRACE.yaml` to satisfy quick pre-push traceability.
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
- [[Execution Facade Refactor 2026-03-17 Contract Kernel Sync]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Risk Exposure Seams]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Risk Checklist Pass]]
- [[Execution Facade Refactor 2026-03-17 Contract Change Ledger]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2B Orchestration Seams]]
- [[Execution Facade Refactor 2026-03-18 Cleanup and Verify Pass]]

## Handoffs
- [[Execution Facade Refactor 2026-03-18 Cherry-Pick Recovery Complete]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Inventory Skew Handoff]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Post-Only Handoff]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Handoff]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Risk Exposure Seams Handoff]]

## Log
### 2026-03-18 (session 2 — cherry-pick recovery)
- Discarded broken dirty state from failed bulk cherry-pick (-n).
- Re-cherry-picked 5 seam commits one at a time with compilation checks: post-only, inventory skew, preflight, risk exposure (pending+exposure_budget+margin), cleanup/deadlock fix.
- Removed 3 graybox tests from build_order_intent_gate_ordering_tests.rs that depend on Phase 2B code (build_order_intent_internal_with_events).
- Restored pricer seam (`compute_limit_price_with_events`, `PricerEvent`, `ProductionPricerEvents`) that was silently dropped during cherry-pick conflict resolution.
- 685 tests pass, 0 failures, clippy clean.

### 2026-03-18
- Sealed 6 implementation modules behind facade re-exports: `pub mod` → `mod` for `idempotency/hash`, `recovery/label_match`, `store/ledger`, `store/trade_id_registry`, `deribit/account_summary`, `deribit/public`. Migrated 5 deep-path callers in `bootstrap.rs` and updated doc comments in `tlsm.rs` and `wal.rs`.
- Standardized doc blocks across all facade `api.rs` and `mod.rs` files with consistent Public/Private/Tests sections. Added facade completeness contract tests for `idempotency`, `recovery`, and `status_codes` modules. Added crate-level doc block to `soldier_infra/src/lib.rs`.
- Removed duplicate `tracing::warn!` from WAL nonblocking bump (P0), dead `build_order_intent_internal` function, 15x `needless_return` clippy lints, and `items_after_test_module` in exposure_budget.rs.
- Added 3 graybox tests for `build_order_intent_internal_with_events` (approval, rejection, WAL-nonblocking close).
- Fixed pre-existing test deadlock: 4 engine decision tests used raw `METRICS_TEST_LOCK.lock()` instead of `begin_metrics_test()`, causing deadlock under parallel test execution.
- Flipped Upgrade 2 checklist `Status: FAIL` → `PASS` and closed stale Risk Exposure Seams handoff.
- `verify.sh full` passes clean.

### 2026-03-17
- Added `specs/flows/TIME_FRESHNESS.yaml` entries `TF-022` (`account_summary_max_age_ms`) and `TF-023` (`bunker_mode_max_age_ms`) so new `Appendix A` freshness keys are coverage-compliant for pre-push.
- Updated `TF-022` acceptance references to use existing contract AT IDs after parser compatibility check.
- Refreshed autoresearch manifest artifacts via `autoresearch/skills/harness.sh contract refresh-common` after the latest contract and ledger updates, updating `autoresearch/contract/common/{at_registry.json,context_manifest.json,section_index.md}` and phase1 fixture snapshots.
- Ran `python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json` to refresh contract-kernel metadata after the new ledger row in `specs/CONTRACT.md`.
- Added `CCL-2026-03-17-01` to `specs/CONTRACT.md` to record this branch’s outstanding contract delta and restore deterministic pass of verify gate 02a (`contract_change_ledger`).
- Refreshed `docs/contract_kernel.json` from `specs/CONTRACT.md`, `specs/IMPLEMENTATION_PLAN.md`, and anchor metadata to restore verification contract consistency for branch push.
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
- Flipped the Upgrade 2A checklist rows for `pending exposure` and `exposure budget` to `PASS` in [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md).
- Added `execution/group.rs` and `execution/build_order_intent.rs` as EventSink-based 2B seams with graybox tests and parity checks, then flipped Upgrade 2B rows (`group`, `gate sequence`, `WAL-nonblocking`) to `PASS`.
- Fixed `plans/prd.json` story reference typo for `S6-013` (`S6.13` -> `S6-013`) to satisfy `doc_sync_check`.
- Fixed remaining `build_order_intent`/`routing` compile regressions (WAL nonblocking metric path signature + missing semicolons) so quick mechanical verification can progress to clean.

### 2026-03-05
- PR1-PR4 status documented
- PR4 cleanup landed, behavior consolidation follow-up pending
