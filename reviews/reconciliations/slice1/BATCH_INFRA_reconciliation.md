---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v1.x (original)
  phase_equivalent: R1
artifact_type: evidence_ledger_batch
scope: S1-001, S1-008, S1-009, S1-010
---

# INFRA BATCH RECONCILIATION AUDIT
## Stories: S1-001, S1-008, S1-009, S1-010
**Branch**: main | **HEAD**: 1b85f2522c3ee0b9e6af2349a26f9c0f40c98976
**NO_PRIOR_POSTMORTEM** (for all 4 stories)
**READ-ONLY INTEGRITY**: PASS (no workspace modifications)

---

# ============================================================
# STORY: S1-001 — Workspace scaffolding
# ============================================================

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT GREEN. All structural artifacts exist and workspace builds.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-905 | §0.X Repository Layout | Cargo.toml:1-6 (workspace members list) | Structural: `crates/soldier_core/` and `crates/soldier_infra/` exist; Cargo.toml lists both in `[workspace] members` | Yes — directory existence + workspace member parse | N/A (structural) | Yes — AT-901 tightens: invalid crate manifests would fail `cargo test --workspace` | Yes | **PROVEN** |
| AT-901 | §0.X Repository Layout | plans/verify.sh:1-5 (delegates to verify_fork.sh) | Structural: verify.sh exists, is executable, delegates to verify_fork.sh which runs `cargo test --workspace` (step 15, line 632: `bash "$ROOT/plans/lib/rust_gates.sh"`) | Yes — exit code 0 confirms workspace builds | N/A (structural) | Yes — verify.sh is not vacuous; it runs a comprehensive verification pipeline including cargo test | Yes (Decision A: S1-001 ensures verify.sh exists) | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Rust toolchain on PATH | AT-901 (cargo test exits 0) | PASS — workspace builds (Cargo.toml:1-6 valid) |
| 2 | plans/verify.sh exists | AT-901 | PASS — plans/verify.sh:1-5 exists and delegates correctly |
| 3 | Empty lib.rs sufficient | AT-901 | PASS — lib.rs files are not empty (contain module declarations), but still scaffold-level; `cargo test --workspace` passes |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| verify.sh scope | A — S1-001 creates verify.sh | Yes | plans/verify.sh:1-5 exists. Note: it delegates to plans/verify_fork.sh (comprehensive pipeline), not a minimal `cargo test --workspace` wrapper. This exceeds the premortem's expectation but is not wrong — it is strictly more thorough. |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-905: Create dirs but empty Cargo.toml (no [package]/[lib]) | Yes | AT-901 tightens: cargo test --workspace requires valid manifests | Yes — `crates/soldier_core/Cargo.toml:1-4` has `[package]` with name/version/edition; same for `crates/soldier_infra/Cargo.toml:1-4` |
| AT-901: verify.sh contains `exit 0` only | Yes | verify_fork.sh:632 runs `bash "$ROOT/plans/lib/rust_gates.sh"` which invokes cargo test | Yes — verify.sh is not vacuous |

## D) DESIGN RISK NOTES

- **INFO**: verify.sh delegates to verify_fork.sh which is a comprehensive multi-gate pipeline (700+ lines). This far exceeds the premortem's expectation of "a single `cargo test --workspace` invocation with `set -euo pipefail`." Not a problem — the contract requires verify.sh to run cargo test, and it does (among many other things).
- **INFO**: `crates/soldier_core/src/lib.rs:3-7` already declares modules (`execution`, `idempotency`, `recovery`, `risk`, `venue`), indicating S1-001 was implemented alongside later stories. The scaffold is no longer empty but remains valid.
- **INFO**: `crates/soldier_infra/src/lib.rs:3-7` declares modules (`bootstrap`, `config`, `deribit`, `store`, `wal`), also showing post-scaffold growth.

## E) REMEDIATION PLAN

```
[INFO] verify.sh is more comprehensive than premortem predicted — no action needed.
[INFO] lib.rs files contain module declarations from later stories — expected and correct.
```

No P0/P1/P2 issues found.

## F) SCOPE CHECK

| File (premortem §0) | Exists? | Notes |
|---------------------|---------|-------|
| Cargo.toml | Yes | Cargo.toml:1-6 — workspace with 2 members |
| .gitignore | Yes | .gitignore:1-33 — includes `target/` (addresses failure mode #5) |
| crates/soldier_core/Cargo.toml | Yes | crates/soldier_core/Cargo.toml:1-12 |
| crates/soldier_core/src/lib.rs | Yes | crates/soldier_core/src/lib.rs:1-11 |
| crates/soldier_infra/Cargo.toml | Yes | crates/soldier_infra/Cargo.toml:1-12 |
| crates/soldier_infra/src/lib.rs | Yes | crates/soldier_infra/src/lib.rs:1-11 |

Scope drift: None. All predicted files exist. Additional module files inside crates are from later stories (S1-002, S1-010, etc.), not S1-001 scope drift.

```
READY FOR SELF_REVIEW
```

---

# ============================================================
# STORY: S1-008 — OrderSize discovery
# ============================================================

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT GREEN. Discovery document exists with contract-aligned content.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-277 | §1.0 Dispatcher Rules | None (discovery story) | docs/order_size_discovery.md exists; line 58: "AT-277: option uses amount=qty_coin, perp uses amount=qty_usd; option qty_usd unset; mismatches rejected." | N/A — discovery doc, not enforcement | N/A | Yes — report includes per-instrument-kind field population table (lines 36-42) | Yes | **DEFERRED** (enforcement in S1-004/S1-005) |
| AT-920 | §1.0 Dispatcher Rules | None (discovery story) | docs/order_size_discovery.md exists; line 59: "AT-920: contracts/amount mismatch beyond tolerance → Rejected(ContractsAmountMismatch), dispatch count 0, RiskState::Degraded." | N/A — discovery doc, not enforcement | N/A | Yes — report includes tolerance formula (line 48), mismatch rejection (line 70), and explicit handoff note for S1-007 | Yes | **DEFERRED** (enforcement in S1-007) |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Codebase has some OrderSize logic | Report content review | PASS — report correctly identifies "None" (docs/order_size_discovery.md:10: "Crates were reset to empty scaffolding") and proceeds with gap analysis |
| 2 | CONTRACT.md §1.0 is stable | Report references contract anchors | PASS — report references AT-277, AT-920, and cites contract fields explicitly |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Report format: High-level summary (Option A) | A — high-level with gap list | Yes | docs/order_size_discovery.md:61-73 (gap list), lines 76-88 (required tests table), lines 92-110 (minimal diff). Matches "high-level summary with explicit gap list." |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-277: Omit per-instrument-kind population rules | Yes (content) | docs/order_size_discovery.md:36-42 — per-instrument-kind canonical field table | Yes — table enumerates option/linear_future vs perpetual/inverse_future |
| AT-920: Mention mismatch in passing without detail | Yes (content) | docs/order_size_discovery.md:44-49 — full contracts/amount consistency section with formula, tolerance, epsilon | Yes — details the full check, not just a passing mention |

## D) DESIGN RISK NOTES

- **INFO**: The report correctly identifies "Everything is a gap" (line 63) since crates were reset. This is expected for a discovery story against a clean slate.
- **INFO**: Report lists 9 required tests for S1-004 (lines 76-88), which provides strong traceability for the implementation story.

## E) REMEDIATION PLAN

```
[INFO] Discovery doc complete — all contract fields enumerated, gaps identified, tests proposed.
[INFO] No enforcement in this story — all AT enforcement deferred to S1-004/S1-005/S1-007.
```

No P0/P1/P2 issues found.

## F) SCOPE CHECK

| File (premortem §0) | Exists? | Notes |
|---------------------|---------|-------|
| docs/order_size_discovery.md | Yes | 111 lines, covers OrderSize struct, canonical unit rules, gaps, required tests |

Scope drift: None.

```
READY FOR SELF_REVIEW
```

---

# ============================================================
# STORY: S1-009 — Dispatcher mapping discovery
# ============================================================

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT GREEN. Discovery document exists with contract-aligned content.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-277 | §1.0 Dispatcher Rules | None (discovery story) | docs/dispatch_map_discovery.md exists; line 51: "AT-277: option uses amount=qty_coin (coin), perp uses amount=qty_usd (USD); option qty_usd unset; mismatches rejected" | N/A — discovery doc | N/A | Yes — report enumerates per-instrument-kind outbound amount field (lines 26-33) and edge cases in gaps (lines 56-67) | Yes | **DEFERRED** (enforcement in S1-005) |
| AT-920 | §1.0 Dispatcher Rules | None (discovery story) | docs/dispatch_map_discovery.md exists; line 52: "AT-920: contracts/amount mismatch beyond tolerance → Rejected(ContractsAmountMismatch), dispatch count 0, RiskState::Degraded" | N/A — discovery doc | N/A | Yes — report details tolerance formula (lines 37-38), mismatch check flow (lines 82-89), and proposed tests | Yes | **DEFERRED** (enforcement in S1-007) |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Codebase has dispatch logic | Report content review | PASS — report correctly says "None" (docs/dispatch_map_discovery.md:10-11) and provides gap analysis |
| 2 | CONTRACT.md §1.0 Dispatcher Rules stable | Report references anchors | PASS — report references AT-277, AT-920 with full contract citation |
| 3 | S1-008 and S1-009 have clear scope boundaries | Scope guard in reports | PASS — S1-008 covers OrderSize struct fields; S1-009 covers dispatcher outbound mapping |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Scope boundary with S1-008 | A — clean separation | Yes | docs/dispatch_map_discovery.md:5-6 scopes to "Dispatcher amount mapping for Deribit requests"; docs/order_size_discovery.md:5 scopes to "OrderSize struct, sizing invariants" |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-277: Omit edge cases (zero qty_coin for options, both fields populated for perps) | Partially | docs/dispatch_map_discovery.md:63 lists edge cases as wrong impl concern, but gap list (lines 56-67) includes "Rejection for invalid index_price <= 0" without explicitly enumerating all edge case scenarios per instrument_kind | Partial — edge cases are acknowledged but not exhaustively listed in a per-kind table |
| AT-920: Omit full check-flow tracing | Yes | docs/dispatch_map_discovery.md:109-117 — S1-007 section details full check flow | Yes |

## D) DESIGN RISK NOTES

- **P2**: The premortem §5 identifies "Report lists which amount field to send per instrument_kind but omits edge cases" as a wrong impl. The report does mention edge cases (index_price <= 0 on line 67) but doesn't have a comprehensive per-kind edge case table as the tightening suggests.

## E) REMEDIATION PLAN

```
[INFO] Discovery doc complete — dispatcher mapping rules, mismatch rejection, reduce_only all covered.
[INFO] No enforcement in this story — AT enforcement deferred to S1-005/S1-007.
[PRD_FIX] GAP-009-1: P2 — Per-instrument-kind edge case table could be more exhaustive.
```

## F) SCOPE CHECK

| File (premortem §0) | Exists? | Notes |
|---------------------|---------|-------|
| docs/dispatch_map_discovery.md | Yes | 127 lines |

Scope drift: None.

```
READY FOR SELF_REVIEW
```

---

# ============================================================
# STORY: S1-010 — Appendix A config defaults
# ============================================================

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

---

# SUMMARY

| Story | ATs | Verdicts | Blockers | Top Priority Fix |
|-------|-----|----------|----------|-----------------|
| S1-001 | AT-905, AT-901 | PROVEN, PROVEN | None | None |
| S1-008 | AT-277, AT-920 | DEFERRED, DEFERRED | None (discovery only) | None |
| S1-009 | AT-277, AT-920 | DEFERRED, DEFERRED | None (discovery only) | GAP-009-1 (P2) |
| S1-010 | AT-341, AT-040, AT-424, AT-970, AT-971 | PROVEN, WEAK_PROOF, PROVEN, PROVEN, PROVEN | GAP-010-1 (P1) | AT-040 Err path needs end-to-end test |
