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
- **never call `code_review_expert_attest.sh` unless you actually ran code-review-expert and reported findings in this session** — the attestation script is not a rubber stamp

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

### 2) Stage intended files + Obsidian tracking

Stage implementation files by explicit path, not broad wildcards, unless the operator explicitly approves broader staging.

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

**Obsidian tracking (soft gate):**
The pre-commit hook classifies changes by risk class (`docs_only`, `obsidian_only`, `non_critical`, `critical`). For `non_critical` and `critical` changes:

- Update the project note (`obsidian/Projects/`) with what changed.
- If this is the **first commit in a review window**, create or update a debrief/session handoff (`obsidian/Debriefs/`) and link it from the project note's `## Debriefs` section.
- If this is a **follow-up commit** (debrief already on this branch), set `OBSIDIAN_REVIEW_FIX=1` to skip the debrief requirement.
- If **amending**, the guard auto-detects and passes.

Stage obsidian files alongside implementation files:

```bash
git add path/to/impl obsidian/Projects/MyProject.md obsidian/Debriefs/MyProject\ 2026-03-19\ Summary.md
```

For `docs_only` and `obsidian_only` changes, the gate is skipped at commit time (enforced at push/PR boundary).

### 3) Code review gate

For `non_critical` and `critical` changes, the pre-commit hook requires a code-review-expert attestation. This gate exists to ensure you actually reviewed your own work before committing.

**You must run code-review-expert BEFORE attempting the commit.** The flow is:

1. Run `code-review-expert` (the superpowers agent) on the staged changes
2. Report the findings to the operator
3. Fix any P0/P1 issues found
4. Only then call `./plans/code_review_expert_attest.sh` to write the marker
5. Proceed to commit

**Do not call `code_review_expert_attest.sh` to unblock the gate without running the review.** That is fake compliance. If you did not review the code, say so in the commit result and let the operator decide.

For `docs_only`, `obsidian_only`, and `formatting_only` changes, this gate is skipped at commit time.

### 4) Validation record
Before commit, record what was checked.

Minimum output:
- Code review: ran / skipped (with reason)
- Tests run:
- Remaining known risk:

If nothing was validated, say so explicitly.

### 5) Create commit
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

### 6) Record result
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
