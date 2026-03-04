# Verify Pipeline Performance Fix Pack v2 (Patched + Decision-Complete)

<proposed_plan>
## Verify Pipeline Performance Fix Pack v2 (Patched + Decision-Complete)

### Summary
Apply the safe, high-impact performance fixes in workflow/harness scripts while preserving fail-closed behavior, bash 3.2 portability, gate ordering, and artifact semantics.
This plan includes exact implementation choices, deterministic tests, and measurable acceptance thresholds.

### Public Interfaces / Contracted Behaviors
1. Existing verify/preflight CLI behavior remains unchanged.
2. `.log/.rc/.time/FAILED_GATE` artifact semantics remain unchanged.
3. `VERIFY_PARALLEL=0|1` support remains unchanged.
4. New optional test-control env var (internal harness use): `PREFLIGHT_WAIT_N_MODE=auto|force_on|force_off` (default `auto`).
5. Invalid `PREFLIGHT_WAIT_N_MODE` values and unsupported forced wait-n paths fail closed with deterministic diagnostics.

### Implementation Steps
1. Baseline benchmark capture (before edits).
2. Optimize preflight shell syntax check with two-stage flow.
3. Add dual-path fixture throttling (`wait -n` when supported, polling fallback).
4. Cache `now_monotonic_ns` backend once at startup.
5. Optimize `_compute_fixture_hash` with deterministic fast path + strict fallback.
6. Batch `verify_gate_contract_check` token checks with preserved diagnostics order.
7. Optimize verify timing summary loops to shell builtins.
8. Switch `run_logged` timing to `SECONDS` builtin (integer seconds).
9. Memoize `status_fixture_path_hash` backend selection once per run.
10. Memoize `should_enable_csp_strict` changed-file set once per run.
11. Add/adjust tests and update fixture profile counts.
12. Run workflow verification, code-review-expert, then final verify evidence.

### Detailed Implementation Spec

1. **Baseline benchmark capture**
   - Record median of 5 runs for:
   - preflight shell syntax block microbenchmark.
   - `./plans/verify_gate_contract_check.sh` runtime.
   - verify timing-summary microbenchmark over latest verify artifact dir.
   - Store command snippets + medians in `plans/progress.txt`.

2. **Preflight shell syntax optimization**
   - File: `/Users/admin/Desktop/opus-trader/plans/preflight.sh`
   - Fast path: single-parse aggregate check over all `plans/*.sh` files via temp file (`bash -n "$tmp_aggregate"`).
   - Do not use `bash -n plans/*.sh` (it syntax-checks only the first file argument and is fail-open for the rest).
   - On failure: run existing per-file loop to collect exact failing files.
   - If aggregate temp-file preparation fails, fail closed (setup error) instead of silently skipping syntax checks.
   - Preserve existing output messages and fail behavior.

3. **Dual-path fixture throttling**
   - File: `/Users/admin/Desktop/opus-trader/plans/preflight.sh`
   - Add `supports_wait_n()` using:
   - `BASH_VERSINFO` check (`>= 4.3`) and `help wait` includes `-n`.
   - Validate `PREFLIGHT_WAIT_N_MODE` with strict allowlist:
   - accepted: `auto|force_on|force_off`.
   - other values => deterministic setup-fail diagnostic + exit 2.
   - Resolution logic:
   - `PREFLIGHT_WAIT_N_MODE=force_on` => use wait-n path.
   - `PREFLIGHT_WAIT_N_MODE=force_off` => use polling path.
   - `auto` => capability-detected path.
   - If `force_on` is set but `wait -n` is unsupported, fail closed with explicit diagnostic (do not silently downgrade to polling).
   - Wait-n path blocks on completion, then prunes PID list once.
   - Polling path remains unchanged as fallback for bash 3.2.

4. **Monotonic clock backend init**
   - File: `/Users/admin/Desktop/opus-trader/plans/preflight.sh`
   - Add one-time init selecting backend in order:
   - `date +%s%N` valid numeric nanos.
   - `python3`.
   - `python`.
   - `perl`.
   - epoch-seconds fallback.
   - `now_monotonic_ns()` dispatches by selected backend via `case`, no repeated `command -v` checks.

5. **Fixture hash optimization with broad-scope guarantee**
   - File: `/Users/admin/Desktop/opus-trader/plans/preflight.sh`
   - Keep existing broad dependency policy.
   - Fast path preconditions:
   - git available and in worktree.
   - clean staged + unstaged state.
   - no untracked files under `plans/ specs/ SKILLS/ tools/ scripts/`.
   - Fast path input list: `git ls-files -- plans specs SKILLS tools scripts`.
   - Fallback trigger: any precondition failure, empty list, or command error.
   - Fallback path: current `find|sort|xargs shasum` logic (unchanged semantics).

6. **Batched token checks in verify gate contract script**
   - File: `/Users/admin/Desktop/opus-trader/plans/verify_gate_contract_check.sh`
   - Introduce single-read-per-file token presence checks.
   - Preserve deterministic token order and fail message format:
   - `missing code token '<token>' in <file>`.
   - Preserve fail-first behavior in original token order.

7. **Timing summary loop optimization**
   - File: `/Users/admin/Desktop/opus-trader/plans/verify_fork.sh`
   - Replace `basename` and `cat` subprocesses with:
   - parameter expansion for names.
   - builtin file reads (`elapsed="$(<"$f")"` for `.time`, `warn_text="$(<"$wf")"` for `.warn`).
   - Preserve multiline `.warn` payload behavior (no line truncation).
   - Preserve emitted lines exactly.

8. **`run_logged` timing optimization**
   - File: `/Users/admin/Desktop/opus-trader/plans/lib/verify_utils.sh`
   - Replace external `date +%s` calls with `SECONDS`:
   - `local start=$SECONDS`.
   - `elapsed=$((SECONDS-start))`.
   - Keep integer `.time` format unchanged.

9. **Status fixture hash backend memoization**
   - File: `/Users/admin/Desktop/opus-trader/plans/verify_fork.sh`
   - Detect hash backend once per verify run.
   - Preserve same fallback ordering and final sanitize/truncate behavior.

10. **`should_enable_csp_strict` memoization**
    - File: `/Users/admin/Desktop/opus-trader/plans/verify_fork.sh`
    - Compute changed-file set once and cache globally.
    - Preserve same base-ref handling and match regex behavior.

11. **Tests and fixture profile updates**
    - Update: `/Users/admin/Desktop/opus-trader/plans/tests/test_preflight_fixture_profiles.sh`
    - Add assertions for:
    - wait-n capability routing + override modes.
    - invalid `PREFLIGHT_WAIT_N_MODE` and unsupported `force_on` fail-closed behavior.
    - monotonic backend init function presence.
    - shell syntax two-stage behavior markers.
    - Update expected smoke fixture count.
    - Update: `/Users/admin/Desktop/opus-trader/plans/tests/test_verify_fork_guardrails.sh`
    - Assert memoized backend helpers and summary loop invariants (including multiline warn payload parity).
    - Add: `plans/tests/test_verify_gate_contract_check_batching.sh`
    - Verifies deterministic missing-token ordering and unchanged failure message contract.
    - Add new test scripts to smoke fixture list in `/Users/admin/Desktop/opus-trader/plans/preflight.sh` and update count assertions.

12. **Verification + review workflow**
    - Run targeted tests:
    - `bash plans/tests/test_preflight_fixture_profiles.sh`
    - `bash plans/tests/test_verify_fork_guardrails.sh`
    - `bash plans/tests/test_verify_gate_contract_check_batching.sh`
    - `bash plans/tests/test_artifact_lint.sh`
    - Run `./plans/workflow_verify.sh`.
    - Run `code-review-expert` skill review on the diff.
    - Run `./plans/verify.sh quick`.
    - Run `./plans/verify.sh full` on clean tree, or CI clean-checkout proof if local full is blocked by dirty-tree policy.

### Test Cases and Scenarios
1. Bash 3.2-compatible path forced (`PREFLIGHT_WAIT_N_MODE=force_off`) still passes fixture throttling.
2. Wait-n path forced (`PREFLIGHT_WAIT_N_MODE=force_on`) passes and produces same fixture outcomes.
3. Invalid wait mode value fails closed with deterministic setup diagnostics.
4. `force_on` on an environment without wait-n support fails closed with explicit diagnostics.
5. Token batching fails on first missing token in canonical order with unchanged error text.
6. Hash fast path and fallback path produce deterministic non-empty hash output.
7. `.time` artifacts remain numeric integers and artifact lint remains green.

### Acceptance Criteria (Numeric)
1. Shell syntax microbenchmark median improves by at least 70% vs baseline.
2. `verify_gate_contract_check` median runtime improves by at least 30% vs baseline.
3. Timing-summary microbenchmark median improves by at least 90% vs baseline.
4. No functional regression in required harness tests and `workflow_verify`.
5. `verify.sh quick` green; `verify.sh full` green (local clean tree or CI proof).

### Assumptions and Defaults
1. Preserve fail-closed defaults and gate ordering.
2. Preserve portability for macOS bash 3.2 users.
3. Preserve broad fixture hash dependency coverage.
4. Do not remove serial validator path (`VERIFY_PARALLEL=0`) in this batch.
5. Defer rust/spec overlap refactor unless post-batch metrics still justify it.
</proposed_plan>

## /6 Review Rerun (same stack)

No P0/P1/P2 findings on the patched plan.

### Stack Results
1. `/pr-review`: `PASS`
2. `/failure-mode-review`: `PASS`
3. `/strategic-failure-review`: `PASS`
4. `/contract-review`: `PASS` (workflow fail-closed + verification constraints preserved)
5. `/validator-audit`: `PASS` (batched checks keep deterministic fail-first contract)
6. `/devils-advocate`: `SKIPPED` (plan-only stage, no AT diff yet)

**Aggregate decision:** `PASS`

### Review Coverage
- `/Users/admin/Desktop/opus-trader/plans/preflight.sh` — preflight throttling, shell syntax, monotonic timer, fixture hash changes are fully specified.
- `/Users/admin/Desktop/opus-trader/plans/verify_fork.sh` — summary-loop, csp-strict memoization, status-hash memoization specified with parity constraints.
- `/Users/admin/Desktop/opus-trader/plans/verify_gate_contract_check.sh` — batched-token strategy preserves deterministic diagnostics.
- `/Users/admin/Desktop/opus-trader/plans/lib/verify_utils.sh` — `SECONDS` timing replacement keeps `.time` format stable.
- `/Users/admin/Desktop/opus-trader/plans/tests/test_preflight_fixture_profiles.sh` — branch coverage and fixture-count updates included.
- `/Users/admin/Desktop/opus-trader/plans/tests/test_verify_fork_guardrails.sh` — guardrail invariants preserved and extended.
- `/Users/admin/Desktop/opus-trader/plans/tests/test_artifact_lint.sh` — artifact semantics explicitly protected.
- `/Users/admin/Desktop/opus-trader/plans/workflow_verify.sh` — required harness verification step included.
- `/Users/admin/Desktop/opus-trader/reviews/REVIEW_CHECKLIST.md` — evidence/compounding/workflow checks satisfied in plan specification.
