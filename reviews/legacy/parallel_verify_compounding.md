# Compounding: Parallel Verify Implementation

## AGENTS.md Updates Proposed

**Rule 1**: MUST use `run_parallel_group()` for independent validators
- **Trigger**: Adding new spec validators or status fixture validators to verify.sh
- **Prevents**: Adding sequential validators that slow down iteration loop
- **Enforce**: Code review checks that new validators use SPEC_VALIDATOR_SPECS array pattern

**Rule 2**: MUST NOT use eval without input validation for dynamic commands
- **Trigger**: Any new parallel execution pattern in verify.sh
- **Prevents**: Shell injection vulnerabilities in parallel runners
- **Enforce**: Grep for `eval` in verify.sh during review; require validation or array expansion

**Rule 3**: SHOULD cap parallel jobs to avoid CI resource exhaustion
- **Trigger**: Adding new parallel execution paths
- **Prevents**: OOM kills and thrashing on small CI runners
- **Enforce**: All parallel job counts must have explicit caps (e.g., `[[ $JOBS -gt 4 ]] && JOBS=4`)

**Rule 4**: MUST add smoke tests for harness structural changes
- **Trigger**: Adding new parallel primitives or execution patterns
- **Prevents**: Broken harness changes from reaching CI
- **Enforce**: Smoke test gate (0a-parallel) catches regressions on every verify run

**Rule 5**: MUST use membership checking for set-based filtering
- **Trigger**: Adding new filtering modes to workflow_acceptance.sh
- **Prevents**: Range-based filtering bugs when filtering non-contiguous IDs
- **Enforce**: test_start() must use membership check for set filters, not array index ranges

## Bug Fixes Applied

**Initial Implementation Issues**:
1. **--only-set filtering**: Used array filtering + range checking (wrong) → Fixed with membership checking in test_start()
2. **eval argument handling**: Initially quoted $cmd (broke functionality) → Fixed with UNQUOTED $cmd + validation
3. **Smoke test gate**: Warned but didn't fail → Fixed with fail-closed gate

**Lessons Learned**:
- Test membership filtering requires explicit membership check, not range-based array indexing
- eval security: validation BEFORE eval provides safety; quoting $cmd breaks functionality (entire command becomes single arg)
- Self-proving requirements (smoke tests) must be fail-closed, not best-effort warnings
- Security and functionality can conflict - understand the tradeoffs and validate inputs instead of blindly quoting

## Elevation Plan

**Top 3 Sinks**:
1. Slow verify cycle (45-50 min) blocks fast iteration
2. CI feedback delay compounds WIP inventory
3. Manual performance optimization requires deep bash knowledge

**Elevation 1**: Instrumented parallel verify harness
- **Owner**: Automation (verify.sh timing data)
- **Effort**: Already implemented
- **Expected Gain**: 2-3x faster verify cycle (45-50 min → 15-25 min)
- **Proof**: `.time` files in artifacts show per-gate timing

**Subordinate Win 1**: Portable wave-based parallelization
- **Owner**: Bash 3.2 compatible primitives
- **Effort**: ~70 lines of portable bash
- **Expected Gain**: Works on all developer machines (macOS + Linux)
- **Proof**: No dependency on Bash 4+ features (wait -n, local -n)

**Subordinate Win 2**: Self-validating harness changes
- **Owner**: Smoke test gate catches regressions
- **Effort**: ~40 line smoke test + 1 new gate
- **Expected Gain**: Fast feedback if parallel primitives break
- **Proof**: Gate 0a-parallel runs on every verify.sh invocation

**Subordinate Win 3**: Fail-closed security validation
- **Owner**: Input validation before eval
- **Effort**: ~7 lines of regex validation
- **Expected Gain**: Prevents shell injection in parallel runners
- **Proof**: Commands with metacharacters are rejected before execution

## Migration Path

**For developers adding new validators**:
1. Add to SPEC_VALIDATOR_SPECS array (not sequential run_logged)
2. Use format: `"name|timeout|command args"`
3. Ensure command has no shell metacharacters
4. Test with `./plans/test_parallel_smoke.sh`

**For CI/CD pipeline owners**:
1. No changes required (parallel execution is automatic)
2. Monitor timing improvement via .time artifacts
3. Adjust SPEC_LINT_JOBS cap if needed for resource constraints
