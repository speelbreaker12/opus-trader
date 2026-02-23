ROLE
You are an external reviewer performing a reconciliation audit of existing code for ${STORY_ID}.
Do NOT write the review yourself — dispatch via review_logged.sh.
Audit only. No code edits.
This is a Cycle 1 review: prove or disprove that the implementation is contract-compliant.

STORY
- Story: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}
- Mode: RECONCILIATION — story already implemented, auditing retroactively

SCOPE — STORY PROOF SCOPE (NOT DIFF, NOT WHOLE SLICE)

Review story scope, not the whole slice:

1. PRD story entry (enforcing_contract_ats, implementation_tests, acceptance)
2. Premortem for the story (reviews/premortems/${STORY_ID}_premortem.md) — especially §4 decisions, §5 wrong-impls, §2 assumptions
3. Recon preflight artifact (AT proof audit from Step 1)
4. `scope.touch` files — read and audit the code directly
5. Proving tests for the story's ATs
6. Contract clauses / ATs cited by the story (specs/CONTRACT.md, relevant sections only)
7. Adjacent enforcement code only if needed for causality (e.g., PolicyGuard/WAL/TLSM)

Do NOT ask the reviewer to "review the git diff" — there may be no diff.
Do NOT ask the reviewer to review the entire slice — too broad, too noisy.

TASK — EXTERNAL CONTRACT-PROOF AUDIT

Run external review:
```
./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}
```
or
```
./plans/review_logged.sh ${STORY_ID} --tool opus --files "<scope.touch files>"
```
or
```
./plans/review_logged.sh ${STORY_ID} --tool kimi --files "<scope.touch files>"
```

When framing the review context, tell the reviewer:

  "This is a retroactive contract-proof audit of existing implementation.
   Review the story proof scope: ATs, enforcement points, proving tests, premortem.
   Focus on: Conflicts, Missing Proofs, paper compliance, fail-open paths, weak causal tests."

PRIORITIES (reviewer must check, in this order)

1. **Contract alignment (AT-by-AT)** — Does each claimed AT have a real proving test? Does it prove causality (dispatch_count, reject_reason, latch_reason), not just existence? **Re-read the AT anchor text in CONTRACT.md** — does the enforcement point implement the clause's specific requirement, or merely a prerequisite/side-effect?
2. **Paper compliance detection** — AT claimed in PRD but not causally proven? implementation_tests[] points to real tests? No fake "passes" logic?
3. **Fail-closed behavior** — For EACH input AND intermediate computation in enforcement functions: (1) Missing/None → reject? (2) NaN/Inf → reject? (3) Negative where unsigned expected → reject? (4) Out-of-domain (type::MAX, percentage > 1.0, timestamp beyond sane range) → reject? (5) Corrupt/garbage extreme values → reject or degrade? (6) Narrowing type casts (`as i64`, `as u32`) — is the source value bounded before the cast? "Invalid" means all six — not just NaN. No warn-and-continue? No silent fallback?
4. **Premortem conformance**:
   - §4 decisions — implemented as chosen? If diverged, justified or silent drift?
   - §5 wrong impls — blocked by tightening tests? Would the wrong impl pass the current suite?
   - §2 assumptions — turned into tests? Or explicitly killed with evidence?
5. **Observability** — Reason code / structured log / metric on reject/degrade/latch paths?
6. **Pattern conformance** — Gates use real quantities, state transitions explicit, small blast radius (including deserialization: strict serde enums in batch-deserialized types must not poison sibling elements), idempotent where retries happen?
7. **Combinatorial coverage** — For functions with 2+ branching inputs (Option, enum, bool): are cross-cutting input combinations tested? Does one input's presence cause checks on other inputs to be skipped? For constants with magnitude comments, does the comment match the literal value?
8. **Mechanical verification** — Run `./plans/verify_mechanical.sh`. Any FAIL = P1. Checks: (a) tests compile, (b) enforcement points have production callers, (c) implementation_tests[] entries exist as real test functions.

ESCALATION TO WIDER REVIEW

Default to story-scope. Escalate beyond it only if:
- Story touches a shared primitive (PolicyGuard, TradingMode, WAL, dispatch gate)
- Reviewer finds a pattern bug likely repeated elsewhere
- Modified module is used by multiple stories (blast radius risk)

PROOF GRAPH (when --proof-graph is active)

A proof_graph.json skeleton has been generated at:
  artifacts/story/${STORY_ID}/<tool>/proof_graph.json

For each AT entry in the `ats[]` array, fill the `at_verdict` block:
  "at_verdict": {
    "verdict": "PROVEN_INTEGRATED|PROVEN_UNIT|WEAK_PROOF|CLAIMED_NOT_PROVEN|UNTESTED_ENFORCEMENT|WRONG_IMPL_UNBLOCKED|INVALID_REF|FAIL_OPEN_RISK|MISSING|DEFERRED",
    "severity": "BLOCKING|HARDENING|INFO",
    "rationale": "One sentence explaining your verdict"
  }

Also fill `enforcement.status` and `wiring.status` if you have evidence.
Leave other fields as-is (they are pre-populated from PRD + premortem).

Rules:
- DEFERRED = "I cannot evaluate this AT" (not "it's fine")
- If uncertain, use the MORE RESTRICTIVE verdict (fail-closed)
- Do NOT modify schema_version, head_sha, or story_meta

OUTPUT
- Write review file(s) to artifacts/story/${STORY_ID}/codex/ (or opus/ or kimi/).
- Review MUST include: `Review basis: STORY_SCOPE (Cycle 1)`
- Include:
  - STOPLIGHT verdict
  - Conflicts list (if any)
  - Missing proofs list
  - Premortem divergences (if any)
  - Minimal next actions (smallest-first — order by effort, not severity)
- Classify findings: BLOCKING / MEDIUM / LOW.
- If clean: include explicit statement: "No blocking findings; reconciliation proof is causal and sufficient."
- End with: "READY FOR FIX".

PROHIBITED
- Do NOT hand-write review artifacts
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT edit any source code — review only
- Do NOT write review markdown by hand — use review_logged.sh
- Do NOT review only the git diff if no code changed yet
- Do NOT skip PRD/AT mapping or premortem in review framing
- Do NOT claim the step is "done" — only the supervisor validates completion
