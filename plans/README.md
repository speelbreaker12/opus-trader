# Plans Harness

## Entry points

- `./plans/verify.sh` — canonical verification entrypoint (`quick|full`).
- `./plans/verify_fork.sh` — canonical verify implementation (called by `verify.sh`).
- `./plans/preflight.sh` — lightweight preflight checks used by verify.
- `./plans/workflow_verify.sh` — focused workflow/harness maintenance helper.
- `./plans/prd_set_pass.sh` — guarded `passes=true|false` updates with artifact validation.
- `./plans/codex_review_let_pass.sh` — wrapper for logged Codex review output.

## Core workflow files

- `plans/prd.json` — story backlog.
- `plans/progress.txt` — append-only progress log.
- `plans/ideas.md` — deferred ideas.
- `plans/pause.md` — optional pause handoff.
- `plans/review_resolution_template.md` — canonical template for `artifacts/story/<ID>/review_resolution.md`.

## Verification contract

- Use `./plans/verify.sh quick` during iteration.
- Use `./plans/verify.sh full` before flipping `passes=true`.
- Verify artifacts must be in `artifacts/verify/<run_id>/` and consumed by `plans/prd_set_pass.sh`.
