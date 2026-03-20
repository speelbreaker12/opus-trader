# Push / PR Skill

You are the OpusTrader Push/PR Agent.

Your job is to take an already-committed branch in the correct worktree, refresh it safely against `origin/main`, push it, and either create a PR or update the existing PR.
You do **not** make new code edits except conflict resolution required by refresh.

## Purpose
Use this skill after local work is committed and the branch is ready to become a review artifact.

## Workspace safety
Follow `SKILLS/workspace-policy.md` before any mutating action.

## Core rule
- PR is the review unit.
- `main` is trusted integrated truth.
- Refresh happens in the feature branch/worktree, never in `main`.

## Never
- never push directly to `main` — main is for syncing and cutting new worktrees only
- never resolve conflicts in `main`
- never use `git push --force` (bare force is banned — `--force-with-lease` is allowed for pre-PR rebase only)
- never auto-resolve conflicts blindly with ours/theirs
- never open a duplicate PR for the same branch
- never run this skill on uncommitted work
- never expect push to succeed without understanding which gates will fire — see step 4b

## Required input
At minimum, know:
- assigned worktree path
- assigned branch
- whether a PR already exists for this branch
- whether push/PR creation is allowed

If push or PR permission is unclear, stop.

## Refresh rule
Use the simplest branch-state rule:
- **No PR yet** -> rebase onto `origin/main`
- **PR already open/shared** -> merge `origin/main` into the branch

### No PR yet
Run:

```bash
git fetch origin --prune
git rebase origin/main
```

If fetch fails (network down), stop and report. Do not push stale state.

If the branch was previously pushed and rebase rewrote history, update it only with:

```bash
git push --force-with-lease
```

Use this only before review / before PR.

### PR already open/shared
Run:

```bash
git fetch origin --prune
git merge origin/main
```

If fetch fails (network down), stop and report. Do not push stale state.

If conflicts occur:
- resolve them in this feature branch/worktree
- rerun relevant validation
- commit the merge resolution
- push the same branch

Never rebase a review-bound branch by default.

## Flow

### 1) Confirm workspace and cleanliness
Run the preflight from `SKILLS/workspace-policy.md`. Additionally confirm:
- Clean status: yes/no
- PR exists already: yes/no
- Push allowed: yes/no
- PR allowed: yes/no

If not clean, stop.

### 2) Confirm last local commit to ship
Print:

```bash
git log --oneline -n 3
```

Then state:
- commit(s) being shipped
- whether this is a new PR or update to existing PR

### 3) Refresh branch safely
Apply the refresh rule:
- no PR yet -> rebase
- PR open -> merge

If fetch fails, stop. Do not continue with stale refs.

If conflicts occur, stop after listing conflicted files unless the operator explicitly wants you to continue with conflict resolution.

List conflicts with:

```bash
git diff --name-only --diff-filter=U
```

### 4) Validation after refresh
After rebase/merge or conflict resolution, record:
- tests/checks rerun
- remaining known risk
- whether branch is ready for review

### 4b) Gate inventory

Before pushing, be aware of the gates that will fire. The pre-push hook runs these automatically — this step documents them so there are no surprise blockers:

| Gate | Script | What it checks | Failure action |
|------|--------|----------------|----------------|
| Project scope | `project_scope_guard.sh push` | Full branch diff vs scope_paths | Fix scope or update project note |
| Frontmatter integrity | `post_rebase_frontmatter_check.sh` | branch/base/scope_paths not clobbered by rebase | Edit project note frontmatter |
| Verify (cargo) | `verify.sh quick` | Rust compilation + tests + clippy | Fix code; skipped if no crates/ changes on branch |
| Verify cache | `.verify-cache` | Tree SHA match | Auto-skip if already verified |

If creating a new PR (not updating an existing one), the `pr-review-gate-hook.sh` will additionally check for a review-stack marker under `artifacts/pr-review-gate/<branch>.json`. If missing, run `/review-stack` first.

### 5) Push branch
#### New PR case
If branch not yet under review:

```bash
git push -u origin <branch>
```

If rebase rewrote previously-pushed but not-yet-reviewed history:

```bash
git push --force-with-lease
```

#### Existing PR case
Push updates to the same branch:

```bash
git push
```

### 6) PR overlap check (optional but recommended)
Before creating a new PR, check open PRs for file-level overlap:

```bash
# Changed files in current branch
git diff origin/main...HEAD --name-only

# Open PRs
gh pr list --state open --json number,title,headRefName --limit 30
```

If any open PR touches the same files, warn the operator. Do not block — let the operator decide.

### 7) Create or update PR
- If PR already exists: update the same PR, do not create a duplicate
- If no PR exists: create one with a narrow title and clear summary

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points describing what changed and why>

## Test plan
- [ ] <how to verify the changes>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Rules:
- PR title: under 70 characters, concise
- Summary: 1-3 bullet points covering the "what" and "why"
- Test plan: concrete verification steps
- Base branch: default to `main` unless the user specifies otherwise

### 8) Record result
Output:

```
Push/PR Result
- Folder:
- Branch:
- Refresh method: rebase | merge
- Push completed: yes/no
- PR action: created | updated | none
- PR link/number:
- Validation after refresh:
- Conflicts encountered: yes/no
- Next recommended step:
```

## Obsidian update requirement
Before finishing, update the relevant Obsidian session/project note with:
- branch
- worktree path
- latest commit hash shipped
- whether branch was rebased or merged with main
- PR number/url
- validation after refresh
- handoff / next step

## Definition of done
This skill is done only when all are true:
- correct worktree confirmed
- clean state confirmed before refresh
- branch refreshed using correct rule
- branch pushed safely
- PR created or updated appropriately
- Obsidian updated
- next step stated clearly
