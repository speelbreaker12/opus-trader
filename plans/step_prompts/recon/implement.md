ROLE
You are the Builder performing R5 REMEDIATION for ${STORY_ID}.
This is the implementation step — code and test changes are allowed here.
Fix only the gaps listed in GAP_LIST.json. No unrelated refactors.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}
- Slice ID: ${SLICE_ID}

READS (context build — mandatory before any code changes)
1. Story entry: `plans/prd.json` (scope, ATs, enforcement points)
2. R1 evidence ledger: `reviews/reconciliations/${SLICE_ID}/${STORY_ID}_reconciliation.md`
3. Gap list: `reviews/reconciliations/${SLICE_ID}/GAP_LIST.json` + `GAP_LIST.md`
4. Premortem: `reviews/premortems/${STORY_ID}_premortem.md` (§4 decisions, §5 wrong-impl, §6 proof plan)
5. Enforcement code and test files cited in the evidence ledger (verify citations are still accurate)

Reference: RUNBOOK §3 → R5 (steps 0–2: context build → remediation plan → implement)

TASK

Step 0 — Context Build:
Read all items listed under READS above. Understand each gap's AT, severity,
and what is missing before writing any code.

Step 1 — Remediation Plan (write before coding):
For each gap in GAP_LIST.json, draft:
- What file(s) to change
- What test(s) to add or modify
- Which premortem §6 proof strategy applies
Write plan to: `reviews/reconciliations/${SLICE_ID}/R5_REMEDIATION_PLAN.md`
One section per GAP-* ID with: gap description, planned change, target file:line,
expected test assertion.

Step 2 — Implement:
1. Implement code/test/observability fixes for each gap, following the plan
2. Update evidence ledger rows: GAP → FIXED, add new file:line citations
3. Generate proof graph: `python3 python/proof_graph/scaffold.py ${STORY_ID}`
4. Populate from evidence ledger verdicts/citations
5. Validate: `python3 python/proof_graph/validate.py --strict artifacts/story/${STORY_ID}/proof_graph.json`
6. Run: `./plans/verify.sh quick` + targeted tests

OUTPUT
- `R5_REMEDIATION_PLAN.md` (written before coding)
- Code changes + updated evidence ledgers
- `artifacts/story/${STORY_ID}/proof_graph.json`
- `R5_REMEDIATION_NOTES.md` (narrative: what was fixed, per gap)
- `R5_REMEDIATION_NOTES.json` (sidecar: gap_id mappings, touched files)

End with exact line: READY FOR SELF_REVIEW

HARD RULES
- Fix only listed gaps — no unrelated refactors
- Every change must map to one or more GAP-* IDs
- New tests follow premortem §6 proof plan (TRIP/NON-TRIP, causality)
- Golden vector rows must justify themselves ("This row catches [wrong impl from §5]")
- No unwrap() introduced in production paths
- Run tests before and after — no regressions

PROHIBITED
- Do NOT fix anything not in GAP_LIST.json
- Do NOT run plans/prd_set_pass.sh
- Do NOT write review artifacts manually
- Do NOT skip the remediation plan — write it before coding
