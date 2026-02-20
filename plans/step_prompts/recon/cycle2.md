ROLE
You are the Reviewer. Verify the reconciliation audit. No code edits.
This is RECONCILIATION mode — the story already has passes=true.

STORY: ${STORY_ID}
BASE_BRANCH: ${BASE_BRANCH}

TASK

GREEN PATH (no code changes in fix step):
- Perform abbreviated validation of the reconciliation audit.
- Review the scope.touch files and confirm the audit found no issues.
- Produce at least 1 review artifact confirming audit completeness.

YELLOW/RED PATH (code changed in fix step):
- Full adversarial review of the fix diff (--base ${BASE_BRANCH}).
- Re-review only the delta since cycle1.
- Confirm BLOCKING=0.
- Confirm no new bypasses introduced by fixes.
- Produce review artifact(s) with full finding table.

For both paths:
- Run at least 1 review: `./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}` or `--tool opus`

OUTPUT
- Write review file to artifacts/story/${STORY_ID}/codex/ (or opus/).
- Include STOPLIGHT + finding table.
- End with: "READY FOR RESOLUTION".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT edit any source code — review only
- Do NOT claim the step is "done" — only the supervisor validates completion
