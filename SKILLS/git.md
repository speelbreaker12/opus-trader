# SKILL: /git (Branch, Merge, and Worktree Discipline)

Purpose
- Prevent work loss from blanket merge resolution, unpushed commits, and worktree branch conflicts.
- Safely resolve merge conflicts while preserving contract alignment and fail-closed behavior.
- Enforce "never commit on main" discipline.
- Keep worktrees isolated, tracked, and disposable.

When to use
- Starting any new task (before first commit)
- Creating a worktree
- Before merging or rebasing
- PR has merge conflicts
- Rebasing a branch onto main
- Cherry-picking across branches
- After `git merge` or `git rebase` reports conflicts
- After a PR merges (cleanup)
- When main repo and worktrees get out of sync

Root cause this addresses
- S5-004: blanket `--theirs` on 8 merge conflicts lost enriched prompt infra + resolution prompt (2/8 files had unique branch work silently destroyed)
- S5-004: worktree held `main`, blocking the main repo from checking out `main`
- S5-004: unpushed proof-graph V2 commit in main repo caused rebase conflict weeks later

---

## Part 1: Branch + Worktree Rules

### Rule 1: Never Commit Directly on `main`

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

### Rule 2: Worktrees Use Feature Branches, Not `main`

```bash
# WRONG — locks main out of the main repo entirely:
git worktree add ../wt_recon main

# RIGHT — worktree gets its own branch:
git worktree add ../wt_recon -b recon/S5-004 main
```

**Why**: Only one checkout of a branch can exist at a time. If a worktree holds `main`, the main repo directory cannot switch to `main` (git refuses with `fatal: 'main' is already checked out at ...`).

#### Worktree lifecycle
```bash
# 1. Create (always with a branch)
git worktree add ../wt_<task> -b <branch-name> main

# 2. Work on branch, push, create PR

# 3. After PR merges — clean up
git worktree remove ../wt_<task>
git branch -d <branch-name>           # local
git push origin --delete <branch-name> # remote (if not auto-deleted)
```

#### Worktree inventory check
```bash
# See all worktrees and which branches they hold
git worktree list

# Prune stale worktree references
git worktree prune
```

### Rule 3: Push Early, Push Often

Every commit that exists only locally is a future conflict.

```bash
# After any meaningful work:
git push origin HEAD

# Check for unpushed commits across ALL local branches:
git log --branches --not --remotes --oneline
```

If `git log --branches --not --remotes` shows commits, either push them or delete the branch.

### Rule 4: One Worktree = One Task = One Branch

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

## Part 2: Merge Conflict Resolution

### Step 1: Identify conflicts
```bash
git status --porcelain | grep "^UU\|^AA\|^DD"
git diff --name-only --diff-filter=U
```

### Step 2: Classify each conflict by risk level

| File Pattern | Risk | Extra Care |
|--------------|------|------------|
| `crates/soldier_core/` | HIGH | Verify fail-closed preserved |
| `crates/soldier_infra/` | HIGH | Check error handling |
| `specs/CONTRACT.md` | HIGH | Check section numbering, AT refs |
| `specs/state_machines/` | HIGH | State transition integrity |
| `plans/*.sh` | MEDIUM | Run verify.sh after |
| `python/schemas/` | MEDIUM | Validate fixtures |
| `prd.json` | MEDIUM | Check task IDs, refs |
| Docs, comments, README | LOW | Standard resolution |

### Step 3: Before blanket `--theirs` or `--ours` — diff each file

**Never blindly accept one side for all conflicts.** In S5-004, blanket `--theirs` on 8 files silently destroyed the enriched prompt infrastructure and detailed resolution prompt (2/8 files had unique branch work).

```bash
merge_base=$(git merge-base HEAD MERGE_HEAD)
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

### Step 4: For each conflict, resolve with safety bias

**a) Understand both sides:**
- Read the PR description / commit message for "ours"
- Read the incoming commit message for "theirs"
- Identify CONTRACT.md sections involved
- Check git log for context:
  ```bash
  git log --oneline -5 HEAD
  git log --oneline -5 MERGE_HEAD
  ```

**b) Resolve with safety bias:**
- If uncertain which behavior is correct -> keep MORE RESTRICTIVE
- If both add code -> check for duplicate functionality
- If both modify same function -> re-read contract requirements
- Default to `ReduceOnly` over `Active` when merging TradingMode logic

**c) Verify patterns preserved after resolution:**
```rust
// Check these patterns are intact:
// - No new unwrap() introduced
// - Fail-closed defaults maintained
// - Error handling not swallowed
// - Latch behavior preserved
```

### Step 5: Post-resolution verification

```bash
# Must pass before marking resolved
cargo check                    # Compiles
cargo test                     # Tests pass
./plans/verify.sh --quick      # Gates pass (if available)
```

### Step 6: For CONTRACT.md conflicts specifically

```bash
# After resolution, verify integrity
python3 scripts/check_contract_crossrefs.py --contract specs/CONTRACT.md --strict
python3 scripts/check_arch_flows.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml
```

Check:
- Section numbers still sequential
- AT-### references valid
- Cross-references resolve
- No orphaned sections

### Step 7: For prd.json conflicts

```bash
# Validate JSON structure
python3 -m json.tool plans/prd.json > /dev/null

# Check for duplicate task IDs
jq '.tasks[].id' plans/prd.json | sort | uniq -d
```

---

## Part 3: Conflict Resolution Patterns

### Pattern: Both sides add to a list/enum
```rust
// OURS adds:
RejectReasonCode::PolicyStale,
// THEIRS adds:
RejectReasonCode::WatchdogTimeout,

// RESOLUTION: Include both, check for semantic overlap
RejectReasonCode::PolicyStale,
RejectReasonCode::WatchdogTimeout,
```

### Pattern: Both sides modify same match arm
```rust
// Read both implementations
// Keep the MORE RESTRICTIVE behavior
// If unclear, check CONTRACT.md for the requirement
```

### Pattern: Structural changes conflict
```rust
// One side refactors, other adds feature
// Usually: apply refactor first, then re-add feature on new structure
// May need to rebase instead of merge
```

---

## Part 4: Anti-Patterns

| Anti-pattern | Why it's dangerous |
|--------------|-------------------|
| Blanket `--theirs` or `--ours` | May lose critical safety logic or branch-specific tooling (S5-004: lost enriched prompt infra) |
| Resolve safety code without reading both sides | Could introduce fail-open bugs |
| Skip verification "it's just a merge" | Merges can break invariants |
| Lose AT references during resolution | Breaks contract traceability |
| Add `unwrap()` to "simplify" resolution | Introduces panic paths |
| Swallow errors to make code compile | Hides contract violations |
| Commit directly on `main` | No PR review, no rollback, lost in S5-004 |
| Worktree on `main` branch | Locks main out of main repo |
| Leave unpushed commits for weeks | Causes ghost conflicts on next pull |

---

## Part 5: Checklists

### Pre-Merge Checklist

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

### Post-PR-Merge Cleanup Checklist

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

## Part 6: Recovery

### Main Repo Stuck on Wrong Branch

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

### Quick Reference Commands

```bash
# See what's conflicting
git diff --check

# See conflict markers
grep -rn "<<<<<<" .

# Abort if needed
git merge --abort
git rebase --abort

# After resolving all conflicts
git add <resolved-files>
git rebase --continue   # or git merge --continue
```

---

## Output

When invoking this skill, report:
- Current worktree layout (`git worktree list`)
- Any unpushed commits (`git log --branches --not --remotes --oneline`)
- Branch checkout conflicts (which worktree holds which branch)
- Recommended cleanup actions
- (If resolving conflicts) List of files resolved with risk classification, verification results, any CONTRACT.md sections needing human review, warnings about fail-closed patterns
