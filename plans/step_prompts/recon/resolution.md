ROLE
You are the Builder closing the review loop for ${STORY_ID}.
You must create a gate-compliant review resolution artifact.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Read and use the template: plans/review_resolution_template.md
2) Create: artifacts/story/${STORY_ID}/review_resolution.md
3) The document MUST contain these exact lines:
   Story: ${STORY_ID}
   HEAD: ${HEAD}
   Blocking addressed: YES
   Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
4) The document MUST reference the actual review files with real paths:
   - Codex cycle 1 review file: <path>
   - Codex cycle 2 review file: <path>
   - Self-review file: <path>
5) Include a "## Finding Disposition" section.
   - For GREEN reconciliation (0 findings): "Reconciliation audit: no findings."
   - Otherwise: disposition every finding (FIXED or DEFERRED with rationale).
6) Write postmortem using plans/postmortem_template.md:
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
- Print the path to review_resolution.md
- Postmortem path (if written)
- Paste the final resolution contents
- End with exact line: READY FOR VERIFY_FULL

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT omit the exact required lines
- Do NOT leave placeholders (<TODO>, TBD, etc.)
