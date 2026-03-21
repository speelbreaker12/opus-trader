# Verify Harness Acceleration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve `./plans/verify.sh quick|full` as the only authoritative verify surface, harden the harness where it can currently blur truthfulness or parallel diagnostics, then add scoped local iteration entrypoints and deterministic Rust accelerators without making verify behavior host-dependent.

**Architecture:** Freeze `./plans/verify.sh` as the thin contract entrypoint and keep `plans/verify_fork.sh` canonical. First fix the existing nonblocking-gate truthfulness issue, then extract reusable Rust gate runners from `plans/lib/rust_gates.sh`, plus a shared setup helper in `plans/lib/verify_env.sh` that both `verify_fork.sh` and `verify_scope.sh` source. Scoped local iteration runs must write to `artifacts/verify_scope/<run_id>/` and record `authoritative=false` plus a `scope` field in metadata so they cannot be confused with authoritative `artifacts/verify/<run_id>/` runs. Parallel diagnostics hardening for the existing parallel runner lands before any new Python overlap work. Any new workflow-facing script or test introduced by this patch series must be added to `plans/workflow_files_allowlist.txt`, `plans/tests/test_workflow_allowlist_coverage.sh`, and `plans/workflow_verify.sh` in the same tranche so the workflow control surface stays complete. Local-only tuning such as `VERIFY_PARALLEL_JOBS` experiments or custom `CARGO_TARGET_DIR` values is documented separately and is not part of the harness contract work.

**Tech Stack:** Bash 3.2-compatible shell scripts, Cargo, pytest, existing verify artifact conventions.

---

## Chunk 1: Fix Harness Truthfulness First

### Task 1: Fix `run_logged_nonblocking_gate` so soft findings and broken gates diverge cleanly

**Files:**
- Modify: `plans/verify_fork.sh`
- Modify: `plans/tests/test_verify_accelerators.sh`
- Modify: `plans/tests/test_verify_fork_guardrails.sh`

- [ ] **Step 1: Write failing tests for nonblocking-gate truthfulness**

Test cases:
- a real soft-gate finding still produces a warn artifact and preserves nonblocking behavior
- a broken gate runner, missing script, or exec failure is treated as infrastructure failure rather than a soft warning
- quick mode can distinguish "the check found an issue" from "the gate itself is broken"
- nonblocking gate convention is explicit: `rc=1` means a legitimate soft finding; `rc>=2` plus `124`, `126`, `127`, and `137` are infrastructure failure

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: FAIL because the harness still collapses soft findings and broken gates into the same path.

- [ ] **Step 3: Implement minimal truthfulness hardening**

Implementation outline:
- keep `./plans/verify.sh quick|full` unchanged
- keep `plans/verify_fork.sh` as the only authoritative orchestration path
- preserve nonblocking semantics for legitimate soft-gate findings
- hard fail when the gate infrastructure itself is broken
- update existing guardrail coverage so `rc>=2` no longer passes through the warn-artifact path
- implement the explicit convention for nonblocking gates:
  - `1` = finding
  - `2+` = gate infra failure
  - `124`, `126`, `127`, `137` = timeout / exec failure / command-not-found / timeout kill and therefore infra failure

- [ ] **Step 4: Run the test again**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: PASS

## Chunk 2: Freeze The Contract And Extract Shared Runners

### Task 2: Refactor shared Rust runners without changing verify authority

**Files:**
- Modify: `plans/verify_fork.sh`
- Create: `plans/lib/verify_env.sh`
- Modify: `plans/lib/rust_gates.sh`
- Modify: `plans/tests/test_verify_accelerators.sh`
- Modify: `plans/workflow_verify.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

- [ ] **Step 1: Write failing tests for shared Rust runner units**

Test cases:
- `plans/verify_fork.sh` still owns the authoritative quick/full flow
- `plans/lib/verify_env.sh` centralizes shared environment/bootstrap setup needed by both `verify_fork.sh` and `verify_scope.sh`
- `plans/lib/rust_gates.sh` exposes reusable units for:
  - format
  - clippy
  - tests
  - smoke/facade lints
- the extracted units can be called by both full verify and later focused entrypoints

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: FAIL because the harness does not yet expose shared Rust runner functions.

- [ ] **Step 3: Implement minimal runner extraction**

Implementation outline:
- keep `./plans/verify.sh quick|full` unchanged
- keep `plans/verify_fork.sh` as the only authoritative orchestration path
- move shared env/bootstrap setup into `plans/lib/verify_env.sh`
- extract reusable Rust runner functions from `plans/lib/rust_gates.sh`
- add `plans/lib/verify_env.sh` to the workflow control surface in the same tranche
- avoid changing Python scheduling in this chunk

- [ ] **Step 4: Run the test again**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: PASS

## Chunk 3: Add A Single Scoped Dispatcher

### Task 3: Add `verify_scope.sh` as a local iteration tool only

**Files:**
- Create: `plans/verify_scope.sh`
- Create: `plans/tests/test_verify_scope.sh`
- Modify: `plans/verify_fork.sh`
- Modify: `plans/lib/verify_env.sh`
- Modify: `plans/lib/rust_gates.sh`
- Modify: `plans/workflow_verify.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

- [ ] **Step 1: Write failing tests for the scoped dispatcher**

Test cases:
- `./plans/verify_scope.sh contract`
- `./plans/verify_scope.sh workflow`
- `./plans/verify_scope.sh rust clippy`
- `./plans/verify_scope.sh rust tests`
- each scoped run is explicitly marked non-authoritative in output and metadata
- each scoped run writes to `artifacts/verify_scope/<run_id>/`, never `artifacts/verify/<run_id>/`
- scoped metadata includes at minimum:
  - `authoritative: false`
  - `scope: <selected-slice>`
  - `run_root: "verify_scope"`

- [ ] **Step 2: Run the new dispatcher test to verify it fails**

Run: `bash plans/tests/test_verify_scope.sh`
Expected: FAIL because the dispatcher does not exist yet.

- [ ] **Step 3: Implement the minimal dispatcher**

Implementation outline:
- one dispatcher only, not multiple bespoke wrappers
- source the shared setup helper from Chunk 2 rather than duplicating env setup
- reuse the shared Rust runners from Chunk 2
- only expose focused local iteration surfaces
- do not allow scoped runs to masquerade as full verify evidence
- use a separate artifact root: `artifacts/verify_scope/<run_id>/`
- write non-authoritative metadata explicitly in `verify.meta.json`
- add `plans/verify_scope.sh` and `plans/tests/test_verify_scope.sh` to the workflow control surface in the same tranche

- [ ] **Step 4: Run the dispatcher test again**

Run: `bash plans/tests/test_verify_scope.sh`
Expected: PASS

Why this chunk is early:
- this is the biggest total local-iteration win because skipping irrelevant gates beats making irrelevant gates faster
- keep it ahead of Rust accelerators so accelerator work attaches to the shared runner and the scoped entrypoints, not only the full verify path

## Chunk 4: Add Accelerators To The Shared Rust Runner

### Task 4: Add deterministic `sccache` and `nextest` support

**Files:**
- Modify: `plans/verify_fork.sh`
- Modify: `plans/lib/rust_gates.sh`
- Modify/extend: `plans/tests/test_verify_accelerators.sh`

- [ ] **Step 1: Extend failing tests for explicit `sccache` control**

Test cases:
- `VERIFY_USE_SCCACHE=1` requires `sccache`
- requested accelerator state is recorded deterministically
- warm-cache repeat runs keep exact current Rust selection semantics while benefiting from `sccache`

- [ ] **Step 2: Run the accelerator test to verify it fails**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: FAIL because the shared runner does not yet honor explicit `sccache` settings.

- [ ] **Step 3: Implement minimal `sccache` support**

Implementation outline:
- add `VERIFY_USE_SCCACHE=0|1`
- requested but missing `sccache` = hard fail
- CI default remains `sccache=0`
- keep Rust test selection semantics unchanged

- [ ] **Step 4: Run the accelerator test again**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: PASS

- [ ] **Step 5: Extend failing tests for explicit `nextest` control**

Test cases:
- `VERIFY_TEST_RUNNER=nextest` requires `cargo-nextest`
- unsupported `nextest` paths fall back to `cargo test` with explicit logged evidence
- the current mix of workspace tests and smoke/facade paths preserves exact selection semantics

- [ ] **Step 6: Run the accelerator test to verify it fails**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: FAIL because the shared runner does not yet honor explicit `nextest` settings.

- [ ] **Step 7: Implement minimal `nextest` support**

Implementation outline:
- add `VERIFY_TEST_RUNNER=cargo|nextest`
- requested but missing `cargo-nextest` = hard fail
- fallback from unsupported `nextest` path = deterministic artifact plus clear console signal
- keep CI default at `runner=cargo`

- [ ] **Step 8: Run the accelerator test again**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: PASS

Why this chunk is after scoped entrypoints:
- `sccache` is the biggest repeated Rust win, especially on warm-cache repeat runs
- `nextest` is useful but less universal than `sccache`, so it follows `sccache`

## Chunk 5: Harden Parallel Diagnostics Before More Parallelism

### Task 5: Preserve real wait results and report more than the first failure

**Files:**
- Modify: `plans/verify_fork.sh`
- Modify: `plans/lib/verify_utils.sh` (if needed)
- Modify: `plans/tests/test_verify_accelerators.sh` or add a dedicated parallel-runner test

- [ ] **Step 1: Write failing tests for parallel diagnostics hardening**

Test cases:
- `parallel_wait_oldest` preserves the actual `wait` return code when a subshell dies before writing `.rc`
- `finish_parallel_group_or_exit` still identifies the primary failed gate
- secondary failures remain visible in console/artifacts instead of disappearing behind first-failure-only reporting
- slot-reclaim behavior in `start_parallel_gate` stays unchanged; only crash diagnostics/reporting behavior changes

- [ ] **Step 2: Run the diagnostics test to verify it fails**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: FAIL because the current parallel runner still drops the `wait` status and stops at first-failure reporting.

- [ ] **Step 3: Implement minimal diagnostics hardening**

Implementation outline:
- preserve actual `wait` status for crashed parallel gate subprocesses when `.rc` is missing
- keep `start_parallel_gate` slot-reclaim behavior unchanged
- use `finish_parallel_group_or_exit` as the decision/reporting point for missing `.rc` crash diagnostics
- improve reporting of secondary failures without changing the authoritative fail gate decision
- do not let this tranche block the earlier shared-runner, dispatcher, or accelerator work

- [ ] **Step 4: Run the diagnostics test again**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: PASS

## Chunk 6: Measure Before Touching Python Scheduling

### Task 6: Decide whether Python overlap is worth a separate patch

**Files:**
- Modify: `plans/verify_fork.sh` (only if justified)
- Modify: `plans/lib/python_gates.sh` (only if justified)
- Modify: `plans/tests/test_verify_accelerators.sh` or `plans/tests/test_verify_scope.sh` (only if justified)

- [ ] **Step 1: Capture timing evidence after the Rust refactor, accelerators, and diagnostics hardening**

Run: `./plans/verify.sh quick`
Expected: PASS with artifacts sufficient to compare Rust, workflow, and Python slices.

- [ ] **Step 2: Decide whether Python overlap earns inclusion**

Decision rule:
- If the median Python slice time is greater than 20% of total authoritative quick-run wall-clock time across 3 comparable same-machine runs, continue.
- If not, defer overlap and document the deferment.

- [ ] **Step 3: If justified, write a failing scheduling test first**

Test cases:
- overlap is opt-in
- verify still joins all started work
- artifact behavior stays deterministic

- [ ] **Step 4: Run the test to verify it fails**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: FAIL because overlap is not yet implemented.

- [ ] **Step 5: Implement minimal overlap**

Implementation outline:
- keep the concurrency change isolated from the Rust runner work
- preserve deterministic failure handling and artifact writing
- build on the already-hardened parallel diagnostics path

- [ ] **Step 6: Run the scheduling test again**

Run: `bash plans/tests/test_verify_accelerators.sh`
Expected: PASS

## Out Of Scope For This Patch Series

- `VERIFY_PARALLEL_JOBS` tuning as an operator knob
- custom `CARGO_TARGET_DIR` or `/tmp` target-dir experiments

Notes:
- these may be documented for workstation tuning later
- they are not part of the repo-level harness contract or default verify behavior

## Chunk 7: Verification and Closure

### Task 7: Verify the harness end to end

**Files:**
- Modify: `obsidian/Projects/Verify Harness Acceleration.md`
- Create: `obsidian/Debriefs/Verify Harness Acceleration 2026-03-20.md`

- [ ] **Step 1: Run workflow verification**

Run: `./plans/workflow_verify.sh`
Expected: PASS

- [ ] **Step 2: Run repo quick verify**

Run: `./plans/verify.sh quick`
Expected: PASS

- [ ] **Step 3: Run code review before completion**

Requirement:
- apply the `code-review-expert` skill after the implementation is stable and before final completion claims

- [ ] **Step 4: Run full verify or obtain equivalent CI proof before completion**

Run: `./plans/verify.sh full`
Expected: PASS. If a clean local full run is blocked, document the blocker and require clean-checkout CI proof before completion; do not treat this as optional for workflow/harness changes.

- [ ] **Step 5: Update project note and debrief**

Record:
- what shipped
- the single dominant constraint
- whether Python overlap landed or was deferred based on timing evidence
