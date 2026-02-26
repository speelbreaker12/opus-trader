# Step 2: self_review

## CONTEXT
- `artifacts/story/<ID>/implement/patch_plan.md`
- scope.touch code files listed in `plans/prd.json`

## ACTION (4 sub-phases, multi-agent)

**R5b.1 — 6 agents in parallel, each runs one skill:**
- Agent A: `/pr-review` → `FINDINGS_pr_review.md`
- Agent B: `/failure-mode-review` → `FINDINGS_failure_mode.md`
- Agent C: `/strategic-failure-review` → `FINDINGS_strategic.md`
- Agent D: `/contract-review` → `FINDINGS_contract.md`
- Agent E: `/validator-audit` → `FINDINGS_validator.md`
- Agent F: `/devils-advocate` → `FINDINGS_devils_advocate.md`

**R5b.2 — planner agent (read-only):**
- Read all 6 FINDINGS files
- Write `FIX_PLAN.md`: CODE_FIX and TEST_FIX items only (no PRD_FIX or DEFERRED)
- If no items: write `FIX_PLAN.md` with single line `PLAN: EMPTY`

**R5b.3 — fixer agent:**
- If `FIX_PLAN.md` says `PLAN: EMPTY` → skip this phase
- Else: execute every item in FIX_PLAN.md

**R5b.4 — re-runner:**
- If R5b.3 was skipped → skip this phase
- Else: re-run skills whose FINDINGS were affected by the fixes; confirm PASS

## OUTPUT
`artifacts/story/<ID>/self_review/`
→ `FINDINGS_<skill>.md` (6 files)
→ `FIX_PLAN.md`

## RECEIPT
```
plans/wf_step.sh <ID> self_review
```
