# Upgrade 2 Graybox Telemetry Coverage Checklist

Status: PASS

This checklist is the Upgrade 2 acceptance gate.
Upgrade 2 is not complete until both Upgrade 2A and Upgrade 2B are complete.
Upgrade 2A may be marked complete independently.

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
| liquidity | PASS | `crates/soldier_core/src/execution/gate.rs:328`, `crates/soldier_core/src/execution/gate.rs:554` | `ProductionLiquidityGateEvents` adapts the sink path back into metrics. |
| net-edge | PASS | `crates/soldier_core/src/execution/gates.rs:194`, `crates/soldier_core/src/execution/gates.rs:251` | `ProductionNetEdgeEvents` adapts the sink path back into metrics. |
| fee staleness | PASS | `crates/soldier_core/src/risk/fees.rs:89`, `crates/soldier_core/src/risk/fees.rs:177` | `ProductionFeeEvents` adapts the sink path back into metrics. |
| expected slippage | PASS | `crates/soldier_core/src/execution/gate.rs:147`, `crates/soldier_core/src/execution/gate.rs:352`, `crates/soldier_core/src/execution/gate.rs:666` | Covered inside `execution/gate.rs`, not as a separate module. |
| quantize | PASS | `crates/soldier_core/src/execution/quantize.rs:315`, `crates/soldier_core/src/execution/quantize.rs:385`, `crates/soldier_core/src/execution/quantize_tests.rs:763`, `crates/soldier_core/src/execution/quantize_tests.rs:833` | `ProductionQuantizeEvents` adapts the sink path back into metrics. |
| pricer | FAIL | `crates/soldier_core/src/execution/pricer.rs:150` | Emits metrics directly and has no sink seam. |
| inventory skew | FAIL | `crates/soldier_core/src/execution/inventory_skew.rs:134` | Emits metrics directly and has no sink seam. |
| post-only | PASS | `crates/soldier_core/src/execution/post_only_guard.rs:45`, `crates/soldier_core/src/execution/post_only_guard.rs:130`, `crates/soldier_core/src/execution/post_only_guard_tests.rs:320`, `crates/soldier_core/src/execution/post_only_guard_tests.rs:367` | `ProductionPostOnlyEvents` adapts the sink path back into metrics. |
| margin | PASS | `crates/soldier_core/src/risk/margin_gate.rs`, `crates/soldier_core/src/risk/margin_gate_tests.rs` | `evaluate_margin_headroom_gate_with_events` funnels reject paths through `ProductionMarginGateEvents`, with graybox tests proving `evaluate_margin_headroom_gate_with_events` stays side-effect free and wrapper tests preserving metric line behavior. |
| pending exposure | FAIL | `crates/soldier_core/src/risk/pending_exposure.rs:28` | Emits metrics directly and has no sink seam. |
| exposure budget | FAIL | `crates/soldier_core/src/risk/exposure_budget.rs:48` | Emits metrics directly and has no sink seam. |
| preflight | PASS | `crates/soldier_core/src/execution/preflight.rs:218`, `crates/soldier_core/src/execution/preflight.rs:249`, `crates/soldier_core/src/execution/preflight_tests.rs:531`, `crates/soldier_core/src/execution/preflight_tests.rs:567` | `ProductionPreflightEvents` adapts the sink path back into metrics. |

## Upgrade 2B — Orchestration Telemetry Decoupling

This is a non-blocking sibling checklist for Upgrade 2A, but Upgrade 2 stays open until these rows also pass.

### In Scope

- `execution/group.rs`
- `execution/build_order_intent.rs` orchestration metrics:
  `gate_sequence_total`, `wal_nonblocking_allowed_total`

## Upgrade 2B Checklist

| Module | Status | Evidence | Notes |
| --- | --- | --- | --- |
| group | FAIL | `crates/soldier_core/src/execution/group.rs:44`, `crates/soldier_core/src/execution/group.rs:50`, `crates/soldier_core/src/execution/group.rs:56` | Lock-timeout, persist-fail, and `MixedFailed` counters still emit directly from state-machine transitions. |
| gate sequence | FAIL | `crates/soldier_core/src/execution/build_order_intent.rs:244`, `crates/soldier_core/src/execution/build_order_intent.rs:251` | Chokepoint approval/rejection metrics still emit directly from the finish path. |
| WAL-nonblocking | FAIL | `crates/soldier_core/src/execution/build_order_intent.rs:469`, `crates/soldier_core/src/execution/build_order_intent.rs:488` | Chokepoint WAL-nonblocking metrics still emit directly from the RecordedBeforeDispatch branch. |

## Quick Census Command

This repo-wide search should find every `with_events` seam and its sink adapter:

```bash
rg -n "fn .*with_events|_with_events\\(|EventSink<" crates/soldier_core/src crates/soldier_infra/src
```

At the time this checklist was last updated, that search found liquidity, net-edge, fee staleness, quantize, pricer, post-only, preflight, margin, pending exposure, and exposure budget in the in-scope set above.
