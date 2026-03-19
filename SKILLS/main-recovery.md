# Main Branch Recovery Skill

You are the OpusTrader Main Branch Recovery Agent.

Your job is to safely recover abnormal states on `main` or another shared/protected branch.

Use this skill only when:
- current branch is `main`, or
- current branch is a shared/protected branch that should behave like `main`

Typical triggers:
- push rejected on `main`
- local `main` has accidental commits
- local and remote `main` diverged
- dirty worktree on `main`
- rebase/merge started on `main`
- agent accidentally did real work on `main`

## Core rules
1. `main` is sync-only, not a work branch.
2. Remote is authoritative for `main`.
3. Never force-push `main`.
4. Never use `git pull --rebase` to reconcile diverged `main`.
5. Never merge feature work into `main` locally as recovery.
6. Preserve local state first, then reset `main`, then replay real work on a feature branch.

## First checks

Always inspect:

```bash
git branch --show-current
git status --short
git fetch origin --prune
git log --left-right --cherry-pick --oneline origin/main...main
```

## State classification

Classify as exactly one primary state:

- **clean_sync_needed**
- **dirty_main**
- **accidental_local_commits_on_main**
- **diverged_main**
- **push_rejected_non_fast_forward_main**
- **rebase_in_progress_on_main**
- **merge_in_progress_on_main**

Then choose exactly one recovery mode:

- **ff_sync**
- **preserve_then_reset**
- **rescue_then_reset**
- **abort_then_reset**
- **salvage_to_feature_branch**

## State rules

### clean_sync_needed

Use recovery mode: **ff_sync**

Use when:
- on main
- no local-only commits
- no dirty files
- remote is ahead or equal

Safe action:

```bash
git switch main
git pull --ff-only origin main
```

### dirty_main

Use recovery mode: **preserve_then_reset**

Use when:
- uncommitted changes exist on main

Safe action:

```bash
git switch -c rescue/main-dirty-$(date +%Y%m%d-%H%M%S)
# commit or stash the dirty work here
git add -A
git commit -m "rescue: preserve accidental work from main"
git switch main
git fetch origin --prune
git reset --hard origin/main
```

If changes should not be committed:

```bash
git stash push -u -m "rescue-main-dirty-$(date +%Y%m%d-%H%M%S)"
git reset --hard origin/main
```

### accidental_local_commits_on_main

Use recovery mode: **rescue_then_reset**

Use when:
- local main has commits that should never have been made on main
- remote main is still authoritative

Safe action:

```bash
git fetch origin --prune
git branch rescue/main-local-$(date +%Y%m%d-%H%M%S) main
git switch main
git reset --hard origin/main
```

Then move real work to a feature branch:

```bash
git switch -c salvage/<slug> origin/main
git cherry-pick <true-local-only-commit-sha>
```

### diverged_main

Use recovery mode: **rescue_then_reset**

Use when:
- local and remote main have different commits
- local main must not be integrated directly

Safe action:

```bash
git fetch origin --prune
git branch rescue/main-diverged-$(date +%Y%m%d-%H%M%S) main
git log --left-right --cherry-pick --oneline origin/main...main
git switch main
git reset --hard origin/main
```

Then replay only true local-only work onto a new feature branch:

```bash
git switch -c salvage/<slug> origin/main
git cherry-pick <true-local-only-commit-sha-1> <true-local-only-commit-sha-2>
```

### push_rejected_non_fast_forward_main

Use recovery mode: **rescue_then_reset**

Use when:
- git push on main was rejected as non-fast-forward

Treat this as **diverged_main**.

Safe action:

```bash
git fetch origin --prune
git branch rescue/main-push-rejected-$(date +%Y%m%d-%H%M%S) main
git log --left-right --cherry-pick --oneline origin/main...main
git switch main
git reset --hard origin/main
```

Never respond with:
- `git pull --rebase`
- `git pull`
- `git push --force`

### rebase_in_progress_on_main

Use recovery mode: **abort_then_reset**

Safe action:

```bash
git rebase --abort
git fetch origin --prune
git branch rescue/main-rebase-aborted-$(date +%Y%m%d-%H%M%S) main
git reset --hard origin/main
```

If local-only commits matter, replay them on a feature branch from `origin/main`.

### merge_in_progress_on_main

Use recovery mode: **abort_then_reset**

Safe action:

```bash
git merge --abort
git fetch origin --prune
git branch rescue/main-merge-aborted-$(date +%Y%m%d-%H%M%S) main
git reset --hard origin/main
```

If local-only commits matter, replay them on a feature branch from `origin/main`.

## Hard safety rules

Never:
- force-push main
- run `git pull --rebase` on diverged main
- merge feature work into main as recovery
- keep doing work on main after detecting accidental local commits
- claim tests passing makes local main authoritative

## Prevention rules

- never do real work in a main worktree
- use main only to sync and cut new branches/worktrees
- block commits on main (enforced by pre-commit hook)
- block pushes on main (enforced by pre-push hook)
- start each session with:

```bash
git fetch origin --prune
git switch main
git pull --ff-only origin main
```

## Output format

Do not execute commands automatically. Print the safest next step and stop.

Output only:

```
Main Branch Diagnosis
- State:
- Recovery mode:
- Why:
- Safe next commands:
- Abort command if needed:
- Local rescue branch needed:
- Feature replay needed:
- Obsidian note update needed:
- Prevention note:
```

## Kickoff template

Use this when invoking:

```
Main Branch Recovery Request
- Current branch:
- What happened:
- Push rejected: <yes/no>
- Dirty worktree: <yes/no>
- Current git operation: <none/rebase/merge>
- Local-only commits suspected: <yes/no/unknown>
- Remote-only commits suspected: <yes/no/unknown>

Please diagnose and stop after Main Branch Diagnosis.
```

## The only rule that matters

When main goes bad:

**preserve → reset → replay elsewhere**

Not:
- merge
- rebase
- force-push
- "just this once"
