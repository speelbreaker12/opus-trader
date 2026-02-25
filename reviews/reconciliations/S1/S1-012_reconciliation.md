---
provenance:
  tool: claude-code
  model: claude-opus-4-6
  prompt_style: R1-preflight-audit (recon-v3.1)
  cycle: recon-v3.1
  phase_equivalent: R1
artifact_type: evidence_ledger
scope: S1-012
---

# RECONCILIATION R1 PREFLIGHT AUDIT: S1-012

> Story: S1-012 -- S1.4 Instrument lifecycle + expiry safety (Expiry Cliff Guard)
> Enforcement Point: DispatcherChokepoint
> ATs: AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966
> Premortem: `reviews/premortems/S1-012_premortem.md`
> Prior reconciliation: `reviews/reconciliations/slice1/BATCH_EXPIRY_reconciliation.md` (recon-v1.x, NO-GO due to compile error)

## READ-ONLY INTEGRITY CHECK (START)

```
git status --porcelain  # start of audit
M  CLAUDE.md
M  crates/soldier_core/Cargo.toml
M  crates/soldier_core/src/execution/build_order_intent.rs
M  crates/soldier_core/src/execution/dispatch_map.rs
M  crates/soldier_core/src/execution/gate_outcome.rs
M  crates/soldier_core/src/execution/open_runtime.rs
M  crates/soldier_core/src/execution/pipeline.rs
M  crates/soldier_core/src/execution/reject_reason.rs
M  crates/soldier_core/src/risk/pending_exposure.rs
M  crates/soldier_core/tests/test_dispatch_map.rs
M  crates/soldier_core/tests/test_gate_outcome.rs
M  crates/soldier_core/tests/test_intent_pipeline.rs
M  crates/soldier_core/tests/test_recorded_before_dispatch_gate.rs
M  crates/soldier_core/tests/test_reject_reason.rs
M  plans/review_logged.sh
M  reviews/reconciliations/slice1/DEBT_REGISTER.json
M  reviews/reconciliations/slice1/GAP_LIST.md
M  specs/CONTRACT.md
(plus untracked .claude/ and artifacts/ files -- none in scope)
```

No S1-012 source or test files are modified (all changes are from fresh-eyes audit fixes to other stories). S1-012 files are at their committed state.

## HARD GATE

Premortem SS10 STOPLIGHT: **YELLOW**

Debt items (3):
1. DelistingSoon intermediate state -- Low, deferred to Slice 2+
2. Unknown venue error code handling -- Low, deferred to Slice 2+
3. No combined AT for buffer + reconcile interaction -- Low, deferred to Slice 2+

All YELLOW gaps are DEFERRED with owner + target slice. Proceeding.

## PRIOR RECONCILIATION STATUS

The v1.x batch reconciliation (`BATCH_EXPIRY_reconciliation.md`) returned **NO-GO** due to GAP-012-1 (P0 compile error in `common/mod.rs`). That P0 has been **FIXED** (GAP_LIST.md Phase R5, line 232). Additionally:
- GAP-012-2 (P1, AT-960 duplicate-call idempotency test): **FIXED** -- `test_expiry_cancel_idempotent_duplicate_noop` added
- GAP-012-3 (P2, AT-962 restart_required assertion): **ALREADY PRESENT** -- GAP citation added
- GAP-012-4 (P2, default buffer_s config test): **N/A** -- not in Appendix A system
- GAP-012-5 (DEFERRED): Reconcile loop integration test
- GAP-012-6 (DEFERRED): DelistingSoon intermediate state
- GAP-012-7 (P2, ACCEPTED): SS4.2 decision divergence -- Other errors always Retryable regardless of expiry

All 28 expiry guard tests now compile and pass. This R1 audit re-evaluates all 7 ATs against the fixed codebase.

---

## A) GATE RESULT

```
GATE: GO
Reason: All 7 ATs have enforcement points with verified causal proofs.
        All 28 tests pass (cargo test -p soldier_core --test test_expiry_guard: 28 ok, 0 failed).
        Pipeline causality test passes (test_intent_pipeline::test_causality_expiry_guard_blocks_dispatch).
        Prior P0 (compile error) and P1 (idempotency test) gaps are resolved.
        3 DEFERRED items tracked in debt register.
```

---

## B) AT AUDIT TABLE

| AT ID | Contract SS | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | SS5 wrong impls blocked? | SS4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-949 | SS1.0.Y | `venue/lifecycle.rs:167-185::classify_lifecycle_error` | `test_expiry_cancel_idempotent_success` (line 88); `test_cancel_outcome_varies_by_intent_for_expired` (line 160) | **PROVEN**: asserts Terminal(InstrumentExpiredOrDelisted), DoNotRetry, IdempotentSuccess, instrument_state==ExpiredOrDelisted. Varies by intent (Cancel vs Close). | Yes: terminal -> DoNotRetry, restart_required=false, reconcile_scope=InstrumentOnly | Yes: AT-966 is NON-TRIP pair; `test_cancel_outcome_varies_by_intent_for_expired` blocks "mark expired on ANY cancel" | Yes: SS4.1 dedicated ExpiryGuard in `venue/lifecycle.rs` | **PROVEN** |
| AT-950 | SS1.0.Y | `venue/lifecycle.rs:95-164::evaluate_expiry_guard` + `base_gates.rs:362-392` (Gate 6 wiring) | Unit: `test_expiry_delist_buffer_rejects_open` (line 20); Pipeline: `test_at950_pipeline_rejects_open_within_expiry_buffer` (line 198); Boundary: `test_expiry_at_exact_boundary_rejects_open` (line 69); Pipeline causality: `test_causality_expiry_guard_blocks_dispatch` (test_intent_pipeline.rs:392) | **PROVEN**: dispatch_count==0, reject_reason==InstrumentExpiredOrDelisted, gate_trace.last()==ExpiryGuard, no LiquidityGate/NetEdgeGate/Pricer in trace (proves early exit) | Yes: saturating_mul/sub (line 151-152); missing expiry input -> Rejected for OPEN (base_gates.rs:381-392); missing timestamp for expirable instruments -> Rejected (lifecycle.rs:111-131); u64::MAX -> Rejected (lifecycle.rs:141-148); MAX_REASONABLE_EXPIRY_MS bound (7.3e15) | Yes: AT-965 is NON-TRIP pair; `test_pipeline_close_passes_through_expired_instrument` blocks "reject ALL intents" wrong impl | Yes: SS4.1 dedicated ExpiryGuard | **PROVEN** |
| AT-960 | SS1.0.Y | `venue/lifecycle.rs:167-185::classify_lifecycle_error` (pure function, stateless) | `test_expiry_cancel_idempotent_success` (line 88); `test_expiry_cancel_idempotent_duplicate_noop` (line 586) | **PROVEN**: duplicate-call test calls classify_lifecycle_error twice with identical inputs, asserts identical outputs (class, retry, cancel_outcome, instrument_state). Verifies IdempotentSuccess + DoNotRetry + Terminal. Pure function = no side effects = no ledger mutation. | Yes: pure function, no mutable state | Yes: duplicate-call test blocks "skip dispatch but mutate ledger" wrong impl. Pure function proof is structural. | Yes: SS4.3 instrument_state on metadata | **PROVEN** |
| AT-961 | SS1.0.Y | `venue/lifecycle.rs:167-185::classify_lifecycle_error` -- returns `reconcile_scope: ReconcileScope::InstrumentOnly` for terminal errors | `test_expiry_reconcile_does_not_halt_other_instruments` (line 117) | **PROVEN**: Instrument A (terminal) gets InstrumentOnly + ExpiredOrDelisted; Instrument B (Other error) gets Retryable + Active. Proves non-contamination. | Yes: InstrumentOnly scope prevents cross-instrument abort | Yes: SS5 "swallow error silently" blocked -- test asserts A is marked ExpiredOrDelisted (not silently dropped) | Yes: SS4.1 dedicated ExpiryGuard | **PROVEN** |
| AT-962 | SS1.0.Y | `venue/lifecycle.rs:167-185::classify_lifecycle_error` -- returns `retry: RetryDirective::DoNotRetry` + `class: Terminal` + `restart_required: false` | `test_expiry_no_retry_loop_after_positions_clear` (line 140) | **PROVEN**: asserts Terminal, DoNotRetry, restart_required==false. Three-way proof blocks all retry re-entry paths (direct retry, restart-triggered retry, reclassification to retryable). | Yes: DoNotRetry is definitive; Terminal prevents reclassification | Yes: SS5 "mark expired but enqueue retries" blocked by DoNotRetry + restart_required==false + Terminal classification (GAP-012-3 citation at line 134-138) | Yes: SS4.3 instrument_state on metadata | **PROVEN** |
| AT-965 | SS1.0.Y | `venue/lifecycle.rs:95-164::evaluate_expiry_guard` -- returns Allowed when now_ms < opens_blocked_from_ms | Unit: `test_expiry_outside_buffer_allows_open` (line 37); Pipeline: `test_at965_pipeline_allows_open_outside_expiry_buffer` (line 249) | **PROVEN**: Allowed (unit); pipeline: Approved, reject_reason_code==None. Proves guard does not fire outside buffer. | N/A (NON-TRIP -- verifies absence of false positives) | Yes: paired with AT-950 TRIP. Both must pass in same suite. "Always allow OPEN" wrong impl fails AT-950. | Yes | **PROVEN** |
| AT-966 | SS1.0.Y | `venue/lifecycle.rs:186-198::classify_lifecycle_error` -- VenueLifecycleError::Other returns instrument_state: Active | `test_expiry_non_terminal_cancel_does_not_mark_expired` (line 107) | **PROVEN**: asserts Retryable, RetryAllowed, RetryableFailure, instrument_state==Active. Proves non-terminal cancel preserves Active state. | N/A (NON-TRIP -- verifies absence of false positives) | Yes: paired with AT-949 TRIP. "Never mark anything expired" wrong impl fails AT-949. | Yes | **PROVEN** |

**All 7 ATs: PROVEN**

---

## C) PREMORTEM CROSS-REFERENCE

### SS2 Assumptions

| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `expiration_timestamp_ms` available from cached metadata | Missing -> guard cannot compute buffer | `test_no_expiration_timestamp_allows_open` (perpetual, None -> Allowed); `test_expiry_guard_missing_timestamp_linear_future_rejected` (expirable, None -> Rejected); `test_expiry_guard_missing_timestamp_option_rejected`; `test_expiry_guard_missing_timestamp_inverse_future_rejected`; `test_expiry_guard_missing_timestamp_unknown_rejected` (unknown kind, None -> Rejected); `test_pipeline_open_rejected_when_expiry_input_none` (pipeline-level: None input -> Rejected) | **VALIDATED** -- 6 tests cover all instrument_kind x None combinations. Fail-closed for non-perpetuals. |
| 2 | `expiry_delist_buffer_s` has non-zero default | Zero buffer degenerates check | Tests use explicit buffer_s=60. No default config test. | **ASSUMPTION_UNTESTED** (GAP-012-4, N/A -- not in Appendix A config system. Buffer value is set per-call, not from a global default.) |
| 3 | Venue terminal errors mapped to finite set | Unknown error string missed | `VenueLifecycleError` enum at `lifecycle.rs:43-47` has exactly 2 variants: `InstrumentExpiredOrDelisted` and `Other`. Mapping happens upstream. Table-driven at enum level (exhaustive match). | **VALIDATED** -- enum is exhaustive, compiler enforces match completeness. |
| 4 | Intent classification correct (S1-003 dependency) | Misclassification -> wrong rejection | `base_gates.rs:233-238` derives `lifecycle_intent` from `ChokeIntentClass` (authoritative). `test_intent_drift_close_with_open_expiry_input_allowed` (line 342) proves the pipeline overrides caller-provided intent drift. Upstream classification tested in S1-003. | **VALIDATED** -- pipeline override at `base_gates.rs:364-368` provides defense-in-depth. |
| 5 | Reconcile loop iterates per-instrument, no short-circuit | `?` aborts on first error | `test_expiry_reconcile_does_not_halt_other_instruments` (line 117) proves signal-level non-contamination. | **PARTIALLY VALIDATED** -- unit-level signals proven; actual loop integration deferred (GAP-012-5). |

### SS4 Decisions

| Decision | Chosen | Implemented | Match? | Notes |
|----------|--------|-------------|--------|-------|
| SS4.1: Where does the expiry guard live? | (A) Dedicated ExpiryGuard module | `venue/lifecycle.rs` -- dedicated module with `evaluate_expiry_guard()` and `classify_lifecycle_error()` | **MATCH** | Module location is `venue/lifecycle.rs` not `risk/`, but architecturally sound. ExpiryGuard is wired as Gate 6 in `base_gates.rs:362-392`. |
| SS4.2: Unknown venue error codes for expired instruments | (A) Strict allowlist with expiry-dependent fallback | Strict allowlist only. `VenueLifecycleError::Other` always maps to `Retryable` regardless of expiry state (`lifecycle.rs:186-198`). No expiry-dependent fallback. | **DIVERGENCE** (GAP-012-7, ACCEPTED) | The `classify_lifecycle_error` function takes `(intent, error)` but not `is_expired` -- it cannot implement the expiry-dependent fallback. Divergence is conservative: Retryable for unknown errors is safe (may miss a terminal signal for expired instruments but does not create false positives). Accepted as safe in GAP-012-7. |
| SS4.3: instrument_state storage location | (A) Field on instrument metadata struct | Dedicated `InstrumentState` enum in `risk/instrument_state.rs` (Active, ExpiredOrDelisted). Used as a field in `LifecycleDecision` returned by `classify_lifecycle_error`. | **MATCH** (structural equivalent) | The enum is not literally a field on a metadata struct but is returned from the lifecycle classification function for the caller to set. Functionally equivalent. |

### SS5 Wrong-Impl Gate

| AT | Wrong impl | Blocking test(s) | Blocked? |
|----|-----------|------------------|----------|
| AT-949 | Mark expired on ANY cancel (not just terminal errors) | `test_expiry_non_terminal_cancel_does_not_mark_expired` (line 107) -- VenueLifecycleError::Other returns Active | **BLOCKED** |
| AT-950 | Reject ALL intents (not just OPEN) within buffer | `test_pipeline_close_passes_through_expired_instrument` (line 276); `test_intent_drift_close_with_open_expiry_input_allowed` (line 342); `evaluate_expiry_guard` returns Allowed for non-Open intents at `lifecycle.rs:96-98` | **BLOCKED** |
| AT-960 | Skip dispatch but mutate ledger on duplicate cancel | `test_expiry_cancel_idempotent_duplicate_noop` (line 586) -- calls classify_lifecycle_error twice, asserts identical output. Pure function = no mutable state = no ledger mutation. | **BLOCKED** |
| AT-961 | Catch panic from A but swallow error silently (no marking) | `test_expiry_reconcile_does_not_halt_other_instruments` (line 117) -- asserts instrument_state==ExpiredOrDelisted for instrument A | **BLOCKED** |
| AT-962 | Mark A expired but enqueue retry attempts | `test_expiry_no_retry_loop_after_positions_clear` (line 140) -- asserts DoNotRetry + Terminal + restart_required==false (triple proof) | **BLOCKED** |
| AT-965 | Always allow OPEN (never check buffer) | AT-950 TRIP tests catch this (buffer rejects OPEN). Test suite requires both to pass. | **BLOCKED** (paired) |
| AT-966 | Never mark anything as expired (global no-op) | AT-949 TRIP tests catch this (terminal cancel marks expired). Test suite requires both to pass. | **BLOCKED** (paired) |

**All 7 wrong impls blocked.**

---

## D) DESIGN RISK NOTES

### D1: Fail-closed coverage (6 categories)

| Category | Coverage | Evidence |
|----------|----------|----------|
| Missing/None | **COVERED** | `expiration_timestamp_ms: None` tested for all 4 InstrumentKind variants + unknown (None). `expiry_guard: None` in pipeline -> Rejected for OPEN (base_gates.rs:381-392). 6 tests. |
| NaN/Inf | **N/A** | All inputs are `u64` (integer types). No floating-point in expiry guard inputs. Not applicable. |
| Negative | **N/A** | All inputs are `u64` (unsigned). Cannot represent negative values. Not applicable. |
| Out-of-domain | **COVERED** | `u64::MAX` timestamp -> Rejected (test line 510). `MAX_REASONABLE_EXPIRY_MS` bound at `lifecycle.rs:141` (7.3e15). Boundary tests at exact bound (allowed) and 1ms above (rejected). `expiry_delist_buffer_s` overflow protected by `saturating_mul` (line 151). |
| Corrupt | **COVERED** | u64::MAX test covers corrupt feed data. MAX_REASONABLE_EXPIRY_MS bounds-check at lifecycle.rs:141-149 with tracing::warn. |
| Narrowing casts | **N/A** | No casts in evaluate_expiry_guard or classify_lifecycle_error. All types are u64 throughout. |

### D2: Observability on reject/degrade paths

| Path | Logging | Metric | Status |
|------|---------|--------|--------|
| OPEN rejected (inside buffer) | `tracing::info!` at lifecycle.rs:154-159 (now_ms, expiration_ms, buffer_ms) | `METRIC_EXPIRY_GUARD_REJECT` defined at mod.rs:26 but `#[allow(dead_code)]` -- **NOT WIRED** | **GAP**: metric constant defined but not incremented anywhere |
| OPEN rejected (missing timestamp, expirable) | `tracing::warn!` at lifecycle.rs:113-117 | Same unwired metric | **GAP**: same as above |
| OPEN rejected (missing timestamp, unknown kind) | `tracing::warn!` at lifecycle.rs:124-127 | Same unwired metric | **GAP**: same as above |
| OPEN rejected (corrupt timestamp) | `tracing::warn!` at lifecycle.rs:143-147 | Same unwired metric | **GAP**: same as above |
| Perpetual allowed (no expiry) | `tracing::debug!` at lifecycle.rs:105-108 | None needed | OK |
| Pipeline: OPEN rejected at ExpiryGuard | Gate trace includes GateStep::ExpiryGuard; reject_reason_code = InstrumentExpiredOrDelisted | Pipeline-level rejection counters (if wired) | OK (structural) |

**Observability finding**: `METRIC_EXPIRY_GUARD_REJECT` (defined at `crates/soldier_core/src/execution/mod.rs:26`) has `#[allow(dead_code)]` and is never referenced outside its definition. The metric is declared but not wired to any counter increment. This means the drift metric described in premortem SS7 (`s1_012_checks_total{result="rejected"}`) is **not operational**. Tracing logs provide structured observability but the counter for dashboards/alerts is missing.

### D3: Intent override defense

The pipeline at `base_gates.rs:233-238` derives `lifecycle_intent` from `ChokeIntentClass` (authoritative source), then at `base_gates.rs:364-368` overrides the caller-provided `ExpiryGuardInput.intent` with this derived value. This is a strong defensive design that prevents intent drift from causing false rejections. Test `test_intent_drift_close_with_open_expiry_input_allowed` (line 342) explicitly validates this override.

### D4: DelistingSoon state absent

`InstrumentState` enum at `risk/instrument_state.rs:1-10` has only two variants: `Active` and `ExpiredOrDelisted`. The contract defines `DelistingSoon` as a required enum variant (CONTRACT.md SS1.0.Y: "instrument_state: enum { Active, DelistingSoon, ExpiredOrDelisted }"). The variant is absent from the implementation. This is tracked as GAP-012-6 (DEFERRED to Slice 2+) in the debt register.

### D5: Saturating arithmetic

`evaluate_expiry_guard` uses `saturating_mul` (line 151) and `saturating_sub` (line 152). On overflow, `saturating_sub` returns 0, making `opens_blocked_from_ms = 0`, which means `now_ms >= 0` is always true, resulting in OPEN rejection. This is correct fail-closed behavior.

### D6: METRIC_EXPIRY_GUARD_REJECT dead code

The constant `METRIC_EXPIRY_GUARD_REJECT = "expiry_guard_reject_total"` at `execution/mod.rs:26` is marked `#[allow(dead_code)]` with comment "Reserved for expiry guard instrumentation." It is never used. This should be wired in Slice 2 when runtime metrics are integrated.

### D7: Prior P0 resolution verified

GAP-012-1 (common/mod.rs compile error) is confirmed fixed. All 28 tests in `test_expiry_guard.rs` compile and pass. The pipeline causality test `test_causality_expiry_guard_blocks_dispatch` also passes.

---

## E) REMEDIATION PLAN

### Resolved (from prior reconciliation)

| Gap ID | Priority | Status | Resolution |
|--------|----------|--------|------------|
| GAP-012-1 | P0 | **FIXED** | common/mod.rs compilation error removed |
| GAP-012-2 | P1 | **FIXED** | `test_expiry_cancel_idempotent_duplicate_noop` added (line 586) |
| GAP-012-3 | P2 | **ALREADY PRESENT** | `restart_required == false` asserted at line 152; GAP citation at lines 134-138 |
| GAP-012-4 | P2 | **N/A** | Buffer not in Appendix A config system |

### Open (tracked in debt register)

| Gap ID | Priority | Description | Target |
|--------|----------|-------------|--------|
| GAP-012-5 | DEFERRED | Reconcile loop integration test (unit tests prove signals, not actual loop) | Slice 2+ |
| GAP-012-6 | DEFERRED | DelistingSoon intermediate state variant missing from InstrumentState enum | Slice 2+ |
| GAP-012-7 | P2->ACCEPTED | SS4.2 decision divergence: Other errors -> Retryable regardless of expiry (conservative, safe) | Accepted |

### New findings from this audit

| Finding | Priority | Description | Target |
|---------|----------|-------------|--------|
| D6 | P2 (INFO) | `METRIC_EXPIRY_GUARD_REJECT` constant declared but never wired to a counter. SS7 drift metric not operational. Tracing logs provide structured observability as partial mitigation. | Slice 2+ (wire when runtime metrics are integrated) |

---

## F) SCOPE CHECK

| Predicted scope.touch | Exists? | Touched? | Key files |
|----------------------|---------|----------|-----------|
| `crates/soldier_core/src/risk` | Yes | Yes | `risk/instrument_state.rs` (InstrumentState enum) |
| `crates/soldier_core/src/venue` | Yes | Yes | `venue/lifecycle.rs` (ExpiryGuard logic, classify_lifecycle_error) |
| `crates/soldier_core/tests` | Yes | Yes | `tests/test_expiry_guard.rs` (28 tests), `tests/test_intent_pipeline.rs` (causality test) |

**Scope drift** (same as prior reconciliation): `execution/base_gates.rs`, `execution/build_order_intent.rs`, `execution/gate_outcome.rs`, `execution/reject_reason.rs`, `execution/pipeline.rs`, `execution/mod.rs` were touched for pipeline wiring. PRD `scope.touch` was too narrow but all touched files are architecturally correct and necessary for Gate 6 integration.

---

## TEST VERIFICATION

```
cargo test -p soldier_core --test test_expiry_guard
# result: ok. 28 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

cargo test -p soldier_core --test test_intent_pipeline test_causality_expiry_guard_blocks_dispatch
# result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 15 filtered out
```

All 29 relevant tests pass at audit time.

---

## READ-ONLY INTEGRITY CHECK (END)

This audit created only this evidence ledger file (`reviews/reconciliations/S1/S1-012_reconciliation.md`). No production code, test code, or configuration was modified.

---

READY FOR SELF_REVIEW
