# Story 0 Workflow Baseline Green Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the workflow baseline green on a fresh base by fixing the red review-stack wrapper contract while keeping the PR review gate hook test green.

**Architecture:** This roadmap intentionally decomposes into separate story plans; this file covers Story 0 only. On the current fresh base, `bash plans/tests/test_pr_review_gate_hook.sh` is already green, while `bash plans/tests/test_review_command_wrappers.sh` is red because the review-stack command and skill wrappers drifted from the gate contract. The plan keeps the hook as a regression surface, narrows edits to the wrapper files unless a stale branch reproduces a hook failure first, and finishes with the workflow-specific verification entrypoint.

**Tech Stack:** Bash hooks and tests, Markdown command/skill wrappers, git worktrees, repo workflow harness.

---

## File Map

- Modify: `.claude/commands/review-stack.md` — review-stack command wrapper; must advertise the skill clearly and describe the verdict-bearing gate marker that unblocks `gh pr create`.
- Modify: `.claude/skills/review-stack/SKILL.md` — review-stack skill wrapper; must load the canonical `SKILLS/review-stack.md` from repo root.
- Verify only unless a stale branch proves otherwise: `.claude/hooks/pr-review-gate-hook.sh` — keep the current fresh-base behavior green; do not widen Story 0 with speculative hook edits.
- Test: `plans/tests/test_review_command_wrappers.sh`
- Test: `plans/tests/test_pr_review_gate_hook.sh`
- Test: `plans/tests/test_preflight_fixture_profiles.sh`
- Verify: `./plans/workflow_verify.sh`

## Current Baseline (2026-03-21)

- `bash plans/tests/test_pr_review_gate_hook.sh` -> `test_pr_review_gate_hook.sh: ok`
- `bash plans/tests/test_review_command_wrappers.sh` -> `FAIL: expected '# SKILL: /review-stack' in .../.claude/commands/review-stack.md`
- `bash plans/tests/test_preflight_fixture_profiles.sh` -> `PASS: preflight fixture profile mapping`
- `plans/tests/test_verify_scope.sh` does not exist on this base; do not invent it or add it to Story 0 verification.

## Chunk 1: Fresh-Base Baseline and Wrapper Contract

### Task 1: Reproduce the current red/green state before editing

**Files:**
- Test: `plans/tests/test_pr_review_gate_hook.sh`
- Test: `plans/tests/test_review_command_wrappers.sh`
- Test: `plans/tests/test_preflight_fixture_profiles.sh`

- [ ] **Step 1: Run the hook test on the actual implementation base**

Run:
```bash
bash plans/tests/test_pr_review_gate_hook.sh
```

Expected on a fresh base:
```text
test_pr_review_gate_hook.sh: ok
```

- [ ] **Step 2: Run the wrapper test and capture the red assertion**

Run:
```bash
bash plans/tests/test_review_command_wrappers.sh
```

Expected on the fresh base:
```text
FAIL: expected '# SKILL: /review-stack' in .../.claude/commands/review-stack.md
```

- [ ] **Step 3: Run the preflight fixture profile test to confirm the surrounding workflow harness is green**

Run:
```bash
bash plans/tests/test_preflight_fixture_profiles.sh
```

Expected:
```text
PASS: preflight fixture profile mapping
```

- [ ] **Step 4: Stop if the hook test is red on the chosen execution branch**

If Step 1 fails on a stale branch, do not debug wrapper drift on top of that red baseline. First inherit a green base by rebasing onto the current clean integration branch or cherry-picking the already-green Story 0 hook state, then rerun Step 1 before editing wrapper files.

---

### Task 2: Rewrite `.claude/commands/review-stack.md` to the gate contract

**Files:**
- Modify: `.claude/commands/review-stack.md`
- Test: `plans/tests/test_review_command_wrappers.sh`

- [ ] **Step 1: Replace the wrapper content with the expected command contract**

Set `.claude/commands/review-stack.md` to:

````md
# SKILL: /review-stack

Invoke the `review-stack` skill to run the full review stack and collect a single gate artifact.

## Steps

1. Use the Skill tool with skill name "review-stack" and follow it fully.

2. Capture the reviewed head:

```bash
git rev-parse HEAD
```

3. After the review stack completes with `PASS` or `CONDITIONAL_PASS`, write the PR gate marker under `artifacts/pr-review-gate`:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$REPO_ROOT/artifacts/pr-review-gate"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH="${BRANCH//\//_}"
HEAD=$(git rev-parse HEAD)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$REPO_ROOT/artifacts/pr-review-gate/${SAFE_BRANCH}.json" <<EOF
{
  "branch": "${BRANCH}",
  "head_commit": "${HEAD}",
  "head": "${HEAD}",
  "verdict": "${DECISION}",
  "timestamp_utc": "${TS}"
}
EOF
```

This marker is checked by the PR review gate before `gh pr create`.
````

- [ ] **Step 2: Run the wrapper test again to confirm the next remaining failure surface**

Run:
```bash
bash plans/tests/test_review_command_wrappers.sh
```

Expected after this file update: the test no longer fails on `.claude/commands/review-stack.md`; if it still fails, correct the wrapper text before proceeding.

---

### Task 3: Rewrite `.claude/skills/review-stack/SKILL.md` to resolve from repo root

**Files:**
- Modify: `.claude/skills/review-stack/SKILL.md`
- Test: `plans/tests/test_review_command_wrappers.sh`

- [ ] **Step 1: Replace the wrapper content with the canonical repo-root loader**

Set `.claude/skills/review-stack/SKILL.md` to:

```md
---
name: review-stack
description: Full 7-skill review stack — pr-review → failure-mode → strategic → contract → validator-audit → devils-advocate → loss-risk-gate. Produces P0/P1/P2 verdict.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat "$(git rev-parse --show-toplevel)/SKILLS/review-stack.md"`
```

- [ ] **Step 2: Rerun the wrapper contract test until it is fully green**

Run:
```bash
bash plans/tests/test_review_command_wrappers.sh
```

Expected:
```text
test_review_command_wrappers.sh: ok
```

- [ ] **Step 3: Commit the wrapper-alignment batch**

Run:
```bash
git add .claude/commands/review-stack.md .claude/skills/review-stack/SKILL.md
git commit -m "workflow: align review-stack wrappers with PR gate"
```

Expected: one commit containing only the wrapper alignment plus required project/debrief tracking files for the Story 0 execution branch.

## Chunk 2: Hook Regression Lock and Workflow Verification

### Task 4: Keep the hook green; only patch it if the actual branch still reproduces red

**Files:**
- Verify: `.claude/hooks/pr-review-gate-hook.sh`
- Test: `plans/tests/test_pr_review_gate_hook.sh`

- [ ] **Step 1: Re-run the hook test after the wrapper changes**

Run:
```bash
bash plans/tests/test_pr_review_gate_hook.sh
```

Expected:
```text
test_pr_review_gate_hook.sh: ok
```

- [ ] **Step 2: If the hook is red on the actual execution base, port the known-green behavior before doing anything else**

Use the clean reference base as the source of truth. The required behavior is:

- read the full tool request payload, not a shell command string reconstructed separately
- keep stdin closed after payload capture (`exec </dev/null`)
- resolve `env`, `command`, and `--chdir` wrappers safely without allowing repo-root escape
- read cached marker verdict/head state once per marker path
- block `gh pr create` unless the current branch has a PASS or CONDITIONAL_PASS marker for the current HEAD

After porting those semantics into `.claude/hooks/pr-review-gate-hook.sh`, rerun:

```bash
bash plans/tests/test_pr_review_gate_hook.sh
```

Do not widen Story 0 beyond that proven hook behavior.

---

### Task 5: Run the full Story 0 verification surface

**Files:**
- Test: `plans/tests/test_review_command_wrappers.sh`
- Test: `plans/tests/test_pr_review_gate_hook.sh`
- Test: `plans/tests/test_preflight_fixture_profiles.sh`
- Verify: `plans/workflow_verify.sh`

- [ ] **Step 1: Re-run the wrapper test**

Run:
```bash
bash plans/tests/test_review_command_wrappers.sh
```

Expected:
```text
test_review_command_wrappers.sh: ok
```

- [ ] **Step 2: Re-run the hook test**

Run:
```bash
bash plans/tests/test_pr_review_gate_hook.sh
```

Expected:
```text
test_pr_review_gate_hook.sh: ok
```

- [ ] **Step 3: Re-run the preflight fixture profile test**

Run:
```bash
bash plans/tests/test_preflight_fixture_profiles.sh
```

Expected:
```text
PASS: preflight fixture profile mapping
```

- [ ] **Step 4: Run the workflow verification entrypoint**

Run:
```bash
./plans/workflow_verify.sh
```

Expected: shell checks complete, `./plans/workflow_contract_gate.sh` passes, and `./plans/verify.sh quick` finishes without errors.

- [ ] **Step 5: Update Story 0 project tracking and commit the final baseline-green batch**

Run:
```bash
git add .claude/commands/review-stack.md .claude/skills/review-stack/SKILL.md .claude/hooks/pr-review-gate-hook.sh obsidian/Projects/*.md obsidian/Debriefs/*.md
git commit -m "workflow: make Story 0 review baseline green"
```

Expected: a clean Story 0 branch/worktree with the wrapper contract green, the hook regression locked, and the workflow verification surface passing.

## Chunk 3: Execution Handoff

### Task 6: Stop after Story 0 and create separate plans for the later stories

**Files:**
- Create later: dedicated story-plan docs for Story 1 through Story 4, and only write a WAL cleanup plan if that optional lane is still justified.

- [ ] **Step 1: Do not start Story 1 implementation from this plan file**

Story 0 is only the workflow baseline. Once it is green, return to the roadmap spec and write separate implementation plans for:

- Story 1: Emergency Close fail-open removal
- Story 2: Margin Gate input semantics
- Story 3: Margin Gate interface, wiring, and math correctness
- Story 4: Type and registry alignment

- [ ] **Step 2: Record the handoff**

Document in the Story 0 debrief that later remediation stories need their own implementation plans and should branch from the now-green workflow base instead of reusing a stale branch root.
