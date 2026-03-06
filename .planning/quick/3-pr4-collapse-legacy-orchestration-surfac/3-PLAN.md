# Quick Task 3: PR4 — Collapse Legacy Orchestration Surface

**Created:** 2026-03-05
**Status:** Executed (cleanup-only scope)

**Scope note:** This quick task covered the PR 172 cleanup slice only.
It did **not** collapse the remaining OPEN-vs-pipeline orchestration duplication or remove the WAL-shim path.

## Task 1: Delete orphaned test file + remove evaluate alias

**Files:**
- `crates/soldier_core/src/execution/engine_parity_tests.rs` (DELETE)
- `crates/soldier_core/src/execution/engine.rs` (EDIT)

**Action:**
1. `git rm` the orphaned `engine_parity_tests.rs` (768 lines, never compiled)
2. Remove `evaluate()` alias (lines 265-271) from `engine.rs`
3. Fix `#[path]` module name: `engine_parity_tests` → `engine_decision_tests`

**Verify:** `cargo check -p soldier_core` succeeds

**Done:** Orphaned file gone, evaluate alias removed, module name correct

## Task 2: Clean up legacy parity helpers in engine_decision_tests.rs

**Files:**
- `crates/soldier_core/src/execution/engine_decision_tests.rs` (EDIT)

**Action:**
1. Delete `legacy_open_decision()` and `legacy_pipeline_decision()` helper functions
2. Delete `execution_engine_evaluate_alias_matches_decide` test
3. Remove legacy parity assertions (`legacy_book`, `legacy` var, `assert_eq!(delegated, legacy)`) from 5 tests
4. Rename 3 test functions (drop "legacy" from names)
5. Remove now-unused imports
6. Update module doc comment

**Verify:** `cargo test -p soldier_core --lib` succeeds

**Done:** No legacy parity helpers remain; tests assert engine behavior directly

## Task 3: Add gate-fallback coverage test + update obsidian status

**Files:**
- `crates/soldier_core/src/execution/engine_decision_tests.rs` (EDIT)
- `obsidian/Upgrades for AI/1/Status 2026-03-05.md` (EDIT)

**Action:**
1. Add `open_runtime_unknown_liquidity_detail_falls_back_to_gate_reject_codes` test
2. Update obsidian status to reflect PR3+PR4 complete

**Verify:** `./plans/verify.sh quick` passes; facade lint passes

**Done:** Fallback path tested; obsidian status updated.

**Deferred follow-up:** Behavior-focused orchestration consolidation remains open in `glowing-booping-parasol.md`.
