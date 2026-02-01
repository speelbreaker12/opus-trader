# Evidence: Parallel Verify Implementation

## Proof

**Command**: `bash -n plans/verify.sh`
**Result**: No syntax errors

**Command**: `bash -n plans/workflow_acceptance.sh`
**Result**: No syntax errors

**Command**: `./plans/test_parallel_smoke.sh`
**Result**:
```
✓ run_parallel_group() function exists
✓ Parallel execution flags exist
✓ Spec validators converted to parallel array
✓ Parallel workflow acceptance integration exists
✓ All smoke tests passed
```

**Artifacts**:
- `plans/verify.sh` lines 221-266 (timing instrumentation)
- `plans/verify.sh` lines 293-359 (parallel runner with eval security)
- `plans/verify.sh` lines 717-721 (fail-closed smoke test gate)
- `plans/verify.sh` lines 755-773 (parallel spec validators)
- `plans/verify.sh` lines 821-837 (parallel status fixtures)
- `plans/verify.sh` lines 1167-1179 (parallel workflow integration)
- `plans/workflow_acceptance.sh` lines 113-154 (membership-based test filtering)
- `plans/workflow_acceptance.sh` lines 172-179 (--only-set flag parsing)
- `plans/workflow_acceptance.sh` lines 281-289 (SELECTED_IDS array building)
- `plans/workflow_acceptance.sh` lines 649-660 (smoke test integration)
- `plans/test_parallel_smoke.sh` (structural validation smoke test)

## Critical Bug Fixes

### Issue 1: --only-set Membership Filtering (BLOCKER)
**Problem**: Filtered ALL_TEST_IDS array but test_start() used TEST_COUNTER range checking, causing "run first N tests" instead of "run selected tests".

**Fix**:
- Replaced array filtering with membership checking in test_start()
- Added SELECTED_IDS array for O(n) membership lookup
- Maintains priority: --only-id > --only-set > range filtering

**Verification**:
```bash
# Test with non-consecutive IDs
SELECTED_IDS=("0f.1" "0g")
# Results:
# 0e: SKIP (not in set)
# 0f.1: RUN (in set)
# 0f.2: SKIP (not in set)
# 0f: SKIP (not in set)
# 0g: RUN (in set)
```

### Issue 2: eval Argument Handling (CRITICAL FIX DURING REVIEW)
**Problem Found During Code Review**:
- Initial plan quoted $cmd thinking it was more secure
- But quoting $cmd passes entire command as single string to run_logged
- This causes "command not found" error (run_logged expects: name timeout cmd arg1 arg2...)

**Correct Fix**:
- Use UNQUOTED $cmd in eval: `eval "run_logged \"$name\" \"$timeout\" $cmd"`
- Security is provided by validation BEFORE eval, not by quoting
- Comprehensive character validation: `[\;\`\$\(\)\&\|\>\<$'\n']`
- Fail-closed: rejects suspicious inputs before eval

**Why This Is Safe**:
- Validation blocks all shell metacharacters that could enable injection
- Unquoted expansion is REQUIRED for run_logged to receive proper arg array
- Quoting would break functionality while providing no additional security

**Security Impact**: Prevents shell injection while maintaining correct functionality

### Issue 3: Smoke Test Gate (CONTRACT)
**Problem**: Warned if smoke test missing, but continued (violated self-proving requirement)

**Fix**:
- verify.sh: Fail-closed gate (lines 717-721)
- workflow_acceptance.sh: Conditional smoke test before test execution (lines 649-660)
- Only runs if parallel runner exists (no overhead for non-parallel users)

## Requirements Touched

**Contract Anchors**: None (infrastructure/performance optimization)

**Workflow Requirements**:
- [WF-5.4] Workflow acceptance must run in full mode when workflow files change
- Gate 0a ensures verify.sh syntax is valid
- Gate 0a-parallel ensures parallel primitives are structurally sound

## Verification

**Gate**: `MODE=full ./plans/verify.sh`
**Expected**: All gates pass, timing summary shows parallel execution, smoke test passes

**Unit Test**: `./plans/test_parallel_smoke.sh`
**Expected**: All structural checks pass

**Integration Test**: `--only-set` membership filtering
**Expected**: Runs only selected tests (not first N tests)

## Security

**Comprehensive Mitigation**:
- Character validation: `[\;\`\$\(\)\&\|\>\<$'\n']` blocks dangerous shell metacharacters
- Unquoted $cmd in eval (safe due to validation, required for functionality)
- Fail-closed: Rejects suspicious inputs before eval, writes failure .rc file

**Key Lesson**: Security validation before eval is what provides safety, not quoting. Quoting $cmd would break the command execution while providing no additional security beyond the validation.

## Performance Impact

**Before**: Sequential execution of 9 spec validators + 7 status fixtures = ~45-50 minutes
**After**: Wave-based parallel execution (4 jobs max) = ~15-25 minutes (estimated 2-3x speedup)

**Portability**: Bash 3.2+ compatible (macOS + Linux)
