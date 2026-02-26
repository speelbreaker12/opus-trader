# Execution Module Facade Lockdown — Design

**Date:** 2026-02-26
**Scope:** `crates/soldier_core/src/execution/` only (Phase 1)
**Approach:** Option 4 — Split tests by contract vs internals

## Problem

`execution/mod.rs` exports 19 `pub mod` sub-modules with ~120 re-exported symbols.
Every internal wire type (`LiquidityGateInput`, `PricerInput`, `NetEdgeInput`, etc.)
is reachable by any crate. This invites coupling — an AI agent or future crate can
import `execution::gate::some_internal_fn` and nobody notices until refactoring breaks
everything.

Compounding issue: `verify.sh quick` runs `cargo test --workspace --lib`. The ~100
gate-level tests sitting in `crates/soldier_core/tests/` are invisible to the fast
feedback loop. The most important safety tests (fail-closed gates) only run during
`verify.sh full`.

## Principles

1. **Contract is defined by production consumers, not tests.**
   When a test needs `LiquidityGateInput`, the question is not "can we re-export it?"
   It's: "Should any production consumer ever need to construct this type?"
   If the answer is no, keep it private and change the test strategy.

2. **Integration tests must not drag internals into the contract.**
   `crates/soldier_core/tests/common/mod.rs` currently imports gate-level wire types.
   If we blindly require "integration tests must compile using only the facade," we'll
   be tempted to re-export all of that and call it "the contract." That's how deep
   modules die: the public interface becomes a mirror of internals.

3. **The fast feedback loop must include contract tests.**
   If the most valuable contract tests live exclusively in `crates/soldier_core/tests/`
   and `verify.sh quick` skips them, the fast loop can pass while the contract is broken.
   That's a TOC constraint violation.

## Public API Decision — Phased Approach

**Phase 1 (this design): Facade + module privacy only.**
Wire types (`LiquidityGateInput`, `PricerInput`, `NetEdgeInput`, etc.) remain `pub`.
Module paths become private (`pub mod` → `mod`). All external access goes through the
facade (`execution::{...}` only). This gives boundary protection now with zero
compilation risk.

**Why not `pub` → `pub(crate)` in Phase 1?** `OpenRuntimeInput`, `IntentPipelineInput`,
and `AssembledPipelineParams` embed gate wire types as public fields. Making those field
types `pub(crate)` while the containing structs remain `pub` will not compile — Rust
requires public struct fields to use public types. Hiding wire types requires either
making those structs opaque or replacing them with contract-level input types, both of
which are Phase 2 work.

**Phase 2 (future design): Contract input types + wire type internalization.**
Introduce `ExecutionInput` / `ExecutionEngine::decide()` that does not expose gate
inputs. Only then do gate wire types become `pub(crate)`. This is the proper deep-module
boundary — see §12.

## Goals

1. **Compiler-enforced privacy**: internal modules become `mod` (not `pub mod`).
   External crates cannot reach gate internals via deep module paths.
2. **Centralized facade**: all public re-exports live in `api.rs`.
   Wire types remain `pub` but are only reachable through the facade, not through
   `execution::gate::LiquidityGateInput`. (Phase 2 makes them `pub(crate)`.)
3. **Fast feedback**: gate unit tests move next to the code (`#[cfg(test)]`), running
   in `verify.sh quick` (`--lib`).
4. **Contract-only integration tests**: `crates/soldier_core/tests/` imports only
   from the facade. Black-box, not white-box.
5. **Contract tests in the fast loop**: `verify.sh quick` gains a smoke-contract lane
   that runs high-value contract integration tests.

## Design

### 1. Module Visibility — `pub mod` → `mod`

```rust
// crates/soldier_core/src/execution/mod.rs

//! Execution module facade.
//! Public API is defined in `api.rs` — read that file first.

pub mod api;                    // the only public surface

mod base_gates;
mod build_order_intent;
mod dispatch_map;
mod gate;
mod gate_outcome;
mod gates;
mod group;
mod intent_assembly;
mod inventory_skew;
mod label;
mod open_runtime;
mod order_size;
mod pipeline;
mod post_only_guard;
mod preflight;
mod pricer;
mod quantize;
mod reject_reason;
mod tlsm;

// Re-export public API at module level for backwards compat
// with contract-level imports like `execution::Side`.
pub use api::*;
```

Public re-exports live in `api.rs`. No new public exports may be added outside
`api.rs`.

**Telemetry helpers — contract decision:** `with_intent_trace_ids()` and
`take_execution_metric_lines()` are currently `pub fn` in `mod.rs`, but their
only callers are integration tests in `soldier_core/tests/` (4 test files — all
in the "must move" table). Zero callers in `soldier_infra`. Zero production callers.
**These are not contract.** In Step 2, when those test files move to `#[cfg(test)]`
unit tests, change both functions to `pub(crate)`. The moved tests retain access
(same crate). `emit_execution_metric_line` is already `pub(crate)` and stays.

### 2. Public Facade — `api.rs` (contract types only)

**Phase 1 contract has two tiers:**

- **Execution contract** = chokepoint boundary (`build_order_intent*`, `ChokeResult`,
  `GateResults`, `RejectReasonCode`) + lifecycle primitives needed by
  `soldier_infra` and contract-level integration tests (`Tlsm*`, `AtomicGroup*`,
  `Label*`, `Side`, `OrderSize`, `RecordedBeforeDispatchGate`).
- **Pipeline contract** = none. Pipeline wiring (`evaluate_intent_pipeline`,
  `IntentPipelineInput`, gate wire types, assembly params) is internal. Unit-tested
  only. Not in the facade.

This split forces test placement: if a test needs pipeline internals, it's a unit
test. If it tests through the chokepoint or lifecycle primitives, it's a contract
integration test.

The decision tree for each symbol:

```
Should any production consumer or contract integration test need this type?
├── YES (chokepoint/lifecycle) → export in api.rs, freeze it
└── NO  (pipeline wiring)      → omit from api.rs, unit-test only
```

**Critical finding:** `IntentPipelineInput`, `OpenRuntimeInput`, and
`AssembledPipelineParams` all contain gate-level wire types as fields
(`liquidity: Option<LiquidityGateInput>`, `net_edge_input: NetEdgeInput`, etc.).
These are internal wiring, not contract. In Phase 1, they remain `pub` (because
their field types must also be `pub`), but are **not re-exported in `api.rs`** and
are unreachable through the facade since their parent modules are private.
Phase 2 introduces contract input types that replace these structs, enabling
`pub` → `pub(crate)` on wire types.

```rust
// crates/soldier_core/src/execution/api.rs
//
// 44 symbols. Each justified by production consumer or contract integration
// test that survives the test-move step.

//! # Execution Pipeline — Public API
//!
//! This file defines the complete public surface of the execution module.
//! If a type is not re-exported here, it is an internal implementation detail.
//!
//! RULE: The contract is defined by production consumers, not tests.
//! A type is public only if an external crate needs it in production
//! or in a contract-level integration test that stays in tests/.
//!
//! RULE: crates/soldier_core/tests/* may only import from this facade.
//! Anything needing gate-internal types belongs in #[cfg(test)] unit tests.

// ── Chokepoint Boundary (10 symbols) ──
pub use super::build_order_intent::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult,
    GateResults, GateStep, RecordedBeforeDispatchGate,
    build_order_intent, build_order_intent_with_wal_gate,
    build_order_intent_with_optional_wal_gate,
    build_order_intent_with_reject_reason_code,
};
// CUT: ChokeMetrics (all consumers in must-move tests)
// CUT: GateSequenceResult, gate_sequence_total (sole consumer test_gate_ordering → must-move)
// CUT: build_gate_results (zero external consumers)

// ── Reject Reason (4 symbols) ──
pub use super::reject_reason::{
    GateRejectCodes, RejectReasonCode,
    reject_reason_registry, reject_reason_registry_contains,
};
// CUT: reject_reason_from_chokepoint (zero external consumers)
// CUT: PipelineResult (return type of excluded evaluate_intent_pipeline)

// ── Gate Outcome ──
// CUT: GateOutcome (sole consumer test_gate_outcome → must-move; source: gate_outcome module)

// ── Domain Primitives (4 symbols) ──
pub use super::quantize::Side;
pub use super::order_size::{OrderSize, OrderSizeInput, build_order_size};
// CUT: DispatchConsistencyProof, DispatchRequest, ValidatedDispatch (zero external consumers)
// CUT: IntentClass (sole consumer test_dispatch_map → must-move)
// CUT: OrderSizeError (all consumers in must-move tests)

// ── Label (7 symbols) ──
pub use super::label::{
    LABEL_MAX_LEN, LabelError, LabelInput,
    decode_label, derive_gid12, derive_sid8, encode_label,
};
// CUT: ParsedLabel (zero external consumers)

// ── Group Atomicity (11 symbols) ──
pub use super::group::{
    AtomicGroup, GroupConfig, GroupError, GroupLock,
    GroupState, GroupStateTransition, InMemoryGroupPersistence, LegResult,
    LockAcquisitionResult,
    persist_before_dispatch, try_acquire_group_lock,
};
// CUT: GroupPersistence (zero external consumers — trait implemented internally)
// CUT: group_lock_timeout_total, group_mixed_failed_total, group_persist_fail_total
//      (sole consumer test_static_rejection_counters → must-move; §10: metrics not contract)

// ── Trade Lifecycle State Machine (8 symbols) ──
pub use super::tlsm::{
    OooCategory, PersistedTransition, Tlsm,
    TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink,
    TransitionResult,
};
// CUT: NoopTransitionSink (zero external consumers — test utility, move to #[cfg(test)])
// CUT: ooo_count, ooo_total (sole consumer test_tlsm; §10: metrics not contract)
```

**Excluded from facade** — unreachable via `execution::{...}` since parent modules
are private; `pub` → `pub(crate)` deferred to Phase 2:

| Category | Types excluded from facade | Reason |
|----------|--------------------------|--------|
| **Chokepoint internals** | `ChokeMetrics`, `GateSequenceResult`, `gate_sequence_total`, `build_gate_results` | All consumers in must-move tests or zero consumers |
| **Pipeline types** | `PipelineResult`, `GateOutcome`, `IntentPipelineInput`, `IntentPipelineMetrics`, `QuantizePipelineInput`, `evaluate_intent_pipeline` | Return type / input of excluded functions; zero surviving consumers |
| **Assembly wiring** | `AssembledPipelineParams`, `SizingParams`, `assemble_sizing`, `choke_intent_to_dispatch`, `evaluate_assembled_pipeline`, `AssemblySizingError`, `AssembledSizing` | Internal pipeline wiring |
| **OPEN runtime wiring** | `OpenRuntimeInput`, `OpenRuntimeMetrics`, `OpenRuntimeOutput`, `build_open_intent_with_assembly`, `build_open_order_intent_runtime`, `settle_pending_on_tlsm_terminal` | Internal pipeline wiring |
| **Liquidity gate** | `LiquidityGateInput`, `LiquidityGateResult`, `LiquidityGateDecision`, `LiquidityGateRejectReason`, `LiquidityGateMetadata`, `LiquidityGateMetrics`, `GateIntentClass`, `L2BookSnapshot`, `L2Level`, `evaluate_liquidity_gate`, `expected_slippage_bps_samples`, `liquidity_gate_reject_total` | Gate internals |
| **Net edge gate** | `NetEdgeInput`, `NetEdgeResult`, `NetEdgeRejectReason`, `NetEdgeMetrics`, `evaluate_net_edge`, `net_edge_reject_total` | Gate internals |
| **Pricer gate** | `PricerInput`, `PricerResult`, `PricerRejectReason`, `PricerMetrics`, `compute_limit_price`, `pricer_reject_total` | Gate internals |
| **Quantize gate** | `QuantizeConstraints`, `QuantizeError`, `QuantizeMetrics`, `QuantizeStaticRejectReason`, `QuantizedValues`, `quantize`, `quantize_reject_total` (`Side` stays public) | Gate internals |
| **Preflight gate** | `PreflightInput`, `PreflightResult`, `PreflightReject`, `PreflightMetrics`, `OrderType`, `preflight_intent`, `preflight_reject_total` | Gate internals |
| **Base gates** | `BaseGatesInput`, `BaseGatesLegacy`, `BaseGatesMetrics`, `BaseGatesPassed`, `BaseGatesRejection`, `evaluate_base_gates` | Gate internals |
| **Post-only guard** | `PostOnlyInput`, `PostOnlyResult`, `PostOnlyMetrics`, `check_post_only`, `post_only_reject_total` | Gate internals |
| **Inventory skew** | `InventorySkewInput`, `InventorySkewResult`, `InventorySkewRejectReason`, `InventorySkewMetrics`, `evaluate_inventory_skew`, `inventory_skew_reject_total` | Gate internals |
| **Dispatch map** | `DispatchConsistencyProof`, `DispatchRequest`, `ValidatedDispatch`, `IntentClass`, `DispatchMapError`, `CONTRACTS_AMOUNT_MATCH_TOLERANCE`, `MismatchMetrics`, `map_to_dispatch`, `validate_and_dispatch` | Zero consumers or must-move only |
| **Domain types** | `OrderSizeError`, `ParsedLabel` | All consumers in must-move tests |
| **Group internals** | `GroupPersistence`, `group_lock_timeout_total`, `group_mixed_failed_total`, `group_persist_fail_total` | Trait zero consumers; metrics §10 rule |
| **TLSM internals** | `NoopTransitionSink`, `ooo_count`, `ooo_total` | Test utility zero consumers; metrics §10 rule |
| **Reject reason** | `reject_reason_from_chokepoint` | Zero external consumers |

### 3. Internal Wire Types — Phase 1 vs Phase 2

**Phase 1 (this design):** Wire types remain `pub` in their source files. Privacy
is enforced structurally — their parent modules are `mod` (not `pub mod`), so external
crates cannot reach them. Within `soldier_core`, they remain fully accessible for
pipeline wiring and `#[cfg(test)]` unit tests. Integration tests in `tests/` also
cannot reach them (module is private), which is the forcing function for test moves.

**Phase 2 (future):** Once contract-level input types (`ExecutionInput` /
`ExecutionEngine::decide()`) replace the pipeline wiring structs, then wire types
can become `pub(crate)`:

```rust
// Phase 2 ONLY (gate.rs) — after contract input types exist
pub(crate) struct LiquidityGateInput { ... }
pub(crate) fn evaluate_liquidity_gate(...) -> LiquidityGateResult { ... }
```

**Do not attempt `pub` → `pub(crate)` in Phase 1.** `OpenRuntimeInput`,
`IntentPipelineInput`, and `AssembledPipelineParams` embed these types as public
fields. Making field types `pub(crate)` while the containing struct is `pub` is a
compile error.

### 4. Move Tests — `tests/` → `#[cfg(test)]` Unit Tests

Each integration test file that touches internal wire types gets moved next to the code
it tests. These tests immediately start running in `verify.sh quick`.

**Tests that MUST move** (they construct internal wire types):

| Integration test file | Move to |
|----------------------|---------|
| `tests/test_liquidity_gate.rs` | `src/execution/gate.rs` `#[cfg(test)] mod tests` |
| `tests/test_net_edge_gate.rs` | `src/execution/gates.rs` `#[cfg(test)] mod tests` |
| `tests/test_pricer.rs` | `src/execution/pricer.rs` `#[cfg(test)] mod tests` |
| `tests/test_quantize.rs` | `src/execution/quantize.rs` `#[cfg(test)] mod tests` |
| `tests/test_preflight.rs` | `src/execution/preflight.rs` `#[cfg(test)] mod tests` |
| `tests/test_post_only_guard.rs` | `src/execution/post_only_guard.rs` `#[cfg(test)] mod tests` |
| `tests/test_inventory_skew.rs` | `src/execution/inventory_skew.rs` `#[cfg(test)] mod tests` |
| `tests/test_base_gates.rs` | `src/execution/base_gates.rs` `#[cfg(test)] mod tests` |
| `tests/test_gate_outcome.rs` | `src/execution/gate_outcome.rs` `#[cfg(test)] mod tests` |
| `tests/test_order_size.rs` | `src/execution/order_size.rs` `#[cfg(test)] mod tests` |
| `tests/test_label.rs` | `src/execution/label.rs` `#[cfg(test)] mod tests` |
| `tests/test_dispatch_map.rs` | `src/execution/dispatch_map.rs` `#[cfg(test)] mod tests` |
| `tests/test_intent_assembly.rs` | `src/execution/intent_assembly.rs` `#[cfg(test)] mod tests` |
| `tests/test_intent_pipeline.rs` | `src/execution/pipeline.rs` `#[cfg(test)] mod tests` |
| `tests/test_open_runtime_wiring.rs` | `src/execution/open_runtime.rs` `#[cfg(test)] mod tests` |
| `tests/test_static_rejection_counters.rs` | Split — see counter mapping table below |
| `tests/test_rejection_side_effects.rs` | Split: gate parts → gate files, pipeline parts → `pipeline.rs` |
| `tests/test_gate_ordering.rs` | `src/execution/build_order_intent.rs` `#[cfg(test)] mod tests` |
| `tests/test_intent_determinism.rs` | Move: uses `PricerInput`, `QuantizeConstraints` directly |
| `tests/test_intent_id_propagation.rs` | Move: uses `PricerInput`, `QuantizeConstraints` directly |
| `tests/test_missing_config.rs` | Move: builds full gate inputs |
| `tests/common/mod.rs` | **Delete.** Helpers split per-module into `#[cfg(test)]` blocks. |
| `tests/prop_net_edge.rs` | `src/execution/gates.rs` `#[cfg(test)]` |
| `tests/prop_liquidity_gate.rs` | `src/execution/gate.rs` `#[cfg(test)]` |
| `tests/prop_quantize.rs` | `src/execution/quantize.rs` `#[cfg(test)]` |
| `tests/prop_label.rs` | `src/execution/label.rs` `#[cfg(test)]` |
| `tests/prop_tlsm.rs` | `src/execution/tlsm.rs` `#[cfg(test)]` |
| `tests/prop_pipeline_gi001.rs` | `src/execution/pipeline.rs` `#[cfg(test)]` |

**`test_static_rejection_counters.rs` split mapping:**

| Counter tests (fn names) | Target module | Counter function |
|--------------------------|---------------|------------------|
| `test_inventory_skew_*` (3 tests) | `src/execution/inventory_skew.rs` | `inventory_skew_reject_total` |
| `test_pricer_*` (2 tests) | `src/execution/pricer.rs` | `pricer_reject_total` |
| `test_quantize_*` (3 tests) | `src/execution/quantize.rs` | `quantize_reject_total` |
| `test_post_only_*` (3 tests) | `src/execution/post_only_guard.rs` | `post_only_reject_total` |
| `test_group_*` (3 tests) | `src/execution/group.rs` | `group_lock_timeout_total`, `group_mixed_failed_total`, `group_persist_fail_total` |
| `test_fee_staleness_*` (3 tests) | **Keep in `tests/`** — uses `risk` module, not execution internals |
| `test_margin_gate_*` (2 tests) | **Keep in `tests/`** — uses `risk` module |
| `test_pending_exposure_*` (2 tests) | **Keep in `tests/`** — uses `risk` module |
| `test_exposure_budget_*` (3 tests) | **Keep in `tests/`** — uses `risk` module |

After the split, rename the remaining integration test file to
`tests/test_static_rejection_counters_risk.rs` (10 tests, risk-only imports).

**Tests that stay in `tests/`** (use only contract types):

| Integration test file | Why it stays |
|----------------------|-------------|
| `tests/test_tlsm.rs` | TLSM types are contract-level (stays public) |
| `tests/test_atomic_group.rs` | Group types are contract-level |
| `tests/test_reject_reason.rs` | RejectReasonCode is contract-level |
| `tests/adversarial_gi_enforcement.rs` | Highest-value contract test. **Must be rewritten in this migration** (see §4a below). Currently calls `evaluate_intent_pipeline()` directly (excluded from facade) and depends on `common::base_open_input()` which constructs `IntentPipelineInput` with internal wire types. Rewrite to use chokepoint surface only (`build_order_intent_with_*`, `GateResults`, `RejectReasonCode`). Pipeline-level assertions (e.g., "missing liquidity input → LiquidityGateNoL2") move to `pipeline.rs` unit tests. |
| `tests/test_dispatch_chokepoint.rs` | Architectural constraint test (file scanning) |
| `tests/test_idempotency.rs` | Uses `idempotency` module, not execution internals |
| `tests/test_label_match.rs` | Uses `recovery` module |
| `tests/test_capabilities.rs` | Uses `venue` module |
| `tests/test_margin_gate.rs` | Uses `risk` module |
| `tests/test_fee_staleness.rs` | Uses `risk` module |
| `tests/test_pending_exposure.rs` | Uses `risk` module |
| `tests/test_exposure_budget.rs` | Uses `risk` module |
| `tests/test_instrument_kind_mapping.rs` | Uses `venue` module |
| `tests/test_instrument_cache_ttl.rs` | Uses `venue` module |
| `tests/test_expiry_guard.rs` | Uses `venue` module |
| `tests/test_recorded_before_dispatch_gate.rs` | Uses `RecordedBeforeDispatchGate` (public) |

### 4a. `adversarial_gi_enforcement.rs` — Chokepoint-Level Rewrite

This test currently calls `evaluate_intent_pipeline()` directly and imports
`IntentPipelineMetrics` — both excluded from the facade. It also depends on
`common::base_open_input()` which constructs `IntentPipelineInput` with internal
wire types (`LiquidityGateInput`, `NetEdgeInput`, `PricerInput`). This contradicts
"pipeline wiring is not contract."

**Fix: rewrite to chokepoint-level contract surface.**

The 15 pipeline tests (GI-001, GI-002, GI-004, GI-009, GI-017) must be rewritten
to exercise the contract through chokepoint functions:

```rust
// BEFORE (calls excluded pipeline entrypoint):
use soldier_core::execution::{evaluate_intent_pipeline, IntentPipelineMetrics, ...};
let result = evaluate_intent_pipeline(&input, &mut metrics);

// AFTER (uses facade-only chokepoint surface):
use soldier_core::execution::{
    build_order_intent_with_wal_gate, GateResults, RejectReasonCode, ChokeResult, ...
};
let result = build_order_intent_with_wal_gate(&gate_results);
```

**Pipeline-level assertions that test internal gate wiring** (e.g., "missing
`LiquidityGateInput` → `LiquidityGateNoL2`", "missing `NetEdgeInput` →
`NetEdgeMissingInput`") are valuable but belong in `pipeline.rs` `#[cfg(test)]`
unit tests, not in integration tests.

The 4 hash tests (GI-020) use `compute_intent_hash()` from `idempotency` — these
are already facade-clean and stay unchanged.

### 5. `tests/common/mod.rs` — The Coupling Vector

This shared helper module currently constructs gate-level wire types
(`LiquidityGateInput`, `NetEdgeInput`, `PricerInput`, `L2BookSnapshot`, etc.)
for use by integration tests. It is the primary vector through which internals
leak into the contract surface.

**Fix:** Delete `common/mod.rs`. Each gate's test builders become `#[cfg(test)]`
helpers inside the gate's source file:

```rust
// src/execution/gate.rs
#[cfg(test)]
pub(crate) mod test_builders {
    use super::*;

    pub(crate) fn default_liquidity_input() -> LiquidityGateInput {
        LiquidityGateInput { /* defaults */ }
    }
}
```

These builders use `super::*` and are visible within the crate under `#[cfg(test)]`.
If a unit test in `pricer.rs` needs a `LiquidityGateInput` for a wiring test,
it imports `crate::execution::gate::test_builders::default_liquidity_input`.

### 6. Inline vs Sibling Test Files

For modules where the unit tests are large (>200 lines), use the sibling pattern:

```rust
// src/execution/gate.rs
#[cfg(test)]
mod gate_tests;

// src/execution/gate_tests.rs — same visibility as inline, cleaner file
```

This keeps the source file readable while still getting `--lib` coverage.

### 7. TOC Fix — Smoke-Contract Lane in `verify.sh`

Problem: `verify.sh quick` runs `cargo test --workspace --lib`, which skips
`crates/soldier_core/tests/`. After this refactor, only contract tests remain
there, but they're still invisible to the fast loop.

**Fix: Add a `smoke` lane to `verify.sh quick`, immediately after `--lib`.**

```bash
# verify.sh quick — add after the existing `cargo test --workspace --lib --locked` line:

# ── Smoke contract tests (facade-only integration tests) ──
cargo test -p soldier_core --test adversarial_gi_enforcement
cargo test -p soldier_core --test test_dispatch_chokepoint
cargo test -p soldier_core --test test_reject_reason
cargo test -p soldier_core --test test_tlsm
```

Selection rationale:
- `adversarial_gi_enforcement` — chokepoint-level GI guards (rewritten in §4a)
- `test_dispatch_chokepoint` — architectural invariant scan (updated in §8a)
- `test_reject_reason` — reject code registry completeness
- `test_tlsm` — lifecycle state machine contract

This adds seconds, not minutes. The constraint (fast contract feedback) is
directly elevated.

**Modes become:**

| Mode | What runs |
|------|-----------|
| `quick` | `--lib` + smoke contract tests (4 integration tests) |
| `full` | Everything (unchanged) |

### 8. Cross-Crate Impact

**Production code (`soldier_infra`):** Only import is `RecordedBeforeDispatchGate`
in `wal.rs`. This type stays in the public facade. Zero breakage.

**Integration tests (`soldier_infra/tests/`):**
- `test_dispatch_durability.rs` — uses `RecordedBeforeDispatchGate` (public). No change.
- `test_ledger_replay.rs` — uses `Tlsm`, `TlsmEvent`, `TlsmState`, `TransitionResult` (all public). No change.

### 8a. Architectural Scan Tests — Required Updates

`test_dispatch_chokepoint.rs` contains 9 architectural constraint tests that use
string matching on source files. One will break after this refactor:

**`test_chokepoint_reexported_from_execution` (line 308–322):**
Asserts `mod.rs` contains `"pub mod build_order_intent"`. After Step 4, this becomes
`mod build_order_intent` — test fails.

**Fix:** Replace string-match with compile-time contract check:
```rust
#[test]
fn chokepoint_is_publicly_reachable() {
    // Proves the chokepoint function is reachable through the facade.
    // Fails at compile time if the re-export is removed.
    let _ = soldier_core::execution::build_order_intent;
    let _ = soldier_core::execution::build_order_intent_with_wal_gate;
}
```

**`test_dispatch_chokepoint_no_direct_exchange_client_usage` (line 137–197):**
Scans for 6 forbidden dispatch symbols (`DispatchRequest`, `dispatch_map::`, etc.)
and whitelists 4 files: `dispatch_map.rs`, `build_order_intent.rs`,
`intent_assembly.rs`, `mod.rs`. After Step 3, `mod.rs` no longer contains these
symbols (old re-exports deleted). After Step 4, `api.rs` exists but does **not**
contain dispatch symbols (they are CUT from the facade — see §2). The scan will
not flag either file. The existing `mod.rs` whitelist entry becomes inert but
harmless. **No whitelist change is required.**

These fixes belong in Step 4 (same commit as the `pub mod` → `mod` flip).

### 9. Proof Step — Compiler Enforcement

After the refactor, deep module path imports fail at compile time:

```rust
// crates/soldier_infra/src/some_new_file.rs
use soldier_core::execution::gate::LiquidityGateInput;
//                            ^^^^ error: module `gate` is private
```

Facade-level imports work for contract types:

```rust
use soldier_core::execution::Side;              // OK — in api.rs
use soldier_core::execution::RejectReasonCode;  // OK — in api.rs
use soldier_core::execution::Tlsm;              // OK — in api.rs
```

**Phase 1 limitation:** Wire types not in `api.rs` (like `LiquidityGateInput`) are
still technically `pub` in their source files, but unreachable because their parent
modules are private. The lint gate (Step 5 of migration) enforces that no one adds
`pub mod gate;` back. Phase 2 makes them `pub(crate)` for defense-in-depth.

### 10. Metrics as Contract — Explicit Decision

Counter functions like `liquidity_gate_reject_total()` are currently tested in
integration tests. After this refactor, they're internal.

**Rule:** Metrics are NOT part of the contract unless explicitly declared.
Individual gate counter functions (`liquidity_gate_reject_total`,
`pricer_reject_total`, etc.) are internal observability. Tests that assert
specific counter values belong next to the gate code.

The only metrics that could be contract-level are aggregate ones surfaced through
`/status` (e.g., `gate_sequence_total`). Those are already in the facade.

### 11. Migration Order

Each step is a standalone commit for clean bisection. Steps must be done in order.
**Every intermediate commit must compile and pass `cargo test --workspace`.**

**Rollback:** Each step is a single atomic commit. Rollback is `git revert <commit>`.
No migration state files or cleanup needed.

**Step 1a: Add `api.rs` skeleton (single commit).**
Create `api.rs` with contract-type re-exports. Add `pub mod api;` to `mod.rs`.
Do **not** add `pub use api::*;` yet — existing `pub use` blocks in `mod.rs`
still re-export the same names, and `pub use api::*` would conflict (`E0252`).
At this point `execution::api::Side` works, but `execution::Side` still routes
through the old re-exports. Zero behavioral change.

**Step 1b: Migrate contract tests to facade path (one commit per test file).**
Update integration tests that will stay in `tests/` to import from
`soldier_core::execution::api::{...}` instead of `soldier_core::execution::{...}`.
This proves the facade is correct before forcing everyone through it.
After Step 3 (below), normalize these paths back to `soldier_core::execution::{...}`
— once `pub use api::*` is active, the shorter path resolves through the facade
and is the canonical import style.

**Step 2: Move internal tests + rewrite GI tests (one commit per module).**
Start with the simplest (single-gate tests like `test_pricer.rs`), end with complex
multi-gate tests. Split `tests/common/mod.rs` builders per-module into `#[cfg(test)]`
blocks. Delete `common/mod.rs` last. Rewrite `adversarial_gi_enforcement.rs` to use
chokepoint surface only (see §4a); move pipeline-level assertions into `pipeline.rs`
unit tests. Once all test files that call `with_intent_trace_ids` /
`take_execution_metric_lines` are moved, change both to `pub(crate)` (see §1).
Each move is a standalone commit. Verify with `cargo test --workspace` after each.

**Why Step 2 before Step 3:** Old re-exports still exist in `mod.rs`, so the
remaining integration tests (`test_tlsm.rs`, `test_atomic_group.rs`, etc.) continue
to compile via `soldier_core::execution::LiquidityGateInput` even while must-move
tests are being relocated. Moving tests first eliminates all consumers of non-facade
re-exports, making Step 3 safe.

**Step 3: Flip re-exports — old blocks → `pub use api::*` (single commit).**
Delete the 19 `pub use` blocks from `mod.rs` and replace with `pub use api::*;`.
Now `execution::Side` routes through `api.rs`. Must be atomic — cannot have
both the old blocks and `pub use api::*` in the same compilation unit.
All consumers of non-facade symbols were moved in Step 2, so nothing breaks.
Normalize Step 1b's `::api::` paths back to `execution::{...}` in this commit.

**Step 4: Flip module visibility — `pub mod` → `mod` + fix architectural tests (single commit).**
Change all 19 `pub mod` declarations to `mod` (except `api`). Fix any external
imports that used deep module paths (e.g., `execution::gate::...` → `execution::...`).
Wire types remain `pub` in their source files. `pub` → `pub(crate)` is **not** done
here (see §3 — deferred to Phase 2).
Also update `test_dispatch_chokepoint.rs` (see §8a): replace
`test_chokepoint_reexported_from_execution` string match with compile-time
contract check.

**Step 5: Add smoke lane to `verify.sh quick` (single commit).**
After `cargo test --workspace --lib`, run highest-value contract tests:
`adversarial_gi_enforcement`, `test_dispatch_chokepoint`,
`test_reject_reason`, `test_tlsm`.

**Step 6: Add enforcement gate (single commit).**
Add a lint script or compile-fail test that asserts:
- Only one `pub mod` in `execution/mod.rs`: `api`
- No external crate imports `execution::<submodule>::...` (deep paths)
This prevents backsliding.

**Step 7: Verify.**
`verify.sh quick` (now runs gate unit tests + smoke contract tests), then
`verify.sh full`.

**NOT in this migration (Phase 2):** `pub` → `pub(crate)` on wire types. That
requires building contract input types first (see §12).

### 12. Future Work (Not This Design)

- **Phase 2: Contract input types + wire type internalization.** Build
  `ExecutionEngine` with `ExecutionInput { market_snapshot, risk_snapshot,
  intent_request }` where the module internally derives `LiquidityGateInput`,
  `PricerInput`, etc. from domain-level inputs. Integration tests in `tests/`
  would test through `ExecutionEngine::decide()`. **Only after this can wire
  types become `pub(crate)`** — the blocking dependency for true encapsulation.
  Also rewrite `adversarial_gi_enforcement.rs` to use contract inputs instead
  of constructing `IntentPipelineInput` directly.

- **Phase 3: Other modules** — Apply same pattern to `risk/`, `venue/`,
  `idempotency/`, `recovery/`.

- **`test-helpers` feature** — Only introduce if reusable scenario builders are
  needed. Expose scenarios (like `liquidity_reject_scenario() -> ExecutionInput`),
  never internal types. Use `#[cfg(feature = "test-helpers")]` only for builders/
  fixtures, not for exposing wire types directly.

## Non-Goals

- Changing any runtime behavior
- Adding new tests (moved tests preserve existing coverage)
- Modifying CONTRACT.md or specs
- Touching `soldier_infra` module structure
- Building `ExecutionEngine` (Phase 2)
