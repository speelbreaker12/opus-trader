# Upgrade 1B - PR1 Spec (Phase-2 Planning Artifact, Spec-Only)

Status: Draft for stress test  
Date: 2026-03-02  
Scope: PR1 only (single execution entrypoint shell + parity), no PR2/PR3 refactors

## 0) Intent

Introduce one public orchestration entrypoint (`ExecutionEngine`) while preserving legacy behavior exactly.

This is a compatibility PR, not a cleanup PR.

## 1) Non-Goals (PR1)

- No internal gate wiring redesign
- No public input normalization to domain-only structs yet
- No visibility reductions (`pub` -> `pub(crate)`) for legacy orchestration APIs yet
- No contract behavior changes
- No consolidation of `Close` and `Hedge`

## 2) Public API (PR1)

```rust
pub struct ExecutionEngine;

pub enum ExecutionInput<'a> {
    Open(OpenExecutionInput<'a>),
    Close(CloseExecutionInput<'a>),
    Hedge(HedgeExecutionInput<'a>),
    CancelOnly(CancelOnlyExecutionInput<'a>),
}

pub struct ExecutionRuntime<'a> {
    pub pending_exposure_book: Option<&'a PendingExposureBook>,
    pub choke_metrics: ChokeMetrics,
    pub open_runtime_metrics: OpenRuntimeMetrics,
    pub pipeline_metrics: IntentPipelineMetrics,
}

pub enum ExecutionDecision {
    Approved {
        gate_trace: Vec<GateStep>,
        open_metadata: Option<OpenMetadata>,
    },
    Rejected {
        code: RejectReasonCode,
        step: GateStep,
        detail: String,
    },
}

pub struct OpenExecutionInput<'a> {
    pub input: OpenRuntimeInput<'a>,
    pub gate_reject_codes: GateRejectCodes,
}

pub struct CloseExecutionInput<'a> {
    pub input: IntentPipelineInput<'a>,
}

pub struct HedgeExecutionInput<'a> {
    pub input: IntentPipelineInput<'a>,
}

pub struct CancelOnlyExecutionInput<'a> {
    pub input: IntentPipelineInput<'a>,
}

pub struct OpenMetadata {
    pub pending_reservation_id: Option<ReservationId>,
    pub effective_risk_state: RiskState,
    pub adjusted_min_edge_usd: Option<f64>,
    pub mode_hint: MarginGateMode, // transitional in PR1; audit-driven for later removal
}
```

## 3) Variant Matrix

| Variant | Engine Path | Legacy Function | Required Runtime Dependency | Notes |
|---|---|---|---|---|
| Open | OPEN runtime | `build_open_order_intent_runtime` | `pending_exposure_book` required | fail-closed if dependency missing |
| Close | Pipeline | `evaluate_intent_pipeline` | none | `intent_class` forced to `Close` |
| Hedge | Pipeline | `evaluate_intent_pipeline` | none | `intent_class` forced to `Hedge` |
| CancelOnly | Pipeline/chokepoint | `evaluate_intent_pipeline` | none | preserves cancel-only chokepoint semantics |

## 4) WAL Rule Table (PR1)

| Variant | Gate 10 (`RecordedBeforeDispatch`) Rule | Expected Behavior |
|---|---|---|
| Open | Mandatory | WAL failure rejects (`RecordedBeforeDispatchFailed`) |
| Close | Compatibility shim (`wal_recorded` signal), non-blocking | WAL false/warn path does not block by itself |
| Hedge | Compatibility shim (`wal_recorded` signal), non-blocking | WAL false/warn path does not block by itself |
| CancelOnly | Not consulted (short-circuit) | no WAL gate dependency |

PR1 compatibility note:
- Open uses runtime path behavior as authoritative.
- Close/Hedge retain compatibility semantics from legacy pipeline/chokepoint wiring.
- Mandatory adapter-owned WAL attempt semantics for non-Open variants are deferred to PR2+.

## 5) Output Parity Checklist (Must Pass)

For each variant, compare `ExecutionEngine::evaluate` vs direct legacy call:

- Decision parity: `Approved` vs `Rejected`
- Reject code parity (`RejectReasonCode`)
- Reject step parity (`GateStep`)
- Reject detail parity (string)
- Gate trace parity (`Vec<GateStep>`)
- Open metadata parity:
  - `pending_reservation_id`
  - `effective_risk_state`
  - `adjusted_min_edge_usd`
  - `mode_hint` (transitional; audit-driven)
- Fail-closed behavior for missing open runtime dependency is deterministic

Open runtime override reason-code mapping (deterministic, required):

| Open reject detail string | `RejectReasonCode` |
|---|---|
| `PENDING_EXPOSURE_OVERFILL` | `PendingExposureBudgetExceeded` |
| `PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED` | `PendingExposureBudgetExceeded` |
| `GLOBAL_EXPOSURE_BUDGET_REJECT` | `GlobalExposureBudgetExceeded` |

## 6) Consumer Audit (Before Metadata Contraction)

Run:

```bash
rg -n 'mode_hint|adjusted_min_edge_usd|pending_reservation_id|effective_risk_state' crates/ --type rust
```

Rules:

- If non-execution consumers rely on `mode_hint`, do not remove it in PR2 without migration note.
- If only execution-internal/tests use `mode_hint`, mark as removable in PR2.
- Record audit output in PR notes.

## 7) Legacy Orchestration Deprecation Plan

PR1:
- Keep legacy APIs public and unchanged.
- Add engine entrypoint and parity tests only.

PR2:
- Normalize output around `ExecutionDecision`.
- Keep shims while migrating tests/docs to the engine entrypoint.

PR3:
- Deprecate legacy public orchestration helpers.
- Migrate external callsites to engine entrypoint.

PR4:
- Reduce visibility to `pub(crate)` or remove:
  - `evaluate_intent_pipeline`
  - `build_open_order_intent_runtime`
  - `IntentPipelineInput`
  - `PipelineResult`
  - `OpenRuntimeInput`
  - `OpenRuntimeOutput`
- Keep one public orchestration entrypoint: `ExecutionEngine`.

## 8) PR1 Acceptance Evidence

Required:

1. Engine parity tests for Open/Close/Hedge/CancelOnly using branch-complete matrix:
   - Open: approve + reject
   - Close: approve + reject
   - Hedge: approve + reject
   - CancelOnly: cancel short-circuit + WAL-signal scenario
2. WAL-path parity scenario coverage for each applicable variant.
3. Consumer audit output in PR notes.
4. Targeted execution tests green.
5. Verify gate run recorded (local or CI clean checkout).
