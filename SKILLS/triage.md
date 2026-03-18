# SKILL: /triage (Investigate Bug → File GH Issue with TDD Fix Plan)

Investigate a reported problem, find its root cause, and create a GitHub issue with a TDD fix plan. For bugs that shouldn't be fixed immediately — track them properly instead of losing context.

## When to use

- Bug reported but not urgent enough to fix right now
- Want to investigate and document before committing to a fix
- Need to hand off a bug to a future session
- Someone says "triage this" or "file an issue for this"

## When NOT to use

- Urgent bug blocking work → fix it directly
- Already know the root cause → skip to `/slice-execute`
- Pure feature request → use `/interview` instead

## Workflow

### 1. Capture the Problem

Get a brief description from the user. If they haven't provided one, ask ONE question: "What's the problem you're seeing?"

Do NOT ask follow-up questions yet. Start investigating immediately.

### 2. Explore and Diagnose

Use the Agent tool with `subagent_type=Explore` to deeply investigate the codebase. Find:

- **Where** the bug manifests (entry points, API responses, test failures)
- **What** code path is involved (trace the flow)
- **Why** it fails (the root cause, not just the symptom)
- **What** related code exists (similar patterns, tests, adjacent modules)

Look at:
- Related source files and their dependencies
- Existing tests (what's tested, what's missing)
- Recent changes to affected files (`git log --oneline -10 <file>`)
- Error handling in the code path
- Similar patterns elsewhere that work correctly
- CONTRACT.md sections that govern this behavior

### 3. Identify the Fix Approach

Based on investigation, determine:

- The minimal change needed to fix the root cause
- Which modules/interfaces are affected
- What behaviors need to be verified via tests
- Whether this is a regression, missing feature, or design flaw
- **Fail-closed implications**: does the fix touch a safety-critical path?

### 4. Design TDD Fix Plan

Create a concrete, ordered list of RED-GREEN cycles. Each cycle is one vertical slice:

```
1. RED:   Write test that [describes expected behavior] → fails
   GREEN: [Minimal code change to make it pass]

2. RED:   Write test that [describes next behavior] → fails
   GREEN: [Minimal code change to make it pass]

REFACTOR: [Any cleanup needed after all tests pass]
```

Rules:
- Tests verify behavior through public interfaces, not implementation details
- One test at a time — vertical slices, NOT all tests first
- Each test should survive internal refactors
- For safety-critical paths: include fail-closed test (what happens when guard triggers?)
- Reference CONTRACT.md sections where applicable

### 5. Create the GitHub Issue

Create using `gh issue create`. Do NOT ask the user to review before creating — just create it and share the URL.

```bash
gh issue create --title "<concise bug title>" --body "$(cat <<'ISSUE_BODY'
## Problem

**Actual behavior**: [what happens]
**Expected behavior**: [what should happen]
**Reproduction**: [how to trigger, if applicable]

## Root Cause Analysis

[What code path is involved, why it fails, contributing factors]

Describe modules and behaviors, NOT specific file paths or line numbers —
the issue should remain useful after refactors.

## Contract Alignment

[Which CONTRACT.md sections govern this behavior, if any]

## TDD Fix Plan

1. **RED**: Write test that [expected behavior]
   **GREEN**: [Minimal change]

2. **RED**: Write test that [next behavior]
   **GREEN**: [Minimal change]

**REFACTOR**: [Cleanup if needed]

## Acceptance Criteria

- [ ] Root cause fixed (not just symptom)
- [ ] Fail-closed behavior preserved
- [ ] All new tests pass
- [ ] Existing tests still pass
- [ ] `./plans/verify.sh quick` passes

## Risk Assessment

- **Severity**: [LOW/MED/HIGH]
- **Blast radius**: [what else could break]
- **Safety-critical**: [yes/no — does it touch trading/risk paths?]
ISSUE_BODY
)"
```

### 6. Report Back

Print the issue URL and a one-line summary of the root cause.

## Anti-Patterns

- **Fixing immediately**: This skill is for investigation + documentation, not fixing. If you want to fix, use `/slice-execute`
- **Shallow diagnosis**: Don't stop at the symptom — trace to root cause
- **Vague fix plans**: "Fix the bug" is not a TDD step. Be specific about what test to write
- **File-path coupling**: The issue should survive refactors. Describe behaviors, not `src/foo/bar.rs:42`
- **Skipping contract check**: Every bug in safety-critical code needs contract alignment analysis
