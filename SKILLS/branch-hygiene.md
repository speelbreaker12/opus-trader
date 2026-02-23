# SKILL: /branch-hygiene (Branch + Worktree Discipline)

Purpose
- Prevent work loss from blanket merge resolution, unpushed commits, and worktree branch conflicts.
- Enforce "never commit on main" discipline.
- Keep worktrees isolated, tracked, and disposable.

When to use
- Starting any new task (before first commit)
- Creating a worktree
- Before merging or rebasing
- After a PR merges (cleanup)
- When main repo and worktrees get out of sync

Root cause this addresses
- S5-004: blanket `--theirs` on 8 merge conflicts lost enriched prompt infra + resolution prompt (2/8 files had unique branch work silently destroyed)
- S5-004: worktree held `main`, blocking the main repo from checking out `main`
- S5-004: unpushed proof-graph V2 commit in main repo caused rebase conflict weeks later

---

## Rule 1: Never Commit Directly on `main`

```bash
# WRONG — commits go straight to production, no PR review, no rollback
git checkout main
# ... do work ...
git commit
git push origin main

# RIGHT — branch it, even for "just docs"
git checkout -b fix/descriptive-name main
# ... do work ...
git push -u origin fix/descriptive-name
gh pr create --base main
```

**Cost of branching**: 10 seconds.
**Cost of not branching**: irrecoverable mistakes pushed to main.

**Exception**: Trivial 1-line typo fixes when you're certain. Even then, prefer a branch.

---

## Rule 2: Worktrees Use Feature Branches, Not `main`

```bash
# WRONG — locks main out of the main repo entirely:
git worktree add ../wt_recon main

# RIGHT — worktree gets its own branch:
git worktree add ../wt_recon -b recon/S5-004 main
```

**Why**: Only one checkout of a branch can exist at a time. If a worktree holds `main`, the main repo directory cannot switch to `main` (git refuses with `fatal: 'main' is already checked out at ...`).

### Worktree lifecycle
```bash
# 1. Create (always with a branch)
git worktree add ../wt_<task> -b <branch-name> main

# 2. Work on branch, push, create PR

# 3. After PR merges — clean up
git worktree remove ../wt_<task>
git branch -d <branch-name>           # local
git push origin --delete <branch-name> # remote (if not auto-deleted)
```

### Worktree inventory check
```bash
# See all worktrees and which branches they hold
git worktree list

# Prune stale worktree references
git worktree prune
```

---

## Rule 3: Before `--theirs`, Diff Each Conflicted File

**Never blindly accept `--theirs` (or `--ours`) on all conflicts.**

```bash
# During a merge/rebase with conflicts, run this BEFORE resolving:
merge_base=$(git merge-base HEAD MERGE_HEAD)
echo "=== Per-file conflict analysis ==="
for f in $(git diff --name-only --diff-filter=U); do
  ours=$(git diff "$merge_base" HEAD -- "$f" | wc -l | tr -d ' ')
  theirs=$(git diff "$merge_base" MERGE_HEAD -- "$f" | wc -l | tr -d ' ')
  if [ "$ours" -eq 0 ]; then
    echo "SAFE --theirs: $f  (no branch changes)"
  elif [ "$ours" -gt 20 ] && [ "$theirs" -lt "$ours" ]; then
    echo "MANUAL MERGE: $f  (ours=$ours theirs=$theirs — branch has unique work!)"
  elif [ "$ours" -le 20 ]; then
    echo "CHECK FIRST:  $f  (ours=$ours theirs=$theirs — small branch delta)"
  else
    echo "CHECK FIRST:  $f  (ours=$ours theirs=$theirs)"
  fi
done
```

**Decision matrix:**

| Ours diff lines | Theirs diff lines | Action |
|-----------------|-------------------|--------|
| 0 | Any | `--theirs` is safe |
| Small (< 20) | Similar to ours | Likely convergent — `--theirs` probably safe, but verify |
| Large (> 20) | Much smaller | **Branch has unique work** — manual merge required |
| Large | Large | Both changed substantially — manual merge required |

---

## Rule 4: Push Early, Push Often

Every commit that exists only locally is a future conflict.

```bash
# After any meaningful work:
git push origin HEAD

# Check for unpushed commits across ALL local branches:
git log --branches --not --remotes --oneline
```

If `git log --branches --not --remotes` shows commits, either push them or delete the branch.

---

## Rule 5: One Worktree = One Task = One Branch

```
~/Desktop/opus-trader/      → DO NOT commit here. Pull-only reference.
~/Desktop/wt_recon/         → recon/S5-004 (reconciliation)
~/Desktop/wt_proof_graph/   → feature/proof-graph-v2 (proof graph)
~/Desktop/wt_audit/         → audit/slices-0-6 (audit work)
```

**Anti-patterns:**
- Two worktrees sharing a branch
- Main repo directory used for active development
- Worktree outliving its PR by more than a day
- Worktree branch merged but worktree not removed

---

## Pre-Merge Checklist

Run before any `git merge` or `git rebase`:

```bash
# 1. Are there unpushed commits on this branch?
git log origin/$(git branch --show-current)..HEAD --oneline
# If yes: push first

# 2. Is the working tree clean?
git status --porcelain
# If no: stash or commit first

# 3. Is main up to date?
git fetch origin
git log HEAD..origin/main --oneline | wc -l
# Shows how many commits behind
```

---

## Post-PR-Merge Cleanup Checklist

```bash
# 1. Update main
git fetch origin
# (In the main repo, if main is free:)
git checkout main && git pull origin main

# 2. Remove the worktree
git worktree remove ../wt_<task>

# 3. Delete local branch
git branch -d <branch-name>

# 4. Verify no stale worktrees
git worktree list
git worktree prune

# 5. Check for any orphaned unpushed commits
git log --branches --not --remotes --oneline
```

---

## Recovery: Main Repo Stuck on Wrong Branch

If a worktree holds `main` and the main repo can't switch:

```bash
# Option A: Update main ref without checkout
git fetch origin main
# main ref now matches origin/main even though another worktree has it

# Option B: Remove the worktree first
git worktree remove ../wt_<task>
git checkout main
git pull origin main

# Option C: Work from the worktree instead
# (If the worktree IS on main, just use it as your main workspace)
```

---

## Output

When invoking this skill, report:
- Current worktree layout (`git worktree list`)
- Any unpushed commits (`git log --branches --not --remotes --oneline`)
- Branch checkout conflicts (which worktree holds which branch)
- Recommended cleanup actions
