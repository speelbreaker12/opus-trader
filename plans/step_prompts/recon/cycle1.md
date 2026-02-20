ROLE
You are the Reviewer. Audit existing code (not a diff). No code edits.
This is RECONCILIATION mode — the story already has passes=true. You are auditing retroactively.

STORY: ${STORY_ID}
BASE_BRANCH: ${BASE_BRANCH}

TASK — SCOPE.TOUCH FILE REVIEW (not diff-based)
For reconciliation, the code already exists on the integration branch.
Review the story's scope.touch files directly (not a git diff).

- Read the PRD entry for ${STORY_ID} to get the scope.touch file list.
- For each scope.touch file, read and review the implementation:
  - Contract alignment: does the code implement what CONTRACT.md specifies?
  - Fail-closed behavior: are error paths restrictive (ReduceOnly, reject, block)?
  - Paper compliance: is each AT claimed actually proven with causal tests?
  - Call chain integrity: is the enforcement function called from the chokepoint?
- Run external review if available: `./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}`
- Classify findings: BLOCKING / MEDIUM / LOW.
- Flag any paper compliance: AT claimed but no causal proof.
- Flag any fail-open patterns.

OUTPUT
- Write review file(s) to artifacts/story/${STORY_ID}/codex/ (or opus/).
- Include STOPLIGHT + finding table.
- End with: "READY FOR FIX".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT edit any source code — review only
- Do NOT claim the step is "done" — only the supervisor validates completion
