# SKILL: /integrator (Parallel Agent Integration Protocol)

Purpose
- Orchestrate parallel agent work across Git worktrees with one integration lane.
- Run as a persistent poll loop in its own terminal, detecting touch list proposals and completed agents.
- Review and approve touch lists before agents start coding.
- Land finished agent work onto the integration branch via cherry-pick (default), merge, or squash.
- Own all cleanup: worktree deletion, branch deletion, handoff archival.
- Keep agents undisturbed unless main moved inside their touch surface.

When to use
- Starting a parallel work session (preflight + poll loop)
- Reviewing touch list proposals from new agents
- Landing a finished agent's work onto the integration branch
- Deciding whether active agents need to rebase after a landing
- Resolving touch-list violations or shared-file conflicts

Root cause this addresses
- Uncoordinated parallel agents create merge hell, not parallelism.
- The bottleneck is integration quality, not agent count.
- Without touch lists, task decomposition is fiction.
- Agents that self-merge, self-cleanup, or dump artifacts in the repo create chaos.

---

## How It Works

1. You start the **integrator** in one terminal. It runs a persistent poll loop.
2. You open another terminal and tell an agent: "You are an agent. Use the parallel-worker skill. Here is your task."
3. The agent **creates its own worktree**, **proposes a touch list**, and **waits for approval**.
4. You (or the integrator) approve the touch list. The agent implements, commits, writes handoff, stops.
5. The integrator detects the handoff, reviews, lands, cleans up.
6. Repeat for up to 10 agents.

---

## Ownership Boundaries

| Action | Worker | Integrator |
|---|---|---|
| Create worktree | Yes (self-setup) | Yes (can also pre-create) |
| Propose touch list | Yes (before coding) | - |
| Approve touch list | - | User or integrator |
| Work on branch | Yes | - |
| Commit | Yes | - |
| Push agent branch | Optional | Optional |
| Write handoff | Yes (outside repo) | - |
| Review handoff | - | Yes |
| Land onto main | - | Yes |
| Push main | - | Yes |
| Open PR | - | Yes (PR mode) |
| Delete worktree | - | Yes |
| Delete agent branch | - | Yes |
| Rebase worker | - | Yes (notifies) |

## Operating Modes

| Mode | When | After landing |
|---|---|---|
| Direct push | Solo dev, trusted agents | Push `main` directly |
| PR mode | Team repo, CI required | Push staging branch, open PR, wait for CI |

Default to direct push for this repo.

---

## Part 1: Preflight (One-Time Setup)

```bash
git config --global rerere.enabled true
cd /Users/admin/Desktop/opus-trader
git checkout main
git pull --ff-only
mkdir -p ../wt
mkdir -p ~/agent-handoffs/opus-trader
mkdir -p ~/agent-handoffs/opus-trader/done
```

- Worktrees go in `../wt/` (outside the repo, avoids .gitignore noise).
- Handoffs go in `~/agent-handoffs/opus-trader/` (outside the repo, keeps worktrees clean).
- Archived handoffs go in `done/`. Failed handoffs go in `failed/`.

---

## Part 2: Poll Loop (Integrator Runs Continuously)

The integrator runs in its own terminal tab. It polls for two things:
1. **Touch list proposals** from new agents (waiting for approval)
2. **Handoff files** from finished agents (ready for landing)

### Detection
- Touch list proposal: `~/agent-handoffs/opus-trader/{AGENT_ID}_touch_list.md` exists
- Completed handoff: `~/agent-handoffs/opus-trader/{AGENT_ID}.md` exists

The handoff file is the "I'm done" semaphore. A new commit alone is not sufficient.

### Loop
```
repeat:
    # Check for new touch list proposals
    for each *_touch_list.md in ~/agent-handoffs/opus-trader/:
        if not yet reviewed:
            → review touch list proposal (Part 3)

    # Check for completed handoffs
    for each agent worktree that still exists:
        if ~/agent-handoffs/opus-trader/{AGENT_ID}.md exists:
            → enter review-land-cleanup cycle (Part 4)

    sleep 60

    if no worktrees remain and no pending proposals:
        → all agents landed, exit loop
```

Between polls, the integrator also handles:
- Worker requests for files outside touch lists → pause, decide, respond
- Dependency availability → notify blocked worker
- Failed landing triage → human attention

---

## Part 3: Touch List Review

When a new agent starts, it creates its own worktree and writes a touch list proposal to `~/agent-handoffs/opus-trader/{AGENT_ID}_touch_list.md`.

The integrator reviews the proposal:

1. **Read the proposal** — check allowed files, forbidden files, acceptance criteria, dependency notes
2. **Check for overlap** with already-approved touch lists from active agents:
   ```bash
   comm -12 <(sort new_agent_touch.txt) <(sort active_agent_touch.txt)
   # Non-empty = overlap. Decide: reassign files, sequence, or reject.
   ```
3. **Check hotspot files** — if the proposal touches known hotspot files (`specs/CONTRACT.md`, `plans/prd.json`, `crates/soldier_core/src/execution/mod.rs`), verify no other agent owns them
4. **Approve, modify, or reject:**
   - Approve: tell the agent to proceed
   - Modify: tell the agent which files to add/remove, then approve
   - Reject: tell the agent the task can't proceed (dependency, overlap, scope issue)

The agent is blocked until the touch list is approved. It will not write code until it hears back.

---

## Part 4: Review-Land-Cleanup Cycle

Run for each READY agent (handoff file exists), one at a time.

### 4.1 Review Handoff

Read `~/agent-handoffs/opus-trader/{AGENT_ID}.md`. A complete handoff includes:
- summary
- files changed
- tests run + results
- risks/open questions
- final commit SHA
- suggested landing order if dependent on another task

Reject incomplete handoffs — do not proceed.

### 4.2 Verify Clean State

```bash
git -C ../wt/{AGENT_DIR} status --porcelain
# Must be empty. If not, reject.
```

### 4.3 Verify Touch List Compliance

```bash
cd ../wt/{AGENT_DIR}
git diff main --name-only | sort > /tmp/actual.txt
comm -23 /tmp/actual.txt <(sort ~/agent-handoffs/opus-trader/{AGENT_ID}_touch_list.txt)
# Non-empty output = touch list violation. Investigate before landing.
```

### 4.4 Review Diff

Inspect the actual changes. Check for:
- correctness relative to the task objective
- no `unwrap()` in production paths
- no silent error swallowing
- fail-closed on uncertain paths
- no scope creep beyond the touch list

### 4.5 Check Dependency Order

If the handoff says "land after Agent X," verify Agent X has already landed. If not, skip this agent for now and process it in a later poll cycle.

### 4.6 Land

```bash
cd /Users/admin/Desktop/opus-trader
git checkout main
git pull --ff-only
```

| Agent commits | History value | Strategy |
|---|---|---|
| 1 clean commit | N/A | `git cherry-pick <SHA>` |
| Multiple, clean | Worth preserving | `git merge --no-ff agent/{AGENT_ID}` |
| Multiple, messy | Not worth preserving | `git merge --squash agent/{AGENT_ID}` |

When no explicit dependencies exist, land the smallest-diff agent first.

If cherry-pick conflicts: use `/git` skill Part 2 (merge conflict resolution). Do NOT blindly `--theirs`.

### 4.7 Test

```bash
cargo test
./plans/verify.sh quick
```

### 4.8 Handle Result

**If tests pass:**

```bash
# Direct push mode:
git push origin main

# PR mode:
git push origin main:staging/batch-{N}
gh pr create --base main --head staging/batch-{N} \
  --title "Land agent/{AGENT_ID}" \
  --body "$(cat ~/agent-handoffs/opus-trader/{AGENT_ID}.md)"
```

Proceed to cleanup.

**If tests fail:**

```bash
git reset --hard HEAD~1     # for cherry-pick
# or
git reset --hard ORIG_HEAD  # for merge
```

Quarantine the handoff:

```bash
mkdir -p ~/agent-handoffs/opus-trader/failed
mv ~/agent-handoffs/opus-trader/{AGENT_ID}.md ~/agent-handoffs/opus-trader/failed/
```

Leave worktree intact. Flag for human attention. Do not auto-retry.

### 4.9 Cleanup (Integrator Owns This)

The worker never deletes its own worktree or branch.

```bash
# Remove worktree
git worktree remove ../wt/{AGENT_DIR}

# Delete agent branch locally
git branch -d agent/{AGENT_ID}

# Delete agent branch remotely (if pushed)
git push origin --delete agent/{AGENT_ID} 2>/dev/null || true

# Archive handoff and touch list
mv ~/agent-handoffs/opus-trader/{AGENT_ID}.md ~/agent-handoffs/opus-trader/done/
mv ~/agent-handoffs/opus-trader/{AGENT_ID}_touch_list.md ~/agent-handoffs/opus-trader/done/ 2>/dev/null || true
```

### 4.10 Check Overlap with Active Workers

```bash
LANDED=$(git diff HEAD~1 --name-only | sort)
for wt in ../wt/*/; do
    [ -d "$wt/.git" ] || continue
    AGENT_TOUCH=$(git -C "$wt" diff main --name-only | sort)
    OVERLAP=$(comm -12 <(echo "$LANDED") <(echo "$AGENT_TOUCH"))
    if [ -n "$OVERLAP" ]; then
        echo "REBASE NEEDED: $(basename "$wt") overlaps:"
        echo "$OVERLAP"
    else
        echo "OK: $(basename "$wt") — no overlap"
    fi
done
```

Do NOT force every agent to rebase after every landing. Rebase only when main moved inside their touch surface.

---

## Part 5: Scaling Rules

### Start Small

| Phase | Agents | Integrator |
|---|---|---|
| First cycle | 2-3 | You (manual) |
| Proven clean | 4-5 | You or dedicated agent |
| High confidence | 6+ | Dedicated integrator agent |

### When to Stop Scaling

- Integration queue backs up (agents finishing faster than you can land)
- Conflict rate exceeds 1 per 3 landings
- Touch lists start overlapping despite decomposition
- Agents need context from each other's uncommitted work

### Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| 10 agents, day 1 | Integration queue explodes |
| Agents merging to main | Race condition disguised as workflow |
| No touch lists | Multiple agents freelancing in same files |
| Agents rebasing constantly | Churn without value |
| Two worktrees on same branch | Git blocks this; if you work around it, data loss |
| Agent pushes to main | Bypasses integration verification |
| Hotspot file with no owner | Guaranteed conflicts |
| Symmetric edits to shared file | Sequence it instead |
| Agents dumping artifacts in the repo | Dirty worktrees, verification gate failures |
| Agents deleting their own worktrees | Destroys rollback path before landing is verified |

---

## Part 6: Completion

When all worktrees are removed and all handoffs are archived:

```bash
git worktree list          # should show only main repo
git worktree prune
git fetch --prune
cargo test
./plans/verify.sh full
ls ~/agent-handoffs/opus-trader/done/
ls ~/agent-handoffs/opus-trader/failed/ 2>/dev/null
```

---

## Part 7: Checklists

### Preflight Checklist

- [ ] Integration branch is clean and current (`git pull --ff-only`)
- [ ] rerere enabled (`git config rerere.enabled` returns `true`)
- [ ] Worktree root exists (`../wt/`)
- [ ] Handoff directories exist (`~/agent-handoffs/opus-trader/`, `done/`)

### Touch List Review Checklist

- [ ] Proposal file exists and is complete
- [ ] Allowed files are reasonable for the task scope
- [ ] No overlap with active agents' approved touch lists
- [ ] No hotspot files without ownership
- [ ] Forbidden files include known shared files
- [ ] Acceptance criteria and tests are specified

### Per-Agent Landing Checklist

- [ ] Handoff file exists and is complete
- [ ] Worker worktree is clean (`git status --porcelain` empty)
- [ ] Files changed match approved touch list (no violations)
- [ ] Dependency order satisfied
- [ ] Diff reviewed
- [ ] Cherry-pick (or merge/squash) applied
- [ ] `cargo test` passes
- [ ] `./plans/verify.sh quick` passes
- [ ] Overlap detection run against active agents
- [ ] Affected agents notified to rebase (if any)
- [ ] Integration branch pushed
- [ ] Worktree removed
- [ ] Agent branch deleted
- [ ] Handoff + touch list archived to `done/`

### Post-Completion Checklist

- [ ] All agents landed
- [ ] All worktrees removed
- [ ] All agent branches deleted (local + remote)
- [ ] `git worktree prune` run
- [ ] `./plans/verify.sh full` passes on final integrated state
- [ ] All handoffs in `done/` (or `failed/` with triage notes)

---

## Output

When invoking this skill, report:
- Current worktree layout (`git worktree list`)
- Active agents and their status (proposing / working / ready / landed / failed)
- Pending touch list proposals
- Touch list overlap matrix
- Landing queue (which agent to land next)
- Sync notifications (which agents need rebase)
- Integration branch state (clean / dirty / ahead of remote)
- Handoff directory contents (pending / done / failed)
