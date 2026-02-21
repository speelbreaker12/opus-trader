ROLE
You are the Builder closing the review loop. No code edits.

STORY: ${STORY_ID}
HEAD: ${HEAD}

TASK
1) Read: plans/review_resolution_template.md
2) Create: artifacts/story/${STORY_ID}/review_resolution.md
3) Fill ALL placeholders with real values.
4) The file MUST include these exact lines (verbatim):
   Story: ${STORY_ID}
   HEAD: ${HEAD}
   Blocking addressed: YES
   Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
5) The file MUST include references to the actual review files (with real paths):
   - Codex cycle 1 review file: <path>
   - Codex cycle 2 review file: <path>
   - Opus review file: <path> (if applicable)
   - Self-review file: <path>
6) Include section:
   ## Finding Disposition
   (always include, even if no findings — write "No findings to disposition.")
7) Write postmortem using plans/postmortem_template.md:
   - Save to: artifacts/story/${STORY_ID}/postmortem.md
   - Required for YELLOW/RED stories and any story touching gates, TradingMode, RiskState, WAL, or replay.
   - Fill all 9 sections. Key requirements:
     - Section 1: Name ONE constraint in a single sentence + Constraint Class
     - Section 5: Describe a wrong implementation that could have passed before
     - Section 6: Rule Updates table — at least one permanent change (this is the point)
     - Section 8: Next-Story Startup Note (carry-forward constraint)
     - Section 9: Complete the checklist (all boxes checked)
   - Keep it to ~1 page. If you can't name the constraint in one sentence, it's fluff.

OUTPUT
- review_resolution.md path
- Postmortem path (if written)
- Paste the final resolution contents
- End exactly with: READY FOR RESOLUTION GATE

PROHIBITED
- Do NOT edit code/tests/PRD in this step
- Do NOT run wf_step.sh, story_review_gate.sh, prd_set_pass.sh, or verify.sh
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
