# Preflight Guard Diagnostics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `plans/legacy_layout_guard.sh` and `plans/readme_ci_parity_check.sh` emit exact offender evidence and avoid misleading broad matches that mask unrelated contract work.

**Architecture:** Add focused shell fixture tests for each guard first, then patch each guard with the smallest deterministic helpers needed for line-level or path-level diagnostics. Keep `plans/preflight.sh` unchanged and verify the new guard output through the guard scripts themselves plus a lightweight preflight run.

**Tech Stack:** Bash, `rg`/`grep`, existing `plans/tests/*.sh` shell fixture pattern

---

### Task 1: Legacy Layout Guard Diagnostic Tests

**Files:**
- Create: `plans/tests/test_legacy_layout_guard.sh`
- Modify: `plans/legacy_layout_guard.sh`

**Step 1: Write the failing test**

```bash
echo "$out" | grep -Fq "plans/ralph.sh" || fail "missing active legacy path"
echo "$out" | grep -Fq "reviews/postmortems/example.md" || fail "missing unlabeled postmortem path"
```

**Step 2: Run test to verify it fails**

Run: `bash plans/tests/test_legacy_layout_guard.sh`
Expected: `FAIL` because the guard still collapses offenders or matches too broadly.

**Step 3: Write minimal implementation**

```bash
printf '  - %s\n' "${present[@]}" >&2
printf '  - %s\n' "${unlabeled[@]}" >&2
```

Also tighten the legacy-reference matcher to explicit legacy command/path tokens.

**Step 4: Run test to verify it passes**

Run: `bash plans/tests/test_legacy_layout_guard.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add plans/tests/test_legacy_layout_guard.sh plans/legacy_layout_guard.sh
git commit -m "test: harden legacy layout guard diagnostics"
```

### Task 2: README/CI Parity Guard Diagnostic Tests

**Files:**
- Create: `plans/tests/test_readme_ci_parity_check.sh`
- Modify: `plans/readme_ci_parity_check.sh`

**Step 1: Write the failing test**

```bash
echo "$out" | grep -Fq "README.md:3" || fail "missing README line evidence"
echo "$out" | grep -Fq ".github/workflows/ci.yml:8" || fail "missing CI line evidence"
echo "$out" | grep -Fq "discovered jobs:" || fail "missing discovered job ids"
```

**Step 2: Run test to verify it fails**

Run: `bash plans/tests/test_readme_ci_parity_check.sh`
Expected: `FAIL` because the guard currently reports regex/token failures without exact line evidence.

**Step 3: Write minimal implementation**

```bash
grep -En "$pattern" "$file" >&2
awk '/^[[:space:]]{2}[A-Za-z0-9_-]+:$/ { print $1 }' "$CI_WORKFLOW"
```

Add small helpers that:

- print exact `file:line` hits for forbidden patterns
- include discovered top-level job ids when `verify` or `prd-story-gate` cannot be parsed

**Step 4: Run test to verify it passes**

Run: `bash plans/tests/test_readme_ci_parity_check.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add plans/tests/test_readme_ci_parity_check.sh plans/readme_ci_parity_check.sh
git commit -m "test: improve README CI parity guard diagnostics"
```

### Task 3: Repo Verification

**Files:**
- Verify: `plans/legacy_layout_guard.sh`
- Verify: `plans/readme_ci_parity_check.sh`
- Verify: `plans/preflight.sh`

**Step 1: Run focused guard tests**

Run: `bash plans/tests/test_legacy_layout_guard.sh && bash plans/tests/test_readme_ci_parity_check.sh`
Expected: both tests `PASS`

**Step 2: Run guards against the real repo**

Run: `./plans/legacy_layout_guard.sh && ./plans/readme_ci_parity_check.sh`
Expected: both commands `PASS`

**Step 3: Run lightweight preflight verification**

Run: `PREFLIGHT_FIXTURE_MODE=none ./plans/preflight.sh`
Expected: preflight completes without regressing guard output or exit behavior

**Step 4: Commit**

```bash
git add plans/legacy_layout_guard.sh plans/readme_ci_parity_check.sh plans/tests/test_legacy_layout_guard.sh plans/tests/test_readme_ci_parity_check.sh docs/plans/2026-03-07-preflight-guard-diagnostics-design.md docs/plans/2026-03-07-preflight-guard-diagnostics.md
git commit -m "feat: improve preflight guard diagnostics"
```
