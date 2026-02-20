ROLE
You are the Builder (or Supervisor) closing the review loop.

STORY: ${STORY_ID}

TASK
- Create artifacts/story/${STORY_ID}/review_resolution.md using the template from plans/review_resolution_template.md.
- The resolution MUST contain:
  - "Blocking addressed: YES"
  - "BLOCKING=0 MAJOR=0 MEDIUM=0" (or accurate counts with explicit deferrals)
  - Lists any deferred items with owners and rationale

OUTPUT
- Provide the file path and paste its contents.
- End with: "READY FOR VERIFY_FULL".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
