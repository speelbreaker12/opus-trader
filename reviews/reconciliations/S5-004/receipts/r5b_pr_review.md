# PR Review: S5-004 — Single Chokepoint build_order_intent()

## What This Story Implements
Routes ALL dispatch through `build_order_intent()` with a deterministic 10-gate pipeline. Rejects OPEN intents when RiskState != Healthy. Provides gate trace for audit. Source-scanning tests prevent bypass.

## SOLID / Architecture

### Single Responsibility
- `build_order_intent.rs` — sole responsibility: gate sequencing and dispatch authorization. Does NOT implement individual gates.
- Individual gates are evaluated by callers (`open_runtime.rs`, `pipeline.rs`) and passed as `GateResults` booleans.
- Clear separation: gate logic lives in gate modules, sequencing lives in chokepoint.

### Open/Closed
- Adding new gates requires modifying `build_order_intent_internal()` — this is acceptable because the gate sequence IS the contract. Making it plugin-based would be over-engineering.
- `GateResults` struct must grow for new gates — compile-time breakage ensures all callsites update.

### Interface Segregation
- `ChokeResult` returns either `Approved { gate_trace }` or `Rejected { reason, gate_trace }` — clean discriminated union.
- `RecordedBeforeDispatchGate` trait is minimal (one method).

### Dependency Inversion
- WAL gate uses trait `RecordedBeforeDispatchGate` — injectable. Good.
- Other gates use pre-computed booleans — less ideal but acceptable for Phase 1.

## Security

- No `unwrap()` in production code.
- `GateResults::default()` is fail-closed (all false).
- Metrics mutators (`record_approved`, `record_rejected`) are private to the module.
- Source-scanning tests prevent architectural bypass.
- No external input parsing in the chokepoint — all inputs are pre-validated.

## Issues Found

### P3: Static AtomicU64 counters not resettable in tests
`GATE_SEQUENCE_ALLOWED_TOTAL` and `GATE_SEQUENCE_REJECTED_TOTAL` are global statics. Tests that check these values are order-dependent. Not a safety issue, but fragile for parallel test execution.

### P4: Deprecated API still used by both callsites
`pipeline.rs` and `open_runtime.rs` both use the deprecated `build_order_intent()` with `#[allow(deprecated)]`. Phase 2 TODO. Not blocking.

## Verdict: PASS
No P0/P1/P2 issues. Architecture is clean and well-defended.
