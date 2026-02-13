# Intent Gate Ordering Invariants

## Normative Ordering Constraints

### C1: Reject Before Persist

All validation gates (DispatchAuth, Preflight, Quantize, DispatchConsistency, FeeCacheCheck, LiquidityGate, NetEdgeGate, Pricer) **must** execute before RecordedBeforeDispatch (WAL append).

**Rationale:** If we persist an intent to WAL before validating it, a crash after WAL write but before rejection would leave an invalid intent in the log, requiring reconciliation of something that should never have been recorded.

### C2: WAL Before Dispatch

RecordedBeforeDispatch (WAL append) is always the **last** gate before the intent is approved for dispatch to the exchange. No dispatch may occur without a prior WAL entry.

**Rationale:** CONTRACT.md RecordedBeforeDispatch — if the process crashes after dispatch but before WAL write, the system cannot reconcile the exchange state on restart. WAL-first guarantees crash recovery can detect all dispatched intents.

### C3: No Side Effects Before Accept

An intent is only approved (ChokeResult::Approved) when **all** gates pass. If any single gate fails, the result is ChokeResult::Rejected. The gate trace stops at the failing gate — no subsequent gates execute.

**Rationale:** Partial execution of the gate pipeline could create inconsistent state. Early-exit on failure ensures rejected intents produce zero persistent side effects (proven by S6-002 tests).

## Gate Ordering (Deterministic)

```
1. DispatchAuth     — RiskState check (OPEN requires Healthy)
2. Preflight        — Order type validation
3. Quantize         — Lot size quantization
4. DispatchConsistency — contracts/amount + liquidity-clamp consistency
5. FeeCacheCheck    — Fee cache staleness
6. LiquidityGate    — Book-walk slippage (OPEN only)
7. NetEdgeGate      — Fee + slippage vs min_edge (OPEN only)
8. Pricer           — IOC limit price clamping (OPEN only)
9. RecordedBeforeDispatch — WAL append (LAST, always)
```

## CI Enforcement

Tests in `crates/soldier_core/tests/test_gate_ordering.rs` enforce:
- C1: `test_constraint_reject_gates_before_persist`
- C2: `test_constraint_wal_is_last_gate_{open,close,hedge}`
- C3: `test_constraint_no_approval_with_any_gate_failed`
- Trace stops at failure: `test_constraint_rejected_trace_stops_at_failure`
- WAL after all validation: `test_constraint_wal_after_all_validation_gates`
