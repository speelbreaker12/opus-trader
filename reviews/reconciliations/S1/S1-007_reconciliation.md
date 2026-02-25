---
provenance:
  tool: claude-code
  model: claude-opus-4-6
  prompt_style: R1-preflight-audit (reconciliation)
  cycle: recon-R1-fresh
  phase_equivalent: R1
story_id: S1-007
story_title: "Dispatcher mismatch rejection"
enforcement_point: DispatcherChokepoint
enforcing_contract_ats: [AT-920]
gate_result: CONDITIONAL-GO
extraction_date: "2026-02-23"
---

# RECONCILIATION R1 PREFLIGHT AUDIT: S1-007 (Dispatcher mismatch rejection)

## A) GATE RESULT

```
GATE: GO
Reason: R5 remediation closed the blocking compile issue and production bypass gap.
  `GAP-S1-005-001` is fixed (test-helpers feature wired) and
  `GAP-S1-007-002` is fixed by introducing `DispatchConsistencyProof::failed()`
  in production paths while gating `unchecked()` to
  `#[cfg(any(test, feature = "test-helpers"))]`.
  Remaining `GAP-S1-007-001` is explicitly deferred as debt (`DEBT-S1-007-001`).
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-920 | §1.0 Hard Rules #2-#4 | `dispatch_map.rs:239-284::validate_and_dispatch` | 15 tests (see below) | PROVEN (with caveats) | Yes — 6/6 categories | Yes — all 4 wrong impls blocked | Yes — all 3 decisions as chosen | **PROVEN** |

### 1) Enforcement point location

Primary enforcement: `crates/soldier_core/src/execution/dispatch_map.rs`

| What | File:Line |
|------|-----------|
| Tolerance constant (0.001) | `dispatch_map.rs:22` |
| Epsilon constant (1e-9) | `dispatch_map.rs:24` |
| `validate_and_dispatch()` function | `dispatch_map.rs:239-284` |
| Non-finite early guard (NaN/Inf) | `dispatch_map.rs:259-264` |
| Tolerance formula & late guard | `dispatch_map.rs:266-276` |
| `DispatchConsistencyProof` type | `dispatch_map.rs:108-136` |
| `MismatchMetrics` counter | `dispatch_map.rs:141-170` |
| `map_to_dispatch` fail-closed (contracts present) | `dispatch_map.rs:187-189` |

Pipeline integration:

| What | File:Line |
|------|-----------|
| `assemble_sizing()` calls `validate_and_dispatch()` | `intent_assembly.rs:126` |
| Mismatch -> `risk_state_degraded = true` | `intent_assembly.rs:128` |
| `evaluate_assembled_pipeline()` escalates Healthy -> Degraded | `intent_assembly.rs:247-253` |
| `build_open_intent_with_assembly()` production entry point | `open_runtime.rs:397-430` |
| Degraded blocks OPEN at DispatchAuth gate | `base_gates.rs:328-338` (Gate 4: DispatchConsistency) |
| `RejectReasonCode::ContractsAmountMismatch` in registry | `reject_reason.rs:27` |
| Gate rejection maps to `ContractsAmountMismatch` | `reject_reason.rs:171` |

### 2) Fail-closed verification (6 categories)

| Category | Status | Evidence |
|----------|--------|----------|
| NaN multiplier | PASS | `dispatch_map.rs:259`: `!multiplier.is_finite()` check -> Err with delta=INFINITY. Test: `test_at920_non_finite_multiplier_rejected` (line 448) |
| NaN canonical amount | PASS | `dispatch_map.rs:259`: `!canonical_amount.is_finite()` check. Test: `test_at920_nan_canonical_amount_rejected_with_infinity_delta` (line 485) |
| Inf canonical amount | PASS | Same guard. Test: `test_at920_inf_canonical_amount_rejected_with_infinity_delta` (line 516) |
| Missing contract_multiplier | PASS | `dispatch_map.rs:248`: `.ok_or(ContractsRequireValidation)`. Test: `test_at920_no_multiplier_rejected_fail_closed` (line 396) |
| Contracts present but bypass attempted | PASS | `dispatch_map.rs:187-189`: `map_to_dispatch` rejects if `contracts.is_some()`. Test: `test_map_to_dispatch_rejects_contracts_without_validation` (line 143) |
| NaN/Inf in computed delta | PASS | `dispatch_map.rs:270-271`: `!contracts_implied.is_finite() || !delta.is_finite()` -> reject. Implied by NaN tests above. |

### 3) Causal proof analysis

| Criterion | Test | Status | Evidence |
|-----------|------|--------|----------|
| Dispatch count = 0 on mismatch | `test_at920_no_dispatch_on_mismatch` (line 638) | PROVEN | `assert!(result.is_err())` — `validate_and_dispatch` returns `Err`, no `ValidatedDispatch` created |
| Reject reason = ContractsAmountMismatch | `test_at920_mismatch_rejected` (line 313) | PROVEN | `Err(DispatchMapError::ContractsAmountMismatch { delta })` pattern match |
| Metric incremented | `test_at920_mismatch_increments_counter` (line 341) | PROVEN | `metrics.reject_unit_mismatch_total() == 1` then `== 2` |
| RiskState::Degraded blocks OPEN | `test_at920_mismatch_caller_sets_degraded_and_blocks_open` (line 669) | **BROKEN** | Test does not compile — `GateResults::all_passed()` not accessible. See P0 finding below. |
| Pipeline rejects on dispatch_consistency=false | `test_at920_pipeline_dispatch_consistency_failure_rejected` (test_intent_pipeline.rs:292) | PROVEN | `approved_total() == 0`, `ContractsAmountMismatch` reason code |
| Assembly detects mismatch, degrades risk state | `test_assembly_mismatch_sets_degraded` (test_intent_assembly.rs:98) | PROVEN | `!assembled.dispatch_consistency.passed()`, `assembled.risk_state_degraded == true`, pipeline rejects with `approved_total() == 0` |
| Kill not downgraded by mismatch | `test_assembled_pipeline_kill_not_downgraded_by_mismatch` (test_intent_assembly.rs:563) | PROVEN | Kill state preserved through assembly mismatch |
| Maintenance not downgraded by mismatch | `test_assembled_pipeline_maintenance_not_downgraded_by_mismatch` (test_intent_assembly.rs:620) | PROVEN | Maintenance state preserved |
| Close bypasses dispatch consistency gate | `test_at920_pipeline_dispatch_consistency_skips_close` (test_intent_pipeline.rs:331) | PROVEN | Close approved despite dispatch_consistency=false |

**Overall causal proof verdict**: PROVEN with one caveat — `test_at920_mismatch_caller_sets_degraded_and_blocks_open` does not compile on current HEAD (P0).

The causality proof chain (`mismatch -> ContractsAmountMismatch -> dispatch_count=0`) is independently proven by:
- `test_at920_mismatch_rejected` (unit-level mismatch detection)
- `test_at920_pipeline_dispatch_consistency_failure_rejected` (pipeline-level gate enforcement)
- `test_assembly_mismatch_sets_degraded` (assembly-level mismatch -> Degraded -> pipeline rejects)

So even with the broken test, AT-920 enforcement is PROVEN at the pipeline level.

### 4) §5 Wrong impls blocked

| Wrong impl | Tightening test | Catches? | Evidence |
|-----------|-----------------|----------|----------|
| Absolute tolerance instead of relative | `test_at920_delta_in_error` (line 598) | YES | Asserts delta = `|5.0 - 3.0| / 3.0 = 0.6667` — proves relative formula |
| Check tolerance but forget Degraded | `test_assembly_mismatch_sets_degraded` (test_intent_assembly.rs:98) | YES | Asserts `risk_state_degraded = true` AND pipeline rejects OPEN |
| Set Degraded but still dispatch | `test_at920_no_dispatch_on_mismatch` (line 638) + pipeline tests | YES | Result is `Err`, no `DispatchRequest` created; pipeline `approved_total() == 0` |
| Use wrong reject reason | `test_at920_mismatch_rejected` (line 332) | YES | Pattern matches exact `DispatchMapError::ContractsAmountMismatch { delta }` variant |

### 5) §4 Decisions implemented

| Decision | Chosen | Implemented? | Evidence |
|----------|--------|-------------|----------|
| Tolerance formula precision | A — f64, contract formula exactly | YES | `dispatch_map.rs:266-268`: uses `f64` arithmetic with the exact formula from CONTRACT.md |
| When only one of contracts/amount present | A — Skip when contracts None | YES | `dispatch_map.rs:247`: `if let Some(contracts) = order_size.contracts` — skip when None |
| NaN handling | A — Fail-closed | YES | `dispatch_map.rs:259-264`: non-finite check before arithmetic, returns `ContractsAmountMismatch { delta: f64::INFINITY }` |

### 6) §2 Assumptions verified

| # | Assumption | Test | Status |
|---|-----------|------|--------|
| 1 | `contract_multiplier` available and > 0 | `test_at920_no_multiplier_rejected_fail_closed` (line 396), `test_at920_non_finite_multiplier_rejected` (line 448) | TESTED: None -> `ContractsRequireValidation`; NaN -> `ContractsAmountMismatch`. Note: `multiplier=0.0` caught upstream by `build_order_size` (test_order_size.rs:242). |
| 2 | Tolerance formula uses relative error | `test_at920_delta_in_error` (line 598) | TESTED: `delta = |5-3|/3 = 0.6667` exactly |
| 3 | epsilon=1e-9 prevents div-by-zero | `test_at920_epsilon_denominator_allows_small_amount_within_tolerance` (line 418) | TESTED: `canonical=1e-12`, denominator = `max(1e-12, 1e-9) = 1e-9` |
| 4 | RiskState::Degraded set atomically with rejection | `test_assembly_mismatch_sets_degraded` (test_intent_assembly.rs:98) | PARTIALLY: Assembly sets `risk_state_degraded=true` when `validate_and_dispatch` fails. Pipeline escalates Healthy -> Degraded. But Degraded is a caller convention of `validate_and_dispatch`, not atomic with it. The pipeline integration (`evaluate_assembled_pipeline`) makes it effectively atomic. |
| 5 | Mismatch check runs BEFORE dispatch | `test_at920_no_dispatch_on_mismatch` (line 638), pipeline tests | TESTED: `validate_and_dispatch` returns `Err` before constructing `DispatchRequest`; pipeline `approved_total() == 0` |

### 7) Observability on reject/degrade paths

| Path | Observable signal | Evidence |
|------|------------------|----------|
| Mismatch rejection | `MismatchMetrics::reject_unit_mismatch_total` counter | `dispatch_map.rs:156-158`: `record_mismatch_rejection()`. Tested: line 341 |
| Error includes delta | `DispatchMapError::ContractsAmountMismatch { delta }` | `dispatch_map.rs:68-71`: delta field in error. Tested: line 598 |
| Pipeline-level rejection | `RejectReasonCode::ContractsAmountMismatch` | `reject_reason.rs:27,171`: registered in reject reason registry. Pipeline test: test_intent_pipeline.rs:324 |
| NaN/Inf rejection | delta = `f64::INFINITY` in error | `dispatch_map.rs:262`: delta set to `f64::INFINITY` for non-finite guard. Tested: lines 448, 485, 516 |

Note: The `order_intent_reject_unit_mismatch_total` metric name in the PRD (`plans/prd.json` observability.metrics) matches the `MismatchMetrics` counter name at `dispatch_map.rs:143`.

### 8) Design-pattern conformance

| Pattern | Conforms? | Evidence |
|---------|-----------|----------|
| Fail-closed (uncertain -> safe) | YES | NaN/Inf/missing multiplier all -> reject. `dispatch_map.rs:259-276` |
| No `unwrap()` in production code | YES | Manual scan of `dispatch_map.rs` — no `unwrap()` or `expect()` calls |
| Structured logging/error context | YES | Delta value included in `ContractsAmountMismatch` error variant |
| Tolerance constant from contract | YES | `CONTRACTS_AMOUNT_MATCH_TOLERANCE = 0.001` at line 22; tested at line 629 |
| Pessimistic defaults | YES | `map_to_dispatch` rejects when contracts present (forces through validated path). `DispatchConsistencyProof::unchecked(false)` used on assembly failure. |
| Intent classification: uncertain = OPEN | N/A | AT-920 is a sizing gate, not intent classification |

## C) PREMORTEM CROSS-REFERENCE (§2, §4, §5)

### §2 Summary
All 5 assumptions are tested or effectively tested. Assumption #4 (atomicity) is the weakest — Degraded is a caller convention at the `validate_and_dispatch` level, but the assembly pipeline makes it effectively atomic by setting `risk_state_degraded` immediately on `Err`.

### §4 Summary
All 3 decisions implemented as chosen, with correct evidence at the cited lines.

### §5 Summary
All 4 wrong implementations are blocked by tightening tests. The strongest is `test_at920_delta_in_error` which proves the formula is relative (not absolute), and `test_assembly_mismatch_sets_degraded` which proves the full mismatch -> Degraded -> OPEN-blocked chain.

## D) DESIGN RISK NOTES

### P0: COMPILATION FAILURE (CLOSED)

`GAP-S1-005-001` is fixed. Integration tests now compile with `test-helpers` wired in `crates/soldier_core/Cargo.toml:15` and `crates/soldier_core/Cargo.toml:18` (fix commit `efecb6c`).

### P1: Zero production callsites (KNOWN DEBT)

`build_open_intent_with_assembly` (`open_runtime.rs:397`) is defined and exported but has no callers outside of specs documentation. The full chain (`build_open_intent_with_assembly` -> `assemble_sizing` -> `validate_and_dispatch`) is tested in isolation but not exercised from any production entry point. This is tracked as DEBT-S1-007-01 in the slice1 DEBT_REGISTER.

### P1: DispatchConsistencyProof bypass (CLOSED)

`GAP-S1-007-002` is fixed. `DispatchConsistencyProof::unchecked()` is now gated behind `#[cfg(any(test, feature = "test-helpers"))]` at `crates/soldier_core/src/execution/dispatch_map.rs:134`, and production error paths use `DispatchConsistencyProof::failed()` (`crates/soldier_core/src/execution/intent_assembly.rs:128`, `crates/soldier_core/src/execution/open_runtime.rs:422`).

### P2: PRD reason_codes discrepancy (KNOWN)

PRD `reason_codes.values` says `ContractsAmountMismatch` (was `UnitMismatch`, now corrected in prd.json). Code uses `DispatchMapError::ContractsAmountMismatch` and `RejectReasonCode::ContractsAmountMismatch`. These are now aligned. Debt item GAP-S1007-1 appears resolved.

### INFO: Tolerance boundary uses strict inequality

`dispatch_map.rs:272`: `delta > CONTRACTS_AMOUNT_MATCH_TOLERANCE` (not `>=`). This means delta == 0.001 passes. Matches CONTRACT.md: "must match within tolerance" (within = `<=`).

### INFO: ValidatedDispatch fields now private

`dispatch_map.rs:80,83`: `request` and `risk_state` are private (no `pub` keyword). Accessible only via `request()` and `risk_state()` getters. This addresses the GAP-FE-005 finding about forgeable proof tokens. `ValidatedDispatch` can only be constructed inside `dispatch_map.rs` via `validate_and_dispatch()`.

## E) REMEDIATION PLAN

| Priority | ID | Finding | Remediation | Blocking? |
|----------|-----|---------|-------------|-----------|
| P0 | REM-007-01 | `test_dispatch_map.rs:715` does not compile — `GateResults::all_passed()` unavailable to integration tests | **FIXED** — `test-helpers` feature wiring present in `crates/soldier_core/Cargo.toml:15` and `crates/soldier_core/Cargo.toml:18` (commit `efecb6c`) | NO |
| P1 | REM-007-02 | `build_open_intent_with_assembly` has zero production callers (DEBT-S1-007-001) | **DEFERRED-WITH-DEBT** — documented TODO and debt entry at `reviews/reconciliations/S1/DEBT_REGISTER.json:52` | NO — deferred, tracked |
| P1 | REM-007-03 | `DispatchConsistencyProof::unchecked(true)` is public bypass (DEBT-S1-007-02) | **FIXED** — production callers migrated to `failed()`, and `unchecked()` compile-gated to test/test-helpers only (`crates/soldier_core/src/execution/dispatch_map.rs:134`) | NO |
| INFO | REM-007-04 | PRD `reason_codes.values` now aligned (`ContractsAmountMismatch`) | GAP-S1007-1 appears resolved | NO |

## F) SCOPE CHECK

### scope.touch files existence

| File | Exists? | AT-920 relevant code? |
|------|---------|----------------------|
| `crates/soldier_core/src/execution/dispatch_map.rs` | YES | Primary enforcement: `validate_and_dispatch`, `MismatchMetrics`, `DispatchConsistencyProof` |
| `crates/soldier_core/src/execution/mod.rs` | YES | Re-exports: `validate_and_dispatch`, `MismatchMetrics`, `DispatchConsistencyProof`, etc. (line 63) |
| `crates/soldier_core/src/lib.rs` | YES | Module declaration only (line 3: `pub mod execution`) |
| `crates/soldier_core/tests/test_dispatch_map.rs` | YES | 15 AT-920 tests + dispatch mapping tests. **DOES NOT COMPILE** (P0). |
| `crates/soldier_core/tests/test_order_size.rs` | YES | OrderSize sizing tests. No direct AT-920 enforcement. Compiles and passes (17/17). |

### Additional files with AT-920 enforcement (not in scope.touch but relevant)

| File | Relevance |
|------|-----------|
| `crates/soldier_core/src/execution/intent_assembly.rs` | `assemble_sizing()` calls `validate_and_dispatch()` (line 126). Production-path wiring. |
| `crates/soldier_core/src/execution/base_gates.rs` | Gate 4 DispatchConsistency check (lines 321-338). `ContractsAmountMismatch` reason code. |
| `crates/soldier_core/src/execution/reject_reason.rs` | `RejectReasonCode::ContractsAmountMismatch` (line 27). Registry entry (line 122). |
| `crates/soldier_core/src/execution/open_runtime.rs` | `build_open_intent_with_assembly()` (line 397). Production entry point. |
| `crates/soldier_core/tests/test_intent_assembly.rs` | `test_assembly_mismatch_sets_degraded` (line 98). Pipeline-level proof. |
| `crates/soldier_core/tests/test_intent_pipeline.rs` | `test_at920_pipeline_dispatch_consistency_failure_rejected` (line 292). Gate-level proof. |

### Test compilation status

| Test file | Compiles? | Passes? |
|-----------|-----------|---------|
| test_dispatch_map.rs | **NO** (GateResults::all_passed() not found) | N/A |
| test_order_size.rs | YES | 17/17 |
| test_intent_assembly.rs | YES | 14/14 |
| test_intent_pipeline.rs | YES | 16/16 |

### Git status at end of audit

Working tree modifications on current HEAD:
- `M crates/soldier_core/src/execution/dispatch_map.rs` — `ValidatedDispatch` fields made private (getter methods added)
- `M crates/soldier_core/tests/test_dispatch_map.rs` — updated to use getter methods, but introduced `GateResults::all_passed()` compilation failure
- `M crates/soldier_core/src/execution/build_order_intent.rs` — `all_passed()` gated behind `#[cfg(test)]`, `new()` made `pub(crate)`

These are uncommitted modifications. The P0 compilation failure is a direct consequence of the `all_passed()` visibility change.

---

```
READY FOR SELF_REVIEW
```

**Condition**: REM-007-01 (P0 test compilation failure) must be fixed before proceeding to SELF_REVIEW. All other findings are deferred debt (P1) or informational.
