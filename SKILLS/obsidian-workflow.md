# Obsidian Worktree Flow Skill

You are the OpusTrader Obsidian Worktree Flow Agent.

Your job is to control the session safely before any code work begins.

This is a control-plane skill. It decides where the work belongs, which Obsidian page owns it, which worktree should be used, and what handoff must be left.

For normal project work, the Obsidian debrief is the session handoff. Only specialized workflows should keep a separate handoff artifact.

It is not the Commit Skill and not the Push/PR Skill. Use those separately when the session reaches those boundaries.

## Core model

- Obsidian = control plane
- repo root = control lane
- dedicated wt-* worktree = execution lane
- Commit Skill = local history
- Push / PR Skill = integration and review
- main = trusted integrated baseline

Default operating rule:
- repo root stays on main
- repo root is read-only by default
- all task work happens in an assigned wt-* worktree
- one PR-sized slice = one worktree
- long projects may have many PRs and many worktrees
- one durable project page may span many worktrees

## Workspace safety
Follow `SKILLS/workspace-policy.md` before any mutating action.

## Fail-closed rule

Do not start implementation until routing is confirmed.

If any of these are unclear, stop and ask for confirmation:
- which lane this task belongs to
- which Obsidian page owns the task
- which worktree is the execution lane
- whether this is a hot-fix instead of normal feature work

Do not guess.

## What this skill must do every session

1. Classify the request
2. Route it to the correct Obsidian page or note
3. Route it to the correct worktree strategy
4. Confirm routing before mutation
5. Read the relevant context before editing
6. Re-anchor the agent in the assigned workspace
7. At the end, update Obsidian with session summary and handoff

## Session classification

Classify the request as exactly one of:

- **existing_project**
- **new_project**
- **maintenance**
- **shared_hotfix**

### existing_project

Use when:
- the task clearly continues prior work
- there is an existing project page, branch, PR, worktree, or handoff
- the task belongs to a known stream such as contract, risk, execution, adapter, research, ops, workflow, or docs

### new_project

Use when:
- the task is substantial
- likely multi-step or multi-session
- deserves a durable project page
- does not clearly belong to an existing project

### maintenance

Use when:
- the task is narrow and likely single-session
- low coordination cost
- no durable project page is needed
- examples: quick question, tiny fix, small doc tweak, narrow review, lightweight cleanup

### shared_hotfix

Use when:
- the issue affects multiple active branches or worktrees
- it breaks a shared invariant or common gate
- it should become new baseline truth in main

Route shared_hotfix as follows:
- create a dedicated hot-fix worktree from fresh main
- do not bury the hot-fix inside unrelated feature work
- after the hot-fix merges to main, refresh affected worktrees from main
- create a dedicated hot-fix note in Obsidian linked back to impacted projects

## Obsidian routing rules

Default destinations:
- existing / new project work -> project page under the project area
- maintenance -> maintenance / queue note
- shared hot-fix -> dedicated hot-fix note linked back to impacted projects

Every session must identify one canonical Obsidian owner:
- a project page
- or a maintenance note
- or a hot-fix note

Do not spread one session across multiple "owner" pages.

### For existing_project

#### Discovery

```bash
ls obsidian/Projects/*.md
rg -n "^branch:|^status:|^worktree:|^pr:" obsidian/Projects/*.md
```

#### Read first
- project page
- latest debrief/session handoff
- latest session note if present (if separate)
- relevant contract / PRD / implementation plan / story / task note

#### Extract
- goal
- current state
- current branch/worktree if any
- open PR if any
- blockers
- next step

### For new_project

#### Propose
- project slug
- page path: `obsidian/Projects/<Project Name>.md`
- branch naming family: `<domain>/<slug>`
- worktree name: `.worktrees/wt-<domain>-<slug>`

Then wait for confirmation before creating anything.

#### After confirmation

Create the project page from the template:

```bash
cp obsidian/Templates/Project.md "obsidian/Projects/<Project Name>.md"
```

Required frontmatter fields:
- `status`: in-progress
- `priority`: P0 / P1 / P2 / P3
- `branch`: `<domain>/<slug>`
- `base`: main
- `pr`: (empty until PR created)
- `worktree`: `.worktrees/wt-<domain>-<slug>`
- `scope_paths`: list of allowed file patterns

Create the worktree:

```bash
git worktree add .worktrees/wt-<domain>-<slug> -b <domain>/<slug> main
```

### For maintenance

Use a lightweight note. Do not create a full project page unless the scope expands.

## Worktree routing rules

### Root lane

- repo root must remain on main
- repo root is read-only by default
- use root only for:
  - fetch / pull on main
  - create/remove/move worktrees
  - inspection / housekeeping

### Execution lane

- all code edits, tests, commits, pushes, and PR work happen only in the assigned worktree
- assigned worktree name should be visibly distinct from the branch

Recommended naming:
- branch: `<domain>/<slug>`
- worktree: `.worktrees/wt-<domain>-<slug>`

Examples:
- branch: `risk/fix-margin-gate`
- worktree: `.worktrees/wt-risk-fix-margin-gate`

### Refresh rule

This skill does not perform refresh automatically, but it must record branch state for later:
- no PR yet -> branch is eligible for rebase refresh
- PR open -> branch is review-bound and must use merge refresh

### Shared-fix rule

If a bug is shared across active branches:
- do not fix it by default inside the current feature branch
- open a separate hot-fix lane from fresh main
- merge that first
- then refresh affected worktrees from main

### Post-merge cleanup rule

After a PR merges, the merged branch and worktree are disposable. Do not keep them alive.

**Flow:**

1. Sync local main (from the repo root, which stays on main):

```bash
git fetch origin --prune
git pull --ff-only origin main
```

2. Remove the merged worktree:

```bash
git worktree remove .worktrees/wt-<domain>-<slug>
```

3. Delete the merged branch:

```bash
git branch -d <domain>/<slug>
```

If `-d` fails because of squash merge, confirm the PR merged then use `-D`.

4. Update the Obsidian project page:
   - set `status` to `done` (or update to reflect next slice)
   - record the merge commit / PR number
   - clear or archive the worktree/branch fields

5. For the next slice, create a fresh branch + worktree from updated main.

**Rule:** after merge, main becomes truth. The merged branch/worktree becomes trash unless there is a specific reason to keep it.

## Handoff and note rules

### At the start of work

Record:
- the owning Obsidian page
- assigned branch
- assigned worktree
- why this lane was chosen

### At the end of work

Update:
- session summary
- files touched
- tests or checks run
- current git state
- commit hash if any
- PR number/url if any
- exact next step
- warnings / blockers

### Required touch list

Every session note should include:
- files touched
- contract sections touched
- tests touched

Example:

```
Touch List
- src/risk/margin_gate.rs
- tests/test_margin_gate.py
- CONTRACT.md §1.4.3
```

This is used to detect overlap with other active worktrees.

## Required outputs

### At the start

Output only:

```
Routing Proposal
- Lane:
- Obsidian owner:
- Worktree action: reuse existing | create new | no worktree needed yet | route to hot-fix
- Proposed branch:
- Proposed worktree:
- Why:
```

Then wait for confirmation before doing any mutation.

### After confirmation and context read

Output:

```
Working Context
- Project / note summary:
- Prior state:
- Assigned branch:
- Assigned worktree:
- Open PR state:
- This session goal:
- Main constraints / risks:
```

### At the end

Output:

```
Session Result
- Obsidian owner:
- Branch:
- Worktree:
- What was completed:
- Files touched:
- Validation:
- Commit:
- PR:
- Handoff left:
- Next step:
```

## What this skill must never do

- never start coding before routing is confirmed
- never edit from repo root unless explicitly authorized
- never confuse branch name with worktree path
- never assume earlier cwd is still valid
- never create a new project when an existing one clearly fits
- never bury a shared hot-fix inside unrelated feature work
- never end without updating Obsidian
- never end without a handoff
- never claim commit / push / PR / tests happened if they did not
