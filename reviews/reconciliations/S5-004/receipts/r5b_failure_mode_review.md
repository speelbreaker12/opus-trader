# Failure Mode Review: S5-004 — Single Chokepoint

## Interface Crossings

### 1. Caller → Chokepoint (GateResults)
- **Risk**: Caller constructs `GateResults` with wrong boolean values (e.g., `liquidity_gate_passed = true` when gate actually rejected).
- **Mitigation**: `build_gate_results()` is the constructor. Source-scan test `test_no_direct_gate_results_construction_in_production` prevents `GateResults { ... }` construction outside the chokepoint module.
- **Residual risk**: Callers can still pass `true` to `build_gate_results()` when the gate didn't actually pass. The chokepoint trusts its callers. Defense-in-depth: `open_runtime.rs` computes gate results from actual gate evaluations.

### 2. Chokepoint → Metrics (ChokeMetrics)
- **Risk**: Metrics out of sync with actual decisions.
- **Mitigation**: `finish_approved()` and `finish_rejected()` are the only exit paths, and they always update metrics. No path through `build_order_intent_internal` can return without going through `finish_*`.

### 3. WAL Gate Trait Interface
- **Risk**: WAL gate implementation always returns `Ok(())` (stub).
- **Mitigation**: Deprecated `build_order_intent()` path falls back to `gate_results.wal_recorded` boolean. New `_with_wal_gate()` path calls the actual trait method.
- **Residual risk**: Both callsites use the deprecated path. Phase 2 migration required.

## State Transitions

### RiskState check at Gate 1
- All 4 RiskState variants tested: Healthy (allowed), Degraded/Maintenance/Kill (rejected for OPEN).
- CLOSE/HEDGE bypass this check correctly.
- CANCEL exits even earlier (after DispatchAuth, before Preflight).

### Intent Classification
- 4 variants: Open, Close, Hedge, CancelOnly.
- Each variant's path tested independently.
- No "unknown" variant possible — Rust enum is exhaustive.

## Edge Cases

### NaN/Infinity in dispatch clamp (Gate 4 sub-check)
- Lines 333-334: `!requested_qty.is_finite() || requested_qty <= 0.0` catches NaN, Infinity, negative, and zero.
- Same for `max_dispatch_qty`. GOOD — fail-closed on invalid floats.

### Both qty fields None (no clamp metadata)
- Lines 331: `(None, None) => {}` — skip clamp check. This is correct: no metadata = no constraint to enforce.

### One qty field None, other Some
- Lines 346-356: falls into `_` arm → reject with `DISPATCH_CLAMP_INCOMPLETE`. Fail-closed. GOOD.

## Findings

| # | Severity | Finding |
|---|----------|---------|
| 1 | P3 | WAL gate bypass: both callsites use deprecated path with precomputed boolean. Phase 2 TODO tracked. |
| 2 | INFO | Gate trace is `Vec<GateStep>` — heap allocation per intent. Acceptable for Phase 1 correctness over performance. |

## Verdict: PASS — no P0/P1/P2 failures found.
