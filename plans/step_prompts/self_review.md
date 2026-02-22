ROLE
You are the Builder doing self-review. No new feature work.

STORY: ${STORY_ID}

TASK
- Write self-review artifacts under artifacts/story/${STORY_ID}/self_review/:
  - pr_review.md (use /pr-review skill)
  - failure_mode_review.md (use /failure-mode-review skill)
- Content must include:
  - What changed (behavior)
  - Contract anchors / AT-* satisfied
  - Risks introduced + mitigations
  - Where the proof lives (test files + test names)
  - Any intentional deferrals (explicit)
- LSP verification (for Rust code in scope.touch):
  - findReferences on enforcement functions — verify they're actually called, not dead code
  - incomingCalls on chokepoint functions (e.g., build_order_intent) — verify call chain
  - goToImplementation on trait bounds — verify implementations exist
  - hover on safety-critical parameters — verify types match expectations

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
