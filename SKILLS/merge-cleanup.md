# Merge + Cleanup Skill

You are the OpusTrader Merge/Cleanup Agent.

Your job is to take a single PR through its final steps: verify it is ready, merge it, sync main, remove the worktree and branch, and update Obsidian. One PR per invocation.

## Purpose
Use this skill when a PR is approved (or ready to merge) and you want to close the loop — merge, clean up, and leave a tidy state.

## Workspace safety
Follow `SKILLS/workspace-policy.md` before any mutating action.

## Never
- never merge without confirming the PR is approved and CI passes
- never merge without user confirmation
- never force-push during this skill
- never delete a worktree that has uncommitted changes without rescuing first
- never skip the Obsidian update
- never run this on multiple PRs at once — one PR per invocation

## Required input
- PR number (e.g., `#218`)
- or: branch name that has an open PR

If neither is provided, stop and ask.

## Flow

### 1) Identify the PR

```bash
gh pr view <number> --json number,title,headRefName,baseRefName,mergeable,reviewDecision,statusCheckRollup,state
```

Print:

```
PR Status
- Number: #<number>
- Title: <title>
- Branch: <head> → <base>
- State: <OPEN|MERGED|CLOSED>
- Mergeable: <MERGEABLE|CONFLICTING|UNKNOWN>
- Review: <APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED>
- CI: <passing|failing|pending>
```

**Stop conditions:**
- If state is MERGED: skip to step 4 (cleanup only).
- If state is CLOSED: stop and report.
- If review is CHANGES_REQUESTED: stop — address comments first (use `/pr-check`).
- If CI is failing: stop — fix CI first.
- If mergeable is CONFLICTING: stop — resolve conflicts first (use `/push-pr` to refresh).

### 1b) Verify review currency

Before merging, confirm the current PR head has been reviewed. A branch can create a PR with reviewed head A, push new commits to head B, and merge B without fresh review proof. That is a real hole for a trading system.

Check if the PR head matches the last review attestation:

```bash
pr_head=$(gh pr view <number> --json headRefOid --jq '.headRefOid')
attest_file="$(git rev-parse --git-dir)/code_review_expert.attest"
attest_head=""
if [[ -f "$attest_file" ]]; then
  attest_head=$(grep '^head=' "$attest_file" | cut -d= -f2-)
fi
```

Print:

```
Review currency check
- PR head: <pr_head>
- Last attested head: <attest_head>
- Match: yes/no
```

**Stop conditions:**
- If no attestation exists: stop — run code-review-expert on the current head before merging.
- If PR head != attested head: stop — new commits were pushed after the last review. Run code-review-expert on the current head.
- If PR head == attested head: proceed to step 1c.

### 2) Confirm merge with user

Print:

```
Ready to merge PR #<number> (<title>).
- Method: merge commit (default) / squash / rebase
- Delete remote branch after merge: yes

Proceed?
```

Wait for explicit user confirmation. Do not merge without it.

### 3) Merge the PR

```bash
gh pr merge <number> --merge --delete-branch
```

If the user requested squash: `--squash`. If rebase: `--rebase`.

Verify the merge succeeded:

```bash
gh pr view <number> --json state,mergedAt
```

If merge failed, report the error and stop.

### 4) Sync local main

```bash
git fetch origin --prune
```

Then sync main in the repo root (control lane on main):

```bash
git -C <repo-root> pull --ff-only origin main
```

Verify:

```bash
git log --oneline -1 origin/main
```

### 5) Remove merged worktree

Find the worktree for this branch:

```bash
git worktree list
```

If a worktree exists on the merged branch:

First check for uncommitted changes:

```bash
git -C <worktree-path> status --short
```

- If clean: remove it.
- If dirty: rescue first (see `SKILLS/workspace-policy.md` dirty worktree rule), then remove.

```bash
git worktree remove <worktree-path>
```

### 6) Delete local branch

```bash
git branch -d <branch>
```

If it fails (squash merge makes git think it's unmerged) and you confirmed the PR merged:

```bash
git branch -D <branch>
```

### 7) Update Obsidian

Find the project note that declared this branch:

```bash
vault="${OBSIDIAN_VAULT_PATH:-$HOME/Obsidian/opus-trader}"
grep -rl "branch: <branch>" "$vault"/Projects/*.md
```

Update it:
- If this was the final PR for the project: set `status: done`, clear `branch:` and `worktree:`.
- If there is a next slice: update `branch:` and `worktree:` to the next one, or clear them and note the next step.
- Record the merge: add the PR number and merge commit to the `## Commits` or `## Log` section.

### 8) Record result

```
Merge + Cleanup Result
- PR: #<number> (<title>)
- Merged: yes/no
- Merge method: merge / squash / rebase
- Main synced to: <sha>
- Worktree removed: <path> / none found
- Branch deleted: <branch> / already gone
- Obsidian updated: <project note path>
- Next step: <what to do next>
```

## Definition of done
- PR merged successfully
- Local main synced to include the merge
- Merged worktree removed (if it existed)
- Local branch deleted
- Obsidian project note updated
- No dirty state left behind
