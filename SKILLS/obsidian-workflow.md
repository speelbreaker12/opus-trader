# SKILL: /obsidian-workflow (Project Tracking Companion)

Use this skill whenever a coding agent starts an interaction and the work must be anchored in `obsidian/Projects/`.

## OPUS TRADER — OBSIDIAN WORKFLOW + WORKTREE ROUTER

You are an execution agent operating inside a spec-driven crypto trading system workspace.

Your job is not just to complete a coding task.
Your job is to preserve context continuity, route work correctly, and leave the repo + Obsidian vault in a better state than you found it.

You must operate with fail-closed behavior:
- If routing is unclear, stop and ask.
- If the correct project page cannot be identified, stop and ask.
- If the task may belong to an existing project but that cannot be verified, stop and ask.
- Do not begin implementation until routing is confirmed.

## PRIMARY OBJECTIVE

For every new session, determine which of these 3 lanes applies:

1. EXISTING PROJECT
2. NEW PROJECT
3. SMALL QUESTION / MAINTENANCE TASK

Then:
- route to the correct Obsidian folder/page,
- route to the correct git worktree,
- read the existing context,
- execute the task,
- update Obsidian with a session note + handoff,
- record commit information if a commit is created.

You must preserve continuity for future agents.

## LOCAL OPERATING CONTEXT

Assume the workspace is an autonomous crypto/options trading platform with strong emphasis on:
- Spec-Driven Development
- fail-closed behavior
- auditability
- risk controls
- contract-first implementation
- clean handoffs between agents

Typical work domains include:
- contract / spec remediation
- PRD ↔ contract alignment
- risk engine behavior
- execution engine behavior
- Deribit adapter behavior
- options strategy research / backtesting
- telemetry / snapshots / truth capsules / decision logs
- infra / deployment / ops
- Obsidian workflow / agent orchestration / prompts

## SESSION INTAKE PROTOCOL

At the start of every session, do the following in order.

### Step 1 — classify the request
Classify the user request into exactly one lane:

#### A. EXISTING PROJECT
Use this when:
- the task clearly continues prior work,
- there is an existing project page,
- there is already a branch/worktree/handoff, or
- the task belongs to a known stream such as contract remediation, risk engine, execution engine, Deribit adapter, strategy research, infra, or workflow automation.

#### B. NEW PROJECT
Use this when:
- the task is substantial,
- likely multi-step or multi-session,
- deserves a durable project page,
- and does not clearly belong to an existing project.

#### C. SMALL QUESTION / MAINTENANCE TASK
Use this when:
- the task is narrow,
- likely single-session,
- low coordination cost,
- no durable project artifact is needed beyond a lightweight note,
- examples: tiny fix, small clarification, one-file cleanup, minor doc edit, answer-first task, quick review, small prompt tweak.

### Step 2 — produce a routing proposal
Before any implementation, present a routing proposal in compact form:

- `Lane:` existing_project | new_project | maintenance
- `Obsidian target:` exact folder/page you propose
- `Worktree action:` reuse existing | create new
- `Reason:` 1–3 sentences
- `Need confirmation:` yes

Do not implement before the user confirms.

---

## ROUTING RULES

### If EXISTING PROJECT
You must:
1. identify the most relevant existing project page,
2. read that page first,
3. read the latest handoff/session notes if present,
4. reuse the existing worktree if appropriate, otherwise propose a new worktree linked to the same project,
5. summarize the current context before executing.

You must extract from the project page if available:
- project goal
- current status
- active branch/worktree
- open constraints
- last completed step
- next recommended step
- latest handoff
- relevant files/specs/contracts

### If NEW PROJECT
You must:
1. propose a project name,
2. propose the Obsidian page path,
3. propose a worktree/branch name,
4. ask for confirmation,
5. once approved, create the project page with a minimal template,
6. create the worktree,
7. log session start.

### If SMALL QUESTION / MAINTENANCE TASK
You must:
1. route to the maintenance/question area in Obsidian,
2. create a lightweight session note,
3. use a lightweight worktree only if code changes are needed,
4. avoid creating a full project page unless the task expands.

If a maintenance task grows beyond its original scope, stop and explicitly propose converting it into a project.

## WORKTREE RULES

### General
- One meaningful task stream = one worktree.
- Do not mix unrelated changes in one worktree.
- Reuse an existing worktree only if the task clearly belongs to that stream.

### Fail-closed rules
Do not create or switch worktrees silently.
Always tell the user:
- whether you will reuse or create one,
- why, and
- what it will be named.

## READ-BEFORE-WRITE RULE

Before executing, you must read the relevant context artifacts if they exist:

1. project page
2. latest handoff
3. latest session log
4. relevant contract / PRD / implementation plan / story file
5. relevant notes in Obsidian
6. relevant repo files tied to the task

Then produce a short working context summary:
- what this project is,
- what has already been done,
- what remains,
- what this session will do.

Do not begin edits until that summary is grounded.

## EXECUTION RULES FOR THIS CRYPTO TRADING SYSTEM

Because this system is safety-sensitive, optimize for:
- fail-closed behavior over convenience,
- contract alignment over cleverness,
- narrow changes over broad rewrites,
- explicit invariants over implicit assumptions,
- auditability over speed.

When the task touches any of the following, elevate caution:
- live trading permissions
- risk gates
- order placement behavior
- Deribit adapter logic
- margin / exposure logic
- degraded or maintenance states
- WAL / idempotency / replay / truth capsule / snapshot behavior

In these areas:
- explicitly identify the invariant being protected,
- identify what must fail closed,
- identify what evidence should exist after the change.

## OBSIDIAN UPDATE RULES

At the end of the session, update Obsidian before finalizing.

### For project work
Add or update:
1. session log entry
2. progress summary
3. next-step handoff
4. commit reference if commit exists

### For maintenance work
Add:
1. lightweight note with task, result, and any follow-up needed
2. commit reference if commit exists

## REQUIRED SESSION NOTE TEMPLATE

Use this structure for every session note:

### Session
- Date:
- Agent:
- Lane: existing_project | new_project | maintenance
- Obsidian page:
- Worktree:
- Branch:
- Scope of this session:

### Context consumed
- Project page read:
- Handoff read:
- Other docs/specs read:

### Work completed
- Bullet list of concrete changes made

### Files touched
- List of important files changed or reviewed

### Decisions / constraints
- Important decisions made
- Constraints or blockers discovered

### Validation
- Tests run:
- Reviews performed:
- What remains unverified:

### Commit
- Commit created: yes/no
- Commit hash:
- Commit message:

### Handoff for next agent
- Current state:
- Recommended next step:
- Warnings / risks:
- Open questions:

## COMMIT + HANDOFF RULES

If you make a commit, you must record:
- short commit hash
- one-line commit summary
- what changed
- why it changed
- what the next agent should do next

If you do not make a commit, you must still leave:
- current state
- partial work completed
- what remains
- whether the worktree is reusable

Never finish a session without a handoff.

## RESPONSE FORMAT RULES

At session start, after classification but before doing work, output:

### Routing Proposal
- Lane:
- Obsidian target:
- Worktree action:
- Proposed branch/worktree name:
- Why this route is correct:

### Confirmation Required
- Please confirm this routing before I proceed.

After confirmation and context reading, output:

### Working Context
- Project summary:
- Prior state:
- This session goal:
- Main risks/constraints:

At session end, output:

### Session Result
- What was completed:
- Files changed:
- Validation:
- Commit:
- Obsidian updated:
- Handoff left for next agent:

## STRICT DO-NOT RULES

Do not:
- start coding before routing is confirmed,
- invent project context without reading the page/handoff,
- create a new project if an existing one clearly fits,
- bury maintenance work inside the wrong project,
- mix unrelated task streams in one worktree,
- end the session without updating Obsidian,
- end the session without a handoff,
- claim a commit exists if it does not,
- claim validation was done if it was not.

## HEURISTICS FOR THIS SPECIFIC SYSTEM

Use these routing defaults unless evidence says otherwise:

### Route to EXISTING PROJECT if task mentions:
- contract section, clause, AT, invariant
- phase, story, implementation plan
- PR review or remediation
- Deribit adapter
- risk gate / execution gate / slippage / liquidity / exposure
- a known branch, PR, worktree, or project name
- “continue”, “resume”, “fix this”, “review this”, “phase 0/1”, “upgrade”, “slice”

### Route to NEW PROJECT if task:
- introduces a new subsystem,
- needs a new workflow/skill,
- defines a new research track,
- adds a new durable automation stream.

### Route to MAINTENANCE if task is:
- a quick question,
- a one-off clarification,
- a tiny doc touch,
- a small cleanup,
- a narrow answer-first task with minimal continuity needs.

## FINAL STANDARD

Your output must make it easy for another agent to answer these questions instantly:
- What project is this?
- Where does it live in Obsidian?
- Which worktree is active?
- What was just done?
- What commit contains it?
- What should happen next?

If those answers are not obvious, the session is not complete.

## Purpose
Route each session from the user’s first request into the correct project context, switch/create the correct worktree, load handoff history, and force update of Obsidian logs before commit.

## Session bootstrap (auto-run target)

At every new agent session, this skill should be the first workflow step before any project edits.

```bash
# 1) Read all active projects and project status
ls obsidian/Projects
rg -n "^worktree:|^## Current State|^## Handoffs|^## Log|\\[\\[.*handoff|branch:|pr:" obsidian/Projects/*.md

# 2) Confirm Obsidian-required docs are present
test -f AGENTS.md && rg -n "Obsidian Project Tracking|workflow|Router" AGENTS.md
test -f obsidian/Active\\ Projects.md && sed -n '1,200p' obsidian/Active\\ Projects.md

# 3) Confirm required hooks are available
chmod +x .claude/hooks/obsidian-context-hook.sh .claude/hooks/obsidian-precommit-hook.sh .githooks/pre-push 2>/dev/null || true
```

If this bootstrap checklist has not been done in the current session, stop and run it before reading user code changes.

## When to use
- Starting/continuing any agent session that touches project work
- Ambiguous first-message routing between existing projects, maintenance, or new work
- Multi-worktree routing decisions
- You need to ensure handoff continuity across agents

## When not to use
- Purely local shell/repo maintenance with no Obsidian project linkage
- Non-persistent, ephemeral tasks unrelated to tracked projects

## One-time startup preflight

1. Read project registry and constraints:

```bash
ls obsidian/Projects
rg -n "^worktree:|^## Current State|^## Log|\\[\\[.*Handoff|branch:|pr:" obsidian/Projects/*.md
```

2. Read routing docs referenced by AGENTS:
- `AGENTS.md` section about Obsidian workflow
- `obsidian-workflow.md` if present

3. If repo hooks exist, confirm they are configured:

```bash
chmod +x .claude/hooks/obsidian-context-hook.sh .claude/hooks/obsidian-precommit-hook.sh .githooks/pre-push 2>/dev/null || true
```

## Step 1 — First-message triage (must run first)

Use this decision path on the first user message after session start:

1. **Classify intent**:
   - *General question / tiny note / non-implementation request* → treat as maintenance/housekeeping.
   - *Task with concrete change verb* (implement/fix/add/refactor/investigate/ship) → treat as implementation.
   - *Contains explicit project name or strong tokens* → attempt project match.

2. **Match against `obsidian/Projects/*.md`**:
   - If one strong match: proceed to that project.
   - If multiple matches: ask the user to pick one.
   - If no match:
     - ask user whether this is (a) maintenance question or (b) a new project.
     - do **not** create a new worktree until user confirms.

3. **Fallback routing**:
   - If maintenance question + small scope, note in the maintenance/fallback project file.
   - If uncertain after one pass, do not proceed with project creation yet.

## Step 2 — Select project + worktree

For an existing project:

1. Open the project note:

```bash
sed -n '1,220p' "obsidian/Projects/<Project Name>.md"
```

2. Read:
   - current state
   - key files
   - roadmap/plan
   - branch + PR metadata
   - `## Handoffs` links

3. Determine worktree:
   - Use `worktree` frontmatter value if present.
   - Check path exists (`ls -d .worktrees/<name>`).
   - If missing, ask user before creating/recreating.

For a new project:

1. Ask for approval before creation.
2. Copy template and create the project note:

```bash
cp obsidian/Templates/Project.md "obsidian/Projects/<Project Name>.md"
```

3. Add required frontmatter fields: `status`, `priority`, `branch`, `pr`, `worktree`, and seed `## Log`.
4. Create/switch worktree according to hook/project policy and confirm with the user.

## Step 3 — Load execution context

Use this deterministic handoff helper first:

```bash
get_latest_project_handoff() {
  local project_file="$1"
  local note
  note="$(sed -n '/^## Handoffs/,/^## /p' "$project_file" 2>/dev/null \
    | awk '/- \\[\\[/{print $0}' \
    | tail -n 1 \
    | sed -E 's/.*\\[\\[(.+)\\]\\].*/\\1/')"
  if [ -z "$note" ]; then
    echo "No handoff links in $project_file"
    return 1
  fi
  if [ -f "obsidian/Debriefs/${note}.md" ]; then
    echo "obsidian/Debriefs/${note}.md"
  elif [ -f "obsidian/Projects/${note}.md" ]; then
    echo "obsidian/Projects/${note}.md"
  else
    echo "Could not resolve handoff file path for: $note"
    return 1
  fi
}
```

```bash
# Read latest handoff target from a project
LATEST_HANDOFF=$(get_latest_project_handoff "obsidian/Projects/<Project Name>.md")
printf '%s\n' "$LATEST_HANDOFF"
test -f "$LATEST_HANDOFF" && sed -n '1,220p' "$LATEST_HANDOFF"
```

Before editing code:

1. Read the current handoff log from the project’s handoff target(s) and latest project log entries.
2. If a project handoff exists, read the latest handoff file first.
3. Summarize "what was attempted, what is blocked, and exact next action" to the user.
4. Confirm scope assumptions before touching files.

### Handoff/Scope guard reminder

Before editing or committing beyond tiny docs, enforce:

```bash
git status --short
rg -n "^## Handoffs|^## Log|worktree:|branch:|pr:" "obsidian/Projects/<Project Name>.md"
```

- If the worktree is marked dirty and you are about to run merge/rebase/cherry-pick, abort and ask the user to decide.
- If unresolved files exist, pause and ask for cleanup before continuing with a cross-scope PR.

## Step 4 — During execution

- Keep changes inside the active project scope unless the user explicitly expands scope.
- If pre-push scope guard is enabled, do not mix unrelated files in the same branch.
- If a risky operation is needed (rebase/merge/cherry-pick), stop and verify WIP constraints.

## Step 5 — Commit-time Obsidian update (mandatory)

Before every commit (and as part of commit prep):

1. Update the active project file:
   - add dated entry to `## Log`
   - include commit intent/summary and changed paths
   - update `Current State` when state shifted
   - update `status` / `branch` / `pr` if changed

2. Add a handoff note for the next agent:
   - identify what changed
   - include blockers / risks / unfinished tasks
   - include exact next command or file to continue

3. Ensure project file is staged (required by pre-commit policy).
4. Include the latest commit hash in the handoff section or new debrief note.

## Step 6 — Finish-session handoff

At session handoff boundaries:
- create or update a concise handoff note in the project `## Handoffs` area
- include:
  - what worked
  - what did not work
  - latest commit hash
  - exact next step
  - branch/PR status

## Required communication pattern

At start and end of a routed session, report:
- selected/created project
- chosen worktree path
- handoff file consulted/updated
- commit hash + one-line summary

## Guardrails for quality

- Do not auto-delete active project worktrees after PRs.
- Ask before switching worktrees for the user.
- Never commit generated or local-only mirror artifacts without explicit approval.
- If unclear intent remains, ask one clarifying question and proceed only after confirmation.
- Keep commit payload aligned with scope marker `scope_paths` in `.tmp/obsidian-context-router/scope/*.json` when PR-scope guard is expected.
