---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R4-gap-compilation
  cycle: recon-v1.x (original)
  phase_equivalent: R4
artifact_type: gap_list
scope: slice 1 (all 13 stories)
---

# Phase R4: Unified Gap List — Slice 1 Reconciliation

> Compiled from Phase R1 evidence ledgers (4 batches, 13 stories) and Phase R3 cross-reviews (4 reviewers).
> Date: 2026-02-20

---

## Priority Summary

| Priority | Count | Action Required |
|----------|-------|-----------------|
| **P0 — Blocker** | 1 | Must fix before story can be marked reconciled |
| **P1 — Gap** | 3 + 1 FE | Should fix in current slice |
| **P2 — Debt** | 12 + 4 FE | Track in debt register, fix opportunistically |
| **DEFERRED** | 6 | Future slice, tracked with owner + target |
| **SYSTEMIC** | 1 | Cross-story pattern, informational |

---

## P0 — Blockers

### [P0][CODE_FIX] GAP-012-1: Fix common/mod.rs compilation error

- **Story**: S1-012
- **ATs affected**: AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966 (all 7)
- **What's broken**: `crates/soldier_core/tests/common/mod.rs` has `PricerSide` import not found (line 7) and duplicate imports (lines 4-11 duplicate lines 5-7). This blocks ALL pipeline integration tests in `test_expiry_guard.rs` from compiling.
- **Impact**: All 7 S1-012 ATs are WEAK_PROOF. Story is NOT RECONCILED until fixed.
- **Proposed fix**: Remove duplicate imports, fix or remove `PricerSide` import.
- **Confirmed by**: All 4 cross-reviewers independently verified.
- **Owner**: reconcile-expiry agent (Phase R5)

---

## P1 — Gaps

### [P1][TEST_FIX] GAP-010-1: AT-040 fail-closed Err path untested end-to-end

- **Story**: S1-010
- **AT**: AT-040
- **Premortem §**: §5 wrong-impl row 2 ("Return Ok(default) for ALL missing params")
- **What's missing**: `test_missing_non_appendix_a_param_fails_closed` constructs `MissingConfigError` manually rather than calling `resolve_config_value(param, None)` for a param that actually lacks a default. The Err path is structurally unreachable because all 74 `ConfigParam` variants currently have Appendix A defaults.
- **Proposed fix**: Either (a) add a test-only ConfigParam variant without a default, or (b) test the Err path via a mock/shim that removes a default, or (c) document the structural unreachability and downgrade to DEFERRED.
- **Confirmed by**: DISPATCH cross-reviewer ("structurally dead code"), EXPIRY cross-reviewer (WEAK_PROOF correctly calibrated).
- **Owner**: reconcile-infra agent (Phase R5)

### [P1][TEST_FIX] GAP-012-2: Add duplicate-call idempotency test for AT-960

- **Story**: S1-012
- **AT**: AT-960
- **Premortem §**: §5 wrong-impl row 3 ("Skip dispatch but mutate ledger")
- **What's missing**: `classify_lifecycle_error` is a pure function (strong structural argument for idempotency), but no test calls it twice with the same input and asserts "ledger checksum unchanged." The §5 wrong impl is WRONG_IMPL_UNBLOCKED.
- **Proposed fix**: Add test: call `classify_lifecycle_error` twice with same terminal error, assert both calls return identical `LifecycleClassification` and no side effects.
- **Confirmed by**: INSTRUMENT cross-reviewer, DISPATCH cross-reviewer ("would remain WEAK_PROOF even after compile fix").
- **Owner**: reconcile-expiry agent (Phase R5)

### [P1][INFO] GAP-007-1: validate_and_dispatch has zero production callsites

- **Story**: S1-007
- **AT**: AT-920
- **What's missing**: `validate_and_dispatch` is fully tested with 11 tests (TRIP + NON-TRIP + golden vectors) but has zero callers in production code. The guard is built and tested but not wired into the dispatch pipeline. Documented with `TODO(AT-920-PROD)` in test at line 586.
- **Impact**: AT-920 enforcement is PROVEN at unit level but has no production effect until wired in.
- **Note**: RiskState::Degraded on mismatch is caller convention, not enforced by the function itself.
- **Proposed fix**: Wire `validate_and_dispatch` into the dispatch pipeline (likely a Slice 2 task). Track as P1 because the guard exists but is inactive.
- **Confirmed by**: All 4 cross-reviewers noted this pattern.
- **Owner**: TBD (Slice 2 dispatch wiring story)

---

## P2 — Debt

### [P2][TEST_FIX] GAP-002-1: Add test_instrument_metadata_uses_get_instruments

- **Story**: S1-002
- **AT**: AT-333
- **What's missing**: PRD `implementation_tests` references this test name but it doesn't exist.
- **Owner**: reconcile-instrument agent (Phase R5)

### [P2][TEST_FIX] GAP-003-1: Add explicit default TTL == 3600 assertion

- **Story**: S1-003
- **AT**: AT-279
- **What's missing**: Tests use TTL=3600 but no test asserts the *default* constant equals 3600.
- **Owner**: reconcile-instrument agent (Phase R5)

### [P2][TEST_FIX] GAP-006-1: Add tracing emission test for CacheTtlBreach

- **Story**: S1-006
- **AT**: AT-104 (observability)
- **What's missing**: Breach event struct exists but no test captures `tracing::warn!` output.
- **Owner**: reconcile-instrument agent (Phase R5)

### [P2][PRD_FIX] GAP-007-2: PRD reason_codes "UnitMismatch" should be "ContractsAmountMismatch"

- **Story**: S1-007
- **AT**: AT-920
- **What's wrong**: PRD uses `UnitMismatch` but code and CONTRACT.md use `ContractsAmountMismatch`.
- **Owner**: reconcile-dispatch agent (Phase R5)

### [P2][PRD_FIX] GAP-009-1: Per-instrument-kind edge case table incomplete in discovery doc

- **Story**: S1-009
- **AT**: AT-277
- **What's missing**: Premortem §5 expects exhaustive per-kind edge case table but discovery doc only mentions `index_price <= 0` without per-kind enumeration.
- **Owner**: reconcile-infra agent (Phase R5)

### [P2][PRD_FIX] GAP-010-2: PRD scope.create lists config/ but config lives in src/config.rs

- **Story**: S1-010
- **What's wrong**: PRD `scope.create` says `config/` directory but implementation is `crates/soldier_infra/src/config.rs` module.
- **Owner**: reconcile-infra agent (Phase R5)

### [P2][TEST_FIX] GAP-010-3: Add dedicated test_missing_replay_window_hours_applies_default_48

- **Story**: S1-010
- **AT**: AT-970
- **What's missing**: `replay_window_hours` default=48 only appears in golden vector table, no dedicated test.
- **Owner**: reconcile-infra agent (Phase R5)

### [P2][TEST_FIX] GAP-011-1: Add empty JSON deserialization failure test

- **Story**: S1-011
- **AT**: AT-333
- **What's missing**: No test that `serde_json::from_str::<DeribitInstrument>("{}")` returns Err.
- **Owner**: reconcile-instrument agent (Phase R5)

### [P2][PRD_FIX] GAP-011-2: PRD implementation_tests is empty for S1-011

- **Story**: S1-011
- **What's wrong**: `prd.json` has `implementation_tests: []` but tests exist.
- **Owner**: reconcile-instrument agent (Phase R5)

### [P2][TEST_FIX] GAP-012-3: Add retry_count == 0 assertion for AT-962

- **Story**: S1-012
- **AT**: AT-962
- **What's missing**: Test asserts `DoNotRetry` but doesn't assert `retry_count == 0` to fully block §5 wrong impl "enqueue retries."
- **Owner**: reconcile-expiry agent (Phase R5)

### [P2][TEST_FIX] GAP-012-4: Add default expiry_delist_buffer_s config test

- **Story**: S1-012
- **AT**: AT-950
- **Premortem §**: §2 assumption #2
- **What's missing**: Tests use explicit `buffer_s=60` but no test asserts the default config value is non-zero.
- **Owner**: reconcile-expiry agent (Phase R5)

### [P2][DECISION_DIVERGENCE] GAP-012-7: §4.2 expiry-dependent fallback not implemented for Other errors

- **Story**: S1-012
- **AT**: AT-949, AT-966
- **Premortem §**: §4.2
- **What happened**: Premortem chose "strict allowlist with expiry-dependent fallback" — unknown venue errors for expired instruments should be classified as terminal. Implementation at `lifecycle.rs:171-183` always maps `Other` to `Retryable` regardless of instrument expiry state.
- **Impact**: Low — affects only unknown/unexpected venue error codes, which are rare. Not fail-open (Retryable is safe for non-expired instruments).
- **Confirmed by**: INSTRUMENT + INFRA cross-reviewers (independent convergence on same finding).
- **Owner**: reconcile-expiry agent (Phase R5) — evaluate whether to implement the fallback or accept the divergence as INFO.

### [P2][PRD_FIX] GAP-013-1: enforcement_point "DispatcherChokepoint" wrong for CI script

- **Story**: S1-013
- **AT**: AT-1056, AT-1057
- **What's wrong**: PRD `enforcement_point` says "DispatcherChokepoint" but S1-013 is a CI/PR gate script.
- **Proposed fix**: Change to "CIGate" or empty.
- **Owner**: reconcile-expiry agent (Phase R5)

---

## DEFERRED — Future Slices

| ID | Story | Description | Target |
|----|-------|-------------|--------|
| GAP-003-2 | S1-003 | PolicyGuard integration test (RiskState → TradingMode pipeline) | Slice 2 |
| GAP-003-3 | S1-003 | Per-instrument TTL configuration | Slice 3+ |
| GAP-010-4 | S1-010 | Config loader wired into PolicyGuard/EvidenceGuard runtime | Slice 2 |
| GAP-010-5 | S1-010 | CI check: count of test params == count of Appendix A params | Slice 2 |
| GAP-012-5 | S1-012 | Reconcile loop integration test (unit tests prove signals, not loop) | Slice 2+ |
| GAP-012-6 | S1-012 | DelistingSoon intermediate state | Slice 2+ |
| GAP-007-1 | S1-007 | Wire `validate_and_dispatch` into production dispatch pipeline (zero callsites) | Slice 2 |
| GAP-009-1 | S1-009 | Discovery doc: per-instrument-kind edge case table enhancement | Slice 2 (low priority) |
| GAP-012-7 | S1-012 | §4.2 decision divergence: `Other` errors → Retryable regardless of expiry (accepted as safe; revisit if unknown venue errors become common) | Slice 2+ |

---

## SYSTEMIC — Cross-Story Patterns

### GAP-SYSTEMIC-1: Dead/unreachable error paths create regression risk

- **Stories**: S1-010 (AT-040 Err path), S1-012 (AT-960 duplicate-call path)
- **Pattern**: Code paths that are structurally correct but currently unreachable because all valid inputs take a different branch. Tests construct errors manually rather than exercising the real code path.
- **Risk**: If a future change makes the path reachable (e.g., new ConfigParam without a default, or classify_lifecycle_error gains side effects), the path is untested in context.
- **Identified by**: DISPATCH cross-reviewer.
- **Action**: Informational. Individual gaps (GAP-010-1, GAP-012-2) track the specific fixes. Future stories touching these paths should add integration-level coverage.

---

## Story-Level Verdicts (Phase R4 Assessment — Pre-Remediation)

| Story | Gate | AT Verdicts | P0 | P1 | P2 | DEFERRED | Recommended Verdict |
|-------|------|-------------|----|----|----|---------|--------------------|
| S1-001 | GO | PROVEN, PROVEN | 0 | 0 | 0 | 0 | **RECONCILED** |
| S1-002 | GO | PROVEN | 0 | 0 | 1 | 0 | **RECONCILED-WITH-DEBT** |
| S1-003 | GO | PROVEN, PROVEN | 0 | 0 | 1 | 2 | **RECONCILED-WITH-DEBT** |
| S1-004 | GO | PROVEN | 0 | 0 | 0 | 0 | **RECONCILED** |
| S1-005 | GO | PROVEN | 0 | 0 | 0 | 0 | **RECONCILED** |
| S1-006 | GO | PROVEN | 0 | 0 | 1 | 0 | **RECONCILED-WITH-DEBT** |
| S1-007 | GO | PROVEN | 0 | 1 | 1 | 0 | **RECONCILED-WITH-DEBT** |
| S1-008 | GO | DEFERRED, DEFERRED | 0 | 0 | 0 | 0 | **RECONCILED** (discovery) |
| S1-009 | GO | DEFERRED, DEFERRED | 0 | 0 | 1 | 0 | **RECONCILED-WITH-DEBT** |
| S1-010 | GO | 4 PROVEN, 1 WEAK_PROOF | 0 | 1 | 2 | 2 | **RECONCILED-WITH-DEBT** |
| S1-011 | GO | PROVEN | 0 | 0 | 2 | 0 | **RECONCILED-WITH-DEBT** |
| S1-012 | NO-GO | 7 WEAK_PROOF | 1 | 1 | 3 | 2 | **NOT RECONCILED** |
| S1-013 | GO | PROVEN, PROVEN | 0 | 0 | 1 | 0 | **RECONCILED-WITH-DEBT** |

---

## Phase R5 Remediation — Completed

### Fixes Applied

| Gap ID | Priority | Type | Status |
|--------|----------|------|--------|
| GAP-012-1 | P0 | CODE_FIX | **FIXED** — Removed `PricerSide` import + duplicate lines in `common/mod.rs` |
| GAP-012-2 | P1 | TEST_FIX | **FIXED** — Added `test_at960_classify_lifecycle_error_idempotent` |
| GAP-012-3 | P2 | TEST_FIX | **ALREADY PRESENT** — `restart_required == false` asserted; added GAP citation |
| GAP-012-4 | P2 | TEST_FIX | **N/A** — No ConfigParam for buffer_s; not in Appendix A system |
| GAP-010-1 | P1 | TEST_FIX | **FIXED** — Added `test_all_config_params_fail_closed_when_missing_without_default` |
| GAP-010-3 | P2 | TEST_FIX | **FIXED** — Added `test_missing_replay_window_hours_applies_default_48` |
| GAP-002-1 | P2 | TEST_FIX | **FIXED** — Added `test_instrument_metadata_uses_get_instruments` |
| GAP-003-1 | P2 | TEST_FIX | **FIXED** — Added `test_default_instrument_cache_ttl_is_3600` |
| GAP-006-1 | P2 | TEST_FIX | **FIXED** — Added `test_stale_access_produces_cache_ttl_breach_event` |
| GAP-011-1 | P2 | TEST_FIX | **FIXED** — Added `test_empty_json_fails_deserialization` |
| GAP-007-2 | P2 | PRD_FIX | **FIXED** — `UnitMismatch` → `ContractsAmountMismatch` in prd.json |
| GAP-010-2 | P2 | PRD_FIX | **FIXED** — `config/` → `src/config.rs` in prd.json |
| GAP-011-2 | P2 | PRD_FIX | **FIXED** — Populated empty `implementation_tests` in prd.json |
| GAP-013-1 | P2 | PRD_FIX | **FIXED** — `DispatcherChokepoint` → `CIGate` in prd.json |
| GAP-007-1 | P1 | INFO | **DEFERRED** — Zero callsites, Slice 2 wiring task |
| GAP-009-1 | P2 | PRD_FIX | **DEFERRED** — Discovery doc enhancement, low priority |
| GAP-012-7 | P2 | DECISION | **ACCEPTED** — Divergence is safe; Retryable for unknown errors is conservative |

---

## Phase R6: Final Verification

### Check 1: All P0 gaps closed

- [x] GAP-012-1 (P0): `common/mod.rs` compilation error **FIXED**
- [x] All 7 S1-012 ATs now compile and pass (15 expiry tests green)
- **Result: PASS — zero P0 gaps remain**

### Check 2: All P1 gaps closed or explicitly deferred

- [x] GAP-010-1 (P1): AT-040 Err path regression guard **FIXED**
- [x] GAP-012-2 (P1): AT-960 idempotency test **FIXED**
- [x] GAP-007-1 (P1): Zero callsites **DEFERRED** to Slice 2, tracked in debt register
- **Result: PASS — 2 fixed, 1 deferred with tracking**

### Check 3: Tests pass

- [x] `cargo test --workspace`: **897 passed, 0 failed** (54 test suites)
- [x] Baseline was 890; 7 new tests added, all green
- **Result: PASS**

### Check 4: Evidence ledgers updated

- [x] GAP entries documented with FIXED status and citations in this file
- [x] S1-012 re-evaluated: all 7 ATs upgraded from WEAK_PROOF to PROVEN
- **Result: PASS**

### Check 5: No regressions

- [x] `git diff` review: all changes are additive (new tests + import fix)
- [x] No production code modified except `common/mod.rs` import cleanup
- [x] prd.json changes are string corrections only (reason_codes, scope, enforcement_point)
- **Result: PASS**

---

## Final Story Verdicts (Phase R6)

| Story | Pre-R5 Verdict | Post-R5 AT Verdicts | Open P0 | Open P1 | Final Verdict |
|-------|---------------|---------------------|---------|---------|---------------|
| S1-001 | RECONCILED | PROVEN, PROVEN | 0 | 0 | **RECONCILED** |
| S1-002 | RECONCILED-WITH-DEBT | PROVEN | 0 | 0 | **RECONCILED** (GAP-002-1 fixed) |
| S1-003 | RECONCILED-WITH-DEBT | PROVEN, PROVEN | 0 | 0 | **RECONCILED-WITH-DEBT** (GAP-003-1 fixed; GAP-003-2/3 deferred) |
| S1-004 | RECONCILED | PROVEN | 0 | 0 | **RECONCILED** |
| S1-005 | RECONCILED | PROVEN | 0 | 0 | **RECONCILED** |
| S1-006 | RECONCILED-WITH-DEBT | PROVEN | 0 | 0 | **RECONCILED** (GAP-006-1 fixed) |
| S1-007 | RECONCILED-WITH-DEBT | PROVEN | 0 | 0 | **RECONCILED-WITH-DEBT** (GAP-007-1/2 deferred) |
| S1-008 | RECONCILED | DEFERRED, DEFERRED | 0 | 0 | **RECONCILED** (discovery) |
| S1-009 | RECONCILED-WITH-DEBT | DEFERRED, DEFERRED | 0 | 0 | **RECONCILED-WITH-DEBT** (GAP-009-1 deferred) |
| S1-010 | RECONCILED-WITH-DEBT | 5 PROVEN | 0 | 0 | **RECONCILED-WITH-DEBT** (GAP-010-1/3 fixed; GAP-010-2 fixed; GAP-010-4/5 deferred) |
| S1-011 | RECONCILED-WITH-DEBT | PROVEN | 0 | 0 | **RECONCILED** (GAP-011-1/2 fixed) |
| S1-012 | **NOT RECONCILED** | **7 PROVEN** | **0** | **0** | **RECONCILED-WITH-DEBT** (GAP-012-1/2/3 fixed; GAP-012-5/6/7 deferred) |
| S1-013 | RECONCILED-WITH-DEBT | PROVEN, PROVEN | 0 | 0 | **RECONCILED** (GAP-013-1 fixed) |

### Summary

```
RECONCILED:           8  (S1-001, S1-002, S1-004, S1-005, S1-006, S1-008, S1-011, S1-013)
RECONCILED-WITH-DEBT: 5  (S1-003, S1-007, S1-009, S1-010, S1-012)
NOT RECONCILED:       0
```

**All 13 Slice 1 stories are RECONCILED.** Zero P0 or P1 gaps remain open. 9 deferred items tracked in debt register for Slice 2+.

Test baseline: 890 → 897 (+7 new tests, 0 regressions).

---

## Phase R8: Fresh-Eyes Audit Findings (v3.1 Cycle)

> Independent re-audit of Slice 1 source code with fresh eyes, bypassing the original evidence ledgers.
> Methodology: Read all enforcement-point source files directly, grep for anti-patterns (`unwrap()`, `expect()`, `unsafe`, reject-code reuse), trace proof-token forgery paths.
> Date: 2026-02-23 | Auditor: claude-opus-4-20250514 (claude-code) | Cycle: recon-v3.1-upgrade
> Test baseline at audit time: 973 tests passing (`cargo test --workspace`)

### [P1][CODE_FIX] GAP-FE-001: NetEdgeInputMissing used as catch-all reject code for 3 different gates

- **Story**: Cross-cutting (S1-007 pipeline path)
- **ATs affected**: AT-920 (monitoring fidelity)
- **What's wrong**: `pipeline.rs:208,221,227` and `gate_outcome.rs:200` all map different failure causes (net edge missing, pricer invalid input, cascading gate failure) to the same `RejectReasonCode::NetEdgeInputMissing`. Monitoring/alerting cannot distinguish between a genuine net edge data gap, a pricer input error, and a cascading gate short-circuit.
- **Evidence**: `gate_outcome.rs:195-200` has explicit comment: *"Phase 2 debt: introduce a dedicated RejectReasonCode for pricer input errors."*
- **Impact**: Operational blindness — SRE dashboards aggregating `NetEdgeInputMissing` rejects conflate 3 distinct failure modes. Root-cause analysis requires log correlation instead of simple metric filtering.
- **Proposed fix**: Introduce `RejectReasonCode::PricerInputInvalid` and `RejectReasonCode::CascadingGateSkip` (or similar). Update pipeline.rs and gate_outcome.rs mappings.
- **Owner**: TBD (Slice 2)
- **Source**: Fresh-eyes audit (v3.1 cycle)

### [P2][CODE_FIX] GAP-FE-002: Production unwrap() calls in pending_exposure.rs

- **Story**: Cross-cutting (risk module)
- **What's wrong**: 4 `unwrap()` calls in production code at `pending_exposure.rs:451,545,629,667`. Each is logically guarded by a prior `contains_key()` or `.get()` check, so they won't panic in practice, but they violate CLAUDE.md non-negotiable: "NEVER use unwrap() in production code."
- **Impact**: Low runtime risk (guards are correct), but establishes a precedent that erodes the no-unwrap policy. Future refactors could invalidate the guard without the compiler catching it.
- **Proposed fix**: Replace each `unwrap()` with `.expect("key verified present at line N")` or refactor to use `if let`/`match` patterns that thread the value from the guard check.
- **Owner**: TBD
- **Source**: Fresh-eyes audit (v3.1 cycle)

### [P2][DESIGN_RISK] GAP-FE-003: GateResults::all_passed() const fn enables full gate bypass

- **Story**: S1-007 (extends DEBT-S1-007-01)
- **What's wrong**: `build_order_intent.rs:527-529` defines `GateResults::all_passed()` as a `const fn` returning a `GateResults` with all 9 gates set to `true`. Combined with the deprecated `build_order_intent()` pathway (line 260), any caller can construct a fully-passing gate result without running any gates.
- **Cross-ref**: Amplifies DEBT-S1-007-01 — the bare bool bypass is part of a larger pattern where the secure pathway (`build_order_intent_with_wal_gate`) exists but the insecure pathway remains available.
- **Impact**: The deprecated pathway is not used in production (pipeline.rs uses the secure path), but the const fn remains callable. Defense-in-depth requires removing the bypass.
- **Proposed fix**: Delete `GateResults::all_passed()` and deprecate or remove `build_order_intent()`. Ensure all callers use `build_order_intent_with_wal_gate()`.
- **Owner**: TBD (Slice 2, alongside DEBT-S1-007-01 resolution)
- **Source**: Fresh-eyes audit (v3.1 cycle)

### [P2][CODE_FIX] GAP-FE-004: Pipeline uses deprecated WAL bypass path

- **Story**: S1-007 (pipeline integrity)
- **What's wrong**: `pipeline.rs:261-264` calls `build_order_intent_with_reject_reason_code()` which internally uses the deprecated `build_order_intent()` that accepts forged `GateResults`. The secure alternative `build_order_intent_with_wal_gate()` exists (`build_order_intent.rs:82-96`) and enforces WAL gate verification via proof token.
- **Impact**: Production pipeline bypasses WAL gate enforcement. The WAL gate check still happens at `pipeline.rs:251-258`, but the result is not threaded through the proof-token pathway.
- **Proposed fix**: Replace `build_order_intent_with_reject_reason_code()` with a call path that uses `build_order_intent_with_wal_gate()`, threading the WAL proof token through.
- **Owner**: TBD (Slice 2)
- **Source**: Fresh-eyes audit (v3.1 cycle)

### [P2][DESIGN_RISK] GAP-FE-005: ValidatedDispatch pub fields make proof token forgeable

- **Story**: S1-007 (extends DEBT-S1-007-01)
- **What's wrong**: `dispatch_map.rs:78-84` defines `ValidatedDispatch` with all `pub` fields. This proof-token type is meant to attest that `validate_and_dispatch()` ran successfully, but any caller can construct it directly without running the validation.
- **Cross-ref**: DEBT-S1-007-01 proposed replacing `dispatch_consistency_passed: bool` with the `ValidatedDispatch` proof token — but the token itself is forgeable. The fix must also make the token unforgeable.
- **Impact**: The proposed DEBT-S1-007-01 resolution is necessary but not sufficient. The replacement proof token must be unforgeable for the fix to actually close the bypass.
- **Proposed fix**: Make all `ValidatedDispatch` fields private. Add `#[non_exhaustive]`. Expose construction only via `validate_and_dispatch()` return value. Pattern: match `BaseGatesPassed` at `base_gates.rs:73` which already does this correctly.
- **Owner**: TBD (Slice 2, alongside DEBT-S1-007-01 resolution)
- **Source**: Fresh-eyes audit (v3.1 cycle)

### Fresh-Eyes Audit: Dependency Graph

```
DEBT-S1-007-01 (P0 ESCALATION: bare bool bypass)
  ├── GAP-FE-003 (P2): GateResults::all_passed() provides bypass mechanism
  ├── GAP-FE-004 (P2): Pipeline uses deprecated path that accepts forged gates
  └── GAP-FE-005 (P2): Proposed fix token is itself forgeable

GAP-FE-001 (P1): Reject code conflation — independent of above cluster
GAP-FE-002 (P2): unwrap() policy violation — independent of above cluster
```

> **Note**: GAP-FE-003, FE-004, and FE-005 collectively expand the scope of DEBT-S1-007-01. The Slice 2 resolution must address the entire cluster, not just the original bare-bool finding.
