ROLE
You are the Builder fixing findings for ${STORY_ID} (reconciliation mode).
This is the only step where code/PRD/evidence edits are expected.
Work from the Step 2 Patch Plan and Cycle 1 review findings.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

READS
- Step 2 output (AT Audit Table + Step 5 Patch Plan)
- Cycle 1 review artifacts in artifacts/story/${STORY_ID}/codex/ or opus/

TASK
GREEN PATH (0 findings from both Step 2 audit AND Cycle 1 review):
- If Step 2 patch plan is empty AND cycle 1 found 0 actionable findings,
  this step passes automatically.
- Confirm: "0 findings — no fixes needed."

YELLOW/RED PATH (findings exist):
1) Work through the Step 2 Patch Plan, ordered smallest-first:
   - CODE_FIX items: fix enforcement, fail-closed paths, proof gaps
   - TEST_FIX items: add/fix TRIP/NON-TRIP tests, golden vectors, causal proof
   - PRD_FIX items: update implementation_tests[], enforcing_contract_ats[], loss_mode
2) Address all BLOCKING and MAJOR findings from Cycle 1 review.
3) For HARDENING items from Step 2: defer unless they address a contract violation.
   Document: why deferred, risk impact, owner story/slice.
4) Run: ./plans/verify.sh quick
5) Note: fixing code ESCALATES remaining steps to full review requirements.

OUTPUT
- Patch plan disposition: | # | Category | Verdict (FIXED/DEFERRED) | Evidence |
- Summary of changes made (files touched)
- verify.sh quick result (if fixes were made)
- End with exact line: READY FOR CYCLE2 REVIEW

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT mark deferred findings as fixed
- Do NOT introduce fail-open behavior to "make tests pass"
- Do NOT widen scope beyond this story unless required for correctness
