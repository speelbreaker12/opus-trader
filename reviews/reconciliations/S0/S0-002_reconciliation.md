# S0-002 Reconciliation Audit (R1)

**Story**: S0-002 -- P0-C Keys & Secrets Baseline
**Auditor**: R1 Reconciliation Auditor (read-only)
**Date**: 2026-02-24
**Premortem**: `reviews/premortems/S0-002_premortem.md` (YELLOW stoplight)
**Status**: `passes: true` in `plans/prd.json`

---

## A) GATE RESULT

```
GATE: GO (conditional)
Reason: Implementation exceeds premortem predictions. The enforcement code
  (`stoic-cli` `_cmd_keys_check`) validates both `withdraw_enabled` and
  `transfer_enabled` fields, checks forbidden scopes, and verifies
  probe_results for withdrawal/transfer rejection. Tests construct
  adversarial probe fixtures and assert specific error content. The
  premortem's central weakness (probe provenance) remains accepted debt
  and was accurately predicted.
READ_ONLY_VIOLATION: NONE
```

**Conditions on GO**:
1. The `scopes: ["all"]` wrong-impl from premortem S5 row 2 is NOT blocked by the enforcement code (see Design Risk Note D1).
2. The `"withdraw"` scope is not checked as a forbidden scope string -- only `"transfer"` is (see Design Risk Note D2).
3. Probe provenance remains unverifiable by machine (accepted debt from premortem, confirmed here).

---

## B) AT AUDIT TABLE

No formal ATs (`enforcing_contract_ats: []`). Auditing the two `implementation_tests` as informal enforcement.

### B.1 — `test_api_keys_are_least_privilege_runtime`
**File**: `/Users/admin/Desktop/opus-trader/crates/soldier_infra/tests/test_phase0_runtime.rs`, lines 155-228

| Aspect | Finding |
|--------|---------|
| **What it does** | (1) Loads the baseline `key_scope_probe.json` and runs `keys-check --probe <path> --env STAGING` -- asserts exit 0 and `ok: true` (line 171-177). (2) Creates an adversarial probe with `withdraw_enabled: true` and `withdraw.result: "success"`, runs `keys-check`, asserts exit 1, `ok: false`, and that the errors array contains the string `"withdraw_enabled"` (lines 180-227). |
| **What it proves** | The `keys-check` command rejects a probe where `withdraw_enabled` is `true`. The assertion at line 224 checks for the *specific* error field name `"withdraw_enabled"`, confirming the enforcement path was the one that triggered. |
| **Causal proof?** | **PARTIAL-STRONG**. The test constructs a targeted fixture where only `withdraw_enabled` differs from valid, and asserts a specific error string mentioning `"withdraw_enabled"`. This is close to causal -- it isolates the `withdraw_enabled` check. However, the bad probe also has `withdraw.result: "success"` which would independently fail the `trade scope requires explicit forbidden withdrawal result` check (stoic-cli line 990-991). Two violation paths fire simultaneously; the test only asserts one. |
| **Fail-closed?** | **YES** -- the enforcement code at stoic-cli:972 uses `entry.get("withdraw_enabled") is not False`, which means any value other than literal `False` (including `None`, missing, `True`, `0`, `"false"`) triggers the error. This is a proper fail-closed check. |
| **Verdict** | **PASS** (with minor tightening opportunity noted in D3) |

### B.2 — `test_api_keys_transfer_privilege_rejected_runtime`
**File**: `/Users/admin/Desktop/opus-trader/crates/soldier_infra/tests/test_phase0_runtime.rs`, lines 231-285

| Aspect | Finding |
|--------|---------|
| **What it does** | Creates an adversarial probe with `transfer_enabled: true`, `scopes: ["read_account", "trade", "transfer"]`, and `transfer.result: "success"`. Runs `keys-check --probe <path> --env STAGING`, asserts exit 1, `ok: false`, and that the errors array contains the string `"transfer"` (lines 279-283). |
| **What it proves** | The `keys-check` command rejects a probe with transfer privileges. The fixture triggers *three* independent violation paths: (1) `transfer_enabled is not False` (stoic-cli:974), (2) `"transfer" in scopes_lower` (stoic-cli:979), (3) `transfer_result in {"success", "accepted"}` (stoic-cli:992-993). The assertion checks for the string `"transfer"` in errors, which any of these would satisfy. |
| **Causal proof?** | **PARTIAL** -- the test proves that *something* about the transfer configuration is rejected, but because three checks fire simultaneously, it does not isolate which specific enforcement gate caused the rejection. The assertion `contains("transfer")` is broad enough to match any of the three error messages. Ideally there would be three separate sub-tests, each triggering exactly one violation. |
| **Fail-closed?** | **YES** -- `transfer_enabled is not False` (stoic-cli:974) is fail-closed in the same way as `withdraw_enabled`. The scopes check (stoic-cli:979) is a blocklist approach, not an allowlist, which means it only catches the exact string `"transfer"`, not novel dangerous scopes (see D1). |
| **Verdict** | **PASS** (with tightening opportunities noted in D1, D3) |

### B.3 — Summary Table

| Test function | What it proves | Causal proof? | Fail-closed? | Verdict |
|---|---|---|---|---|
| `test_api_keys_are_least_privilege_runtime` | `withdraw_enabled != false` triggers rejection with specific error | Partial-strong (two violations fire, one asserted) | YES (stoic-cli:972 `is not False`) | PASS |
| `test_api_keys_transfer_privilege_rejected_runtime` | Transfer-capable probe is rejected; error mentions "transfer" | Partial (three violations fire, assertion matches any) | YES (stoic-cli:974 `is not False`; scopes blocklist) | PASS |

---

## C) PREMORTEM CROSS-REFERENCE

### C.1 — Section 2 Assumptions

| # | Assumption | Prediction | Reality | Status |
|---|-----------|-----------|---------|--------|
| 1 | Exchange key has least-privilege (no withdraw) | Test should assert `withdraw_enabled == false` | stoic-cli:972 enforces `withdraw_enabled is not False`; test at test_phase0_runtime.rs:224 asserts error contains `"withdraw_enabled"` | **CONFIRMED** |
| 2 | `key_scope_probe.json` was generated from actual API call, not hand-crafted | Premortem predicted this is unverifiable by test (blind) | The probe JSON (evidence/phase0/keys/key_scope_probe.json) includes `probe_results` with API call outcomes but **no cryptographic proof of provenance**. Tests only validate the JSON structure. Probe could be hand-crafted. | **CONFIRMED BLIND** (accepted debt) |
| 3 | JSON required fields are sufficient to prove least-privilege | Killed (accepted scope) in premortem | `_cmd_keys_check` validates `withdraw_enabled`, `transfer_enabled`, `scopes`, and `probe_results`. It does NOT validate presence of `env`, `exchange`, `key_id`, `timestamp_utc`, `operator` fields. | **PARTIALLY CONFIRMED** -- enforcement goes beyond simple field-presence but stops short of full schema validation |
| 4 | `docs/keys_and_secrets.md` covers all four required sections | Predicted blind -- needed manual review | File exists at `/Users/admin/Desktop/opus-trader/docs/keys_and_secrets.md` (5878 bytes). Contains: Key Types & Required Scopes (creation rules), Rotation Plan with cadence table + steps, Storage & Access section (where secrets live), Runtime Identity Enforcement + LIVE key protection. All four sections present with substantive content. | **CONFIRMED** |
| 5 | Runtime tests hit exchange API vs. static fixture | Premortem predicted Option B (static fixture validation) | **CONFIRMED Option B**: Tests construct JSON fixtures in-process (test_phase0_runtime.rs:181-198, 233-255) and invoke `stoic-cli keys-check` which parses JSON -- no live API calls | **CONFIRMED** |

### C.2 -- Section 4 Decisions

| Decision | Chosen option | Implemented? | Evidence |
|----------|--------------|-------------|----------|
| What constitutes "least privilege" | Option A: strict (trade + read-only, withdraw false, no transfer) | **YES** -- stoic-cli `_cmd_keys_check` (lines 970-998) checks: `withdraw_enabled is not False`, `transfer_enabled is not False`, `"transfer" in scopes`, withdrawal probe result must be "permission_denied" or similar, transfer probe must not show success | stoic-cli:970-998 |
| Tests hit real API or use mocks? | Option B (static JSON validation predicted) | **YES** -- tests construct JSON fixtures and pass them to the CLI. No live API. | test_phase0_runtime.rs:181-198, 233-255 |

### C.3 -- Section 5 Wrong Implementations

| Wrong impl | Predicted tightening | Actually blocked? | Evidence |
|---|---|---|---|
| Doc with section header but no rules | Tighten: must include scopes to enable/deny, who creates | **NOT AUTOMATICALLY BLOCKED** -- no automated doc content check exists. However, the actual document (`docs/keys_and_secrets.md`) contains substantive content: scope tables (lines 29-34), naming conventions, rotation steps (lines 94-101). Human review passed this. | Accepted gap -- inherent to documentation stories |
| Hand-crafted JSON with `scopes: ["all"]` passing | Tighten: test must assert scopes NOT contain "all", "withdraw", "transfer" | **PARTIALLY BLOCKED**: `"transfer"` is checked in scopes (stoic-cli:979), but `"all"` and `"withdraw"` are NOT checked as forbidden scope strings. A probe with `scopes: ["all"]` and `withdraw_enabled: false` and valid probe_results would pass if the probe_results fields are crafted correctly. | **GAP -- see D1** |
| `test_api_keys_are_least_privilege_runtime` only checks JSON structure, not values | Tighten: assert `withdraw_enabled == false` AND scopes subset of allowlist | **PARTIALLY BLOCKED**: `withdraw_enabled` is checked as `is not False` (stoic-cli:972). Scopes are checked via blocklist (`"transfer"` only), not an allowlist. | **GAP on allowlist -- see D1** |
| `test_api_keys_transfer_privilege_rejected_runtime` validates document, not key | Tighten: attempt API call with transfer intent | **NOT DONE** -- premortem predicted this as an accepted gap (Option B). Tests validate the probe JSON, not the actual key. | Accepted gap (consistent with premortem) |
| Rotation plan with no cadence/owner/procedure | Tighten: must include cadence, party, steps | **NOT AUTOMATICALLY BLOCKED** -- no automated check. Actual document has cadence table (lines 88-91: quarterly for STAGING, monthly for LIVE), owner column, and 7 rotation steps (lines 96-101). | Accepted gap -- doc content is substantive |

---

## D) DESIGN RISK NOTES

### D1 -- Scope blocklist vs. allowlist (LOW-MED)

The `_cmd_keys_check` function (stoic-cli:977-998) checks scopes using a **blocklist** approach: it only rejects `"transfer"` as a forbidden scope string. It does NOT check for:
- `"withdraw"` as a scope string (it only checks `withdraw_enabled` as a boolean field and the withdrawal probe result)
- `"all"` (a meta-scope that could grant all permissions)
- Any other novel dangerous scopes the exchange may add in the future

The premortem's wrong-impl #2 (S5 row 2) specifically predicted a probe with `scopes: ["all"]` as a wrong implementation. The enforcement code does not block this. A probe with `scopes: ["all"], withdraw_enabled: false, transfer_enabled: false` and carefully crafted `probe_results` (e.g., `withdraw.result: "permission_denied"`) would pass `keys-check`.

**Severity**: LOW-MED. The `probe_results` checks provide a second defense layer (withdrawal must show "permission_denied"), but the `"all"` scope is not caught at the scope level.

**Remediation**: Add `"withdraw"` and `"all"` to the forbidden scopes blocklist, or switch to an allowlist approach where `scopes` must be a subset of `{"read_account", "trade", "read_market_data", "public_market_data_only", "cancel_all"}`.

### D2 -- `"withdraw"` not in forbidden scopes (LOW)

While `withdraw_enabled` is correctly checked as a boolean, the string `"withdraw"` is not checked in the `scopes` array. An exchange could expose a key with `scopes: ["read_account", "trade", "withdraw"]` but `withdraw_enabled: false` (if the exchange has separate scope and feature flag semantics). The enforcement would pass because:
- `withdraw_enabled is not False` -> passes (it IS False)
- `"transfer" in scopes_lower` -> passes ("transfer" not present)
- The withdrawal probe result check only fires for `"trade"` scope keys, and the result could be crafted as "permission_denied"

This is a theoretical gap; exchange APIs typically don't have this inconsistency, but defense-in-depth would check the scope string too.

### D3 -- Test causality isolation (LOW)

Both tests trigger multiple violation paths simultaneously instead of isolating a single enforcement gate. This means if one enforcement check regresses (gets removed), the test could still pass because another check catches the same fixture. Ideally, each test would trigger exactly one violation and assert the corresponding specific error message.

### D4 -- No JSON schema validation in `keys-check` (LOW)

The `keys-check` command does not validate the presence of required fields (`env`, `exchange`, `key_id`, `timestamp_utc`, `operator`). It only checks privilege-related fields. The PRD acceptance criterion 5 requires "valid JSON with required fields" but `keys-check` only checks a subset. The PRD `verify` step uses `python -c "import json; json.load(open(...))"` which only validates JSON syntax, not field presence.

### D5 -- Probe provenance (MED, tracked in premortem)

The premortem's central weakness is confirmed: nothing prevents a hand-crafted `key_scope_probe.json` from passing all automated checks. The tests validate static JSON, not actual exchange API responses. The probe includes `probe_results` with plausible-looking API outcomes but these are self-reported claims with no external verification.

The actual probe JSON (`evidence/phase0/keys/key_scope_probe.json`) includes three environments (STAGING, PAPER, LIVE) with detailed probe results including identity checks, order placement results, revoked key tests, and withdrawal rejection. The content quality is high, but provenance remains unverifiable by machine. This matches the premortem's prediction exactly.

---

## E) REMEDIATION PLAN

| # | Finding | Severity | Remediation | Effort |
|---|---------|----------|-------------|--------|
| R1 | `scopes: ["all"]` passes enforcement (D1) | LOW-MED | Add `"all"` and `"withdraw"` to forbidden scopes check at stoic-cli:979, or switch to allowlist | XS |
| R2 | `"withdraw"` not in forbidden scopes (D2) | LOW | Add `"withdraw"` to blocklist at stoic-cli:979 (subsumed by R1) | XS |
| R3 | Tests trigger multiple violations simultaneously (D3) | LOW | Split into separate sub-tests, each with a single-violation fixture and exact error assertion | S |
| R4 | No field-presence validation in `keys-check` (D4) | LOW | Add required field check (`env`, `exchange`, `key_id`, `timestamp_utc`, `operator`) in `_cmd_keys_check`; or add JSON schema file as premortem S9 suggested | S |
| R5 | Probe provenance unverifiable (D5) | MED | Accepted debt per premortem. Future: require API call logs, signed timestamps, or CI-based probe execution | M (deferred) |
| R6 | No contract AT anchors (premortem S1 gap) | LOW | Add AT-P0C-01 and AT-P0C-02 to CONTRACT.md per premortem S6 plan | S (deferred) |

**Blocking remediations**: NONE. All findings are LOW or LOW-MED severity. The MED-severity probe provenance issue (R5) is accepted debt, consistent with the premortem's YELLOW stoplight assessment.

---

## F) SCOPE CHECK

| Scope file | Predicted in PRD/premortem | Exists? | Content quality |
|---|---|---|---|
| `docs/keys_and_secrets.md` | Yes (PRD `scope.touch[0]`) | YES (5878 bytes, last modified 2026-02-17) | **GOOD** -- Contains all four required sections: key creation rules with scope tables, rotation plan with cadence + steps, storage & access policy, runtime identity enforcement. Substantive content, not boilerplate. |
| `evidence/phase0/keys/key_scope_probe.json` | Yes (PRD `scope.touch[1]`) | YES (3164 bytes, last modified 2026-02-17) | **GOOD** -- Three environments (STAGING, PAPER, LIVE), all required fields present, detailed probe_results including identity checks, order placement, withdrawal rejection. All `withdraw_enabled: false`, all `transfer_enabled: false`. |
| `crates/soldier_infra/tests/test_phase0_runtime.rs` | Yes (implementation_tests host file) | YES (1255 lines) | **GOOD** -- Contains both claimed test functions plus additional Phase 0 tests. Tests use adversarial fixture construction and specific error assertions. |
| `stoic-cli` (enforcement code) | Implied (tests invoke it) | YES | **GOOD** -- `_cmd_keys_check` (stoic-cli:942-1010) implements multi-layered privilege validation. No `unwrap()` in production Python code (Python doesn't have unwrap). |

**unwrap() audit**: The `stoic-cli` is Python; `unwrap()` is a Rust concept and does not apply. The test file (`test_phase0_runtime.rs`) uses `unwrap()` at lines 95, 110, 138, 165, 206, 263, 460 -- these are all `.to_str().unwrap()` on path conversions or `parse_stdout_json` helpers. These are acceptable in test code (not production paths). The `expect()` calls in tests all have descriptive messages.

---

## Summary

The S0-002 implementation is **stronger than the premortem predicted**. Key findings:

1. **The enforcement code (`stoic-cli` `_cmd_keys_check`) is well-designed**: it checks `withdraw_enabled`, `transfer_enabled`, forbidden scopes, and probe_results with proper fail-closed semantics (`is not False`).

2. **The tests are functional but could be tighter**: they trigger multiple violations per fixture instead of isolating single enforcement gates. The assertions check for relevant error strings but don't prove exact single-gate causality.

3. **The premortem's predictions were accurate**: Option B (static JSON) was implemented, probe provenance is unverifiable by machine, documentation criteria are subjective. All three YELLOW-stoplight debt items are confirmed as present.

4. **One new finding not in the premortem**: the `scopes` blocklist approach misses `"all"` and `"withdraw"` as scope strings (D1/D2). This is a minor gap because the `probe_results` checks provide a second defense layer.

5. **Documentation quality is high**: `docs/keys_and_secrets.md` is not boilerplate -- it contains specific scope tables, rotation cadences, storage policies, and runtime enforcement rules.

---

## R5 Remediation Update (2026-02-24)

- `GAP-S0-002-001` (`P1`, `CODE_FIX`) -> `FIXED`.
  - `keys-check` now explicitly rejects `all`, `transfer`, `withdraw`, and `margin` scopes, closing the non-trade scope bypass path (`stoic-cli:996-1003`).
  - Added a hard fail when withdraw probe reports success (`stoic-cli:1006-1012`).
  - Added single-violation regression test `test_api_keys_all_scope_rejected_runtime` for `scopes=["all"]` (`crates/soldier_infra/tests/test_phase0_runtime.rs:309-368`).

READY FOR SELF_REVIEW
