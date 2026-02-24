---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R7e-devils-advocate
  cycle: recon-v1.x (original)
  phase_equivalent: R7e
artifact_type: mutation_analysis
scope: slice 1 (initial pass)
---

# Devils Advocate: Phase R5 Reconciliation Tests (R7 Mutation Analysis)

**Date**: 2026-02-21
**Scope**: 7 new tests added during Phase R5 reconciliation remediation for Slice 1
**Analyst**: Claude Opus 4.6 (analysis-only, no code modified)

---

## Phase 1 -- Target ATs

| # | Test File | Test Function | Gate/Guard | What it proves | TRIP or NON-TRIP |
|---|-----------|---------------|------------|----------------|------------------|
| 1 | `test_expiry_guard.rs` | `test_at960_classify_lifecycle_error_idempotent` | classify_lifecycle_error | Calling classify twice with same input yields identical result (purity) | NON-TRIP |
| 2 | `test_instrument_cache_ttl.rs` | `test_default_instrument_cache_ttl_is_3600` | InstrumentCache TTL | Appendix A default TTL of 3600s produces correct boundary behavior | TRIP + NON-TRIP |
| 3 | `test_instrument_cache_ttl.rs` | `test_stale_access_produces_cache_ttl_breach_event` | InstrumentCache breach | Stale access emits CacheTtlBreach event with correct fields | TRIP |
| 4 | `test_instrument_kind_mapping.rs` | `test_instrument_metadata_uses_get_instruments` | derive_instrument_kind | BTC-PERPETUAL venue shape maps to Perpetual | NON-TRIP |
| 5 | `test_config_defaults.rs` | `test_all_config_params_fail_closed_when_missing_without_default` | resolve_config_value | Every ConfigParam resolves Ok with Appendix A default; count matches EXPECTED_PARAM_COUNT | NON-TRIP |
| 6 | `test_config_defaults.rs` | `test_missing_replay_window_hours_applies_default_48` | resolve_config_value | ReplayWindowHours resolves to 48.0 when missing | NON-TRIP |
| 7 | `test_deribit_instrument.rs` | `test_empty_json_fails_deserialization` | DeribitInstrument serde | Empty `{}` fails to deserialize (required fields enforced) | TRIP |

---

## Phase 2 -- Mutation Loop

### Test 1: `test_at960_classify_lifecycle_error_idempotent`

**Implementation under test**: `classify_lifecycle_error(intent, error) -> LifecycleDecision`

The test calls `classify_lifecycle_error` twice with `(Cancel, InstrumentExpiredOrDelisted)` and asserts `result_1 == result_2`.

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | Always-reject: return Terminal for all errors | YES -- GAP | The test only calls with `InstrumentExpiredOrDelisted`. An impl that ignores the `error` param and always returns the Terminal decision would pass. **However**, sibling test `test_expiry_non_terminal_cancel_does_not_mark_expired` calls with `VenueLifecycleError::Other` and asserts Retryable, which catches this. **Net: caught by sibling.** |
| 2 | Hard-coded return (always return the Cancel/Expired decision) | YES -- GAP | Same reasoning as #1; the test itself cannot distinguish a hardcoded response from a pure function because it only tests one input. Sibling tests in the same file cover Other. **Net: caught by sibling.** |
| 3 | Return random result on each call (impure) | NO | Would fail `assert_eq!(result_1, result_2)`. |
| 4 | Ignore `intent` field: always set `cancel_outcome = IdempotentSuccess` | YES -- GAP | The test only uses `Cancel` intent, so ignoring intent and always returning `IdempotentSuccess` would pass. Sibling test `test_expiry_reconcile_does_not_halt_other_instruments` calls with `Close` intent but does NOT assert `cancel_outcome` for the expired branch -- it only checks `reconcile_scope` and `instrument_state`. **This is a real gap in the overall test suite**: no test calls `classify_lifecycle_error(Close, InstrumentExpiredOrDelisted)` and asserts `cancel_outcome == NotApplicable`. |
| 5 | Swap `IdempotentSuccess`/`RetryableFailure` | NO | `test_expiry_cancel_idempotent_success` explicitly asserts `IdempotentSuccess` for Cancel+Expired. |

**Gaps found (test 1)**:
- **GAP-DA-001**: The idempotency test is intrinsically weak because `classify_lifecycle_error` is a pure function (no `&mut self`, no side effects). Calling a pure function twice always yields the same result. The test proves nothing beyond what the compiler's type system already guarantees. It cannot catch any stateful mutation because the function signature forbids state. **Severity: Low** (the test is not wrong, but it provides zero additional safety value for a pure function).
- **GAP-DA-002**: No test asserts `cancel_outcome == CancelOutcome::NotApplicable` when `classify_lifecycle_error` is called with `(Close, InstrumentExpiredOrDelisted)`. An implementation that ignores the `intent` field and always returns `IdempotentSuccess` for the expired branch would pass all existing tests. **Severity: Medium** -- a wrong impl that treats all expired-error intents as "cancel success" would mask incorrect lifecycle handling for Close/Hedge intents.

---

### Test 2: `test_default_instrument_cache_ttl_is_3600`

**Implementation under test**: `InstrumentCache::get_at()` freshness comparison + the constant `3600.0`

The test asserts:
- At age==3600s with ttl=3600.0 -> Healthy
- At age==3601s with ttl=3600.0 -> Degraded
- The numeric constant is 3600.0

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | Always-reject (always return Degraded) | NO | The test asserts Healthy at the boundary. |
| 2 | Always-allow (always return Healthy) | NO | The test asserts Degraded at 3601s. |
| 3 | Hard-code TTL to 3600 (ignore ttl_s parameter) | YES -- GAP | This test ONLY uses `ttl_s = 3600.0`. However, sibling test `test_different_ttl_config_respected` uses `ttl_s = 60.0` and would catch this. **Net: caught by sibling.** |
| 4 | Off-by-one: use `>=` instead of `>` | NO | The boundary test at exactly 3600s checks `Healthy`, which requires `>` (not `>=`). This test explicitly catches the off-by-one. |
| 5 | Ignore ttl_s, hardcode boundary at 3600s | YES -- GAP | Same as #3, caught by sibling `test_different_ttl_config_respected`. |

**Gaps found (test 2)**: None unique to this test. The boundary assertion at 3600s and 3601s is well-constructed. The hardcoded-TTL mutation is caught by the sibling test.

---

### Test 3: `test_stale_access_produces_cache_ttl_breach_event`

**Implementation under test**: `InstrumentCache::get_at()` breach event emission into `pending_breaches` VecDeque.

The test asserts:
- Fresh access -> no breach events
- Stale access (age=5000 > ttl=3600) -> exactly 1 CacheTtlBreach
- Breach fields: instrument_id="ETH-PERPETUAL", age_s~=5000, ttl_s~=3600

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | Always emit breach (even on fresh access) | NO | The test asserts `drain_breaches().is_empty()` after fresh access. |
| 2 | Never emit breach | NO | The test asserts `breaches.len() == 1` after stale access. |
| 3 | Hardcode breach instrument_id to "ETH-PERPETUAL" | YES -- GAP | The test only uses "ETH-PERPETUAL". However, sibling test `test_ttl_breach_event_emitted_on_stale` uses "BTC-PERPETUAL" and checks the instrument_id. **Net: caught by sibling.** |
| 4 | Hardcode age_s to 5000.0 | YES -- GAP | The test only checks `(breaches[0].age_s - 5000.0).abs() < 0.01`. However, sibling `test_ttl_breach_event_emitted_on_stale` checks `age_s ~= 7200.0` with a different stale duration. **Net: caught by sibling.** |
| 5 | Hardcode ttl_s to 3600.0 in breach struct | YES -- PARTIAL GAP | Both this test and the sibling use `ttl_s = 3600.0`. An impl that hardcodes `ttl_s: 3600.0` in the breach struct would pass both. However, `test_different_ttl_config_respected` does NOT check breach events (it only checks RiskState). **Severity: Low** -- the breach event's `ttl_s` field could be hardcoded to 3600.0, but this only affects observability accuracy, not safety gating. |
| 6 | Emit breach but swap instrument_id with a fixed string | NO | The `"ETH-PERPETUAL"` assertion would fail if a different string were used. |

**Gaps found (test 3)**:
- **GAP-DA-003**: No test verifies `CacheTtlBreach.ttl_s` with a non-3600.0 TTL value. An implementation that hardcodes `ttl_s: 3600.0` in the breach struct would pass all existing tests. **Severity: Low** (observability-only, no safety impact).

---

### Test 4: `test_instrument_metadata_uses_get_instruments`

**Implementation under test**: `derive_instrument_kind(input) -> Option<InstrumentKind>`

The test constructs an `InstrumentKindInput { is_option: false, is_future: true, is_perpetual: true, is_linear: false }` and asserts `Some(Perpetual)`.

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | Always return Some(Perpetual) | YES -- GAP | This test only checks one input that expects Perpetual. However, 10 sibling tests cover Option, LinearFuture, InverseFuture, None, and priority rules. **Net: caught by siblings.** |
| 2 | Hard-coded return for this exact input | YES -- GAP | Same as above, caught by siblings. |
| 3 | Ignore `is_linear` field | YES -- GAP | For this test, `is_linear = false`, so ignoring it still yields Perpetual. However, sibling `test_linear_priority_over_perpetual` sets `is_linear: true, is_perpetual: true` and asserts `LinearFuture`, which catches this. **Net: caught by sibling.** |
| 4 | Ignore `is_perpetual` field | NO | If `is_perpetual` is ignored with `is_future: true, is_linear: false`, the impl would return `InverseFuture` instead of `Perpetual`, failing this test. |

**Gaps found (test 4)**:
- **GAP-DA-004**: The test is functionally a duplicate of `test_btc_perpetual_maps_to_perpetual` in the same file (identical `InstrumentKindInput` values). It adds no new mutation coverage. It serves a documentation/traceability purpose (proving the get_instruments "shape" works) but not a behavioral one. **Severity: None** (no safety gap; the test is correct but redundant for mutation purposes).

---

### Test 5: `test_all_config_params_fail_closed_when_missing_without_default`

**Implementation under test**: `resolve_config_value(param, None)` for every `ConfigParam` variant, plus `ALL_PARAMS.len() == EXPECTED_PARAM_COUNT`.

The test iterates over `ALL_PARAMS`, checks `appendix_a_default(param).is_some()`, then checks `resolve_config_value(param, None).is_ok()` and the value matches the default. Finally, it asserts the count.

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | `resolve_config_value` always returns Ok(0.0) | NO | The test asserts `result.unwrap() == default.unwrap()` for each param, and most defaults are non-zero. |
| 2 | `appendix_a_default` always returns Some(0.0) | NO | The test asserts `result.unwrap() == default.unwrap()`, and `resolve_config_value` calls `appendix_a_default` internally. If the default function returned 0.0, the resolved value would be 0.0, but the assertion `result.unwrap() == default.unwrap()` would pass (both 0.0). HOWEVER, sibling test `test_appendix_a_defaults_match_contract` checks specific numeric values (e.g., InstrumentCacheTtlS == 3600.0). **Net: caught by sibling.** |
| 3 | `ALL_PARAMS` missing one variant (EXPECTED_PARAM_COUNT still matches) | NO | The count assertion catches this -- if `ALL_PARAMS` has fewer entries, `ALL_PARAMS.len() != EXPECTED_PARAM_COUNT`. |
| 4 | `EXPECTED_PARAM_COUNT` wrong (but ALL_PARAMS complete) | NO | The count assertion catches this directly. |
| 5 | `resolve_config_value` ignores `None` and always returns Ok(default) even for Some(explicit_value) | YES -- GAP | This test only calls with `value = None`. However, sibling `test_resolve_with_explicit_value_overrides_default` calls with `Some(7200.0)` and asserts the explicit value is returned. **Net: caught by sibling.** |
| 6 | New ConfigParam added without Appendix A default | NO | The `assert!(default.is_some())` check catches this immediately. This is the test's primary purpose. |

**Gaps found (test 5)**:
- **GAP-DA-005**: The test is structurally sound for its stated purpose (regression guard against future variants without defaults). However, the Err branch of `resolve_config_value` is never actually exercised by any test. Since every current `ConfigParam` has a default, the `Err` path from `appendix_a_default(param).ok_or_else(...)` is dead code. A mutation that removes the Err path entirely (e.g., replaces `.ok_or_else(...)` with `.unwrap()`) would pass all tests. **Severity: Medium** -- the fail-closed Err path is untested. However, it is structurally unreachable today, and the test explicitly documents this with the comment "structurally unreachable today because ALL 74 ConfigParam variants have defaults." The guard value is forward-looking. Still, an implementation that uses `.unwrap()` instead of `.ok_or_else(...)` would pass today and silently break if a no-default variant is added.

---

### Test 6: `test_missing_replay_window_hours_applies_default_48`

**Implementation under test**: `resolve_config_value(ConfigParam::ReplayWindowHours, None) -> Ok(48.0)`

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | `appendix_a_default(ReplayWindowHours)` returns Some(48.0) but is hardcoded | N/A | This is literally what it is -- a match arm returning a constant. The test verifies the constant. |
| 2 | Swap ReplayWindowHours default with another param (e.g., 30.0) | NO | The test asserts `== 48.0`. |
| 3 | `resolve_config_value` ignores the param and always returns Ok(48.0) | YES -- GAP | This test only checks ReplayWindowHours. However, sibling tests check other params (MmUtilKill -> 0.95, InstrumentCacheTtlS -> 3600.0), so a blanket "always 48.0" would fail those. **Net: caught by siblings.** |
| 4 | Remove the ReplayWindowHours match arm entirely | NO | Would cause a compile error (non-exhaustive match) or would fall to a different arm/default. The test would fail. |

**Gaps found (test 6)**: None. The test is inherently limited (it checks a single constant), but this is appropriate for a spot-check test. The real coverage comes from `test_all_config_params_fail_closed_when_missing_without_default` which iterates all params.

---

### Test 7: `test_empty_json_fails_deserialization`

**Implementation under test**: `serde_json::from_str::<DeribitInstrument>("{}")` -- tests that serde's derived `Deserialize` impl rejects empty JSON.

| # | Mutation | Passed? | Analysis |
|---|---------|---------|----------|
| 1 | Make all fields `Option<T>` with `#[serde(default)]` | NO -- but subtly | If ALL fields were `Option<T> + default`, `{}` would deserialize successfully. However, this would be a massive struct change that breaks all other tests. **Net: caught by siblings.** |
| 2 | Add `#[serde(default)]` to one required field (e.g., `instrument_name`) | YES -- GAP | Adding `#[serde(default)]` to `instrument_name: String` would still leave other required fields, so `{}` would still fail. The test cannot detect a single field becoming optional. However, sibling tests that check the field values (e.g., `assert_eq!(instr.instrument_name, "BTC-PERPETUAL")`) would still pass because they use full JSON. **This is a structural limitation**: the test catches "all fields optional" but not "one field becomes optional." |
| 3 | Add `#[serde(deny_unknown_fields)]` vs not | N/A | Orthogonal to this test. |
| 4 | Remove one required field from the struct (e.g., drop `base_currency`) | MIXED | If `base_currency` were removed from the struct, `{}` would still fail (other required fields). But the BTC_PERPETUAL_JSON test would also fail if it references the removed field. This mutation is caught by the broader test suite. |
| 5 | Add custom Deserialize impl that accepts `{}` with defaults | NO | The test explicitly asserts `result.is_err()`. |

**Gaps found (test 7)**:
- **GAP-DA-006**: The test proves "at least one field is required" but not "all required fields are required." An implementation that makes `base_currency` optional via `#[serde(default)]` would still fail on `{}` (because `instrument_name`, `kind`, etc. are still required) AND would still pass all existing deserialization tests (because they provide `base_currency` in the JSON). The only way to catch a single field becoming optional is to test deserialization with that specific field omitted. **Severity: Low-Medium** -- individual field-omission tests would strengthen this, but the risk is mitigated by the fact that making a field optional requires an explicit code change that reviewers should catch.

---

## Phase 3 -- Simpler-Than-Correct Gate

For each of the 7 tests in isolation:

### Test 1 (`test_at960_classify_lifecycle_error_idempotent`): **PASS (with caveat)**
The simplest wrong impl (hardcoded return) passes this test alone but fails siblings. The test's value is near-zero for a pure function -- the "idempotency" property is guaranteed by Rust's type system (no `&mut self`, no side effects). However, the test does not create a safety gap because the sibling suite is comprehensive.

**Simpler-than-correct?** Yes, but only if evaluated in isolation. With the full sibling suite: No.

### Test 2 (`test_default_instrument_cache_ttl_is_3600`): **PASS**
No simpler-than-correct implementation exists that passes this test. The boundary checks at 3600s and 3601s require the correct `>` comparison with a matching constant.

### Test 3 (`test_stale_access_produces_cache_ttl_breach_event`): **PASS**
The test's fresh-no-breach + stale-has-breach + field validation requires the correct conditional emission logic. No simpler impl passes.

### Test 4 (`test_instrument_metadata_uses_get_instruments`): **PASS (with caveat)**
`return Some(Perpetual)` passes this test. But the sibling suite prevents it. In isolation: **BLOCKED** (hardcoded return is simpler). With siblings: **PASS**.

### Test 5 (`test_all_config_params_fail_closed_when_missing_without_default`): **PASS**
Iterating all 74 params with value+count checks leaves no simpler impl.

### Test 6 (`test_missing_replay_window_hours_applies_default_48`): **PASS (with caveat)**
`return Ok(48.0)` passes. Siblings prevent it. In isolation: **BLOCKED**. With siblings: **PASS**.

### Test 7 (`test_empty_json_fails_deserialization`): **PASS**
The test validates a serde-derived property. No simpler implementation of the struct that preserves at least one required field would change the outcome.

### Overall Simpler-Than-Correct Gate: **PASS**

When evaluated against the full test suite (including siblings in the same file), no simpler-than-correct implementation passes for any of the 7 functions under test.

When evaluated in ISOLATION (each new test alone), tests 1, 4, and 6 are vulnerable to trivial hardcoded returns. This is acceptable because these tests are additive gap closures, not standalone ATs. They exist alongside comprehensive siblings.

---

## Phase 4 -- Summary of Gaps Found

| Gap ID | Test | Mutation That Passes | Severity | Recommendation |
|--------|------|---------------------|----------|----------------|
| GAP-DA-001 | `test_at960_classify_lifecycle_error_idempotent` | Any hardcoded return (purity is type-guaranteed) | Low | Test is not wrong but provides no safety value for a pure fn. Consider documenting this in the test comment rather than relying on it as a safety assertion. No action required. |
| GAP-DA-002 | `test_at960_classify_lifecycle_error_idempotent` | Ignore `intent` field, always return `IdempotentSuccess` for expired branch | Medium | Add a test: `classify_lifecycle_error(Close, InstrumentExpiredOrDelisted)` -> assert `cancel_outcome == NotApplicable`. This blocks the "all expired = cancel success" mutation. |
| GAP-DA-003 | `test_stale_access_produces_cache_ttl_breach_event` | Hardcode `ttl_s: 3600.0` in breach struct | Low | Add a breach event test with a non-3600 TTL (e.g., `ttl_s = 60.0`) that checks `breach.ttl_s == 60.0`. Low priority (observability only). |
| GAP-DA-004 | `test_instrument_metadata_uses_get_instruments` | Identical to sibling test | None | No action. Test serves traceability, not mutation coverage. |
| GAP-DA-005 | `test_all_config_params_fail_closed_when_missing_without_default` | Replace `.ok_or_else(...)` with `.unwrap()` | Medium | Cannot test today (no variant without a default). The test's forward-looking guard is sufficient. Consider adding a compile-time comment warning on the `ok_or_else` line. No immediate action. |
| GAP-DA-006 | `test_empty_json_fails_deserialization` | Make one (non-first-checked) required field optional | Low-Medium | Consider adding per-field omission tests for safety-critical fields (instrument_name, kind, tick_size, min_trade_amount, contract_size). Low priority -- reviewers should catch field optionality changes. |

---

## Phase Transition

Remaining possible mutations all require logic more complex than the correct implementation, OR are caught by sibling tests in the same file.

**Weakest surviving tests** (most vulnerable to isolation-mode mutations):
1. `test_at960_classify_lifecycle_error_idempotent` -- proves nothing beyond type-system guarantees for a pure function
2. `test_instrument_metadata_uses_get_instruments` -- exact duplicate of sibling inputs
3. `test_missing_replay_window_hours_applies_default_48` -- single spot-check, fully subsumed by exhaustive iterator test

**Strongest test** (highest mutation-killing power):
- `test_all_config_params_fail_closed_when_missing_without_default` -- iterates all 74 params, checks value equality AND count invariant. Almost no wrong implementation can pass this.

---

## Tests Added

None. This analysis is read-only per instructions.

## Recommended Actions (Priority Order)

1. **Medium priority**: Add test `classify_lifecycle_error(Close, InstrumentExpiredOrDelisted)` asserting `cancel_outcome == NotApplicable` (GAP-DA-002)
2. **Low priority**: Add breach event test with custom TTL to verify `breach.ttl_s` is not hardcoded (GAP-DA-003)
3. **Low priority**: Consider per-field omission deserialization tests for `DeribitInstrument` critical fields (GAP-DA-006)
4. **No action**: GAP-DA-001 (type-system guarantee), GAP-DA-004 (documentation value), GAP-DA-005 (forward-looking guard)
