Review basis: STORY_SCOPE (Cycle 1)

# R3 Cross-Review: S0-003, S0-004, S0-005

**Reviewer**: Beta (R3A Cross-Reviewer)
**Date**: 2026-02-24
**Head commit**: 5bfc230

---

## S0-003 (Break-Glass Runbook + Drill) -- HIGH RISK

### Checklist

- [x] **AT causal proof**: CONFIRMED. `test_break_glass_kill_blocks_open_allows_reduce_runtime` (test_phase0_runtime.rs:315-358) asserts `reason="kill_mode_blocks_open"` (exit 1) and `reason="kill_mode_allows_risk_reduction"` (exit 0). These are Kill-specific reason codes, not generic rejects. The `_dispatch_decision` function (stoic-cli:884-896) returns these strings only when `mode == "KILL"`. This is genuine causal proof.
- [x] **AT semantic match**: N/A -- no formal AT-XXX claimed for this story.
- [x] **Premortem S4 decisions implemented as chosen**: PARTIALLY. File sentinel (preferred in S4) was NOT implemented; CLI command path was used instead. R1 correctly flags this as a mismatch. The CLI approach is arguably better (structured logging, atomic writes), but the S4 verification gate was not formally closed. AGREE with R1.
- [x] **Premortem S5 wrong impls blocked**: CONFIRMED. 8 of 9 wrong impls are blocked. The partial gap is the `simulate-close --dry-run` in REDUCE_ONLY being a drill-only path, not the real close path. AGREE with R1.
- [x] **Premortem S2 assumptions**: Assumptions 1, 2, 5 are validated by tests. Assumptions 3, 4, 6 are partially validated (process/document review only). AGREE with R1.
- [x] **Fail-closed on Missing/None**: CRITICAL ISSUE CONFIRMED. `_load_runtime_state` at stoic-cli:196-199 returns `_default_runtime_state()` which defaults to `trading_mode="ACTIVE"` when the file does not exist. This is **fail-OPEN** for the break-glass case. R1 correctly identifies this as the highest-severity finding.
- [ ] **Fail-closed on NaN/Inf**: N/A (Python string-based modes, not numeric).
- [ ] **Fail-closed on Negative**: N/A.
- [ ] **Fail-closed on Out-of-domain**: CONFIRMED. Unknown mode strings -> KILL (stoic-cli:165-166, 234-241). Unknown mode in `_dispatch_decision` -> `False, "unknown_mode"` (stoic-cli:896).
- [ ] **Fail-closed on Corrupt**: CONFIRMED. Unparseable JSON -> KILL (stoic-cli:203-209). Invalid shape -> KILL (stoic-cli:211-217). Schema mismatch -> KILL (stoic-cli:221-231).
- [ ] **Fail-closed on Narrowing casts**: N/A (Python, no integer narrowing).
- [ ] **Combinatorial coverage**: The `_dispatch_decision` function has 3 modes x N intents. Tests cover KILL+OPEN, KILL+REDUCE_ONLY. Missing: ACTIVE+OPEN (tested in test_policy_is_required_and_bound), REDUCE_ONLY+OPEN, REDUCE_ONLY+CLOSE, unknown_mode. Partially covered.
- [x] **Constants accuracy**: `RUNTIME_MODES` and `RUNTIME_STATE_SCHEMA_VERSION` are used consistently.
- [x] **Paper compliance**: PRD claims match reality for runbook/drill/log_excerpt artifacts.

### Verdict agreement/disagreement with R1

**AGREE** on all major findings:

1. AGREE: GATE GO (conditional) is correct. Core Kill enforcement is mechanically sound.
2. AGREE: R1 finding -- missing state file defaults to ACTIVE (stoic-cli:197-199). I verified: `_default_runtime_state()` on line 163 has `trading_mode: str = "ACTIVE"` as default. Line 198-199: `if not path.exists(): return default_state, []` -- returns ACTIVE with NO errors. This is fail-OPEN for break-glass. Severity HIGH.
3. AGREE: Drill version binding is missing (R2 remediation).
4. AGREE: Runbook snapshot drift (R3 remediation).
5. AGREE: Risk reduction verification uses drill-only `simulate-close` (R4 remediation).

**DISAGREE** on one point (minor):

- R1 says the e2e test `test_break_glass_command_path_runtime` tests "full lifecycle including state persistence across CLI invocations." This is CORRECT -- I verified the test seeds orders (line 506-525), calls `emergency kill` (line 534), then calls `status` (line 552) and `simulate-open` (line 570) as separate CLI invocations, all reading from the same `runtime_state` file. Each CLI invocation is a separate subprocess (via `run_cli()`), so state persistence IS tested across invocations. AGREE with R1 on this point after verification.

### Missed gaps

1. **NEW FINDING (MEDIUM): No test for state file deletion mid-session.** R1 identified this in the narrative (D3) but did not elevate it to a distinct remediation item. There should be a test that: (a) triggers `emergency kill`, (b) deletes the runtime state file, (c) calls `status` or `dispatch-check`, and (d) asserts the system does NOT revert to ACTIVE. Currently, this test does not exist. The `remove_if_exists` at line 632 is cleanup, not a mid-session test.

2. **NEW FINDING (LOW): `_dispatch_decision` does not load runtime state.** The `dispatch-check` subcommand takes `--mode` as a CLI argument (stoic-cli:914), NOT from the runtime state file. This means the test `test_break_glass_kill_blocks_open_allows_reduce_runtime` proves the decision logic in isolation but does NOT prove that the runtime state file is consulted during dispatch authorization. Only `test_break_glass_command_path_runtime` proves the full chain (emergency kill -> state file -> status reflects KILL -> simulate-open blocked). R1 noted this correctly ("Isolation: YES. This test isolates the dispatch authorization decision independent of runtime state") but did not flag the gap that dispatch-check does not read runtime state -- it relies on the caller to pass the correct mode.

3. **NEW FINDING (LOW): Race condition / TOCTOU in state file.** The `_load_runtime_state` function at stoic-cli:196 reads the file non-atomically. Between `path.exists()` (line 198) and `path.read_text()` (line 201), the file could be deleted. This would raise an exception caught at line 202, which falls through to KILL -- so the race is actually **fail-closed** for this specific path. However, the file could also be replaced with a valid ACTIVE state between the check and the read in the `_cmd_emergency` flow. R1 did not analyze this TOCTOU path. Impact: LOW because stoic-cli is single-process.

### Citation spot-checks (HIGH risk -- 3+ verified)

| # | R1 Claim | My Verification | File:Line | Match? |
|---|----------|-----------------|-----------|--------|
| 1 | `_default_runtime_state` defaults to ACTIVE (stoic-cli:165-166) | VERIFIED: `def _default_runtime_state(*, trading_mode: str = "ACTIVE"...)` at line 163. Line 165: unknown mode -> `mode = "KILL"`. But the **default parameter** is ACTIVE, not KILL. R1's line reference is slightly off (163, not 165-166 for the ACTIVE default) but the finding is correct. | stoic-cli:163 | YES (line off by 2) |
| 2 | `_dispatch_decision` returns `False, "unknown_mode"` at stoic-cli:896 | VERIFIED: Line 896: `return False, "unknown_mode"` -- exact match. | stoic-cli:896 | YES |
| 3 | Test `test_break_glass_kill_blocks_open_allows_reduce_runtime` asserts `reason="kill_mode_blocks_open"` at lines 331-333 | VERIFIED: Lines 331-333: `assert_eq!(blocked_payload["reason"], Value::String("kill_mode_blocks_open".to_string()))` | test_phase0_runtime.rs:331-333 | YES |
| 4 | Test `test_break_glass_command_path_runtime` seeds 3 orders and verifies flush to 0 | VERIFIED: Line 512 `--count 3`, line 531 `assert_eq!(pending_before_payload["pending_count"], Value::from(3))`, line 549 `assert_eq!(kill_payload["pending_orders"], Value::from(0))` | test_phase0_runtime.rs:512,531,549 | YES |
| 5 | `_load_runtime_state` returns ACTIVE with no errors on missing file | VERIFIED: Line 198-199: `if not path.exists(): return default_state, []` where `default_state = _default_runtime_state()` which has `trading_mode="ACTIVE"`. Empty errors list `[]` means no warning. | stoic-cli:197-199 | YES |

---

## S0-004 (Health + Owner Status Scaffolding)

### Checklist

- [ ] **AT causal proof**: PARTIAL. `test_status_command_behavior_runtime` (test_phase0_runtime.rs:426-487) asserts `ok`, `trading_mode`, `is_trading_allowed` for healthy (ACTIVE) and unhealthy (missing policy -> KILL) paths. These are value assertions, not just existence checks. However, `contract_version` and `build_id` are NOT asserted in the test output. AGREE with R1.
- [x] **AT-022 semantic match**: CONFIRMED CLAIMED_NOT_PROVEN. AT-022 in CONTRACT.md (line 4442-4447) requires: "When: `GET /api/v1/health`. Then: HTTP 200 and keys `ok`, `build_id`, `contract_version` exist with `ok == true`." The implementation is a CLI `./stoic-cli status` command, not an HTTP endpoint. R1's verdict of CLAIMED_NOT_PROVEN is **CORRECT**.
- [x] **Premortem S4 decisions**: Decision A (scaffolding only, no HTTP) implemented as chosen. AGREE with R1.
- [ ] **Premortem S5 wrong impls blocked**: `ok` hardcoded as const true -- BLOCKED (test asserts `ok=false` on unhealthy path, line 471). `contract_version` wrong string -- **NOT BLOCKED** (no `"5.2"` assertion in any test). `build_id` empty/placeholder -- **NOT BLOCKED** (test injects `STOIC_BUILD_ID` but never asserts it in output). `is_trading_allowed` wrong for ReduceOnly -- **NOT BLOCKED** (no explicit ReduceOnly test). AGREE with R1 on all four.
- [x] **Premortem S2 assumptions**: Assumption 1 (`contract_version == "5.2"`) partially validated -- `DEFAULT_CONTRACT_VERSION = "5.2"` at stoic-cli:35 but no test asserts output contains it. Assumption 3 (`TradingMode` enum) diverged -- Python strings, not Rust enum. AGREE with R1.
- [x] **Fail-closed**: All 6+ fail-closed paths verified. Missing policy -> KILL (stoic-cli:444). Corrupt state -> KILL. Path outside repo -> KILL. These are well-implemented.
- [ ] **Combinatorial coverage**: Only 2 of 3 modes tested (ACTIVE and KILL-via-missing-policy). REDUCE_ONLY `is_trading_allowed=false` is NOT tested. AGREE with R1 finding R5.
- [ ] **Constants accuracy**: `DEFAULT_CONTRACT_VERSION = "5.2"` (stoic-cli:35) -- matches CONTRACT.md. But no test verifies the output contains this value.
- [ ] **Paper compliance**: PRD claims "scaffolding only" -- matches implementation. But PRD `scope.touch` lists `crates/soldier_infra/src/lib.rs` which contains no S0-004 code. AGREE with R1 finding R6.

### AT-022 Semantic Match Section

I independently read AT-022 in CONTRACT.md at lines 4442-4447:

```
AT-022
- Given: service is running.
- When: `GET /api/v1/health`.
- Then: HTTP 200 and keys `ok`, `build_id`, `contract_version` exist with `ok == true`.
- Pass criteria: response matches required keys/values.
- Fail criteria: non-200 OR missing keys OR `ok != true`.
```

R1's verdict of **CLAIMED_NOT_PROVEN** is **CORRECT** because:
1. No HTTP endpoint exists -- the implementation is a CLI script.
2. No test issues an HTTP GET request.
3. The data model produces the correct fields, but the transport layer is missing.
4. The PRD explicitly defers HTTP to S8-008, making this a known, accepted gap.

### Verdict agreement/disagreement with R1

**AGREE** on all major findings:

1. AGREE: GATE YELLOW (CLAIMED_NOT_PROVEN) -- correct assessment.
2. AGREE: No `contract_version` assertion in test (R2).
3. AGREE: No `build_id` assertion in test (R3).
4. AGREE: No `health` subcommand test (R4). I confirmed: `test_status_command_behavior_runtime` uses `["status", "--format", "json"]` (line 436), not `["health", ...]`. No test function name contains "health" in test_phase0_runtime.rs.
5. AGREE: No explicit ReduceOnly `is_trading_allowed=false` test (R5).
6. AGREE: Scope file mismatch (R6).

### Missed gaps

1. **NEW FINDING (LOW): `_cmd_health` and `_cmd_status` are separate functions but only `_cmd_status` is tested.** The `_cmd_health` function (stoic-cli:343-366) and `_cmd_status` function (stoic-cli:418-461) produce different payloads. `_cmd_health` returns `ok`, `build_id`, `contract_version`, `errors`. `_cmd_status` returns those plus `trading_mode`, `is_trading_allowed`, `pending_orders`, etc. AT-022 targets `/health`, not `/status`. R1 flagged this as "no health subcommand test" but I want to emphasize: the two functions have different error handling paths and the health function is completely untested in the integration suite.

2. **NEW FINDING (LOW): `_detect_build_id` fallback chain.** At stoic-cli:118-131 (per R1), the function has a 3-step fallback: env var -> git SHA -> "unknown". When `build_id == "unknown"`, it adds an error (stoic-cli:354-355), which makes `ok=false`. This means a deploy without `STOIC_BUILD_ID` set and without git would report unhealthy. This is arguably fail-closed (good) but could cause surprise failures in container environments. R1 noted this (D3) but categorized it as informational. I agree with that severity.

### Citation spot-checks

| # | R1 Claim | My Verification | File:Line | Match? |
|---|----------|-----------------|-----------|--------|
| 1 | No `"5.2"` match in test_phase0_runtime.rs | VERIFIED: My grep for `5\.2` and `contract_version` in the test file returned zero matches for either string as an assertion value. | test_phase0_runtime.rs | YES |
| 2 | `_is_trading_allowed_mode` returns `mode == "ACTIVE"` | VERIFIED: stoic-cli line 323-324: `def _is_trading_allowed_mode(mode: str) -> bool: return mode == "ACTIVE"` | stoic-cli:323-324 | YES |
| 3 | Test asserts `ok=false` on missing policy path | VERIFIED: Line 471: `assert_eq!(unhealthy_payload["ok"], Value::Bool(false))` | test_phase0_runtime.rs:471 | YES |

---

## S0-005 (Machine Policy Loader Baseline)

### Checklist

- [x] **AT causal proof**: CONFIRMED. `test_policy_is_required_and_bound_runtime` (test_phase0_runtime.rs:87-151) has TRIP/NON-TRIP causality: valid policy -> exit 0, `ok=true`, `decision=ALLOW` (line 97-104) vs missing policy -> exit 1, `ok=false`, `reason="policy_validation_failed"` (lines 112-131). The only variable changed is the policy file path. Causal proof is strong.
- [x] **AT semantic match**: N/A -- no formal AT-XXX claimed.
- [x] **Premortem S4 decisions**: Decision A (Python loader is canonical strict validator) implemented as chosen. `_load_policy_with_validation` at stoic-cli:327-340 imports `policy_loader.py` and calls `load_policy()` + `validate_policy()`. CONFIRMED.
- [x] **Premortem S5 wrong impls blocked**: 7 of 9 blocked. "Loader accepts `{}`" -- blocked partially (mechanism proven by individual key tests but no explicit `{}` golden vector). "Meta-test calls loader with `--lenient`" -- BLOCKED (grep confirms no `--lenient` in meta-test invocation per R1). AGREE with R1.
- [x] **Premortem S2 assumptions**: All 7 assumptions validated or explicitly deferred. Assumption 7 (TOCTOU) correctly deferred. AGREE with R1.
- [x] **Fail-closed on Missing/None**: CONFIRMED. `_load_policy_with_validation` returns `(None, errors)` when policy is missing or invalid (stoic-cli:332-338). Callers then fail closed: `_cmd_dispatch_check` returns exit 1 (stoic-cli:902-912), `_cmd_status` forces `trading_mode="KILL"` (stoic-cli:444).
- [x] **Fail-closed on Corrupt**: CONFIRMED. Malformed JSON -> `load_policy()` raises exception -> caught at stoic-cli:332 -> returns `(None, errors)`. Test at test_phase0_runtime.rs:133-151 writes `"{ invalid_json: "` and asserts exit 1.
- [ ] **Combinatorial coverage**: Policy loader tests (~30 in test_policy_loader.py) cover missing keys, unknown keys, empty strings, wrong types, bool-as-int, zero/negative limits, missing file, invalid JSON, non-object root, invalid UTF-8. Good coverage.
- [x] **Constants accuracy**: N/A for this story.
- [x] **Paper compliance**: PRD claims match reality.

### Verdict agreement/disagreement with R1

**AGREE** on all major findings:

1. AGREE: GATE GO -- implementation is substantively correct.
2. AGREE: No explicit `validate_policy({})` test (R2) -- low risk because mechanism is proven.
3. AGREE: `--lenient` flag is low risk (R3) -- dev-only, documented, not passed in meta-test.
4. AGREE: Value-range validation deferred to S2.2 PolicyGuard (R4).
5. AGREE: TOCTOU deferred to Phase 1+ (R5).

### `--lenient` flag risk assessment

I verified `_load_policy_with_validation` at stoic-cli:327-340. This function does NOT accept a `--lenient` flag -- it always calls `validate_policy()` and returns `None` if errors exist. The `--lenient` flag is only on the `policy_loader.py` CLI interface, not on the `stoic-cli` integration path. So even if `policy_loader.py` is invoked with `--lenient` directly, the `stoic-cli` path that actually gates dispatch decisions ALWAYS uses strict validation. This makes the `--lenient` risk even lower than R1 assessed.

**Could `--lenient` be accidentally passed?** Only if someone invokes `policy_loader.py` directly (not through `stoic-cli`). The runtime enforcement path (`stoic-cli` -> `_load_policy_with_validation` -> `policy_loader.load_policy` + `policy_loader.validate_policy`) does not use CLI argument parsing at all -- it calls the functions directly. The `--lenient` flag can only weaken the standalone CLI invocation, not the runtime path. Risk: NEGLIGIBLE.

### Missed gaps

1. **NEW FINDING (LOW): Cross-story interaction -- policy missing + break-glass.** If `config/policy.json` is missing AND the operator triggers `emergency kill`, what happens? The `_cmd_emergency` function (stoic-cli:518) loads policy at line ~561 via `_load_policy_with_validation`. If policy is missing, the emergency command should still succeed (it writes runtime state, not policy). I traced the code: `_cmd_emergency` at stoic-cli:518 does NOT load policy -- it only loads runtime state. So emergency kill works even without a valid policy. This is correct behavior but R1 did not analyze this cross-story interaction.

### Citation spot-checks

| # | R1 Claim | My Verification | File:Line | Match? |
|---|----------|-----------------|-----------|--------|
| 1 | `_load_policy_with_validation` returns `(None, errors)` on validation failure | VERIFIED: stoic-cli:336-338: `if validation_errors: errors.extend(...); return None, errors` | stoic-cli:336-338 | YES |
| 2 | `test_policy_is_required_and_bound_runtime` tests valid, missing, and malformed policy | VERIFIED: Valid (lines 92-104), Missing (lines 106-131), Malformed (lines 133-151). All three cases present with causal assertions. | test_phase0_runtime.rs:87-151 | YES |
| 3 | Missing policy in `_cmd_dispatch_check` returns exit 1 with `reason="policy_validation_failed"` | VERIFIED: stoic-cli:901-912: `policy, policy_errors = _load_policy_with_validation(...)`, `if policy is None: ... return 1` with payload containing `reason: "policy_validation_failed"`. | stoic-cli:901-912 | YES |

---

## Systemic Patterns

1. **Test value-assertion gaps are consistent.** Across S0-003, S0-004, and S0-005, the tests assert structural behavior (exit codes, boolean ok/not-ok, reason codes) but often skip asserting specific field values (`contract_version`, `build_id`). This is a systemic pattern: tests prove the mechanism works but do not nail down the exact output contract. S0-004 is most affected.

2. **Fail-closed is strong on corrupt/invalid inputs, weak on missing inputs.** Corrupt JSON -> KILL is consistent across all stories. But missing state file -> ACTIVE (S0-003) is a notable exception. The principle "if uncertain, choose the safe/restrictive option" is violated for the missing-file case in runtime state loading.

3. **Python CLI instead of Rust.** All three stories' enforcement lives in `stoic-cli` (Python), not in Rust crates. The Rust integration tests call `stoic-cli` as a subprocess. This is not a defect but diverges from what the premortems assumed (Rust structs, serde, etc.). R1 correctly noted this across all three stories.

4. **No formal AT-XXX for S0-003 and S0-005.** Two of three stories have no `enforcing_contract_ats`. Only S0-004 claims AT-022, which is CLAIMED_NOT_PROVEN. This means the entire S0-003/004/005 batch has zero fully-proven ATs. The safety argument rests entirely on implementation tests.

---

## Summary

| Dimension | S0-003 | S0-004 | S0-005 |
|-----------|--------|--------|--------|
| Agree with R1 | YES | YES | YES |
| R1 Gate verdict | GO (conditional) | YELLOW (CLAIMED_NOT_PROVEN) | GO |
| My Gate verdict | AGREE | AGREE | AGREE |
| New findings | 3 | 2 | 1 |
| Missed gaps by R1 | 1 (mid-session state deletion not elevated to remediation) | 1 (health vs status function divergence) | 1 (cross-story policy+emergency interaction) |

**Totals:**
- AGREE with R1: 3/3 stories
- New findings: 6 total (1 MEDIUM, 5 LOW)
- Missed gaps: 3 total (all LOW -- R1 mentioned most of these in narrative but did not elevate)
- R1 quality: HIGH -- thorough, well-cited, correctly identified the critical fail-open finding in S0-003

**Pre-existing enforcement citations:**
- `stoic-cli:884-896` (`_dispatch_decision` -- fail-closed dispatch gate)
- `stoic-cli:196-199` (`_load_runtime_state` -- missing file default, the fail-open finding)
- `stoic-cli:327-340` (`_load_policy_with_validation` -- strict policy loading)
- `stoic-cli:323-324` (`_is_trading_allowed_mode` -- ACTIVE-only derivation)

**Pre-existing test citations:**
- `test_phase0_runtime.rs:315` (`test_break_glass_kill_blocks_open_allows_reduce_runtime`)
- `test_phase0_runtime.rs:490` (`test_break_glass_command_path_runtime`)
- `test_phase0_runtime.rs:426` (`test_status_command_behavior_runtime`)
- `test_phase0_runtime.rs:87` (`test_policy_is_required_and_bound_runtime`)
