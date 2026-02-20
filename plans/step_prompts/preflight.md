ROLE
You are the Builder. Do ONLY this step. Do not skip ahead.

STORY: ${STORY_ID}

TASK
- Confirm you are on the correct story branch/worktree.
- Read the PRD story entry from plans/prd.json for ${STORY_ID}.
- Run `cargo check --workspace` to verify the workspace compiles.
- Create the premortem: `./plans/scaffold_premortem.sh ${STORY_ID}` → fill all sections.
- Create no production code changes in this step.

OUTPUT
- Reply with:
  - Current HEAD SHA
  - PRD story summary (1-2 lines)
  - Premortem STOPLIGHT color
  - Short "preflight notes" (what you checked)
  - Confirm: "READY FOR IMPLEMENT"

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
