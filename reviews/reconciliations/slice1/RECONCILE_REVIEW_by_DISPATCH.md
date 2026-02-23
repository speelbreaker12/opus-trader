# Phase R3 Cross-Review: DISPATCH Reviewer

**Reviewer domain**: DISPATCH (order sizing, dispatch mapping)
**Reviewed batches**: BATCH_INFRA, BATCH_INSTRUMENT, BATCH_EXPIRY
**Date**: 2026-02-20
**HEAD**: 1b85f2522c3ee0b9e6af2349a26f9c0f40c98976
**Review basis**: STORY_SCOPE (Cycle 1)

## Stories Reviewed

1. S1-001 (Workspace scaffolding) -- BATCH_INFRA
2. S1-008 (OrderSize discovery) -- BATCH_INFRA
3. S1-009 (Dispatcher mapping discovery) -- BATCH_INFRA
4. S1-010 (Appendix A config defaults) -- BATCH_INFRA
5. S1-002 (InstrumentKind derivation and RiskState enum) -- BATCH_INSTRUMENT
6. S1-011 (Deribit public instrument structs) -- BATCH_INSTRUMENT
7. S1-003 (InstrumentCache TTL and RiskState degradation) -- BATCH_INSTRUMENT
8. S1-006 (InstrumentCache TTL observability hooks) -- BATCH_INSTRUMENT
9. S1-012 (Expiry Cliff Guard) -- BATCH_EXPIRY
10. S1-013 (PR Merge-Readiness Automation Gate) -- BATCH_EXPIRY

---

## Per-Story Evaluation

### S1-001 (Workspace scaffolding)

- **Verdict agreement**: AGREE with PROVEN for both AT-905 and AT-901.
  - The workspace members are explicitly listed in `Cargo.toml:1-5` and crate directories exist with valid manifests. `verify.sh` delegates to a comprehensive pipeline that includes `cargo test --workspace`. Structural ATs with structural proof -- appropriate.

- **Citation spot-checks**:
  1. `Cargo.toml:1-6` -- VERIFIED. Lines 1-6 contain `[workspace]` with `members = ["crates/soldier_core", "crates/soldier_infra"]` and `resolver = "2"`.
  2. `plans/verify.sh:1-5` -- VERIFIED. File exists and delegates to `verify_fork.sh`. The claim that it is executable and delegates correctly is accurate.

- **Missed gaps**: None. The INFRA auditor correctly noted that `lib.rs` files are no longer empty scaffolds (they contain module declarations from later stories). This is expected and acknowledged.

- **S5 wrong-impl assessment**: Both wrong impls are adequately blocked. AT-905's "empty Cargo.toml" wrong impl is blocked because `cargo test --workspace` requires valid `[package]` sections. AT-901's "exit 0 only" wrong impl is blocked because `verify_fork.sh` runs actual `cargo test`.

---

### S1-008 (OrderSize discovery)

- **Verdict agreement**: AGREE with DEFERRED for both AT-277 and AT-920.
  - This is a discovery story producing a document, not enforcement code. DEFERRED to S1-004/S1-005/S1-007 is the correct verdict.

- **Citation spot-checks**:
  1. `docs/order_size_discovery.md` -- file existence confirmed by the INFRA auditor. I did not independently verify the specific line numbers (58, 59) since this is a markdown document with no enforcement significance. Acceptable for a discovery story.

- **Missed gaps**: None. Discovery stories have no enforcement points to miss.

- **S5 wrong-impl assessment**: The S5 analysis for a discovery story is somewhat unusual -- the auditor checks whether the *content* of the report adequately addresses wrong impls. This is a reasonable approach for a document-only story. No concerns.

---

### S1-009 (Dispatcher mapping discovery)

- **Verdict agreement**: AGREE with DEFERRED for both ATs.

- **Citation spot-checks**: Same as S1-008 -- document citations, not code enforcement. Acceptable.

- **Missed gaps**: The auditor flagged a P2 gap (GAP-009-1: per-instrument-kind edge case table could be more exhaustive). This is the right call. The premortem S5 identifies "omit edge cases" as a wrong impl for AT-277, and the report acknowledges edge cases without exhaustively tabulating them per instrument kind. I agree this is P2 (informational, not blocking).

- **S5 wrong-impl assessment**: Adequately covered. The partial verdict on the AT-277 edge case wrong impl is honest and well-calibrated.

---

### S1-010 (Appendix A config defaults)

- **Verdict agreement**: AGREE with PROVEN for AT-341, AT-424, AT-970, AT-971. AGREE with WEAK_PROOF for AT-040.

  The AT-040 WEAK_PROOF is correct and well-reasoned. I verified the test at `test_config_defaults.rs:38-66`: it constructs a `MissingConfigError` manually and checks its Display output, but it does NOT call `resolve_config_value(some_param_without_default, None)` to exercise the actual Err path. The code at `config.rs:452` does return `Err` via `appendix_a_default(param).ok_or_else(...)`, but since ALL 74 `ConfigParam` variants currently have Appendix A defaults (every match arm returns `Some(...)`), there is no variant that would actually trigger the `None` -> `Err` path. This means the Err path is structurally dead code at present. WEAK_PROOF is the right verdict.

- **Citation spot-checks**:
  1. `config.rs:149-262::appendix_a_default` -- VERIFIED. The function spans lines 149-263 and contains a match on all `ConfigParam` variants, returning `Some(value)` for each.
  2. `config.rs:433-456::resolve_config_value` -- VERIFIED. The function spans lines 433-456. Line 452 correctly shows `appendix_a_default(param).ok_or_else(...)` which is the fail-closed Err path.
  3. `test_config_defaults.rs:15-19::test_missing_instrument_cache_ttl_s_applies_default_3600` -- VERIFIED. Lines 15-19 test `resolve_config_value(ConfigParam::InstrumentCacheTtlS, None)` and assert `3600.0`.
  4. `test_config_defaults.rs:90-94::test_resolve_with_explicit_value_overrides_default` -- VERIFIED. Lines 90-94 test `resolve_config_value(ConfigParam::InstrumentCacheTtlS, Some(7200.0))` and assert `7200.0`.

- **Missed gaps**:
  - The auditor correctly identified GAP-010-1 (P1): AT-040 Err path untested end-to-end. This is the highest-priority gap in BATCH_INFRA.
  - The auditor also caught GAP-010-2 (P2): PRD `scope.create` says `config/` directory but implementation uses `src/config.rs` module.
  - One minor gap I would add: The premortem S2 Assumption #2 says "golden vectors use contract values" -- the test `test_appendix_a_defaults_match_contract` at lines 127-194 checks ~35 params, but the Appendix A function has 74 variants. The test is thorough but not exhaustive in the golden vector table. However, `test_all_appendix_a_params_have_defaults` at lines 98-122 does iterate ALL_PARAMS, providing full coverage at the existence level. This is an INFO-level observation, not a gap upgrade.

- **S5 wrong-impl assessment**:
  - AT-341 "hardcode defaults, ignore overrides" -- BLOCKED by `test_resolve_with_explicit_value_overrides_default`. Confirmed.
  - AT-040 "return Ok(default) for ALL missing params" -- WEAK as noted. The auditor is correct that the test doesn't actually exercise the Err path.
  - AT-424 "test only one CSP param" -- BLOCKED by `test_all_params_resolve_through_resolver` which iterates ALL_PARAMS. Confirmed.

---

### S1-002 (InstrumentKind derivation and RiskState enum)

- **Verdict agreement**: AGREE with PROVEN for AT-333 (both derivation and RiskState).

- **Citation spot-checks**:
  1. `types.rs:54::derive_instrument_kind` -- VERIFIED. The function is at line 54, returns `Option<InstrumentKind>`, and correctly maps `InstrumentKindInput` fields to the 4 enum variants + None for unknown.
  2. `test_instrument_kind_mapping.rs:97::test_all_instrument_kinds_derivable` -- VERIFIED. Table-driven test at line 97 with all 4 `InstrumentKind` variants.
  3. `test_instrument_kind_mapping.rs:182::test_riskstate_has_all_variants` -- VERIFIED. Lines 182-199 construct all 4 `RiskState` variants, assert `len() == 4`, and check pairwise distinctness.
  4. `types.rs:74` returning `None` for unknown kinds -- VERIFIED. Line 74 returns `None` for the fallthrough case (combos/unknown).

- **Missed gaps**:
  - The auditor flagged GAP-002-1 (P2): `test_instrument_metadata_uses_get_instruments` does not exist. This test is referenced in the premortem S6 proof plan. I checked: this test is indeed missing. The INSTRUMENT auditor correctly caught this. However, since S1-002 is about derivation logic (not metadata fetching), this is arguably outside S1-002 scope and belongs to S1-011 or a future integration story. P2 is appropriate.
  - The premortem S5 identifies "hardcode InstrumentKind from name matching" as a wrong impl. The auditor notes "structural prevention" because `InstrumentKindInput` has no `name` field. This is correct -- the API design itself prevents this wrong impl. Good analysis.

- **S5 wrong-impl assessment**: All three wrong impls from the premortem are addressed. The "2-variant RiskState" wrong impl is blocked by the 4-variant test. The "all futures map to linear_future" wrong impl is blocked by `test_btc_perpetual_maps_to_perpetual` and `test_btc_dated_future_maps_to_inverse_future`. Adequate.

---

### S1-011 (Deribit public instrument structs)

- **Verdict agreement**: AGREE with PROVEN for AT-333.

- **Citation spot-checks**:
  1. `deribit/public/mod.rs:51::DeribitInstrument` -- VERIFIED. Struct definition at line 51 with all required fields: `instrument_name`, `kind`, `tick_size`, `min_trade_amount`, `amount_step`, `contract_size`.
  2. `test_deribit_instrument.rs:69::test_btc_perpetual_deserializes` -- VERIFIED. Lines 69-80 deserialize a JSON fixture and assert field values.
  3. `test_deribit_instrument.rs:83::test_contract_required_fields_present` -- VERIFIED. Lines 83-95 assert specific numeric values for `tick_size`, `min_trade_amount`, `contract_size`, and `contract_multiplier()`.
  4. `test_deribit_instrument.rs:170::test_pub_reexport` -- VERIFIED. Lines 170-175 verify pub re-export compiles.

- **Missed gaps**:
  - The auditor flagged GAP-011-1 (P2): no empty JSON `{}` deserialization failure test. This is a valid gap from premortem S5 (wrong impl: "hardcoded defaults via `#[serde(default)]` on required fields"). The required fields are `f64` (not `Option<f64>`), which provides structural prevention, but an explicit test would be stronger.
  - The auditor noted DECISION_DIVERGENCE: struct uses Deribit names with `contract_multiplier()` bridge method instead of serde renames. This is correctly classified as INFO (not a violation).
  - Premortem S5 lists "wrong numeric types (tick_size: i64)" as a wrong impl. The auditor says this is blocked by `test_contract_required_fields_present` because the fixture has decimal values (tick_size=0.5). VERIFIED: the fixture JSON has `"tick_size": 0.5`, which would fail to parse into an `i64`. This is structurally correct.

- **S5 wrong-impl assessment**: Adequately covered. The "all fields Option<f64>" wrong impl is blocked by `test_contract_required_fields_present` which asserts specific non-default values. The missing empty-JSON test is P2, not blocking.

---

### S1-003 (InstrumentCache TTL and RiskState degradation)

- **Verdict agreement**: AGREE with PROVEN for both AT-104 and AT-279.

  This is the strongest evidence in the INSTRUMENT batch. The test suite is comprehensive with boundary tests, NaN/Inf fail-closed, TRIP/NON-TRIP pairs, and table-driven `opens_blocked` coverage.

- **Citation spot-checks**:
  1. `cache.rs:162::get_at` -- VERIFIED. The TTL comparison is at line 162: `if ttl_invalid || cache_age_s > ttl_s`. Strict greater-than as required by contract.
  2. `cache.rs:265::opens_blocked` -- VERIFIED. Lines 265-270 show the function matching on all 4 RiskState variants: only Healthy returns false.
  3. `test_instrument_cache_ttl.rs:123::test_stale_cache_blocks_opens` -- VERIFIED. Lines 123-139 insert at t0, check at t0+7200s with ttl=3600, assert Degraded and `opens_blocked` is true.
  4. `test_instrument_cache_ttl.rs:142::test_fresh_cache_allows_opens` -- VERIFIED. Lines 143-155 insert at t0, check at t0 with ttl=3600, assert Healthy and `opens_blocked` is false.
  5. `test_instrument_cache_ttl.rs:50::test_cache_age_at_exact_ttl_is_healthy` -- VERIFIED. Lines 50-65 check at exactly 3600s, assert Healthy. Boundary test.
  6. `test_instrument_cache_ttl.rs:69::test_cache_age_one_second_past_ttl_is_degraded` -- VERIFIED. Lines 69-79 check at 3601s, assert Degraded.
  7. `test_instrument_cache_ttl.rs:83::test_nan_ttl_fails_closed_to_degraded` -- VERIFIED. NaN TTL returns Degraded.
  8. `test_instrument_cache_ttl.rs:458::test_different_ttl_config_respected` -- VERIFIED. Lines 458+ use custom TTL of 60s.

- **Missed gaps**:
  - The auditor flagged GAP-003-1 (P2): no explicit default TTL == 3600 assertion. This is correct -- the cache tests use `3600.0` as a test value but don't assert it as a default constant. However, S1-010 covers Appendix A defaults including `InstrumentCacheTtlS=3600.0`. The gap is real at the S1-003 scope level but covered at the system level via S1-010. P2 is appropriate.
  - The DECISION_DIVERGENCE (per-entry `inserted_at` vs cache-wide `last_refresh_ts`) is correctly classified as INFO and is noted as an improvement.
  - PolicyGuard integration deferred to Slice 2 is correctly tracked.

- **S5 wrong-impl assessment**: Comprehensive. All 5 wrong impls from the premortem are blocked:
  - "Degraded but OPEN not blocked" -- blocked by `test_stale_cache_blocks_opens`.
  - "OPEN blocked but CLOSE also blocked" -- blocked by `test_opens_blocked_is_sole_gate_closes_ungated` (line 161).
  - "Always returns Degraded" -- blocked by `test_fresh_cache_allows_opens` (NON-TRIP).
  - "TTL hardcoded to 3600s" -- blocked by `test_different_ttl_config_respected` (custom TTL 60s).
  - "Cache age never increases" -- blocked by `test_stale_instrument_cache_sets_degraded` (line 34).

---

### S1-006 (InstrumentCache TTL observability hooks)

- **Verdict agreement**: AGREE with PROVEN for AT-104 (observability).

- **Citation spot-checks**:
  1. `cache.rs:143::get_at` -- VERIFIED. Line 144 increments `self.hits_total`. This is the same `get_at` function that serves both S1-003 and S1-006.
  2. `cache.rs:163` (stale_total) -- VERIFIED. Line 163 increments `self.stale_total` within the `if ttl_invalid || cache_age_s > ttl_s` block.
  3. `cache.rs:155` (last_age_s gauge) -- VERIFIED. Line 155 sets `self.last_age_s = Some(cache_age_s)`.
  4. `test_instrument_cache_ttl.rs:189::test_cache_hits_counter_increments` -- VERIFIED. Lines 189-198 insert then lookup, assert `hits_total()` goes from 0 to 1.
  5. `test_instrument_cache_ttl.rs:322::test_stale_total_counter_increments` -- VERIFIED. Lines 322-337 assert fresh access keeps `stale_total()` at 0, stale access increments to 1.
  6. `test_instrument_cache_ttl.rs:421::test_last_age_s_gauge_updates` -- VERIFIED. Lines 421-439 assert gauge starts None, updates on lookup.

- **Missed gaps**:
  - GAP-006-1 (P2): no tracing emission test for `CacheTtlBreach`. The auditor noted this correctly. The `CacheTtlBreach` struct is pushed to `pending_breaches` (line 168-172 of cache.rs), and there is a `test_ttl_breach_event_emitted_on_stale` test at line 346 (the auditor cited this). But there is no `tracing::warn!` capture test. The breach is a drain-based event, not a tracing event, so "tracing emission test" is a slight misnomer -- it's more that the breach struct is tested but not the actual structured log emission. P2 is appropriate.
  - Premortem S5 identifies "hits_total counts misses too" as a wrong impl. The auditor says this is blocked by `test_cache_hits_counter_increments` at lines 189, 204 (miss excluded). I verified: the hits counter only increments after a successful `self.entries.get()` (line 142-144 of cache.rs: the `?` operator returns `None` before `hits_total` increments). This is structurally correct. However, I note there is no explicit "miss does NOT increment hits_total" test. The structural prevention is sufficient for PROVEN.

- **S5 wrong-impl assessment**: All three wrong impls are adequately addressed. "Metrics defined but never incremented" is directly tested. "Wrong field names in log" is tested via the breach struct fields test. "hits_total counts misses too" is structurally prevented.

---

### S1-012 (Expiry Cliff Guard)

- **Verdict agreement**: AGREE with WEAK_PROOF for all 7 ATs.

  The auditor correctly identified that the compilation error in `common/mod.rs` is a P0 blocker that prevents ALL pipeline integration tests from compiling. I independently verified:
  - `common/mod.rs:7` imports `PricerSide` which does NOT exist in `soldier_core::execution` (grep confirms zero matches in the source).
  - `common/mod.rs:8-10` are duplicate imports of the same items from lines 5-7 (minus `PricerSide`), causing duplicate import errors.

  This means test_expiry_guard.rs cannot compile (it has `mod common;` at line 1), so all pipeline tests (AT-950, AT-965) and any test that uses `common::base_open_input()` cannot run. The unit tests (AT-949, AT-960, AT-961, AT-962, AT-966) don't use `common::` directly for their core logic, but because `mod common;` is declared at line 1, the entire test binary fails to compile.

  WEAK_PROOF is the correct verdict across the board. The code and tests *look* correct based on source reading, but cannot be verified by execution.

- **Citation spot-checks**:
  1. `lifecycle.rs:152::classify_lifecycle_error` -- VERIFIED. Lines 152-183 match on `VenueLifecycleError` and return `LifecycleDecision` with correct fields.
  2. `lifecycle.rs:96::evaluate_expiry_guard` -- VERIFIED. Lines 95-149 implement the buffer check with saturating arithmetic, intent filtering, and fail-closed behavior for missing expiration on expirable instruments.
  3. `test_expiry_guard.rs:83::test_expiry_cancel_idempotent_success` -- VERIFIED. Lines 83-98 call `classify_lifecycle_error(Cancel, InstrumentExpiredOrDelisted)` and assert Terminal, DoNotRetry, IdempotentSuccess, ExpiredOrDelisted.
  4. `test_expiry_guard.rs:15::test_expiry_delist_buffer_rejects_open` -- VERIFIED. Lines 15-29 create input within buffer, assert Rejected.
  5. `test_expiry_guard.rs:153::test_at950_pipeline_rejects_open_within_expiry_buffer` -- VERIFIED. Lines 153-200 construct full pipeline input, assert ExpiryGuard gate trace, InstrumentExpiredOrDelisted reject code. This is the strongest causal proof test -- but it cannot compile.
  6. `test_expiry_guard.rs:204::test_at965_pipeline_allows_open_outside_expiry_buffer` -- VERIFIED. Lines 204-224 construct input outside buffer, assert Approved and no reject code.

- **Missed gaps**:
  - GAP-012-1 (P0): compilation error in `common/mod.rs`. Correctly identified and correctly prioritized.
  - GAP-012-2 (P1): no duplicate-call idempotency test for AT-960. The premortem S5 specifies "assert ledger checksum unchanged between T0 and T0+1 duplicate cancel." The current test calls `classify_lifecycle_error` once and checks the output, but `classify_lifecycle_error` is a pure function -- calling it twice will by definition return the same result. The real idempotency concern is at the integration level (does the system dispatch twice?), which is untested. P1 is appropriate.
  - GAP-012-3 (P2): no `retry_count == 0` assertion for AT-962. The test at line 130 asserts `DoNotRetry` directive but doesn't check that no retry was actually enqueued. This is a reasonable gap to flag but depends on whether retry enqueueing exists at this layer.
  - I would also note: the premortem S2 Assumption #2 ("expiry_delist_buffer_s has non-zero default") is flagged as ASSUMPTION_UNTESTED by the auditor, which is correct. Tests use explicit `buffer_s=60`, never checking the default.

- **S5 wrong-impl assessment**:
  - AT-949 "mark expired on ANY cancel" -- blocked by `test_expiry_non_terminal_cancel_does_not_mark_expired` (line 102). CORRECT.
  - AT-950 "reject ALL intents" -- blocked by `test_pipeline_close_passes_through_expired_instrument` (line 231). CORRECT, but CANNOT COMPILE (pipeline test).
  - AT-960 "skip dispatch but mutate ledger" -- UNBLOCKED. The auditor correctly flags this. No duplicate-call test exists. The "ledger checksum unchanged" tightening from the premortem is not implemented.
  - AT-961 "swallow error silently" -- PARTIALLY blocked. The test at line 112 asserts InstrumentOnly scope and ExpiredOrDelisted state, which does catch the "swallow" scenario. But it doesn't verify logging occurs.
  - AT-962 "mark expired but enqueue retries" -- PARTIALLY blocked. DoNotRetry is asserted but no retry_count check.

---

### S1-013 (PR Merge-Readiness Automation Gate)

- **Verdict agreement**: AGREE with PROVEN for both AT-1056 and AT-1057.

- **Citation spot-checks**:
  1. `pr_gate.sh:830-832` -- VERIFIED. Lines 830-832 check `$CHECK_FAIL != "0"` and append "checks_failing" to the problems array.
  2. `pr_gate.sh:833-835` -- VERIFIED. Lines 833-835 check `$CHECK_PENDING != "0"` and append "checks_pending".
  3. `test_pr_gate.sh:217-226` -- VERIFIED. Lines 217-226 show fixture test cases for pending and failing checks. The mock `gh` API returns appropriate JSON payloads for each scenario.

- **Missed gaps**:
  - GAP-013-1 (P2): `enforcement_point` in prd.json says "DispatcherChokepoint" but this is a CI script. The auditor correctly flags this as a PRD metadata error. Not a code defect.
  - Premortem S5 identifies "always exits 0" and "only checks build, not test" as wrong impls. Both are blocked by Cases 5-7 which use `expect_fail` assertions. The gate evaluates ALL check-runs uniformly, not selectively. This is correct.

- **S5 wrong-impl assessment**: Both wrong impls are adequately blocked. The 29 test cases provide comprehensive fixture-based coverage. No concerns.

---

## Cross-Batch Consistency Analysis

### Verdict Calibration Comparison

**PROVEN usage across batches:**
- BATCH_INFRA: PROVEN used for structural artifacts (S1-001) and comprehensive config tests (S1-010 AT-341/AT-424). Appropriate -- tests exist, assert exact values, cover parameterized cases.
- BATCH_INSTRUMENT: PROVEN used for AT-333 (derivation), AT-104 (cache TTL), AT-279 (TTL config), AT-104 (observability). All have strong causal proof with boundary tests, NaN/Inf, and TRIP/NON-TRIP pairs. Consistent with BATCH_INFRA standards.
- BATCH_EXPIRY: PROVEN used only for S1-013 (pr_gate.sh). This is appropriate -- the fixture-based test suite has 29 cases. Consistently calibrated.

**WEAK_PROOF usage across batches:**
- BATCH_INFRA: WEAK_PROOF used for AT-040 (config Err path). Reason: test constructs error manually, doesn't call the actual code path. This is well-calibrated.
- BATCH_EXPIRY: WEAK_PROOF used for all S1-012 ATs. Reason: compilation error prevents test execution. Also well-calibrated.
- There is a *qualitative* difference between these two WEAK_PROOF uses: AT-040 is weak because the test is inadequate even if it compiles; S1-012 is weak because tests *look* correct but cannot be verified by execution. The EXPIRY auditor could have been more specific about which ATs would be PROVEN if the compile error were fixed. Based on my source reading:
  - AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966 would likely all be PROVEN once the compile error is fixed, EXCEPT AT-960 which would remain WEAK_PROOF due to the missing duplicate-call test.

**DEFERRED usage across batches:**
- BATCH_INFRA: DEFERRED used for S1-008 and S1-009 (discovery stories). Correct and consistent.
- No other batch uses DEFERRED. This is appropriate -- S1-008 and S1-009 are the only pure-discovery stories.

### Systematic Patterns

1. **Consistent DECISION_DIVERGENCE handling**: All three batches handle decision divergences from premortems as INFO-level notes, not as violations. This is the correct approach -- implementations that improve on premortem predictions are acceptable.

2. **Consistent scope drift tracking**: All batches have scope check sections. The EXPIRY batch notes scope drift into `execution/` for pipeline wiring. The INFRA batch notes that `config/` directory doesn't exist (module instead). These are honest observations.

3. **No leniency bias detected**: I found no case where a batch gave PROVEN to evidence that deserved WEAK_PROOF. The INFRA batch's WEAK_PROOF for AT-040 and the EXPIRY batch's global WEAK_PROOF for S1-012 both demonstrate willingness to downgrade verdicts when evidence is insufficient.

---

## Systemic Patterns

### Issues Appearing Across Multiple Ledgers

1. **Dead or structurally unreachable error paths**: AT-040 in S1-010 (all ConfigParam variants have defaults, so the None->Err path is dead code) and AT-960 in S1-012 (pure function idempotency is structural, not tested). Both cases involve code paths that are correct but untested because the current code structure makes them unreachable. This is a recurring pattern worth tracking -- as the codebase evolves, these paths may become reachable without tests to catch regressions.

2. **Missing integration/end-to-end tests**: Multiple stories defer PolicyGuard integration (S1-003, S1-010). The reconcile loop integration test for S1-012 is also deferred. This is acceptable for Slice 1 but creates a testing gap that should be addressed in Slice 2.

3. **Premortem-predicted tests that don't exist**: `test_instrument_metadata_uses_get_instruments` (S1-002 premortem) and the empty JSON failure test (S1-011 premortem). These are P2 gaps in both cases. Premortems are aspirational; not all predicted tests need to exist if structural prevention provides equivalent coverage.

4. **The common/mod.rs compilation error** (S1-012) is a systemic risk: it blocks ALL integration tests in soldier_core that use `mod common;`, not just S1-012 tests. Any test file importing `common` will fail to compile. This should be P0 across the board.

### Common Blind Spots

- **No batch explicitly validates that tests were EXECUTED (not just read).** All three auditors read test source code and verified the logic, but none reported actually running `cargo test` to confirm tests pass. The EXPIRY auditor gets the closest by identifying the compilation error, which implies they tried or would have tried. For future reconciliations, an execution check should be part of the procedure.

---

## Summary Table

| Story | Original Verdict | My Assessment | Citation Accuracy | Missed Gaps |
|-------|-----------------|---------------|-------------------|-------------|
| S1-001 | PROVEN, PROVEN | AGREE | 2/2 verified | None |
| S1-008 | DEFERRED, DEFERRED | AGREE | N/A (document) | None |
| S1-009 | DEFERRED, DEFERRED | AGREE | N/A (document) | None |
| S1-010 | PROVEN(3), WEAK_PROOF(1), PROVEN(1) | AGREE | 4/4 verified | INFO: golden vector table not fully exhaustive |
| S1-002 | PROVEN, PROVEN | AGREE | 4/4 verified | None beyond GAP-002-1 |
| S1-011 | PROVEN | AGREE | 4/4 verified | None beyond GAP-011-1 |
| S1-003 | PROVEN, PROVEN | AGREE | 8/8 verified | None beyond GAP-003-1 |
| S1-006 | PROVEN | AGREE | 6/6 verified | None beyond GAP-006-1 |
| S1-012 | WEAK_PROOF (all 7) | AGREE | 6/6 verified (source reading) | AT-960 would remain WEAK_PROOF even after compile fix |
| S1-013 | PROVEN, PROVEN | AGREE | 3/3 verified | None beyond GAP-013-1 |

**Overall assessment**: All three batches are well-calibrated, honest about gaps, and consistent in their verdict standards. The single P0 issue (S1-012 common/mod.rs compilation error) is correctly identified and prioritized. No verdict disagreements.
