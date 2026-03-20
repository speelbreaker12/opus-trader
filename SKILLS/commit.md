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

### 1) Confirm workspace + main branch gate

Run the preflight from `SKILLS/workspace-policy.md`. Review the `git status --short` output to identify in-scope and unexpected files.

**Hard gate:** check the current branch immediately:

```bash
current_branch="$(git branch --show-current)"
```

If `current_branch` is `main` or `master`: **STOP.** Do not proceed. Print:

```
ERROR: Current branch is main. Commits on main are blocked.
Use /main-recovery if main is in an abnormal state.
Otherwise, switch to your assigned worktree.
```

If any other preflight check fails, stop.

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
The pre-commit hook classifies changes by risk class (`docs_only`, `obsidian_only`, `formatting_only`, `non_critical`, `critical`). For `non_critical` and `critical` changes:

- **On each commit:** append to the session debrief/handoff note (`obsidian/Debriefs/`). This is an append-only log — do not rewrite it on every commit.
- **On the first commit in a review window:** create the debrief note and link it from the project note's `## Debriefs` section.
- **Do not update the main project page (`obsidian/Projects/`) on every commit.** Update it once per session or at the PR boundary (`/push-pr`). Touching it on every commit creates merge conflicts across branches.
- If this is a **follow-up commit** (debrief already on this branch), set `OBSIDIAN_REVIEW_FIX=1` to skip the debrief requirement.
- If **amending**, the guard auto-detects and passes.

Stage the debrief alongside implementation files:

```bash
git add path/to/impl obsidian/Debriefs/MyProject\ 2026-03-19\ Summary.md
```

For `docs_only`, `obsidian_only`, and `formatting_only` changes, the gate is skipped at commit time (enforced at push/PR boundary).

### 3) Validation record
Before commit, record what was checked.

Minimum output:
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

Co-author footer is optional. Include it when the agent materially contributed to the implementation:

```bash
git commit -m "$(cat <<'EOF'
risk: fail closed when margin headroom input is missing

Co-Authored-By: <agent-identity>
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

## Obsidian update rule

- **Debrief/handoff note:** append on each commit (commit hash, what changed, validation).
- **Main project page:** update once per session or at PR boundary — not on every commit.

## Definition of done
This skill is done only when all are true:
- correct worktree confirmed (not main, not bare repo root)
- intended files staged only
- local commit created successfully
- no push performed
- no PR action performed
- debrief/handoff note appended
- next step stated clearly
