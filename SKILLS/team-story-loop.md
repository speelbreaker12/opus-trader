# SKILL: /team-story-loop (Team-Based PRD Story Loop)

## Purpose

Execute the PRD story implementation workflow using a coordinated team of 4 agents. Parallelizes independent review steps and automates Copilot aftercare.

## When to Use

- Implementing a PRD story that needs the full story loop (13+ steps)
- When you want automated Copilot aftercare instead of manual fix-push-ack cycles
- When you want parallel reviews (self-review + verify, Codex + Kimi, Codex #2 + CRE)

## Prerequisites

- [ ] Story ID identified (e.g., `S5-004`)
- [ ] Integration branch exists and is clean (e.g., `run/slice1-clean`)
- [ ] `plans/prd.json` has the story with `passes: false`
- [ ] `gh` CLI authenticated
- [ ] `codex` and `kimi` CLIs available (or review steps will be skipped)

## Team Design

| Agent | Type | Role | Active During |
|-------|------|------|---------------|
| `team-lead` | general-purpose | Orchestrator + implementer | Entire workflow |
| `reviewer` | general-purpose | All reviews: self, Codex, Kimi, CRE | Tasks 3, 5, 8 |
| `copilot-watcher` | general-purpose | Polls PR for bot comments, fixes, acks | Task 15 only |
| `guardian` | general-purpose | Validates artifacts at checkpoints | Entire workflow (background) |

**WIP=1 preserved**: All agents work on the **same story**. No concurrent stories.

## Workflow

### Phase 0: Team Setup

```
1. TeamCreate: name="story-{STORY_ID}", description="Story loop for {STORY_ID}"
2. Create all 16 tasks (see Task List below)
3. Set up task dependencies (blockedBy chains)
4. Spawn guardian agent (background, entire workflow)
5. Claim task 1 as team-lead
```

### Phase 1: Implementation (Tasks 1-2)

**Team-lead only.**

```
Task 1: Create worktree and story branch
  git worktree add /Users/admin/Desktop/wt_{STORY_ID} -b story/{STORY_ID}/{slug} {INTEGRATION_BRANCH}
  cd /Users/admin/Desktop/wt_{STORY_ID}

Task 2: Implement the story
  - Read PRD item from plans/prd.json
  - Read relevant CONTRACT.md sections
  - Write code, tests
  - Commit
  → Message guardian: "Task 2 done. Check compilation."
```

### Phase 2: First Review Round (Tasks 3-5) — PARALLEL WINDOW 1

**Spawn reviewer. Tasks 3 + 4 run simultaneously.**

```
Task 3 [reviewer]: Write self-review artifacts
  - Run /pr-review and /failure-mode-review skills
  - Save to artifacts/story/{ID}/self_review/
  - Run self_review_logged.sh

Task 4 [team-lead]: Run verify.sh quick
  - ./plans/verify.sh quick
  - Capture VERIFY_RUN_ID
  → Message guardian: "Task 4 done. Run ID: {RUN_ID}"

Task 5 [reviewer]: Run Codex #1 + Kimi (parallel within reviewer)
  - codex_review_logged.sh (blocked by task 4)
  - kimi_review_logged.sh (blocked by task 4)
  → Report findings to team-lead
```

### Phase 3: Fix and Re-verify (Tasks 6-7)

**Team-lead only.**

```
Task 6 [team-lead]: Triage and fix findings
  - Read reviewer's report (from tasks 3 + 5)
  - Fix BLOCKING and MAJOR findings
  - Commit fixes

Task 7 [team-lead]: Run verify.sh quick
  → Message guardian: "Task 7 done. Run ID: {RUN_ID}"
```

### Phase 4: Second Review Round (Task 8) — PARALLEL WINDOW 2

**Reviewer runs both at once.**

```
Task 8 [reviewer]: Run Codex #2 + code-review-expert (parallel)
  - codex_review_logged.sh (Codex review #2)
  - code_review_expert_logged.sh (CRE review)
  → Report findings to team-lead
  → Team-lead sends shutdown_request to reviewer after task 9
```

### Phase 5: Final Fix and Verify (Tasks 9-12)

**Team-lead only.**

```
Task 9 [team-lead]: Fix remaining findings

Task 10 [team-lead]: Run verify.sh quick
  → Message guardian: "Task 10 done. Run ID: {RUN_ID}"

Task 11 [team-lead]: Sync with integration branch
  git fetch origin
  git rebase {INTEGRATION_BRANCH}
  (resolve conflicts if any)

Task 12 [team-lead]: Run verify.sh full + contract review
  ./plans/verify.sh full
  - Create contract_review.json with "decision": "PASS"
  → Message guardian: "Task 12 done. Run ID: {RUN_ID}"
```

### Phase 6: Pass and PR (Tasks 13-14)

```
Task 13 [team-lead]: Run prd_set_pass.sh
  ./plans/prd_set_pass.sh {STORY_ID} true

Task 14 [team-lead]: Commit PRD pass and create PR
  git add plans/prd.json
  git commit -m "{STORY_ID}: mark pass"
  git push -u origin story/{STORY_ID}/{slug}
  gh pr create --base {INTEGRATION_BRANCH} --title "story/{STORY_ID}: {title}" --body "..."
  → Message guardian: "PR created. Check task 14."
```

### Phase 7: Copilot Aftercare (Task 15) — PARALLEL WINDOW 3

**Spawn copilot-watcher.**

```
Task 15 [copilot-watcher]: Copilot aftercare loop
  - Poll PR for bot comments
  - Fix unresolved inline comments
  - verify.sh quick after fixes
  - Push, post AFTERCARE_ACK
  - Run pr_gate.sh locally to confirm
  → Report to team-lead: success or escalation
```

### Phase 8: Merge and Cleanup (Task 16)

```
Task 16 [team-lead]: Merge PR and cleanup
  - FF-only merge: git checkout {INTEGRATION_BRANCH} && git merge --ff-only story/{STORY_ID}/{slug}
  - git push origin {INTEGRATION_BRANCH}
  - Clean up worktree: git worktree remove /Users/admin/Desktop/wt_{STORY_ID}
  - git branch -d story/{STORY_ID}/{slug}
  → Shutdown copilot-watcher
  → Shutdown guardian
  → TeamDelete
```

## Task List Template (16 Tasks)

Create these with `TaskCreate`. Two parallelism windows marked with `||`:

```
 1. Create worktree and story branch          [team-lead]          blockedBy: []
 2. Implement story                           [team-lead]          blockedBy: [1]
 3. Write self-review artifacts               [reviewer]           blockedBy: [2]       || with 4
 4. Run verify.sh quick                       [team-lead]          blockedBy: [2]       || with 3
 5. Run Codex #1 + Kimi review               [reviewer]           blockedBy: [4]
 6. Triage and fix findings                   [team-lead]          blockedBy: [3, 5]
 7. Run verify.sh quick                       [team-lead]          blockedBy: [6]
 8. Run Codex #2 + code-review-expert         [reviewer]           blockedBy: [7]       || both at once
 9. Fix remaining findings                    [team-lead]          blockedBy: [8]
10. Run verify.sh quick                       [team-lead]          blockedBy: [9]
11. Sync with integration branch              [team-lead]          blockedBy: [10]
12. Run verify.sh full + contract review      [team-lead]          blockedBy: [11]
13. Run prd_set_pass.sh                       [team-lead]          blockedBy: [12]
14. Commit PRD pass and create PR             [team-lead]          blockedBy: [13]
15. Copilot aftercare loop                    [copilot-watcher]    blockedBy: [14]
16. Merge PR and cleanup                      [team-lead]          blockedBy: [15]
```

## Agent Lifecycle

### Spawning

Agents are spawned **lazily** — only when their phase begins:

| Agent | Spawn Trigger | Shutdown Trigger |
|-------|---------------|------------------|
| guardian | Task 1 starts | Task 16 completes |
| reviewer | Task 3 starts | Task 9 starts (after findings received) |
| copilot-watcher | Task 15 starts | Task 16 starts (after gate passes) |

### Spawn Commands

```
# Guardian (background, entire workflow)
Task tool: name="guardian", subagent_type="general-purpose", run_in_background=true
  prompt: "You are the guardian agent for story {STORY_ID}. Repo root: {path}. Monitor checkpoints per .claude/agents/guardian.md."

# Reviewer (tasks 3, 5, 8)
Task tool: name="reviewer", subagent_type="general-purpose", team_name="story-{STORY_ID}"
  prompt: "You are the reviewer for story {STORY_ID}. SHA: {sha}. Integration branch: {branch}. Follow .claude/agents/reviewer.md."

# Copilot-watcher (task 15)
Task tool: name="copilot-watcher", subagent_type="general-purpose", team_name="story-{STORY_ID}"
  prompt: "You are the copilot-watcher for story {STORY_ID}. PR: #{n}. Repo: {owner/repo}. Follow .claude/agents/copilot-watcher.md."
```

### Shutdown

Use `SendMessage` with `type: "shutdown_request"`:
```
SendMessage: type="shutdown_request", recipient="reviewer", content="All reviews complete. Shutting down."
SendMessage: type="shutdown_request", recipient="copilot-watcher", content="Gate passed. Shutting down."
SendMessage: type="shutdown_request", recipient="guardian", content="Workflow complete. Shutting down."
```

## Guardian Checkpoint Gates

The guardian validates artifacts at each phase boundary. These are defense-in-depth — `prd_set_pass.sh` is the final gate, but the guardian catches problems early.

| After Task | Guardian Checks |
|------------|----------------|
| 2 | Workspace compiles (`cargo check --workspace`) |
| 3 | Self-review artifacts exist (3 files) |
| 4 | No FAILED_GATE, all .rc == 0 in verify run |
| 5 | Codex + Kimi review artifacts exist |
| 7 | All .rc == 0 in verify run |
| 8 | 2+ Codex reviews, 1+ CRE review exist |
| 10 | Clean working tree |
| 12 | verify.meta.json mode=full, HEAD matches, contract_review decision=PASS |
| 13 | prd.json shows passes=true for story |
| 14 | PR exists on GitHub |
| 15 | AFTERCARE_ACK posted for HEAD |

**Important**: Each verify creates artifacts under `artifacts/verify/<VERIFY_RUN_ID>/`. Team-lead must send the run ID to guardian after each verify completes.

## Communication Protocol

### Team-lead → Reviewer
```
"Self-review story {ID} at {SHA}. Then run Codex+Kimi after task 4 unblocks."
"Run Codex #2 + code-review-expert for {SHA}."
```

### Reviewer → Team-lead
```
"Self-review done. External reviews done. 2 BLOCKING, 1 MAJOR."
"Second round done. 0 BLOCKING."
```

### Team-lead → Guardian
```
"Task 4 done. Verify run ID: {RUN_ID}. Check checkpoint."
"Task 12 done. Full verify run ID: {RUN_ID}. Check all gates."
```

### Guardian → Team-lead
```
"CHECKPOINT OK: Task {N}. All assertions passed."
"CHECKPOINT FAIL: Task {N}. artifacts/story/{ID}/kimi/ is empty."
```

### Team-lead → Copilot-watcher
```
"PR #{n} for story {ID}. Enter aftercare loop."
```

### Copilot-watcher → Team-lead
```
"Aftercare complete. Gate passes for PR #{n} at SHA {sha}."
"ESCALATE: 5 cycles without gate passing. Remaining: {problems}."
```

## Error Recovery

| Situation | Recovery |
|-----------|----------|
| Reviewer reports CLI missing | Team-lead skips that review, documents in findings |
| Guardian reports checkpoint fail | Team-lead evaluates severity, fixes or documents exception |
| Copilot-watcher escalates | Team-lead manually fixes and re-runs gate |
| Verify fails after sync | Team-lead resolves conflicts, re-runs verify |
| prd_set_pass.sh fails | Check which gate failed (exit codes), fix, retry |

### prd_set_pass.sh Exit Codes
- Exit 1: verify.meta.json missing or wrong mode
- Exit 2: usage error
- Exit 3: HEAD mismatch
- Exit 4: FAILED_GATE or non-zero .rc
- Exit 5: missing self-review, Codex, or Kimi artifacts

## Contract Alignment

This skill implements:
- [WF-2.1] Contract alignment mandatory (task 12 contract review)
- [WF-2.2] Verification mandatory (tasks 4, 7, 10, 12)
- [WF-2.3] WIP=1 enforcement (single story per team)
- [WF-2.4] Slice order enforcement (inherited from prd.json)
- [WF-2.5] No cheating detection (inherited from verify.sh)

See `specs/WORKFLOW_CONTRACT.md` for the full workflow contract.
