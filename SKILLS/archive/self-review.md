# SKILL: /self-review (5-Skill Review Stack)

Purpose
- Run the full 5-skill self-review stack in sequence, collecting findings into a single artifact
- Replaces manually invoking each skill one by one
- Produces a structured aggregate report with per-skill verdicts and a final decision

When to use
- Story loop step 3 (self-review)
- Any time you need a comprehensive review of changes before external review
- After `/slice-execute` completes implementation

When NOT to use
- Documentation-only changes (use `/pr-review` alone)
- Non-safety Python scripts with no contract surface (use `/pr-review` alone)

---

## Inputs

| Input | Required | Default |
|-------|----------|---------|
| STORY_ID | Yes | — |
| BASE_BRANCH | No | `main` |
| DIFF_CMD | No | `git diff ${BASE_BRANCH}...HEAD` |

---

## Process

### Phase 0 — Setup

1. Resolve inputs:
   ```bash
   HEAD=$(git rev-parse --short HEAD)
   DIFF=$(git diff ${BASE_BRANCH}...HEAD --stat)
   ```
2. Create artifact directory:
   ```
   artifacts/story/${STORY_ID}/self_review/
   ```
3. Check if changes touch safety-critical code:
   ```bash
   SAFETY_CRITICAL=$(git diff ${BASE_BRANCH}...HEAD --name-only | grep -cE 'crates/soldier_core/|crates/soldier_infra/' || true)
   ```

### Phase 1 — PR Review (`/pr-review`)

Run the `/pr-review` skill checklist against the diff.

**Record:**
- Finding count (P0 / P1 / P2)
- Verdict: PASS / FAIL

**Short-circuit:** If any P0 finding, stop and report. Fix P0s before continuing.

### Phase 2 — Failure-Mode Review (`/failure-mode-review`)

Run the `/failure-mode-review` skill. Read actual source files, not just diffs.

**Record:**
- Failure modes found (with file:line references)
- Verdict: PASS / CONCERNS

### Phase 3 — Strategic Failure Review (`/strategic-failure-review`)

Run the `/strategic-failure-review` skill.

**Skip condition:** If `SAFETY_CRITICAL == 0` AND the change touches fewer than 3 files, skip this phase and record `SKIPPED (non-safety, small change)`.

**Record:**
- Structural/operational risks found
- Verdict: PASS / CONCERNS

### Phase 4 — Contract Review (`/contract-review`)

Run the `/contract-review` skill (fast safety filter).

**Skip condition:** If `SAFETY_CRITICAL == 0`, skip and record `SKIPPED (no safety-critical files changed)`.

**Record:**
- Findings by severity (CRITICAL / HIGH / MEDIUM / LOW)
- Decision: PASS / FAIL
- This produces the `contract_review.json` needed by `prd_set_pass.sh`

### Phase 5 — Devil's Advocate (`/devils-advocate`)

Run the `/devils-advocate` skill on new/modified ATs.

**Skip condition:** If no new or modified acceptance tests exist in the diff, skip and record `SKIPPED (no AT changes)`.

**Record:**
- Mutations attempted / gaps found / tests added
- Simpler-than-correct gate: PASS / BLOCKED

---

## Phase 6 — Aggregate & Write Artifact

### Decision Logic

```
if any phase == FAIL or BLOCKED:
    DECISION = FAIL
elif any phase == CONCERNS:
    DECISION = CONDITIONAL_PASS (list concerns)
else:
    DECISION = PASS
```

### Artifact Template

Write to `artifacts/story/${STORY_ID}/self_review/<UTC_TS>_self_review.md`:

```markdown
# Self Review — ${STORY_ID}

Story: ${STORY_ID}
HEAD: ${HEAD}
Timestamp (UTC): ${TS}
Decision: ${DECISION}

## Stack Results

| # | Skill | Verdict | Findings |
|---|-------|---------|----------|
| 1 | /pr-review | PASS/FAIL | P0:0 P1:0 P2:0 |
| 2 | /failure-mode-review | PASS/CONCERNS | N failure modes |
| 3 | /strategic-failure-review | PASS/CONCERNS/SKIPPED | N risks |
| 4 | /contract-review | PASS/FAIL/SKIPPED | C:0 H:0 M:0 L:0 |
| 5 | /devils-advocate | PASS/BLOCKED/SKIPPED | N mutations, N gaps |

Checklist:
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
- Contract alignment checked: YES
- Acceptance criteria met: YES/NO

## PR Review Findings
<findings from phase 1, or "None">

## Failure-Mode Review Findings
<findings from phase 2, or "None">

## Strategic Failure Review Findings
<findings from phase 3, or "None — skipped">

## Contract Review Findings
<findings from phase 4, or "None — skipped">

## Devil's Advocate Results
<findings from phase 5, or "None — skipped">

## Risks / Follow-ups
<aggregate list of unresolved concerns, deferred items>

## Fixes Applied During Review
<list any fixes made during review, with commit SHAs>
```

### Contract Review JSON

If Phase 4 ran, also write `artifacts/story/${STORY_ID}/self_review/contract_review.json`:

```json
{
  "story_id": "${STORY_ID}",
  "head": "${HEAD}",
  "timestamp_utc": "${TS}",
  "decision": "PASS",
  "findings": []
}
```

---

## Fix-and-Continue Rule

When a phase finds issues:

1. **P0 / CRITICAL / BLOCKED**: Stop the stack. Fix immediately. Re-run from the phase that failed.
2. **P1-P2 / HIGH-MEDIUM / CONCERNS**: Note the finding. Continue the stack. Fix all at the end. Then re-run only the phases that had findings.
3. **LOW / informational**: Note and continue. No re-run needed.

After fixes, update the artifact with the final verdicts.

---

## Exit Criteria

The skill is complete when:
1. All 5 phases have run (or been legitimately skipped)
2. The aggregate decision is PASS or CONDITIONAL_PASS
3. The self-review artifact is written with all findings documented
4. Any fixes applied during review are committed
5. End message: `READY FOR SELF_REVIEW GATE`

---

## PROHIBITED

- Do NOT add new features or refactor unrelated code
- Do NOT run `wf_step.sh`, `story_review_gate.sh`, `prd_set_pass.sh`, or `verify.sh`
- Do NOT edit `.wf/receipts/` or any workflow state files
- Do NOT modify `plans/prd.json` passes field
- Do NOT fabricate findings or skip phases without documenting the skip reason
- Do NOT claim the step is "done" — only the supervisor validates completion
