ROLE
You are the Builder. Final verification only.

STORY: ${STORY_ID}

TASK
1) Ensure the working tree is clean (no uncommitted changes).
2) Run `./plans/verify.sh quick` first to catch obvious issues.
3) Then run `./plans/verify.sh full` for the complete verification suite.
4) If verify fails, fix the issues and re-run until it passes.
5) Confirm the current HEAD matches the HEAD in review artifacts.
6) Ensure artifacts/verify/<run>/verify.meta.json exists with mode=full and head_sha == current HEAD.
7) Report any failures exactly (no hiding, no silent retries).

OUTPUT
- Verify run path
- Commands run + exit codes
- Key PASS evidence lines
- Current HEAD SHA
- Any failures (if none, say "none")
- End exactly with: READY FOR VERIFY_FULL GATE

PROHIBITED
- Do NOT run prd_set_pass.sh or flip passes=true
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT edit code after verification in this step (if verify fails, fix then re-verify)
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
