# Critical Config Keys — Phase 1

## Fail-Closed Principle

Missing or invalid critical config MUST cause rejection with an enumerated reason code. The system MUST NOT silently default to unsafe values.

## Critical Keys

| Key | Module | Missing Behavior | Reason Code |
|-----|--------|-----------------|-------------|
| `tick_size` | quantize | Reject | `InstrumentMetadataMissing{field:"tick_size"}` |
| `amount_step` | quantize | Reject | `InstrumentMetadataMissing{field:"amount_step"}` |
| `min_amount` | quantize | Reject | `InstrumentMetadataMissing{field:"min_amount"}` |
| `gross_edge_usd` | net_edge | Reject | `NetEdgeInputMissing` |
| `fee_usd` | net_edge | Reject | `NetEdgeInputMissing` |
| `expected_slippage_usd` | net_edge | Reject | `NetEdgeInputMissing` |
| `min_edge_usd` | net_edge | Reject | `NetEdgeInputMissing` |
| `l2_snapshot` | liquidity_gate | Reject OPEN | `LiquidityGateNoL2` |
| `qty` (valid > 0) | pricer | Reject | `InvalidInput` |
| `RiskState` (Healthy) | chokepoint | Reject OPEN | `RiskStateNotHealthy` |

## Invalid Value Handling

- `NaN` → treated as missing → fail-closed
- `Infinity` → treated as missing → fail-closed
- `0.0` (for step/tick) → treated as missing → fail-closed
- Negative values → treated as missing → fail-closed

## CI Enforcement

`cargo test -p soldier_core --test test_missing_config`
