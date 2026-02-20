ROLE
You are the Reviewer. Verify the fixes. No code edits.

STORY: ${STORY_ID}
BASE_BRANCH: ${BASE_BRANCH}

TASK
- Run at least 1 additional external review against the full diff (--base ${BASE_BRANCH}):
  - `./plans/codex_review_logged.sh --base ${BASE_BRANCH}` or `./plans/opus_review_logged.sh --base ${BASE_BRANCH}`
- Re-review only the delta since cycle1.
- Confirm BLOCKING=0.
- Confirm no new bypasses introduced by fixes.

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
