# Dispatch Chokepoint

## Normative Statement

**All order dispatch must route through `build_order_intent()`.** No other code path may construct, approve, or bypass the chokepoint gate sequence.

This is mandated by CONTRACT.md CSP.5.2.

## Module

**File:** `crates/soldier_core/src/execution/build_order_intent.rs`

**Function:** `pub fn build_order_intent(intent_class, risk_state, metrics, gate_results) -> ChokeResult`

**Exchange Client Type:** `DispatchRequest` (constructed only after `ChokeResult::Approved` is returned by the chokepoint)

## Gate Ordering (Deterministic)

1. `DispatchAuth` — RiskState check (OPEN requires Healthy)
2. `Preflight` — Order type validation
3. `Quantize` — Lot size quantization
4. `FeeCacheCheck` — Fee cache staleness
5. `LiquidityGate` — Book-walk slippage (OPEN only)
6. `NetEdgeGate` — Fee + slippage vs min_edge (OPEN only)
7. `Pricer` — IOC limit price clamping (OPEN only)
8. `RecordedBeforeDispatch` — WAL append

## Intent Class Behavior

| Intent Class | Gates Executed | RiskState Requirement |
|---|---|---|
| Open | All 8 | Healthy only |
| Close | 1-4, 8 | Any |
| Hedge | 1-4, 8 | Any |
| CancelOnly | 1 only | Any |

## CI Enforcement

`crates/soldier_core/tests/test_dispatch_chokepoint.rs` scans source code to verify:

- Only `build_order_intent.rs` constructs `ChokeResult::Approved`
- Only `build_order_intent.rs` calls `record_approved()`
- No production code calls `map_to_dispatch()` / `validate_and_dispatch()` outside the chokepoint boundary
- No production code constructs `DispatchRequest` outside `dispatch_map.rs` and the chokepoint boundary
- Only `build_order_intent.rs` defines functions returning `ChokeResult`
- No production code constructs `GateResults` outside the chokepoint module
