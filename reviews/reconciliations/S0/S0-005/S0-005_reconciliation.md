# S0-005 Reconciliation Audit: P0-F Machine Policy Loader Baseline

**Auditor**: R1 Reconciliation Auditor
**Date**: 2026-02-24
**Story**: S0-005 (passes=true, enforcing_contract_ats=[], enforcement_point="")

---

## A) GATE RESULT

```
GATE: GO
Reason: Implementation is substantively correct. Policy loading is fail-closed in both
        Python and Rust paths. Schema validation is strict (rejects unknown keys, missing
        required fields, wrong types, zero/negative risk limits). The runtime binding is
        proven via stoic-cli dispatch-check which dynamically loads and validates the policy
        via STOIC_POLICY_PATH. Two debt items carry forward (no formal AT-XXX, no explicit
        empty-JSON-object test) but neither represents a live safety gap.
READ_ONLY_VIOLATION: NONE
```

---

## B) AT AUDIT TABLE

No formal AT-XXX IDs exist for this story. The two implementation tests serve as informal enforcement.

| Test function | What it proves | Causal proof? | Fail-closed? | Verdict |
|---|---|---|---|---|
| `tools/phase0_meta_test.py::test_machine_policy_loader_and_config` (line 479) | (1) `config/policy.json` exists and is valid JSON with required keys, (2) `fail_closed` is `true`, (3) PAPER env is non-trade-capable, (4) snapshot matches canonical policy file, (5) `policy_loader.py` invoked as subprocess exits 0 on canonical policy | YES -- invokes the real `policy_loader.py` as a subprocess (line 533-534), validates the canonical `config/policy.json` path (line 481), not a fixture. Exit code is checked (line 541). | YES -- any failure appends to errors list and causes meta-test to return 1 (line 874-878). | PASS |
| `crates/soldier_infra/tests/test_phase0_runtime.rs::test_policy_is_required_and_bound_runtime` (line 87) | (1) Valid policy + ACTIVE OPEN -> ALLOW (exit 0, decision=ALLOW), (2) Missing policy -> exit 1, reason=`policy_validation_failed`, errors mention "policy", (3) Malformed JSON policy -> exit 1, reason=`policy_validation_failed` | YES -- TRIP/NON-TRIP causality: the ONLY difference between the valid case (line 93-104) and the missing case (line 107-131) is the presence/absence of the policy file. The malformed case (line 134-151) writes invalid JSON to a temp file, proving parse failure is detected. | YES -- missing policy -> exit 1, `ok=false`, `reason="policy_validation_failed"` (line 113-131). Malformed policy -> exit 1, `ok=false` (line 140-151). No fallback to default policy. | PASS |
| `tests/phase0/test_policy_loader.py` (full suite, ~30 tests) | Comprehensive unit tests for `validate_policy()`: missing keys, unknown keys, empty policy_id, fail_closed must be true (not false/string/0/None/1), MARKET must be forbidden, bool-as-int rejected in risk_limits, zero/negative risk limits rejected, environment constraints (DEV/PAPER non-trade, LIVE trade-capable), unknown env entries flagged, allowed/forbidden overlap, load errors (missing file, invalid JSON, non-object root, invalid UTF-8), snapshot integrity, CLI strict/lenient behavior, absolute path protection, print flag | YES -- each test mutates exactly one field and checks for the specific error message. | YES -- validates that strict mode is the default (no --lenient), that lenient mode emits warnings, and that all error categories produce non-zero exit codes. | PASS |

**Coverage assessment**: The test suite is thorough. The main gap is the absence of a dedicated test for `validate_policy({})` (empty JSON object). However, `validate_policy({})` would hit the required-key check at `policy_loader.py:62-64` and produce 8 "missing required top-level key" errors, so this gap is theoretical rather than a live risk. The `TestMissingKeys::test_missing_required_key` test (line 183) proves the mechanism works for individual missing keys.

---

## C) PREMORTEM CROSS-REFERENCE

### S2 Assumptions

| # | Assumption | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `config/policy.json` has a defined schema with required fields that the strict loader validates against | VALIDATED | `policy_loader.py:18-27` defines `REQUIRED_TOP_LEVEL` with 8 keys. `validate_policy()` (line 59-163) checks each key's type and value. `test_policy_loader.py::TestMissingKeys` (line 182-196) and `TestFailClosedField` (line 203-232) confirm. |
| 2 | The policy path is bound at runtime (Rust reads from the same path Python validates) | VALIDATED | `stoic-cli:34` sets `DEFAULT_POLICY_PATH = ROOT / "config" / "policy.json"`. `stoic-cli:348,427,649,843,900` all read from `STOIC_POLICY_PATH` env var (defaulting to `config/policy.json`). `test_phase0_runtime.rs:89,95` uses `config/policy.json` and passes it via `STOIC_POLICY_PATH`. The `stoic-cli` is a Python script, not a compiled Rust binary -- it imports `policy_loader.py` via `_load_policy_loader_module()` (line 108-115), calling the same `load_policy()` + `validate_policy()` functions. Path binding is proven. |
| 3 | "Strict" means the loader rejects unknown fields | VALIDATED | `policy_loader.py:69-71` rejects unknown top-level keys. `policy_loader.py:99-101` rejects unknown environment entries. `policy_loader.py:151-153` rejects unknown risk_limits keys. `test_policy_loader.py:188-191` (unknown top-level), `test_policy_loader.py:313-317` (unknown env entry), `test_policy_loader.py:372-376` (unknown risk_limits key) all confirm. |
| 4 | The loader exits non-zero on ANY validation failure | VALIDATED | `policy_loader.py:224` returns `0 if args.lenient else 1` when errors exist. Default mode is strict (no `--lenient`). `test_policy_loader.py:60-69` confirms bad policy exits 1. CLI test `test_policy_loader.py:96-103` confirms absolute path rejected. |
| 5 | The Rust runtime refuses to start if policy is absent (or enters ReduceOnly) | VALIDATED | `test_phase0_runtime.rs:107-131` proves missing policy -> exit 1, `ok=false`, `reason="policy_validation_failed"`. `stoic-cli:650-663` (`_cmd_simulate_open`) returns exit 1 with `reason="policy_validation_failed"` when policy is None. `stoic-cli:443-444` (`_cmd_status`) forces `trading_mode = "KILL"` when policy is None. No fallback default policy exists. |
| 6 | Schema is forward-compatible / deny_unknown_fields | VALIDATED (with documented limitation) | Unknown keys are rejected at all levels (top-level, environments, risk_limits). Adding a new field to `config/policy.json` without updating `REQUIRED_TOP_LEVEL` in `policy_loader.py` will cause the new field to be flagged as unknown. This is fail-closed by design. Limitation: schema evolution requires lockstep update -- correctly documented as a design choice in premortem S4. |
| 7 | TOCTOU gap between Python validation and Rust consumption | DEFERRED (accepted) | Both the `stoic-cli` and the `policy_loader.py` are Python. The `stoic-cli` imports `policy_loader.py` and calls `load_policy()` + `validate_policy()` inline at runtime, not at CI-time. The TOCTOU gap is therefore narrower than assumed in the premortem -- there is no separate "CI-time validation" vs "Rust-time consumption". The policy is loaded and validated in the same process invocation. However, a separate Python meta-test (`phase0_meta_test.py`) does validate the file independently, creating a (benign) gap. Correctly deferred to Phase 1+ hardening. |

### S4 Decisions

| Decision | Chosen option | Implementation matches? | Evidence |
|----------|--------------|------------------------|----------|
| Schema strictness: minimal required schema + reject unknown | Option A | YES | `policy_loader.py:18-27` (REQUIRED_TOP_LEVEL), `policy_loader.py:69-71` (unknown keys rejected), `policy_loader.py:99-101` (unknown envs rejected), `policy_loader.py:151-153` (unknown risk_limits rejected) |
| Malformation: test multiple categories (not just syntax) | Option B | YES | `test_policy_loader.py` covers: missing required keys (line 183), unknown keys (line 188), empty strings (line 193), wrong types for fail_closed (line 203-228), bool-as-int in risk_limits (line 277), zero/negative risk limits (line 358-370), missing file (line 431), invalid JSON (line 435), non-object root (line 441), invalid UTF-8 (line 447). |
| Python loader is canonical strict validator; Rust test proves path binding | Option A | YES | `stoic-cli:108-115` imports and calls `policy_loader.py`. `test_phase0_runtime.rs:87-151` proves path binding via `dispatch-check` which routes through `stoic-cli:899-924` which calls `_load_policy_with_validation()`. |

### S5 Wrong Impls

| Wrong impl | Blocked? | Evidence |
|------------|----------|----------|
| Loader ignores file, always exits 0 | BLOCKED | `test_policy_loader.py:60-69` passes bad policy and asserts exit 1. `test_phase0_runtime.rs:107-131` passes missing policy path and asserts exit 1. |
| Loader parses JSON but does not validate schema (`{}` passes) | BLOCKED (partially) | `validate_policy()` checks REQUIRED_TOP_LEVEL at line 62-64. Empty `{}` would trigger 8 "missing required top-level key" errors. However, **no explicit test for `validate_policy({})` exists**. The mechanism is proven by individual missing-key tests (line 183-186), but a direct `{}` golden vector is absent. Minor gap. |
| Loader only rejects syntactically invalid JSON | BLOCKED | `test_policy_loader.py:60-69` passes structurally valid but semantically incomplete JSON (`{"policy_id": "X"}`) and asserts exit 1. |
| Loader catches validation error but exits 0 | BLOCKED | `test_policy_loader.py:60-69` asserts `result.returncode == 1`. `policy_loader.py:224` explicitly returns 1 when errors exist and not lenient. No bare `except` or error swallowing in the validation path. |
| Meta-test tests mock instead of real loader | BLOCKED | `phase0_meta_test.py:533-534` invokes `policy_loader.py` as a subprocess. Line 481 uses canonical `config/policy.json` path. |
| Meta-test calls loader with `--lenient` | BLOCKED | Grep for `--lenient` in `phase0_meta_test.py` returns zero matches. The meta-test invocation at line 533 does not pass `--lenient`. |
| Python validates but Rust ignores policy entirely | BLOCKED | `test_phase0_runtime.rs:87-151` proves that `dispatch-check` (which routes through `stoic-cli`) fails when policy is missing/malformed. The `stoic-cli` calls `_load_policy_with_validation()` before making dispatch decisions (line 900-912). |
| Meta-test validates fixture instead of canonical policy | BLOCKED | `phase0_meta_test.py:481` explicitly uses `root / "config" / "policy.json"` (the canonical path). |
| Loader validates schema but not value ranges | DEFERRED (documented) | `policy_loader.py:160-161` checks `value <= 0` for risk_limits (rejects zero and negative). But no upper-bound checks exist. Correctly documented as deferred to S2.2 PolicyGuard in premortem S10. |

---

## D) DESIGN RISK NOTES

### D1: The `--lenient` flag exists and weakens validation

`policy_loader.py:169-173` defines a `--lenient` flag that causes the loader to exit 0 even when validation fails. The flag includes a loud WARNING (`policy_loader.py:194-199`), and the meta-test does not pass it (confirmed by grep). However, the flag's existence creates a risk surface: a CI pipeline that accidentally passes `--lenient` would silently accept invalid policy.

**Risk level**: LOW. The flag is clearly documented as `[DEV ONLY]` in the help text. The meta-test explicitly does not use it. `test_policy_loader.py:72-82` proves lenient mode's behavior is tested and understood. Test at line 84-94 confirms the warning is emitted.

### D2: stoic-cli is Python, not Rust

The premortem assumed a Python-validates-at-CI-time / Rust-consumes-at-runtime split. In reality, `stoic-cli` is a Python script that imports `policy_loader.py` at runtime. This is actually *safer* than the assumed architecture: there is no cross-language boundary, no schema duplication risk, and the TOCTOU gap is within a single process. The Rust integration tests (`test_phase0_runtime.rs`) call `stoic-cli` as a subprocess, which means they exercise the full Python policy loading pipeline end-to-end.

### D3: `unwrap()` in test code only

The `unwrap()` calls in `test_phase0_runtime.rs` (lines 62, 72, 95, 110, 138, 165, 206, 263, etc.) are all in test code (`.to_str().unwrap()`, `parse_stdout_json()`, etc.). This is acceptable per CLAUDE.md guidelines: `unwrap()` is prohibited in production code but standard in tests. The `stoic-cli` (production Python) has no equivalent; all exceptions are caught and produce error payloads.

### D4: Risk limit validation has basic range checks

`policy_loader.py:158-161` rejects non-numeric, boolean, and non-positive (`<= 0`) values for risk limits. `_is_strict_numeric()` (line 50-56) also rejects NaN and Infinity. This provides basic protection. Upper-bound validation (e.g., `max_daily_loss_usd: 999999999`) is correctly deferred to PolicyGuard (S2.2) as noted in the premortem debt register.

### D5: No empty-object golden vector

The premortem S5 specifically identifies "loader accepts `{}` as input" as the most dangerous wrong-impl. While `validate_policy({})` would correctly fail (8 missing-key errors from `policy_loader.py:62-64`), there is no explicit test that calls `validate_policy({})` or passes `{}` as a file to the CLI. The `test_missing_required_key` test (line 183) removes a single key from a valid policy, which proves the mechanism but not the exact golden vector. The `must_be_valid_json()` function in `phase0_meta_test.py:88-99` also rejects empty objects at line 97-98, but this applies to evidence files, not to `validate_policy()` directly.

**Risk level**: LOW. The enforcement mechanism is proven to work. The gap is a missing golden vector, not a missing enforcement path.

---

## E) REMEDIATION PLAN

| # | Item | Severity | Remediation | Owner |
|---|------|----------|-------------|-------|
| R1 | No formal AT-XXX in CONTRACT.md for P0-F | MEDIUM | Add AT-XXX anchors to CONTRACT.md for: (1) valid policy exits 0, (2) malformed policy exits non-zero, (3) runtime path binding. Populate `enforcing_contract_ats` in prd.json. | Deferred to contract maintenance pass (tracked in premortem S10 debt) |
| R2 | No explicit `validate_policy({})` test | LOW | Add a test in `test_policy_loader.py` that calls `validate_policy({})` and asserts at least 8 "missing required top-level key" errors. Also add a CLI test that passes `{}` as a file and asserts exit 1. | Story implementor or follow-up |
| R3 | `--lenient` flag exists | INFORMATIONAL | Flag is clearly documented as dev-only and is tested. No action required. Consider removing the flag entirely in a future hardening pass if it causes confusion. | No action needed |
| R4 | Value-range validation deferred | MEDIUM | PolicyGuard (S2.2) must validate ranges at runtime. Track as explicit requirement in S2.2 premortem. | S2.2 implementor (already tracked in premortem S10 debt) |
| R5 | TOCTOU gap for Phase 1+ | LOW | Rust runtime should re-validate or checksum policy at load time for production. Currently mitigated by single-process architecture (stoic-cli is Python, not separate Rust binary). | Phase 1+ (already tracked in premortem S10 debt) |

---

## F) SCOPE CHECK

| Scope file | In-scope? | Verified? |
|-----------|-----------|-----------|
| `config/policy.json` | YES | Read and audited. 41-line JSON with required keys, environments, order types, risk limits, fail_closed=true. |
| `tools/policy_loader.py` | YES | Read and audited. 233-line strict loader with `REQUIRED_TOP_LEVEL`, `validate_policy()`, `main()` with `--lenient` / `--print` / `--allow-absolute` flags. No bare except. All exceptions propagate to non-zero exit. |
| `tools/phase0_meta_test.py` | YES | Read and audited. `test_machine_policy_loader_and_config()` at line 479 validates canonical `config/policy.json`, invokes `policy_loader.py` as subprocess, checks snapshot integrity. Does not pass `--lenient`. |
| `tests/phase0/test_machine_policy_loader_and_config.md` | YES | Read and audited. 26-line markdown describing test purpose, procedure, and pass criteria. Matches implementation. |
| `crates/soldier_infra/tests/test_phase0_runtime.rs` | YES | `test_policy_is_required_and_bound_runtime` at line 87 audited. Tests valid, missing, and malformed policy via `dispatch-check`. TRIP/NON-TRIP causality proven. |
| `tests/phase0/test_policy_loader.py` | IN SCOPE (not listed in prd.json touch but directly tests policy_loader.py) | Read and audited. ~30 tests covering happy path, fail-closed default, missing/malformed keys, fail_closed field, MARKET forbidden, bool-as-int, environment constraints, order type overlap, risk limit boundaries, snapshot integrity, load errors. |
| `stoic-cli` | IN SCOPE (runtime binding target) | Read and audited. Python script that imports policy_loader.py at runtime. All command paths that touch trading decisions call `_load_policy_with_validation()`. Missing/invalid policy forces KILL or exit 1. |

**Out-of-scope files verified NOT touched**: No production Rust code in `crates/soldier_core/src/` or `crates/soldier_infra/src/` was modified for this story. `crates/soldier_infra/src/config.rs` contains `MaxPolicyAgeSec` (line 98, 240, 333) which is related but is a separate concern (Appendix A defaults, not policy loading).

---

READY FOR SELF_REVIEW
