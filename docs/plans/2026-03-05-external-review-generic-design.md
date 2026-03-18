# External Review Generic Skill Design

Date: 2026-03-05
Status: Proposed

## Goal

Add one thin convenience command:

```bash
/external-review-generic <target>
```

It should:

- run `codex`, `opus`, `kimi`, and `gemini` generic reviews in parallel
- work on a PR, a commit, specific files, or the current tracked local diff
- write one short consolidated summary with authoritative per-tool status

This is a convenience tool, not a new workflow gate.

## Non-Goals

- No enriched-mode support
- No reconciliation or `passes=true` integration
- No overlap matrix, proof graph, or heavy deduplication logic
- No auto-fix behavior
- No new reviewer-specific CLI contract beyond what existing scripts already support
- No implicit untracked-file discovery in no-arg mode; untracked files must be passed explicitly via `--files` in v1

## Supported Inputs

Primary forms:

```bash
/external-review-generic PR190
/external-review-generic #190
/external-review-generic 190
/external-review-generic --commit HEAD
/external-review-generic --base origin/main
/external-review-generic --files "path1 path2"
/external-review-generic
```

Behavior:

- `PR190`, `#190`, `190` = review that PR diff
- `--commit <sha|ref>` = review one commit
- `--base <ref>` = review current branch diff vs base
- `--files "<paths>"` = review selected files
- no args = review current tracked working-tree diff only; untracked files must be named explicitly with `--files`

## Implementation Shape

Files:

- `SKILLS/external-review-generic.md`
- `docs/skills/index.md`
- `plans/external_review_generic.sh`

If the new `plans/` entrypoint lands, wire it into workflow verification surfaces:

- `plans/workflow_verify.sh`
- `plans/workflow_files_allowlist.txt`
- `plans/tests/test_workflow_allowlist_coverage.sh`

Reuse existing scripts:

- `plans/parallel_review.sh`
- `plans/review_logged.sh`

The new script should stay thin and only do:

1. target normalization plus safe `RUN_ID` generation
2. parallel dispatch via `plans/parallel_review.sh`
3. authoritative status capture plus simple summary generation

## Execution Flow

### 1) Normalize target and run id

Convert the user input into one review mode:

- PR token -> PR mode
- `--commit` -> pass through
- `--base` -> pass through
- `--files` -> pass through
- no args -> use `--uncommitted` for the current tracked working-tree diff only

Derive a shell-safe, filesystem-safe `RUN_ID` for `plans/parallel_review.sh` and artifact paths. It must stay within `[A-Za-z0-9_-]`, for example:

```text
external_review_generic_20260305T220000Z_pr_190
external_review_generic_20260305T220000Z_commit_HEAD
```

The requested target string is display text only; it must not be used directly as the `RUN_ID`.

### 2) Resolve PR mode deterministically

PR mode must run against the actual PR head commit and an explicit resolved base ref. Use this sequence:

1. Resolve PR metadata with:

   ```bash
   gh pr view <PR> --json number,baseRefName,headRefOid
   ```

2. Create a temporary worktree.
3. Fetch both refs from the repo remote:

   ```bash
   git fetch origin "<baseRefName>" "pull/<PR>/head:refs/tmp/external-review/pr-<PR>"
   ```

4. Create a detached worktree at `refs/tmp/external-review/pr-<PR>`.
5. Run the reviews inside that worktree with:

   ```bash
   plans/parallel_review.sh "$RUN_ID" \
     --tools codex,opus,kimi,gemini \
     --prompt generic \
     --base "origin/<baseRefName>"
   ```

6. Clean up the temporary worktree and temp ref afterward.

Important:

- Do not pass the raw PR token to `parallel_review.sh`.
- Do not use `headRefName` as the diff basis.
- The review basis for PR mode is always `git diff origin/<baseRefName>...HEAD` inside the temporary PR-head worktree.

### 3) Dispatch all four reviews

Run:

```bash
plans/parallel_review.sh "$RUN_ID" \
  --tools codex,opus,kimi,gemini \
  --prompt generic \
  <resolved mode args>
```

Notes:

- Use the existing model defaults from `plans/review_logged.sh`
- Allow `CODEX_MODEL` and `GEMINI_MODEL` env overrides to pass through naturally
- Do not add extra model flags in v1

Wrapper responsibilities during dispatch:

- tee `plans/parallel_review.sh` output to a temporary dispatch log
- parse the authoritative per-tool completion lines (`[done] ... exit=0` / `[FAIL] ... exit=<rc>`)
- write `artifacts/story/<RUN_ID>/external_review_generic/dispatch_status.json`
- treat those recorded exit codes as the source of truth for reviewer success/failure

Artifact presence alone must never be used to infer reviewer success.

### 4) Build a short summary

Read:

- `artifacts/story/<RUN_ID>/external_review_generic/dispatch_status.json`
- `artifacts/story/<RUN_ID>/codex/codex.generic.md`
- `artifacts/story/<RUN_ID>/opus/opus.generic.md`
- `artifacts/story/<RUN_ID>/kimi/kimi.generic.md`
- `artifacts/story/<RUN_ID>/gemini/gemini.generic.md`
- `artifacts/story/<RUN_ID>/review_logs/*.log` when a reviewer fails

Then write:

- `artifacts/story/<RUN_ID>/external_review_generic/summary.md`

The summary should be simple and operator-friendly.

## Summary Format

Required sections:

1. Target reviewed
2. Per-tool status (`OK` / `FAIL`, plus exit code)
3. Per-tool `P0/P1/P2` counts
4. Short merged findings list
5. Failures, missing artifacts, or inconsistent outputs

Rules:

- Only parse finding counts from reviewers whose recorded exit code is `0`
- If a reviewer exit code is non-zero, mark counts as `unavailable` rather than treating artifact contents as trusted
- If a reviewer exit code is `0` but the canonical `*.generic.md` artifact is missing, mark the run inconsistent and fail the wrapper
- Keep the most important findings first
- Include the reporting tool name(s)
- Preserve citations when present

The merged findings list does not need perfect deduplication. Simple grouping is enough.

## Terminal Output

Print a short summary:

- requested target
- normalized `RUN_ID`
- which tools succeeded or failed
- total blocking findings (`P0 + P1`) from successful reviewers only
- summary artifact path

## Failure Behavior

Keep behavior simple and fail-closed:

- exit `0` only if all four reviews succeed and summary generation succeeds
- if one or more reviews fail, still write the summary from `dispatch_status.json` plus whatever artifacts exist
- missing artifact plus non-zero reviewer exit code = failed reviewer
- missing artifact plus zero reviewer exit code = wrapper error / inconsistent run
- artifact presence alone does not imply success
- exit non-zero if any reviewer failed, status capture failed, or summary generation failed

This gives the operator useful output without pretending the run fully succeeded.

## Verification Plan

Add one focused test script:

- `plans/tests/test_external_review_generic.sh`

Test cases:

1. target normalization for PR / commit / files / tracked-uncommitted
2. `RUN_ID` normalization produces a value valid for `plans/parallel_review.sh`
3. PR mode fetches `pull/<PR>/head`, checks out the fetched head, and passes the resolved base ref to `parallel_review.sh`
4. dispatch status capture records per-tool exit codes from `parallel_review.sh` output
5. summary file is written from status data plus canonical artifacts
6. reviewer failure still produces a summary, marks counts unavailable for failed reviewers, and exits non-zero
7. zero-exit reviewer plus missing canonical artifact is treated as inconsistent and exits non-zero

Implementation-phase validation:

```bash
bash plans/tests/test_external_review_generic.sh
```

If `plans/external_review_generic.sh` is added, update workflow verification coverage for it:

- `plans/workflow_verify.sh`
- `plans/workflow_files_allowlist.txt`
- `plans/tests/test_workflow_allowlist_coverage.sh`

Then run:

```bash
./plans/workflow_verify.sh
./plans/verify.sh quick
```

## Acceptance Criteria

Accepted when all are true:

1. One command works for PR, commit, files, and the current tracked local diff.
2. PR mode reviews the fetched PR head against the resolved base ref inside a temporary detached worktree.
3. The command launches `codex`, `opus`, `kimi`, and `gemini` in parallel using generic review mode.
4. The command writes both `dispatch_status.json` and one consolidated summary artifact.
5. Per-tool success or failure is derived from recorded dispatch exit codes, not artifact presence.
6. Any failed reviewer makes the command exit non-zero, but partial results are preserved.
