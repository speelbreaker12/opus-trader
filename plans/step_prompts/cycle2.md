ROLE
You are the Reviewer. Verify the fixes. No code edits.

STORY: ${STORY_ID}
BASE_BRANCH: ${BASE_BRANCH}

TASK
Run the logged review script again to produce cycle 2 review on the fixed code:
- `./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}`
  (or: `./plans/codex_review_logged.sh ${STORY_ID} --base ${BASE_BRANCH}`)

This must generate a second logged review artifact (with logger provenance / transcript hashes).

OUTPUT
- New cycle 2 review file path
- Count of BLOCKING/MAJOR/MEDIUM findings (should be 0)
- End exactly with: READY FOR CYCLE2 GATE

PROHIBITED
- Do NOT write the review file by hand
- Do NOT edit code in this step
- Do NOT run wf_step.sh, story_review_gate.sh, prd_set_pass.sh, or verify.sh
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT edit any source code — review only
- Do NOT claim the step is "done" — only the supervisor validates completion
