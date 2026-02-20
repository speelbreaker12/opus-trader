ROLE
You are the Auditor performing retroactive self-review. No new feature work.
This is RECONCILIATION mode — the story already has passes=true. You are auditing retroactively.

STORY: ${STORY_ID}

TASK — 5-SKILL REVIEW STACK + LSP VERIFICATION
Write self-review artifacts under artifacts/story/${STORY_ID}/self_review/:

1. pr_review.md (use /pr-review skill) — SOLID, architecture, security
2. failure_mode_review.md (use /failure-mode-review skill) — interface crossings, state transitions
3. strategic_failure_review.md (use /strategic-failure-review skill) — hidden assumptions, simpler alternatives
4. contract_review.md (use /contract-review skill) — fail-open hazard filter, CONTRACT.md alignment
5. devils_advocate.md (use /devils-advocate skill) — mutation testing, simpler-than-correct gate

Framing: "retroactive audit of existing code" — focus on what might have been missed the first time.

LSP VERIFICATION (for Rust code in scope.touch):
- findReferences on enforcement functions — verify they're actually called, not dead code
- incomingCalls on chokepoint functions (e.g., build_order_intent) — verify call chain
- goToImplementation on trait bounds — verify implementations exist
- hover on safety-critical parameters — verify types match expectations

Content must include:
- What the story implements (behavior)
- Contract anchors / AT-* satisfied
- Risks found during audit + mitigations (existing or needed)
- Where the proof lives (test files + test names)
- Any gaps found vs blind premortem predictions

OUTPUT
- Provide the path(s) written.
- Summarize in 5 bullets.
- End with: "READY FOR CYCLE1 REVIEW".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
