# Step 5: cycle2

## CONTEXT
- `artifacts/story/<ID>/fix/fix_summary.md` (lines 1-2: PATH + code_changed)
- Fix diff (`git diff <cycle1_head>..HEAD`)

## ACTION
- Read lines 1-2 of `fix_summary.md` to determine review scope:
  - `PATH: GREEN` **and** `code_changed: NO` → **1 review** (lightweight confirmation)
  - `PATH: YELLOW` **or** `code_changed: YES` → **2 reviews** (full adversarial)
- Dispatch review(s) via `plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool>`
- Review basis: **FIX_DIFF** (review the fix changes, not full story scope)
- Prefix all artifact filenames with `c2_` to distinguish from C1 artifacts

## OUTPUT
`artifacts/story/<ID>/<tool>/c2_*.md` → cycle2 review artifact(s)

## RECEIPT
```
plans/wf_step.sh <ID> cycle2
```
