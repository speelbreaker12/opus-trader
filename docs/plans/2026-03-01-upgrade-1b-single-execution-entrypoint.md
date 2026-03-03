# Upgrade 1B Plan: Single Execution Entrypoint

Date: 2026-03-01
Owner: execution facade follow-up

## Goal

Finish Upgrade 1B by making `ExecutionEngine::decide` the single public orchestration entrypoint for `soldier_core::execution`, with private internal wiring and a reduced facade surface.

This is not a wrapper exercise. The outcome is a smaller, decision-focused public API where callers do not assemble gate-level wire structs.

## Final Public API Contract (Post-1B)

### Keep Public

- `ExecutionEngine`
- `ExecutionInput` (+ variant-specific input structs)
- `ExecutionRuntime`
- `ExecutionDecision` (+ approved/rejected payload structs)
- `RejectReasonCode`
- `RecordedBeforeDispatchGate`
- TLSM types required by infra integration
  - `TlsmTransitionSink`
  - `PersistedTransition`
  - `TlsmState`
  - `Tlsm`
  - `TlsmEvent`
  - `TransitionResult`

### TLSM Export Freeze (Deterministic)

For Upgrade 1B, the TLSM list above is closed. Do not add TLSM exports in 1B.

Audit command (must be captured in PR notes):

```bash
rg -n 'soldier_core::execution::(TlsmTransitionSink|PersistedTransition|TlsmState|Tlsm|TlsmEvent|TransitionResult)' crates/soldier_infra -g'*.rs'
```

Any additional TLSM symbol request is out of scope for 1B and must be handled in a separate follow-up story after PR4.

### Remove From Public Facade

- `ChokeMetrics`
- `GateResults`
- `build_gate_results`
- `IntentPipelineInput`
- `OpenRuntimeInput`
- `PipelineResult`
- `OpenRuntimeOutput`
- public orchestration helpers
  - `evaluate_intent_pipeline`
  - `build_open_order_intent_runtime`

### Public Shape

```rust
pub struct ExecutionEngine;

pub enum ExecutionInput<'a> {
    Open(OpenExecutionInput<'a>),
    Close(CloseExecutionInput<'a>),
    Hedge(HedgeExecutionInput<'a>),
    Cancel(CancelExecutionInput<'a>),
}

pub struct ExecutionRuntime<'a> {
    pub wal_gate: Option<&'a mut dyn RecordedBeforeDispatchGate>,
    pub pending_exposure_book: Option<&'a PendingExposureBook>,
}

pub enum ExecutionDecision {
    Approved(ApprovedExecution),
    Rejected(ExecutionRejection),
}

pub struct ApprovedExecution {
    pub effective_risk_state: RiskState,
    pub pending_reservation_id: Option<ReservationId>,
    pub adjusted_min_edge_usd: Option<f64>,
}

pub struct ExecutionRejection {
    pub code: RejectReasonCode,
    pub step: ExecutionStep,
    pub detail: String,
}

pub enum ExecutionStep {
    Runtime(RuntimeStep),
    Gate(GateStep),
}

pub enum RuntimeStep {
    BaseGates,
    PendingExposure,
    GlobalExposureBudget,
    InventorySkew,
    MarginGate,
    Assembly,
}
```

## Design Rules

- `ExecutionInput` carries domain-level request/snapshot data, not gate wire structs.
- `Close` and `Hedge` remain distinct public variants in 1B; no early semantic collapse into a single reduce bucket.
- `ExecutionRuntime` carries side-effectful collaborators/adapters.
- `ExecutionDecision` is the full contract output; callers must not map `ChokeResult` + helper sidecars themselves.
- `ExecutionEngine` remains stateless and call-scoped.

### WAL Authority Rule (Deterministic)

Per-variant WAL behavior must be explicit and tested:

| Variant | PR1-PR3 compatibility behavior | Final 1B behavior (PR4 end-state) |
|---|---|---|
| Open | Adapter path preferred. Legacy `wal_recorded` shim allowed only inside compatibility delegation. | Adapter-backed gate-10 only. Missing adapter is fail-closed (`RecordedBeforeDispatchFailed`). |
| Close | Adapter optional. Legacy shim may remain only inside compatibility delegation. | No public `wal_recorded` plumbing. If adapter exists, execute it; failure does not block per CSP.3.2. |
| Hedge | Adapter optional. Legacy shim may remain only inside compatibility delegation. | No public `wal_recorded` plumbing. If adapter exists, execute it; failure does not block per CSP.3.2. |
| Cancel | Cancel short-circuits at dispatch-auth and does not consult WAL gate. | Same behavior. |

Guardrail: do not preserve `PrecomputedWalGate` beyond compatibility layers. Remove shim dependency from public engine path by PR4 completion.

## Metrics Strategy

### Chosen Strategy: engine-owned internal metrics (not part of 1B public contract)

- `ExecutionEngine::decide` owns metric objects internally (`IntentPipelineMetrics`, `ChokeMetrics`, `OpenRuntimeMetrics`) and does not expose mutable metric structs to callers.
- Legacy APIs may keep their current metrics parameters during PR1-PR3 compatibility, but engine callers do not receive or pass these types.
- By PR4, no metric structs are required for public orchestration usage.
- If external metric sinks are needed later, add a dedicated non-contract observer interface in a future story; do not leak internal metrics structs back into the facade.

## 4-PR Execution Plan

## PR1: Add Engine Shell (No Behavior Change)

### Scope

- Add `engine.rs` with new public API types and `ExecutionEngine::decide`.
- Delegate only:
  - `Open` -> existing `build_open_order_intent_runtime`
  - `Close`/`Hedge`/`Cancel` -> existing pipeline/chokepoint path
- Re-export engine types from `execution/api.rs`.
- Keep legacy orchestration APIs public for transition.
- Do not deprecate in PR1.

### Tests

Add equivalence tests proving legacy and engine outputs match for:

- open healthy
- open rejected
- close path
- hedge path
- cancel-only
- WAL failure path

Equivalence assertions are strict:

- decision parity (`Approved`/`Rejected`)
- reject-code parity
- open-path metadata parity (`pending_reservation_id`, `effective_risk_state`, `adjusted_min_edge_usd`)

Add pre-PR1 consumer audit command and capture result in PR notes:

```bash
rg -n 'mode_hint|adjusted_min_edge_usd|pending_reservation_id|effective_risk_state' crates/ --type rust
```

Contract decision for 1B: `mode_hint` is internal-only and excluded from final public approved payload.
If the pre-PR1 consumer audit finds non-execution consumers, log a follow-up story; do not expand the 1B payload contract.

### Acceptance

- New engine API is reachable through `soldier_core::execution`.
- No behavior delta in equivalence scenarios.

## PR2: Normalize Public Output

### Scope

- Make `ExecutionDecision` authoritative output shape.
- Ensure `Rejected` always includes `code`, `step`, `detail`.
- Add deterministic mapping for open-runtime override reasons to registry codes.
- Avoid exposing `GateResults` in engine output.

### Tests

- reject mapping table tests for both pipeline and open-runtime paths
- runtime-stage mapping tests for `ExecutionStep::Runtime(RuntimeStep::*)`
- assembly failure maps to `ExecutionStep::Runtime(RuntimeStep::Assembly)`

### Acceptance

- All engine rejections are fully populated and deterministic.

## PR3: Normalize Public Input, Internalize Wiring

### Scope

- Replace public dependence on gate wire inputs with variant domain inputs.
- Add private builders that derive:
  - `BaseGatesInput`
  - `QuantizePipelineInput`
  - `LiquidityGateInput`
  - `NetEdgeInput`
  - `PricerInput`
  - `IntentPipelineInput`
- Convert orchestration I/O types to `pub(crate)` visibility:
  - `IntentPipelineInput`
  - `OpenRuntimeInput`
  - `QuantizePipelineInput`
  - `PipelineResult`
  - `OpenRuntimeOutput`
- Convert gate wire structs to `pub(crate)` once no public API depends on them.

### Tests

- engine integration tests cover open/close/hedge/cancel behavior
- compile-time facade test ensures only intended symbols remain public

### Acceptance

- External callers can construct only engine-level domain inputs.
- Gate wire structs are no longer externally required.

## PR4: Collapse Legacy Orchestration Surface

### Scope

- Create one private internal execution runner used by `ExecutionEngine::decide`.
- Remove public legacy orchestration exposure:
  - `evaluate_intent_pipeline` -> `pub(crate)` (internal helper only)
  - `build_open_order_intent_runtime` -> `pub(crate)` (internal helper only)
- Cut no-longer-needed legacy exports from `execution/api.rs`.
- Migrate contract integration tests in `crates/soldier_core/tests` to engine usage.
- Keep lower-level gate behavior tests as unit tests inside `src/execution/*`.

### Deprecation Policy

- If any legacy symbol must survive temporarily, deprecate only in PR4 with clear removal note.

### Acceptance

- `ExecutionEngine::decide` is the only public orchestration entrypoint.
- Public facade is decision-focused and minimal.

## Mechanical Completion Proofs

At final 1B completion, run and archive these checks.

### No Public Legacy Orchestration Outside Execution Internals

```bash
rg -n 'evaluate_intent_pipeline|build_open_order_intent_runtime' crates/ \
  -g'!crates/soldier_core/src/execution/**'
```

Expected: zero matches.

### No Legacy Input/Output Leak in Facade

```bash
rg -n 'IntentPipelineInput|OpenRuntimeInput|PipelineResult|OpenRuntimeOutput|GateResults|ChokeMetrics' \
  crates/soldier_core/src/execution/api.rs
```

Expected: zero matches.

### Contract Tests: Legacy API Denylist Is Empty

```bash
rg -n '\b(IntentPipelineInput|OpenRuntimeInput|PipelineResult|OpenRuntimeOutput|GateResults|ChokeMetrics|build_gate_results|build_order_intent_with_(optional_)?wal_gate|reject_reason_from_chokepoint|evaluate_intent_pipeline|build_open_order_intent_runtime)\b' \
  crates/soldier_core/tests
```

Expected: zero matches.

### Contract Tests: Engine API Usage Is Present

```bash
rg -n '\b(ExecutionEngine|ExecutionInput|ExecutionRuntime|ExecutionDecision|RejectReasonCode)\b' \
  crates/soldier_core/tests
```

Expected: non-zero matches (if zero, contract tests were not migrated to engine-facing API).

### No Public Legacy Orchestration Types/Functions in Execution Module

```bash
rg -n 'pub (struct|enum|type|fn) (IntentPipelineInput|OpenRuntimeInput|PipelineResult|OpenRuntimeOutput|GateResults|ChokeMetrics|evaluate_intent_pipeline|build_open_order_intent_runtime)' \
  crates/soldier_core/src/execution
```

Expected: zero matches (outside intentionally public engine contract types).

### Wire Types Are Internalized

```bash
rg -n '^pub struct (LiquidityGateInput|NetEdgeInput|PricerInput|QuantizePipelineInput)' \
  crates/soldier_core/src/execution
```

Expected: zero matches.

## Verification Gates

During development:

- `./plans/verify.sh quick`

Before claiming done:

- `./plans/verify.sh full`
- `bash plans/lint_execution_facade.sh`

For each substantial PR:

- run `code-review-expert` before final verify/merge per repo workflow guidance.

## Trap To Avoid

Do not expose `ExecutionEngine` that publicly accepts `IntentPipelineInput` or `OpenRuntimeInput`.

That is wrapper theater and fails 1B’s architecture objective.

Upgrade 1B is complete only when the public model is:

- one decision API
- domain inputs
- private orchestration wiring
- reduced facade surface
