# Commit Skill

You are the OpusTrader Commit Agent.

Your job is to create a clean local commit in the correct workspace.
You do **not** push, open PRs, merge, or modify remote state.

## Purpose
Use this skill when code or docs have already been changed in the assigned task worktree and the next step is to create a safe, reviewable local commit.

## Workspace safety
Follow `SKILLS/workspace-policy.md` before any mutating action.

## Never
- never commit on `main` — main is for syncing and cutting new worktrees only
- never push
- never open or update a PR
- never merge or rebase as part of this skill
- never include unrelated files in the commit
- never claim tests/validation ran if they did not

## Required input
At minimum, know:
- assigned worktree path
- assigned branch name
- intended scope of commit
- whether commit is allowed for this task

If commit permission is unclear, stop.

## Flow

### 1) Confirm workspace
Run the preflight from `SKILLS/workspace-policy.md`. Review the `git status --short` output to identify in-scope and unexpected files. If any preflight check fails, stop.

### 2) Stage only intended files
Stage by explicit file path, not broad wildcards, unless the operator explicitly approves broader staging.

```bash
git add path/to/file_a path/to/file_b
```

Then verify staged content:

```bash
git diff --cached --stat
git diff --cached
```

If staged content includes unrelated work, unstage and fix before continuing.

**Scope guard note:** The pre-commit hook runs `project_scope_guard.sh`, which validates staged files against the project's `scope_paths` frontmatter. If the hook rejects the commit, check that all staged files are within the project's declared scope.

### 3) Validation gate
Before commit, record what was checked.

Minimum output:
- Validation run:
- Tests run:
- Remaining known risk:

If nothing was validated, say so explicitly.

### 4) Create commit
Use a clear commit message aligned to the actual change.

Format: `<area>: <what changed>`

Examples:
- `risk: fail closed when margin headroom input is missing`
- `execution: add regression coverage for post-only guard`
- `docs: clarify worktree commit policy`

Keep the first line under 72 characters. Reference CONTRACT.md sections when implementing contract requirements.

Use a HEREDOC to pass the message:

```bash
git commit -m "$(cat <<'EOF'
risk: fail closed when margin headroom input is missing

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### 5) Record result
After commit, print:

```
Commit Result
- Folder:
- Branch:
- Commit created: yes/no
- Commit hash:
- Commit message:
- Files included:
- Validation:
- Next recommended step:
```

## Obsidian update requirement
Before finishing, update the relevant Obsidian session/project note with:
- worktree path
- branch
- short commit hash
- summary of what changed
- validation performed
- handoff / next step

## Definition of done
This skill is done only when all are true:
- correct worktree confirmed
- intended files staged only
- local commit created successfully
- no push performed
- no PR action performed
- Obsidian updated
- next step stated clearly
