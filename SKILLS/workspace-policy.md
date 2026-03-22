# Workspace Policy

Single source of truth for workspace safety and worktree lifecycle. All mutating skills (`/commit`, `/push-pr`, `/obsidian-workflow`, `/git`) reference this file.

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

## Session start

Sync main and survey worktrees before starting any work:

```bash
git fetch origin --prune
git switch main
git pull --ff-only origin main
git worktree list
```

Classify every worktree as one of:

| Class | Meaning | Action |
|-------|---------|--------|
| ACTIVE | Currently being worked on | Keep |
| STALE | Valid but behind main | Refresh (see below) |
| DIRTY | Has uncommitted changes | Resolve immediately (see below) |
| MERGED | PR landed | Delete worktree + branch |
| ABANDONED | No PR, no task, no next step | Delete |
| RESCUE | Temporary holding branch | Keep only if referenced by a handoff |

Do not start coding until the current worktree is clearly classified.

## Worktree cap

No more than **5 active worktrees** at any time. If at the cap, clean up before creating a new one.

## Dirty worktree resolution

When a worktree has uncommitted changes, do exactly one of:

**A. Keep** — changes are real and belong on that branch:
```bash
git add -A
git commit -m "wip: <short description>"
```

**B. Rescue** — partial/messy work worth preserving:
```bash
git switch -c rescue/<slug>
git add -A
git commit -m "rescue: preserve partial work"
```

**C. Discard** — junk:
```bash
git restore --staged .
git restore .
git clean -fd
```

Default rule: do not leave dirt behind.
Avoid `git stash` as normal policy — stash creates hidden garbage. Prefer commit, rescue branch, or discard.

## Keeping worktrees synchronized

**No open PR yet** — refresh with rebase:
```bash
git fetch origin --prune
git rebase origin/main
```

**PR already open** — refresh with merge:
```bash
git fetch origin --prune
git merge origin/main
```

**Never on main:** no rebase, no merge-based recovery, no force-push. If main diverges, use `/main-recovery`.

## After a PR merges

```bash
# 1. Sync main
git switch main
git fetch origin --prune
git pull --ff-only origin main

# 2. Remove merged worktree
git worktree remove <path>

# 3. Delete local branch
git branch -d <branch>
# If squash-merged and -d complains but merge confirmed:
git branch -D <branch>
```

Merged worktrees should not hang around "just in case."

## Abandoned worktree rule

Delete a worktree if any of these are true:
- No PR
- No active task
- No next step
- Untouched for 7+ days
- Replaced by a newer branch
- Exists because nobody cleaned it

## Session end

At the end of every session, leave:
- main clean and synced
- current worktree clean
- Obsidian updated
- merged worktrees removed
- no unexplained dirty trees
- no more than 5 active worktrees

## Obsidian session record

Record these in Obsidian for every session:
- Project
- Assigned branch
- Assigned worktree
