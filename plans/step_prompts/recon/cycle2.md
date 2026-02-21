ROLE
You are the Builder requesting a second external reconciliation review after fixes.
Do NOT write the review yourself.
This is a Cycle 2 review: fix-diff audit + closure verification + AT regression spot-check.

STORY
- Story: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}
- Mode: RECONCILIATION — verifying that fixes close Cycle 1 findings without regressions

SCOPE — FIX DIFF + AT REGRESSION

Cycle 2 reviews the FIXES, not the full story implementation (that was Cycle 1).

Reviewer must:
1. Review only the changes made in the fix step (git diff from pre-fix to HEAD)
2. Confirm all Cycle 1 BLOCKING findings are actually closed
3. Re-check impacted AT proofs — if a fix modified a test for AT-960, re-run mutation analysis on AT-960's full proof chain (not just the changed lines)
4. Confirm no new fail-open paths introduced by fixes
5. Run Simpler-Than-Correct Gate on any modified tests — a fix that closes one gap but opens another is the classic Cycle 2 failure mode

TASK — EXTERNAL CLOSURE VERIFICATION

GREEN PATH (Step 5 had 0 findings — no code changes):
- Allow lightweight confirmation review. Do not force fake work.
- Review the scope.touch files and confirm the Cycle 1 audit found no issues.
- Produce at least 1 review artifact confirming audit completeness.
- Include explicit statement: "RECON-CLEAN: Cycle 1 + self-review found BLOCKING=0. No fix diff to review. Audit-only reconciliation confirmed."

YELLOW/RED PATH (Step 5 made fixes — code changed):
- Full adversarial review of the fix diff.
- Re-review only the delta since Cycle 1.
- Confirm BLOCKING=0.
- Confirm no new bypasses introduced by fixes.
- Re-check impacted AT causal proofs.
- Produce review artifact(s) with full finding table.

For both paths, run at least 1 review:
```
./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}
```
or
```
./plans/review_logged.sh ${STORY_ID} --tool opus --base ${BASE_BRANCH}
```
or
```
./plans/review_logged.sh ${STORY_ID} --tool kimi --base ${BASE_BRANCH}
```

Frame the review as:
  "Cycle 2 closure verification. Review the fix diff.
   Confirm all Cycle 1 BLOCKING findings are resolved.
   Re-check impacted AT proofs for regression.
   Run Simpler-Than-Correct Gate on any modified tests."

OUTPUT
- Write review file to artifacts/story/${STORY_ID}/codex/ (or opus/ or kimi/).
- Review MUST include: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`
- Include STOPLIGHT verdict + finding table.
- Remaining BLOCKING/P1/P2 count.
- Closure status for each Cycle 1 finding (CLOSED / OPEN / NEW).
- End with: "READY FOR RESOLUTION".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT edit any source code — review only
- Do NOT hand-write review artifacts — use review_logged.sh
- Do NOT skip closure verification of prior findings
- Do NOT claim the step is "done" — only the supervisor validates completion
