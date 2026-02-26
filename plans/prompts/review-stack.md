# 6-Skill Review Stack Prompt

> **Tool-agnostic.** This prompt works with any LLM agent (Claude, Codex, Kimi, Opus, etc.).
> For Claude Code users: this is also available as `/review-stack` or `/6`.

## Purpose

Run all 6 review skills in sequence on a PR or story diff, collecting findings into a single aggregate report. This is the most thorough single-pass review available.

The 6 skills, in order:
1. **PR Review** — correctness, conventions, performance, testing
2. **Failure-Mode Review** — implementation-level failure analysis (caching, state, integrations, error paths)
3. **Strategic Failure Review** — architectural, systemic, operational risks
4. **Contract Review** — fail-open hazards, CONTRACT.md alignment
5. **Validator Audit** — missing validations in rule-based validators
6. **Devils Advocate** — mutation testing: write wrong impls that pass the test suite

## When to use

- Full PR/change review (the "everything" option)
- Self-review step in the story loop (step 3)
- Reconciliation R5b self-review gate
- Any time you want comprehensive coverage and are willing to spend the review budget

## When NOT to use

- Documentation-only changes (use PR Review alone)
- Quick feedback on a small fix (use PR Review alone)
- Non-safety Python scripts with no contract surface (use PR Review alone)

---

## Variables (substitute before dispatch)

| Variable | Description | Example |
|----------|-------------|---------|
| `${STORY_ID}` | Story being reviewed | `S1-007` |
| `${BASE_BRANCH}` | Branch to diff against | `main` |
| `${HEAD}` | Current git HEAD sha | `abc1234` |
| `${DIFF_CMD}` | Diff command | `git diff main...HEAD` |

---

## Skill Definitions

Each skill has a full definition file in `SKILLS/`. Read the relevant file before executing each phase.

| Phase | Skill | Definition file | Focus |
|-------|-------|----------------|-------|
| 1 | `/pr-review` | `SKILLS/pr-review.md` | Correctness, conventions, performance, testing |
| 2 | `/failure-mode-review` | `SKILLS/failure-mode-review.md` | How code fails: caching, state, integrations, error paths, concrete value walkthroughs |
| 3 | `/strategic-failure-review` | `SKILLS/strategic-failure-review.md` | Architectural purity, complexity ratio, hidden assumptions, compounding failures, operational concerns |
| 4 | `/contract-review` | `SKILLS/contract-review.md` | Fail-open patterns, PolicyGuard/TradingMode enforcement, intent classification, execution layer, owner endpoints |
| 5 | `/validator-audit` | `SKILLS/validator-audit.md` | Missing validations, enum exhaustiveness, field coverage, paper compliance, merge invariants |
| 6 | `/devils-advocate` | `SKILLS/devils-advocate.md` | Mutation testing: wrong impls that pass, simpler-than-correct gate, TRIP/NON-TRIP isolation |

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

### Phase 1 — PR Review

Read `SKILLS/pr-review.md` and execute the full checklist.

**Record:** Finding count (P0 / P1 / P2), Verdict: PASS / FAIL

**Short-circuit:** If any P0 finding → stop. Fix P0s before continuing.

### Phase 2 — Failure-Mode Review

Read `SKILLS/failure-mode-review.md`. Read actual source files, not just diffs.

**Mandatory sections:** Always apply §6 (Concrete Value Walkthrough). Triage remaining sections per the skill's triage table.

**Record:** Failure modes found (with file:line references), Verdict: PASS / CONCERNS

### Phase 3 — Strategic Failure Review

Read `SKILLS/strategic-failure-review.md`.

**Skip condition:** If `SAFETY_CRITICAL == 0` AND the change touches fewer than 3 files → skip. Record `SKIPPED (non-safety, small change)`.

**Mandatory sections:** Always apply §2 (Complexity-to-Benefit), §12 (Mental Model Mismatches), §20 (Simpler Alternative), §22 (Safety Invariants).

**Record:** Structural/operational risks found, Verdict: PASS / CONCERNS

### Phase 4 — Contract Review

Read `SKILLS/contract-review.md`.

**Skip condition:** If `SAFETY_CRITICAL == 0` → skip. Record `SKIPPED (no safety-critical files changed)`.

**Record:** Findings by severity (CRITICAL / HIGH / MEDIUM / LOW), Decision: PASS / FAIL

This produces the `contract_review.json` needed by `prd_set_pass.sh`.

### Phase 5 — Validator Audit

Read `SKILLS/validator-audit.md`.

**Skip condition:** If the change does not touch validators, rule sets, schema validation, or proof graph code → skip. Record `SKIPPED (no validator code changed)`.

**Mandatory sections when run:** Always apply §1 (Enum Exhaustiveness), §2 (Field Coverage), §3 (Dead Import Detection), §6 (Paper Compliance).

**Record:** Coverage gaps found, missing rules identified, Verdict: PASS / CONCERNS

### Phase 6 — Devils Advocate

Read `SKILLS/devils-advocate.md`.

**Skip condition:** If no new or modified acceptance tests exist in the diff → skip. Record `SKIPPED (no AT changes)`.

**Record:** Mutations attempted / gaps found / tests added, Simpler-than-correct gate: PASS / BLOCKED

---

## Aggregate Decision

```
if any phase == FAIL or BLOCKED:
    DECISION = FAIL
elif any phase == CONCERNS:
    DECISION = CONDITIONAL_PASS (list concerns)
else:
    DECISION = PASS
```

---

## Fix-and-Continue Rule

When a phase finds issues:

1. **P0 / CRITICAL / BLOCKED**: Stop the stack. Fix immediately. Re-run from the phase that failed.
2. **P1-P2 / HIGH-MEDIUM / CONCERNS**: Note the finding. Continue the stack. Fix all at the end. Then re-run only the phases that had findings.
3. **LOW / informational**: Note and continue. No re-run needed.

After fixes, update the artifact with the final verdicts.

---

## Output Format

Write to `artifacts/story/${STORY_ID}/self_review/`:

```markdown
# 6-Skill Review Stack — ${STORY_ID}

Story: ${STORY_ID}
HEAD: ${HEAD}
Base: ${BASE_BRANCH}
Timestamp (UTC): ${TS}
Decision: ${DECISION}

## Stack Results

| # | Skill | Verdict | Findings |
|---|-------|---------|----------|
| 1 | /pr-review | PASS/FAIL | P0:0 P1:0 P2:0 |
| 2 | /failure-mode-review | PASS/CONCERNS | N failure modes |
| 3 | /strategic-failure-review | PASS/CONCERNS/SKIPPED | N risks |
| 4 | /contract-review | PASS/FAIL/SKIPPED | C:0 H:0 M:0 L:0 |
| 5 | /validator-audit | PASS/CONCERNS/SKIPPED | N gaps |
| 6 | /devils-advocate | PASS/BLOCKED/SKIPPED | N mutations, N gaps |

## PR Review Findings
<findings from phase 1, or "None">

## Failure-Mode Review Findings
<findings from phase 2, or "None">

## Strategic Failure Review Findings
<findings from phase 3, or "None — skipped">

## Contract Review Findings
<findings from phase 4, or "None — skipped">

## Validator Audit Findings
<findings from phase 5, or "None — skipped">

## Devils Advocate Results
<findings from phase 6, or "None — skipped">

## Risks / Follow-ups
<aggregate list of unresolved concerns, deferred items>

## Fixes Applied During Review
<list any fixes made during review, with commit SHAs>
```

### Contract Review JSON

If Phase 4 ran, also write `contract_review.json`:

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

## Exit Criteria

The skill is complete when:
1. All 6 phases have run (or been legitimately skipped with documented reason)
2. The aggregate decision is PASS or CONDITIONAL_PASS
3. The review artifact is written with all findings documented
4. Any fixes applied during review are committed
5. End message: `READY FOR REVIEW GATE`

---

## Hard Constraints

- Do NOT add new features or refactor unrelated code
- Do NOT run `wf_step.sh`, `prd_set_pass.sh`, or `verify.sh`
- Do NOT modify `plans/prd.json` passes field
- Do NOT fabricate findings or skip phases without documenting the skip reason
- Read actual source files — do not reason abstractly from descriptions
- Every finding must include file:line references

---

## Dispatch Examples

### Claude Code
```
/review-stack S1-007
# or equivalently:
/6 S1-007
```

### Codex / other agents
```bash
# Substitute variables and feed as system prompt
STORY_ID=S1-007 BASE_BRANCH=main HEAD=$(git rev-parse HEAD) \
  envsubst < plans/prompts/review-stack.md | agent-run --prompt -

# Or provide the 6 skill definitions alongside:
cat SKILLS/pr-review.md SKILLS/failure-mode-review.md \
    SKILLS/strategic-failure-review.md SKILLS/contract-review.md \
    SKILLS/validator-audit.md SKILLS/devils-advocate.md \
    plans/prompts/review-stack.md | agent-run --prompt -
```

### wf_step integration (preferred)
```bash
# The review stack is invoked during self_review step
plans/wf_step.sh S1-007 self_review --dry-run
```
