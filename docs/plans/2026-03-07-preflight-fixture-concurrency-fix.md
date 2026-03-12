# Preflight Fixture Concurrency Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate false timeout failures in quick preflight by lowering the default smoke-fixture fanout without reducing fixture coverage.

**Architecture:** Keep the existing smoke fixture set and per-test timeout behavior unchanged. Only lower the default `PREFLIGHT_PARALLEL_JOBS` value in `plans/preflight.sh`, then lock that default with regression tests and rerun the clean baseline in the isolated worktree.

**Tech Stack:** Bash, existing shell fixture tests in `plans/tests/`.

---

### Task 1: Lock A Safer Default Fixture Fanout

**Files:**
- Modify: `plans/preflight.sh`
- Modify: `plans/tests/test_preflight_fixture_profiles.sh`

**Step 1: Write the failing test**

- In `plans/tests/test_preflight_fixture_profiles.sh`, add an assertion that `plans/preflight.sh` contains:

```bash
PREFLIGHT_PARALLEL_JOBS="${PREFLIGHT_PARALLEL_JOBS:-4}"
```

**Step 2: Run test to verify it fails**

Run:

```bash
bash plans/tests/test_preflight_fixture_profiles.sh
```

Expected: FAIL because the script still defaults `PREFLIGHT_PARALLEL_JOBS` to `8`.

**Step 3: Write minimal implementation**

- In `plans/preflight.sh`, change the default fixture fanout from `8` to `4`.
- Do not change the smoke fixture list or the `240` second timeout in the same patch.

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_preflight_fixture_profiles.sh
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plans/preflight.sh plans/tests/test_preflight_fixture_profiles.sh
git commit -m "fix: lower preflight fixture fanout default"
```

---

### Task 2: Prove The Harness Fix Removes The False Timeout Failure

**Files:**
- Verify: `plans/preflight.sh`
- Verify: `plans/tests/test_review_logged_timeout_retry_noncodex.sh`
- Verify: `plans/tests/test_external_review_generic.sh`

**Step 1: Re-run the targeted fixture tests**

Run:

```bash
bash plans/tests/test_review_logged_timeout_retry_noncodex.sh
bash plans/tests/test_external_review_generic.sh
```

Expected: PASS.

**Step 2: Re-run the clean baseline verify**

Run:

```bash
./plans/verify.sh quick
```

Expected: the prior timeout-only baseline failure is cleared, or any remaining failure is different and no longer the same harness contention symptom.

**Step 3: Commit**

```bash
git add plans/preflight.sh plans/tests/test_preflight_fixture_profiles.sh
git commit -m "fix: lower preflight fixture fanout default"
```
