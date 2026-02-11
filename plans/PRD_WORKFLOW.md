# PRD Workflow (Manual Verify Model)

This repository uses manual PRD story execution with verify as the only gate.
`specs/WORKFLOW_CONTRACT.md` is the source of truth; this file is a concise operator guide and must stay contract-aligned.

## Core rules

1. Use one branch/worktree per Story ID.
2. Run `./plans/verify.sh quick` during implementation/review.
3. Run `./plans/verify.sh full` before marking complete.
4. Flip `passes=true` only via:

```bash
./plans/prd_set_pass.sh <STORY_ID> true --artifacts-dir artifacts/verify/<run_id>
```

5. Keep WIP=2 maximum:
- one story in `VERIFYING` (full verify running, worktree frozen)
- one story in `IMPLEMENTING/REVIEW`

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
