# S1-002 Reconciliation R1 Preflight Audit

**Story**: S1-002 -- S1.1 InstrumentKind and RiskState
**Date**: 2026-02-23
**Mode**: READ-ONLY (no production code or test edits)
**Auditor**: Claude Opus 4.6 (reconciliation agent)
**Git status**: Verified unchanged at start and end (read-only integrity confirmed)

---

## A) GATE RESULT

**PASS WITH OBSERVATIONS**

All enforcement points for AT-333 are implemented and tested. The `derive_instrument_kind` function returns `None` on unrecognized input (fail-closed), and pipeline-level tests in `test_intent_assembly.rs` prove that unknown kinds cause dispatch rejection with `dispatch_count=0` and `RejectReasonCode::AssemblyFailed`. The RiskState enum has all 4 contract-required variants and is consumed throughout the codebase.

Two observations noted (not blocking):
1. Stale TODO comment in `types.rs:46` says function is "only called from unit tests" -- this is factually incorrect since `assemble_sizing` (called from `open_runtime.rs:408`) invokes `derive_instrument_kind` in production.
2. Premortem Assumption #2 (USDC-margined perpetual metadata detection) remains unvalidated against live API, as noted in the YELLOW stoplight. However, the abstraction layer (`InstrumentKindInput`) decouples the derivation logic from venue-specific metadata extraction, making this a wiring concern outside S1-002 scope.

---

## B) AT AUDIT TABLE

| AT ID | Contract section | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | wrong-impls blocked (premortem section 5)? | decisions as chosen (premortem section 4)? | Verdict |
|-------|---------|----------------------------------------|-----------------|---------------|--------------|---------------------|----------------------|---------|
| AT-333 | section 1.0 Instrument Units and Notional Invariants (line 710-715) | `crates/soldier_core/src/venue/types.rs:55::derive_instrument_kind` | `test_all_instrument_kinds_derivable`, `test_option_maps_to_option`, `test_btc_perpetual_maps_to_perpetual`, `test_usdc_margined_perpetual_maps_to_linear_future`, `test_btc_dated_future_maps_to_inverse_future`, `test_usdc_dated_future_maps_to_linear_future`, `test_combo_instruments_return_none`, `test_linear_priority_over_perpetual`, `test_option_priority_over_future_when_both_set`, `test_get_instruments_realistic_payloads`, `test_instrument_metadata_uses_get_instruments` | PROVEN | YES | YES | YES | PASS |
| AT-333 (pipeline causality) | section 1.0 | `crates/soldier_core/src/execution/intent_assembly.rs:112` (`.ok_or(AssemblySizingError::UnknownInstrumentKind)?`) | `test_assembly_unknown_kind_fails_closed`, `test_assembled_pipeline_unknown_kind_rejects` | PROVEN (dispatch_count=0, RejectReasonCode::AssemblyFailed) | YES | YES | YES | PASS |
| (implicit: RiskState) | Definitions (line 92) | `crates/soldier_core/src/risk/state.rs:13::RiskState` | `test_riskstate_has_all_variants`, `test_riskstate_derives` | PROVEN (4 variants, all distinct, Copy+Clone+Eq+Hash) | N/A (enum definition) | YES | N/A | PASS |

---

## C) PREMORTEM CROSS-REFERENCE

### Section 2 Assumptions

| # | Assumption | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Deribit `kind` field values are `option`, `future`, `option_combo` | VALIDATED | `InstrumentKindInput` abstraction decouples from raw Deribit values. `test_get_instruments_realistic_payloads` (test file line 234-299) covers BTC-PERPETUAL, BTCUSDC-PERP, ETH option, BTC dated future, and combo instruments with comments showing the Deribit field derivation. |
| 2 | USDC-margined perpetuals have detectable metadata | DEFERRED (YELLOW debt) | `is_linear` flag in `InstrumentKindInput` (types.rs:43) represents `settlement_currency == quote_currency`. Tested via `test_usdc_margined_perpetual_maps_to_linear_future` (test file line 44-55). Live API validation still pending per premortem debt register. |
| 3 | S1-011 struct includes `kind` field accessible to conversion logic | VALIDATED | `InstrumentKindInput` is a standalone struct (types.rs:35-44) that decouples from S1-011. Callers construct it from venue metadata. Compile-time check: `test_assembly_unknown_kind_fails_closed` uses `InstrumentKindInput` directly. |
| 4 | RiskState enum requires exactly 4 variants | VALIDATED | `test_riskstate_has_all_variants` (test file line 305-324) constructs all 4 variants, asserts length=4, and verifies all pairs are distinct. Exhaustive `match` arms used throughout codebase (e.g., `cache.rs:282-285`). |

### Section 4 Decisions

| Decision | Chosen option | Implemented as chosen? | Evidence |
|----------|--------------|----------------------|----------|
| How to distinguish perpetual vs linear_future vs inverse_future | Option A: settlement_currency + instrument metadata | YES | `InstrumentKindInput` uses `is_linear` (settlement=quote check), `is_perpetual`, `is_future` flags. `derive_instrument_kind` at types.rs:55-86 implements the decision tree: linear check first (line 71), then perpetual (line 76), then inverse (line 81). |
| Fail behavior for unknown instrument kind | Option A: Return error, block instrument | YES | `derive_instrument_kind` returns `None` for unknown/contradictory inputs (types.rs:63,85). `assemble_sizing` converts to `AssemblySizingError::UnknownInstrumentKind` (intent_assembly.rs:112). Pipeline rejects with `RejectReasonCode::AssemblyFailed` and dispatch_count=0 (proven by `test_assembled_pipeline_unknown_kind_rejects`). |

### Section 5 Wrong Implementations

| Wrong impl | Blocked? | Evidence |
|-----------|----------|----------|
| Hardcode InstrumentKind based on instrument name string matching | YES | `derive_instrument_kind` takes `InstrumentKindInput` with boolean flags, not strings. `test_get_instruments_realistic_payloads` uses name strings only as test labels; actual mapping is via metadata flags. No string matching in production code. |
| Map all futures to `linear_future` regardless of settlement currency | YES | `test_btc_perpetual_maps_to_perpetual` (line 29-40) and `test_btc_dated_future_maps_to_inverse_future` (line 58-70) explicitly prove non-linear futures map to Perpetual and InverseFuture respectively. Table-driven `test_all_instrument_kinds_derivable` covers all 4 variants. |
| RiskState enum with only 2 variants (Healthy, Kill) | YES | `test_riskstate_has_all_variants` asserts exactly 4 variants and all are distinct. Adding or removing variants would fail this test. Exhaustive match in `opens_blocked` (cache.rs:282-285) catches `Degraded | Maintenance | Kill`. |

---

## D) DESIGN RISK NOTES

### D1: Stale TODO comment (LOW)
`crates/soldier_core/src/venue/types.rs:46` contains:
```
// TODO(slice-N): Wire into production dispatch -- currently only called from unit tests
```
This comment is factually stale. `derive_instrument_kind` is called from `assemble_sizing` (intent_assembly.rs:111), which is called from `open_runtime.rs:408` -- the production OPEN dispatch path. The TODO should be removed to avoid confusion during future audits.

### D2: No serde derives on InstrumentKind or RiskState (INFO)
Neither `InstrumentKind` (types.rs:16-26) nor `RiskState` (state.rs:12-25) derive `Serialize`/`Deserialize`. The premortem section 3 failure mode #5 identified serde serialization mismatch as a risk. Currently there is no serde requirement for these enums (they are used as in-memory types), but if they are ever serialized (e.g., for /status endpoint or logging), serde derives with `#[serde(rename_all = "snake_case")]` should be added. This is not a current defect.

### D3: No metrics/counters on derivation path (INFO)
The premortem section 7 lists `instrument_cache_refresh_errors_total` as a drift metric, but this belongs to S1-003 (cache TTL), not S1-002. The `derive_instrument_kind` function itself has a `tracing::warn!` on contradictory flags (types.rs:58-63) but no counter for derivation failures. For S1-002's scope (pure enum derivation), this is acceptable -- the counter lives at the `assemble_sizing` level where `AssemblySizingError` is surfaced.

### D4: Contradictory flag handling (GOOD)
The function explicitly handles the case where both `is_option` and `is_future` are true (types.rs:57-64), returning `None` with a structured warning log. This is a proper fail-closed pattern. Test coverage: `test_option_priority_over_future_when_both_set` (test file line 170-180).

---

## E) REMEDIATION PLAN

| # | Finding | Severity | Action | Owner | Target |
|---|---------|----------|--------|-------|--------|
| E1 | Stale TODO comment at types.rs:46 | LOW | Remove or update the comment to note that production wiring exists via `assemble_sizing` in `open_runtime.rs` | S1-002 owner | Next touch |
| E2 | Premortem Assumption #2 (USDC-margined perpetual metadata) remains unvalidated against live Deribit API | MEDIUM (deferred debt from premortem) | Validate with real API response fixture when live API access is available. The `InstrumentKindInput` abstraction mitigates risk. | S1-002 owner | Pre-production |
| E3 | No dedicated counter for `derive_instrument_kind` failures | LOW | Not needed at S1-002 scope -- failures are counted at the `assemble_sizing` layer. Monitor if observability gaps appear. | N/A | No action needed |

**No blocking findings. No code changes required for reconciliation pass.**

---

## F) SCOPE CHECK

### Files in scope.touch vs actual enforcement

| File | In scope.touch? | Reviewed? | Finding |
|------|----------------|-----------|---------|
| `crates/soldier_core/src/venue/mod.rs` | YES | YES | Correctly re-exports `InstrumentKind`, `InstrumentKindInput`, `derive_instrument_kind` (line 19) |
| `crates/soldier_core/src/venue/types.rs` | YES | YES | Contains `InstrumentKind` enum (line 17), `InstrumentKindInput` struct (line 35), `derive_instrument_kind` function (line 55). All 4 contract variants present. |
| `crates/soldier_core/src/risk/state.rs` | YES | YES | Contains `RiskState` enum (line 13) with all 4 contract variants: Healthy, Degraded, Maintenance, Kill |
| `crates/soldier_core/src/risk/mod.rs` | YES | YES | Correctly re-exports `RiskState` (line 35) |
| `crates/soldier_core/src/lib.rs` | YES | YES | Exposes `risk` and `venue` modules (lines 6-7) |
| `crates/soldier_core/tests/test_instrument_kind_mapping.rs` | YES | YES | 13 tests covering all derivation paths, realistic payloads, metadata-affects-sizing proof, RiskState variants, and RiskState derives. All 13 pass. |

### Out-of-scope files reviewed for pipeline causality

| File | Why reviewed | Finding |
|------|-------------|---------|
| `crates/soldier_core/src/execution/intent_assembly.rs` | Pipeline enforcement point for unknown kind rejection | `derive_instrument_kind` called at line 111; `None` result -> `AssemblySizingError::UnknownInstrumentKind` at line 112 |
| `crates/soldier_core/tests/test_intent_assembly.rs` | Pipeline-level causality proof tests | `test_assembly_unknown_kind_fails_closed` and `test_assembled_pipeline_unknown_kind_rejects` prove dispatch_count=0 with `RejectReasonCode::AssemblyFailed`. 14 tests, all pass. |
| `crates/soldier_core/src/execution/open_runtime.rs` | Production wiring of `assemble_sizing` | Called at line 408 -- confirms production path uses `derive_instrument_kind` |

### Fail-closed coverage (6 categories)

| Category | Covered? | Evidence |
|----------|----------|----------|
| Missing/None | YES | `test_combo_instruments_return_none` -- all flags false returns `None`; pipeline rejects with `AssemblyFailed` |
| NaN/Inf | YES | `test_assembly_nan_qty_fails_closed`, `test_assembly_inf_qty_fails_closed` -- NaN/Inf canonical_qty rejected as `InvalidOrderSize` |
| Negative | N/A | `InstrumentKindInput` fields are `bool` -- negative values not applicable to this derivation |
| Out-of-domain | YES | `test_option_priority_over_future_when_both_set` -- contradictory flags (both option+future) return `None` with tracing warning |
| Corrupt | YES | Covered by Out-of-domain: contradictory boolean combination is the corruption mode for this struct |
| Narrowing casts | N/A | No numeric casts in `derive_instrument_kind` -- pure boolean logic |

### Unwrap/expect audit

- `crates/soldier_core/src/venue/types.rs`: 0 `unwrap()`, 0 `expect()` -- CLEAN
- `crates/soldier_core/src/risk/state.rs`: 0 `unwrap()`, 0 `expect()` -- CLEAN

---

## Verification Summary

- **13/13 tests pass** in `test_instrument_kind_mapping.rs`
- **14/14 tests pass** in `test_intent_assembly.rs` (pipeline causality)
- **0 unwrap()/expect()** in enforcement files
- **0 serde derives** (acceptable for current in-memory usage)
- **1 stale TODO** (types.rs:46, LOW severity)
- **1 deferred assumption** (USDC-margined perpetual live API validation, MEDIUM, premortem debt)
- **Git status unchanged** -- read-only integrity confirmed

---

READY FOR SELF_REVIEW
