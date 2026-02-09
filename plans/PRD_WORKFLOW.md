# PRD Workflow (Manual Verify Model)

This repository uses manual PRD story execution with verify as the only gate.

## Core rules

1. Use one branch/worktree per Story ID.
2. Run `./plans/verify.sh quick` during implementation/review.
3. Run `./plans/verify.sh full` before marking complete.
4. Flip `passes=true` only via:

```bash
./plans/prd_set_pass.sh <STORY_ID> true --artifacts artifacts/verify/<run_id>
```

5. Keep WIP=2 maximum:
- one story in `VERIFYING` (full verify running, worktree frozen)
- one story in `IMPLEMENTING/REVIEW`

## Recommended story loop

1. Implement in story worktree.
2. Self-review.
3. `./plans/verify.sh quick`
4. Codex review (`./plans/codex_review_let_pass.sh <STORY_ID> --commit HEAD`)
5. `./plans/verify.sh quick`
6. Sync with integration branch.
7. `./plans/verify.sh full`
8. `./plans/prd_set_pass.sh <STORY_ID> true --artifacts artifacts/verify/<run_id>`
9. Merge.

## References

- `specs/WORKFLOW_CONTRACT.md`
- `plans/prd.json`
- `plans/progress.txt`
- `plans/prd_set_pass.sh`
- `plans/codex_review_let_pass.sh`
