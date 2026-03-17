# Upgrade 2 Graybox Telemetry Coverage Checklist

Status: FAIL

This checklist is the Upgrade 2 acceptance gate.
Upgrade 2 is complete only when every in-scope telemetry-bearing module passes the checks below.

## Scope Rule

Upgrade 2 scope is defined by the rows in `## Current Checklist`, not by prose in status notes or project summaries.

- A module is in scope only if it appears in the checklist table.
- Closing Upgrade 2 requires every in-scope row to read `PASS`.
- Adding or removing scope requires editing this checklist table and its supporting note/evidence, so scope changes stay mechanical.

## Pass Rule

A module is PASS only if all of these are true:

- It exposes an internal crate-private `*_with_events(...)` or equivalent sink-based path in the module.
- That graybox path returns the same domain result as the production entrypoint.
- The graybox path reports observability through a sink such as `EventSink` instead of calling global metric emitters directly.
- The production wrapper adapts those events back into the existing metrics and tracing contract.
- There is a graybox test that calls the sink-based path directly.
- There is a parity test that proves the wrapper still preserves the legacy metrics and trace behavior.

## Current Checklist

| Module | Status | Evidence | Notes |
| --- | --- | --- | --- |
| liquidity | PASS | `crates/soldier_core/src/execution/gate.rs:328`, `crates/soldier_core/src/execution/gate.rs:554` | `ProductionLiquidityGateEvents` adapts the sink path back into metrics. |
| net-edge | PASS | `crates/soldier_core/src/execution/gates.rs:194`, `crates/soldier_core/src/execution/gates.rs:251` | `ProductionNetEdgeEvents` adapts the sink path back into metrics. |
| fee staleness | PASS | `crates/soldier_core/src/risk/fees.rs:89`, `crates/soldier_core/src/risk/fees.rs:177` | `ProductionFeeEvents` adapts the sink path back into metrics. |
| expected slippage | PASS | `crates/soldier_core/src/execution/gate.rs:147`, `crates/soldier_core/src/execution/gate.rs:352`, `crates/soldier_core/src/execution/gate.rs:666` | Covered inside the liquidity seam, not as a separate module. |
| quantize | FAIL | `crates/soldier_core/src/execution/quantize.rs:232` | Emits metrics directly and has no sink seam. |
| pricer | FAIL | `crates/soldier_core/src/execution/pricer.rs:150` | Emits metrics directly and has no sink seam. |
| inventory skew | FAIL | `crates/soldier_core/src/execution/inventory_skew.rs:134` | Emits metrics directly and has no sink seam. |
| post-only | FAIL | `crates/soldier_core/src/execution/post_only_guard.rs:85` | Emits metrics directly and has no sink seam. |
| margin | FAIL | `crates/soldier_core/src/risk/margin_gate.rs:22` | Emits metrics directly and has no sink seam. |
| pending exposure | FAIL | `crates/soldier_core/src/risk/pending_exposure.rs:28` | Emits metrics directly and has no sink seam. |
| exposure budget | FAIL | `crates/soldier_core/src/risk/exposure_budget.rs:48` | Emits metrics directly and has no sink seam. |
| preflight | FAIL | `crates/soldier_core/src/execution/preflight.rs:192` | Emits metrics directly and has no sink seam. |
| group | FAIL if in scope | `crates/soldier_core/src/execution/group.rs:44`, `crates/soldier_core/src/execution/group.rs:50`, `crates/soldier_core/src/execution/group.rs:56` | Orchestration metric surface still emits directly. |
| WAL-nonblocking | FAIL if in scope | `crates/soldier_core/src/execution/build_order_intent.rs:481`, `crates/soldier_core/src/execution/build_order_intent.rs:488` | Chokepoint metric surface still emits directly. |

## Quick Census Command

This repo-wide search should find every `with_events` seam and its sink adapter:

```bash
rg -n "fn .*with_events|_with_events\\(|EventSink<" crates/soldier_core/src crates/soldier_infra/src
```

At the time this checklist was written, that search only found liquidity, net-edge, and fee staleness in the in-scope set above.
