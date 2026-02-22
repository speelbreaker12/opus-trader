# RECONCILIATION AUDIT: S1-012 (Expiry Cliff Guard)

NO_PRIOR_POSTMORTEM

## READ-ONLY INTEGRITY CHECK
```
diff /tmp/recon_start_status_S1-012.txt /tmp/recon_end_status_S1-012.txt
(empty — no workspace modifications)
```

## HARD GATE
Premortem §10 STOPLIGHT: **YELLOW**
- Debt items all marked DEFERRED with owner + target slice (Slice 2+)
- DelistingSoon intermediate state: Low severity, deferred
- Unknown venue error code handling: Low severity, deferred
- No combined AT for buffer + reconcile interaction: Low severity, deferred

All YELLOW gaps are explicitly DEFERRED. Proceeding.

---

## A) GATE RESULT

```
GATE: NO-GO
Reason: COMPILATION_ERROR in shared test common/mod.rs blocks all test_expiry_guard tests from running; test evidence cannot be verified at HEAD
```

---

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-949 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:152::classify_lifecycle_error` | `test_expiry_guard.rs:83::test_expiry_cancel_idempotent_success` | Yes: asserts Terminal, DoNotRetry, IdempotentSuccess, ExpiredOrDelisted | Yes: terminal -> DoNotRetry | AT-966 is pair but COMPILE FAILURE blocks | Yes: §4.1 dedicated ExpiryGuard | **WEAK_PROOF** (compile failure) |
| AT-950 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:96::evaluate_expiry_guard` + `base_gates.rs:356-386` | `test_expiry_guard.rs:15::test_expiry_delist_buffer_rejects_open` (unit) + `test_expiry_guard.rs:153::test_at950_pipeline_rejects_open_within_expiry_buffer` (pipeline) | Yes: Rejected(InstrumentExpiredOrDelisted); pipeline: gate_trace.last() == ExpiryGuard, dispatch_count=0 | Yes: saturating_mul/sub; missing expiry -> Rejected for expirable | AT-965 is NON-TRIP pair but COMPILE FAILURE blocks | Yes: §4.1 dedicated ExpiryGuard | **WEAK_PROOF** (compile failure) |
| AT-960 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:152::classify_lifecycle_error` (pure function = idempotent) | `test_expiry_guard.rs:83::test_expiry_cancel_idempotent_success` | Partial: single-call semantics but NO duplicate-call test | Yes: pure function | No "ledger checksum unchanged" tightening | Yes: §4.3 field on metadata | **WEAK_PROOF** (no duplicate-call test + compile failure) |
| AT-961 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:152::classify_lifecycle_error` — returns `reconcile_scope: InstrumentOnly` | `test_expiry_guard.rs:112::test_expiry_reconcile_does_not_halt_other_instruments` | Yes: A gets InstrumentOnly + ExpiredOrDelisted; B gets Retryable + Active | Yes: InstrumentOnly prevents cross-contamination | §5 "swallow error" blocked by asserting ExpiredOrDelisted | Yes | **WEAK_PROOF** (compile failure) |
| AT-962 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:152::classify_lifecycle_error` — returns `retry: DoNotRetry` + `class: Terminal` | `test_expiry_guard.rs:130::test_expiry_no_retry_loop_after_positions_clear` | Yes: Terminal, DoNotRetry, restart_required=false | Yes: DoNotRetry definitive | §5 "retry queue grows" partially blocked but no retry_count==0 assertion | Yes | **WEAK_PROOF** (compile failure) |
| AT-965 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:95::evaluate_expiry_guard` — returns Allowed outside buffer | `test_expiry_guard.rs:32::test_expiry_outside_buffer_allows_open` (unit) + `test_expiry_guard.rs:204::test_at965_pipeline_allows_open_outside_expiry_buffer` (pipeline) | Yes: Allowed; pipeline: Approved, reject_reason_code==None, dispatch_count==1 | N/A (NON-TRIP) | Counterpart to AT-950 | Yes | **WEAK_PROOF** (compile failure) |
| AT-966 | §1.0.Y | `crates/soldier_core/src/venue/lifecycle.rs:171::classify_lifecycle_error` — Other returns Active | `test_expiry_guard.rs:102::test_expiry_non_terminal_cancel_does_not_mark_expired` | Yes: Retryable, Active, RetryableFailure | N/A (NON-TRIP) | Counterpart to AT-949 | Yes | **WEAK_PROOF** (compile failure) |

**CRITICAL NOTE**: All verdicts are WEAK_PROOF because `crates/soldier_core/tests/common/mod.rs` has a compilation error (`PricerSide` not found at line 7, duplicate imports at lines 4-11) that prevents any test in `test_expiry_guard.rs` from compiling.

---

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | `expiration_timestamp_ms` available from cached instrument metadata | Test with None (perpetual) → Allowed | TESTED: `test_no_expiration_timestamp_allows_open` (line 46) + Q7 retrofit tests (lines 341-475) |
| 2 | `expiry_delist_buffer_s` has non-zero default | Config test: default > 0 | NOT DIRECTLY TESTED: tests use explicit buffer_s=60. ASSUMPTION_UNTESTED. |
| 3 | Venue terminal errors mapped to finite set | Table-driven enum test | TESTED: enum-level matching, not fuzzy strings |
| 4 | Intent classification correct (S1-003 dependency) | Upstream tests | TESTED INDIRECTLY: pipeline tests use ChokeIntentClass; base_gates overrides with authoritative lifecycle_intent |
| 5 | Reconcile loop iterates per-instrument | AT-961 tests | TESTED at unit level; no loop integration test |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| §4.1: Dedicated ExpiryGuard module | (A) Dedicated module | Yes | `venue/lifecycle.rs:1-184` |
| §4.2: Strict allowlist with expiry-dependent fallback | (A) Strict allowlist | Partially: enum-level matching is effectively allowlist. No expiry-dependent fallback for Other. | `lifecycle.rs:171-183` — Other always → Retryable |
| §4.3: instrument_state on metadata | (A) Field on metadata struct | Yes — dedicated enum | `risk/instrument_state.rs:1-10` |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-949: Mark expired on ANY cancel | Yes | `test_expiry_non_terminal_cancel_does_not_mark_expired` (line 102) | Yes |
| AT-950: Reject ALL intents (not just OPEN) | Yes | `test_pipeline_close_passes_through_expired_instrument` (line 231) + `test_intent_drift_close_with_open_expiry_input_allowed` (line 297) | Yes |
| AT-960: Skip dispatch but mutate ledger | **No** | — | **WRONG_IMPL_UNBLOCKED**: No duplicate-call test |
| AT-961: Swallow error silently | Partial | `test_expiry_reconcile_does_not_halt_other_instruments` (line 112) | Partially |
| AT-962: Mark expired but enqueue retries | Partial | `test_expiry_no_retry_loop_after_positions_clear` (line 130) | Partially — DoNotRetry but no retry_count==0 |
| AT-965: Always allow OPEN | Yes (paired) | AT-950 TRIP test catches this | Yes |
| AT-966: Never mark anything expired | Yes (paired) | AT-949 TRIP test catches this | Yes |

---

## D) DESIGN RISK NOTES

1. **COMPILATION ERROR in common/mod.rs** (BLOCKING): `PricerSide` not found + duplicate imports. Blocks ALL integration tests.
2. **No reconcile loop integration test**: Unit tests prove signals but not that the loop respects them.
3. **AT-960 idempotency is structural, not tested**: Pure function argument strong but no duplicate-call test.
4. **DelistingSoon absent**: Explicitly deferred.
5. **Saturating arithmetic**: Good fail-closed on overflow.
6. **Intent override in pipeline**: Good defensive design.

---

## E) REMEDIATION PLAN

```
[CODE_FIX]  GAP-012-1: Fix common/mod.rs compilation error. P0.
[TEST_FIX]  GAP-012-2: Add duplicate-call idempotency test for AT-960. P1.
[TEST_FIX]  GAP-012-3: Add retry_count == 0 assertion for AT-962. P2.
[TEST_FIX]  GAP-012-4: Add default expiry_delist_buffer_s config test. P2.
[DEFERRED]  GAP-012-5: Reconcile loop integration test. (Slice 2+)
[DEFERRED]  GAP-012-6: DelistingSoon intermediate state. (Slice 2+)
[INFO]      §4.2 divergence: enum boundary at different layer than predicted. Not a defect.
[INFO]      prd.json implementation_tests list is accurate.
```

---

## F) SCOPE CHECK

| Predicted scope.touch | Exists? | Touched? | Notes |
|----------------------|---------|----------|-------|
| `crates/soldier_core/src/risk` | Yes | Yes | `instrument_state.rs` added |
| `crates/soldier_core/src/venue` | Yes | Yes | `lifecycle.rs` added |
| `crates/soldier_core/tests` | Yes | Yes | `test_expiry_guard.rs` with 20 tests |

**Scope drift**: `execution/base_gates.rs`, `build_order_intent.rs`, `gate_outcome.rs`, `reject_reason.rs`, `pipeline.rs` — all in execution/ for pipeline wiring. PRD scope.touch was too narrow but touched files are architecturally correct.

---

READY FOR SELF_REVIEW

---
---

# RECONCILIATION AUDIT: S1-013 (PR Merge-Readiness Automation Gate)

NO_PRIOR_POSTMORTEM

## READ-ONLY INTEGRITY CHECK
```
diff /tmp/recon_start_status_S1-013.txt /tmp/recon_end_status_S1-013.txt
(empty — no workspace modifications)
```

## HARD GATE
Premortem §10 STOPLIGHT: **GREEN**

---

## A) GATE RESULT

```
GATE: GO
Reason: Both ATs have enforcement points, proving tests, and all tests pass.
```

---

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-1056 | §0.Z.9.1 | `plans/pr_gate.sh:830-832` — checks_failing detection | `plans/tests/test_pr_gate.sh:217-226` (Cases 5/6/7) | Yes: expect_fail asserts exit!=0 + reason token | Yes: empty/null → pending → fail | Yes: §5 "always exits 0" blocked by Cases 5-7 | Yes: §4.1 reason tokens | **PROVEN** |
| AT-1057 | §0.Z.9.1 | `plans/pr_gate.sh:830-835` — checks_failing + checks_pending for all check-runs | `plans/tests/test_pr_gate.sh:217-226` (Cases 5-7) + Case 1 (all-green) | Yes: failing check-runs cause reason token; pending causes checks_pending | Yes: pending fail-closed | §5 "only checks build" — gate evaluates ALL check-runs uniformly | Yes: §4.1 reason tokens | **PROVEN** |

---

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | `gh` CLI available | Mock not found → clear error | TESTED: pr_gate.sh:71 `need gh` |
| 2 | `gh pr view --json` stable schema | Killed: external dependency | KILLED |
| 3 | Branch auto-detection | No-PR case → clear error | TESTED: pr_gate.sh:302-308, Cases 0/0b/0c |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| §4.1: Reason token to stdout, exit 1 | (A) | Yes | pr_gate.sh:893, 905 |
| §4.2: Bot detection by user type Bot | (A) | Yes | pr_gate.sh:668 — type:Bot + copilot login |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Always exits 0 | Yes | Cases 5-7 use expect_fail | Yes |
| Only checks build, not test | Yes | Gate evaluates ALL check-runs uniformly | Yes |

---

## D) DESIGN RISK NOTES

1. All failure modes produce deterministic reason tokens. Good.
2. Fail-closed on missing data (gh, jq, PR payload). Good.
3. Self-deadlock avoidance via --ignore-check-run-regex. Good.
4. **PRD_FIX**: enforcement_point "DispatcherChokepoint" is wrong for a CI script.
5. Comprehensive: 29 test cases.

---

## E) REMEDIATION PLAN

```
[PRD_FIX]   GAP-013-1: enforcement_point "DispatcherChokepoint" → empty or "CIGate". P2.
[INFO]      All enforcement points verified. No code fixes needed.
[INFO]      29 fixture test cases provide thorough coverage.
```

---

## F) SCOPE CHECK

All scope.touch files exist and are correctly wired. No scope drift.

---

READY FOR SELF_REVIEW

---
---

# EXPIRY BATCH SUMMARY

| Story | ATs | Verdicts | Blockers |
|-------|-----|----------|----------|
| S1-012 | 7 ATs | All **WEAK_PROOF** | **GAP-012-1 (P0)**: common/mod.rs compile error |
| S1-013 | AT-1056, AT-1057 | PROVEN, PROVEN | None |
