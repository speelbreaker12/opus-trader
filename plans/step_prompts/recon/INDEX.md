# Recon Step Prompts — Index

> Read this file first. It defines policies that apply to every step.

## Debrief Policy

**GREEN path** (step completed, 0 BLOCKING findings, no code changes):
Write one line: `Step complete.`

**YELLOW or RED path** (findings found, fixes applied, or step blocked):
Write full §0–§11 ToC debrief using `plans/postmortem_template.md`.

## Card Index

| Step | File | Role |
|------|------|------|
| 0 preflight | preflight.md | Read PRD + CONTRACT + premortem → AT proof table + STOPLIGHT |
| 1 implement | implement.md | Diagnose code → classify gaps → write patch plan |
| 2 self_review | self_review.md | 6-skill stack → FIX_PLAN → apply fixes |
| 3 cycle1 | cycle1.md | External STORY_SCOPE review → evidence_ledger.md + PATH signal |
| 4 fix | fix.md | Apply BLOCKING findings from C1 |
| 5 cycle2 | cycle2.md | External FIX_DIFF review (1 or 2 dispatches based on PATH) |
| 6 resolution | resolution.md | Write review_resolution.md + postmortem if YELLOW/RED |
| 7 verify_full | verify_full.md | Run ./plans/verify.sh full |
| 8 pass | — | Run prd_set_pass.sh to flip passes=true |

## Receipt Command

Every step ends with:
```
plans/wf_step.sh <STORY_ID> <step_name>
```
If the step failed its gate, the script will tell you what is missing.

## Reference

For unusual situations, escalation policy, debt register rules, and verdict enum:
`reviews/premortems/RUNBOOK_PREMORTEM_RECON.md`
