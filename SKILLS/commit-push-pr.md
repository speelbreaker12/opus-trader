# SKILL: /commit-push-pr (Stage → Commit → Push → PR)

> **Canonical version.** The `commit-commands` plugin also registers `commit-push-pr` — that is a generic fallback. This SKILLS/ file is the project-specific version with opus-trader conventions (HEREDOC commits, Co-Author line, no force-push). Prefer this one.

## Purpose
One-shot command to stage changes, create a well-formed commit, push the branch, and open a PR on GitHub.

## When to use
- After completing implementation work and you're ready to ship
- When you want to go from local changes to an open PR in one step

## Process

### 1) Survey Changes
```bash
# See what's changed
git status
git diff --stat
git log --oneline -5
```

Review all staged and unstaged changes. Identify:
- Which files should be committed (skip secrets, `.env`, large binaries)
- Whether changes are logically cohesive (one PR = one concern)

### 1.5) Sync with main

Before staging, bring the branch up to date:

```bash
git fetch origin main
git merge origin/main
```

- If the merge is **clean** → continue to step 2
- If there are **conflicts** → stop immediately. List conflicting files:
  ```bash
  git diff --name-only --diff-filter=U
  ```
  Then ask the user: resolve now or abort? Do not proceed until they decide.
- Never auto-resolve conflicts

### 2) Stage Files
- Stage files by name — prefer `git add <file>...` over `git add -A`
- Never stage files that contain secrets or credentials
- If changes span multiple concerns, ask the user whether to split into separate commits

### 3) Write Commit Message
Follow project conventions from CLAUDE.md:

```
<area>: <what changed>

<optional body — why, not what>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Rules:
- First line under 72 characters
- Format: `<area>: <what changed>`
- Reference CONTRACT.md sections when implementing contract requirements
- Use a HEREDOC to pass the message to `git commit`

### 4) Push Branch
```bash
# Push with upstream tracking
git push -u origin HEAD
```

- If the branch has no upstream, set it with `-u`
- Never force-push unless the user explicitly requests it
- Never push to `main` or `master` directly

### 5) Create Pull Request
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
- If a PR already exists for this branch, update it instead of creating a duplicate

### 6) Report Back
Output the PR URL so the user can review it.

## Hard Constraints
- Never force-push
- Never push directly to main/master
- Never stage files containing secrets (.env, credentials, tokens)
- Never skip the Co-Authored-By line
- Never create empty commits
- If there are merge conflicts, stop and ask the user
- If there are no changes to commit, say so and stop
