---
project: "[[Execution Facade Refactor]]"
date: "2026-03-18"
branch: project/execution-facade-refactor
worktree: .worktrees/execution-facade-refactor
---

## What Was Done

Cherry-pick recovery from broken `-n` bulk cherry-pick. Discarded dirty state, re-applied 5 seam commits one at a time with compilation verification after each, then restored the pricer seam that was silently dropped during earlier conflict resolution.

### Commits Added (6 on top of `9985fb9b`)

| SHA | Description |
|-----|-------------|
| `ad6aabe5` | post-only event seam |
| `402dc515` | inventory skew event seam |
| `80183f35` | preflight event seam |
| `9ea1386f` | risk: pending_exposure + exposure_budget + margin_gate event seams |
| `22baab12` | dead code removal, clippy lints, test deadlock fix (begin_metrics_test) |
| `4dee9607` | restore pricer event seam lost during cherry-pick |

### Current HEAD: `4dee9607`

- **685 tests pass**, 0 failures
- Compiles clean
- All 11 Upgrade 2A modules now have `_with_events` seams

## What's NOT Done

### Upgrade 2A Checklist Drift

The checklist at `docs/codebase/upgrade2_graybox_telemetry_checklist.md` has 4 stale FAIL rows that should be PASS now:

| Module | Checklist says | Actual state |
|--------|---------------|--------------|
| pricer | FAIL | PASS — `compute_limit_price_with_events` exists (restored in `4dee9607`) |
| inventory skew | FAIL | PASS — `evaluate_inventory_skew_with_events` exists |
| pending exposure | FAIL | PASS — `reserve_with_events` exists |
| exposure budget | FAIL | PASS — `evaluate_global_exposure_budget_with_events` exists |

**Action needed**: Update these 4 rows to PASS with evidence line numbers. The overall Status is already PASS (flipped during the rescue branch session), so this is just row-level cleanup.

### Upgrade 2B (NOT started on this branch)

The rescue branch had 2 more commits:
- `64c775b5` — Upgrade 2B: convert build_order_intent + group to EventSink seams
- `1629f51c` — seal implementation modules behind facade re-exports

These were **not** cherry-picked. The 3 graybox tests for `build_order_intent_internal_with_events` were removed from `build_order_intent_gate_ordering_tests.rs` since they depend on 2B code.

### Phase 2A Test Conversions (NOT started)

The original Phase 2A goal was to convert ~160 tests across 7 files from production wrappers to `_with_events`. This has not been started. The handoff from the previous session describes the conversion patterns:

- **Pattern A** (gate.rs, gates.rs): `_with_events` replaces metrics entirely
- **Pattern B** (quantize, pricer, inventory_skew, post_only, preflight): adds events param alongside metrics

Conversion scripts were in `/tmp/` on the previous session and may not survive restart. See the previous handoff for the script logic.

### Module Sealing (NOT on this branch)

Commit `1629f51c` on the rescue branch sealed 6 implementation modules (`pub mod` → `mod`). This was **not** cherry-picked. The doc block commits (`09c51a96`) that describe modules as "private" are already on this branch, but the actual `mod` visibility change is not.

## Key Files

| File | Purpose |
|------|---------|
| `docs/codebase/upgrade2_graybox_telemetry_checklist.md` | Upgrade 2 acceptance gate (4 rows need updating) |
| `crates/soldier_core/src/execution/pricer.rs` | Restored pricer seam |
| `crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs` | 3 graybox tests removed (2B scope) |

## How to Resume

```bash
cd /Users/admin/Desktop/opus-trader/.worktrees/execution-facade-refactor
git log --oneline -8  # Verify HEAD is 4dee9607
cargo test --lib -p soldier_core  # Should show 685 passed
```

Next steps in priority order:
1. Fix 4 stale FAIL rows in upgrade checklist (quick)
2. Decide whether to cherry-pick 2B commits or defer
3. Phase 2A test conversions (~160 tests across 7 files)
