# Step 1: implement

## CONTEXT
- `artifacts/story/<ID>/preflight/audit.md` (STOPLIGHT + AT proof table)
- scope.touch code files listed in `plans/prd.json`

## ACTION
- For each AT with FAIL or PARTIAL verdict in the proof table:
  - Read the relevant code and test
  - Trace the fail-closed path from intent to enforcement
  - Identify the gap
- Classify each gap:
  - CODE_FIX: implementation is wrong or missing
  - TEST_FIX: test doesn't prove causality (wrong impl would still pass)
  - PRD_FIX: PRD claim is incorrect
  - DEFERRED: valid gap but out of scope for this recon cycle
- Write one patch_plan entry per gap
- No code edits in this step

## OUTPUT
`artifacts/story/<ID>/implement/patch_plan.md`
-> One entry per gap: classification | AT-ID | what is wrong | proposed fix

## RECEIPT
```
plans/wf_step.sh <ID> implement
```
