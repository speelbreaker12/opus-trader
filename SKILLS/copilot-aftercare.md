# Skill: Copilot Aftercare

**Purpose**: Automate the Copilot review response loop for any PR (simple fixes, non-PRD work).

**Use this after**: PR is created and CI has started (Copilot review triggered).

**DO NOT use this for**: PRD stories (use `/ralph-loop` which includes Tier 3 aftercare).

---

## When to Use

After creating a PR for:
- Bug fixes
- Clippy warning fixes
- Test additions
- Simple refactors
- Documentation updates
- Any non-PRD work

**Timing**: Run this skill immediately after `gh pr create`. The skill will wait for Copilot to review (up to 90 min with progressive warnings).

---

## What This Skill Does

1. Spawns a `copilot-watcher` agent in **Tier 1 mode**
2. Agent polls for Copilot/bot comments on your PR
3. Agent validates and applies suggested fixes
4. Agent regenerates self-review (only review needed for simple work)
5. Agent runs `verify.sh quick` to ensure fixes don't break anything
6. Agent pushes changes and posts `AFTERCARE_ACK` token
7. Agent reports completion or escalates if stuck

**You get**: Hands-off Copilot response automation. No manual fix-push-ack loop.

---

## Prerequisites

- PR must be created: `gh pr create ...` completed successfully
- Branch is pushed to remote: `git push -u origin HEAD`
- Working directory is on the PR branch (not detached HEAD)
- Current branch has upstream tracking: `git rev-parse --abbrev-ref HEAD@{upstream}`

**Note**: Skill will retry PR detection up to 3 times (GitHub API propagation can take a few seconds after PR creation).

---

## Skill Invocation

```
/copilot-aftercare
```

**No parameters needed**. The skill auto-detects:
- Current PR number (via `gh pr view`)
- Repository (via git remote)
- Current branch

---

## What the Agent Will Do

### Step 1: Wait for Copilot Review (Progressive Timeout)
- 0-15 min: Silent wait, polls every 60s
- 15 min: Log "waiting for Copilot review"
- 45 min: Warn you, continue waiting
- 90 min: Escalate (Copilot CI may have failed)

### Step 2: Process Comments
For each Copilot inline comment:
1. **Validate** suggestion (check spec sections, function names, file paths are correct)
2. **Apply** fix (either suggestion block or minimal targeted fix)
3. **Stage** changes

### Step 3: Verify
```bash
./plans/verify.sh quick
```
If verify fails → revert changes, escalate to you.

### Step 4: Regenerate Review
Run `/pr-review` skill to regenerate self-review for new HEAD.

**Why regenerate?** Per `specs/WORKFLOW_CONTRACT.md:136-137`, any HEAD change requires review regeneration (not re-stamping metadata).

Optional: Save review to `artifacts/adhoc/<timestamp>/self_review/` for future reference.

### Step 5: Push + ACK
```bash
git push
gh pr comment <PR_NUMBER> --body "AFTERCARE_ACK: <HEAD_SHA>"
```

### Step 6: Report
Agent sends you a completion message:
```
Copilot aftercare complete (TIER=1).
- Addressed 2 inline comments
- Regenerated reviews (self-review)
- verify.sh quick: PASS
- Final HEAD: abc123def456
- ACK posted for PR #42
```

---

## Escalation Scenarios

Agent will escalate (send you a message and wait for instructions) if:
- **No Copilot review after 90 min**: Copilot CI may have failed, check manually
- **Suggestion validation fails**: Copilot referenced nonexistent spec section or function
- **Fix breaks verify.sh quick**: Applied fix caused test failures
- **5 fix cycles without success**: Keep finding new comments or gate failures
- **GitHub API errors**: Cannot fetch comments or post ACK

**When escalated**: Agent goes idle. You can:
- Manually fix the issue, push, then send agent "retry" message
- Manually complete aftercare and shut down agent
- Debug the root cause

---

## Time Estimate

- **Typical case** (0-2 Copilot comments): 5-10 min (mostly waiting for Copilot to review)
- **Heavy case** (3-5 comments): 10-15 min
- **Escalation case**: Variable (depends on issue complexity)

---

## Artifact Preservation

By default, agent **optionally** saves self-review to `artifacts/adhoc/<timestamp>/self_review/`.

**When to save**:
- Non-trivial fixes (worth preserving for future reference)
- Bugs that required investigation
- Changes with subtle correctness concerns

**When to skip**:
- Trivial typos
- Obvious clippy fixes
- Changes with zero risk

The agent will save if the self-review finds any findings (even minor), otherwise skips to reduce clutter.

---

## Example Usage

### Scenario: Fix Clippy Warnings

```bash
# 1. Make changes
git checkout -b fix/clippy-warnings
# ... edit files ...
git add .
git commit -m "fix: address clippy warnings in risk module"
git push -u origin HEAD

# 2. Create PR
gh pr create \
  --title "fix: address clippy warnings in risk module" \
  --body "Fixed 3 clippy warnings (unnecessary_map_or, type_complexity)"

# 3. Invoke aftercare skill
/copilot-aftercare

# 4. Wait for agent to complete (or escalate)
# ... 5-10 minutes later ...

# 5. Agent reports success
# Copilot aftercare complete (TIER=1).
# - Addressed 1 inline comment (suggested simplifying .map_or to .is_some_and)
# - Regenerated reviews (self-review)
# - verify.sh quick: PASS
# - Final HEAD: abc123def456
# - ACK posted for PR #42

# 6. Merge PR
gh pr merge --squash --delete-branch
```

---

## Difference from Tier 2/3 Aftercare

| Feature | Tier 1 (this skill) | Tier 2 | Tier 3 (PRD) |
|---------|---------------------|--------|--------------|
| **Reviews regenerated** | Self-review only | Self + Codex | Self + Codex×2 |
| **Verify level** | quick | full | full |
| **Gate check** | None | None | prd_set_pass.sh |
| **Artifact commit** | Standard | Standard | Artifact-only protocol |
| **Artifacts required** | Optional | Optional | Mandatory |
| **Use case** | Simple fixes | Complex features | PRD stories |

---

## Skill Implementation

This skill:

### 1. Validate Branch State

```bash
# Check not on detached HEAD
CURRENT_BRANCH=$(git branch --show-current)
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "ERROR: Not on a branch (detached HEAD)."
  echo "Checkout a branch first: git checkout -b <branch-name>"
  exit 1
fi

# Check branch has upstream tracking
if ! git rev-parse --abbrev-ref HEAD@{upstream} >/dev/null 2>&1; then
  echo "ERROR: Current branch has no upstream."
  echo "Push first: git push -u origin HEAD"
  exit 1
fi
```

### 2. Detect PR Number (with Retry)

```bash
# Retry up to 3 times (GitHub API propagation lag)
for attempt in {1..3}; do
  PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null)

  if [[ -n "$PR_NUMBER" ]]; then
    echo "Detected PR #${PR_NUMBER}"
    break
  fi

  echo "Waiting for PR to appear in GitHub API (attempt $attempt/3)..."
  sleep 2
done

if [[ -z "$PR_NUMBER" ]]; then
  echo "ERROR: No PR found for current branch after 3 attempts."
  echo "Ensure:"
  echo "  1. PR was created: gh pr create"
  echo "  2. Branch is pushed: git push -u origin HEAD"
  echo "  3. GitHub API has propagated (wait 10s and retry)"
  exit 1
fi
```

### 3. Detect Repository

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

if [[ -z "$REPO" ]]; then
  echo "ERROR: Could not detect repository."
  echo "Ensure you're in a git repository with GitHub remote."
  exit 1
fi

echo "Repository: $REPO"
```

### 4. Spawn Copilot-Watcher Agent

```bash
# Build spawn prompt with all required parameters
SPAWN_PROMPT="PR_NUMBER=${PR_NUMBER} REPO=${REPO} TIER=1. Run aftercare loop for PR #${PR_NUMBER}."

# Use Task tool to spawn agent
Task(
  subagent_type="copilot-watcher",
  prompt="$SPAWN_PROMPT",
  description="Copilot aftercare (Tier 1)",
  model="sonnet"  # Fast, sufficient for simple fixes
)
```

### 5. Wait and Report

Wait for agent completion or escalation, then report result to user.

---

## Integration with Other Skills

- **Complements `/simple-fix-loop`**: The simple fix loop skill calls this skill at task 5
- **Used by `/complex-feature-loop`**: The complex feature loop calls copilot-watcher in Tier 2 mode (not this skill, uses Task directly)
- **NOT used by `/ralph-loop`**: PRD workflow uses Tier 3 copilot-watcher (different configuration)

---

## Notes

- **Safe to re-invoke**: If agent gets stuck, you can safely invoke this skill again (it will re-check comments, skip already-resolved)
- **Idempotent**: Multiple ACK posts for the same HEAD are harmless (gate only checks latest)
- **Transparent**: All agent actions logged to stdout (you see progress)
- **Human-in-loop**: Agent escalates on ambiguity rather than guessing
