# STEP: R1 READ-ONLY AUDIT (Appendix A derived copy)

## ROLE

You are the Builder in RECONCILIATION mode running **Phase R1: read-only implementation audit**.
Do NOT write or modify production code, tests, PRD, or review artifacts in this step.

## STORY

- Story ID: `${STORY_ID}`
- Base Branch: `${BASE_BRANCH}`
- Current HEAD: `${HEAD}`
- Mode: RECONCILIATION (read-only)

## PURPOSE

Audit the already-implemented story against the premortem, contract, and PRD claims.
The **premortem is your primary audit checklist** — walk it section by section against the real code.
Find the real enforcement points, verify fail-closed behavior, verify causal proof quality, verify premortem decisions and wrong-impl tightenings, and produce a remediation plan.
No edits in this step.
This audit produces the evidence ledger consumed before the reconciliation `implement` step. Do not skip from this audit directly to `self_review`.

## READ FIRST (required)

1. **The story premortem**: `reviews/premortems/${STORY_ID}_premortem.md`
   This is your primary audit checklist. Walk §0-§8 against reality.
2. Existing R1/preflight evidence for this story, if present (for reruns/comparison)
3. Prior postmortem(s) for this slice/story (if any)
4. `specs/CONTRACT.md` (relevant clauses for this story)
5. `specs/DESIGN_PATTERNS.md` §0 (if present / used in this repo)
6. `plans/prd.json` (the story entry for `${STORY_ID}`)
   - Story lookup check: `jq -e --arg id "${STORY_ID}" '.items[] | select(.id == $id)' plans/prd.json >/dev/null`
   - AT source: `jq --arg id "${STORY_ID}" '.items[] | select(.id == $id) | .enforcing_contract_ats' plans/prd.json`
   - Scope source: `jq --arg id "${STORY_ID}" '.items[] | select(.id == $id) | .scope.touch' plans/prd.json`
7. Files listed in the premortem §0 `scope.touch`

**MISSING ARTIFACT RULE**: If any required item (4, 6, 7) is missing from the workspace
(file does not exist, story ID not found in `plans/prd.json`), immediately return:
```
GATE: NO-GO
Reason: MISSING_ARTIFACT: <filename or description>
```
Do not proceed. Do not guess or hallucinate the content of missing artifacts.

Item 5 (`specs/DESIGN_PATTERNS.md` §0) is conditional. If the file is absent in this repo/story,
note `DESIGN_PATTERNS_NOT_PRESENT` and continue.

**Item 2 (existing R1/preflight evidence) is OPTIONAL when the premortem (item 1) exists.** When
the premortem exists, it is already your primary audit checklist and prior audit artifacts add
marginal context only. If an earlier audit exists, read it for comparison. If it does not exist
and the premortem does, proceed without it.

**Item 3 (prior postmortems) is OPTIONAL.** If no postmortem exists for this story, proceed
without it. Note in output: `NO_PRIOR_POSTMORTEM`.

**PREMORTEM HARD RULE** (item 1 only): If `reviews/premortems/${STORY_ID}_premortem.md` does not exist:
- **STOP.** Output:
  ```
  GATE: NO-GO
  Reason: PREMORTEM_MISSING
  ```
  Do not proceed.
- Write the premortem first using Mode A (Premortem Authoring) before entering reconciliation.
- Do NOT guess or hallucinate premortem content. There is no surrogate or fallback path for R1.

## HARD GATE

Open the premortem §10 STOPLIGHT result before doing anything else:
- **RED**    -> STOP. Do not proceed. Report which blockers must be fixed first.
- **YELLOW** -> Proceed only if every gap is explicitly marked:
  - DEFERRED (future slice), or
  - FIX IN IMPLEMENT
- **GREEN**  -> Proceed.

If an existing preflight/audit artifact already exists for this story, check its STOPLIGHT too. The
more restrictive gate wins.

## READ-ONLY INTEGRITY CHECK

Run at the **start** of this step:
```bash
git status --porcelain > /tmp/recon_start_status_${STORY_ID}.txt
```

Run at the **end** of this step (before writing READY FOR IMPLEMENT GATE):
```bash
git status --porcelain > /tmp/recon_end_status_${STORY_ID}.txt
diff /tmp/recon_start_status_${STORY_ID}.txt /tmp/recon_end_status_${STORY_ID}.txt
```

If the diff is non-empty, the workspace was modified during a read-only step.
Report: `READ_ONLY_VIOLATION: <list of changed files>` and include it in Section A (GATE RESULT).
A read-only violation does NOT automatically mean NO-GO — the audit findings are still valid —
but the violation must be reported so the lead can investigate.

---

## TASK (READ-ONLY AUDIT)

For each AT in `enforcing_contract_ats[]` for `${STORY_ID}`:

### 1) Locate the enforcement point

- Identify the real code path that enforces the behavior.
- Record: file, line number, function/method name, and the specific guard/branch.
- Cross-reference against premortem §6 proof plan: is this the enforcement point the premortem predicted?
- If no real enforcement point exists, mark: **CLAIMED_NOT_PROVEN**

### 2) Verify fail-closed behavior

- Check how the code behaves for:
  - Missing input (None / empty / absent field)
  - Stale input (expired cache, old timestamp)
  - Invalid input (negative where positive expected, wrong type)
  - NaN / Inf / contradictory values
  - Retries / restarts / partial state (if applicable)
- Confirm behavior is reject / degrade / halt (not warn-and-continue).
- If fail-open exists, flag it clearly as **FAIL_OPEN**.
- Run: `rg "unwrap()" <enforcement_file>` — any hits in production paths?
  - Acceptable only in tests or with a documented safety comment.
  - If found in production code, flag as **UNWRAP_IN_PROD**.

### 3) Verify causal proof (tests)

- Find the test(s) that prove this AT.
- Record: test file, line number, and test function name.
- Confirm the test proves causality using one or more of:
  - `dispatch_count` (0 vs 1)
  - `reject_reason` / `reason_code` (exact variant match)
  - `latch_reason` (specific latch set)
  - State transition (RiskState / TradingMode change)
  - No-dispatch proof (dispatch_count == 0)
  - Idempotency proof (same input twice -> same output)
- If the test only proves "something happened" but not **why** or **which guard caused it**, mark: **WEAK_PROOF**
  - Example — Strong proof: test asserts `dispatch_count == 0 AND reject_reason == ContractsAmountMismatch`
  - Example — Weak proof: test asserts `result.is_err()` but doesn't verify which error or which guard caused it
- If the enforcement point exists and a test exists, but the test does not actually exercise the enforcement point (they are disconnected), mark: **UNTESTED_ENFORCEMENT**
- For safety-critical ATs:
  - Does a TRIP test exist? (triggers the guard, asserts causality)
  - Does a NON-TRIP test exist? (doesn't trigger, asserts pass-through)
  - Does a golden vector / table-driven test exist?
    - How many rows?
    - Does it cover boundary cases (at threshold, off-by-one)?
    - Does it cover NaN / Inf / missing for each numeric input?
    - Does it include at least one case from premortem §5?
  - If no golden vector exists for a safety-critical gate, mark: **MISSING_GOLDEN_VECTOR**

### 4) Verify premortem §5 wrong impls are blocked

This is the highest-value check. The premortem identified specific wrong implementations that would pass naive tests.

- For each wrong implementation in the premortem's §5 table:
  - Find the tightening test that distinguishes correct from wrong.
  - If the test exists, record: test file, test function, what it catches.
  - If no tightening test exists, mark: **WRONG_IMPL_UNBLOCKED**
  - A wrong impl that is easier than the correct impl and has no tightening test is a **P0 gap**.

### 5) Verify premortem §4 decisions were implemented as chosen

The premortem recorded explicit design decisions with a chosen option and rejected alternatives.

- For each decision in §4:
  - Was the chosen option implemented? Cite file:line.
  - If a different option was implemented, flag: **DECISION_DIVERGENCE**
  - Decision divergence is not automatically wrong — but it must be explained.
    If the code uses a better approach than the premortem chose, note it as INFO.
    If the code uses a rejected option without justification, note it as P1.

### 6) Verify premortem §2 assumptions

The premortem made assumptions that "must become a test or get killed."

- For each assumption in §2:
  - Does the predicted test exist? Record test name.
  - If the assumption was wrong, was it killed with evidence?
  - If the assumption is still relevant and has no test, mark: **ASSUMPTION_UNTESTED**

### 7) Check observability on reject/degrade paths

- For each rejection or degradation path:
  - Is there a structured log via `tracing` (warn/error level)?
  - Does the log include: reason code, relevant IDs (intent, instrument), diagnostic values?
  - Is there a metric that increments? (counter for reject events, gauge for state)
  - If a reject path is silent (no log, no metric, no reason code), mark: **SILENT_REJECT**

### 8) Check design-pattern conformance (audit only)

- Does the implementation use real quantities (not unsafe proxies)?
  - e.g., `net_edge_usd` vs a boolean flag that approximates it
- Is idempotency handled where retries are possible?
- Is state local / blast radius bounded?
- Any hidden assumptions that could become self-destructive later?
  - e.g., "this works because the cache is always fresh" — but staleness is possible

### 9) Build the remediation list (NO EDITS YET)

Classify every issue as one of:

| Classification | Meaning | When to use |
|---------------|---------|-------------|
| **CODE_FIX** | Fix in follow-up remediation work | Missing enforcement, fail-open path, unwrap in prod |
| **TEST_FIX** | Fix in follow-up remediation work | Missing TRIP/NON-TRIP, missing golden vector, weak proof |
| **PRD_FIX** | Fix in follow-up remediation work | Wrong `implementation_tests[]`, stale `enforcing_contract_ats[]` |
| **DEFERRED** | Future slice | Include owner + target slice |
| **INFO** | Non-blocking, no action required | Observations, minor style notes, "better design" ideas |

### IMPORTANT

- If you discover a "better design," do NOT redesign here. Mark it:
  - **BLOCKING** if it creates loss/safety risk (must fix now)
  - **HARDENING** if it is an improvement but not required for contract compliance (defer)
- Decision rule for BLOCKING vs HARDENING:
  - Fail-open path reachable in **normal operation** (valid inputs, standard flow) -> **BLOCKING**
  - Fail-open path requires **adversarial or out-of-spec input** to reach -> **HARDENING** (document the assumption about what is out-of-spec)
- Do not conflate "different from premortem prediction" with "wrong."
  The premortem was written before code existed. The code may have found a better path.
  Only flag divergence as a problem when the code violates the contract or is fail-open.

---

## ALLOWED COMMANDS (read-only)

```
rg / grep / cat / jq / less          (inspection)
cargo check --workspace              (compilation check)
cargo test <target>                   (verification — run, don't create)
git status / git diff / git show / git log  (inspection)
diff                                  (read-only integrity comparison)
```

### PROHIBITED COMMANDS

```
sed -i / awk (with file modification) / any write command that modifies repository files
cargo add / cargo rm                  (dependency changes)
```

---

## OUTPUT (required format)

### A) GATE RESULT

```
GATE: GO | NO-GO
Reason: <one line>
```

### B) AT AUDIT TABLE

For each AT, provide all columns:

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|

Verdict values:
- **PROVEN** — enforcement exists, test proves causality, fail-closed confirmed
- **CLAIMED_NOT_PROVEN** — no enforcement found, or enforcement exists but no causal test
- **WEAK_PROOF** — test exists but doesn't prove causality (checks existence, not cause)
- **UNTESTED_ENFORCEMENT** — enforcement point exists and test exists, but the test does not exercise the enforcement point (they are disconnected)
- **WRONG_IMPL_UNBLOCKED** — §5 wrong impl has no tightening test
- **DEFERRED** — AT not yet implemented (tracked in debt register)

### C) PREMORTEM CROSS-REFERENCE

#### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|

#### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|

#### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|

### D) DESIGN RISK NOTES

List any risks discovered:
- Fail-open paths
- Hidden assumptions (e.g., "works because X is always true" but X can be false)
- Proxy decisions (using a flag where a real quantity is needed)
- Idempotency gaps
- Blast radius concerns
- Silent reject paths (no log, no metric)

### E) REMEDIATION PLAN (ordered, smallest-first)

```
[CODE_FIX]  GAP-XXX-1: <description>
[TEST_FIX]  GAP-XXX-2: <description>
[PRD_FIX]   GAP-XXX-3: <description>
[DEFERRED]  GAP-XXX-4: <description> (owner: <who>, target: <slice>)
[INFO]      <observation>
```

Priority ordering:
1. P0 — Safety-critical AT with no enforcement or no TRIP test
2. P1 — Enforcement exists but wrong-impl tightening missing, or observability absent
3. P2 — Minor: naming mismatch, enforcement in slightly different location than predicted

### F) SCOPE CHECK

- Confirm each file in premortem §0 `scope.touch` exists
- Note any scope drift (files touched that weren't predicted, or predicted files not touched)
- Note any files that should have been in scope but weren't listed

### FINAL LINE (exact)

```
READY FOR IMPLEMENT GATE
```

---

## PROHIBITED

- Do NOT edit production code
- Do NOT edit tests
- Do NOT edit `plans/prd.json`
- Do NOT create or modify review artifacts
- Do NOT create new files in any directory
- Do NOT run `./plans/prd_set_pass.sh`
- Do NOT claim a fix was applied in this step
- Do NOT skip the premortem §10 STOPLIGHT gate
- Do NOT skip reading the premortem — it is your primary audit checklist
- Do NOT treat "different from premortem" as automatically wrong — evaluate against the contract

---

## QUALITY BAR

A good reconciliation audit:
- Cites **file:line** for every PASS claim (no "I believe it exists")
- Flags every §5 wrong impl that lacks a tightening test
- Distinguishes WEAK_PROOF from PROVEN (a test that checks "something happened" is not proof)
- Notes DECISION_DIVERGENCE without assuming it's wrong
- Produces a remediation plan that a different agent could execute without further context
- Never marks PASS on a safety-critical AT without verifying both TRIP and NON-TRIP tests
