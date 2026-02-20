# Unified Audit Report: Slices 0-6 — Keep / Patch / Quarantine

**Date**: 2026-02-18
**Scope**: `crates/soldier_core/` + `crates/soldier_infra/` (19 gates + infrastructure)
**Method**: 4 parallel agents (2x Audit B pattern conformance, 2x Audit C strategic failure), ~355K tokens, 135 tool calls
**Reference docs**: `specs/DESIGN_PATTERNS.md`, `specs/CONTRACT.md`

---

## QUARANTINE — Must fix before Slice 7

| # | Finding | Source | File(s) | Risk |
|---|---------|--------|---------|------|
| **Q1** | **Two parallel orchestration paths** | C(Opus)-5.5, C(Haiku)-4 | `pipeline.rs` + `open_runtime.rs` | Both independently wire gates into `build_order_intent()`. Gate ordering divergence has no compile-time enforcement. GateResults mutated in scattered locations across open_runtime. |
| **Q2** | **FeeCacheCheck: NaN fail-open** | B(Opus)-5 | `risk/fees.rs:138` | Non-finite `fee_stale_buffer` silently replaced with `0.0`. Forbidden by DESIGN_PATTERNS.md §1.1 and §2. |
| **Q3** | **PostOnlyGuard: NaN fail-open** | B(Opus)-15 | `post_only_guard.rs:91-102` | NaN `limit_price` silently passes — NaN comparisons always false. Post-only order dispatched without crossing detection. |
| **Q4** | **GroupLock: NaN in fills** | B(Opus)-19 | `group.rs:226-285` | NaN `filled_qty`/`requested_qty` makes atomicity checks unpredictable. |
| **Q5** | **Triple Intent Classification Enums** | C(Haiku)-1 | `build_order_intent.rs`, `dispatch_map.rs`, `gate.rs` | `ChokeIntentClass` has `CancelOnly`, `IntentClass` has `Cancel`, `GateIntentClass` has `CancelOnly`. Mismap between layers → CANCEL routed to wrong gates. |
| **Q6** | **dispatch_map hardcodes `RiskState::Healthy`** | C(Haiku)-5 | `dispatch_map.rs:222` | `validate_and_dispatch()` always returns `Healthy`. Callers must manually downgrade on AT-920 mismatch — implicit coupling with no enforcement. |
| **Q7** | **ExpiryGuard: zero observability** | B(Opus)-6 | `venue/lifecycle.rs` | No `*Metrics`, no counters, no tracing. Cannot debug in production. |

### Q1: Two parallel orchestration paths

**Files**: `crates/soldier_core/src/execution/pipeline.rs` + `crates/soldier_core/src/execution/open_runtime.rs`

Both `evaluate_intent_pipeline()` and `build_open_order_intent_runtime()` independently construct `GateResults` and feed into the same chokepoint (`build_order_intent()`). Gate ordering and skip logic is implemented independently in each path. A change to gate ordering in one path must be manually replicated in the other. Additionally, `open_runtime.rs` mutates `GateResults` fields in scattered locations (lines 135-137, 149-151, 158-174, 183-224, 232-237), making the evaluation order implicit rather than declarative.

**Resolution**: Consolidate into a single wiring path before Slice 7 adds complexity. Return individual gate results from evaluation functions and assemble `GateResults` in a single deterministic pass.

### Q2: FeeCacheCheck NaN fail-open + warn-and-continue

**File**: `crates/soldier_core/src/risk/fees.rs:138`

Non-finite `fee_stale_buffer` is silently replaced with `0.0`. This is the exact anti-pattern DESIGN_PATTERNS.md §1.1 forbids ("No epsilon-clamping fallbacks — validate preconditions, don't silently fix bad inputs") and §2 ("NaN/Inf in safety path → Reject or most restrictive state, Never warn and continue").

Additionally, `FeeEvaluation` is a plain struct, not a two-variant enum. No `AtomicU64` statics. No `tracing::debug!` on hard-stale path.

**Resolution**: Non-finite `fee_stale_buffer` should trigger HardStale/Degraded rejection. Refactor `FeeEvaluation` to two-variant enum with diagnostics in both branches.

### Q3: PostOnlyGuard NaN fail-open

**File**: `crates/soldier_core/src/execution/post_only_guard.rs:91-102`

NaN `limit_price` silently passes because NaN comparisons (`>=`, `<=`) always return `false`, meaning a NaN limit price never "crosses" the touch. A post-only order with NaN limit price would be dispatched without crossing detection.

Additionally: no diagnostics in either branch, no reason enum, `PostOnlyMetrics` only has `reject_total`.

**Resolution**: Add `is_finite()` check on `limit_price`. NaN must reject (fail-closed). Add diagnostics and typed reject reason enum.

### Q4: GroupLock NaN in fills

**File**: `crates/soldier_core/src/execution/group.rs:226-285`

NaN `filled_qty` or `requested_qty` would make atomicity checks (`max_f - min_f <= epsilon`) behave unpredictably. No `is_finite()` validation in `apply_leg_result()` or `is_atomicity_intact()`.

Also missing: `GroupMetrics` struct entirely, `try_acquire_at()` for deterministic testing.

**Resolution**: Add `is_finite()` checks. NaN should trigger MixedFailed fail-closed. Add `GroupMetrics` and `try_acquire_at(now: Instant)`.

### Q5: Triple Intent Classification Enums

**Files**:
- `crates/soldier_core/src/execution/build_order_intent.rs:40-50` — `ChokeIntentClass` (Open, Close, Hedge, CancelOnly)
- `crates/soldier_core/src/execution/dispatch_map.rs:29-39` — `IntentClass` (Open, Close, Hedge, Cancel)
- `crates/soldier_core/src/execution/gate.rs` — `GateIntentClass` (Open, Close, Hedge, CancelOnly)

Three different enums with conflicting variant names (`Cancel` vs `CancelOnly`). Mismap between layers could route CANCEL orders to OPEN gates or vice versa.

**Resolution**: Consolidate to a single authoritative enum. Add compile-time conversions if layers need distinct types.

### Q6: dispatch_map hardcodes RiskState::Healthy

**File**: `crates/soldier_core/src/execution/dispatch_map.rs:222`

`validate_and_dispatch()` always returns `RiskState::Healthy` in `ValidatedDispatch`. Comment at line 175 says "caller MUST set RiskState::Degraded" but there is no enforcement. AT-920 contract/amount mismatches increment metrics but return Healthy anyway.

**Resolution**: Return mismatch reason from `validate_and_dispatch()` making it impossible for callers to ignore.

### Q7: ExpiryGuard zero observability

**File**: `crates/soldier_core/src/venue/lifecycle.rs`

No `*Metrics` struct, no counters, no `tracing::debug!`, no `emit_execution_metric_line`. `ExpiryGuardResult::Allowed` has no diagnostics.

**Resolution**: Add `ExpiryGuardMetrics` with reject/allowed counters, structured tracing on reject, diagnostics in both branches.

---

## PATCH — Fix before next PRD merge

| # | Finding | Source | File(s) | Action |
|---|---------|--------|---------|--------|
| **P1** | Deprecated WAL bypass active | C(Opus)-5.6, C(Haiku)-3 | `pipeline.rs:335`, `open_runtime.rs:252` | Migrate to `build_order_intent_with_wal_gate()` |
| **P2** | Dual TLSM state enums | C(Opus)-2.4 | `tlsm.rs` + `ledger.rs` | Add test: `is_valid_successor()` matches `Tlsm::apply()` for all pairs |
| **P3** | RiskState computed in 4 locations | C(Opus)-2.1, C(Haiku)-2 | `fees.rs`, `cache.rs`, `open_runtime.rs:86-93,218-220` | Extract `worst_risk_state()` combinator |
| **P4** | 60+ inline `is_finite()` guards | C(Opus)-1.1 | All gate files | Extract `ensure_finite(v, label) -> Result` helper |
| **P5** | Dual metrics accounting | C(Opus)-1.2 | All gates with both struct + AtomicU64 | Unify — struct delegates to atomics |
| **P6** | Metric names are string literals | C(Opus)-3.3 | gate.rs, gates.rs, preflight.rs, build_order_intent.rs | Extract into `const` strings |
| **P7** | 10 gates missing AtomicU64/tracing | B(both) | Quantize, Pricer, MarginHeadroom, PendingExposure, GlobalExposureBudget, InventorySkew, PostOnlyGuard, FeeCacheCheck, ExpiryGuard, GroupLock | Add static counters + `tracing::debug!` + `emit_execution_metric_line` |
| **P8** | Preflight: Allowed has no diagnostics | B(Opus)-2 | `preflight.rs:72-77` | Add diagnostics field |
| **P9** | Pricer: no per-reason metrics | B(Opus)-9 | `pricer.rs:80-122` | Add per-reason breakdown |
| **P10** | WAL `eprintln!` in production | B(Opus)-18 | `ledger.rs:721` | Replace with `tracing::warn!` |
| **P11** | GroupLock: no `_at()` time injection | B(Opus)-19 | `group.rs:136` | Add `try_acquire_at(now: Instant)` |
| **P12** | Document CSP.3.2 exception | B(Opus)-10 | `build_order_intent.rs:454-459` | Add DESIGN_PATTERNS exception comment |
| **P13** | Hardcoded thresholds (fees, group lock) | C(Haiku)-P1 | `fees.rs`, `group.rs` | Document as debt for config integration |
| **P14** | Fallback reason codes mask root cause | C(Haiku)-P2 | `reject_reason.rs` | Add `tracing::warn!` when fallback is used |

---

## KEEP — No changes needed

| Gate/Finding | Notes |
|---|---|
| **DispatchAuth** (`build_order_intent.rs`) | Full pattern conformance: typed result, metrics, deterministic |
| **LiquidityGate** (`gate.rs`) | Reference implementation: is_finite on all inputs, AtomicU64, tracing, emit_metric |
| **NetEdge** (`gates.rs`) | Reference implementation: Option<f64> inputs, per-reason counters, emit_metric |
| **InstrumentCache** (`cache.rs`) | Reference: `_at()` methods, breach events, fail-closed on miss/non-finite TTL |
| **PendingExposure** (`pending_exposure.rs`) | Full pattern: is_finite, typed result, idempotent reserve/settle |
| **DispatchConsistency** (`build_order_intent.rs`) | Correctly typed: handles incomplete metadata with DISPATCH_CLAMP_INCOMPLETE |
| **GroupStateMachine** state enforcement | Terminal states block mutations, out-of-order handled gracefully |
| **RejectReasonCode registry** (`reject_reason.rs`) | Single enum, single mapper, serde SCREAMING_SNAKE documented |
| **`emit_execution_metric_line()` centralization** | Single thread-local VecDeque, 4096 cap, well-factored |
| **`opens_blocked()` single authority** | Sole gate check, well-tested |
| **WAL single-writer design** | Documented Phase 1 limitation |
| **TradeIdRegistry Mutex poison handling** | Fail-closed on poison |
| **Thread-local metric buffer** | Bounded, silent drop acceptable for Phase 1 |
| **WAL capacity** | Documented debt for multi-instrument |
| **PendingExposureBook RefCell** | Documented debt for async migration |
| **Metric counter overflow safety** | u64 counters: ~584B years at 1/ns |

---

## Audit B: Per-Gate Pattern Conformance Scorecard

```
| #  | Gate                       | Input Val | Fail-Closed | Reject Reason | Result Type | Observability | Determ Test | Verdict    |
|----|----------------------------|-----------|-------------|---------------|-------------|---------------|-------------|------------|
| 1  | DispatchAuth               | PASS      | PASS        | PASS          | PASS        | PASS          | PASS        | KEEP       |
| 2  | Preflight                  | PASS      | PASS        | PASS          | PARTIAL     | PASS          | PASS        | PATCH      |
| 3  | Quantize                   | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PASS        | PATCH      |
| 4  | DispatchConsistency        | PASS      | PASS        | PASS          | PASS        | PASS          | PASS        | KEEP       |
| 5  | FeeCacheCheck              | PASS      | PARTIAL     | PARTIAL       | PARTIAL     | PARTIAL       | PASS        | QUARANTINE |
| 6  | ExpiryGuard                | PARTIAL   | PASS        | PARTIAL       | PARTIAL     | FAIL          | PASS        | QUARANTINE |
| 7  | LiquidityGate              | PASS      | PASS        | PASS          | PASS        | PASS          | PASS        | KEEP       |
| 8  | NetEdgeGate                | PASS      | PASS        | PASS          | PASS        | PASS          | PASS        | KEEP       |
| 9  | Pricer                     | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PASS        | PATCH      |
| 10 | RecordedBeforeDispatch     | PASS      | PASS        | PASS          | PASS        | PASS          | PARTIAL     | PATCH      |
| 11 | MarginHeadroomGate         | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PASS        | PATCH      |
| 12 | PendingExposureReservation | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PASS        | PATCH      |
| 13 | GlobalExposureBudget       | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PASS        | PATCH      |
| 14 | InventorySkew              | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PASS        | PATCH      |
| 15 | PostOnlyGuard              | PARTIAL   | PASS        | PARTIAL       | PARTIAL     | PARTIAL       | PASS        | QUARANTINE |
| 16 | VenueCapabilities          | PASS      | PASS        | PARTIAL       | PARTIAL     | FAIL          | PASS        | QUARANTINE |
| 17 | InstrumentCacheTTL         | PASS      | PASS        | PASS          | PARTIAL     | PASS          | PASS        | PATCH      |
| 18 | WAL Ledger                 | PASS      | PASS        | PASS          | PASS        | PARTIAL       | PARTIAL     | PATCH      |
| 19 | GroupLock/Persistence       | PARTIAL   | PASS        | PARTIAL       | PARTIAL     | FAIL          | PARTIAL     | QUARANTINE |
```

**Summary**: 4 KEEP, 10 PATCH, 5 QUARANTINE

---

## Audit C: Strategic Failure Findings

| Category | Findings | KEEP | PATCH | QUARANTINE |
|----------|----------|------|-------|------------|
| 1. Duplicated Logic | 5 | 3 | 2 | 0 |
| 2. Multiple Sources of Truth | 4 | 2 | 2 | 0 |
| 3. Naming Conventions | 4 | 3 | 1 | 0 |
| 4. Global State / Locks | 5 | 5 | 0 | 0 |
| 5. Single Points of Failure | 6 | 3 | 2 | 1 |

**Totals: 24 findings — 16 KEEP, 7 PATCH, 1 QUARANTINE**

---

## Key Insight: Slice 3 vs Slice 4-6 Drift

All four agents independently confirmed the same pattern: **Slice 3 gates** (LiquidityGate, NetEdge, Preflight) have full observability scaffolding — AtomicU64 statics, `tracing::debug!`, `emit_execution_metric_line`. **Slice 4-6 gates** (Quantize, Pricer, MarginHeadroom, PendingExposure, GlobalExposureBudget, InventorySkew) copied the result-type pattern but dropped the observability layer. This is the exact drift `specs/DESIGN_PATTERNS.md` was created to prevent.

---

## Not Implemented (acknowledged Slice 7+ scope)

- PolicyGuard (logic embedded in chokepoint — extract when TradingMode is implemented)
- FundingRateGuard
- VolatilityGuard
- LatencyGuard
- WashTradeGuard
- DuplicateOrderGuard

---

## Execution Priority

```
IMMEDIATE (safety):     Q2, Q3, Q4         — NaN fail-opens, smallest patches
ARCHITECTURAL (blocks): Q1, Q5, Q6         — structural consolidation
OBSERVABILITY:          Q7, P7, P8, P9     — can batch
INFRASTRUCTURE:         P1-P6, P10-P14     — can parallelize
```
