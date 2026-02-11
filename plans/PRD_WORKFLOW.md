# PRD Workflow (Manual Verify Model)

This repository uses manual PRD story execution with verify and review/PR gates.
`specs/WORKFLOW_CONTRACT.md` is the source of truth; this file is a concise operator guide and must stay contract-aligned.

## Core rules

1. Use one branch/worktree per Story ID.
2. Use PRs as the merge mechanism; do not merge story branches into local `main`.
3. Keep the same story worktree until PR merge (or explicit abandonment), then clean it up.
4. Keep WIP=2 maximum:
- one story in `VERIFYING` (full verify running, worktree frozen)
- one story in `IMPLEMENTING/REVIEW`
5. Run `./plans/verify.sh quick` during implementation/review.
6. Run `./plans/verify.sh full` before marking complete/merge-grade.
7. Flip `passes=true` only via:

```bash
./plans/prd_set_pass.sh <STORY_ID> true --artifacts-dir artifacts/verify/<run_id>
```

8. Dirty-tree policy: do not use dirty verify exceptions by default; prefer CI verify on PR (clean checkout) or clean the worktree first.

## PR loop (trimmed)

1. Rebase/sync story branch onto latest integration/mainline branch.
2. Run required gates in that story worktree:
- `./plans/verify.sh quick` during iteration
- `./plans/verify.sh full` before merge-grade/pass flip
3. Push branch and open/update PR.
4. Run `./plans/pre_pr_review_gate.sh <STORY_ID>` before PR merge gating.
5. Run `./plans/pr_gate.sh --wait --story <STORY_ID>` until it passes.
6. Optional automation: `./plans/pr_aftercare_codex.sh` may be used for iterative fix/push loops, but it is not required.
7. Merge via PR after gates are green.

## Recommended story loop

1. Implement in story worktree (single Story ID).
2. Capture `REVIEW_SHA="$(git rev-parse HEAD)"`, then write self-review for that SHA.
3. `./plans/verify.sh quick`
4. Codex review for `REVIEW_SHA` (`./plans/codex_review_let_pass.sh <STORY_ID> --commit "$REVIEW_SHA"`), then fix blocking issues.
5. Kimi review for `REVIEW_SHA` (`./plans/kimi_review_logged.sh <STORY_ID> --commit "$REVIEW_SHA"`), then fix blocking issues.
6. `./plans/verify.sh quick`
7. Second Codex review for `REVIEW_SHA`, then fix blocking issues.
8. `./plans/verify.sh quick`
9. Findings review via code-review-expert skill; save artifact with `./plans/code_review_expert_logged.sh <STORY_ID> --head "$REVIEW_SHA" --status COMPLETE`.
10. Turn top findings into failing tests first (red), then fix to green.
11. `./plans/verify.sh quick`
12. Sync with integration branch.
13. If sync changed code, `./plans/verify.sh quick` again.
14. Freeze story worktree and run `./plans/verify.sh full`.
15. `./plans/prd_set_pass.sh <STORY_ID> true --artifacts-dir artifacts/verify/<run_id>`
16. Merge.

## Required evidence notes

- `passes=true` requires full-verify artifacts and review evidence for the same `HEAD`.
- `./plans/prd_set_pass.sh` enforces evidence checks via `./plans/story_review_gate.sh`.
- If `HEAD` changes after review starts, regenerate the complete review set for the chosen SHA.

## References

- `specs/WORKFLOW_CONTRACT.md`
- `plans/prd.json`
- `plans/progress.txt`
- `plans/prd_set_pass.sh`
- `plans/codex_review_let_pass.sh`
