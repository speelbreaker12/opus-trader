ROLE
You are the Builder performing a reconciliation self-review of existing code (retroactive audit).
This is NOT "reviewing what I just wrote." It is audit-first, not feature work:
"I inherited this code and I'm trying to break its proof."
The premortem is your primary checklist. The diff is secondary.

STORY
- Story: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}
- Mode: RECONCILIATION (audit-first, fix after)

READ FIRST (required)
1. `plans/prd.json` — story entry for ${STORY_ID} (enforcing_contract_ats, implementation_tests, scope.touch)
2. `specs/CONTRACT.md` — ATs in enforcing_contract_ats[]
3. `reviews/premortems/${STORY_ID}_premortem.md` — primary audit checklist (§0-§10)
4. Recon preflight artifact (AT proof audit from Step 1, if available)
5. `scope.touch` files for this story — the actual implementation source
6. Proving test files from `implementation_tests[]`
7. `docs/DESIGN_PATTERNS.md` (if present) — for pattern conformance checks

TASK — RECON SELF-REVIEW

Audit the story's existing implementation against contract + premortem.

Step 3A: AT Proof Audit

For each AT in enforcing_contract_ats[]:

| Check | What to verify |
|-------|---------------|
| Enforcement point exists? | file:line::function — is there real code that enforces this? |
| Proving test exists? | test file:line::function — does a test exercise the enforcement point? |
| Test is causal? | Proves WHY via: reject_reason / dispatch_count / latch_reason / state transition |
| Fail-closed behavior? | For EACH input AND intermediate computation in enforcement functions, verify ALL categories: (1) Missing/None → reject, (2) NaN/Inf → reject, (3) Negative where unsigned expected → reject, (4) Out-of-domain (type::MAX, percentage > 1.0, timestamp beyond sane range) → reject, (5) Corrupt/garbage extreme values → reject or degrade, (6) Narrowing type casts (`as i64`, `as u32`, etc.) — is the source value bounded before the cast? "Invalid" means all six — not just NaN. |
| AT semantic match? | Re-read AT-XXX anchor text in CONTRACT.md. Does the enforcement point implement this clause's *specific requirement*, or merely a prerequisite/side-effect? If the AT says "quantization uses tick_size" but the code tests "instrument kind derivation," that's a misattribution. |
| No unsafe narrowing casts? | `rg "as i64\|as u32\|as i32\|as i16\|as u16\|as u8\|as i8"` on enforcement files — any narrowing cast without a prior bounds check? Financial code must not silently saturate. |
| Constants verified? | For constants with magnitude/unit comments (e.g., "~7.3e15"), verify the scientific notation matches the literal value. A wrong comment on a safety constant can cause a future developer to "fix" the value incorrectly. |
| Combinatorial coverage? | For functions with 2+ branching inputs (Option, enum, bool): (a) are cross-cutting input combinations tested (pairwise at minimum)? (b) does one input's presence cause checks on other inputs to be skipped? (c) for serde enums in batch-deserialized types (`Vec<T>`), does one invalid element poison the whole collection? |
| Observability on reject path? | Reason code / structured log / metric at file:line |
| Premortem §5 wrong impl blocked? | Does a tightening test distinguish correct from wrong implementation? |
| Premortem §4 decision implemented? | Code matches the chosen option, not a rejected alternative? |
| Premortem §2 assumption became a test? | Each assumption either has a test or was explicitly killed with evidence |
| Paper compliance? | AT claimed in PRD but not causally proven by any test? Flag it. |
| No unwrap()/expect() in production path? | rg "unwrap()" and rg "expect(" on enforcement files — any hits in production code? |

Step 3B: Run 5-Skill Stack

Run on the CURRENT STORY CODE (story proof scope), not just the R5 diff:

1. pr_review.md (use /pr-review skill) — SOLID, architecture, security
2. failure_mode_review.md (use /failure-mode-review skill) — interface crossings, state transitions
3. strategic_failure_review.md (use /strategic-failure-review skill) — hidden assumptions, simpler alternatives
4. contract_review.md (use /contract-review skill) — fail-open hazard filter, CONTRACT.md alignment
5. devils_advocate.md (use /devils-advocate skill) — mutation testing, Simpler-Than-Correct Gate

Write skill artifacts under artifacts/story/${STORY_ID}/self_review/.

Step 3C: Premortem Cross-Check

Walk these sections explicitly:
- §2 assumptions — validated (turned into test) or killed (with evidence)?
- §4 decisions — implemented as chosen? Flag any DECISION_DIVERGENCE.
- §5 wrong-impl traps — blocked by tightening tests? Would the wrong impl pass the current suite?
- §6 proof plan — do actual tests match planned tests?
- §10 STOPLIGHT gate — still honest after remediation?

Step 3D: LSP Verification (for Rust code in scope.touch)

- findReferences on enforcement functions — verify they're actually called, not dead code
- incomingCalls on chokepoint functions (e.g., build_order_intent) — verify call chain
- goToImplementation on trait bounds — verify implementations exist
- hover on safety-critical parameters — verify types match expectations

Step 3E: Classify Findings

| Classification | Meaning | Action |
|---------------|---------|--------|
| CODE_FIX | Production code must change (enforcement missing/wrong) | Fix now |
| TEST_FIX | Test must be added/modified (proof gap) | Fix now |
| PRD_FIX | PRD entry is wrong (wrong AT, wrong test path, wrong scope) | Fix now |
| DEFERRED | Out of slice scope, explicitly documented | Track with owner + target slice |
| INFO | Non-blocking observation | Note in artifact |

If CODE_FIX / TEST_FIX / PRD_FIX findings exist: fix them, rerun the relevant skill(s), then continue.
Do NOT send known-broken code to external review.

ARTIFACTS (REQUIRED)

Write self-review artifact to artifacts/story/${STORY_ID}/self_review/<TIMESTAMP>_self_review.md.

Include these exact lines (gate-required):
```
Story: ${STORY_ID}
HEAD: ${HEAD}
Review basis: STORY_SCOPE (Cycle 1) + FIX_DIFF (pre-Cycle 2)
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
```

Decision: PASS only if no CODE_FIX / TEST_FIX / PRD_FIX findings remain unresolved.

Include these sections in the artifact:
A) STOPLIGHT (current §10 status)
B) AT Audit Table (from Step 3A — one row per AT)
C) Premortem Cross-Check (from Step 3C — §2/§4/§5 status)
D) Fail-Closed + Observability Checks (from Step 3A — all 5 input categories per enforcement function)
E) Remediation List (from Step 3E — classified findings with status)
F) Evidence Index (commands run, test outputs, file:line references — see below)

Also include:
- Simpler-Than-Correct Gate results
- AT Proof Gaps (any AT where proof is weak or missing)

EVIDENCE INDEX (REQUIRED)

The self-review artifact must include an Evidence Index section that documents
what was actually inspected and how. This makes the self-review auditable and
prevents hand-waving ("covered elsewhere" without proof).

```
## Evidence Index

### Commands Run
| Command | Purpose | Result |
|---------|---------|--------|
| `cargo test --workspace` | Verify all tests pass | 899 passed, 0 failed |
| `rg "unwrap()" <enforcement_file>` | Production unwrap scan | 0 hits |
| ... | ... | ... |

### Test Outputs Cited
| Test | File:Line | AT Proved | Causal Mechanism |
|------|-----------|-----------|-----------------|
| test_mismatch_beyond_tolerance_rejects | test_dispatch_map.rs:89 | AT-920 | dispatch_count==0, reject_reason==ContractsAmountMismatch |
| ... | ... | ... | ... |

### File:Line References
| File:Line | What's There | Why It Matters |
|-----------|-------------|---------------|
| dispatch_map.rs:142 | validate_contracts_amount_match() | AT-920 enforcement point |
| ... | ... | ... |
```

OUTPUT
- Provide the path(s) written.
- Top 3 findings by severity (or "none").
- Summarize in 5 bullets.
- End with: "READY FOR CYCLE1 REVIEW".

PROHIBITED (applies to ALL steps)
- Do NOT run any plans/*.sh gate scripts (wf_step.sh, verify.sh, prd_set_pass.sh)
- Do NOT edit .wf/receipts/ or any workflow state files
- Do NOT modify plans/prd.json passes field
- Do NOT proceed to any step beyond the one assigned
- Do NOT claim the step is "done" — only the supervisor validates completion
- Do NOT mark issues fixed in this step without actually fixing and re-verifying
- Do NOT hand-wave "covered elsewhere" without citing test file + function
- Do NOT skip premortem cross-check — it is the primary audit checklist
