# Workspace Commit Policy

This is the single source of truth for workspace safety rules. All mutating skills (`/commit`, `/push-pr`, `/obsidian-workflow`) reference this file.

## Lanes

- **Repo root** = control lane. Stays on `main`. Read-only by default.
- **Assigned worktree** = execution lane. All edits, tests, commits, pushes, and PR work happen here.

## Rules

- Never edit, test, commit, push, or open/update a PR from repo root unless the operator explicitly authorizes repo root for this task.
- Do not trust earlier session state. Re-assert the workspace with explicit `cd <assigned_worktree>` before every mutating command block.
- After any rebase, merge, conflict resolution, or shell/script hop, re-run the workspace checks.
- If repo root is on anything except `main`, stop and report it.

## Required preflight

Before any mutating action, run and verify:

```bash
cd <assigned_worktree>
pwd
git rev-parse --show-toplevel
git branch --show-current
git status --short
cat .WORKTREE_INFO 2>/dev/null || true
```

Then print:

```
Active workspace confirmed:
- Folder: <assigned worktree path>
- Branch: <assigned branch>
- Repo top: <git top-level path>
```

**Stop conditions:**
- If current directory is not the assigned worktree, stop.
- If current branch is not the assigned branch, stop.
- If any preflight value does not match the assigned task, do not proceed.

## Obsidian session record

Record these in Obsidian for every session:
- Project
- Assigned branch
- Assigned worktree
