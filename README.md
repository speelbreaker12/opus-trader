# opus-trader

`opus-trader` uses a manual PRD worktree flow with a single verification source of truth.

## Canonical Entrypoints

- `./plans/verify.sh quick` — fast local iteration checks.
- `./plans/verify.sh full` — completion gate (required before `passes=true`).

## WIP=2 Worktree Workflow

At most two active story worktrees:

1. One worktree in `VERIFYING` (running `./plans/verify.sh full`, frozen while it runs).
2. One worktree in `IMPLEMENTING`/`REVIEW`.

Required story loop:

1. Implement in story worktree.
2. Run `./plans/verify.sh quick`.
3. Run Codex review (`./plans/codex_review_let_pass.sh <STORY_ID> --commit HEAD`).
4. Run `./plans/verify.sh quick` again after review fixes.
5. Freeze worktree and run `./plans/verify.sh full`.
6. Flip pass using `./plans/prd_set_pass.sh <STORY_ID> true --artifacts artifacts/verify/<run_id>`.

For full contract details, see `specs/WORKFLOW_CONTRACT.md`.
