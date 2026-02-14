# Workflow Anti-Skip Hardening Plan (P1/P2 Governance Layer)

## Summary
Harden the PRD story loop so agents cannot skip required review/verify steps.
Implement this as a **single-source-of-truth state machine derived from append-only workflow events**, enforced by existing gates (`story_review_gate`, `pre_pr_review_gate`, `verify full`, CI merge checks).

This plan targets the 5 currently skippable workflow steps and preserves existing branch/story conventions in this repo.

## Goals
1. Make step order mechanically enforceable.
2. Block pass flips, PR readiness, and merge when sequence is incomplete.
3. Prevent “verify one tree, merge another” drift.
4. Avoid new ambiguity by keeping one canonical workflow truth.

## Non-Goals
1. No slice acceptance criteria changes.
2. No changes to trading runtime behavior.
3. No migration away from `story/<STORY_ID>[-slug]` naming unless explicitly approved later.

## Canonical State Model
Use one append-only ledger per story:
- `artifacts/story/<STORY_ID>/workflow_events.jsonl`

Each event includes:
- `schema_version`
- `story_id`
- `head_sha`
- `branch`
- `event_type`
- `timestamp_utc`
- `run_id` (if verify-related)
- `details` (structured map; includes `changed=true|false` for sync)

Derived state is computed on demand by a new helper:
- `plans/workflow_state_eval.py`
This outputs pass/fail + missing/out-of-order transitions.

No separate `.workflow_state/*.json` tracked file is introduced.

## Enforced State Sequence
Required ordered chain (same `story_id`, same `head_sha` unless explicitly marked sync transition):
1. `implemented_marker` (optional explicit start marker; recommended)
2. `self_review_pass`
3. `quick_pre_reviews` (Step 3)
4. `codex_review_1_pass`
5. `kimi_review_pass`
6. `quick_post_review_fixes` (Step 6)
7. `codex_review_2_pass`
8. `quick_post_second_codex` (Step 6.2)
9. `code_review_expert_complete`
10. `quick_post_findings_fixes` (Step 6.6)
11. `sync_with_integration` (Step 7; includes `changed` flag)
12. `quick_post_sync` (required only when `changed=true`)
13. `full_verify_pass`
14. `pre_pr_gate_pass`

## Script Contract Changes (Pre/Postconditions)
1. `plans/self_review_logged.sh`
- Pre: story exists, branch matches story.
- Post on success: append `self_review_pass`.
- Fail-closed: do not overwrite PASS semantics.

2. `plans/codex_review_logged.sh`
- New required flag: `--stage first|second`.
- Pre first: `quick_pre_reviews` exists.
- Pre second: `quick_post_review_fixes` exists.
- Post: append `codex_review_1_pass` or `codex_review_2_pass`.

3. `plans/kimi_review_logged.sh`
- Pre: `quick_pre_reviews` exists.
- Post: append `kimi_review_pass`.

4. `plans/code_review_expert_logged.sh`
- Pre: `quick_post_second_codex` exists.
- Post (status COMPLETE): append `code_review_expert_complete`.

5. `plans/story_sync_logged.sh` (new)
- Wraps sync action recording (`merge`/`rebase` metadata + `changed`).
- Post: append `sync_with_integration`.

6. `plans/verify_fork.sh`
- Quick mode: accepts `STORY_ID` + `WORKFLOW_STEP` and appends one of:
  - `quick_pre_reviews`
  - `quick_post_review_fixes`
  - `quick_post_second_codex`
  - `quick_post_findings_fixes`
  - `quick_post_sync`
- Full mode:
  - requires clean tree precondition (`git diff --exit-code`, `git diff --cached --exit-code`)
  - validates workflow state completion before running final pass-sensitive gates
  - appends `full_verify_pass` only on full success.

7. `plans/pre_pr_review_gate.sh`
- Enforce existing review evidence plus derived-state invariants:
  - second Codex present
  - required quick reruns present
  - full verify pass present
  - state chain complete for story/head
- Post: append `pre_pr_gate_pass`.

8. `plans/prd_set_pass.sh`
- Keep as sole `passes=true` mutator.
- Continue calling `story_review_gate`; extend gate to require derived-state completion.

## New/Updated Gate Enforcement
1. `plans/story_review_gate.sh`
- Add workflow-state evaluation call.
- Hard-fail on missing/out-of-order events.
- Keep existing artifact SHA-consistency checks.

2. `plans/verify_fork.sh` full
- Add `workflow_state_contract` gate before completion-sensitive sections.
- Fail closed if state evaluator reports incomplete chain.

3. CI merge blocker
- Add required CI check `workflow_state_complete`:
  - validates derived state for story branch/head.
  - independent of crossref/contract coverage checks.

## Post-Verify Drift Protection
After full verify success, create immutable fingerprint artifact:
- `artifacts/story/<STORY_ID>/workflow_fingerprint.json`
- Includes:
  - `head_sha`
  - `verify_run_id`
  - digest map for governance-critical paths:
    - `plans/**` (selected gate scripts)
    - `docs/PHASE0_CHECKLIST_BLOCK.md`
    - `docs/PHASE1_CHECKLIST_BLOCK.md`
    - `docs/ROADMAP.md`
    - workflow allowlist files
CI recomputes and fails on mismatch.

## Branch/Story Binding
Preserve current contract:
- `story/<STORY_ID>` or `story/<STORY_ID>-<slug>`
- Enforce story ID = branch ID = event story ID.

## Deadlock / Retry Safety
Add optional bounded retries in review wrapper scripts:
- `MAX_REVIEW_RETRIES` default `2`.
- On exceed: emit deterministic failure and stop loop.
- No auto-accept/auto-resolution of review comments.

## Files to Add
1. `plans/workflow_event_log.sh`
2. `plans/workflow_state_eval.py`
3. `plans/story_sync_logged.sh`
4. `plans/tests/test_workflow_state_eval.sh`
5. `plans/tests/test_workflow_event_log.sh`

## Files to Modify
1. `plans/self_review_logged.sh`
2. `plans/codex_review_logged.sh`
3. `plans/kimi_review_logged.sh`
4. `plans/code_review_expert_logged.sh`
5. `plans/story_review_gate.sh`
6. `plans/pre_pr_review_gate.sh`
7. `plans/prd_set_pass.sh` (minimal wiring if needed)
8. `plans/verify_fork.sh`
9. `specs/WORKFLOW_CONTRACT.md`
10. `plans/tests/test_story_review_gate.sh`
11. `plans/tests/test_pre_pr_review_gate.sh`
12. `plans/test_verify_fork_smoke.sh`
13. CI workflow file(s) to require `workflow_state_complete`

## Test Cases
1. Missing Step 3 quick run -> fail at codex/kimi precondition and story gate.
2. Missing Step 6 quick rerun -> fail second Codex precondition/gate.
3. Missing Step 6.2 rerun -> fail code-review-expert precondition/gate.
4. Missing Step 6.6 rerun -> fail pre-PR and pass flip.
5. Skip sync step -> fail full verify precondition for pass-sensitive path.
6. Sync changed=true without quick_post_sync -> fail.
7. Full verify with dirty tree -> fail.
8. Post-verify governance file change -> fingerprint mismatch in CI -> fail.
9. Out-of-order event injection -> state evaluator fail.
10. All steps complete in order -> gates pass and `prd_set_pass` allowed.

## Rollout
1. Phase A: introduce event logging + evaluator + tests (warn mode optional for one cycle).
2. Phase B: hard-fail in `story_review_gate` and `pre_pr_review_gate`.
3. Phase C: enforce in `verify full` and CI required check.
4. Phase D: remove temporary compatibility toggles.

## Assumptions and Defaults
1. SSOT for workflow decisions remains `specs/WORKFLOW_CONTRACT.md`.
2. Decision inputs for phase gating remain:
   - Phase 0: `docs/PHASE0_CHECKLIST_BLOCK.md`, `docs/ROADMAP.md`
   - Phase 1: `docs/PHASE1_CHECKLIST_BLOCK.md`, `docs/ROADMAP.md`
3. Historical roadmap docs are non-authoritative context only.
4. Fail-closed behavior is default for all new checks.
