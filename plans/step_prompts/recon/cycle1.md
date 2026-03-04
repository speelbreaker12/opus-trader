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
- Write canonical JSON ledger at `artifacts/story/<ID>/evidence_ledger.json`:
  - `path`: `GREEN` (0 BLOCKING findings) or `YELLOW` (any P0/P1 finding)
  - `at_verdicts[]`: one row per AT in `enforcing_contract_ats[]`
  - required row fields: `at_id`, `verdict`, `enforcement`, `test`, `notes`
  - for `verdict=PROVEN`, `enforcement` and `test` must include `file:line` citations
- Keep markdown ledgers as read-only legacy compatibility only; do not create new `.md` ledger files.

## OUTPUT
- `artifacts/story/<ID>/<tool>/` → review artifact from review_logged.sh
- `artifacts/story/<ID>/evidence_ledger.json` → canonical PATH signal + AT verdict coverage

## RECEIPT
```
plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool>
plans/wf_step.sh <ID> cycle1
```
