# R4 Gap Synthesis — S0 (Phase 0)

**Date**: 2026-02-24
**Head commit**: 5bfc230
**Sources**: R1 (6 evidence ledgers) + R2 (lead eval) + R3A (Alpha + Beta cross-reviews)
**R3B**: Not performed (retroactive audit of already-passed Phase 0 stories)

---

## Severity Resolution

| Gap | R1 | R2 | R3A | Final | Rationale |
|-----|----|----|-----|-------|-----------|
| S0-002 scopes blocklist | LOW-MED | LOW-MED | MED (Alpha) | **MED** | probe_results withdrawal check bypassed for non-trade scopes; bypass more complete than R1 assessed |

All other severities unchanged across R1/R2/R3A.

---

## P0 — Safety-Critical (1)

### GAP-S0-003-001: Missing state file defaults to ACTIVE (fail-OPEN)

**Story**: S0-003 (Break-Glass Runbook + Drill)
**Source**: R1 + R2 confirmed + R3A Beta confirmed
**Enforcement**: `stoic-cli:196-199` (`_load_runtime_state`)
**Classification**: CODE_FIX

`_load_runtime_state()` returns `_default_runtime_state()` with `trading_mode="ACTIVE"` when the state file is absent. If the file is deleted after a Kill transition (container restart, filesystem cleanup), the system silently reverts to ACTIVE with no warning. This is **fail-OPEN for the last-resort safety mechanism**.

**Fix**: Distinguish "never initialized" from "deleted after Kill". When state file expected but missing, default to KILL or emit warning + latch.

---

## P1 — Must Fix (6)

### GAP-S0-002-001: Scope blocklist bypass (MED)

**Story**: S0-002 (Keys & Secrets Baseline)
**Source**: R1 D1/D2 + R3A Alpha (severity upgrade + new analysis)
**Enforcement**: `stoic-cli:979` (scopes check), `stoic-cli:987-998` (probe_results)
**Classification**: CODE_FIX

Scope blocklist at `stoic-cli:979` only checks `"transfer"`. `"all"` and `"withdraw"` bypass entirely. R3A Alpha confirmed: `probe_results` withdrawal check (lines 987-991) does NOT fire for non-`"trade"` scopes — the `else` branch at 994-998 skips withdrawal validation. A key with `scopes: ["all"], withdraw_enabled: false` passes ALL checks. Only `withdraw_enabled is not False` boolean check remains as defense.

**Fix**: Switch to allowlist (only known-safe scopes) OR add `"all"`, `"withdraw"`, `"margin"` to forbidden. Add single-violation test for `scopes: ["all"]` golden vector.

### GAP-S0-003-002: No mid-session state deletion test (MED)

**Story**: S0-003
**Source**: R3A Beta (new finding)
**Classification**: TEST_FIX

No test exercises: kill → delete state file → dispatch-check → assert not ACTIVE. R1 identified the code gap (GAP-S0-003-001) but did not elevate the missing test to a distinct remediation item.

**Fix**: Add `test_break_glass_mid_session_state_deletion_runtime`.

### GAP-S0-004-002: No contract_version assertion

**Story**: S0-004 | **AT**: AT-022 | **Classification**: TEST_FIX

`DEFAULT_CONTRACT_VERSION = "5.2"` at `stoic-cli:35` but no test asserts this value in output. Premortem S5 wrong-impl (wrong string) is unblocked.

**Fix**: Add `assert_eq!(payload["contract_version"], "5.2")`.

### GAP-S0-004-003: No build_id assertion

**Story**: S0-004 | **AT**: AT-022 | **Classification**: TEST_FIX

Test injects `STOIC_BUILD_ID` but never asserts the injected value in output. Premortem S5 wrong-impl (empty/placeholder) is unblocked.

**Fix**: Add `assert_eq!(payload["build_id"], injected_value)`.

### GAP-S0-004-004: No health subcommand test

**Story**: S0-004 | **AT**: AT-022 | **Classification**: TEST_FIX
**Source**: R1 R4 + R3A Beta (health vs status divergence)

`_cmd_health` (stoic-cli:343-366) and `_cmd_status` (stoic-cli:418-461) are separate functions with different payloads and error handling. Only `_cmd_status` tested. AT-022 targets `/health`, not `/status`.

**Fix**: Add `test_health_command_behavior_runtime` exercising `./stoic-cli health --format json`.

### GAP-S0-004-005: No REDUCE_ONLY is_trading_allowed test

**Story**: S0-004 | **AT**: AT-022 | **Classification**: TEST_FIX

`_is_trading_allowed_mode` returns `mode == "ACTIVE"` — REDUCE_ONLY should yield false. Only ACTIVE and KILL paths tested.

**Fix**: Add table-driven mode test: `[{ACTIVE, true}, {REDUCE_ONLY, false}, {KILL, false}]`.

---

## P2 — Should Fix (7)

| Gap ID | Story | Description | Classification |
|--------|-------|-------------|----------------|
| GAP-S0-000-001 | S0-000 | `[FILL]` placeholders in metadata (inconsistent with sign-off block) | PRD_FIX |
| GAP-S0-001-001 | S0-001 | Missing postmortem (R3A Alpha flagged) | PRD_FIX |
| GAP-S0-002-002 | S0-002 | Multi-violation test isolation — tests fire 2-3 gates, assert only 1 | TEST_FIX |
| GAP-S0-003-003 | S0-003 | Drill version binding missing (no commit hash in drill.md) | PRD_FIX |
| GAP-S0-003-004 | S0-003 | Runbook snapshot drifted (Dashboard section added) | PRD_FIX |
| GAP-S0-004-006 | S0-004 | scope.touch lists wrong file (lib.rs vs stoic-cli) | PRD_FIX |
| GAP-S0-005-001 | S0-005 | No validate_policy({}) test for empty object boundary | TEST_FIX |

---

## DEFERRED (5)

| Gap ID | Story | Description | Target |
|--------|-------|-------------|--------|
| GAP-S0-002-003 | S0-002 | Probe provenance unverifiable by machine | Phase 2+ CI |
| GAP-S0-003-005 | S0-003 | Risk reduction uses drill-only simulate-close | Phase 1+ |
| GAP-S0-003-006 | S0-003 | TOCTOU in state file (single-process mitigates) | Multi-process |
| GAP-S0-004-001 | S0-004 | AT-022 HTTP transport missing (CLI only) | S8-008 |
| GAP-S0-005-002 | S0-005 | Value-range upper bounds deferred | S2.2 PolicyGuard |

---

## Systemic Gaps (2)

### GAP-SYSTEMIC-001 (P2): No automated CI for doc snapshot drift

**Affected**: S0-000, S0-001
Both rely on manual `diff` between canonical docs and evidence snapshots. No CI gate prevents drift.

### GAP-SYSTEMIC-002 (P2): No formal AT anchors across Phase 0

**Affected**: S0-000, S0-001, S0-002, S0-003, S0-005
Only S0-004 claims AT-022 (CLAIMED_NOT_PROVEN). Safety argument for the other 5 stories rests on implementation tests and doc reviews alone.

---

## Priority Summary

| Priority | Count | Key items |
|----------|-------|-----------|
| **P0** | 1 | S0-003 missing-state → ACTIVE (fail-OPEN in break-glass) |
| **P1** | 6 | S0-002 scopes bypass, S0-003 deletion test, S0-004 x4 test gaps |
| **P2** | 7 | Doc fixes, test isolation, scope.touch, postmortem |
| **DEFERRED** | 5 | AT-022 HTTP (S8-008), probe provenance, value ranges, TOCTOU, drill |
| **Systemic** | 2 | CI for doc drift, formal AT anchors |

---

## R4 Gate Checks

| Gate ID | Check | Result |
|---------|-------|--------|
| `R4_GAP_LIST_COMPLETE` | GAP_LIST.md and GAP_LIST.json both exist; every story has gap entries | **PASS** |
| `R4_NO_UNCHECKED_CLEAN_REVIEW` | No story with empty gaps and missing coverage proof | **PASS** — all 6 stories have gaps |
| `R4_DEBT_DRAFT_COMPLETE` | Every DEFERRED gap has a matching debt entry stub | **PASS** — see DEBT_REGISTER.json |
