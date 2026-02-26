# Step 7: verify_full

## CONTEXT
- Current HEAD (no files to pre-read)

## ACTION
- Run: `./plans/verify.sh full`
- Confirm the output contains: `mode=full`
- Confirm no `FAILED_GATE` file exists in `artifacts/verify/<timestamp>/`
- If verify fails: read the failure output, fix the issue, re-run

## OUTPUT
`artifacts/verify/<timestamp>/` → verify artifact (created by verify.sh)

## RECEIPT
```
plans/wf_step.sh <ID> verify_full
```
