# Fix 1 Contract Kernel Drift Diagnostics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make stale `docs/contract_kernel.json` failures emit a deterministic rebuild command instead of leaving operators to infer the remediation from a generic hash mismatch.

**Architecture:** Keep `plans/verify_fork.sh` as the gate entrypoint and improve the actionable failure message inside `scripts/check_contract_kernel.py`, where the kernel/source comparison already lives. Add one fixture-style shell regression test that proves the stale-contract path emits the exact rebuild command, then update workflow allowlist coverage so the new harness file is treated as part of the workflow surface.

**Tech Stack:** Bash harness tests, Python checker script, git worktree workflow

---

### Task 1: Add the stale-kernel remediation path with TDD

**Files:**
- Create: `plans/tests/test_contract_kernel_drift_message.sh`
- Modify: `scripts/check_contract_kernel.py`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

**Step 1: Write the failing test**

Create `plans/tests/test_contract_kernel_drift_message.sh` as a fixture-style shell test that:

- copies or writes the minimal required files into a temp repo shape:
  - `docs/architecture/contract_anchors.md`
  - `docs/architecture/validation_rules.md`
  - `specs/CONTRACT.md`
  - `specs/IMPLEMENTATION_PLAN.md`
- runs `python3 scripts/build_contract_kernel.py --out "$tmp_repo/docs/contract_kernel.json"` against that fixture
- mutates only `specs/CONTRACT.md` after the kernel is built so `sources.contract_sha256` becomes stale
- runs `python3 scripts/check_contract_kernel.py --kernel "$tmp_repo/docs/contract_kernel.json"` from the fixture root
- asserts:
  - the command exits non-zero
  - stderr contains `sources.contract_sha256 mismatch`
  - stderr contains `python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json`

Suggested assertion shape:

```bash
if python3 "$ROOT/scripts/check_contract_kernel.py" --kernel "$fixture/docs/contract_kernel.json" \
    >"$stdout_log" 2>"$stderr_log"; then
  fail "expected stale contract kernel check to fail"
fi

grep -Fq 'sources.contract_sha256 mismatch' "$stderr_log" \
  || fail "expected contract sha mismatch message"
grep -Fq 'python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json' "$stderr_log" \
  || fail "expected rebuild remediation command"
```

**Step 2: Run test to verify it fails**

Run: `bash plans/tests/test_contract_kernel_drift_message.sh`

Expected: FAIL because the current checker reports the mismatch but does not yet emit the explicit rebuild command.

**Step 3: Write minimal implementation**

Update `scripts/check_contract_kernel.py` so the `contract_sha256` mismatch path emits the remediation command before failing. Keep the change narrow:

- compute the expected contract hash exactly as it does today
- when `sources["contract_sha256"]` mismatches, fail with a message that still includes the mismatch but appends the remediation command
- do not reorder validation or broaden the change into a new helper/artifact flow

Implementation shape:

```python
if sources.get("contract_sha256") != expected_hashes["contract_sha256"]:
    fail(
        "sources.contract_sha256 mismatch "
        f"(expected {expected_hashes['contract_sha256']}); "
        "run python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json"
    )
```

**Step 4: Update workflow allowlist coverage**

Add `plans/tests/test_contract_kernel_drift_message.sh` to:

- `plans/workflow_files_allowlist.txt`
- the `required=(...)` list in `plans/tests/test_workflow_allowlist_coverage.sh`

Keep the allowlist sorted.

**Step 5: Run the focused test set**

Run:

```bash
bash plans/tests/test_contract_kernel_drift_message.sh
bash plans/tests/test_workflow_allowlist_coverage.sh
python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json
bash plans/tests/test_verify_fork_guardrails.sh
```

Expected:

- the new regression test passes
- allowlist coverage passes
- the current repo kernel still validates
- existing verify-fork guardrails stay green

**Step 6: Commit**

```bash
git add \
  plans/tests/test_contract_kernel_drift_message.sh \
  plans/tests/test_workflow_allowlist_coverage.sh \
  plans/workflow_files_allowlist.txt \
  scripts/check_contract_kernel.py
git commit -m "fix: add contract kernel drift remediation message"
```
