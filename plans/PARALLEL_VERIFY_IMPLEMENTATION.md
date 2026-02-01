# Parallel Verify.sh Implementation

## Summary

Successfully implemented parallelization in `plans/verify.sh` to speed up the Ralph audit process by 2-4x through wave-based parallel execution. All changes are portable (Bash 3.2+, macOS and Linux compatible).

## Implementation Status

### ✅ P0: Foundation (COMPLETE)
- **Timing Instrumentation**: Added `.time` files for all gates to measure performance
  - Each gate now writes elapsed time to `${VERIFY_ARTIFACTS_DIR}/${name}.time`
  - Timing summary printed in verbose mode at end of run
  - Timing data persisted for analysis even in CI quiet mode

- **Safe Parallel Primitives**: Added three environment flags to make `run_logged()` safe for background execution
  - `RUN_LOGGED_SUPPRESS_EXCERPT=1`: Skip error excerpt printing (parent handles)
  - `RUN_LOGGED_SKIP_FAILED_GATE=1`: Skip FAILED_GATE writing (parent writes deterministically)
  - `RUN_LOGGED_SUPPRESS_TIMEOUT_FAIL=1`: Skip timeout fail exit (parent handles)

- **Wave-Based Parallel Runner**: New `run_parallel_group()` function
  - Processes specs in waves (batches) for Bash 3.2 compatibility
  - Deterministic failure detection (first failure in declared order)
  - No race conditions on FAILED_GATE
  - Portable (no `wait -n`, works on macOS Bash 3.2)

### ✅ P1: Parallel Spec Validators (COMPLETE)
- Converted 9 sequential spec validators to parallel array execution
- Auto-detects CPU cores, caps at 4 to avoid CI runner thrashing
- Maintains deterministic FAILED_GATE ordering
- All validators still have same log artifacts (`.log`, `.rc`, `.time`)

**Before**: Sequential execution (~3-5 minutes estimated)
**After**: Parallel waves (~1 minute estimated on 4-core machine)

### ✅ P2: Parallel Status Fixtures (COMPLETE)
- Converted 7 sequential status fixture validations to parallel execution
- Uses deterministic glob ordering to preserve failure priority
- Capped at 4 parallel jobs (status validation is lightweight)

**Before**: Sequential execution (~1-2 minutes estimated)
**After**: Parallel waves (~30-45 seconds estimated on 4-core machine)

### ✅ P3: Parallel Workflow Acceptance (COMPLETE)
- Integrated existing `workflow_acceptance_parallel.sh` for full mode
- Smoke mode stays sequential (already fast)
- Auto-detects cores, caps at 8 to avoid OOM
- Only runs in full mode (workflow file changes or explicit full)

**Before**: Sequential tests in full mode (~10-20 minutes)
**After**: Parallel tests in full mode (~3-8 minutes on 8-core machine)

## Usage

### Standard Usage (No Changes Required)
```bash
# Quick mode (default locally)
./plans/verify.sh

# Full mode (default in CI)
./plans/verify.sh full

# All parallelization is automatic - no flags needed
```

### Measuring Performance Improvements

**Step 1: Baseline (before optimization, for reference)**
If you want to measure the old sequential behavior, you would need to revert changes, but since we've already implemented, we can just measure the new parallel behavior.

**Step 2: Current Performance**
```bash
# Run in verbose mode to see timing summary
MODE=full VERIFY_CONSOLE=verbose ./plans/verify.sh

# Timing summary appears at end:
# === Gate Timings ===
# contract_crossrefs                         35s
# arch_flows                                 28s
# state_machines                             42s
# ...
```

**Step 3: Analyze Timing Data**
```bash
# After run, timing files are in artifacts
cat artifacts/verify/*/contract_crossrefs.time
cat artifacts/verify/*/workflow_acceptance.time

# View all timings sorted by duration
ls -1 artifacts/verify/*/*.time | while read f; do
  name=$(basename "$f" .time)
  time=$(cat "$f")
  printf "%-40s %5ss\n" "$name" "$time"
done | sort -t: -k2 -nr
```

### Environment Variables

**Existing Variables (unchanged):**
- `MODE=quick|full` - Verification level
- `VERIFY_CONSOLE=verbose|quiet|auto` - Output verbosity
- `VERIFY_RUN_ID=...` - Custom run ID
- `VERIFY_ARTIFACTS_DIR=...` - Custom artifacts directory

**New Internal Variables (auto-set, not user-facing):**
- `SPEC_LINT_JOBS` - Auto-detected cores for spec validators (capped at 4)
- `WORKFLOW_JOBS` - Auto-detected cores for workflow tests (capped at 8)
- `RUN_LOGGED_*` flags - Internal use only for parallel execution

## File Changes

### Modified Files
1. **plans/verify.sh** (main changes)
   - Lines 221-266: Updated `run_logged()` with timing and flags
   - After line 266: Added `run_parallel_group()` function (~60 lines)
   - Lines 640-711 region: Converted spec validators to parallel array
   - Lines 731-756 region: Converted status fixtures to parallel array
   - Lines 1088-1099: Integrated parallel workflow acceptance
   - Before line 1102: Added timing summary output

### New Files
1. **plans/test_parallel_smoke.sh** - Smoke test for parallelization changes
2. **plans/PARALLEL_VERIFY_IMPLEMENTATION.md** - This documentation

### Existing Files (used, not modified)
1. **plans/workflow_acceptance_parallel.sh** - Pre-existing parallel harness

## Technical Details

### Why Wave Scheduling Instead of `wait -n`?
- macOS ships with Bash 3.2 (from 2007) as default
- `wait -n` requires Bash 4.3+ (2014)
- Wave scheduling works on Bash 3.2+ (100% portable)
- Efficiency loss vs "wait-any" is negligible with only 9 validators

### Deterministic Failure Ordering
The parallel runner ensures FAILED_GATE is deterministic:
1. Jobs run in parallel (non-deterministic completion order)
2. After wave completes, check `.rc` files in **declared array order**
3. First failure in declared order sets FAILED_GATE
4. Only first failure prints excerpt (no console spam)

### Bash 3.2 Compatibility Notes
- ✅ No `wait -n` (requires 4.3+)
- ✅ No `local -n` nameref (requires 4.3+)
- ✅ No `readarray` / `mapfile` (requires 4.0+)
- ✅ Uses basic array syntax supported since Bash 3.0

## Expected Performance Impact

**System 1: Developer Iteration Loop (verify.sh)**

| Gate | Before (sequential) | After (parallel) | Speedup |
|------|---------------------|------------------|---------|
| 0c: Spec validators (9 scripts) | ~3-5 min | ~1 min | 3-5x |
| 0d: Status fixtures (7 files) | ~1-2 min | ~30-45 sec | 2-3x |
| 6: Workflow acceptance (full) | ~10-20 min | ~3-8 min | 2-4x |

**Overall expected speedup**: 2-3x on full verify cycle

**Note**: Actual speedup depends on:
- Number of CPU cores (auto-detected, capped appropriately)
- Disk I/O speed (SSD vs HDD)
- Python interpreter startup time
- Individual validator complexity

## Validation

### Smoke Test
```bash
./plans/test_parallel_smoke.sh
```

Expected output:
```
✓ verify.sh syntax is valid
✓ run_parallel_group() function added
✓ Parallel execution flags added
✓ Spec validators converted to parallel array
✓ Parallel workflow acceptance integration added

=== All Smoke Tests Passed ===
```

### Full Verification
```bash
# Run full verify to ensure all gates still pass
MODE=full ./plans/verify.sh
```

## Troubleshooting

### Issue: Parallel execution seems slow
**Check CPU core count:**
```bash
# macOS
sysctl -n hw.ncpu

# Linux
nproc
```

If running in a container/VM with limited cores, parallelization may not help much.

### Issue: Jobs capped at 4 or 8, want more
**Current caps** (by design):
- Spec validators: capped at 4 (avoid thrashing)
- Workflow tests: capped at 8 (avoid OOM)

Caps are conservative for CI runners. To adjust, edit verify.sh:
```bash
# Spec validators (around line 715)
[[ $SPEC_LINT_JOBS -gt 4 ]] && SPEC_LINT_JOBS=4  # Change 4 to higher

# Workflow tests (around line 1095)
[[ $WORKFLOW_JOBS -gt 8 ]] && WORKFLOW_JOBS=8   # Change 8 to higher
```

### Issue: Timing summary not showing
Make sure `VERIFY_CONSOLE=verbose`:
```bash
MODE=full VERIFY_CONSOLE=verbose ./plans/verify.sh
```

Timing data is still collected in quiet mode, just not printed.

## Future Work (Out of Scope for Current Implementation)

### Track 2: Full PRD Throughput Optimization
**Deferred pending timing data** from 10+ full PRD runs:
- Incremental per-story auditing with global input tracking
- Conditional BLOCKED caching with machine-readable reasons
- Slice-level parallelization with full isolation

**Don't optimize until System 1 (verify.sh) timing data is collected.**

### Additional Optimization Candidates (if needed)
- Rust test parallelization (already uses cargo's parallel runner)
- Python test parallelization (pytest-xdist)
- Node test parallelization (if not already parallel)

## Rollback Instructions

If parallelization causes issues:

1. **Quick rollback**: Revert verify.sh to previous commit
```bash
git checkout HEAD~1 plans/verify.sh
```

2. **Partial rollback**: Keep timing but disable parallelization
```bash
# Edit verify.sh, replace parallel sections with sequential calls
# (Not recommended - better to debug and fix)
```

## Conclusion

All planned parallelization improvements are implemented:
- ✅ P0: Safe parallel primitives with timing instrumentation
- ✅ P1: Parallel spec validators (9 scripts)
- ✅ P2: Parallel status fixtures (7 files)
- ✅ P3: Parallel workflow acceptance integration (full mode)

Expected impact: **2-3x faster verify cycle** for developer iteration.

Next step: Collect baseline timing data from multiple runs to:
1. Validate speedup claims
2. Identify any remaining bottlenecks
3. Inform Track 2 (PRD throughput) optimization decisions
