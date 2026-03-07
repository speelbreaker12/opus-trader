# PRD Auditor Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the verified PRD-auditor safety and determinism gaps, especially `eval`-based argv execution, ROADMAP ref validation drift, audit summary type ambiguity, and duplicated decision/hash logic.

**Architecture:** Keep the current shell-first toolchain intact and harden it incrementally behind focused shell regression tests. Reuse existing repo patterns instead of inventing a parallel framework: shell fixture tests under `plans/tests/`, ROADMAP-ref detection precedent from `plans/prd_slice_prepare.sh`, and shared hashing through `plans/lib/hash_utils.sh`.

**Tech Stack:** Bash, Python 3, jq, existing shell fixture tests in `plans/tests/`.

**Constraints:**
- The worktree is already dirty. Do not revert unrelated user changes.
- Keep write scope limited to `plans/`, `prompts/auditor.md`, `plans/tests/`, and `plans/PRD_WORKFLOW.md`.
- Prefer behavior tests over grep-only tests except for pure prompt/doc guardrails.
- Shell changes and tests must stay compatible with Bash 3.2 on macOS; do not rely on `mapfile` / `readarray` or other Bash 4+-only features.
- If shared hash helpers are adopted, preserve current missing-file behavior (`""` hash, no hard failure) unless the same task updates every caller and fixture accordingly.

---

### Task 1: Remove `eval` From `prd_pipeline.sh`

**Files:**
- Modify: `plans/prd_pipeline.sh`
- Create: `plans/tests/test_prd_pipeline.sh`
- Test: `plans/tests/test_guard_no_command_substitution.sh`

**Step 1: Write the failing test**

- In `plans/tests/test_prd_pipeline.sh`, create a temp repo fixture that copies:
  - `plans/prd_pipeline.sh`
  - `plans/prd_schema_check.sh` stub returning `0`
  - `plans/prd_gate.sh` or a custom gate stub that records received argv to a file
- Add a case where:
  - `PRD_GATE_ARGS='--label "two words"'`
  - the stub gate records its argv
  - the test asserts the stub receives one token `two words`, not two split tokens
- Add a second case where:
  - `PRD_GATE_ARGS='--label "$(touch "$tmp_dir/pwned")"'`
  - the test asserts `$tmp_dir/pwned` is **not** created

**Step 2: Run test to verify it fails**

Run:

```bash
bash plans/tests/test_prd_pipeline.sh
```

Expected: FAIL on the current `eval "arg_arr=($args)"` path.

**Step 3: Write minimal implementation**

- In `plans/prd_pipeline.sh`, replace the `eval` branch with a helper such as `parse_cmd_args()`.
- Implement parsing with a non-executing parser:
  - recommended: `python3` + `shlex.split()` emitting NUL-delimited argv
  - consume it in Bash 3.2 with `while IFS= read -r -d '' arg; do arg_arr+=("$arg"); done < <(...)`
  - do not use `mapfile` / `readarray`; the repo shell baseline is Bash 3.2
- Preserve the current `PRD_*_ARGS` interface so callers do not need a migration in the same patch.
- Fail fast with a clear error if parsing fails.

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_prd_pipeline.sh
bash plans/tests/test_guard_no_command_substitution.sh
```

Expected: both PASS.

**Step 5: Commit**

```bash
git add plans/prd_pipeline.sh plans/tests/test_prd_pipeline.sh plans/tests/test_guard_no_command_substitution.sh
git commit -m "fix: remove eval from prd pipeline args"
```

---

### Task 2: Handle Pipeline Timeouts As Timeouts, Not Generic Failures

**Files:**
- Modify: `plans/prd_pipeline.sh`
- Modify: `plans/tests/test_prd_pipeline.sh`

**Step 1: Extend the failing test**

- In `plans/tests/test_prd_pipeline.sh`, add timeout fixtures for each pipeline-owned `run_cmd()` path that should classify timeouts explicitly:
  - initial Stage A gate timeout:
    - stub gate sleeps longer than `PIPELINE_CMD_TIMEOUT`
    - pipeline is run with `MAX_REPAIR_PASSES=2`
    - assert the pipeline exits after the first timeout instead of burning all passes
    - assert `.context/prd_pipeline_blocked.json` reports `GATE_TIMEOUT`
  - Stage A cutter or autofix timeout:
    - stub cutter or autofix sleeps past timeout
    - assert blocked JSON reports `CUTTER_TIMEOUT` or `AUTOFIX_TIMEOUT` rather than exiting without a classified reason
  - Stage B auditor timeout:
    - stub auditor sleeps past timeout after Stage A succeeds
    - assert blocked JSON reports `AUDIT_TIMEOUT`, not generic `AUDIT_FAIL`
  - final gate timeout:
    - make Stage A and Stage B succeed, then have the final gate sleep past timeout
    - assert blocked JSON reports `FINAL_GATE_TIMEOUT`, not generic `FINAL_GATE_FAIL`

**Step 2: Run test to verify it fails**

Run:

```bash
bash plans/tests/test_prd_pipeline.sh
```

Expected: FAIL because current Stage A logic retries gate timeouts, Stage B/C still collapse timeouts into generic failure reasons, and cutter/autofix timeout paths are not classified because those call sites currently run under `set -e`.

**Step 3: Write minimal implementation**

- In `plans/prd_pipeline.sh`, preserve the existing timeout return codes from `run_cmd()`.
- Add a small helper to invoke `run_cmd()` under `set +e` and return its rc to the caller without losing the script's global `set -e` behavior.
- Branch on `124` / `137` at every pipeline-owned `run_cmd()` call site:
  - Stage A gate: emit `GATE_TIMEOUT`
  - `PRD_AUTOFIX`: emit `AUTOFIX_TIMEOUT`
  - `PRD_CUTTER`: emit `CUTTER_TIMEOUT`
  - Stage B auditor: emit `AUDIT_TIMEOUT`
  - final gate: emit `FINAL_GATE_TIMEOUT`
- If optional Stage B.1 patcher remains timeout-wrapped in the same patch, classify it explicitly too (`PATCHER_TIMEOUT`) rather than leaving it generic.
- Stop the repair / pipeline flow immediately for timeout cases.
- Keep ordinary lint/gate failures on the existing retry path.

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_prd_pipeline.sh
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plans/prd_pipeline.sh plans/tests/test_prd_pipeline.sh
git commit -m "fix: classify prd pipeline timeout failures explicitly"
```

---

### Task 3: Make `prd_ref_check.sh` ROADMAP-Aware And Remove The `S8-020` Special Case

**Files:**
- Modify: `plans/prd_ref_check.sh`
- Modify: `plans/prd_lint.sh`
- Modify: `plans/tests/test_prd_ref_check_status_lite_markers.sh`
- Create: `plans/tests/test_prd_ref_check_roadmap_refs.sh`

**Step 1: Write the failing ROADMAP and compact-status tests**

- In `plans/tests/test_prd_ref_check_roadmap_refs.sh`, add fixture repos with:
  - `specs/CONTRACT.md`
  - `specs/IMPLEMENTATION_PLAN.md`
  - `docs/ROADMAP.md`
  - a PRD containing a `category=policy` or `category=infra` item using `ROADMAP.md P0-A ...`
- Add cases:
  - existing ROADMAP ref resolves and exits `0`
  - missing ROADMAP ref exits non-zero with an `unresolved roadmap_ref` style diagnostic
- In `plans/tests/test_prd_ref_check_status_lite_markers.sh`, add a synthetic non-`S8-020` story containing all `compact_csp_status_markers`, then assert it does not emit missing-CSP-key warnings.

**Step 2: Run tests to verify they fail**

Run:

```bash
bash plans/tests/test_prd_ref_check_roadmap_refs.sh
bash plans/tests/test_prd_ref_check_status_lite_markers.sh
```

Expected: ROADMAP case fails today; compact-status case still depends on the hardcoded `S8-020` ID.

**Step 3: Write minimal implementation**

- In `plans/prd_ref_check.sh`:
  - load `docs/ROADMAP.md` / `ROADMAP.md` when present
  - build a dedicated `roadmap_haystack`
  - detect ROADMAP refs using the same broad rules already used in `plans/prd_slice_prepare.sh` (`ROADMAP` token and `P\d+-[A-Z]` anchors)
  - validate policy/infra ROADMAP refs against `roadmap_haystack`, not `contract_haystack`
  - emit `roadmap` diagnostics distinctly from `contract` diagnostics
- Replace the `sid == 'S8-020'` branch with content-based detection:
  - if all compact CSP markers are present, treat the item as `compact_csp_status`
  - do not key the behavior to one story ID
- In `plans/prd_lint.sh`, update unresolved-ref guidance so policy/infra ROADMAP refs do not always point users back to `specs/CONTRACT.md`.

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_prd_ref_check_roadmap_refs.sh
bash plans/tests/test_prd_ref_check_status_lite_markers.sh
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plans/prd_ref_check.sh plans/prd_lint.sh plans/tests/test_prd_ref_check_roadmap_refs.sh plans/tests/test_prd_ref_check_status_lite_markers.sh
git commit -m "fix: validate roadmap refs and generalize compact status checks"
```

---

### Task 4: Tighten Audit Summary Typing And Reuse One Decision Helper

**Files:**
- Modify: `plans/prd_audit_check.sh`
- Modify: `plans/run_prd_auditor.sh`
- Modify: `plans/tests/test_prd_audit_check.sh`
- Create: `plans/tests/test_run_prd_auditor_decision_outputs.sh`

**Step 1: Write the failing tests**

- In `plans/tests/test_prd_audit_check.sh`, add a case where summary counts are strings:
  - `"items_total": "1"`
  - `"items_pass": "1"`
  - etc.
  - assert the script fails with a type-specific error such as `summary counts must be numbers, not strings`
- In `plans/tests/test_run_prd_auditor_decision_outputs.sh`, reuse the fixture style from `plans/tests/test_run_prd_auditor_timeout_fallback.sh` but swap in a deterministic auditor stub that writes a tiny audit JSON.
- Add PASS / FAIL / BLOCKED cases and assert:
  - `plans/prd_audit.json` is accepted by `prd_audit_check.sh`
  - `.context/prd_audit_cache.json` gets the expected `decision`
  - `.context/audit_costs.jsonl` ends with the same final decision

**Step 2: Run tests to verify they fail**

Run:

```bash
bash plans/tests/test_prd_audit_check.sh
bash plans/tests/test_run_prd_auditor_decision_outputs.sh
```

Expected: FAIL on string-count diagnostics and/or duplicated decision behavior.

**Step 3: Write minimal implementation**

- In `plans/prd_audit_check.sh`, replace the current `tonumber? != null` precheck with explicit numeric-type validation for all summary count fields.
- Keep fail-closed behavior, but make the error message type-specific.
- In `plans/run_prd_auditor.sh`, add a single helper such as `compute_audit_decision()` that derives PASS / FAIL / BLOCKED from the validated audit JSON once.
- Feed that same value into:
  - `write_audit_cache`
  - `audit_cost_end`

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_prd_audit_check.sh
bash plans/tests/test_run_prd_auditor_decision_outputs.sh
bash plans/tests/test_run_prd_auditor_timeout_fallback.sh
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plans/prd_audit_check.sh plans/run_prd_auditor.sh plans/tests/test_prd_audit_check.sh plans/tests/test_run_prd_auditor_decision_outputs.sh plans/tests/test_run_prd_auditor_timeout_fallback.sh
git commit -m "fix: harden audit summary typing and unify decision derivation"
```

---

### Task 5: Reuse `plans/lib/hash_utils.sh` And Add Stage Outcome Data To Cost Logs

**Files:**
- Modify: `plans/run_prd_auditor.sh`
- Modify: `plans/prd_pipeline.sh`
- Modify: `plans/prd_audit_check.sh`
- Modify: `plans/lib/hash_utils.sh`
- Create: `plans/tests/test_prd_hash_utils_adoption.sh`
- Modify: `plans/tests/test_prd_pipeline.sh`
- Modify: `plans/tests/test_run_prd_auditor_decision_outputs.sh`
- Modify: `plans/tests/test_run_prd_auditor_timeout_fallback.sh`

**Step 1: Write the failing tests**

- In `plans/tests/test_prd_hash_utils_adoption.sh`, assert:
  - `plans/run_prd_auditor.sh` sources `plans/lib/hash_utils.sh`
  - `plans/prd_pipeline.sh` sources `plans/lib/hash_utils.sh`
  - `plans/prd_audit_check.sh` sources `plans/lib/hash_utils.sh`
  - those files no longer declare local `sha256_file()` / `hash_file()` helpers
- Also assert the shared helper path preserves current caller expectations for missing files:
  - hashing a missing file returns an empty string
  - callers do not hard-fail just because an optional file is absent
- Extend copied-script fixture tests (`plans/tests/test_prd_pipeline.sh`, `plans/tests/test_run_prd_auditor_decision_outputs.sh`, and `plans/tests/test_run_prd_auditor_timeout_fallback.sh`) so their temp repos also copy `plans/lib/hash_utils.sh`
- Extend `plans/tests/test_run_prd_auditor_timeout_fallback.sh` to assert stage JSONL entries include a per-stage outcome field such as `rc`.

**Step 2: Run tests to verify they fail**

Run:

```bash
bash plans/tests/test_prd_hash_utils_adoption.sh
bash plans/tests/test_run_prd_auditor_timeout_fallback.sh
```

Expected: FAIL because the scripts still carry local hash helpers, copied-script fixtures do not yet stage the shared helper, the shared helper semantics do not yet match callers, and cost stages omit `rc`.

**Step 3: Write minimal implementation**

- Pick one compatibility path and keep it explicit:
  - preferred: extend `plans/lib/hash_utils.sh` so missing files return `""` with rc `0`, matching current callers
  - alternative: add tiny compatibility wrappers in each caller before removing local helpers
- Source `plans/lib/hash_utils.sh` from:
  - `plans/run_prd_auditor.sh`
  - `plans/prd_pipeline.sh`
  - `plans/prd_audit_check.sh`
- Remove local duplicate hash helpers from those scripts.
- Update copied-script fixture tests so temp repos also stage `plans/lib/hash_utils.sh` before invoking the hardened scripts.
- Update `audit_cost_stage()` in `plans/run_prd_auditor.sh` to accept and record an `rc` (or `result`) argument.
- Pass actual stage outcomes at each `audit_cost_stage()` call site.

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_prd_hash_utils_adoption.sh
bash plans/tests/test_prd_pipeline.sh
bash plans/tests/test_run_prd_auditor_decision_outputs.sh
bash plans/tests/test_run_prd_auditor_timeout_fallback.sh
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plans/lib/hash_utils.sh plans/run_prd_auditor.sh plans/prd_pipeline.sh plans/prd_audit_check.sh plans/tests/test_prd_hash_utils_adoption.sh plans/tests/test_prd_pipeline.sh plans/tests/test_run_prd_auditor_decision_outputs.sh plans/tests/test_run_prd_auditor_timeout_fallback.sh
git commit -m "refactor: share hash helper and log audit stage outcomes"
```

---

### Task 6: Align Prompt And Docs With Enforced Behavior

**Files:**
- Modify: `prompts/auditor.md`
- Modify: `plans/PRD_WORKFLOW.md`
- Create: `plans/tests/test_prd_auditor_prompt.sh`

**Step 1: Write the failing guard test**

- In `plans/tests/test_prd_auditor_prompt.sh`, assert:
  - `prompts/auditor.md` includes `loss_mode` in the required item fields
  - the `failure_mode` enum line in `prompts/auditor.md` matches the schema enum in `plans/prd_schema_check.sh`
- Add a simple grep-based check that `plans/PRD_WORKFLOW.md` no longer jumps from `8.` to `11.` in the recommended story loop.

**Step 2: Run test to verify it fails**

Run:

```bash
bash plans/tests/test_prd_auditor_prompt.sh
```

Expected: FAIL because `loss_mode` is missing and the workflow numbering gap still exists.

**Step 3: Write minimal implementation**

- In `prompts/auditor.md`:
  - add `loss_mode` to the required field list
  - add one short semantic reminder where the prompt already discusses risk / fail-closed checks
- Keep the current `failure_mode` values unchanged, but make the prompt line exactly match the schema line to reduce drift.
- In `plans/PRD_WORKFLOW.md`, restore steps `9.` and `10.` or renumber the section cleanly.

**Step 4: Run tests to verify it passes**

Run:

```bash
bash plans/tests/test_prd_auditor_prompt.sh
```

Expected: PASS.

**Step 5: Commit**

```bash
git add prompts/auditor.md plans/PRD_WORKFLOW.md plans/tests/test_prd_auditor_prompt.sh
git commit -m "docs: align prd auditor prompt and workflow docs"
```

---

## Recommended Execution Order

1. Task 1
2. Task 2
3. Task 3
4. Task 4
5. Task 5
6. Task 6

Reasoning:
- Task 1 removes the only verified P0 issue.
- Task 2 builds on the same new pipeline test harness.
- Task 3 closes the highest-value deterministic validation gap.
- Task 4 fixes validator correctness/diagnostics before further refactoring.
- Task 5 is cleanup that should follow behavior stabilization.
- Task 6 is lowest-risk prompt/doc alignment.

---

## Deferred Follow-Ups (Not Required For The First Pass)

- Add a sentinel / field-count guard to the long `jq` → `read` record packing in `plans/prd_lint.sh`.
- Add dedicated suites for `plans/prd_autofix.sh`, `plans/prd_slice_prepare.sh`, and `plans/contract_prd_matrix.py`.
- If drift keeps recurring, move the `failure_mode` enum to a canonical shared source instead of relying only on the new prompt guard test.

---

## Final Verification Sweep

After all tasks are complete, run:

```bash
bash plans/tests/test_prd_pipeline.sh
bash plans/tests/test_prd_ref_check_roadmap_refs.sh
bash plans/tests/test_prd_ref_check_status_lite_markers.sh
bash plans/tests/test_prd_audit_check.sh
bash plans/tests/test_run_prd_auditor_decision_outputs.sh
bash plans/tests/test_run_prd_auditor_invocation.sh
bash plans/tests/test_run_prd_auditor_timeout_fallback.sh
bash plans/tests/test_prd_hash_utils_adoption.sh
bash plans/tests/test_prd_auditor_prompt.sh
```

Then run a broader smoke pass:

```bash
./plans/verify.sh quick
```

Expected:
- all new targeted tests PASS
- `./plans/verify.sh quick` reaches the repo's current clean baseline or fails only on unrelated pre-existing branch issues
