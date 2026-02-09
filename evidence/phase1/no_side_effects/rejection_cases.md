# Rejection Side Effects Evidence

## Invariant

CONTRACT.md AT-201: Rejected intents must produce **zero** persistent state changes.
Only observability counters (metrics) may be modified.

## Rejection Cases Tested

### Case 1: RiskState Not Healthy
- **Trigger:** `ChokeIntentClass::Open` + `RiskState::Degraded`
- **Gate:** DispatchAuth (gate 1)
- **Verified:** WAL unchanged, no orders, no position delta, no exposure increment
- **Test:** `test_rejected_risk_state_no_side_effects`

### Case 2: Market Order Forbidden (Preflight)
- **Trigger:** `OrderType::Market` on any instrument
- **Gate:** Preflight
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_preflight_no_side_effects`

### Case 3: Quantization Too Small
- **Trigger:** `qty=0.5`, `amount_step=1.0`, `min_amount=1.0` → rounds to 0
- **Gate:** Quantize
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_quantize_no_side_effects`

### Case 4: Net Edge Too Low
- **Trigger:** `net_edge = 0 < min_edge = 2`
- **Gate:** NetEdgeGate
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_net_edge_no_side_effects`

### Case 5: Missing Net Edge Input (Fail-Closed)
- **Trigger:** `fee_usd = None`
- **Gate:** NetEdgeGate (NetEdgeInputMissing)
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_net_edge_missing_input_no_side_effects`

### Case 6: Pricer Net Edge Too Low
- **Trigger:** `gross=3, fee=2, min_edge=5 → net=1 < 5`
- **Gate:** Pricer
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_pricer_no_side_effects`

### Case 7: WAL Gate Failure
- **Trigger:** `wal_recorded = false`
- **Gate:** RecordedBeforeDispatch (gate 8)
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_wal_gate_no_side_effects`

### Case 8: Invalid Instrument Metadata
- **Trigger:** `tick_size = 0.0`
- **Gate:** Quantize (InstrumentMetadataMissing)
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_invalid_metadata_no_side_effects`

### Case 9: Multiple Sequential Rejections
- **Trigger:** 3 different rejections in sequence
- **Verified:** No state accumulation across rejections
- **Test:** `test_multiple_rejections_no_state_accumulation`

### Case 10: Stop Order Rejection
- **Trigger:** `OrderType::StopLimit` with trigger
- **Gate:** Preflight (OrderTypeStopForbidden)
- **Verified:** WAL unchanged, no orders, no position delta
- **Test:** `test_rejected_stop_order_no_side_effects`

## CI Link

`cargo test -p soldier_core --test test_rejection_side_effects`
