# Step 0: preflight

## CONTEXT
- `plans/prd.json` → story entry: `scope.touch` file list + AT references
- `specs/CONTRACT.md` → sections referenced by scope.touch files
- `artifacts/story/<ID>/premortem.md`

## ACTION
- Read each scope.touch file
- Build AT proof table: AT-ID | test file:line | verdict (PASS / FAIL / PARTIAL)
  - PASS: test exists, covers the AT, and would catch a wrong implementation
  - PARTIAL: test exists but coverage is incomplete or causal proof is weak
  - FAIL: test missing, wrong, or does not prove the AT claim
- Assign STOPLIGHT on line 1 of audit.md:
  - GREEN: all verdicts PASS
  - YELLOW: any PARTIAL, no FAIL
  - RED: any FAIL
- No code edits in this step

## OUTPUT
`artifacts/story/<ID>/preflight/audit.md`
→ Line 1: `STOPLIGHT: GREEN` (or YELLOW or RED)
→ Then: AT proof table

## RECEIPT
```
plans/wf_step.sh <ID> preflight
```
