ROLE
You are the Builder performing RECONCILIATION PREFLIGHT for ${STORY_ID}.
This is an audit step. Do NOT write production code in this step.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Read the PRD entry for ${STORY_ID} in plans/prd.json.
2) Read the referenced contract clauses / ATs in specs/CONTRACT.md.
3) Read the prior postmortem: ${PRIOR_POSTMORTEM_PATH}
   - If not NONE: read section "## 8) Next-Story Startup Note" for carry-forward constraints.
   - If NONE: no prior postmortem exists.
4) For each AT in enforcing_contract_ats:
   - identify the proving test file and test function (or mark missing)
   - check if proof is CAUSAL (reject reason, dispatch_count, latch/mode/result), not just existence
   - note proof quality: PROVEN / WEAK / MISSING / DEFERRED
5) Verify all scope.touch files exist.
6) Run: cargo check --workspace
7) Produce an AT proof audit table and a STOPLIGHT verdict for this story.

OUTPUT
- AT Proof Audit table: | AT | Test file:line | Causal? | Status | Notes |
- scope.touch file existence summary
- Contract alignment notes (including any paper-compliance risk)
- STOPLIGHT: GREEN / YELLOW / RED
- End with exact line: READY FOR IMPLEMENT

PROHIBITED
- Do NOT edit production code
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT hand-wave missing tests as "covered elsewhere" without naming exact test files
