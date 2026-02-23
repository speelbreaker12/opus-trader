---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INFRA_reconciliation.md
story_id: S1-010
story_title: "Appendix A config defaults"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (AT-040 WEAK_PROOF P1 + P2 gaps)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-010 (Appendix A config defaults)

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT YELLOW — all debt items explicitly deferred.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-341 | Appendix A.CSP | crates/soldier_infra/src/config.rs:149-262::appendix_a_default + config.rs:433-456::resolve_config_value | test_config_defaults.rs:15-19::test_missing_instrument_cache_ttl_s_applies_default_3600 + test_config_defaults.rs:29-33::test_missing_mm_util_kill_applies_default_095 | Yes — exact value assertions (3600.0, 0.95) | Yes — resolve_config_value returns Err for missing params without defaults (config.rs:452-455), rejects NaN/Inf (config.rs:438-443), rejects negative (config.rs:444-449) | Yes — test_resolve_with_explicit_value_overrides_default (line 90-94) proves config overrides work | Yes (Decision A: typed struct) | **PROVEN** |
| AT-040 | Appendix A.GOP | crates/soldier_infra/src/config.rs:452-455::resolve_config_value (None + no default -> Err) | test_config_defaults.rs:38-66::test_missing_non_appendix_a_param_fails_closed | **WEAK_PROOF** — test constructs MissingConfigError manually and checks Display output; does NOT call resolve_config_value(param, None) for a param that actually lacks a default | Yes — the code path is correct: config.rs:452 returns Err | N/A | Yes (Decision A: return Err, not latch) | **WEAK_PROOF** |
| AT-424 | Appendix A.CSP | crates/soldier_infra/src/config.rs:149-262::appendix_a_default (all CSP params) | test_config_defaults.rs:69-87::test_all_params_resolve_through_resolver + test_config_defaults.rs:98-122::test_all_appendix_a_params_have_defaults + test_config_defaults.rs:127-194::test_appendix_a_defaults_match_contract | Yes — iterates ALL_PARAMS, golden vector checks exact values | Yes | Yes — parameterized iteration catches missing defaults | N/A | **PROVEN** |
| AT-970 | Appendix A.GOP | crates/soldier_infra/src/config.rs:211::EvidenceguardGlobalCooldown => Some(120.0) + config.rs:256::ReplayWindowHours => Some(48.0) | test_config_defaults.rs:22-26::test_missing_evidenceguard_global_cooldown_applies_default_120 + golden vector table (line 165,175) | Partial — dedicated test for cooldown; replay_window_hours only in golden vector | Yes | N/A | N/A | **PROVEN** |
| AT-971 | Appendix A.GOP | crates/soldier_infra/src/config.rs:149-262::appendix_a_default (all GOP params) | test_config_defaults.rs:69-87::test_all_params_resolve_through_resolver | Yes — parameterized iteration covers all GOP params | Yes | Yes | N/A | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | S1-001 scaffolding complete | AT-905 | PASS |
| 2 | Appendix A is single source of truth | Golden vectors use contract values | PASS — test_appendix_a_defaults_match_contract checks ~40 params |
| 3 | Fail-closed means error return, not panic | AT-040 | PASS — resolve_config_value returns Result, no unwrap()/panic |
| 4 | Config loader standalone in soldier_infra | Scope guard | PASS — config.rs is standalone |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Config representation | A — Typed struct with enum variants | **DECISION_DIVERGENCE (INFO)** | config.rs uses `enum ConfigParam` (74 variants) + match arms. Better than struct + Default. |
| Fail-closed for missing non-Appendix-A params | A — Return Err | Yes | config.rs:452-455 |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-341: Hardcode defaults, ignore overrides | Yes | test_resolve_with_explicit_value_overrides_default (line 90-94) | Yes |
| AT-040: Return Ok(default) for ALL missing params | **WEAK** | test_missing_non_appendix_a_param_fails_closed (line 38-66) | **No** — doesn't call resolve_config_value for a param without a default |
| AT-424: Test only one CSP param | Yes | test_all_params_resolve_through_resolver (line 69-87) | Yes — iterates ALL |
| AT-970: Handle cooldown but not replay_window_hours | Yes | golden vector (line 175) | Yes |

## D) DESIGN RISK NOTES

- **P1 — AT-040 WEAK_PROOF**: Err path untested end-to-end. All 74 variants have defaults.
- **P2 — Missing config/ directory**: PRD scope.create mismatch.
- **P2 — AT-970 replay_window_hours**: Only in golden vector, no dedicated test.
- **INFO**: NaN/Inf/negative rejection tested (lines 214, 220, 235).

## E) REMEDIATION PLAN

```
[TEST_FIX]  GAP-010-1: P1 — AT-040 fail-closed Err path untested end-to-end.
[PRD_FIX]   GAP-010-2: P2 — PRD scope.create lists config/ but config lives in src/config.rs.
[TEST_FIX]  GAP-010-3: P2 — Add dedicated test_missing_replay_window_hours_applies_default_48().
[DEFERRED]  GAP-010-4: Config loader not wired into PolicyGuard/EvidenceGuard runtime.
[DEFERRED]  GAP-010-5: CI check that count of test params == count of Appendix A params.
[INFO]      Enum+match design is an improvement over premortem's struct+Default prediction.
[INFO]      NaN/Inf/negative rejection is bonus fail-closed behavior with tests.
```

## F) SCOPE CHECK

| File (premortem §0) | Exists? | Notes |
|---------------------|---------|-------|
| crates/soldier_infra/src/lib.rs | Yes | lib.rs:4 declares `pub mod config;` |
| crates/soldier_infra/tests/ | Yes | test_config_defaults.rs exists with 17 tests |
| crates/soldier_infra/config/ (create) | **MISSING** | Config is src/config.rs module, not a subdirectory |

```
READY FOR SELF_REVIEW
```
