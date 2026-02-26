# Step 3: cycle1

## CONTEXT
- scope.touch files listed in `plans/prd.json` story entry
- `reviews/premortems/<ID>_premortem.md`

## ACTION
- Dispatch external review:
  ```
  plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool>
  ```
- Review basis: **STORY_SCOPE** (review the story's implementation, not git diff)
- Write `evidence_ledger.md`; **first line must be exactly one of:**
  - `PATH: GREEN` — 0 BLOCKING findings (P0 or P1)
  - `PATH: YELLOW` — any BLOCKING findings exist
- List all findings after the PATH line: severity | AT-ID | what is wrong

## OUTPUT
- `artifacts/story/<ID>/<tool>/` → review artifact from review_logged.sh
- `artifacts/story/<ID>/cycle1/evidence_ledger.md` → PATH signal + findings

## RECEIPT
```
plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool>
plans/wf_step.sh <ID> cycle1
```
