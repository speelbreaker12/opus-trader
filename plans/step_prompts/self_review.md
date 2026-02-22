ROLE
You are the Builder doing self-review. No new feature work.

STORY: ${STORY_ID}
HEAD: ${HEAD}

TASK
1) Create a self-review artifact at:
   artifacts/story/${STORY_ID}/self_review/<TIMESTAMP>_self_review.md
2) The file MUST include these exact lines (verbatim):
   Story: ${STORY_ID}
   HEAD: ${HEAD}
   Decision: PASS
   - Failure-Mode Review: DONE
   - Strategic Failure Review: DONE
3) Run your internal review checks:
   - PR review (use /pr-review skill)
   - Failure-mode review (use /failure-mode-review skill)
   - Strategic failure review (use /strategic-failure-review skill)
4) Content must include:
   - What changed (behavior)
   - Contract anchors / AT-* satisfied
   - Risks introduced + mitigations
   - Where the proof lives (test files + test names)
   - Any intentional deferrals (explicit)
5) Summarize findings and fixes needed (if any) in the self-review artifact.

OUTPUT
- Self-review file path
- Short summary of findings (or "none")
- End exactly with: READY FOR SELF_REVIEW GATE

PROHIBITED
- Do NOT add new features or refactor unrelated code
- Do NOT run wf_step.sh, story_review_gate.sh, prd_set_pass.sh, or verify.sh
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT fabricate external review artifacts
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
