# SKILL: /integrator (On-Demand Batch Integration)

Purpose
- Perform one deliberate integration session for a reviewed batch of worker output.
- Create a fresh batch branch from `main`, re-review approved work, cherry-pick or squash, run tests, push, and open one draft PR.
- Clean up landed worktrees and branches after the batch PR merges.

When to use
- Workers have finished and committed in their worktrees
- You have reviewed the workers' output and chosen which branches or commits to include
- You want one grouped push and one PR

Do NOT use as a background coordinator. This is an on-demand, single-pass tool.

---

## Core Rules

1. Operate only from the main repo checkout.
2. Refresh `main` first.
3. Create a fresh batch branch from `main`.
4. Re-review every approved worker input before landing it.
5. Prefer cherry-picking exact reviewed commits.
6. Push the batch branch, not `main`.
7. Open one draft PR.
8. Do not merge to `main` until tests pass and the user approves.

---

## Sequence

### Step 1: Refresh the integration lane
```bash
git checkout main
git pull --ff-only
```

### Step 2: Create a new batch branch
```bash
git checkout -b batch/YYYY-MM-DD-01 main
```

Use format `batch/YYYY-MM-DD-NN`. Increment the suffix (`-01`, `-02`, ...) if you run multiple integration sessions in one day.

### Step 3: Review each approved worker input again
For each approved worker branch:

```bash
git log --oneline main..agent/01-risk
git diff --stat main...agent/01-risk
git diff main...agent/01-risk
```

For each approved commit:

```bash
git show --stat <commit-sha>
git show <commit-sha>
```

Do not skip this review. The integrator is the final gate.

### Step 4: Land approved work onto the batch branch
Preferred default:
```bash
git cherry-pick <commit-sha>
```

Alternatives:
- `git merge --squash agent/01-risk` for messy multi-commit worker branches
- `git merge --no-ff agent/01-risk` only when preserving the branch history is genuinely valuable

If a cherry-pick or merge conflicts, resolve manually. If the conflict is non-trivial, exclude that worker's changes from this batch and handle them in a follow-up session.

### Step 5: Run tests
Run the required verification suite after the batch is assembled.
For risky or tightly coupled changes, also run focused tests after each landing.

```bash
cargo test
./plans/verify.sh quick
```

### Step 6: Push the batch branch
```bash
git push -u origin batch/YYYY-MM-DD-01
```

### Step 7: Open one draft PR
Open a draft PR from the batch branch to `main`.

---

## Review Checklist

Before pushing the batch branch, confirm:
- every landed change was explicitly approved by the user
- every landed change was re-reviewed by the integrator
- tests passed
- `git status --porcelain=v1` is empty
- the batch branch contains only intended changes

## Decision Rules

- If one worker produced one clean final commit: cherry-pick it.
- If one worker produced several clean commits and their history matters: `merge --no-ff`.
- If one worker produced several messy commits and only the end state matters: `merge --squash`.
- If a worker branch is not clearly ready: leave it out of the batch.

---

## Post-Merge Cleanup

After the batch PR merges to `main`:

```bash
git checkout main
git pull --ff-only

# Remove landed worktrees
git worktree remove ../wt/01-risk
git worktree remove ../wt/02-ui

# Delete landed agent branches (local + remote)
git branch -d agent/01-risk agent/02-ui
git push origin --delete agent/01-risk agent/02-ui 2>/dev/null || true

# Delete the batch branch (local + remote)
git branch -d batch/YYYY-MM-DD-01
git push origin --delete batch/YYYY-MM-DD-01 2>/dev/null || true

# Prune stale references
git worktree prune
git fetch --prune
```

Only remove worktrees for workers whose changes were included in the merged batch. Workers excluded from this batch keep their worktrees for the next session.

---

## Red Flags

Never:
- push `main` directly from a worker worktree
- include unreviewed worker commits in the batch
- merge failing tests
- batch unrelated risky changes together just because they are available

---

## Output

When invoking this skill, report:
- Available worker branches and their status (ready / not ready / excluded)
- Batch branch name
- Changes landed (per worker: commit SHA, files changed)
- Test results
- PR URL after creation
