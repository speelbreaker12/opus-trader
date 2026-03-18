# Step 4: fix

## CONTEXT
- `artifacts/story/<ID>/evidence_ledger.json` (canonical PATH signal + BLOCKING findings)

## ACTION
- Read `path` from `evidence_ledger.json`
- **If `path == GREEN`:**
  - No code changes needed
  - Write `fix_summary.md`: first line `PATH: GREEN`, second line `code_changed: NO`
  - Done
- **If `path == YELLOW`:**
  - Apply every BLOCKING (P0/P1) finding listed in `evidence_ledger.json`
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
