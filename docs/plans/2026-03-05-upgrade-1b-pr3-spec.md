# Upgrade 1B - PR3 Spec: Normalize Public Input, Internalize Wiring

Status: **Complete** (verified 2026-03-05 on `wip/main-pre-sync-20260304`)
Date: 2026-03-05
Reference: `docs/plans/2026-03-01-upgrade-1b-single-execution-entrypoint.md` §PR3

---

## 0) Intent

Replace public dependence on gate wire inputs with variant domain inputs, and convert internal
orchestration I/O types to `pub(crate)`. This is the unlock that lets gate wire types become
crate-private.

---

## 1) Scope

### Input normalization

Replace public wiring structs with engine-level domain inputs:

- `OpenExecutionInput` — carries `LiquidityExecutionInput`, `NetEdgeExecutionInput`,
  `PricerExecutionInput`, `InventorySkewExecutionInput` (all engine-level, not gate-level)
- `CloseExecutionInput`, `HedgeExecutionInput`, `CancelExecutionInput` — carry `ExecutionBaseInput`

Private builder functions inside `engine.rs` derive internal gate types from these domain inputs:
- `build_open_runtime_input` → `OpenRuntimeInput` + `LiquidityGateInput` + `NetEdgeInput` + `PricerInput`
- `build_pipeline_input` → `IntentPipelineInput` + `QuantizePipelineInput`
- `build_base_gates_input` → `BaseGatesInput`

### Visibility reductions

Convert orchestration I/O types to `pub(crate)`:

| Type | File | Status |
|------|------|--------|
| `IntentPipelineInput` | `pipeline.rs` | `pub(crate)` |
| `QuantizePipelineInput` | `pipeline.rs` | `pub(crate)` |
| `PipelineResult` | `pipeline.rs` | `pub(crate)` |
| `OpenRuntimeInput` | `open_runtime.rs` | `pub(crate)` |
| `OpenRuntimeOutput` | `open_runtime.rs` | `pub(crate)` |
| `LiquidityGateInput` | `gate.rs` | `pub(crate)` |
| `NetEdgeInput` | `gates.rs` | `pub(crate)` |
| `PricerInput` | `pricer.rs` | `pub(crate)` |

---

## 2) Acceptance Criteria

### External callers use only domain inputs

Integration tests in `crates/soldier_core/tests/` must not reference any internal gate or
orchestration types. Only `soldier_core::execution::{...}` facade symbols are allowed.

### Facade symbol test

`tests/test_execution_facade_public.rs` must compile and pass:
- `execution_facade_symbols_publicly_reachable` — constructs facade types, calls `ExecutionEngine::decide`
- `facade_symbol_lists_stay_in_sync` — verifies unit and integration symbol lists match

### Engine integration tests

`src/execution/engine_decision_tests.rs` covers:
- Open approve + reject (global budget, pending exposure, WAL failure, missing pending_book)
- Close WAL non-blocking
- Hedge quantize reject
- Cancel WAL skip
- Pipeline assembly failure → `RuntimeStep::Assembly`
- Open-runtime step mappings (BaseGates, MarginGate, InventorySkew)
- Override reason-code table (PENDING_EXPOSURE_OVERFILL, GLOBAL_EXPOSURE_BUDGET_REJECT)

---

## 3) Mechanical Proof Commands

Run all four before declaring PR3 complete. All must return zero matches.

```bash
# 1. Wire types are pub(crate) — expect zero pub struct matches
rg -n '^pub struct (LiquidityGateInput|NetEdgeInput|PricerInput|QuantizePipelineInput)' \
  crates/soldier_core/src/execution

# 2. Orchestration I/O types are pub(crate) — expect zero pub struct matches
rg -n '^pub.* struct (IntentPipelineInput|OpenRuntimeInput|PipelineResult|OpenRuntimeOutput)' \
  crates/soldier_core/src/execution

# 3. No legacy types in api.rs — expect zero
rg -n 'IntentPipelineInput|OpenRuntimeInput|PipelineResult|OpenRuntimeOutput|GateResults|ChokeMetrics' \
  crates/soldier_core/src/execution/api.rs

# 4. No legacy types in integration tests — expect zero
rg -n 'IntentPipelineInput|OpenRuntimeInput|LiquidityGateInput|NetEdgeInput|PricerInput|evaluate_intent_pipeline|build_open_order_intent_runtime' \
  crates/soldier_core/tests
```

**Verified 2026-03-05**: all four return zero on `wip/main-pre-sync-20260304`.

---

## 4) Current Status (2026-03-05)

All PR3 scope items are complete on `wip/main-pre-sync-20260304`:

- All 8 wire/orchestration types converted to `pub(crate)` ✓
- Engine-level domain input types in place (`LiquidityExecutionInput`, `NetEdgeExecutionInput`, etc.) ✓
- Private builder functions derive internal types inside `engine.rs` ✓
- No legacy types in `execution/api.rs` ✓
- No legacy types in `tests/` ✓
- Facade completeness test exists and passes ✓

---

## 5) What PR3 Does NOT Cover (deferred to PR4)

- `evaluate_intent_pipeline` and `build_open_order_intent_runtime` remain `pub(crate)` but are not
  yet collapsed into a single internal runner. PR4 removes these as the public-facing orchestration
  split and routes everything through one private internal path.
- Legacy orchestration paths (`pipeline.rs`, `open_runtime.rs`) still exist as separate modules.
  PR4 creates one private internal execution runner and migrates tests off the legacy helpers.

See: `docs/plans/2026-03-01-upgrade-1b-single-execution-entrypoint.md` §PR4 for the remaining scope.

---

## 6) Verification Gate

```bash
./plans/verify.sh quick
bash plans/lint_execution_facade.sh
```
