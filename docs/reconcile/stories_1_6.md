# Reconciliation Report: Stories S0-000 through S0-005 (Slice 0)

**Audit date:** 2026-02-17
**Branch:** `reconcile/stories_1_6_contract_alignment`
**Baseline tag:** `pre_prd_fix_story1-6`
**Auditor:** Opus 4.6 (team: reconcile-s0, 3 parallel auditors + lead)
**Authority chain:** CONTRACT.md v5.2 > IMPLEMENTATION_PLAN.md > PRD > code

---

## A) STOPLIGHT Summary

| Story  | Verdict       | Color  |
|--------|---------------|--------|
| S0-000 | KEEP          | GREEN  |
| S0-001 | KEEP          | GREEN  |
| S0-002 | KEEP          | GREEN  |
| S0-003 | KEEP          | GREEN  |
| S0-004 | KEEP          | YELLOW |
| S0-005 | PATCH (PRD)   | YELLOW |

**Overall: YELLOW** — No contract violations. Two stories need PRD metadata fixes (doc-drift only + AT over-claim). No code changes required. No reverts. No quarantine.

---

## B) Reconciliation Table

| Story | Current PRD Claim | Contract Target | Actual Behavior | Verdict | Required Patch | Tests/Evidence |
|-------|-------------------|-----------------|-----------------|---------|----------------|----------------|
| S0-000 | Launch policy doc; `passes=true`; no ATs; no enforcement point | P0-A: `docs/launch_policy.md` with instruments/venues, position limits, order rate, environments | `docs/launch_policy.md` exists (6.3KB), covers instruments, venues, position limits, order rate, 4 environments. Snapshot at `evidence/phase0/policy/launch_policy_snapshot.md`. Config at `config/policy.json` with machine-readable risk limits. Runtime test validates policy binding + fail-closed on missing. | **KEEP** | None — PRD correctly has no ATs (P0-A has no formal AT). Consider adding `implementation_tests` reference to `test_trading_policy.rs` (already listed). | `config/policy.json`, `docs/launch_policy.md`, `evidence/phase0/policy/launch_policy_snapshot.md` |
| S0-001 | Env isolation doc; `passes=true`; no ATs | P0-B: `docs/env_matrix.md` with environment separation | `docs/env_matrix.md` exists (4.5KB), lists DEV/STAGING/PAPER/LIVE with exchange accounts, key permissions, secret storage. Snapshot at `evidence/phase0/env/env_matrix_snapshot.md`. | **KEEP** | None — contract satisfied. PRD correctly has no ATs. | `docs/env_matrix.md`, `evidence/phase0/env/env_matrix_snapshot.md` |
| S0-002 | Keys & secrets doc; `passes=true`; no ATs | P0-C: `docs/keys_and_secrets.md` + least-privilege proof (JSON probe) | `docs/keys_and_secrets.md` exists (5.9KB) with key creation rules, rotation plan, least-privilege. `evidence/phase0/keys/key_scope_probe.json` exists. **Bonus:** Runtime tests `test_api_keys_are_least_privilege_runtime` and `test_api_keys_transfer_privilege_rejected_runtime` prove fail-closed key scope checking. | **KEEP** | None — exceeds contract requirements. PRD under-claims by not referencing runtime tests. Minor: consider adding runtime test refs to `implementation_tests`. | `docs/keys_and_secrets.md`, `evidence/phase0/keys/key_scope_probe.json`, `test_phase0_runtime.rs::test_api_keys_*` |
| S0-003 | Break-glass runbook + drill; `passes=true`; no ATs | P0-D: `docs/break_glass_runbook.md` + drill evidence | `docs/break_glass_runbook.md` exists (6.5KB) with STOP TRADING steps, risk reduction verify, escalation. `evidence/phase0/break_glass/drill.md` + `log_excerpt.txt` + `runbook_snapshot.md` all exist. **Bonus:** Runtime tests `test_break_glass_kill_blocks_open_allows_reduce_runtime` and `test_break_glass_command_path_runtime` prove Kill mode blocks OPEN, allows risk reduction, emergency kill flushes queue. | **KEEP** | None — exceeds contract. PRD under-claims by not referencing runtime tests. | `docs/break_glass_runbook.md`, `evidence/phase0/break_glass/*`, `test_phase0_runtime.rs::test_break_glass_*` |
| S0-004 | Health endpoint scaffolding; `passes=true`; AT-022; enforcement: StatusEndpoint | P0-E: Minimal health output (`ok`, `build_id`, `contract_version`) + owner status (`trading_mode`, `is_trading_allowed`) | **No HTTP endpoint.** Implementation is CLI-based: `stoic-cli status --format json` produces JSON with `ok`, `build_id`, `contract_version`, `trading_mode`, `is_trading_allowed`. Test `test_status_command_behavior_runtime` proves: healthy → ok=true/ACTIVE/allowed, unhealthy (missing policy) → ok=false/KILL/not-allowed. | **KEEP** | PRD acceptance text honestly says "scaffolding — full AT-022 enforcement in S8-008". This is valid: P0-E contract says "minimal health output", AT-022 says "GET /api/v1/health" which is the full HTTP endpoint (later story). **Fix:** Clarify in PRD that this story provides the *data model* + *CLI path*, not the HTTP endpoint. AT-022 reference should be annotated as "partial/scaffolding" not "enforcing". | `test_phase0_runtime.rs::test_status_command_behavior_runtime`, `docs/health_endpoint.md` |
| S0-005 | Policy loader; `passes=true`; AT-040, AT-341; enforcement: PolicyGuard | P0-F: Machine-readable policy + strict loader. AT-040: gate fail-closed on missing params. AT-341: safety defaults (instrument_cache_ttl_s=3600, mm_util_kill=0.95) | `config/policy.json` exists with machine-readable policy. `tools/policy_loader.py` validates strictly, fails closed on missing/malformed. Test `test_policy_is_required_and_bound_runtime` proves: valid policy → ALLOW, missing → fail-closed, malformed → fail-closed. **BUT: AT-040 and AT-341 are over-claims.** AT-341 is about Rust runtime applying safety defaults for `instrument_cache_ttl_s`/`mm_util_kill` — config/policy.json doesn't contain these fields. AT-040 is about runtime gates failing closed on missing parameters (like `dd_limit` in §5.2) — not about policy file validation. | **PATCH (PRD only)** | **Remove AT-040 and AT-341** from `enforcing_contract_ats`. P0-F has no formal contract AT. The story is correctly implemented but over-claims AT coverage that belongs to later runtime stories (S1-010 for instrument_cache_ttl_s, later slices for gate fail-closed). **Also:** change `enforcement_point` from "PolicyGuard" to "" (this is a config/tooling story, not a PolicyGuard gate). | `config/policy.json`, `tools/policy_loader.py`, `test_phase0_runtime.rs::test_policy_is_required_and_bound_runtime` |

---

## C) Conflict List

| # | Contract Clause/AT | Implementation Mismatch | Severity | Story |
|---|-------------------|-------------------------|----------|-------|
| 1 | AT-040 (gate fail-closed on missing params) | S0-005 claims this AT but implements Python config validation, not Rust runtime gate behavior. AT-040 is about gates (PolicyGuard, EvidenceGuard) failing closed at tick time when a required parameter is missing. | **LOW** — no unsafe behavior, just wrong PRD metadata | S0-005 |
| 2 | AT-341 (CSP safety defaults: instrument_cache_ttl_s=3600, mm_util_kill=0.95) | S0-005 claims this AT but config/policy.json doesn't contain these fields. AT-341 is about Rust runtime applying Appendix A defaults. | **LOW** — no unsafe behavior, just wrong PRD metadata | S0-005 |
| 3 | AT-022 (GET /api/v1/health HTTP endpoint) | S0-004 references AT-022 but delivers CLI-based status, not HTTP. PRD honestly says "scaffolding". No false claim of full enforcement, but the `enforcing_contract_ats` array includes AT-022 which could mislead automated checks. | **LOW** — honest scaffolding claim, but metadata could confuse tooling | S0-004 |

**No HIGH or CRITICAL conflicts found.** All stories implement useful, safe behavior. Issues are metadata/traceability only.

---

## D) Minimal Next Actions (ordered, smallest first)

### 1. Fix S0-005 PRD AT mappings (5 min)
```
In plans/prd.json, for S0-005:
- Set "enforcing_contract_ats": []
- Set "enforcement_point": ""
- Optionally add a comment in description noting "P0-F has no formal AT"
```

### 2. Fix S0-004 PRD AT annotation (5 min)
```
In plans/prd.json, for S0-004:
- Change "enforcing_contract_ats": ["AT-022"] to:
  "enforcing_contract_ats": ["AT-022"]  (keep, but add)
  "primary_owner_for": []  (remove AT-022 — this is scaffolding, not ownership)
- OR: Keep AT-022 in enforcing_contract_ats but add a field like
  "at_coverage": "partial/scaffolding" to distinguish from full enforcement
```

### 3. Enrich PRD implementation_tests for S0-002 and S0-003 (5 min)
```
S0-002: Add to implementation_tests:
  "crates/soldier_infra/tests/test_phase0_runtime.rs::test_api_keys_are_least_privilege_runtime"
  "crates/soldier_infra/tests/test_phase0_runtime.rs::test_api_keys_transfer_privilege_rejected_runtime"

S0-003: Add to implementation_tests:
  "crates/soldier_infra/tests/test_phase0_runtime.rs::test_break_glass_kill_blocks_open_allows_reduce_runtime"
  "crates/soldier_infra/tests/test_phase0_runtime.rs::test_break_glass_command_path_runtime"
```

### 4. Verify gates pass after PRD edits (2 min)
```bash
./plans/verify.sh quick
```

---

## E) Summary

- **0 stories need code changes** — all code is contract-compliant
- **0 stories need revert** — nothing contradicts the contract
- **0 stories need quarantine** — nothing is orphaned
- **1 story needs PRD metadata fix** (S0-005: remove over-claimed ATs)
- **1 story needs PRD annotation** (S0-004: clarify scaffolding vs full AT-022)
- **2 stories under-claim** (S0-002, S0-003: runtime tests exist but aren't referenced)

The implementation is solid. Phase 0 stories deliver what the contract requires and more. The only issues are traceability metadata in the PRD.
