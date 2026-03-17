# SKILL: /super-pr-review (Maximum Coverage Review)

Purpose
- Run all 7 internal review skills AND 4 external tools simultaneously (parallel), then synthesize
- Maximum coverage: subsumes `/review-stack` AND `/external-review` in a single pass
- Produces a single cross-validated verdict with findings from both tracks

When to use
- Before merging any safety-critical change
- When you want the highest-confidence verdict possible
- After all fixes are applied and you want a final all-clear

When NOT to use
- Quick iterative feedback (use `/review-stack` alone)
- External reviews are rate-limited/unavailable

---

## Inputs

| Input | Required | Default |
|-------|----------|---------|
| STORY_ID | Yes | — |
| TARGET | Yes | PR number or `--base main` |
| BASE_BRANCH | No | `main` |

---

## Architecture: 2-Wave Parallel Dispatch

```
Wave 1 (all in parallel):
  Agent 1  → /pr-review
  Agent 2  → /failure-mode-review
  Agent 3  → /contract-review
  Agent 4  → /validator-audit
  Agent 5  → /devils-advocate
  Agent 6  → /loss-risk-gate
  Agent 7  → external-review (plans/external_review_generic.sh TARGET)

Wave 2 (after failure-mode completes):
  Agent 8  → /strategic-failure-review (requires failure-mode output)

Wave 3:
  Synthesis → cross-reference Track A (internal) + Track B (external), write final verdict
```

Each Wave 1 agent reads its SKILL file and executes fully autonomously.

---

## Phase 0 — Setup

1. Resolve inputs and create artifact directory:
   ```bash
   ARTIFACT_DIR="artifacts/story/${STORY_ID}/super_pr_review"
   mkdir -p "${ARTIFACT_DIR}"
   HEAD=$(git rev-parse --short HEAD)
   TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   ```

2. Track safety-critical surface:
   ```bash
   SAFETY_CRITICAL=$(git diff ${BASE_BRANCH}...HEAD --name-only | grep -cE 'crates/soldier_core/|crates/soldier_infra/' || true)
   ```

---

## Phase 1 — Wave 1: Parallel Dispatch (7 agents simultaneously)

Dispatch all 7 agents in a single message with multiple Agent tool calls. Each agent is independent.

**Agent 1 — PR Review**
- Read `SKILLS/pr-review.md` and execute the full checklist against the diff
- Write findings to `artifacts/story/${STORY_ID}/self_review/pr_review.md`

**Agent 2 — Failure-Mode Review**
- Read `SKILLS/failure-mode-review.md` and execute all mandatory sections
- Write findings to `artifacts/story/${STORY_ID}/self_review/failure_mode_review.md`
- CRITICAL: This agent's output is required by Wave 2

**Agent 3 — Contract Review**
- Read `SKILLS/contract-review.md`
- Skip if `SAFETY_CRITICAL == 0`
- Write findings to `artifacts/story/${STORY_ID}/self_review/contract_review.md`
- Write `artifacts/story/${STORY_ID}/self_review/contract_review.json`

**Agent 4 — Validator Audit**
- Read `SKILLS/validator-audit.md`
- Skip if no validators/rule-checkers changed
- Write findings to `artifacts/story/${STORY_ID}/self_review/validator_audit.md`

**Agent 5 — Devils Advocate**
- Read `SKILLS/devils-advocate.md`
- Skip if no new/modified acceptance tests in diff
- Write findings to `artifacts/story/${STORY_ID}/self_review/devils_advocate.md`

**Agent 6 — Loss-Risk Gate**
- Read `SKILLS/loss-risk-gate.md`
- Skip if diff doesn't touch risk/dispatch/position/fail-closed logic
- Write findings to `artifacts/story/${STORY_ID}/self_review/loss_risk_gate.md`

**Agent 7 — External Review**
- Run: `cd /Users/admin/Desktop/opus-trader && ./plans/external_review_generic.sh ${TARGET}`
- Wait for completion and capture exit code
- External artifacts land in `artifacts/story/${TARGET}/external_review_generic/`

---

## Phase 2 — Wave 2: Strategic Failure Review (after failure-mode completes)

**Agent 8 — Strategic Failure Review**
- Read `SKILLS/strategic-failure-review.md`
- Read failure-mode output from `artifacts/story/${STORY_ID}/self_review/failure_mode_review.md`
- Small-change mode if `SAFETY_CRITICAL == 0` AND < 3 files changed
- Write findings to `artifacts/story/${STORY_ID}/self_review/strategic_failure_review.md`

---

## Phase 3 — Synthesis

Read all agent outputs and cross-reference Track A (internal) vs Track B (external).

### Aggregate Decision Logic

```
if any internal phase == FAIL or BLOCKED:
    DECISION = FAIL
elif loss_risk_gate == NO-GO or BLOCKING:
    DECISION = FAIL
elif external review exit non-zero:
    DECISION = FAIL
elif any internal phase == CONCERNS:
    DECISION = CONDITIONAL_PASS
elif loss_risk_gate == HARDENING:
    DECISION = CONDITIONAL_PASS
else:
    DECISION = PASS
```

### Cross-Validation

For each internal finding, check if external tools corroborate. Flag:
- **CONFIRMED**: Internal + external both flagged
- **INTERNAL_ONLY**: Internal found it, external missed it
- **EXTERNAL_ONLY**: External found it, internal missed it

---

## Output Format

Write `artifacts/story/${STORY_ID}/super_pr_review/summary.md`:

```markdown
# Super PR Review — ${STORY_ID}

HEAD: ${HEAD}
Base: ${BASE_BRANCH}
Timestamp (UTC): ${TS}
DECISION: ${DECISION}

## Track A — Internal (7+1 Skills)

| # | Skill | Verdict | Findings |
|---|-------|---------|----------|
| 1 | /pr-review | PASS/FAIL | P0:0 P1:0 P2:0 |
| 2 | /failure-mode-review | PASS/CONCERNS | N failure modes |
| 3 | /strategic-failure-review | PASS/CONCERNS/SKIPPED | N risks |
| 4 | /contract-review | PASS/FAIL/SKIPPED | C:0 H:0 M:0 L:0 |
| 5 | /validator-audit | PASS/CONCERNS/SKIPPED | N gaps |
| 6 | /devils-advocate | PASS/BLOCKED/SKIPPED | N mutations |
| 7 | /loss-risk-gate | GO/NO-GO/SKIPPED | Lens: X |

## Track B — External

| Tool | Exit | Summary |
|------|------|---------|
| codex | 0/1 | ... |
| opus | 0/1 | ... |
| kimi | 0/1 | ... |
| gemini | 0/1 | ... |

## Cross-Validation Summary

| Finding | Internal | External | Status |
|---------|----------|----------|--------|
| ... | Y/N | Y/N | CONFIRMED/INTERNAL_ONLY/EXTERNAL_ONLY |

## Blocking Issues
<P0/CRITICAL/BLOCKED items — must fix before merge>

## Non-Blocking Findings
<P1-P3/CONCERNS items — fix or track>

## Verdict
DECISION: ${DECISION}
```

Write gate marker: `artifacts/story/${STORY_ID}/super_pr_review/.gate`
```
decision=${DECISION}
head=${HEAD}
timestamp=${TS}
```

---

## PROHIBITED

- Do NOT run `wf_step.sh`, `prd_set_pass.sh`, or `verify.sh`
- Do NOT mark stories as passing
- Do NOT skip phases without documenting the skip reason
- Read actual source files — do not reason from descriptions alone
- Every finding must include file:line references
