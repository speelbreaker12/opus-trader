# New Project

Create a new project with file, worktree, index registration, and conflict check.

## Steps

### 1. Infer touch files

From the user's request, identify:
- Exact files that will be modified
- Directories/modules that will be touched
- Test files related to the work

Classify each as **Primary** (core implementation) or **Secondary** (tests, docs, incidental).

### 2. Scan for conflicts

Read all active project files in `~/Desktop/obsidian/projects/`:

```bash
grep -l "^status: in-progress" ~/Desktop/obsidian/projects/*.md
```

For each active project, compare proposed touch files against its `## Touch Files` section.

**Conflict rules:**
- **Red**: same Primary file/path in two active projects → STOP
- **Yellow**: overlap in Secondary files → WARN
- **Green**: no overlap → proceed

If Red conflict detected, output:

```
CONFLICT DETECTED

Proposed touch files overlap with active project:
- Project: <existing project name>
- Worktree: <existing worktree>
- Overlapping files:
  - <file1>
  - <file2>

Options:
1. Continue in existing project
2. Expand existing project scope
3. Create new project with revised non-overlapping touch surface
```

Then **ASK**. Do not proceed.

### 3. Create project file

After conflict check passes:

```bash
cat > ~/Desktop/obsidian/projects/<Project Name>.md << 'EOF'
---
status: in-progress
priority: <P0|P1|P2|P3>
branch: <domain>/<slug>
base: main
pr:
started: "<YYYY-MM-DD>"
worktree: .worktrees/wt-<domain>-<slug>
---

## Objective
<one sentence>

## Touch Files
### Primary
- <path1>
- <path2>

### Secondary
- <test_path1>
- <doc_path1>

## Conflict Status
CLEAR

## Current State
<initial intent>

## Commits

## Next Actions
- Define plan

## Links
- Plan:
- Design:
- Audit:

## Key Files

## Debriefs

## Log
### <YYYY-MM-DD>
- Project created
EOF
```

### 4. Create worktree and branch

```bash
cd <repo-root>
git worktree add .worktrees/wt-<domain>-<slug> -b <domain>/<slug> main
```

### 5. Update index

Add a row to `~/Desktop/obsidian/index/PROJECT_INDEX.md`:

```
| [[<Project Name>]] | in-progress | <priority> | <domain>/<slug> | — |
```

### 6. Set as active

```bash
echo '[[projects/<Project Name>]]' > ~/Desktop/obsidian/index/ACTIVE_PROJECT.md
```

### 7. Output

```
PROJECT: <name>
WORKTREE: .worktrees/wt-<domain>-<slug>
BRANCH: <domain>/<slug>
STATUS: in-progress
CREATED: <date>
CONFLICT: CLEAR

TOUCH FILES (Primary):
- <path1>
- <path2>

NEXT:
1. Define plan

ACTION:
Switched to worktree .worktrees/wt-<domain>-<slug>
```

## Rules

- Touch files must be declared at project creation, not "figured out later"
- Always run conflict check before creating
- No two active projects may own the same Primary touch file unless explicitly marked as a deliberate shared-scope exception
- One project = one file = one branch = one worktree
- Never create `obsidian/` folders inside repos
- Always update both `PROJECT_INDEX.md` and `ACTIVE_PROJECT.md`
