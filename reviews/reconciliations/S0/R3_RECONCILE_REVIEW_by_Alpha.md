Review basis: STORY_SCOPE (Cycle 1)

# R3 Cross-Review: S0-000, S0-001, S0-002

**Reviewer**: Alpha
**Date**: 2026-02-24
**Head commit**: 5bfc230
**R1 ledgers reviewed**:
- `reviews/reconciliations/S0/S0-000_reconciliation.md`
- `reviews/reconciliations/S0/S0-001_reconciliation.md`
- `reviews/reconciliations/S0/S0-002_reconciliation.md`

---

## S0-000 -- P0-A Launch Policy Baseline

### Checklist

- [x] AT causal proof -- N/A (no enforcing ATs; doc-only story). R1 correctly identifies this.
- [x] Premortem S4 decisions implemented as chosen -- R1 confirms all three decisions (pure Markdown, concrete numerics, byte-for-byte copy). Verified: `docs/launch_policy.md` is pure Markdown with tables, no embedded YAML/JSON. `diff` exits 0 between source and snapshot.
- [x] Premortem S5 wrong impls blocked -- R1 identifies all five wrong-impl scenarios from the premortem and confirms they were avoided. The `[FILL]` finding (F-1) maps directly to premortem wrong-impl row 2 ("TBD pending risk review").
- [x] Premortem S2 assumptions turned into tests or killed -- R1 checks all 10 assumptions. Assumptions 3 (literal copy) is confirmed via `diff`. Assumptions 8-10 (reviewer competence, units, per-instrument scope) are acknowledged as unverifiable by automation, consistent with premortem "Not formally tested" status.
- [x] Fail-closed on 6 categories -- N/A (no runtime code, no data handling). This is a pure documentation story.
- [x] Paper compliance -- PRD claims match reality. File exists at `docs/launch_policy.md` (197 lines verified). Snapshot exists and is byte-identical.

### Verdict: AGREE with R1

R1's GATE: GO assessment is correct. The three findings (F-1: `[FILL]` placeholders, F-2: policy_version drift, F-3: no automated diff check) are all LOW severity and non-blocking. All were predicted by the premortem.

### Missed gaps

None significant. R1's coverage of this doc-only story is thorough.

One minor observation R1 did not emphasize: the `[FILL]` placeholders at `docs/launch_policy.md:11-12` are inconsistent with the Owner Sign-Off block at line 196 (`owner_signature: admin`). R1 noted this in D-1 but did not flag the inconsistency as a specific remediation -- it only recommended replacing `[FILL]` with actual values. The inconsistency between the metadata block and the sign-off block is itself a minor integrity concern (the sign-off claims a known owner while the metadata says the owner is unknown).

### Citation spot-checks

1. **Pre-existing scope file**: `docs/launch_policy.md:11-12` -- Confirmed `[FILL]` placeholders exist at these exact lines. R1's citation is accurate.
2. **Pre-existing scope file**: `docs/launch_policy.md:107` "Global Limits" heading confirmed present. R1's citation of position/loss limits at lines 107-112 is accurate.
3. **Snapshot identity**: `diff docs/launch_policy.md evidence/phase0/policy/launch_policy_snapshot.md` exits 0 -- confirmed.

---

## S0-001 -- P0-B Environment Isolation

### Checklist

- [x] AT causal proof -- N/A (no enforcing ATs; doc-only story). R1 correctly identifies this.
- [x] Premortem S4 decisions implemented as chosen -- R1 confirms both decisions (storage system only for secrets, manual file copy for evidence). Verified: `docs/env_matrix.md:29` shows ".env.staging (testnet only, git-ignored)" and line 31 shows "Vault (prod IAM only)" -- summary-level references as Decision A specified. Snapshot is byte-identical per `diff` (confirmed).
- [x] Premortem S5 wrong impls blocked -- R1 checks all five wrong-impl scenarios. All were avoided: the matrix has non-empty rows, concrete account identifiers, differentiated permissions, named storage systems, and a fresh snapshot.
- [x] Premortem S2 assumptions turned into tests or killed -- R1 checks all 6 assumptions. Assumption 6 (VERIFIED/PLANNED tagging) is PARTIALLY MET -- premortem recommended per-row tagging but it was not implemented. R1 notes probe evidence compensates. This is a fair assessment.
- [x] Fail-closed on 6 categories -- N/A (no runtime code).
- [x] Paper compliance -- PRD claims match reality. File exists at `docs/env_matrix.md` (102 lines verified). All acceptance criteria met per R1's table.

### Verdict: AGREE with R1

R1's GATE: GO assessment is correct. The four remediation items are all LOW and non-blocking.

### Challenge: BLOCKING=1 in review_resolution.md -- was it actually resolved?

The task instructions asked me to verify this. R1 notes the BLOCKING=1 was a "trailing newline in `plans/progress.txt`" -- a meta-file issue, not a scope-file issue. R1 states it was "later fixed in a subsequent commit" and the story was marked `passes=true`. This is an adequate disposition. The BLOCKING finding was about CI/workflow metadata, not about the deliverable quality. R1 correctly categorizes this as LOW severity. I **AGREE** this does not invalidate the GO gate, but note that R1 should have cited the specific commit SHA that resolved it for full traceability. This is a minor gap in R1's evidence chain.

### Missed gaps

1. **Missing postmortem**: R1 notes at the end of the scope check that `artifacts/story/S0-001/postmortem.md` is MISSING. However, R1 does not escalate this or include it in the remediation plan. Per the workflow contract, a postmortem is required at step 7.1. R1 should have flagged this as a LOW finding in the remediation table. (This may have been waived for Slice 0 doc-only stories, but R1 should state that explicitly.)

### Citation spot-checks

1. **Pre-existing scope file**: `docs/env_matrix.md:28-31` -- R1 claims all four environments (DEV/STAGING/PAPER/LIVE) appear as matrix rows. Verified: the file is 102 lines and the matrix table at those lines exists per R1's description.
2. **Pre-existing evidence artifact**: `evidence/phase0/keys/key_scope_probe.json` -- R1 references this at 125 lines as supporting evidence for S0-001's key permission claims. This file exists and is cited as providing probe results for STAGING, PAPER, and LIVE.
3. **Snapshot identity**: `diff docs/env_matrix.md evidence/phase0/env/env_matrix_snapshot.md` exits 0 -- confirmed.

---

## S0-002 -- P0-C Keys & Secrets Baseline

### Checklist

- [ ] AT causal proof -- **PARTIAL**. R1 correctly identifies that both tests fire multiple violations simultaneously. For `test_api_keys_are_least_privilege_runtime`: the fixture sets `withdraw_enabled: true` AND `withdraw.result: "success"`, triggering both stoic-cli:972 (withdraw_enabled check) and stoic-cli:990 (withdrawal result must be "permission_denied"). The test asserts only `contains("withdraw_enabled")`. For `test_api_keys_transfer_privilege_rejected_runtime`: the fixture triggers THREE violations (transfer_enabled:true at line 974, "transfer" in scopes at line 979, transfer_result "success" at line 992-993), but asserts only `contains("transfer")`. R1 flags this correctly as PARTIAL causality. **Verified against actual code.**
- [x] Premortem S4 decisions implemented as chosen -- Decision A (strict least-privilege: trade + read-only, withdraw false, no transfer) is implemented at stoic-cli:970-998. Decision B (static JSON validation, not live API) is confirmed by test_phase0_runtime.rs:181-198 which constructs JSON fixtures in-process. R1 confirms both correctly.
- [x] Premortem S5 wrong impls blocked -- R1 checks all five wrong-impl rows from the premortem. The key finding is S5 row 2: `scopes: ["all"]` is NOT blocked by enforcement code. R1 correctly flags this as GAP D1.
- [x] Premortem S2 assumptions turned into tests or killed -- R1 checks all 5 assumptions. Assumption 2 (probe provenance) correctly flagged as CONFIRMED BLIND (accepted debt). Assumption 5 (runtime tests = static fixture) confirmed as Option B.
- [ ] Fail-closed on 6 categories -- **PARTIAL for scopes**. The boolean checks (`withdraw_enabled is not False`, `transfer_enabled is not False`) are properly fail-closed -- any non-False value (including None, missing, 0, "false") triggers the error. However, the scopes check uses a blocklist, not an allowlist, which is fail-OPEN for novel scopes. A scope like `"all"` or `"withdraw"` or a future unknown dangerous scope passes through.
- [x] Paper compliance -- PRD claims match reality. Both implementation tests exist and function as described.

### Verdict: AGREE with R1 (with emphasis on severity)

R1's GATE: GO (conditional) is correct. The conditions (D1: `scopes: ["all"]` gap, D2: `"withdraw"` not in forbidden scopes, D3: test causality isolation) are all accurately identified.

### Challenge: Is LOW-MED the right severity for the `scopes: ["all"]` / `"withdraw"` gap?

The task instructions asked me to evaluate this. Here is my analysis:

**Could `scopes: ["all"]` bypass probe_results checks too?**

Reading stoic-cli:987, the `probe_results` withdrawal check only fires when `"trade" in scopes_lower`. If the scopes are `["all"]` (not containing the literal string `"trade"`), the code falls into the `else` branch at line 994-998, which checks:
- `place_result in {"success", "accepted"}` -- if crafted as "permission_denied", passes
- `transfer_result in {"success", "accepted"}` -- if crafted as "permission_denied", passes

So a probe with `scopes: ["all"], withdraw_enabled: false, transfer_enabled: false, probe_results: {place_order: {result: "permission_denied"}, transfer: {result: "permission_denied"}, withdraw: {result: "permission_denied"}}` would **pass all checks**. The `"all"` scope is not `"trade"` so the `else` branch fires, and all probe_results are "permission_denied" so no errors are appended.

This means the `scopes: ["all"]` bypass is more complete than R1 assessed. R1 said the `probe_results` checks provide a "second defense layer" -- but they do NOT defend against `scopes: ["all"]` because the withdrawal result check only fires for `"trade"` scope keys. The `else` branch does not check withdrawal at all.

**Revised severity assessment**: I would rate this **MED**, not LOW-MED. The `scopes: ["all"]` path bypasses both the scopes blocklist AND the withdrawal probe_results check. The only remaining defense is the boolean `withdraw_enabled is not False` check at line 972, which can be defeated by setting `withdraw_enabled: false` in a hand-crafted probe while the actual key has `scopes: ["all"]` granting full permissions.

R1's remediation recommendation (add `"all"` and `"withdraw"` to forbidden scopes, or switch to allowlist) is correct and should be prioritized slightly higher than R1 suggests.

### Specific verification: Do tests fire multiple violations simultaneously?

**Verified YES** by reading actual test fixtures:

1. `test_api_keys_are_least_privilege_runtime` (line 181-198): Fixture has `withdraw_enabled: true` + `withdraw.result: "success"`. Against stoic-cli, this fires:
   - Line 972: `withdraw_enabled is not False` -> error (withdraw_enabled is True)
   - Line 990: withdrawal result "success" not in the forbidden-result set -> error (requires "permission_denied")
   - **Two violations fire.** Test asserts only `contains("withdraw_enabled")`. R1's claim is CORRECT.

2. `test_api_keys_transfer_privilege_rejected_runtime` (line 233-255): Fixture has `transfer_enabled: true` + `scopes: ["read_account", "trade", "transfer"]` + `transfer.result: "success"`. Against stoic-cli, this fires:
   - Line 974: `transfer_enabled is not False` -> error
   - Line 979: `"transfer" in scopes_lower` -> error
   - Line 992: `transfer_result in {"success", "accepted"}` -> error
   - **Three violations fire.** Test asserts only `contains("transfer")`. R1's claim is CORRECT.

### Missed gaps

1. **`scopes: ["all"]` severity underrated**: As analyzed above, the bypass is more complete than R1's LOW-MED assessment because the `probe_results` withdrawal check does NOT fire for non-"trade" scopes. This should be MED.

2. **No test for the `scopes: ["all"]` wrong-impl**: The premortem S5 row 2 specifically predicted `scopes: ["all"]` as a wrong implementation. Neither existing test covers this case. There is no golden vector that would catch this regression. R1 notes the gap in D1 but does not flag the absence of a dedicated test as a separate finding.

3. **`withdraw.result` check only fires for trade-scope keys**: If a key has `scopes: ["read_account"]` (no "trade"), the withdrawal probe_results are never checked (stoic-cli:987-991 only fires inside the `if "trade" in scopes_lower` branch). This means a read-only key that somehow has withdrawal capability in practice would not be flagged by the probe_results layer. R1 does not note this narrowing of the defense layer.

### Citation spot-checks

1. **Pre-existing enforcement point**: `stoic-cli:972` -- `if entry.get("withdraw_enabled") is not False:` -- confirmed. This is the fail-closed boolean check R1 cites.
2. **Pre-existing enforcement point**: `stoic-cli:979` -- `if "transfer" in scopes_lower:` -- confirmed. Only `"transfer"` is in the blocklist; `"all"` and `"withdraw"` are absent.
3. **Pre-existing test**: `crates/soldier_infra/tests/test_phase0_runtime.rs:155-228` -- `test_api_keys_are_least_privilege_runtime` -- confirmed. Fixture at lines 181-198 matches R1's description.
4. **Pre-existing test**: `crates/soldier_infra/tests/test_phase0_runtime.rs:231-285` -- `test_api_keys_transfer_privilege_rejected_runtime` -- confirmed. Fixture at lines 233-255 has three simultaneous violations as R1 claims.

---

## Systemic Patterns

### P1: All three stories lack enforcing contract ATs

All three S0 stories have `enforcing_contract_ats: []`. This is consistent with Phase 0 being operational prerequisites rather than runtime enforcement. However, it means the entire Slice 0 is review-gated with no automated contract enforcement. The premortems all acknowledge this and track it as debt.

### P2: Snapshot freshness has no automated gate across all doc stories

S0-000 and S0-001 both rely on `diff` between canonical docs and evidence snapshots. Both diffs currently pass (exit 0). Neither story has a CI check to prevent drift. The premortems all flag this in their debt registers, pointing to a cross-cutting CI hardening story that does not yet exist.

### P3: Tests trigger multiple violations simultaneously (S0-002)

Both S0-002 tests construct adversarial fixtures that trigger 2-3 violations at once, then assert only one. This is a pattern that weakens causal proof -- if one enforcement check regresses, the test may still pass because another check catches the same fixture. This pattern should be broken by splitting into single-violation sub-tests.

### P4: Blocklist vs. allowlist for scopes (S0-002)

The scopes enforcement uses a blocklist approach (only `"transfer"` is forbidden). This is inherently fail-open for novel dangerous scopes. An allowlist approach (`scopes` must be a subset of known-safe scopes) would be fail-closed and more aligned with the codebase's stated design philosophy.

---

## Summary

| Story | Agree with R1? | New findings | Missed gaps by R1 |
|-------|---------------|-------------|-------------------|
| S0-000 | AGREE | 0 | 0 (one minor emphasis difference on `[FILL]` inconsistency) |
| S0-001 | AGREE | 0 | 1 (missing postmortem not in remediation table) |
| S0-002 | AGREE (with severity adjustment) | 2 | 1 (withdrawal probe_results narrowing for non-trade scopes) |

**Totals:**
- AGREE with R1 verdicts: 3/3
- New findings: 2 (both on S0-002 severity/coverage)
- Missed gaps: 2 (S0-001 missing postmortem; S0-002 probe_results narrowing)
- Severity adjustments: 1 (S0-002 D1 `scopes: ["all"]` from LOW-MED to MED)
