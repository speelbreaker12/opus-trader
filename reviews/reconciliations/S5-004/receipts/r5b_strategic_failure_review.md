# Strategic Failure Review: S5-004 — Single Chokepoint

## Hidden Assumptions

### 1. Gate evaluations are honest
The chokepoint trusts that callers pass truthful `GateResults`. If `open_runtime.rs` sets `liquidity_gate_passed = true` without actually running the liquidity gate, the chokepoint cannot detect this.

**Mitigation**: Source-scanning tests enforce that `GateResults` is only constructed inside the chokepoint module (via `build_gate_results()`). The function signature requires one boolean per gate, making it hard to accidentally skip a gate without consciously passing a value.

**Residual risk**: A developer could still pass `true` without running the gate. The `_with_wal_gate()` pattern (derive gate result from actual execution) is the long-term fix for all gates, but that's a Phase 2+ concern.

### 2. Source-scanning tests are comprehensive
The bypass detection relies on string matching (`"ChokeResult::Approved"`, `"record_approved"`, etc.). If someone constructs an approval via a different pattern (e.g., deserializing, transmuting), the scan wouldn't catch it.

**Mitigation**: The scan also checks for `-> ChokeResult` function signatures and `GateResults {` construction. Multiple overlapping checks make bypass harder. In practice, Rust's type system prevents most of these — you can't construct `ChokeResult::Approved` without the enum variant.

### 3. Test isolation with global statics
`GATE_SEQUENCE_ALLOWED_TOTAL` and `GATE_SEQUENCE_REJECTED_TOTAL` are `static AtomicU64`. Tests that read these values see cumulative counts from all prior tests in the process. This could cause flaky tests if assertions expect specific values.

**Mitigation**: The metric line test (`test_gate_sequence_emits_structured_reject_metric_line`) uses `>= 1` assertion instead of `== 1`. Other tests don't read global counters. Low risk.

## Simpler Alternatives Considered

### Why not a pipeline trait with pluggable gates?
Would add complexity without safety benefit. The contract specifies a fixed gate order — making it configurable introduces the risk of misconfiguration. Hardcoded sequence is simpler and provably correct.

### Why not return `Result<OrderIntent, RejectReason>` instead of `ChokeResult`?
The `gate_trace` field in both `Approved` and `Rejected` variants is critical for audit. A simple `Result` would lose the trace on the success path.

## Operational Concerns

### Observability gap: which gate rejected?
`ChokeRejectReason::GateRejected { gate, reason }` captures both the gate name and a human-readable reason string. The `gate_sequence_total` metric tracks accept/reject counts. Sufficient for Phase 1.

### No retry/backoff
The chokepoint is synchronous and immediate. No retry logic needed — callers evaluate gates, pass results, and get an immediate accept/reject.

## Findings

| # | Severity | Finding |
|---|----------|---------|
| 1 | INFO | Source-scanning bypass detection is strong but not formally proven. Acceptable for Phase 1. |
| 2 | INFO | Hardcoded gate sequence is correct design choice per contract. |

## Verdict: PASS — no strategic risks identified.
