ROLE
You are the Builder. Final verification only.

STORY: ${STORY_ID}

TASK
- Ensure the working tree is clean (no uncommitted changes).
- Run `./plans/verify.sh quick` first to catch obvious issues.
- Then run `./plans/verify.sh full` for the complete verification suite.
- If verify fails, fix the issues and re-run until it passes.
- Ensure artifacts/verify/<run>/verify.meta.json exists and has mode=full and head_sha == current HEAD.
- Do NOT flip passes=true.

OUTPUT
- Provide verify run path.
- Provide summary of gates (all .rc files must be 0).
- End with: "READY TO PASS".

PROHIBITED (applies to ALL steps)
- Do NOT run prd_set_pass.sh or flip passes=true
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
