# SKILL: /commit-push-pr (Stage → Commit → Push → PR)

## Purpose
One-shot command to stage changes, create a well-formed commit, push the branch, and open a PR on GitHub.

## When to use
- After completing implementation work and you're ready to ship
- When you want to go from local changes to an open PR in one step

## Process

### 1) Survey Changes
```bash
git status
git diff --stat
git log --oneline -5
```

Review all staged and unstaged changes. Identify:
- Which files should be committed (skip secrets, `.env`, large binaries)
- Whether changes are logically cohesive (one PR = one concern)

### 2) Mixed-Concern Scan

Before staging, analyse whether the changed files span unrelated concerns.

```bash
# Files changed vs main (or the relevant base branch)
git diff main...HEAD --name-only 2>/dev/null || git diff --name-only
```

Group changed files by top-level module (first two path components). Flag as **mixed-concern** if ANY of:
- Multiple distinct crates are touched (`crates/soldier_core/` AND `crates/soldier_infra/` AND/OR `crates/other/`)
- Source code (`crates/`) is mixed with workflow tooling (`plans/`) where the `plans/` changes are not directly supporting the same story (e.g., unrelated lint scripts)
- Changes span >3 unrelated subsystems within a single crate (e.g., `execution/`, `risk/`, `venue/`, `pricer/` all changed for different reasons)

**If mixed-concern is detected:**
- Report the groupings clearly:
  ```
  ⚠️  Mixed-concern detected:
    Group A (execution gate): crates/soldier_core/src/execution/gate.rs, ...
    Group B (venue facade lint): plans/lint_venue_facade.sh, ...
  ```
- Ask the user: "These changes appear to mix concerns. Recommend splitting into separate PRs. Proceed as one PR, or split?"
- **Do NOT auto-split.** Wait for user instruction.
- If user says "proceed as one" — continue. If "split" — stage and commit Group A first, then Group B as a follow-up commit/PR.

### 3) Stage Files
- Stage files by name — prefer `git add <file>...` over `git add -A`
- Never stage files that contain secrets or credentials
- Only stage files belonging to the concern of this PR

### 4) Write Commit Message
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

### 5) Push Branch
```bash
git push -u origin HEAD
```

- If the branch has no upstream, set it with `-u`
- Never force-push unless the user explicitly requests it
- Never push to `main` or `master` directly

### 6) PR Overlap Check

Before creating the PR, check open PRs for file-level overlap with the current branch.

```bash
# List open PRs
gh pr list --state open --json number,title,headRefName --limit 30
```

For each open PR, get its changed files and intersect with the current branch's changed files:
```bash
# Changed files in current branch (vs base)
CURRENT_FILES=$(git diff origin/main...HEAD --name-only 2>/dev/null)

# For each open PR number N:
gh pr diff <N> --name-only 2>/dev/null
```

**Flag overlap** if any open PR touches ≥1 of the same files as the current branch.

Report findings:
```
ℹ️  Open PR overlap check:
  PR #42 "execution: add liquidity gate" — overlapping files: crates/soldier_core/src/execution/gate.rs
  PR #38 "risk: venue facade lint" — no overlap ✓
```

**If overlap found:**
- Warn: "PR #N already touches these files. Merging both could cause conflicts."
- Ask: "Proceed anyway, or review PR #N first?"
- Do NOT block — let the user decide.

**If no overlap:**
- Print: "No overlap with open PRs ✓"
- Continue to PR creation.

### 7) Create Pull Request
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

### 8) Report Back
Output the PR URL so the user can review it.

## Hard Constraints
- Never force-push
- Never push directly to main/master
- Never stage files containing secrets (.env, credentials, tokens)
- Never skip the Co-Authored-By line
- Never create empty commits
- If there are merge conflicts, stop and ask the user
- If there are no changes to commit, say so and stop
- Never auto-split commits — detect and warn only, user decides
