# S0-004 Reconciliation Audit

**Story**: S0-004 -- P0-E Health + Owner Status Scaffolding
**Auditor**: R1 Reconciliation (read-only)
**Date**: 2026-02-24
**Status**: `passes=true`

---

## A) GATE RESULT

**GATE: YELLOW -- CLAIMED_NOT_PROVEN (conditional pass)**

S0-004 claims AT-022 as its sole `enforcing_contract_ats` entry. AT-022 requires an HTTP `GET /api/v1/health` endpoint returning HTTP 200 with JSON keys `ok`, `build_id`, `contract_version`. The implementation delivers a CLI `./stoic-cli status` command in Python, NOT an HTTP endpoint. The premortem (S0-004_premortem.md line 21) correctly identifies this as "partial enforcement" and defers full AT-022 proof to S8-008. The PRD description (prd.json line 373) explicitly states: "Full AT-022 enforcement in S8-008."

The data model IS correct:
- `ok`, `build_id`, `contract_version` keys are produced by `_health_payload()` (stoic-cli:134-143)
- `trading_mode`, `is_trading_allowed` keys are produced by `_status_payload()` (stoic-cli:369-394)
- `is_trading_allowed` derivation is correct: `mode == "ACTIVE"` (stoic-cli:323-324)
- Fail-closed on missing policy: `trading_mode = "KILL"` (stoic-cli:444)
- Fail-closed on corrupt runtime state: `trading_mode = "KILL"` (stoic-cli:204-206, 212-214, 223-225, 236-238)

But AT-022 as written in CONTRACT.md (line 4442-4447) requires HTTP 200, not CLI JSON output. The story cannot fully prove this AT.

---

## B) AT AUDIT TABLE

| AT ID | Contract section | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | section-5 wrong impls blocked? | section-4 decision as chosen? | Verdict |
|-------|---------|----------------------------------------|-----------------|---------------|-------------|-------------------------------|-------------------------------|---------|
| AT-022 | CONTRACT.md section 7.0 (lines 4429-4447) | `stoic-cli:134-143::_health_payload` (health), `stoic-cli:369-394::_status_payload` (status), `stoic-cli:343-366::_cmd_health` (health command), `stoic-cli:418-461::_cmd_status` (status command) | `test_status_command_behavior_runtime` (test_phase0_runtime.rs:426-487) | PARTIAL -- asserts `ok`, `trading_mode`, `is_trading_allowed` values for healthy/unhealthy paths but does NOT test via HTTP transport as AT-022 requires. Also does NOT assert `contract_version` or `build_id` values in the test. | YES -- missing policy -> `trading_mode=KILL`, `ok=false` (lines 471-476). Corrupt state -> KILL (test_runtime_state_schema_mismatch_fails_closed:1070). Path outside repo -> KILL (test_runtime_state_path_outside_repo_rejected:679). | PARTIAL -- see section C below | YES -- Decision A chosen (scaffolding only, no HTTP) | **CLAIMED_NOT_PROVEN** |

### AT-022 Verdict Justification

**Why CLAIMED_NOT_PROVEN, not PROVEN:**

1. **HTTP transport missing**: AT-022 requires `GET /api/v1/health` returning HTTP 200. The implementation is a CLI script (`./stoic-cli health`), not an HTTP endpoint. No HTTP server exists in the codebase for this story.

2. **`contract_version` value not asserted in test**: The proving test (`test_status_command_behavior_runtime`) asserts `ok`, `trading_mode`, and `is_trading_allowed` but never checks `healthy_payload["contract_version"] == "5.2"`. The premortem section 5 specifically identifies this as a wrong-impl vector (line 94: "contract_version field exists but contains `""` or `"0.0"` or `"v5.2"`"). The tightening test ("golden vector unit test: `assert_eq!(health.contract_version, "5.2")`") does NOT exist in the test suite. SEARCHED: `grep "5.2" test_phase0_runtime.rs` -- zero matches.

3. **`build_id` value not asserted in test**: The test injects `STOIC_BUILD_ID=phase0-status-runtime-test` but never asserts the payload contains that value. The premortem section 5 (line 95) requires "`build_id.len() > 0`" assertion. MISSING.

4. **No `health` command test**: The test file has `test_status_command_behavior_runtime` which tests the `status` subcommand. There is NO test for the `health` subcommand (SEARCHED: `grep '"health"' test_phase0_runtime.rs` -- zero matches). AT-022 specifically targets `/health`, not `/status`.

5. **No golden vector serialization test**: Premortem section 5 (line 98) requires a golden-vector test asserting exact JSON key names. No such test exists. The CLI uses Python dicts (not Rust structs with serde), so serde key renaming risk is low, but the key name assertion is still missing.

**Why not UNTESTED_ENFORCEMENT:**
The enforcement point (data model + fail-closed logic) DOES exist and IS tested. The `status` command tests prove the payload structure works correctly. The gap is specifically the HTTP transport layer and exact value assertions.

---

## C) PREMORTEM CROSS-REFERENCE

### section-2 Assumptions

| # | Assumption | Validated? | Evidence |
|---|-----------|------------|----------|
| 1 | `contract_version` canonical value `"5.2"` | PARTIALLY -- `DEFAULT_CONTRACT_VERSION = "5.2"` at stoic-cli:35, but NO test asserts the output contains exactly `"5.2"` | stoic-cli:35, test gap: no `contract_version` assertion in test_status_command_behavior_runtime |
| 2 | `build_id` non-empty at construction | PARTIALLY -- `_detect_build_id()` (stoic-cli:118-131) returns env var or git SHA or `"unknown"`. If `"unknown"`, an error is added (stoic-cli:354). But no test asserts `build_id` in the output payload. | stoic-cli:118-131, 354-355 |
| 3 | `TradingMode` enum available | DIVERGED -- Implementation uses Python string constants `{"ACTIVE", "REDUCE_ONLY", "KILL"}` (stoic-cli:38), NOT a Rust enum. The assumption was about Rust `TradingMode` in `soldier_core`. `TradingMode` exists in soldier_core as comments referencing it from `RiskState` but no formal enum definition found. | stoic-cli:38, crates/soldier_core/src/risk/state.rs (references TradingMode in doc comments only) |
| 4 | `is_trading_allowed` strict derivation | VALIDATED -- `_is_trading_allowed_mode(mode) -> mode == "ACTIVE"` (stoic-cli:323-324). Test asserts `Active->true` (line 454), missing policy (KILL) `->false` (line 476). | stoic-cli:323-324, test_phase0_runtime.rs:454, 476 |
| 5 | "CLI status data model" means structs with serde | DIVERGED -- Implementation is a Python script, not Rust structs. No serde involved. | stoic-cli (entire file is Python) |
| 6 | Serde produces correct JSON key names | N/A -- Python `json.dumps()` uses dict key names directly, not serde. Key names are hardcoded strings in `_health_payload()` and `_status_payload()`. | stoic-cli:135-138, 378-384 |

### section-4 Decisions

| Decision | Chosen | Implemented as chosen? | Evidence |
|----------|--------|----------------------|----------|
| D1: What "scaffolding" means | Option A: data model structs only, no HTTP | YES (but in Python, not Rust) -- CLI script with dict-based payloads, no HTTP endpoint | stoic-cli:343-366 (`_cmd_health`), stoic-cli:418-461 (`_cmd_status`) |
| D2: `contract_version` source | Option A: compile-time constant | YES (Python equivalent) -- `DEFAULT_CONTRACT_VERSION = "5.2"` at module level | stoic-cli:35 |
| D3: `build_id` source | Option C: constructor parameter / DI | YES (Python equivalent) -- `_detect_build_id()` reads `STOIC_BUILD_ID` env var, falls back to git SHA | stoic-cli:118-131, tests inject via env var |

### section-5 Wrong Implementations

| Wrong impl | Blocked by test? | Evidence |
|-----------|-----------------|----------|
| `ok` hardcoded as `const true` | BLOCKED -- test_status_command_behavior_runtime asserts `ok=false` on missing policy (line 471) | test_phase0_runtime.rs:471 |
| `contract_version` wrong string | **NOT BLOCKED** -- no test asserts the exact value `"5.2"` in output. A regression changing `DEFAULT_CONTRACT_VERSION` to `"v5.2"` would pass all tests. | SEARCHED: no `"5.2"` match in test_phase0_runtime.rs |
| `build_id` empty or placeholder | **NOT BLOCKED** -- no test asserts `build_id` value in output payload. The test injects `STOIC_BUILD_ID` but never checks the output contains it. | SEARCHED: no `build_id` assertion in test_status_command_behavior_runtime |
| Health struct never exported (private) | N/A -- Python module, not Rust crate boundary. Functions are module-level and callable. | stoic-cli is a single file |
| `is_trading_allowed` wrong for ReduceOnly | **PARTIALLY BLOCKED** -- test_break_glass_command_path_runtime asserts `REDUCE_ONLY` mode transition (line 608) but does NOT assert `is_trading_allowed=false` for that specific ReduceOnly state. test_status_command_behavior_runtime tests only ACTIVE (true) and KILL via missing-policy (false). No test explicitly sets ReduceOnly and checks `is_trading_allowed=false`. | test_phase0_runtime.rs:452-454 (ACTIVE->true), 473-476 (KILL->false); MISSING explicit ReduceOnly->false |
| Serde serialization wrong key names | N/A -- Python dicts with literal key strings; no serde rename risk | stoic-cli:135-138, 378-384 |

---

## D) DESIGN RISK NOTES

### D1: Scope file mismatch
PRD `scope.touch` lists `crates/soldier_infra/src/lib.rs` but the actual implementation lives in `stoic-cli` (Python script at repo root). The Rust `lib.rs` file (`/Users/admin/Desktop/opus-trader/crates/soldier_infra/src/lib.rs`) contains zero health/status code -- it exports `bootstrap`, `config`, `deribit`, `store`, `wal` modules only (lines 1-14). The scope declaration is misleading: the enforcement point is NOT in `crates/soldier_infra/src/lib.rs`.

**Impact**: Low. The scope mismatch does not affect correctness but makes auditing harder. The test is correctly placed in `crates/soldier_infra/tests/test_phase0_runtime.rs` because it tests the `stoic-cli` binary via `Command::new()`.

### D2: No `health` subcommand test
The designated implementation test `test_status_command_behavior_runtime` tests only the `status` subcommand. AT-022 targets the `health` endpoint (`GET /api/v1/health`). While the `_health_payload()` function at stoic-cli:134-143 produces the correct fields, no automated test exercises the `health` subcommand path. The test plan document at `/Users/admin/Desktop/opus-trader/tests/phase0/test_health_command_behavior.md` describes the procedure but is a markdown document, not an executable test.

### D3: `_detect_build_id()` can return `"unknown"`
At stoic-cli:131, if no `STOIC_BUILD_ID` env var is set and `git rev-parse` fails, the function returns `"unknown"`. This is caught at stoic-cli:354-355 which adds `"build_id: unavailable"` to errors. However, the `build_id` field in the output will still be the string `"unknown"` -- it is included in the payload. AT-022 requires the key to exist (which it does) but does not specify value quality. The premortem correctly identifies this as a future risk for F1_CERT binding.

### D4: Fail-closed is well-implemented
The stoic-cli demonstrates proper fail-closed patterns:
- Missing policy: `trading_mode = "KILL"` (stoic-cli:444)
- Runtime state path outside repo: exception -> `trading_mode = "KILL"` (stoic-cli:437)
- Corrupt runtime state JSON: `trading_mode = "KILL"` (stoic-cli:204-206)
- Invalid runtime state shape: `trading_mode = "KILL"` (stoic-cli:212-214)
- Schema version mismatch: `trading_mode = "KILL"` (stoic-cli:223-225)
- Invalid trading mode string: `trading_mode = "KILL"` (stoic-cli:236-238)
- Invalid default mode in `_default_runtime_state`: `mode = "KILL"` (stoic-cli:166)

Each of these fail-closed paths has a corresponding integration test:
- `test_status_command_behavior_runtime` (missing policy)
- `test_runtime_state_path_outside_repo_rejected` (path outside repo)
- `test_runtime_state_schema_mismatch_fails_closed` (schema mismatch)
- `test_runtime_state_null_schema_fails_closed` (null schema)

### D5: `unwrap()` in production code
The scope file `crates/soldier_infra/src/lib.rs` has zero `unwrap()` calls (verified by grep). The `stoic-cli` Python script has zero `unwrap()` (not applicable -- Python). The test file `test_phase0_runtime.rs` uses `unwrap()` and `expect()` in test helpers (lines 62-72), which is acceptable for test code.

### D6: No TRIP/NON-TRIP tests
The premortem correctly notes (line 118) that TRIP/NON-TRIP is not applicable for scaffolding. There is no runtime gate that "trips" to block trading. The enforcement is read-only data output. This is acceptable for an S0 scaffolding story.

---

## E) REMEDIATION PLAN

### P0 (Blocking for full AT-022 proof -- deferred to S8-008)

| # | Finding | Severity | Action | Owner |
|---|---------|----------|--------|-------|
| R1 | AT-022 requires HTTP `GET /api/v1/health` returning HTTP 200. No HTTP endpoint exists. | P0 | Implement HTTP endpoint wiring in S8-008. Integration test must issue actual HTTP request and assert response. | S8-008 implementor |

### P1 (Test gaps for existing enforcement -- should fix in reconciliation)

| # | Finding | Severity | Action | Owner |
|---|---------|----------|--------|-------|
| R2 | No test asserts `contract_version == "5.2"` in output payload. Premortem section-5 golden vector is unblocked. | P1 | Add assertion `assert_eq!(healthy_payload["contract_version"], Value::String("5.2".to_string()))` to `test_status_command_behavior_runtime`. | Reconciliation fix |
| R3 | No test asserts `build_id` value in output payload. | P1 | Add assertion `assert_eq!(healthy_payload["build_id"], Value::String("phase0-status-runtime-test".to_string()))` to `test_status_command_behavior_runtime`. | Reconciliation fix |
| R4 | No executable test for `health` subcommand. The markdown test plan (`tests/phase0/test_health_command_behavior.md`) is documentation only. | P1 | Add `test_health_command_behavior_runtime` to test_phase0_runtime.rs exercising `./stoic-cli health --format json` with healthy/unhealthy paths. | Reconciliation fix |
| R5 | No test explicitly checks `is_trading_allowed=false` when `trading_mode=REDUCE_ONLY`. The `test_break_glass_command_path_runtime` test transitions to REDUCE_ONLY (line 608) but does not assert `is_trading_allowed`. | P1 | Add `assert_eq!(reduce_mode_payload["is_trading_allowed"], Value::Bool(false))` after line 609 in `test_break_glass_command_path_runtime`, or add dedicated table-driven test. | Reconciliation fix |

### P2 (Documentation / scope hygiene)

| # | Finding | Severity | Action | Owner |
|---|---------|----------|--------|-------|
| R6 | PRD `scope.touch` lists `crates/soldier_infra/src/lib.rs` but no S0-004 code lives there. Actual enforcement is in `stoic-cli` (repo root). | P2 | Update prd.json `scope.touch` to include `stoic-cli` and remove or annotate `crates/soldier_infra/src/lib.rs`. | Documentation fix |
| R7 | Premortem assumes Rust structs with serde; implementation is Python. section-2 assumptions 3, 5, 6 are all about Rust patterns that don't apply. | P2 | No code action needed. Note in postmortem that implementation diverged from premortem's Rust assumption. | Documentation |

---

## F) SCOPE CHECK

### Files in scope.touch vs actual implementation

| Scope file | In scope.touch? | Contains S0-004 code? | Notes |
|-----------|----------------|----------------------|-------|
| `docs/health_endpoint.md` | YES | YES (documentation) | Contains field tables, examples, exit codes. Well-maintained. |
| `crates/soldier_infra/src/lib.rs` | YES | **NO** | Contains only module re-exports for bootstrap/config/deribit/store/wal. Zero health/status code. |
| `stoic-cli` (repo root) | **NO** (not in scope.touch) | **YES** (all enforcement code) | Python script with `_cmd_health`, `_cmd_status`, `_health_payload`, `_status_payload`, `_is_trading_allowed_mode`. This is the actual enforcement point. |
| `crates/soldier_infra/tests/test_phase0_runtime.rs` | NO (test file) | YES (proving test) | Integration test exercising `stoic-cli` via subprocess. |

### Scope verdict
The PRD scope declaration is INACCURATE. The primary enforcement file (`stoic-cli`) is missing from `scope.touch`, and one listed file (`crates/soldier_infra/src/lib.rs`) contains no S0-004 code. This is a P2 documentation issue, not a safety issue.

### enforcing_contract_ats correctness
- `AT-022` is the only entry. This is correct for the claim. The story is the only S0 story with a formal AT.
- However, AT-022 can only be CLAIMED_NOT_PROVEN because the HTTP transport is absent.
- The `is_trading_allowed` derivation logic (acceptance criteria 2-4) has no formal AT anchor in CONTRACT.md section 7.0, as the premortem correctly identifies in the debt register (line 174).

### loss_mode audit
- `worst_case`: "health endpoint returns stale/wrong status -> operator trusts bad state -> delayed incident response" -- ACCURATE for the full story but overstated for scaffolding-only scope. The CLI output can only be stale if the process itself is stale.
- `fail_closed_cap`: "StatusEndpoint health check; no direct trading impact" -- ACCURATE. Read-only data model, no mutating capability.
- `drift_metric`: "health_endpoint_latency_ms p99 < 100ms" -- NOT MEASURABLE until S8-008 provides HTTP endpoint. For scaffolding, this metric is vacuous.

---

## Summary

| Dimension | Status | Notes |
|-----------|--------|-------|
| AT-022 proof | CLAIMED_NOT_PROVEN | Data model correct; HTTP transport deferred to S8-008 |
| Fail-closed behavior | STRONG | 6 fail-closed paths, 4 tested |
| Test coverage of section-5 wrong impls | PARTIAL | `ok` toggle tested; `contract_version` value, `build_id` value, and ReduceOnly `is_trading_allowed` NOT tested |
| Scope accuracy | INACCURATE | Primary enforcement in `stoic-cli`, not in `crates/soldier_infra/src/lib.rs` |
| Premortem quality | HIGH | Thorough analysis, correct identification of AT-022 tension, proper debt tracking |
| Implementation quality | GOOD | Clean Python, proper error handling, no unwrap() equivalent, atomic state writes |

**5 P1 remediation items identified (R2-R5 test gaps, R1 deferred to S8-008).**

---

## R5 Remediation Update (2026-02-24)

- `GAP-S0-004-002` (`P1`, `TEST_FIX`) -> `FIXED`.
  - `test_status_command_behavior_runtime` now asserts `contract_version == "5.2"` on healthy and unhealthy status paths (`crates/soldier_infra/tests/test_phase0_runtime.rs:537-540`, `crates/soldier_infra/tests/test_phase0_runtime.rs:610-613`).
- `GAP-S0-004-003` (`P1`, `TEST_FIX`) -> `FIXED`.
  - `test_status_command_behavior_runtime` now asserts `build_id` value propagation on healthy and unhealthy paths (`crates/soldier_infra/tests/test_phase0_runtime.rs:533-536`, `crates/soldier_infra/tests/test_phase0_runtime.rs:606-609`).
- `GAP-S0-004-004` (`P1`, `TEST_FIX`) -> `FIXED`.
  - Added dedicated `test_health_command_behavior_runtime` to exercise `./stoic-cli health --format json` healthy/unhealthy behavior (`crates/soldier_infra/tests/test_phase0_runtime.rs:632-696`).
- `GAP-S0-004-005` (`P1`, `TEST_FIX`) -> `FIXED`.
  - Added explicit REDUCE_ONLY status assertions (`trading_mode=REDUCE_ONLY`, `is_trading_allowed=false`) in status coverage (`crates/soldier_infra/tests/test_phase0_runtime.rs:547-588`).

READY FOR SELF_REVIEW
