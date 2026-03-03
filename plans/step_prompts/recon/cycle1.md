# Step 3: cycle1

## CONTEXT
- scope.touch files listed in `plans/prd.json` story entry
- `reviews/premortems/<ID>_premortem.md`

## ACTION
- Dispatch external review:
  ```
  plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool> --prompt enriched
  plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool> --prompt generic
  ```
- If needed, set `--timeout-seconds <N>` for slow tool/model responses.
- Review basis: **STORY_SCOPE** (review the story's implementation, not git diff)
- Review quality requirement: every finding must include explicit `path/to/file.ext:line` evidence citations.
- Triage nonzero exits from `review_logged.sh`:
  - Exit `4`: missing required citations. Fix reviewer output quality and rerun.
  - Exit `7`: timeout hard-gate. Increase timeout or reduce prompt/file scope and rerun.
- Sidecar rule: failed runs can intentionally leave no sidecar; do not reuse stale sidecars as evidence.
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
