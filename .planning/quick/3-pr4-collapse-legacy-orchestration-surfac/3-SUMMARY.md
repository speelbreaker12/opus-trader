# Quick Task 3: PR4 — Collapse Legacy Orchestration Surface

**Status:** Complete
**Date:** 2026-03-05
**Commits:** eb91e42, 7f24175, cbc908d

## What was done

### Task 1: Delete orphaned file + remove evaluate alias (eb91e42)
- `git rm engine_parity_tests.rs` — 768-line dead file, never compiled (shadowed by `#[path]`)
- Removed `evaluate()` method from `ExecutionEngine` (passthrough to `decide()`, zero callers)
- Fixed `#[path]` module name: `engine_parity_tests` → `engine_decision_tests`

### Task 2: Clean up legacy parity helpers (7f24175)
- Deleted `legacy_open_decision()` and `legacy_pipeline_decision()` helper functions
- Deleted `execution_engine_evaluate_alias_matches_decide` test
- Removed parity assertions from 5 tests (legacy_book, legacy var, assert_eq)
- Renamed 3 tests to drop "legacy" from names
- Removed 6 now-unused imports
- Updated module doc comment

### Task 3: Add gate-fallback test + obsidian status (cbc908d)
- Added `open_runtime_unknown_liquidity_detail_falls_back_to_gate_reject_codes` test
- Updated obsidian status: all 4 PRs marked Done, Upgrade 1B complete

## Verification

- `cargo test -p soldier_core --lib engine_decision_tests` — 15 tests pass (14 existing + 1 new)
- `plans/lint_execution_facade.sh` — passed
- `verify.sh quick` — core checks pass (flaky timeouts on unrelated recon tests)
- All mechanical proof checks pass:
  - Zero legacy types in `api.rs`
  - Zero legacy types in `tests/`
  - Zero legacy orchestration function calls outside `execution/` (except 1 doc comment)
  - 30 engine type usages in integration tests (non-zero, as expected)

## Net impact

- **-731 lines** (855 removed, 124 added)
- **No production logic changes** (except removing unused `evaluate` alias)
- **+1 test** (gate-fallback coverage)
