# Phase 0 Live Enable Preflight Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert Phase 0 from evidence-only wording into a contract-mandated, fail-closed live-enable preflight by naming the gate explicitly and wiring it to the existing Phase 0 evidence checker.

**Architecture:** Keep `tools/phase0_meta_test.py` as the single source of truth for validating the Phase 0 evidence pack and runtime proofs. Add a thin operator-facing wrapper at `plans/live_enable_preflight.sh`, invoked consistently as `bash ./plans/live_enable_preflight.sh`, then update contract and checklist docs so live-trading enablement explicitly depends on that preflight. Reuse the existing verify gate instead of creating a second evidence validator or adding new runtime dispatch logic, and keep interpreter selection aligned with the current verify harness.

**Tech Stack:** Markdown contract/docs, bash workflow harness, existing Python Phase 0 checker, shell guardrail tests, `./plans/verify.sh quick|full`.

---

### Task 1: Make the contract name the live-enable gate

**Files:**
- Modify: `specs/CONTRACT.md`
- Modify: `specs/IMPLEMENTATION_PLAN.md`
- Review: `docs/phase0_index.md`

**Step 1: Re-read the current Phase 0 wording**

Run: `sed -n '125,175p' specs/CONTRACT.md`
Expected: Phase 0 currently says the P0 items must be completed and evidenced before live-trading enablement, but it does not name a specific enablement preflight.

**Step 2: Rewrite the Phase 0 intro as a named fail-closed gate**

Patch `specs/CONTRACT.md` so the Phase 0 intro states all of the following:
- before any live-trading enablement, the operator/release flow MUST run `bash ./plans/live_enable_preflight.sh`,
- that preflight MUST fail closed if any required P0 evidence is missing, invalid, or unreadable,
- successful Phase 0 docs/evidence alone are insufficient unless the named preflight passes,
- the preflight is a release/readiness gate, not a replacement for later runtime PolicyGuard or Phase 2+ status authority.

**Step 3: Tighten the implementation-plan prerequisite wording**

Patch `specs/IMPLEMENTATION_PLAN.md` anywhere Phase 2 micro-live prerequisites or release/readiness wording references Phase 0 implicitly so it now points to the named Phase 0 preflight instead of generic "evidence complete" language.

**Step 4: Re-scan for drift**

Run: `rg -n "live-trading enablement|Phase 0|preflight|completed and evidenced" specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md`
Expected: the contract and implementation plan both refer to the same named Phase 0 enablement gate.

**Step 5: Commit**

```bash
git add specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md
git commit -m "docs: name phase0 live enable preflight"
```

### Task 2: Add paired acceptance coverage for the new guard

**Files:**
- Modify: `specs/CONTRACT.md`
- Modify if traceability requires it: `plans/prd.json`

**Step 1: Reserve explicit AT IDs**

Run: `rg -n "AT-1233|AT-1234" specs/CONTRACT.md plans/prd.json`
Expected: no hits. If either ID is already taken, pick the next unused pair and use those exact IDs consistently in the remaining steps.

**Step 2: Add the TRIP acceptance test**

Add a new acceptance test in `specs/CONTRACT.md` near the Phase 0 section or the closest release/readiness gate section with these properties:
- use explicit heading `AT-1233`,
- ensure it sits under a valid `Profile: CSP` scope (add a nearby `Profile: CSP` line if needed so `tools/at_parser.py` will parse it),
- Given: all other enablement conditions are forced pass,
- Given: one required Phase 0 evidence artifact is missing or invalid,
- When: `bash ./plans/live_enable_preflight.sh` is evaluated for live enablement,
- Then: the preflight exits non-zero and live enablement is blocked.

**Step 3: Add the NON-TRIP acceptance test**

Add the matching acceptance test with these properties:
- use explicit heading `AT-1234`,
- keep it under the same valid `Profile: CSP` scope as the TRIP case,
- Given: all required Phase 0 docs, snapshots, proofs, and Phase 0 runtime checks are valid,
- Given: all other enablement conditions are forced pass,
- When: `bash ./plans/live_enable_preflight.sh` runs,
- Then: the Phase 0 gate does not block live enablement.

**Step 4: Verify parser-safe formatting and traceability**

Re-read the added tests and ensure all of the following:
- both explicitly force all other gates pass so the new guard satisfies the contract's TRIP/NON-TRIP isolation rule,
- both use concrete `AT-1233` / `AT-1234` headings under a valid `Profile: CSP` scope,
- if the active PRD story for this work tracks enforcing AT coverage, add the new AT IDs to that story in `plans/prd.json`; otherwise leave `plans/prd.json` unchanged.

**Step 5: Check the profile parser early**

Run: `python3 tools/ci/check_contract_profiles.py --contract specs/CONTRACT.md`
Expected: `OK:` summary output with no malformed or unscoped AT errors.

**Step 6: Commit**

```bash
git add specs/CONTRACT.md plans/prd.json
git commit -m "docs: add phase0 preflight acceptance coverage"
```

### Task 3: Sync the canonical Phase 0 docs

**Files:**
- Modify: `docs/PHASE0_CHECKLIST_BLOCK.md`
- Modify: `docs/phase0_acceptance.md`
- Modify: `docs/phase0_index.md`

**Step 1: Update the canonical checklist language**

Patch `docs/PHASE0_CHECKLIST_BLOCK.md` so the top-level rule and any relevant unblock conditions make the named preflight explicit:
- Phase 0 is not done unless the evidence pack exists,
- and the named live-enable preflight is the mechanical gate that must pass before live trading is enabled.

**Step 2: Update the acceptance narrative**

Patch `docs/phase0_acceptance.md` so it no longer reads as evidence-only completion text. It should explicitly say the saved artifacts are the inputs to `bash ./plans/live_enable_preflight.sh`.

**Step 3: Update the Phase 0 index**

Add the new script to `docs/phase0_index.md` with a one-line description that it is the canonical live-enable preflight wrapper for Phase 0 evidence validation.

**Step 4: Re-scan the docs**

Run: `rg -n "live_enable_preflight|Phase 0 is DONE|live-trading enablement|evidence pack" docs/PHASE0_CHECKLIST_BLOCK.md docs/phase0_acceptance.md docs/phase0_index.md`
Expected: the three docs use the same gate name and describe the same boundary.

**Step 5: Commit**

```bash
git add docs/PHASE0_CHECKLIST_BLOCK.md docs/phase0_acceptance.md docs/phase0_index.md
git commit -m "docs: sync phase0 preflight references"
```

### Task 4: Add the thin wrapper and guardrail coverage

**Files:**
- Create: `plans/live_enable_preflight.sh`
- Modify: `plans/tests/test_verify_fork_guardrails.sh`
- Modify: `plans/test_verify_fork_smoke.sh`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/workflow_verify.sh`

**Step 1: Extend guardrail coverage first**

Update `plans/tests/test_verify_fork_guardrails.sh`, `plans/test_verify_fork_smoke.sh`, and `plans/tests/test_workflow_allowlist_coverage.sh` before implementation so they require:
- `plans/live_enable_preflight.sh` to exist,
- the script to parse with `bash -n`,
- `plans/verify_fork.sh` to reference the wrapper instead of invoking the Phase 0 checker directly,
- `plans/verify_fork.sh` to keep the existing Phase 0 gate ordering fail-closed.
- `plans/workflow_files_allowlist.txt` to contain `plans/live_enable_preflight.sh` once the wrapper is added.

**Step 2: Run the guardrail checks to see the failure**

Run:
- `bash plans/tests/test_verify_fork_guardrails.sh`
- `bash plans/test_verify_fork_smoke.sh`
- `bash plans/tests/test_workflow_allowlist_coverage.sh`

Expected: at least one assertion fails because `plans/live_enable_preflight.sh` does not exist yet, verify still calls `tools/phase0_meta_test.py` directly, and the new workflow file is not yet registered in the allowlist.

**Step 3: Implement the wrapper**

Create `plans/live_enable_preflight.sh` as a thin wrapper with this behavior:
- resolve repo root from the script location,
- `cd` to repo root,
- honor `PYTHON_BIN` if it is already provided by the caller,
- otherwise match `plans/lib/verify_utils.sh:ensure_python` selection order (`python` first, then `python3`),
- print a deterministic failure message and exit non-zero if no Python interpreter exists,
- execute `tools/phase0_meta_test.py --root "$ROOT"`,
- produce no success-path side effects beyond whatever the delegated checker already emits.

**Step 4: Register the workflow surface and syntax checks**

Update all of the following:
- add `plans/live_enable_preflight.sh` to `plans/workflow_files_allowlist.txt` in sorted order,
- keep `plans/tests/test_workflow_allowlist_coverage.sh` aligned with the new allowlist entry,
- add `plans/live_enable_preflight.sh` to `plans/workflow_verify.sh` so the local harness syntax sweep catches shell regressions immediately.

**Step 5: Re-run the guardrail checks**

Run:
- `bash plans/tests/test_verify_fork_guardrails.sh`
- `bash plans/test_verify_fork_smoke.sh`
- `bash plans/tests/test_workflow_allowlist_coverage.sh`

Expected: all three pass with the wrapper in place and registered as a canonical workflow file.

**Step 6: Commit**

```bash
git add plans/live_enable_preflight.sh plans/tests/test_verify_fork_guardrails.sh plans/test_verify_fork_smoke.sh plans/tests/test_workflow_allowlist_coverage.sh plans/workflow_files_allowlist.txt plans/workflow_verify.sh
git commit -m "test: add phase0 live enable wrapper guardrails"
```

### Task 5: Wire the wrapper into the canonical verify path

**Files:**
- Modify: `plans/verify_fork.sh`
- Review: `plans/verify.sh`
- Review: `plans/preflight.sh`

**Step 1: Replace the direct Phase 0 checker invocation**

Patch `plans/verify_fork.sh` so the existing `phase0_meta_test` gate continues to exist, but the command it runs becomes the wrapper:

```bash
env PYTHON_BIN="$PYTHON_BIN" bash "$ROOT/plans/live_enable_preflight.sh"
```

Do not rename the gate artifact from `phase0_meta_test` unless a separate artifact migration is required. Preserve the current gate position in the verify order to minimize churn.

**Step 2: Leave the stable wrappers alone**

Do not change `plans/verify.sh` beyond what is strictly required by verification. It must remain a thin wrapper. Do not touch the root `./verify.sh`.

**Step 3: Decide whether preflight needs an explicit dedicated test**

Prefer not to add a brand-new preflight test if the existing guardrail test already proves the wrapper is required and the canonical verify path calls it. `plans/tests/test_verify_fork_guardrails.sh` is already in the smoke fixture list, so reuse that existing verify path unless review proves it is insufficient.

**Step 4: Verify the wiring**

Run: `rg -n "phase0_meta_test|live_enable_preflight" plans/verify_fork.sh plans/test_verify_fork_smoke.sh plans/tests/test_verify_fork_guardrails.sh`
Expected: verify still has the `phase0_meta_test` gate name, and the command path flows through `plans/live_enable_preflight.sh`.

**Step 5: Commit**

```bash
git add plans/verify_fork.sh
git commit -m "build: route phase0 gate through live enable preflight"
```

### Task 6: Refresh derived artifacts and run full verification

**Files:**
- Refresh if needed: `docs/contract_kernel.json`
- Verify: `specs/CONTRACT.md`
- Verify: `plans/live_enable_preflight.sh`
- Verify: `plans/verify_fork.sh`

**Step 1: Refresh the contract kernel**

Run: `python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json`
Expected: the kernel hash updates if `specs/CONTRACT.md` changed.

**Step 2: Validate the kernel**

Run: `python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json`
Expected: the kernel check passes.

**Step 3: Run the local workflow harness check**

Run: `./plans/workflow_verify.sh`
Expected: syntax checks and `./plans/verify.sh quick` pass.

**Step 4: Run canonical verify**

Run:
- `./plans/verify.sh quick`
- `./plans/verify.sh full`

Expected: both pass and `artifacts/verify/<run_id>/` contains the normal verify artifacts. If full verify is blocked by a dirty tree, follow the repo policy: use CI clean-checkout verify or clean the tree first; do not set `VERIFY_ALLOW_DIRTY=1` without explicit owner approval recorded in `plans/progress.txt`.

**Step 5: Run review before final handoff**

After the harness and contract changes are in place, run the `code-review-expert` skill against the diff before the final verify/merge pass. Treat any blocking workflow or fail-closed findings as stop-ship.

**Step 6: Commit**

```bash
git add specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md docs/PHASE0_CHECKLIST_BLOCK.md docs/phase0_acceptance.md docs/phase0_index.md plans/prd.json plans/live_enable_preflight.sh plans/verify_fork.sh plans/workflow_verify.sh plans/test_verify_fork_smoke.sh plans/tests/test_verify_fork_guardrails.sh plans/tests/test_workflow_allowlist_coverage.sh plans/workflow_files_allowlist.txt docs/contract_kernel.json
git commit -m "docs: enforce phase0 live enable preflight"
```

## Deferred Work

- Do not add runtime dispatch blocking logic keyed directly to Phase 0 evidence artifacts in this change. That would mix release governance with hot-path enforcement.
- Do not rename the existing `phase0_meta_test` verify artifact unless a follow-up explicitly handles artifact/reporting churn.
- Do not touch root `./verify.sh` unless a separate instruction explicitly requires it.
