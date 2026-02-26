# Step 4: fix

## CONTEXT
- `artifacts/story/<ID>/cycle1/evidence_ledger.md` (PATH signal + BLOCKING findings)

## ACTION
- Read line 1 of `evidence_ledger.md`
- **If `PATH: GREEN`:**
  - No code changes needed
  - Write `fix_summary.md`: first line `PATH: GREEN`, second line `code_changed: NO`
  - Done
- **If `PATH: YELLOW`:**
  - Apply every BLOCKING (P0/P1) finding listed in `evidence_ledger.md`
  - Run `./plans/verify.sh quick`; confirm it passes
  - Write `fix_summary.md`:
    - Line 1: `PATH: YELLOW`
    - Line 2: `code_changed: YES` or `code_changed: NO`
    - Then: one paragraph describing what was fixed

## OUTPUT
- Code changes (if any)
- `artifacts/story/<ID>/fix/fix_summary.md`

## RECEIPT
```
plans/wf_step.sh <ID> fix
```
