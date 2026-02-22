ROLE
You are the Builder (or Supervisor) closing the review loop.
This is RECONCILIATION mode — the story already has passes=true.

STORY: ${STORY_ID}

TASK
- Create artifacts/story/${STORY_ID}/review_resolution.md using the template from plans/review_resolution_template.md.
- The resolution MUST contain:
  - "Blocking addressed: YES"
  - "BLOCKING=0 MAJOR=0 MEDIUM=0" (or accurate counts with explicit deferrals)
  - Lists any deferred items with owners and rationale
- For GREEN reconciliation (0 findings), resolution should note "Reconciliation audit: no findings."

POSTMORTEM (Step 7.1):
- Write postmortem using plans/postmortem_template.md to artifacts/story/${STORY_ID}/postmortem.md
- Focus on: what surprised you during the audit, what the blind premortem missed,
  what the next story in this slice should watch for.

OUTPUT
- Provide the resolution file path and paste its contents.
- Provide the postmortem file path.
- End with: "READY FOR VERIFY_FULL".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
