# Contract Review: Phase R5 Remediation Diff

**Reviewer:** contract-review skill (claude-opus-4-6)
**Date:** 2026-02-21
**Branch:** recon/S5-004
**Scope:** Unstaged working tree changes (crates/ + plans/prd.json + plans/review_logged.sh)

---

## Contract Review Findings

### HIGH: `CIGate` is not a valid `enforcement_point` value -- PRD schema check fails

**File:** plans/prd.json (S1-013 story, line ~1768)
**Contract Ref:** CLAUDE.md enforcement_point validation rule; `plans/prd_schema_check.sh` line 185
**Category:** Execution

**What changed:** GAP-013-1 changed `enforcement_point` from `"DispatcherChokepoint"` to `"CIGate"` for story S1-013 (PR merge-readiness automation gate).

**Violation:** The valid `enforcement_point` values are defined in both CLAUDE.md and `prd_schema_check.sh` as: `PolicyGuard|EvidenceGuard|DispatcherChokepoint|WAL|AtomicGroupExecutor|StatusEndpoint`. The value `CIGate` is not in this enum. Running `bash plans/prd_schema_check.sh` produces:

```
PRD schema violations:
S1-013: enforcement_point must be a known enforcement point when set
```

**Exploit scenario:** The PRD schema check is a CI gate. With `CIGate` as the value, `prd_schema_check.sh` fails, blocking all PRD-dependent CI flows. This is not a fail-open risk (it fails closed by blocking CI), but it blocks the verify pipeline and prevents any story from passing the PRD schema gate.

**Fix (actionable):** Either:
1. Set `enforcement_point` to `""` (empty string, allowed by the schema for stories without a runtime enforcement point), since S1-013 is a CI/workflow script, not a runtime guard. OR
2. Add `CIGate` to the valid enforcement_point enum in both `prd_schema_check.sh` (line 185) and CLAUDE.md if this is an intentional new enforcement category.

Option 1 is the safer fix because S1-013 (`pre_pr_review_gate.sh`) is not a runtime enforcement point -- it runs in CI, not in the trading loop.

**Evidence:** `bash plans/prd_schema_check.sh` returns exit code 5 with the violation message above.

---

## Summary

- **Production code changes:** One file modified -- `crates/soldier_core/tests/common/mod.rs` -- import cleanup only (removed duplicate imports and removed `PricerSide` which was consolidated into `Side` in a prior story). No production logic changed; this is a test helper file.
- **Test additions:** 8 new tests across 5 test files:
  1. `test_expiry_no_retry_loop_after_positions_clear` -- enhanced with GAP-012-3 comments and `restart_required` assertion (AT-962)
  2. `test_at960_classify_lifecycle_error_idempotent` -- new (GAP-012-2, AT-960)
  3. `test_default_instrument_cache_ttl_is_3600` -- new (GAP-003-1, Appendix A)
  4. `test_stale_access_produces_cache_ttl_breach_event` -- new (GAP-006-1, VR-013)
  5. `test_instrument_metadata_uses_get_instruments` -- new (GAP-002-1, AT-333)
  6. `test_missing_replay_window_hours_applies_default_48` -- new (GAP-010-3, AT-341)
  7. `test_all_config_params_fail_closed_when_missing_without_default` -- new (GAP-010-1, AT-040)
  8. `test_empty_json_fails_deserialization` -- new (GAP-011-1)
- **PRD changes:**
  - GAP-007-2: `UnitMismatch` renamed to `ContractsAmountMismatch` -- **CORRECT**, matches CONTRACT.md section 1.0 and the Rust `RejectReasonCode::ContractsAmountMismatch` enum variant.
  - GAP-013-1: `DispatcherChokepoint` changed to `CIGate` -- **BREAKS PRD SCHEMA CHECK** (see HIGH finding above).
  - GAP-011-2: `implementation_tests` populated with `crates/soldier_infra/tests/test_deribit_instrument.rs` -- **CORRECT**, file exists and contains relevant tests.
  - GAP-010-2: `scope.create` changed from `config/` to `crates/soldier_infra/src/config.rs` -- **CORRECT**, file exists at that path.
  - Unicode normalization: em-dashes, section signs, arrows normalized from multi-byte to escaped unicode -- cosmetic, no semantic change.
- **Fail-open patterns in production code:** NONE. The only production-adjacent change is the test helper import cleanup, which removes dead imports.
- **Shell script changes:** `plans/review_logged.sh` has zsh portability fixes (`${var^}` replaced with `ucfirst()`, `${var,,}` replaced with `lcase()`), and `--files` mode for codex tool is now correctly rejected instead of silently falling through. These are correctness improvements, not safety regressions.
- **All 8 new tests pass** (verified via `cargo test`).

### Test Causality Assessment

| Test | Proves Causality? | Notes |
|------|-------------------|-------|
| `test_expiry_no_retry_loop_after_positions_clear` | Yes | Asserts Terminal class + DoNotRetry + restart_required=false (three separate properties) |
| `test_at960_classify_lifecycle_error_idempotent` | Partial | Proves function purity but AT-960 also requires "no extra dispatch" and "ledger consistency" which this test cannot verify at the unit level. Acceptable as a unit-level complement to integration tests. |
| `test_default_instrument_cache_ttl_is_3600` | Yes | Tests boundary behavior (3600s=Healthy, 3601s=Degraded) and asserts the numeric constant |
| `test_stale_access_produces_cache_ttl_breach_event` | Yes | Verifies fresh=no-breach, stale=exactly-one-breach with correct fields |
| `test_instrument_metadata_uses_get_instruments` | Yes | Constructs realistic venue input shape, asserts correct InstrumentKind derivation |
| `test_missing_replay_window_hours_applies_default_48` | Yes | Asserts resolve_config_value(ReplayWindowHours, None) = 48.0 |
| `test_all_config_params_fail_closed_when_missing_without_default` | Yes | Exhaustive -- tests every ConfigParam variant + count guard against new variants |
| `test_empty_json_fails_deserialization` | Yes | Proves required fields are enforced at the serde level |

No fail-open illusions detected in the test additions.
