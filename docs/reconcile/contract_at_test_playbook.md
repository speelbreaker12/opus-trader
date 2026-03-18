# Contract → AT → Test Playbook

## Purpose

Prevent agent divergence on contract implementation. Agents converge on what's
**tested**, not what's **written**. This playbook ensures every normative contract
clause has a corresponding AT with a proving test before implementation begins.

## When to Use

- Before implementing any new slice or story
- When two agents have diverged on the same contract spec
- When auditing existing implementation for coverage gaps
- After contract changes that add or modify normative clauses

## Step 1: Extract Normative Clauses

Open `specs/CONTRACT.md`. For each section in scope:

1. Extract every MUST / MUST NOT clause
2. Ignore MAY / SHOULD (informational)
3. Record the clause ID (§X.Y.Z) and abbreviated text

**Output**: Clause inventory table.

## Step 2: Map Clauses to ATs

For each clause, find the corresponding AT(s) in CONTRACT.md:

| Clause § | AT(s) | Coverage | Gap? |
|----------|-------|----------|------|
| §1.4.2.1 | AT-225, AT-910 | Partial — covers basic reservation but not per-instrument | YES |

Mark gaps: clauses with no AT, or ATs that don't cover the full clause.

## Step 3: AT Quality Audit

### 3.1 Wrong-Implementation Test

For each AT, ask:

> "What wrong implementation would also pass this AT?"

Examples:
- AT tests total reservation but not per-instrument → wrong impl: single global counter
- AT tests rejection but not the reason code → wrong impl: reject for the wrong reason
- AT tests happy path only → wrong impl: silently skip error paths

### 3.2 Causality Proof

Each AT must prove causality via at least one of:
- `dispatch_count` (0 vs 1)
- `reject_reason` (specific code)
- `latch_reason` (specific code)
- `cortex_override` value

### 3.3 Composition Check

For any two or more ATs that interact (e.g., reservation + exposure limit,
staleness + mode transition):
- Require a combined AT that tests the interaction
- Or explicitly document why the interaction is safe without a combined test

**Output**: AT quality table with ADEQUATE / TOO-COARSE markings.

## Step 4: Build Proof Plan

For each AT, map the full chain:

```
AT-NNN → Enforcement Point → Proving Test(s) → TRIP? → NON-TRIP?
```

Rules:
- Safety-critical ATs require TRIP + NON-TRIP
- Each test must prove causality (see step 3.2)
- Tests must be in `implementation_tests[]` in the PRD

## Step 5: Resolve Ambiguity

### 5.1 Agent Choice Markers

For any behavior not specified by the contract:
- Explicitly mark as "implementation choice" (not a contract requirement)
- Examples: internal data structure, algorithm choice, log format

Do NOT add ATs for implementation choices. Do NOT treat them as contract requirements.

### 5.2 Behavioral ATs for True Ambiguity

For genuinely ambiguous contract clauses:
- Write a behavioral AT (golden vector or property test)
- The AT must distinguish correct from wrong
- Register in CONTRACT.md before implementation

## Step 6: Composition Analysis

If the slice has 2+ interacting clauses:
1. List the interaction pairs
2. For each pair, verify combined behavior is tested
3. If not, add a composition AT

Examples:
- Reservation + exposure limit: what happens when both are near their caps?
- Staleness + mode transition: does stale data correctly trigger mode change?
- Idempotent reservation + cancellation: does cancel-then-re-reserve work?

## Step 7: Gate Decision

- **GO**: All clauses have ATs, all ATs are ADEQUATE or have tightening plans,
  proof plan is complete, no unresolved ambiguities
- **NO-GO**: Any clause lacks an AT without explicit deferral, any AT is
  TOO-COARSE without a fix plan, unresolved ambiguities remain

## Exemptions

- **Policy/certification stories**: No enforcement_point or enforcing_contract_ats
  required (these are process stories, not implementation)
- **Stories with empty `enforcing_contract_ats`**: Skip AT mapping (but consider
  whether ATs should be added)

## Appendix A: Wrong-Implementation Examples

| AT Claim | Wrong Impl That Passes | Fix |
|----------|----------------------|-----|
| "Reservation blocks OPEN when exceeded" | Global counter instead of per-instrument | Add per-instrument AT |
| "Stale feed rejects OPEN" | Rejects with wrong reason code | Assert specific `reject_reason` |
| "Mode latches on bad event" | Latches but doesn't persist across restart | Add persistence/WAL test |
| "Idempotent reservation" | Accepts duplicate but double-counts | Assert reservation amount unchanged on replay |

## Appendix B: Composition Examples

| Interaction | Combined AT | Why Needed |
|-------------|-------------|-----------|
| Reservation + Exposure Limit | AT: reserve near limit, then new OPEN | Tests that both gates fire correctly together |
| Staleness + Mode Transition | AT: stale feed during mode change | Tests that staleness check uses correct mode threshold |
| Idempotent Reserve + Cancel | AT: cancel then re-reserve same ID | Tests that cancel clears the reservation correctly |
