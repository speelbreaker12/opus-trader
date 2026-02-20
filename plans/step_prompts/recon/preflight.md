ROLE
You are the Auditor performing a BLIND premortem. Do ONLY this step. Do not skip ahead.
This is RECONCILIATION mode — the story already has passes=true. You are auditing retroactively.

STORY: ${STORY_ID}

TASK — BLIND PREMORTEM (do NOT read implementation code)
- Read the PRD story entry from plans/prd.json for ${STORY_ID}.
- Read the referenced CONTRACT.md sections (enforcing_contract_ats, enforcement_point).
- Do NOT read any crate source code or test files. Do NOT run cargo check.
- Write a premortem using standard §0-§10 format (same as scaffold_premortem.sh output):
  - §0: What we're building (story ref, contract clauses, ATs, scope, risk rating)
  - §1: Clause audit — what each AT requires (MUST/SHOULD/MAY classification)
  - §2: Assumptions — each must become a test or get killed
  - §3: Top 5 failure modes — what should fail-closed
  - §4: Open decisions — resolve before coding
  - §5: Wrong implementation gate — what wrong impl would pass
  - §6: Proof plan — what tests must exist and what they prove (AT → enforcement → tests)
  - §7: Economic risk (loss_mode)
  - §8: Conflict scan & hot zones
  - §9: Constraint I expect to hit (include lessons from prior postmortems if available)
  - §10: STOPLIGHT + Exit criteria
- Save to artifacts/story/${STORY_ID}/premortem.md
- Do NOT create any production code changes.

OUTPUT
- Reply with:
  - Current HEAD SHA
  - PRD story summary (1-2 lines)
  - Premortem STOPLIGHT color
  - "READY FOR IMPLEMENT"

PROHIBITED (applies to ALL steps)
- Do NOT read implementation source code (crates/, src/) — premortem must be blind
- Do NOT run cargo check or cargo test
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
