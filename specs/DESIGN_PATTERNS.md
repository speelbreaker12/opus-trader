# DESIGN_PATTERNS — Canonical Implementation Patterns

> When CONTRACT.md is silent on *how*, this document decides.
> Agents MUST read this before implementing any gate, guard, or safety-critical path.

## Purpose

CONTRACT.md specifies **what must be true** (behavioral outcomes).
This document specifies **how to build it** (default design choices, canonical shapes, forbidden patterns).

If an agent sees two ways to implement a contract clause and the contract doesn't distinguish them,
this document breaks the tie. If this document is also silent, the agent must match the nearest
existing gate in the codebase — never invent a new pattern.

---

## 0. Principles

These principles frame every section below. When two valid designs exist, apply this priority order.

### 0.1 Decisions use real quantities, not proxies

If a gate is about "edge," compare actual edge vs required edge.
If it's about "budget," check real exposure vs real limit.
No proxy thresholds (e.g., "multiplier > 1.4") unless the contract explicitly allows that proxy
**and** tests prove equivalence between the proxy and the real comparison.

### 0.2 Idempotency everywhere it matters

Anything that can be retried — orders, reservations, WAL writes, state updates — must be safe
to run twice. No double-counting, no double-sending. Use stable IDs and replace semantics
where appropriate.

### 0.3 Smallest surface area change

If the contract doesn't require a refactor, don't refactor. Keep changes localized. Avoid
"architectural upgrades" inside a feature story. This reduces crashes and surprises.

### 0.4 Design priority order

When multiple valid designs exist, choose the one that is (in order):

1. **Harder to misuse** — bad callers get compile errors or immediate rejection, not silent wrong behavior
2. **Easier to audit** — a reviewer can verify correctness by reading, not by running
3. **Easier to test** — fewer mocks, fewer fixtures, more table-driven
4. **Simpler to operate** — fewer knobs, fewer failure modes in production
5. **Faster** (last) — performance matters only after the above are satisfied

### 0.5 No paper compliance

You cannot mark `passes=true` unless:
- Enforcement exists in code (not just a comment or TODO)
- Tests prove it (TRIP + NON-TRIP for safety gates)
- Evidence artifacts exist (verify.sh output, contract_review.json)
- PRD mapping is correct (scope.touch matches actual files changed)

If a wrong implementation would pass the tests, the tests are insufficient — see §6.3 Devil's Advocate.

---

## 1. Canonical Gate Shape

Every gate that decides allow/reject/block MUST follow this shape:

```
inputs → validation → decision → diagnostics → metrics
```

### 1.1 Inputs

- All `f64` inputs checked with `is_finite()` before any arithmetic. NaN/Inf → reject or fail-closed.
- Missing fields use `Option<T>` with explicit match/handling. Never `unwrap_or_default()` on safety values.
- Boundary conditions validated: zero, negative, ordering constraints (e.g., `bid <= ask`).
- No epsilon-clamping fallbacks — validate preconditions, don't silently fix bad inputs.

### 1.2 Validation → Decision

- Two-variant result: `Allowed { diagnostics }` | `Rejected { reason, diagnostics }`.
- No bare `bool` returns for gate decisions. The caller needs to know *why*.
- Each gate has its own strongly-typed reason enum (e.g., `NetEdgeRejectReason`, `LiquidityGateRejectReason`).
- Reason enum maps to the global `RejectReasonCode` registry (`reject_reason.rs`).
- Each distinct failure mode gets its own reason variant. No catch-all "Unknown" for distinguishable failures.

### 1.3 Diagnostics

- Present in BOTH `Allowed` and `Rejected` branches.
- Carry intermediate computations: WAP, mm_util, fillable_qty, cache_age_s, etc.
- Enable root-cause debugging without re-running the gate.

### 1.4 Metrics

- Per-gate `*Metrics` struct with per-reason counters (e.g., `reject_net_edge_too_low_total`).
- Static `AtomicU64` counters with `Relaxed` ordering for API exposure.
- Structured tracing on reject paths: `tracing::debug!()` with typed fields.
- `emit_execution_metric_line()` for unified metric output.
- No `println!`, `eprintln!`, or unstructured string logging.

### 1.5 Deterministic Testing

- Timestamp injection via `_at()` suffixed methods. Core logic never calls `Instant::now()` directly.
- Gate evaluation is a pure function of inputs. Metrics are an observability sidecar, not decision state.
- Test helpers use explicit `Instant` values for reproducibility.

---

## 2. Fail-Closed Defaults

When contract says "fail-closed" but doesn't specify the exact default:

| Situation | Default | Never |
|-----------|---------|-------|
| Unknown TradingMode | `ReduceOnly` | `Active` |
| Unknown RiskState | `Degraded` | `Healthy` |
| Unknown intent classification | `Open` (most restrictive gates apply) | `Close` |
| Missing config value | Reject with specific reason | `unwrap_or_default()` |
| Cache miss | `Degraded` (treat as stale) | `Healthy` |
| NaN/Inf in safety path | Reject or most restrictive state | Warn and continue |
| Non-finite threshold | Treat as violated (fail-closed) | Treat as not violated |
| Unparseable input | Reject with reason code | Silent fallback |

**The "warn and continue" anti-pattern is forbidden on safety paths.**
If a value is bad enough to warn about, it's bad enough to reject on.

---

## 3. Error Handling Hierarchy

In order of preference:

1. **Propagate with `?`** — let the caller decide.
2. **Return typed error** — `Err(GateError::InvalidInput { field, value })`.
3. **Reject with reason code** — for gate decisions.
4. **Log and restrict** — `tracing::warn!` + most restrictive state. Only when the caller cannot handle the error and the system must continue.

Never:
- `let _ = dangerous_op();`
- `.ok()` on safety-critical results
- `unwrap_or(permissive_value)`
- Bare `unwrap()` / `expect()` in production paths

---

## 4. State Machine Patterns

### 4.1 Terminal States

Terminal states have zero valid successors. Once terminal, no further mutations are allowed.
Enforce with `is_valid_successor()` at the persistence layer, not just in-memory.

### 4.2 Latch Pattern

Set on bad event, clear only on explicit reconciliation. Never auto-clear on timeout.

```rust
// SET: unconditional on detecting the condition
self.open_permission_latch = true;
self.latch_reason = LatchReason::WsBookGap;

// CLEAR: only on explicit reconcile call with proof
pub fn reconcile(&mut self, proof: &ReconcileProof) -> Result<(), LatchError> {
    // Validate proof before clearing
    self.open_permission_latch = false;
}
```

### 4.3 Mode Recomputation

TradingMode MUST be recomputed every tick from current inputs. Never store/cache a computed mode.
This prevents stale mode decisions from persisting across ticks.

---

## 5. Naming Conventions

### 5.1 Gate Functions

```
evaluate_<gate_name>()       → main entry point
compute_<derived_value>()    → internal computation
check_<condition>()          → boolean precondition
```

### 5.2 Result Types

```
<Gate>Result::Allowed { diagnostics }
<Gate>Result::Rejected { reason: <Gate>RejectReason, diagnostics }
```

### 5.3 Reason Enums

```
<Gate>RejectReason::<SpecificFailure>    → e.g., NetEdgeRejectReason::NetEdgeTooLow
RejectReasonCode::<PascalCase>           → global registry, wire format = SCREAMING_SNAKE
```

### 5.4 Metrics Structs

```
<Gate>Metrics                → per-gate metrics container
  .reject_<reason>_total()   → per-reason counter
  .allowed_total()           → success counter
```

### 5.5 Test Method Suffixes

```
fn insert_at(...)            → timestamp-injected variant for testing
fn get_at(...)               → timestamp-injected variant for testing
fn risk_state_for_at(...)    → timestamp-injected variant for testing
```

---

## 6. Test Patterns

### 6.1 Every Gate Needs

- **TRIP test**: condition present → gate fires (rejects/restricts)
- **NON-TRIP test**: condition absent → gate allows
- **Boundary test**: value at exact threshold (off-by-one detection)
- **NaN/Inf test**: non-finite input → fail-closed
- **Missing input test**: `None` → fail-closed with specific reason

### 6.2 Table-Driven Preferred

```rust
let cases = [
    (RiskState::Healthy, false, "Healthy allows OPEN"),
    (RiskState::Degraded, true, "Degraded blocks OPEN"),
    (RiskState::Maintenance, true, "Maintenance blocks OPEN"),
    (RiskState::Kill, true, "Kill blocks OPEN"),
];
for (state, expected_blocked, label) in cases {
    assert_eq!(opens_blocked(state), expected_blocked, "{label}");
}
```

### 6.3 Devil's Advocate (Safety-Critical ATs)

After writing tests for a safety-critical gate, run `/devils-advocate`:
1. Write a deliberately wrong implementation that passes all tests
2. If it passes → add a test case that catches it
3. Repeat until wrong impl is harder than correct impl
4. Simpler-than-correct gate: if a trivially wrong impl still passes, tests are insufficient

### 6.4 Adversarial Tests (Global Invariants)

Each testable GI in `specs/invariants/GLOBAL_INVARIANTS.md` has a corresponding
`adversarial_*.rs` test file with `// TARGET: GI-NNN` headers. These tests attempt
to VIOLATE the invariant and assert it's blocked with the correct `RejectReasonCode`.

---

## 7. When This Document Is Silent

If this document doesn't cover a specific design choice:

1. **Look at the nearest existing gate** in the codebase that solves a similar problem.
2. **Match its pattern** — same result type shape, same metrics approach, same test structure.
3. **If no similar gate exists**, flag the decision in the PR for explicit review.

Never invent a new pattern without documenting it here first.

---

## 8. Reference Implementations

These gates are the canonical examples. New gates should match their patterns:

| Pattern | Reference Gate | File |
|---------|---------------|------|
| TTL/staleness check | InstrumentCache | `venue/cache.rs` |
| Threshold gate (multi-tier) | MarginHeadroomGate | `risk/margin_gate.rs` |
| Profitability gate | NetEdge | `execution/gates.rs` |
| Depth/book gate | LiquidityGate | `execution/gate.rs` |
| Input validation + quantization | Quantize | `execution/quantize.rs` |
| Order-type preflight | Preflight | `execution/preflight.rs` |
| Price computation + edge floor | Pricer | `execution/pricer.rs` |
| Budget/limit gate | PendingExposure | `risk/pending_exposure.rs` |
| Portfolio-level gate | GlobalExposureBudget | `risk/exposure_budget.rs` |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-02-19 | Add §0 Principles — real quantities, idempotency, smallest surface, design priority, no paper compliance |
| 2026-02-18 | Initial version — extracted from codebase analysis of 19 production gates |
