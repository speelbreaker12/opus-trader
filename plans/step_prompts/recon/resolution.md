# Step 6: resolution

## CONTEXT
- `artifacts/story/<ID>/cycle1/evidence_ledger.md`
- `artifacts/story/<ID>/<tool>/` → cycle2 artifacts (identified by `Review basis: FIX_DIFF` in content)
- `artifacts/story/<ID>/fix/fix_summary.md` (PATH signal)

## ACTION
- Write `review_resolution.md`; must contain these exact lines:
  ```
  Blocking addressed: YES
  Remaining findings: BLOCKING=0
  ```
- If PATH was YELLOW or RED at any point:
  - Write `postmortem.md` using `plans/postmortem_template.md`
  - Validate: `plans/postmortem_gate.sh <ID>`
- If PATH was GREEN throughout: no postmortem required

## OUTPUT
- `artifacts/story/<ID>/review_resolution.md`
- `artifacts/story/<ID>/postmortem.md` (YELLOW/RED only)

## RECEIPT
```
plans/wf_step.sh <ID> resolution
```
