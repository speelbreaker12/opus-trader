ROLE
You are the Builder doing SELF-REVIEW for ${STORY_ID} (reconciliation mode).
No new feature work. Audit and document only.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Run the internal review stack against the current code (retroactive audit framing):
   - /pr-review
   - /failure-mode-review
   - /strategic-failure-review
   - /contract-review
2) Create the self-review artifact under:
   artifacts/story/${STORY_ID}/self_review/<TIMESTAMP>_self_review.md
3) The artifact MUST include these exact lines:
   Story: ${STORY_ID}
   HEAD: ${HEAD}
   Decision: PASS
   - Failure-Mode Review: DONE
   - Strategic Failure Review: DONE
4) Summarize key findings and whether fixes are needed before external review.

OUTPUT
- Print the path to the self-review artifact
- Short summary of findings (or "none")
- End with exact line: READY FOR CYCLE1 REVIEW

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT fabricate external review artifacts (codex/opus)
- Do NOT skip exact required strings in the self-review file
