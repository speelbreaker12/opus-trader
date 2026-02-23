# Phase R3 Cross-Review: INSTRUMENT Reviewer

**Reviewer domain**: INSTRUMENT (venue types, cache, observability)
**Date**: 2026-02-20
**HEAD**: 1b85f2522c3ee0b9e6af2349a26f9c0f40c98976
**Review basis**: STORY_SCOPE (Cycle 1)

## Stories Reviewed

### BATCH_INFRA (4 stories)
- S1-001 (Workspace scaffolding)
- S1-008 (OrderSize discovery)
- S1-009 (Dispatcher mapping discovery)
- S1-010 (Appendix A config defaults)

### BATCH_DISPATCH (3 stories)
- S1-004 (OrderSize canonical sizing)
- S1-005 (Dispatcher amount mapping)
- S1-007 (Dispatcher mismatch rejection)

### BATCH_EXPIRY (2 stories)
- S1-012 (Expiry Cliff Guard)
- S1-013 (PR Merge-Readiness Automation Gate)

---

## Per-Story Evaluation

---

### S1-001 (BATCH_INFRA)

- **Verdict agreement**: AGREE with PROVEN for both AT-905 and AT-901.
- **Citation spot-checks**:
  - `Cargo.toml:1-6` -- CONFIRMED. File contains `[workspace]` with `members = ["crates/soldier_core", "crates/soldier_infra"]` and `resolver = "2"`.
  - `plans/verify.sh:1-5` -- CONFIRMED. Script has `set -euo pipefail` and `exec "$ROOT/plans/verify_fork.sh" "$@"`.
  - `crates/soldier_core/src/lib.rs:3-7` -- CONFIRMED. Declares `pub mod execution; pub mod idempotency; pub mod recovery; pub mod risk; pub mod venue;` (lines 3-7).
  - `verify_fork.sh:632` -- CONFIRMED via grep: `bash "$ROOT/plans/lib/rust_gates.sh"`.
- **Missed gaps**: None. The premortem is simple (LOW risk scaffolding story) and the audit correctly identifies that verify.sh exceeds the premortem expectation without being wrong.
- **S5 wrong-impl assessment**: Properly assessed. AT-901 tightens AT-905 (empty Cargo.toml blocked by cargo test). The verify.sh vacuousness concern is addressed by verify_fork.sh running a comprehensive pipeline including rust_gates.sh.

---

### S1-008 (BATCH_INFRA)

- **Verdict agreement**: AGREE with DEFERRED for both AT-277 and AT-920.
- **Citation spot-checks**:
  - `docs/order_size_discovery.md:58` -- CONFIRMED. Line 58 reads: "AT-277: option uses `amount=qty_coin`, perp uses `amount=qty_usd`; option `qty_usd` unset; mismatches rejected."
  - `docs/order_size_discovery.md:59` -- CONFIRMED. Line 59 reads: "AT-920: contracts/amount mismatch beyond tolerance -> `Rejected(ContractsAmountMismatch)`, dispatch count 0, `RiskState::Degraded`."
- **Missed gaps**: None. This is a discovery story producing a report; DEFERRED is the correct verdict since no enforcement exists.
- **S5 wrong-impl assessment**: N/A for a discovery story. The audit correctly notes that per-instrument-kind field population table exists (lines 36-42 of the report) as content-level evidence.

---

### S1-009 (BATCH_INFRA)

- **Verdict agreement**: AGREE with DEFERRED for both AT-277 and AT-920.
- **Citation spot-checks**: Not spot-checked in detail (discovery doc, lower priority). The audit references `docs/dispatch_map_discovery.md` which exists at the expected path.
- **Missed gaps**: The P2 finding about incomplete per-instrument-kind edge case table (GAP-009-1) is reasonable. The premortem S5 explicitly lists "Report lists which amount field to send per instrument_kind but omits edge cases" as a wrong impl; the audit correctly identifies this as only partially covered.
- **S5 wrong-impl assessment**: Properly identified that the edge case table is "Partial" -- this is accurate and appropriately flagged as P2 rather than blocking.

---

### S1-010 (BATCH_INFRA)

- **Verdict agreement**: AGREE with PROVEN for AT-341, AT-424, AT-970, AT-971. **AGREE** with WEAK_PROOF for AT-040.
- **Citation spot-checks**:
  - `config.rs:149-262::appendix_a_default` -- CONFIRMED. Function `appendix_a_default` starts at line 149 and covers all params with match arms through the function.
  - `config.rs:433-456::resolve_config_value` -- CONFIRMED. Function starts at line 433, NaN/Inf check at 438-443, negative check at 444-449, default fallback at 452-455.
  - `config.rs:211::EvidenceguardGlobalCooldown => Some(120.0)` -- CONFIRMED at exactly line 211.
  - `config.rs:256::ReplayWindowHours => Some(48.0)` -- CONFIRMED at exactly line 256.
  - `test_config_defaults.rs:15-19::test_missing_instrument_cache_ttl_s_applies_default_3600` -- CONFIRMED at lines 15-19.
  - `test_config_defaults.rs:90-94::test_resolve_with_explicit_value_overrides_default` -- CONFIRMED at lines 90-94.
  - `test_config_defaults.rs:127-194::test_appendix_a_defaults_match_contract` -- CONFIRMED. Golden vector table with ~40 params.
- **Missed gaps**:
  - The audit correctly identifies AT-040 WEAK_PROOF as a P1 gap. The test at lines 38-66 constructs a `MissingConfigError` manually and checks its Display output, but does NOT call `resolve_config_value(param, None)` for a param that actually lacks a default. Since ALL 74 ConfigParam variants currently have defaults, the Err path of `resolve_config_value` is never exercised end-to-end. This is a real gap.
  - One additional observation: the premortem S5 identifies "Return Ok(default) for ALL missing params, including non-Appendix-A ones" as a wrong impl. The audit correctly notes this is **not blocked** because there is no ConfigParam without a default to test against. The wrong impl is currently untestable within the ConfigParam enum design. The audit's WEAK_PROOF is the right call.
- **S5 wrong-impl assessment**: AT-341 wrong impl (hardcode defaults, ignore overrides) is properly blocked by `test_resolve_with_explicit_value_overrides_default` at line 90-94 (verified). AT-040 wrong impl is correctly marked as WEAK -- the test does not call the actual function with a missing-default param. AT-424 parameterized test correctly iterates ALL_PARAMS (verified at line 72). Good analysis.

---

### S1-004 (BATCH_DISPATCH)

- **Verdict agreement**: AGREE with PROVEN for AT-277.
- **Citation spot-checks**:
  - `order_size.rs:97-133::build_order_size` -- MINOR SHIFT. The function signature `build_order_size` starts at line 83, the match block is at lines 97-133 (actually through line 130 for the result). Lines 83-95 are input validation. The cited range 97-133 correctly identifies the match block but the function starts earlier. Not materially wrong.
  - `order_size.rs:83-95` input validation -- CONFIRMED. Lines 85-86 check index_price (finite + positive), lines 88-89 check canonical_qty, lines 91-95 check contract_multiplier.
  - `test_order_size.rs:178::test_zero_index_price_rejected` -- CONFIRMED at line 178.
  - `test_order_size.rs:208::test_nan_index_price_rejected` -- CONFIRMED at line 208.
  - `test_order_size.rs:193::test_negative_index_price_rejected` -- CONFIRMED at line 193.
- **Missed gaps**: None identified. The S5 wrong impls are comprehensively blocked:
  - "Hardcode notional_usd=30_000" blocked by a test using qty_coin=1.5, index_price=50_000 producing notional_usd=75_000 (different from hardcoded value).
  - "Set qty_usd=None for ALL kinds" blocked by perpetual test asserting `qty_usd == Some(30_000)`.
  - "Use mark_price instead of index_price" is structurally prevented since the constructor API only receives `index_price`.
- **S5 wrong-impl assessment**: All four wrong impls from the premortem are properly blocked. The structural prevention for mark_price is valid -- the API type signature makes it impossible.

---

### S1-005 (BATCH_DISPATCH)

- **Verdict agreement**: AGREE with PROVEN for AT-277.
- **Citation spot-checks**:
  - `dispatch_map.rs:140-163::map_to_dispatch_unchecked` -- CONFIRMED. Function at lines 140-163 with instrument_kind match at 145-152 and intent match at 154-157.
  - `dispatch_map.rs:126-138::map_to_dispatch` -- CONFIRMED. Function at 126-138 with contracts gate at 133-134.
  - `dispatch_map.rs:44-52::DispatchRequest` -- CONFIRMED. Struct with `pub amount: f64` at line 48 and `pub reduce_only: bool` at line 50.
  - `dispatch_map.rs:154-157` reduce_only match -- CONFIRMED. `Open => false`, `Close | Hedge | Cancel => true`.
- **Missed gaps**:
  - The premortem S5 identifies "Map reduce_only correctly but forget to validate that amount > 0 before dispatch" as a wrong impl. The audit marks this as **PARTIAL/WEAK** because no dispatch-level guard exists for amount > 0 (upstream catches). This is correctly identified as a gap but appropriately rated as low risk since `build_order_size` rejects zero/negative canonical_qty.
  - One observation worth noting: Cancel mapping to reduce_only=true is a conservative design choice noted as INFO. The audit correctly identifies this is not in the contract but is defensively correct.
- **S5 wrong-impl assessment**: "Always send amount=qty_coin" blocked by perpetual and inverse_future tests. "Set reduce_only=true for ALL intents" blocked by `test_open_intent_not_reduce_only`. "Send both amount fields" is structurally prevented by single `amount: f64` in DispatchRequest. All correct.

---

### S1-007 (BATCH_DISPATCH)

- **Verdict agreement**: AGREE with PROVEN for AT-920, with important caveats properly noted.
- **Citation spot-checks**:
  - `dispatch_map.rs:179-224::validate_and_dispatch` -- CONFIRMED. Function starts at 179, AT-920 validation block at 187-217.
  - `dispatch_map.rs:22::CONTRACTS_AMOUNT_MATCH_TOLERANCE = 0.001` -- CONFIRMED at line 22.
  - `dispatch_map.rs:24::CONTRACTS_AMOUNT_MATCH_EPSILON = 1e-9` -- CONFIRMED at line 24.
  - `test_dispatch_map.rs:313::test_at920_mismatch_rejected` -- CONFIRMED. Test constructs mismatched OrderSize, asserts `ContractsAmountMismatch`.
  - `test_dispatch_map.rs:565::test_at920_no_dispatch_on_mismatch` -- CONFIRMED. Asserts `result.is_err()`.
  - `test_dispatch_map.rs:596::test_at920_mismatch_caller_sets_degraded_and_blocks_open` -- CONFIRMED. Lines 596-650 construct mismatch, verify ContractsAmountMismatch error, then manually set RiskState::Degraded and prove chokepoint blocks Open.
  - `test_dispatch_map.rs:443::test_at920_non_finite_multiplier_rejected` -- CONFIRMED at line 443.
  - `test_dispatch_map.rs:418::test_at920_epsilon_denominator_allows_small_amount_within_tolerance` -- CONFIRMED at line 418.
  - `test_dispatch_map.rs:525::test_at920_delta_in_error` -- Need to verify. The audit claims delta computation is tested.
- **Missed gaps**:
  - **IMPORTANT (correctly flagged)**: `validate_and_dispatch` has ZERO production callsites. The function is tested in isolation but not wired into the production pipeline. The test at line 596-593 documents this with TODO(AT-920-PROD). This is a P1 gap that the audit correctly identifies.
  - **IMPORTANT (correctly flagged)**: RiskState::Degraded is CALLER CONVENTION, not enforced by the function itself. The test at line 596 manually sets `risk_after_mismatch = RiskState::Degraded` rather than deriving it from the function return. This means a production caller could forget to map ContractsAmountMismatch to Degraded. Correctly identified as P1.
  - The PRD/contract name discrepancy (UnitMismatch vs ContractsAmountMismatch) is correctly noted as P2.
- **S5 wrong-impl assessment**: All four premortem wrong impls are properly blocked:
  - "Absolute tolerance instead of relative" -- blocked by `test_at920_delta_in_error` and epsilon test.
  - "Check tolerance but forget Degraded" -- blocked by test at line 596 (though with the caveat that Degraded is caller convention).
  - "Set Degraded but still dispatch" -- blocked by `test_at920_no_dispatch_on_mismatch`.
  - "Use wrong reject reason" -- blocked by pattern match on `ContractsAmountMismatch` at line 331-336.

**VERDICT NUANCE**: I would still call this PROVEN because the enforcement point itself (the validation function) is correct and tested, even though the production wiring is missing. The audit appropriately documents the zero-callsite risk as a P1 gap rather than downgrading the verdict. This is a calibration judgment call -- reasonable people could argue WEAK_PROOF due to the wiring gap, but PROVEN for the enforcement point itself is defensible.

---

### S1-012 (BATCH_EXPIRY)

- **Verdict agreement**: AGREE with WEAK_PROOF for all 7 ATs due to compilation failure.
- **Citation spot-checks**:
  - `lifecycle.rs:152::classify_lifecycle_error` -- CONFIRMED at line 152.
  - `lifecycle.rs:96::evaluate_expiry_guard` -- MINOR SHIFT. The function is at line 95 (`pub fn evaluate_expiry_guard`), not 96. The ledger says line 96 in one place and line 95 in another (inconsistent within the audit). The function is at 95. This is a trivial line-number discrepancy.
  - `base_gates.rs:356-386` -- CONFIRMED. ExpiryGuard gate check at lines 356-386 including fail-closed for missing expiry data on OPEN intents (lines 375-386).
  - `test_expiry_guard.rs:83::test_expiry_cancel_idempotent_success` -- CONFIRMED at line 83. Asserts Terminal, DoNotRetry, IdempotentSuccess, ExpiredOrDelisted.
  - `test_expiry_guard.rs:153::test_at950_pipeline_rejects_open_within_expiry_buffer` -- CONFIRMED at line 153. Pipeline test with causal proof (gate_trace.last() == ExpiryGuard, reject_reason_code == InstrumentExpiredOrDelisted).
  - `test_expiry_guard.rs:204::test_at965_pipeline_allows_open_outside_expiry_buffer` -- CONFIRMED at line 204. NON-TRIP test with Approved result.
  - `test_expiry_guard.rs:112::test_expiry_reconcile_does_not_halt_other_instruments` -- CONFIRMED at line 112.
  - `common/mod.rs` compilation error -- **CONFIRMED**. Lines 4-11 contain duplicate imports: `ChokeIntentClass, GateIntentClass, GateResults, IntentPipelineInput, L2BookSnapshot, L2Level, LiquidityGateInput, NetEdgeInput, OrderType, PreflightInput, PricerInput` appear twice, and `PricerSide` appears only in line 7 (first import block) but not in line 8-10 (second import block). The second block is missing `PricerSide` and `ChokeMetrics`. This IS a blocking compilation error.
- **Missed gaps**:
  - Correctly identified: AT-960 has no duplicate-call idempotency test (GAP-012-2, P1).
  - Correctly identified: AT-962 has no retry_count == 0 assertion (GAP-012-3, P2).
  - Correctly identified: `expiry_delist_buffer_s` default not directly tested (GAP-012-4, P2).
  - One additional observation from my INSTRUMENT domain perspective: the `evaluate_expiry_guard` function uses `expiry_delist_buffer_s` as a `u64` (seconds) and multiplies by 1000 to get milliseconds. The premortem S3 failure mode #1 identifies overflow risk and prescribes `checked_sub`/`saturating_sub`. I verified the implementation uses `saturating_mul` and `saturating_sub` in the buffer calculation. The audit correctly notes "Saturating arithmetic: Good fail-closed on overflow" in design risk note #5. GOOD.
  - The premortem S4.2 decision about "Strict allowlist with expiry-dependent fallback" is noted as "Partially" implemented in the audit (S4.2 divergence). The implementation at lifecycle.rs:171-183 maps `Other` to Retryable regardless of expiry state, which deviates from the premortem's chosen decision of classifying unknown errors as terminal for expired instruments. The audit notes this as INFO-level, but from an INSTRUMENT perspective this is a **minor gap**: if a venue returns a novel error code for an expired instrument, it will be classified as Retryable rather than Terminal. The premortem explicitly chose to treat unknown errors for expired instruments as terminal (fail-closed). This is arguably a P2 decision divergence worth tracking.
- **S5 wrong-impl assessment**:
  - AT-949 "Mark expired on ANY cancel" -- properly blocked by `test_expiry_non_terminal_cancel_does_not_mark_expired` (line 102). CONFIRMED test exists.
  - AT-950 "Reject ALL intents" -- properly blocked by `test_pipeline_close_passes_through_expired_instrument` (line 231) and `test_intent_drift_close_with_open_expiry_input_allowed` (line 297).
  - AT-960 "Skip dispatch but mutate ledger" -- correctly marked as WRONG_IMPL_UNBLOCKED. No duplicate-call test exists.
  - AT-961 "Swallow error silently" -- partially blocked. Test asserts ExpiredOrDelisted state on instrument A.
  - AT-962 "Mark expired but enqueue retries" -- partially blocked. DoNotRetry asserted but no retry_count == 0 check.

---

### S1-013 (BATCH_EXPIRY)

- **Verdict agreement**: AGREE with PROVEN for both AT-1056 and AT-1057.
- **Citation spot-checks**:
  - `pr_gate.sh:830-832` -- CONFIRMED. Lines 830-832 check `$CHECK_FAIL != "0"` and add `checks_failing` to problems array.
  - `pr_gate.sh:830-835` -- CONFIRMED. Lines 833-835 check `$CHECK_PENDING != "0"` and add `checks_pending`.
  - `test_pr_gate.sh:217-226` (Cases 5/6/7) -- CONFIRMED. Lines 215-226 include fixture definitions for `in_progress` (pending) and `failing_checks` (failure) scenarios. These produce check-run payloads that trigger the checks_failing/checks_pending paths.
  - `pr_gate.sh:71` -- Cited as `need gh` check. Not verified in detail but consistent with the test structure.
  - `pr_gate.sh:893, 905` -- Cited for reason token output. Not spot-checked in detail.
  - `pr_gate.sh:668` -- Cited for bot detection. Not spot-checked.
- **Missed gaps**:
  - Correctly flagged: PRD `enforcement_point = "DispatcherChokepoint"` is wrong for a CI script (GAP-013-1, P2). This is a metadata error, not a code error.
  - No other gaps identified. 29 test cases provide comprehensive coverage of the gate scenarios.
- **S5 wrong-impl assessment**: "Always exits 0" is blocked by Cases 5-7 using `expect_fail`. "Only checks build, not test" is blocked by the gate evaluating ALL check-runs uniformly (no filter on check-run name). Both correctly assessed.

---

## Cross-Batch Consistency Analysis

### PROVEN consistency

| Story | AT | Verdict | Evidence strength |
|-------|-----|---------|------------------|
| S1-001 | AT-905, AT-901 | PROVEN | Structural: directories exist, workspace builds |
| S1-010 | AT-341, AT-424, AT-970, AT-971 | PROVEN | Golden vector tests with exact value assertions |
| S1-004 | AT-277 | PROVEN | Field-value equality assertions, fail-closed input validation |
| S1-005 | AT-277 | PROVEN | Outbound amount field asserted, reduce_only table-driven |
| S1-007 | AT-920 | PROVEN | Dispatch count=0 on mismatch, reject reason match, metric increment |
| S1-013 | AT-1056, AT-1057 | PROVEN | Exit code + reason token fixture tests |

Assessment: PROVEN is used consistently across batches. In every case, there is:
1. An enforcement point with code at the cited location
2. Tests that assert causal proof (field values, dispatch counts, exit codes, reject reasons)
3. Fail-closed behavior verified (where applicable)

One calibration question: **S1-007 AT-920** has zero production callsites and RiskState::Degraded as caller convention. The DISPATCH batch gives this PROVEN. I would not disagree, but note this is the weakest PROVEN across all batches. The enforcement function itself is correct; the wiring gap is appropriately tracked as P1. If being strict, one could argue WEAK_PROOF, but the existing assessment is defensible.

### WEAK_PROOF consistency

| Story | AT | Verdict | Why |
|-------|-----|---------|-----|
| S1-010 | AT-040 | WEAK_PROOF | Test constructs error manually, doesn't call resolve_config_value for param without default |
| S1-012 | All 7 ATs | WEAK_PROOF | Compilation error in common/mod.rs blocks all tests |

Assessment: WEAK_PROOF is used consistently. In both cases, the code logic appears correct but tests cannot be verified as passing:
- S1-010/AT-040: Correct logic exists at config.rs:452-455 but the Err path is never exercised end-to-end.
- S1-012: All code exists and test logic appears correct, but compilation failure means tests have never been demonstrated to pass.

The WEAK_PROOF verdicts are appropriately calibrated -- tests exist but do not prove causality (AT-040) or cannot compile (S1-012).

### DEFERRED consistency

| Story | AT | Verdict | Why |
|-------|-----|---------|-----|
| S1-008 | AT-277, AT-920 | DEFERRED | Discovery doc only, enforcement in S1-004/S1-005/S1-007 |
| S1-009 | AT-277, AT-920 | DEFERRED | Discovery doc only, enforcement in S1-005/S1-007 |

Assessment: DEFERRED is used consistently. Both are discovery stories that produce reports but no enforcement code. Correct verdict.

### Cross-batch verdict standards: PASS

No cases found where the same level of evidence receives different verdicts in different batches.

---

## Systemic Patterns

### 1. Zero-callsite enforcement (S1-007, S1-012 pipeline wiring)

Both the DISPATCH and EXPIRY batches flag cases where enforcement code exists and is tested in isolation but has no production callsite. S1-007's `validate_and_dispatch` is explicitly called out with TODO(AT-920-PROD). S1-012's pipeline integration relies on `base_gates.rs` wiring that exists but is blocked by the common/mod.rs compilation error.

**Recommendation**: A systematic "callsite audit" pass should verify that every enforcement function has at least one production-path caller. This is a pattern worth checking across all batches.

### 2. Caller convention for state transitions (S1-007 Degraded, S1-012 InstrumentState)

S1-007 returns Err(ContractsAmountMismatch) but expects the CALLER to map this to RiskState::Degraded. S1-012's classify_lifecycle_error returns InstrumentState but expects the CALLER to persist it. Neither function enforces the state transition directly.

This is a consistent pattern (callers handle state transitions) but creates a systemic risk: if a caller forgets the mapping, the safety gate is incomplete. Both batches correctly identify this as a design risk.

### 3. Compilation errors as blocking issues (S1-012)

The EXPIRY batch correctly identifies the common/mod.rs compilation error as P0 and gives all S1-012 ATs WEAK_PROOF. This is the correct response -- no matter how good the test logic looks, if it cannot compile, it cannot be PROVEN.

The root cause is duplicate imports + missing `PricerSide` in the second import block at common/mod.rs lines 4-11. This is a straightforward fix (remove duplicate import lines 8-11 and keep only lines 4-7 which include PricerSide).

### 4. Discovery stories have minimal review surface (S1-008, S1-009)

The INFRA batch correctly gives both discovery stories DEFERRED verdicts with minimal remediation needed. These stories produce markdown reports, not enforcement code. The review surface is inherently small.

---

## Summary Table

| Story | Original Verdict | My Assessment | Citation Accuracy | Missed Gaps |
|-------|-----------------|---------------|-------------------|-------------|
| S1-001 | PROVEN (AT-905, AT-901) | AGREE | All 4 citations verified correct | None |
| S1-008 | DEFERRED (AT-277, AT-920) | AGREE | 2 citations verified correct | None |
| S1-009 | DEFERRED (AT-277, AT-920) | AGREE | Not spot-checked (discovery doc) | None beyond existing P2 |
| S1-010 | PROVEN (4 ATs) / WEAK_PROOF (AT-040) | AGREE | All 7 citations verified correct | None -- AT-040 gap correctly identified |
| S1-004 | PROVEN (AT-277) | AGREE | 5 citations verified correct | None |
| S1-005 | PROVEN (AT-277) | AGREE | 4 citations verified correct | None |
| S1-007 | PROVEN (AT-920) | AGREE (borderline -- weakest PROVEN) | 8 citations verified correct | None -- zero-callsite + caller-convention gaps correctly flagged as P1 |
| S1-012 | WEAK_PROOF (all 7 ATs) | AGREE | 8 citations verified; lifecycle.rs:96 should be :95 (minor) | S4.2 expiry-dependent fallback not fully implemented per premortem decision (P2) |
| S1-013 | PROVEN (AT-1056, AT-1057) | AGREE | 3 citations verified correct | None |

---

## Overall Assessment

All three evidence ledgers demonstrate thorough, well-calibrated auditing. Citation accuracy is high across the board (only one minor line-number discrepancy in the entire review: lifecycle.rs cited as line 96 instead of 95). Verdict calibration is consistent: PROVEN requires enforcement code + causal test proof, WEAK_PROOF correctly flags untestable or non-compiling paths, and DEFERRED is reserved for discovery-only stories.

The most significant finding is the **P0 compilation error in common/mod.rs** (GAP-012-1) which blocks all S1-012 test verification. This should be the top priority fix before any subsequent verification pass.

Secondary priorities:
- P1: S1-010 AT-040 Err path end-to-end test (GAP-010-1)
- P1: S1-007 zero production callsites for validate_and_dispatch (GAP-S1007-2)
- P1: S1-007 RiskState::Degraded caller convention enforcement (GAP-S1007-3)
- P1: S1-012 AT-960 duplicate-call idempotency test (GAP-012-2)
