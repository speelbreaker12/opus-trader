# Resume Project

Deterministic project resumption. No guessing.

## Steps

### 1. Read the active pointer

```bash
cat ~/Desktop/obsidian/index/ACTIVE_PROJECT.md
```

This file contains a single wikilink to the current project.

### 2. Load project state

Read the linked project file from `~/Desktop/obsidian/projects/`.

Extract:
- `status` (frontmatter)
- `branch` (frontmatter)
- `worktree` (frontmatter)
- `pr` (frontmatter)
- `## Objective`
- `## Touch Files` (Primary and Secondary)
- `## Current State`
- `## Next Actions` or last `## Log` entry

### 3. Match check

Two-signal matching — use **both** semantic match and touch file overlap:

**Signal 1 — Semantic:** Does the user's prompt match the project's objective/context?

**Signal 2 — Touch files:** Do the files the user mentions or implies overlap with the project's Touch Files?

Decision:
- Both signals match → confirmed, proceed
- Semantic matches but touch files don't → likely the right project, proceed with caution
- Touch files match but semantic doesn't → check if work belongs to this project
- Neither matches → search other active projects

If the user's prompt clearly does NOT match the active project:
- Search `~/Desktop/obsidian/projects/*.md` for a better match using both signals
- Prefer the project whose touch files best match the requested files
- If ambiguous → **ASK**. Do not guess.
- If a match is found → update `ACTIVE_PROJECT.md` to point to it

### 4. Enforce environment

If the project has a `worktree` field:
- Verify the worktree exists
- Switch to it

If the project has a `branch` field:
- Verify the current branch matches
- If not → switch or warn

### 5. Output

```
PROJECT: <name>
WORKTREE: <path>
BRANCH: <branch>
STATUS: <status>
PR: <number or none>
CONFLICT: <CLEAR or details>

TOUCH FILES (Primary):
- <file1>
- <file2>

NEXT:
1. <from project file>
2. <from project file>

ACTION:
<Switching to worktree... | Already in correct worktree | No worktree assigned>
```

Then proceed with the user's request.

## Rules

- Never start work without confirming the project match
- Never guess when ambiguous — ask
- Always output the project block before doing anything
- If no `ACTIVE_PROJECT.md` exists or is empty, search `projects/` and ask
- If the user's requested files fall outside the project's Touch Files, warn about scope drift before proceeding
