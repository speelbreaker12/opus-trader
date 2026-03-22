# Upgrade 2 Graybox Telemetry Coverage Checklist

Status: Upgrade 2 checklist rows PASS; branch verification still blocked outside this checklist

This checklist is the Upgrade 2 acceptance gate.
Upgrade 2 is complete only when both Upgrade 2A and Upgrade 2B are complete.
Upgrade 2A remains a useful sub-checklist, but the repo-level status is driven by both tables.

As of 2026-03-21, the previously open review gaps are closed: preflight now routes post-only through the sink seam, the missing preflight crossing graybox test exists, the remaining leaf seams moved inline instance-metric mutation into observer sinks, the routing `no_gate_configured` WAL visibility path uses the chokepoint sink, and the graybox lint now forbids both inline `metrics.record_*()` calls and wrapper-call bypasses. Fresh targeted evidence is green (`cargo clippy --workspace --lib -- -D warnings`, `cargo test -p soldier_core --lib -- --nocapture`, `bash plans/lint_graybox_telemetry.sh`, `bash plans/tests/test_lint_graybox_telemetry.sh`), but `./plans/verify.sh quick` failed in `wf_test_pr_review_gate_hook` (`artifacts/verify/20260321_100806/FAILED_GATE`), which is outside Upgrade 2 scope.

## Scope Rule

Upgrade 2 scope is defined by the rows in `## Upgrade 2A Checklist` and `## Upgrade 2B Checklist`, not by prose in status notes or project summaries.

- A module or telemetry surface is in scope only if it appears in one of the checklist tables below.
- Closing Upgrade 2A requires every row in `## Upgrade 2A Checklist` to read `PASS`.
- Closing Upgrade 2 requires every row in both `## Upgrade 2A Checklist` and `## Upgrade 2B Checklist` to read `PASS`.
- Adding or removing scope requires editing these checklist tables and their supporting notes/evidence, so scope changes stay mechanical.

## Pass Rule

A module is PASS only if all of these are true:

- It exposes an internal crate-private `*_with_events(...)` or equivalent sink-based path in the module.
- That graybox path returns the same domain result as the production entrypoint.
- The graybox path reports observability through a sink such as `EventSink` instead of calling global metric emitters directly.
- The production wrapper adapts those events back into the existing metrics and tracing contract.
- There is a graybox test that calls the sink-based path directly.
- There is a parity test that proves the wrapper still preserves the legacy metrics and trace behavior.

## Upgrade 2A — Leaf Telemetry Decoupling

This is the active rollout scope for Upgrade 2.

### In Scope

- `execution/gate.rs`
- `execution/gates.rs`
- `execution/quantize.rs`
- `execution/pricer.rs`
- `execution/inventory_skew.rs`
- `execution/post_only_guard.rs`
- `execution/preflight.rs`
- `risk/fees.rs`
- `risk/margin_gate.rs`
- `risk/exposure_budget.rs`
- `risk/pending_exposure.rs`

### Out Of Scope

- `execution/group.rs`
- `execution/build_order_intent.rs` orchestration metrics:
  `gate_sequence_total`, `wal_nonblocking_allowed_total`

## Upgrade 2A Checklist

| Module | Status | Evidence | Notes |
| --- | --- | --- | --- |
| liquidity | PASS | `crates/soldier_core/src/execution/gate.rs` | `ObservedLiquidityGateEvents` keeps the graybox seam sink-only while `ProductionLiquidityGateEvents` preserves the wrapper metrics/tracing contract. |
| net-edge | PASS | `crates/soldier_core/src/execution/gates.rs:194`, `crates/soldier_core/src/execution/gates.rs:251` | `ProductionNetEdgeEvents` adapts the sink path back into metrics. |
| fee staleness | PASS | `crates/soldier_core/src/risk/fees.rs:89`, `crates/soldier_core/src/risk/fees.rs:177` | `ProductionFeeEvents` adapts the sink path back into metrics. |
| expected slippage | PASS | `crates/soldier_core/src/execution/gate.rs` | Covered inside `execution/gate.rs`; the observer sink pattern keeps both slippage sampling and reject accounting out of the graybox body. |
| quantize | PASS | `crates/soldier_core/src/execution/quantize.rs`, `crates/soldier_core/src/execution/quantize_tests.rs` | `ObservedQuantizeEvents` owns instance-metric mutation while `ProductionQuantizeEvents` preserves the wrapper contract. |
| pricer | PASS | `crates/soldier_core/src/execution/pricer.rs`, `crates/soldier_core/src/execution/pricer_tests.rs` | `ObservedPricerEvents` keeps pricing metrics in the observer adapter, with graybox and wrapper parity tests proving the legacy metrics contract still holds. |
| inventory skew | PASS | `crates/soldier_core/src/execution/inventory_skew.rs`, `crates/soldier_core/src/execution/inventory_skew_tests.rs` | `ObservedInventorySkewEvents` keeps allow/reject metrics out of the graybox body while `ProductionInventorySkewEvents` preserves wrapper behavior. |
| post-only | PASS | `crates/soldier_core/src/execution/post_only_guard.rs`, `crates/soldier_core/src/execution/post_only_guard_tests.rs` | `ObservedPostOnlyEvents` owns local metric mutation, and preflight now routes through `check_post_only_with_events(...)` instead of the wrapper. |
| margin | PASS | `crates/soldier_core/src/risk/margin_gate.rs`, `crates/soldier_core/src/risk/margin_gate_tests.rs` | `ObservedMarginGateEvents` keeps allow/reject accounting in the observer sink while wrapper parity still preserves the metric-line contract. |
| pending exposure | PASS | `crates/soldier_core/src/risk/pending_exposure.rs` | `ObservedPendingExposureEvents` owns reserve success/reject metrics, including idempotent-hit accounting, while wrapper parity keeps the legacy metric contract intact. |
| exposure budget | PASS | `crates/soldier_core/src/risk/exposure_budget.rs` | `ObservedExposureBudgetEvents` keeps allow/reject accounting out of the graybox body while the production wrapper still emits the legacy metrics/tracing shape. |
| preflight | PASS | `crates/soldier_core/src/execution/preflight.rs`, `crates/soldier_core/src/execution/preflight_tests.rs` | `ObservedPreflightEvents` owns preflight metrics, and the crossing-reject graybox test proves post-only wrapper counters no longer leak through preflight. |

## Upgrade 2B — Orchestration Telemetry Decoupling

This is a non-blocking sibling checklist for Upgrade 2A, but Upgrade 2 stays open until these rows also pass.

### In Scope

- `execution/group.rs`
- `execution/build_order_intent.rs` orchestration metrics:
  `gate_sequence_total`, `wal_nonblocking_allowed_total`

## Upgrade 2B Checklist

| Module | Status | Evidence | Notes |
| --- | --- | --- | --- |
| group | PASS | `crates/soldier_core/src/execution/group.rs`, `crates/soldier_core/src/execution/group.rs` tests | `apply_leg_result_with_events`, `try_acquire_group_lock_with_events`, and `persist_before_dispatch_with_events` keep the state-machine graybox path sink-only while the legacy wrappers still emit the exact contract counters and metric lines. |
| gate sequence | PASS | `crates/soldier_core/src/execution/build_order_intent.rs`, `crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs` | `build_order_intent_internal_with_events` emits typed `ChokeEvent` values; wrapper paths adapt them back into the legacy `gate_sequence_total` contract. |
| WAL-nonblocking | PASS | `crates/soldier_core/src/execution/build_order_intent.rs`, `crates/soldier_core/src/execution/routing.rs`, `crates/soldier_core/src/execution/dispatch_chokepoint_contract_tests.rs` | Graybox chokepoint evaluation reports WAL-nonblocking visibility via `ChokeEvent::WalNonblockingAllowed`; `routing.rs` now routes the `no_gate_configured` path through `emit_wal_nonblocking_allowed(...)` so the chokepoint sink owns both the metric and diagnostic. |

## Quick Census Command

This repo-wide search should find every `with_events` seam and its sink adapter:

```bash
rg -n "fn .*with_events|_with_events\\(|EventSink<" crates/soldier_core/src crates/soldier_infra/src
```

At the time this checklist was last updated, that search found liquidity, net-edge, fee staleness, quantize, pricer, post-only, preflight, margin, pending exposure, and exposure budget in the in-scope set above.
