# SKILL: /pr-check (Review Comments → Resolve Conflicts → Merge → Sync)

> **Canonical version.** The `commit-commands` plugin also registers `pr-check` — that is a generic fallback. This SKILLS/ file is the project-specific version with opus-trader conventions (conflict resolution bias, dependency ordering). Prefer this one.

## Purpose
Scan all open PRs, surface review comments and merge conflicts, resolve them, merge approved PRs, and sync local main.

## When to use
- After `/commit-push-pr` to shepherd PRs to completion
- Periodic housekeeping to keep PRs moving
- When you want a single command to clear your PR queue

## Process

### 1) List All Open PRs
```bash
gh pr list --state open --author @me --json number,title,headRefName,mergeable,reviewDecision,statusCheckRollup
```

For each open PR, collect:
- PR number and title
- Branch name
- Mergeable status (MERGEABLE, CONFLICTING, UNKNOWN)
- Review decision (APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, empty)
- CI check status

Present a summary table to the user:
```
| PR  | Title            | Branch         | Conflicts | Reviews           | CI    |
|-----|------------------|----------------|-----------|-------------------|-------|
| #42 | feat: add widget | feature/widget | None      | APPROVED          | Pass  |
| #38 | fix: cache bug   | fix/cache      | YES       | CHANGES_REQUESTED | Pass  |
```

### 1.5) Detect Superseded / Overlapping PRs
For each pair of open PRs, fetch their changed file lists:
```bash
gh pr diff <number> --name-only
```

Flag pairs that show any of these signals:

| Signal | How to detect |
|--------|---------------|
| **Shared files** | Same path appears in both diffs |
| **Stacked branches** | One branch is based on another (`git merge-base --is-ancestor`) |
| **Commits absorbed** | Commit subjects from PR A appear verbatim in PR B's log |

```bash
# Fetch once before all comparisons (not per-pair)
git fetch origin

# Check if branch A is an ancestor of branch B (stacked)
git merge-base --is-ancestor origin/<branch-a> origin/<branch-b> && echo "stacked"

# Check if PR A's commits are absorbed into PR B (superseded)
git log origin/main..origin/<branch-a> --format='%s' | \
  while read subject; do
    git log origin/<branch-b> --format='%s' | grep -qF "$subject" && echo "absorbed: $subject"
  done

# List commits unique to each PR vs main
git log origin/main..origin/<branch> --oneline
```

Present findings **before** doing any other work:
```
### Potential PR Overlaps (advisory — you decide)
| PR A | PR B | Signal            | Detail                        |
|------|------|-------------------|-------------------------------|
| #38  | #42  | Shared files      | src/auth.rs, config.toml      |
| #35  | #38  | #35 is base of #38| stacked — merge #35 first     |
| #35  | #42  | Commits absorbed  | "fix: validate input" in both |
```

**Ask the user:** "Should any of these be closed before proceeding?"

If the user says yes to closing a PR:
```bash
gh pr close <number> --comment "Superseded by #<other>"
```
Never close a PR without explicit user confirmation per PR.

Skip this step silently if there is only one open PR.

### 2) Surface Review Comments
For each PR with comments or requested changes:
```bash
gh pr view <number> --comments
gh api repos/{owner}/{repo}/pulls/<number>/reviews --jq '.[] | select(.state != "APPROVED") | {user: .user.login, state: .state, body: .body}'
gh api repos/{owner}/{repo}/pulls/<number>/comments --jq '.[] | {user: .user.login, path: .path, line: .line, body: .body}'
```

Summarize each comment with:
- Who left it
- What file/line it's about
- What they want changed
- Suggested action (code fix, clarification reply, dismiss)

**Ask the user** which comments to address before making changes.

### 3) Address Review Comments
For each comment the user wants addressed:
1. Read the relevant file and understand the context
2. Make the fix
3. Stage and commit with message: `review: address <reviewer> feedback on PR #<number>`
4. Push to the PR branch

```bash
git checkout <pr-branch>
# ... make fixes ...
git add <files>
git commit -m "$(cat <<'EOF'
review: address feedback on PR #<number>

<brief description of what was changed and why>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

### 4) Resolve Merge Conflicts
For each PR with CONFLICTING status:
```bash
git checkout <pr-branch>
git fetch origin main
git merge origin/main
```

If conflicts arise:
1. List conflicting files
2. Read each conflicted file
3. Resolve conflicts — prefer the PR branch's intent, incorporate main's structural changes
4. **Show the user** the resolution for each file before staging
5. Stage and commit:
```bash
git add <resolved-files>
git commit -m "$(cat <<'EOF'
merge: resolve conflicts with main for PR #<number>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

### 5) Merge Approved PRs
For each PR that is:
- Review decision: APPROVED (or no reviewers required)
- CI checks: passing
- No merge conflicts

**Ask the user** which PRs to merge, then:
```bash
gh pr merge <number> --merge --delete-branch
```

Rules:
- Default to merge commit (not squash/rebase) unless user specifies otherwise
- Delete the remote branch after merge
- Process PRs in dependency order if branches are stacked

### 6) Sync Local Main
After all merges complete:
```bash
git checkout main
git pull origin main
```

If the user was on a feature branch that got merged:
- Inform them the branch was deleted remotely
- Suggest which branch to work on next

If there are remaining open PRs based on main:
```bash
# Rebase remaining PR branches onto updated main
git checkout <remaining-branch>
git rebase origin/main
git push --force-with-lease
```

**Ask before rebasing** — never force-push without confirmation.

### 7) Final Report
```
## PR Shepherd Summary

### Merged
- #42 feat: add widget → merged to main ✓

### Updated (comments addressed)
- #38 fix: cache bug → pushed review fixes, awaiting re-review

### Conflicts Resolved
- #38 fix: cache bug → resolved 2 files, pushed

### Still Open
- #35 refactor: auth flow → waiting on CI

### Local
- main synced to <sha>
- Current branch: <branch>
```

## Hard Constraints
- Never merge a PR without user confirmation
- Never close a PR without explicit user confirmation (step 1.5)
- Never force-push without user confirmation (use `--force-with-lease` when approved)
- Never dismiss reviews — only address them
- Never merge PRs with failing CI unless user explicitly overrides
- Never resolve conflicts by deleting the PR's changes — preserve intent
- Always show conflict resolutions to the user before committing
- Process stacked PRs in dependency order (base first)
- Step 1.5 overlap analysis is advisory only — never infer intent, always present evidence and ask
