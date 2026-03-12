# PRD Lint Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the proven correctness gap in `plans/prd_lint.sh`, harden `--json` output, and reduce avoidable heuristic noise without a wholesale rewrite.

**Architecture:** Keep the linter in Bash. Add the missing `docs/contract_kernel.json` metadata load, replace the fragile JSON record construction with a safe encoder path, and tighten the existing matching heuristics in place. Make the change self-proving by extending the isolated lint fixture setup and wiring the new lint/gate checks into the real `plans/preflight.sh` / `plans/verify.sh` workflow surface instead of relying on standalone shell tests alone.

**Tech Stack:** Bash 3.2-compatible shell, `jq`, shell tests in `plans/tests/`, workflow verification via `./plans/workflow_verify.sh` and `./plans/verify.sh`.

---

## Validated Baseline

- Reviewed against repo `5f80fd4` on branch `wip/main-pre-sync-20260304`.
- `plans/prd_lint.sh` is 932 lines in this revision.
- The anchor/VR finding is confirmed: the arrays are referenced but never populated, so `MISSING_ANCHOR_REF` and `MISSING_VR_REF` cannot currently fire.
- The `json_escape` bug is confirmed only when a literal control character reaches the manual JSON builder. It is a real robustness bug for `--json`, but it is not a P0 gate-decision failure.
- `plans/tests/test_prd_lint.sh` currently scaffolds `plans/verify.sh` and `plans/prd_schema_check.sh`, but it does not create `docs/contract_kernel.json`; any fail-closed kernel load must add that fixture setup first.
- The current verify surface does not exercise `plans/tests/test_prd_lint.sh` or `plans/tests/test_prd_gate.sh`; `./plans/workflow_verify.sh` only becomes meaningful for this change once the preflight fixture matrix is updated.
- Lower-priority cleanup such as temp-file trap refactoring, `sort` guard removal, or `nocasematch` restoration should stay out of the first pass unless a concrete regression is demonstrated.

## Implementation Order

1. Restore dead anchor/VR enforcement.
2. Make `--json` output robust.
3. Wire the lint/gate coverage into the real verify surface.
4. Normalize inconsistent string-matching behavior.

### Task 1: Restore Anchor/VR Enforcement

**Files:**
- Modify: `plans/prd_lint.sh`
- Modify: `plans/prd_gate_help.md`
- Test: `plans/tests/test_prd_lint.sh`

**Step 1: Write the failing tests**

- Extend the temp lint fixture harness to create a minimal `docs/contract_kernel.json` with at least two anchors and two validation rules, including non-first IDs.
- Add a fixture or inline PRD case where `contract_refs` mentions an anchor title without `Anchor-###`.
- Add a second case where `contract_refs` mentions a validation rule title without `VR-###`.
- Add acceptance cases proving mechanically valid forms still count, including `Anchor-###: Title`, `VR-###: Title`, and `CONTRACT.md Anchor-###` / `CONTRACT.md VR-###`.
- Add a negative case where `docs/contract_kernel.json` is missing or unreadable and assert a deterministic fail-closed lint error.
- Assert the linter exits non-zero and prints `MISSING_ANCHOR_REF` / `MISSING_VR_REF` for the title-only cases.

**Step 2: Run the targeted tests and confirm failure**

Run: `bash plans/tests/test_prd_lint.sh`  
Expected: the new anchor/VR cases fail because the arrays are never populated, and the kernel-missing case fails because there is not yet a deterministic metadata-load guard.

**Step 3: Implement the metadata load**

- Read `docs/contract_kernel.json` once before the per-item loop.
- Populate `anchor_ids[]` / `anchor_titles[]` from `.anchors[]`.
- Populate `vr_ids[]` / `vr_titles[]` from `.validation_rules[]`.
- Keep the implementation Bash 3.2-compatible.
- If the kernel file is missing, unreadable, or invalid JSON, fail closed with a deterministic lint error rather than silently skipping enforcement.
- Treat Anchor/VR IDs as present via boundary-aware matching inside a `contract_refs` token, not only as exact raw-string entries.
- Add dedicated `suggest_fix` branches for `MISSING_ANCHOR_REF` and `MISSING_VR_REF`.

**Step 4: Re-run the targeted tests**

Run: `bash plans/tests/test_prd_lint.sh`  
Expected: the new cases pass, the valid ID-format cases are accepted, and existing lint cases stay green.

**Step 5: Commit**

```bash
git add plans/prd_lint.sh plans/prd_gate_help.md plans/tests/test_prd_lint.sh
git commit -m "fix: restore prd anchor and vr lint enforcement"
```

### Task 2: Replace the Fragile JSON Record Builder

**Files:**
- Modify: `plans/prd_lint.sh`
- Test: `plans/tests/test_prd_lint.sh`
- Smoke coverage: `plans/tests/test_prd_gate.sh`

**Step 1: Write the failing tests**

- Add a test that forces a literal tab or carriage return into an emitted lint message and invokes `plans/prd_lint.sh --json`.
- Add a gate-level case in `plans/tests/test_prd_gate.sh` that sets `PRD_LINT_JSON`, runs `plans/prd_gate.sh`, validates the emitted file with `jq -e`, and asserts the expected error object preserves the message content via JSON escapes.
- Assert the direct `--json` file is valid `jq -e .` output and includes the expected error object.

**Step 2: Run the targeted tests and confirm failure**

Run:
- `bash plans/tests/test_prd_lint.sh`
- `bash plans/tests/test_prd_gate.sh`

Expected: the new direct `--json` control-character case fails with the current `json_escape()` implementation, and the new gate-level `PRD_LINT_JSON` case also fails.

**Step 3: Implement the minimal safe fix**

- Stop hand-assembling JSON strings with `json_escape()` if possible.
- Preferred path: build error/warning objects with `jq -n --arg ...` or another full JSON encoder and store serialized objects directly.
- If `json_escape()` remains, escape the full control-character range, not just `\n`.
- Keep the existing `finish()` JSON schema unchanged so `PRD_LINT_JSON` consumers do not break.

**Step 4: Re-run the targeted tests**

Run:
- `bash plans/tests/test_prd_lint.sh`
- `bash plans/tests/test_prd_gate.sh`

Expected: both pass, the `--json` artifact remains valid JSON, and the gate path preserves the escaped message content that downstream consumers read.

**Step 5: Commit**

```bash
git add plans/prd_lint.sh plans/tests/test_prd_lint.sh plans/tests/test_prd_gate.sh
git commit -m "fix: harden prd lint json output"
```

### Task 3: Wire PRD Lint Coverage into the Workflow Verify Surface

**Files:**
- Modify: `plans/preflight.sh`
- Test: `plans/tests/test_preflight_fixture_profiles.sh`
- Test: `plans/tests/test_prd_lint.sh`
- Test: `plans/tests/test_prd_gate.sh`

**Step 1: Write the failing tests**

- Extend `plans/tests/test_preflight_fixture_profiles.sh` to assert that `plans/tests/test_prd_lint.sh` and `plans/tests/test_prd_gate.sh` are included in the preflight fixture matrix and update the expected counts accordingly.
- If a fixture-profile helper test is sensitive to the list edits, update that expectation in the same task rather than leaving a stale count.

**Step 2: Run the targeted tests and confirm failure**

Run: `bash plans/tests/test_preflight_fixture_profiles.sh`  
Expected: the fixture profile test fails because the new lint/gate coverage is not yet part of `plans/preflight.sh`.

**Step 3: Implement the minimal code change**

- Add `plans/tests/test_prd_lint.sh` and `plans/tests/test_prd_gate.sh` to the preflight fixture matrix so `./plans/verify.sh quick|full` exercises them.
- Keep the implementation in `plans/preflight.sh` unless a new dedicated verify gate is truly needed; `./plans/workflow_verify.sh` should pick up the new coverage indirectly through `./plans/verify.sh quick`.
- Update the fixture profile test to match the new list membership and counts.

**Step 4: Re-run the targeted tests**

Run:
- `bash plans/tests/test_preflight_fixture_profiles.sh`
- `./plans/workflow_verify.sh`

Expected: the fixture profile test passes, and workflow verify now exercises the lint/gate tests through quick verify instead of relying only on standalone commands.

**Step 5: Commit**

```bash
git add plans/preflight.sh plans/tests/test_preflight_fixture_profiles.sh
git commit -m "test: add prd lint coverage to workflow verify surface"
```

### Task 4: Normalize Matching Behavior and Forward-Keyword Detection

**Files:**
- Modify: `plans/prd_lint.sh`
- Test: `plans/tests/test_prd_lint.sh`

**Step 1: Write the failing test**

- Add coverage showing `check_stale_recon_ref` behaves the same for GLOBAL and per-item call sites.
- Add a forward-keyword case that proves `firewall`, `withdrawal`, or `utf16` must not trigger `FORWARD_KEYWORD`.
- Preserve positive cases where `PolicyGuard`, `EvidenceGuard`, `F1`, `replay`, or `WAL` still trigger.

**Step 2: Run the targeted tests and confirm failure**

Run: `bash plans/tests/test_prd_lint.sh`  
Expected: false-positive substring matches or split-case behavior reproduce before the fix.

**Step 3: Implement the minimal code change**

- Make `check_stale_recon_ref` explicitly control its own case-matching behavior, or move the GLOBAL calls below `shopt -s nocasematch`.
- Replace the glob-based forward keyword check with a single boundary-aware regex.
- Use one canonical keyword extraction path so the emitted fix guidance matches the detected term.

**Step 4: Re-run the targeted tests**

Run: `bash plans/tests/test_prd_lint.sh`  
Expected: the false positives disappear and the real forward-keyword cases still warn/error as configured.

**Step 5: Commit**

```bash
git add plans/prd_lint.sh plans/tests/test_prd_lint.sh
git commit -m "fix: tighten prd lint keyword matching"
```

## Deferred Work

- Bulk extraction alignment/sentinel guard: defer unless a concrete misalignment bug is demonstrated; the current pass already fail-closes on bulk `jq` extraction errors.
- Temp-file cleanup refactor for the `jq` stderr file: defer unless an actual leak is reproduced; the current success/failure paths already remove the file.
- `plans/prd_ref_check.sh` / `plans/prd_lint.sh` contract-ref enforcement consolidation: defer to a dedicated follow-up if duplicate logic becomes a maintenance issue.
- `command -v sort` removal: low value, no user-visible impact.
- `nocasematch` restoration at process exit: only worth doing if the script is intentionally sourced as a library.
- `suggest_fix` echo command-substitution cleanup: harmless but good opportunistic cleanup if the touched section is already open.

## Verification Sequence

1. Run focused lint tests after each task:

```bash
bash plans/tests/test_prd_lint.sh
```

2. Run gate smoke after Task 2 or any change touching `PRD_LINT_JSON` shape:

```bash
bash plans/tests/test_prd_gate.sh
```

3. After wiring the tests into preflight, verify the fixture-profile coverage itself:

```bash
bash plans/tests/test_preflight_fixture_profiles.sh
```

4. Because this changes workflow/harness code, run workflow verification before final full verify:

```bash
./plans/workflow_verify.sh
```

5. Run final repo verification from a clean worktree, or rely on CI verify from a clean checkout:

```bash
./plans/verify.sh full
```

6. Before merge, run the default external review step required by the repo workflow for significant harness changes.

## Evidence To Collect

- Failing and passing test output for the new anchor/VR cases, including a missing/unreadable-kernel failure.
- Failing and passing `--json` control-character reproduction using a literal tab or carriage return.
- Failing and passing `PRD_LINT_JSON` gate-path output proving the JSON artifact stays valid and message-preserving.
- Passing `bash plans/tests/test_preflight_fixture_profiles.sh` output showing the new lint/gate tests are part of the preflight matrix.
- Final `./plans/workflow_verify.sh` output.
- Final `./plans/verify.sh full` artifact path under `artifacts/verify/<run_id>/`, or CI proof from a clean checkout if local full verify is not clean.

## Done Criteria

- `MISSING_ANCHOR_REF` and `MISSING_VR_REF` are provably reachable across multiple Anchor/VR IDs, and mechanically valid ID-bearing ref formats are accepted.
- `plans/prd_lint.sh --json` emits valid JSON even when messages contain literal control characters, and the `PRD_LINT_JSON` gate path preserves the escaped message content.
- Missing or unreadable `docs/contract_kernel.json` fails closed with a deterministic lint error.
- The real verify surface executes the new lint/gate tests through preflight.
- Forward keyword detection is boundary-aware.
- `./plans/verify.sh full` passes with updated tests on a clean worktree or equivalent CI clean checkout.
