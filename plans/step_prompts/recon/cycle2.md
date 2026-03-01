# Step 5: cycle2

## CONTEXT
- `artifacts/story/<ID>/fix/fix_summary.md` (lines 1-2: PATH + code_changed)
- Fix diff (`git diff <cycle1_head>..HEAD`)

## ACTION
- Read lines 1-2 of `fix_summary.md` to determine review scope:
  - `PATH: GREEN` **and** `code_changed: NO` → **1 review** (lightweight confirmation)
  - `PATH: YELLOW` **or** `code_changed: YES` → **2 reviews** (full adversarial)
- Dispatch review(s) via `plans/review_logged.sh <STORY_ID> --base <integration_branch> --tool <tool>`
- Use explicit prompt style(s) required by the manifest/policy (`--prompt enriched` and/or `--prompt generic`).
- If needed, set `--timeout-seconds <N>` for slow tool/model responses.
- Review basis: **FIX_DIFF** (review the fix changes, not full story scope)
- `review_logged.sh` writes the review basis line automatically; C2 artifacts are distinguished by `Review basis: FIX_DIFF` in their content — no filename prefix needed
- Review quality requirement: every finding must include explicit `path/to/file.ext:line` evidence citations.
- Triage nonzero exits from `review_logged.sh`:
  - Exit `4`: missing required citations. Fix reviewer output quality and rerun.
  - Exit `7`: timeout hard-gate. Increase timeout or reduce prompt/file scope and rerun.
- Sidecar rule: failed runs can intentionally leave no sidecar; do not reuse stale sidecars as evidence.

## OUTPUT
`artifacts/story/<ID>/<tool>/` → cycle2 review artifact(s) (identified by `Review basis: FIX_DIFF` in content)

## RECEIPT
```
plans/wf_step.sh <ID> cycle2
```
