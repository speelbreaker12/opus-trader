# Devils Advocate R7 Recheck: Gap Closure Verification

**Date**: 2026-02-21
**Scope**: Re-run mutation analysis on the 6 fixes from DEVILS_ADVOCATE_R7.md
**Analyst**: Claude Opus 4.6 (analysis-only, no code modified)
**Prior report**: `reviews/reconciliations/slice1/DEVILS_ADVOCATE_R7.md`

---

## Gap Closure Status

### DA-001: Tautological idempotency test (CLOSED)

**Original gap**: `test_at960_classify_lifecycle_error_idempotent` called a pure function twice and asserted `result_1 == result_2`. This proves nothing beyond what the Rust type system guarantees for a pure function (no `&mut self`, no side effects).

**Fix applied**: Test removed entirely. Replaced by `test_cancel_outcome_varies_by_intent_for_expired` which tests actual behavioral variation (see DA-002).

**Verification**: `grep` confirms `test_at960_classify_lifecycle_error_idempotent` no longer exists in the codebase. The dead-weight test is gone.

**Status: CLOSED**

---

### DA-002: Missing `Close -> NotApplicable` assertion (CLOSED)

**Original gap**: No test called `classify_lifecycle_error(Close, InstrumentExpiredOrDelisted)` and asserted `cancel_outcome == NotApplicable`. An impl that ignores the `intent` field and always returns `IdempotentSuccess` for the expired branch would pass.

**Fix applied**: `test_cancel_outcome_varies_by_intent_for_expired` (line 155 of `test_expiry_guard.rs`) tests both intents:

```rust
// Cancel on expired -> IdempotentSuccess
assert_eq!(cancel_decision.cancel_outcome, CancelOutcome::IdempotentSuccess);
// Close on expired -> NotApplicable
assert_eq!(close_decision.cancel_outcome, CancelOutcome::NotApplicable);
```

**Mutation analysis against full suite**:

| # | Mutation | Passes? | Caught by |
|---|---------|---------|-----------|
| 1 | Ignore `intent`, always return `IdempotentSuccess` for expired | NO | `test_cancel_outcome_varies_by_intent_for_expired` asserts `Close -> NotApplicable` |
| 2 | Ignore `intent`, always return `NotApplicable` for expired | NO | `test_expiry_cancel_idempotent_success` asserts `Cancel -> IdempotentSuccess` |
| 3 | Swap `IdempotentSuccess` and `NotApplicable` | NO | Both assertions above catch the swap |
| 4 | Hard-coded return for all inputs | NO | `test_expiry_non_terminal_cancel_does_not_mark_expired` asserts `Other -> RetryableFailure` |
| 5 | Ignore `error` field entirely | NO | Tests cover both `InstrumentExpiredOrDelisted` and `Other` with different expected `class`, `retry`, `instrument_state`, and `cancel_outcome` |

**Status: CLOSED** -- the "ignore intent field" mutation is now caught.

---

### DA-003: Hardcoded `ttl_s: 3600.0` in breach struct (CLOSED)

**Original gap**: All breach event tests used `ttl_s = 3600.0`. An impl that hardcoded `ttl_s: 3600.0` in the `CacheTtlBreach` struct would pass every test.

**Fix applied**: `test_breach_event_ttl_reflects_custom_config` (line 522 of `test_instrument_cache_ttl.rs`) uses `custom_ttl_s = 120.0` and asserts:

```rust
assert!((breaches[0].ttl_s - 120.0).abs() < 0.01,
    "ttl_s must reflect custom TTL 120, not hardcoded 3600");
```

**Mutation analysis against full suite**:

| # | Mutation | Passes? | Caught by |
|---|---------|---------|-----------|
| 1 | Hardcode `ttl_s: 3600.0` in breach struct | NO | `test_breach_event_ttl_reflects_custom_config` asserts `ttl_s ~= 120.0` |
| 2 | Hardcode `ttl_s: 120.0` in breach struct | NO | `test_ttl_breach_event_emitted_on_stale` asserts `ttl_s ~= 3600.0`, `test_stale_access_produces_cache_ttl_breach_event` also asserts `ttl_s ~= 3600.0` |
| 3 | Hardcode `age_s` in breach struct | NO | Tests use different ages (200.0 vs 5000.0 vs 7200.0) |
| 4 | Never emit breach | NO | Three tests assert `breaches.len() == 1` after stale access |
| 5 | Swap `age_s` and `ttl_s` fields | NO | `test_breach_event_ttl_reflects_custom_config` would get `ttl_s ~= 200.0` (expected 120.0) |

**Status: CLOSED** -- the hardcoded-TTL mutation is now caught by using a non-3600 value.

---

### DA-004: Duplicate test replaced with realistic payloads (CLOSED)

**Original gap**: `test_instrument_metadata_uses_get_instruments` was functionally identical to `test_btc_perpetual_maps_to_perpetual` -- same `InstrumentKindInput`, same assertion. Added zero mutation coverage beyond siblings.

**Fix applied**: Test removed and replaced by `test_get_instruments_realistic_payloads` -- a 5-row table-driven test covering:
1. BTC-PERPETUAL (inverse perpetual -> `Perpetual`)
2. BTCUSDC-PERP (linear perpetual -> `LinearFuture`)
3. ETH-28MAR25-3000-C (option -> `Option`)
4. BTC-28MAR25 (dated inverse future -> `InverseFuture`)
5. BTC-FS-28MAR25_27JUN25 (combo -> `None`)

**Mutation analysis -- does the new test add coverage beyond siblings?**

The sibling suite already covers all 4 `InstrumentKind` variants plus `None`. The new test's primary value is documentation/traceability (realistic instrument names). However, it does exercise one combination the siblings do not: a combo (`None`) with a realistic venue name.

| # | Mutation | Passes new test? | Caught by full suite? |
|---|---------|------------------|----------------------|
| 1 | Always return `Some(Perpetual)` | NO -- rows 2,3,4,5 fail | Also caught by 5+ siblings |
| 2 | Ignore `is_linear` | NO -- row 2 expects `LinearFuture` | Also caught by `test_linear_priority_over_perpetual` |
| 3 | Ignore `is_option` | NO -- row 3 expects `Option` | Also caught by `test_option_maps_to_option` |
| 4 | Ignore `is_perpetual` | NO -- row 1 expects `Perpetual` not `InverseFuture` | Also caught by `test_btc_perpetual_maps_to_perpetual` |
| 5 | Swap `Perpetual` and `LinearFuture` | NO -- rows 1 and 2 cross-check | Also caught by siblings |

The new test is not redundant with any single sibling -- it exercises 5 inputs in one function, and the BTCUSDC-PERP row (linear perpetual) was only previously tested by `test_usdc_margined_perpetual_maps_to_linear_future` which is the same input. The combo row provides a `None` test beyond `test_combo_instruments_return_none` (same input there too).

**Honest assessment**: The replacement test improves readability and traceability significantly. Its mutation-killing power is largely covered by siblings, but it is no longer a 1:1 duplicate. The original DA-004 flagged "duplicate inputs, zero added behavioral coverage." The fix replaced the 1-row duplicate with a 5-row table-driven test that covers all variant paths in a single test function. This is a reasonable closure.

**Status: CLOSED** (improvement over the original; no longer a duplicate)

---

### DA-005: Unreachable Err path in resolve_config_value (EXPECTED NO CHANGE)

**Original gap**: The `Err` branch from `appendix_a_default(param).ok_or_else(...)` is structurally unreachable because all 74 `ConfigParam` variants have defaults. Replacing `.ok_or_else(...)` with `.unwrap()` would pass all tests.

**Current status**: No change was expected or made. The Err path remains unreachable and untestable without adding a `ConfigParam` variant that lacks a default. The forward-looking guard (`test_all_config_params_fail_closed_when_missing_without_default`) catches future regressions by exhaustively verifying all variants have defaults.

**Why not add a `#[cfg(test)]` variant?** Adding a test-only `ConfigParam` variant without a default would make the Err path reachable in tests. This was considered and rejected: it would add production-type pollution (`#[cfg(test)]` on an enum variant) solely to exercise a path that is structurally correct. The existing forward-looking guard is the right design — it ensures that if a future variant is added without a default, the test suite catches it immediately. The `.ok_or_else(...)` vs `.unwrap()` question is a code style choice, not a behavioral gap, when all variants have defaults.

**Status: EXPECTED NO CHANGE** -- structural limitation accepted; `#[cfg(test)]` variant rejected as production-type pollution

---

### DA-006: Per-field omission tests for DeribitInstrument (CLOSED)

**Original gap**: `test_empty_json_fails_deserialization` proves "at least one field is required" but not "all required fields are required." Making a single field optional via `#[serde(default)]` would still fail on `{}` and pass all existing tests.

**Fix applied**: `test_required_fields_individually_enforced` (line 213 of `test_deribit_instrument.rs`) tests all 11 required fields:

```rust
let required_fields = [
    "instrument_name", "kind", "is_active", "settlement_period",
    "settlement_currency", "quote_currency", "base_currency",
    "tick_size", "min_trade_amount", "contract_size", "creation_timestamp",
];
for field in required_fields {
    let json = btc_perpetual_without(field);
    let result = serde_json::from_str::<DeribitInstrument>(&json);
    assert!(result.is_err(), ...);
}
```

The helper `btc_perpetual_without(field)` removes exactly one field from a valid JSON payload.

**Mutation analysis against full suite**:

| # | Mutation | Passes? | Caught by |
|---|---------|---------|-----------|
| 1 | Add `#[serde(default)]` to `instrument_name` | NO | Test removes `instrument_name` from valid payload, expects Err |
| 2 | Add `#[serde(default)]` to `kind` | NO | Test removes `kind`, expects Err. Also, `String::default()` for an enum would not compile; `#[serde(default)]` alone would fail. |
| 3 | Add `#[serde(default)]` to `tick_size` | NO | Test removes `tick_size`, expects Err |
| 4 | Add `#[serde(default)]` to `base_currency` | NO | Test removes `base_currency`, expects Err |
| 5 | Add `#[serde(default)]` to `creation_timestamp` | NO | Test removes `creation_timestamp`, expects Err |
| 6 | Make all 11 fields `Option<T>` with default | NO | Every row fails |
| 7 | Make one field `Option<T>` without serde(default) | N/A | Would still require the field in JSON (None vs missing are different). Not a mutation concern for required fields. |

**Coverage completeness check**: The 11 fields tested are exactly the non-`#[serde(default)]` fields in the `DeribitInstrument` struct. Cross-referencing with the struct definition:
- `amount_step`: `#[serde(default)]` -- correctly excluded (optional)
- `expiration_timestamp`: `#[serde(default)]` -- correctly excluded (optional)
- `is_perpetual`: `#[serde(default)]` -- correctly excluded (optional)
- `tick_size_steps`: `#[serde(default)]` -- correctly excluded (optional Vec)

All required fields are covered. No required field is missing from the test.

**Status: CLOSED** -- individual field-omission tests now catch any single field becoming optional.

---

## Phase 3 -- Simpler-Than-Correct Gate

For each implementation under test, is there a simpler-than-correct implementation that passes the FULL test suite (all siblings included)?

### classify_lifecycle_error: **PASS**
The full suite now tests:
- Cancel + Expired -> `IdempotentSuccess` + `Terminal` + `DoNotRetry` + `ExpiredOrDelisted`
- Close + Expired -> `NotApplicable` + `Terminal` + `DoNotRetry` + `ExpiredOrDelisted` + `InstrumentOnly` + `restart_required == false`
- Cancel + Other -> `RetryableFailure` + `Retryable` + `RetryAllowed` + `Active`
- Close + Other -> `Retryable` + `Active`

No simpler impl (fewer branches) passes all four combinations. The `intent` field AND the `error` field must both be dispatched correctly.

### InstrumentCache::get_at (breach events): **PASS**
Breach event tests now use three distinct TTL values (120.0, 3600.0, and 60.0 via `test_different_ttl_config_respected`'s stale path) and three distinct ages (200.0, 5000.0, 7200.0). No hardcoded constant passes all.

### derive_instrument_kind: **PASS**
12 tests cover all 4 variants + None, with priority rules (option > linear > perpetual). No simpler dispatch tree passes.

### DeribitInstrument deserialization: **PASS**
11 per-field omission tests + full deserialization tests = no field can be made optional without detection.

### resolve_config_value: **PASS** (unchanged)
74-param exhaustive iteration + count check + explicit-value-override test + NaN/Inf rejection = no simpler resolver passes.

### Overall Simpler-Than-Correct Gate: **PASS**

---

## Summary

| Gap ID | Original Issue | Fix Applied | Closed? | Remaining Risk |
|--------|---------------|-------------|---------|----------------|
| DA-001 | Tautological idempotency test (pure fn) | Removed test | CLOSED | None |
| DA-002 | No `Close -> NotApplicable` assertion | `test_cancel_outcome_varies_by_intent_for_expired` tests both intents | CLOSED | None |
| DA-003 | Hardcoded `ttl_s: 3600.0` in breach struct undetected | `test_breach_event_ttl_reflects_custom_config` with TTL=120 | CLOSED | None |
| DA-004 | Duplicate test with zero added coverage | `test_get_instruments_realistic_payloads` (5-row table-driven) | CLOSED | Low -- still largely covered by siblings, but no longer a 1:1 duplicate |
| DA-005 | Unreachable Err path (`ok_or_else` vs `unwrap`) | No change (structural limitation) | EXPECTED NO CHANGE | Forward-looking guard is in place |
| DA-006 | Single field optionality undetected | `test_required_fields_individually_enforced` (11 per-field omission tests) | CLOSED | None |

**Also fixed**: Self-verifying assertion `assert_eq!(expected_default_ttl_s, 3600.0)` removed from `test_default_instrument_cache_ttl_is_3600`. The test now uses the variable for boundary checks without asserting a constant equals itself.

---

## Phase Transition

All 5 actionable gaps (DA-001 through DA-004, DA-006) are closed. DA-005 remains a structural limitation with an appropriate forward-looking guard.

No remaining mutations from the standard list (always-reject, always-allow, hardcoded return, off-by-one, ignore field, swap enum variants) pass the full test suite for any of the implementations under test.

**Weakest surviving test**: `test_get_instruments_realistic_payloads` -- its mutation-killing power is largely subsumed by siblings. If all 7 sibling tests were deleted, this single test would survive most mutations, but it would miss boundary priority rules (e.g., option-over-future ambiguity tested by `test_option_priority_over_future_when_both_set`).

**Strongest new test**: `test_required_fields_individually_enforced` -- 11 independent omission assertions that cannot be bypassed by any single `#[serde(default)]` addition. This was the highest-severity gap in the original report.
