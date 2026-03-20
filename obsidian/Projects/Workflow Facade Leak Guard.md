---
status: review-ready
priority: P1
branch: project/workflow-facade-leak-guard-v2
base: main
pr: https://github.com/speelbreaker12/opus-trader/pull/225
started: "2026-03-20"
aliases:
  - Facade Leak Guard
keywords:
  - workflow
  - facade
  - lint
  - verify
scope_paths:
  - .claude/commands/review-stack.md
  - plans/lib/rust_gates.sh
  - plans/lint_facade_public_modules.sh
  - plans/preflight.sh
  - plans/progress.txt
  - plans/tests/test_lint_facade_public_modules.sh
  - plans/tests/test_preflight_fixture_profiles.sh
  - plans/tests/test_pre_push_hook_env_isolation.sh
  - plans/tests/test_rust_gates_smoke_targets.sh
  - plans/tests/test_workflow_allowlist_coverage.sh
  - .githooks/pre-push
  - plans/verify_fork.sh
  - plans/workflow_files_allowlist.txt
  - obsidian/Projects/Workflow Facade Leak Guard.md
  - obsidian/Debriefs/Workflow Facade Leak Guard 2026-03-20.md
---

## Current State

Review-ready on branch `project/workflow-facade-leak-guard-v2` with PR #225 open against `main`. The slice now includes the original facade leak guard plus a follow-up fix that isolates `.githooks/pre-push` from hook-scoped `GIT_*` variables before verify, preventing fixture-repo git commands from mutating the active review branch. Targeted regression checks passed, the branch was refreshed via `git fetch origin --prune` + `git rebase origin/main` (no-op), and the successful `git push -u origin project/workflow-facade-leak-guard-v2` served as the clean-tree quick-verify proof.

## Commits
- `0c944689` — 2026-03-20 — add and harden the workflow facade leak guard, wire it into live verification, repair stale workflow verification references, and restore runtime snapshot metadata before commit.
- `a89f7c6e` — 2026-03-20 — rebind the project to a dedicated feature branch/worktree for push/PR flow and record full verification readiness.
- `e5e906df` — 2026-03-20 — isolate pre-push hook git env, add regression coverage, and recover clean push/PR flow on the v2 branch.
- `pending` — 2026-03-20 — record PR boundary metadata after opening PR #225.

## Key Files
- plans/lint_facade_public_modules.sh
- plans/tests/test_lint_facade_public_modules.sh
- plans/lib/rust_gates.sh
- plans/preflight.sh
- plans/verify_fork.sh
- plans/tests/test_preflight_fixture_profiles.sh
- plans/tests/test_rust_gates_smoke_targets.sh
- plans/tests/test_workflow_allowlist_coverage.sh
- plans/workflow_files_allowlist.txt
- .claude/commands/review-stack.md

## Debriefs
- [[Workflow Facade Leak Guard 2026-03-20]]

## Log
### 2026-03-20
- Added a repo-wide `pub mod` leak guard for `soldier_core`/`soldier_infra` source trees and wired it into live rust gates.
- Hardened the guard against same-line attributes, multiline attribute blocks, and inline module bodies such as `pub mod foo {}`.
- Added regression fixtures proving fail-closed behavior for missing libs and all known public-module leak shapes.
- Fixed stale workflow verification drift uncovered during validation: neutralized outdated review-stack wrapper wording and removed a dead workflow integration test reference from `verify_fork.sh`.
- Re-ran workflow verification and `./plans/verify.sh quick`; both passed after the workflow fixes.
- Re-ran `./plans/verify.sh full`; it passed before PR preparation.
- Restored `var/runtime/runtime_state.json` to checked-in metadata after verification so the commit scope stays deterministic.
- Rebound the project from generic branch `upgrade1` to dedicated branch `project/workflow-facade-leak-guard` after push/PR preflight showed the original worktree was still attached to `main`.
- Re-cut the work onto `project/workflow-facade-leak-guard-v2` after the first push attempt polluted the previous feature branch with fixture commits.
- Identified the root cause as pre-push hook git environment leakage into verify fixture repos, added `plans/tests/test_pre_push_hook_env_isolation.sh`, and patched `.githooks/pre-push` to clear hook-scoped `GIT_*` variables before invoking `plans/verify.sh`.
- Verified the new env-isolation regression and the updated preflight/allowlist coverage; repo-wide quick verify still hit an existing `test_lint_execution_facade.sh` timeout while the tree was dirty.
- Refreshed `project/workflow-facade-leak-guard-v2` against `origin/main` with a no-op rebase, pushed the clean branch successfully, and opened PR #225: https://github.com/speelbreaker12/opus-trader/pull/225.
