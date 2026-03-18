---
provenance:
  tool: claude-code
  model: claude-opus-4-6
  prompt_style: R1-preflight-audit (reconciliation)
  cycle: recon-R1
  phase_equivalent: R1-preflight
source: standalone audit (not extracted from batch)
story_id: S1-010
story_title: "S1.0 Appendix A config defaults"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (AT-040 WEAK_PROOF P1 + observability + A.7 table drift)
audit_date: "2026-02-23"
---

# R1 PREFLIGHT RECONCILIATION AUDIT: S1-010 (Appendix A config defaults)

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT YELLOW acknowledged. All 5 ATs have enforcement code.
  4 of 5 ATs PROVEN with causal tests. AT-040 WEAK_PROOF (structurally
  unreachable Err path; regression guard exists). Production wiring via
  bootstrap_full() confirmed. Debt items are deferred to Slice 2+ with
  clear owners.
```

**R5 remediation update (2026-02-24):**
- `GAP-S1-010-001` remains intentionally **DEFERRED-WITH-DEBT** and is now explicitly recorded as `DEBT-S1-010-001` in `reviews/reconciliations/S1/DEBT_REGISTER.json:41`.
- R5 notes and traceability are captured in `reviews/reconciliations/S1/R5_REMEDIATION_NOTES.md:15`.

## B) AT AUDIT TABLE

| AT ID | Contract section | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | S5 wrong impls blocked? | S4 decision as chosen? | Verdict |
|-------|-----------------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-341 | Appendix A.CSP (CONTRACT.md:5090-5095) | `config.rs:156-272::appendix_a_default` (defaults table) + `config.rs:471-500::resolve_config_value` (resolver) | `test_config_defaults.rs:18-22::test_missing_instrument_cache_ttl_s_applies_default_3600` + `test_config_defaults.rs:32-36::test_missing_mm_util_kill_applies_default_095` | PROVEN -- exact value assertions (3600.0, 0.95) against resolve_config_value(param, None) | Yes -- resolve_config_value rejects NaN (line 476-481), Inf (same), negative (line 482-487), percentage >1.0 (line 488-493); missing without default returns Err (line 496-499) | Yes -- `test_resolve_with_explicit_value_overrides_default` (line 127-131) proves overrides work, blocking "hardcode defaults, ignore overrides" wrong impl | Yes (Decision A: typed ConfigParam enum) | **PROVEN** |
| AT-040 | Appendix A.GOP (CONTRACT.md:5108-5113) | `config.rs:496-499::resolve_config_value` (None + no default -> Err via `ok_or_else`) | Unit test: `config.rs:564-580::test_missing_non_appendix_a_param_fails_closed` (uses `#[cfg(test)] SyntheticNoDefault` variant). Integration guard: `test_config_defaults.rs:61-103::test_all_config_params_fail_closed_when_missing_without_default` (exhaustive iteration proves all 74 variants have defaults; any new variant without default is caught) | **WEAK_PROOF** -- The actual Err path at line 496 IS exercised via `SyntheticNoDefault` (test-only variant), which proves the code path works. However, no production ConfigParam variant lacks a default today, so the Err path is structurally unreachable in production code. The exhaustive iteration guard (lines 61-103) catches regressions if a future variant is added without a default. | Yes -- the code returns `Err(MissingConfigError)` with deterministic `param_name` and `reason` fields. Display impl includes "fail-closed". No panic, no unwrap. | **Partial** -- The S5 wrong impl "Return Ok(default) for ALL missing params" IS blocked by the `SyntheticNoDefault` unit test, but only for the synthetic variant. The exhaustive iteration test catches the broader case indirectly. | Yes (Decision A: Return Err, not latch) | **WEAK_PROOF** |
| AT-424 | Appendix A.CSP (CONTRACT.md:5097-5102) | `config.rs:156-272::appendix_a_default` (all CSP params have defaults) | `test_config_defaults.rs:106-124::test_all_params_resolve_through_resolver` (iterates ALL_PARAMS, calls resolve_config_value(param, None), asserts Ok + value match) + `test_config_defaults.rs:136-159::test_all_appendix_a_params_have_defaults` (asserts is_some() + non-zero) + `test_config_defaults.rs:164-232::test_appendix_a_defaults_match_contract` (golden vector: 40 params with exact CONTRACT.md values) | PROVEN -- parameterized iteration covers every CSP param; golden vectors verify exact contract values | Yes | Yes -- parameterized iteration makes "test only one CSP param" wrong impl impossible | N/A (no S4 decision for this AT) | **PROVEN** |
| AT-970 | Appendix A.GOP (CONTRACT.md:5115-5120) | `config.rs:217-218::EvidenceguardGlobalCooldown => Some(120.0)` + `config.rs:262::ReplayWindowHours => Some(48.0)` | `test_config_defaults.rs:25-29::test_missing_evidenceguard_global_cooldown_applies_default_120` + `test_config_defaults.rs:40-44::test_missing_replay_window_hours_applies_default_48` (GAP-010-3 fix) + golden vector table (lines 202, 212) | PROVEN -- dedicated tests for both params with exact value assertions via resolve_config_value | Yes | N/A | N/A | **PROVEN** |
| AT-971 | Appendix A.GOP (CONTRACT.md:5122-5127) | `config.rs:156-272::appendix_a_default` (all GOP params) | `test_config_defaults.rs:106-124::test_all_params_resolve_through_resolver` (iterates ALL_PARAMS including all GOP params) + `test_config_defaults.rs:164-232::test_appendix_a_defaults_match_contract` (golden vectors include GOP params: EvidenceguardGlobalCooldown=120.0, ReplayWindowHours=48.0, DecisionSnapshotRetentionDays=30.0) | PROVEN -- parameterized iteration covers all GOP params | Yes | Yes -- parameterized iteration blocks "test only one GOP param" wrong impl | N/A | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### S2 Assumptions

| # | Assumption | Predicted test | Actual status | Evidence |
|---|-----------|---------------|---------------|----------|
| 1 | S1-001 scaffolding complete, `crates/soldier_infra` exists | AT-905 (dependency) | PASS | `crates/soldier_infra/src/lib.rs` exists, `cargo test -p soldier_infra` succeeds |
| 2 | Appendix A is single source of truth for defaults | Golden vectors use contract values | PASS | `test_appendix_a_defaults_match_contract` checks 40 params against exact CONTRACT.md A.7 values |
| 3 | Fail-closed means error return, not panic | AT-040 | PASS | `resolve_config_value` returns `Result`, no `unwrap()` or `panic!()` in config.rs (confirmed by inspection) |
| 4 | Config loader standalone in soldier_infra, not coupled to runtime gates | Scope guard | PASS | `config.rs` is a standalone module. Production wiring goes through `build_gate_config_from_raw()` called from `bootstrap.rs:285`. No direct coupling to PolicyGuard/EvidenceGuard gate logic. |

### S4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) | Notes |
|----------|--------------|-------------|---------------------|-------|
| Config representation: struct vs map | A -- Typed struct | **DECISION_DIVERGENCE (INFO)** | `config.rs:13-132::ConfigParam` enum with 74 variants + exhaustive `match` arms in `appendix_a_default()` and `param_name()` | Implementation uses enum+match rather than struct+Default. This is an improvement: compile-time exhaustiveness checking via match arms. The premortem's reasoning (compile-time safety) is preserved, just with a different mechanism. |
| Fail-closed for missing non-Appendix-A params | A -- Return `Err(ConfigError::MissingRequired)` | Yes | `config.rs:496-499`: `appendix_a_default(param).ok_or_else(\|\| MissingConfigError { ... })` | Exact match to decision. Error type is `MissingConfigError` with `param_name` and `reason` fields, plus Display impl. |

### S5 Wrong Impls

| Wrong impl from premortem | Tightening test exists? | Test name (file:line) | Catches the wrong impl? |
|--------------------------|------------------------|----------------------|------------------------|
| AT-341: Hardcode `instrument_cache_ttl_s=3600` and `mm_util_kill=0.95` as constants, ignoring config overrides | Yes | `test_config_defaults.rs:127-131::test_resolve_with_explicit_value_overrides_default` | Yes -- asserts `resolve_config_value(InstrumentCacheTtlS, Some(7200.0))` returns 7200.0, not 3600.0 |
| AT-040: Return `Ok(default_value)` for ALL missing params including non-Appendix-A | **Yes (unit)** | `config.rs:564-580::test_missing_non_appendix_a_param_fails_closed` | Yes for SyntheticNoDefault variant -- asserts Err with correct param_name and reason. The exhaustive iteration at `test_config_defaults.rs:61-103` guards against regression if a real variant loses its default. |
| AT-424: Test only one CSP param instead of all | Yes | `test_config_defaults.rs:106-124::test_all_params_resolve_through_resolver` | Yes -- iterates ALL_PARAMS (74 variants), preventing partial coverage |
| AT-970: Handle cooldown but not replay_window_hours | Yes | `test_config_defaults.rs:40-44::test_missing_replay_window_hours_applies_default_48` (GAP-010-3 fix) | Yes -- dedicated test for replay_window_hours=48.0 |
| AT-971: Test only one GOP param instead of all | Yes | `test_config_defaults.rs:106-124::test_all_params_resolve_through_resolver` | Yes -- same parameterized iteration covers all GOP params |

## D) DESIGN RISK NOTES

### P1 -- AT-040 Err Path Structurally Unreachable in Production

**Finding**: All 74 production `ConfigParam` variants have Appendix A defaults. The `resolve_config_value` Err path (config.rs:496-499) is only exercisable via the `#[cfg(test)] SyntheticNoDefault` variant. In production, calling `resolve_config_value(param, None)` for any `ConfigParam` will always return `Ok(default)`.

**Mitigation in place**: The unit test at `config.rs:564-580` proves the Err path code is correct. The exhaustive iteration at `test_config_defaults.rs:61-103` with `EXPECTED_PARAM_COUNT` assertion catches any new variant added without a default. The `bootstrap_full()` function at `bootstrap.rs:284-298` provides the production callsite that propagates `MissingConfigError` as `io::Error`.

**Residual risk**: LOW. The guard is comprehensive for regressions. The only risk is if someone adds a new `ConfigParam` variant with `None` default but forgets to update `ALL_PARAMS` and `EXPECTED_PARAM_COUNT` -- this would fail the count assertion test.

**Status**: PERSISTS from prior reconciliation. Accepted as structural debt.

### P2 -- Observability Metric Not Implemented

**Finding**: The PRD specifies `config_defaults_applied_total` counter (prd.json:1487-1493) and the drift_metric references it. No implementation exists in `config.rs` or anywhere in the codebase. The `resolve_config_value` function does not emit any counter when it falls back to a default.

**Impact**: Without this metric, there is no runtime signal when config values are missing and defaults are being applied. This reduces operational visibility but does not affect safety (the defaults are still applied correctly).

**Status**: New finding. Should be tracked as deferred debt for when runtime observability infrastructure is available.

### P2 -- CONTRACT.md A.7 Summary Table Missing 5 Parameters

**Finding**: The code has 74 ConfigParam variants (excluding test-only `SyntheticNoDefault`). The A.7 Summary Table has 69 rows. Missing from A.7: `spread_kill_bps` (75 bps), `depth_kill_min` (100,000 USD), `cortex_kill_window_s` (10s), `exchange_health_stale_s` (180s), `canary_evidence_abort_s` (180s). All 5 are defined with defaults in the detailed Appendix A subsections (CONTRACT.md lines 5222, 5253, 5265, 5420, 5129 respectively). The code values match the contract text. This is an A.7 table completeness issue, not a code bug.

**Impact**: Low. Defaults are correct in code. A.7 table is a convenience summary.

### INFO -- NaN/Inf/Negative/Percentage Validation

The implementation includes input validation beyond what the ATs require:
- NaN rejection: `config.rs:476-481`, tested at `test_config_defaults.rs:251-255`
- Infinity rejection: `config.rs:476-481`, tested at `test_config_defaults.rs:258-262`
- Negative rejection: `config.rs:482-487`, tested at `test_config_defaults.rs:272-276`
- Percentage >1.0 rejection: `config.rs:488-493`, tested at `test_config_defaults.rs:303-333`
- Production callsite validation: `test_config_init.rs:16-28` (NaN), `test_config_init.rs:32-42` (negative), `test_config_init.rs:46-56` (percentage)

This is bonus fail-closed behavior not required by the 5 story ATs.

### INFO -- Production Wiring via bootstrap_full()

`build_gate_config_from_raw()` is called from `bootstrap.rs:285` in `bootstrap_full()`, which validates gate thresholds before storage bootstrap. This provides the production callsite that exercises `resolve_config_value` for 7 gate-critical parameters (fee_cache_soft_s, fee_cache_hard_s, fee_stale_buffer, instrument_cache_ttl_s, l2_book_snapshot_max_age_ms, max_slippage_bps, contracts_amount_match_tolerance). The remaining 67 ConfigParam variants are defined and tested but not yet consumed by a production callsite (deferred to PolicyGuard/EvidenceGuard integration stories).

### INFO -- Zero-Default Exemptions Unnecessary

`test_all_appendix_a_params_have_defaults` (line 148-157) exempts `AtomicQtyEpsilon` and `PositionReconcileEpsilon` from the "default must not be zero" check. However, both have non-zero defaults (`1e-9` and `1e-6` respectively). The exemption is harmless but unnecessary.

## E) REMEDIATION PLAN

```
[DEFERRED]  GAP-S1-010-001: P1 -- AT-040 Err path structurally unreachable in production.
            Status: Regression guard remains in place (`test_all_config_params_fail_closed_when_missing_without_default`);
            SyntheticNoDefault unit test still proves the mechanism.
            Debt tracked as `DEBT-S1-010-001` at `reviews/reconciliations/S1/DEBT_REGISTER.json:41`.

[FIXED]     GAP-010-2: P2 -- PRD scope.create lists config/ but config lives in src/config.rs.
            Status: Fixed in prd.json.

[FIXED]     GAP-010-3: P2 -- Dedicated test_missing_replay_window_hours_applies_default_48().
            Status: Added at test_config_defaults.rs:39-44.

[DEFERRED]  GAP-010-4: Config loader not wired into PolicyGuard/EvidenceGuard runtime.
            Owner: PolicyGuard story owner. Target: Slice 2+.
            Note: 7 of 74 params are wired via build_gate_config_from_raw() in bootstrap_full().

[DEFERRED]  GAP-010-5: CI check that count of test params == count of Appendix A params.
            Owner: Config story owner. Target: Slice 2.
            Note: EXPECTED_PARAM_COUNT=74 check exists in test but is not CI-enforced.

[NEW]       GAP-010-6: P2 -- Observability metric config_defaults_applied_total not implemented.
            Owner: Observability story owner. Target: When runtime metrics infrastructure available.

[NEW]       GAP-010-7: P2 -- CONTRACT.md A.7 Summary Table missing 5 parameters
            (spread_kill_bps, depth_kill_min, cortex_kill_window_s, exchange_health_stale_s,
            canary_evidence_abort_s). Code values match detailed Appendix A text.
            Owner: Contract maintenance. Target: Next contract update.
```

## F) SCOPE CHECK

| File (premortem S0 / PRD scope) | Exists? | Role | Notes |
|--------------------------------|---------|------|-------|
| `crates/soldier_infra/src/lib.rs` (touch) | Yes | Declares `pub mod config;` at line 4, re-exports at line 10 | Correctly wires config module |
| `crates/soldier_infra/src/config.rs` (create) | Yes | 629 lines: ConfigParam enum (74 variants), appendix_a_default(), resolve_config_value(), GateConfig, RawThresholdConfig, build_gate_config_from_raw(), 4 unit tests | Primary enforcement point |
| `crates/soldier_infra/tests/` (touch) | Yes | `test_config_defaults.rs` (23 tests), `test_config_init.rs` (5 tests) | 28 total config-related tests |
| `crates/soldier_infra/src/bootstrap.rs` (not in scope.touch) | Exists | Calls `build_gate_config_from_raw()` at line 285 | Production callsite for resolve_config_value; provides the wiring path |

**Scope violation check**: No files outside scope.touch/create were modified by S1-010. The `bootstrap.rs` integration was added as part of bootstrap story work (not S1-010 scope violation).

## READ-ONLY INTEGRITY CHECK

```
Git status at start and end of audit compared.
No S1-010 scope files were modified during this audit.
New untracked files are test artifact lock files (runtime_state_tests/) from cargo test --list.
Audit was READ-ONLY.
```

---

READY FOR SELF_REVIEW
