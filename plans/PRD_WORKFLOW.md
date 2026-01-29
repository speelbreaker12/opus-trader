# PRD Workflow — Ralph Loop Enforcement

## CRITICAL: Pending PRD Stories Are Ralph-Only

**Pending stories (`passes=false`) in `plans/prd.json` MUST be implemented via the Ralph harness.**

Manual implementation of pending PRD stories is **FORBIDDEN** because it bypasses critical safety guardrails.

**Exception:** Post-implementation fixes to stories with `passes=true` are allowed manually (still requires verify.sh green).

## Why Ralph Is Mandatory

Ralph enforces the workflow contract ([WF-2.x] in `specs/WORKFLOW_CONTRACT.md`):

| Guardrail | What It Prevents |
|-----------|------------------|
| **WIP=1** | Parallel work that creates merge conflicts and context dilution |
| **Contract alignment review** | Changes that violate `specs/CONTRACT.md` |
| **Scope gating** | Out-of-scope edits that bloat commits |
| **Verification gates** | Broken tests, lint failures, schema violations |
| **Audit trail** | Lost context about what was done and why |
| **Circuit breaker** | Repeated failures that waste tokens/time |
| **Cheat detection** | Test deletions or weakening of fail-closed gates |

## How to Implement PRD Stories

### Step 1: Verify Baseline
```bash
# Ensure repo is in good state
./plans/init.sh
./plans/verify.sh full
```

### Step 2: Run Ralph
```bash
# Thorough mode (recommended for production)
RPH_PROFILE=thorough ./plans/ralph.sh 10

# Fast mode (for exploration)
RPH_PROFILE=fast ./plans/ralph.sh 5

# See SKILLS/ralph-loop.md for all options
```

### Step 3: Monitor Progress
```bash
# Watch progress
tail -f plans/progress.txt

# Check state
cat .ralph/state.json | jq .
```

### Step 4: Review Results
```bash
# Check which stories passed
cat plans/prd.json | jq '.items[] | select(.passes==true) | .id'

# Review commits
git log --oneline -10
```

## What Agents Can Do Without Ralph

**Allowed (read-only):**
- Review PRD structure: `cat plans/prd.json | jq '.items[] | select(.id=="S2-001")'`
- Check story status: `jq '.items[] | select(.passes==false) | .id' plans/prd.json`
- Analyze scope: Review `scope.touch` and `scope.create` fields
- Explain stories: Interpret `description`, `acceptance`, `contract_refs`

**Allowed (post-implementation fixes):**
- Fix bugs in stories with `passes=true` (already implemented by Ralph)
- Improve/refactor code from completed stories
- Add missing error handling or edge cases
- Still requires: `./plans/verify.sh` must pass before commit

**How to check if fix is allowed:**
```bash
# Check if story already passed
jq '.items[] | select(.id=="S2-001") | .passes' plans/prd.json

# If output is "true" → manual fix allowed
# If output is "false" → must use Ralph
```

**Forbidden (pending story implementation):**
- Manually implementing story code changes for `passes=false` stories
- Editing files in `scope.touch` to fulfill a pending PRD story
- Creating files in `scope.create` for a pending PRD story
- Marking `passes=true` without Ralph (only Ralph flips pass via `plans/update_task.sh`)

## Quick Decision Flowchart

```
User asks to work on code related to PRD
                 ↓
       Is it a specific PRD story ID?
                 ↓
        ┌────────┴────────┐
       NO                YES
        ↓                 ↓
  Check if code     Check story status:
  was from a        jq '.items[] |
  PRD story         select(.id=="Sx-yyy") |
        ↓            .passes' plans/prd.json
        ↓                 ↓
   Non-PRD work    ┌──────┴──────┐
   → ALLOW         │             │
   (still need  "false"       "true"
    verify.sh)     │             │
                   ↓             ↓
              BLOCK          ALLOW
              Output:        (post-impl fix)
              BLOCKED_PRD_   (still need
              REQUIRES_      verify.sh)
              RALPH
```

## Agent Blocking Protocol

If an agent is asked to work on a PRD story:

1. **Detect**: User says "implement S2-001" or "work on this PRD story"
2. **Check status**: Run `jq '.items[] | select(.id=="S2-001") | .passes' plans/prd.json`
3. **Decision**:
   - If `passes=false` (pending) → **BLOCK**
     - Output: `<promise>BLOCKED_PRD_REQUIRES_RALPH</promise>`
     - Guide: "S2-001 is pending (`passes=false`). Pending PRD stories must be implemented via Ralph harness. Run: `./plans/ralph.sh`"
   - If `passes=true` (already implemented) → **ALLOW**
     - "S2-001 was already implemented. I can help fix or improve it. What needs to be corrected?"
     - Still requires: `./plans/verify.sh` must pass before commit
4. **Offer**: "I can help you run Ralph, review the PRD structure, analyze scope, or fix already-implemented stories."

## Exception: Non-PRD Work

Agents CAN manually implement work that is NOT in PRD:

- **Workflow maintenance**: Changes to `plans/ralph.sh`, `plans/verify.sh`, etc. (governed by [WF-11] Change Control)
- **Bug fixes**: Critical fixes not planned in PRD
- **Documentation**: Updates to `docs/`, `specs/` (if not part of a PRD story)
- **Ad-hoc tasks**: One-off work requested by user outside PRD workflow

**How to distinguish:**
- If it has an `id` like `S0-001`, `S2-003` in `plans/prd.json` → Ralph-only
- If it's not in PRD → Manual implementation allowed (still requires verify.sh green)

## Workflow Contract Alignment

This enforcement implements:
- [WF-2.3] WIP=1 (Ralph execution only)
- [WF-2.2] Verification is mandatory
- [WF-2.1] Contract alignment is mandatory
- [WF-2.4] Slices are executed in order
- [WF-2.5] No cheating

See `specs/WORKFLOW_CONTRACT.md` for full contract.

## References

- **Ralph harness**: `plans/ralph.sh`
- **Workflow contract**: `specs/WORKFLOW_CONTRACT.md`
- **Ralph skill guide**: `SKILLS/ralph-loop.md`
- **Agent instructions**: `AGENTS.md` (section "Ralph loop discipline")
- **Project guide**: `CLAUDE.md` (section "PRD Story Implementation")
