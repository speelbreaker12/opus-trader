# SKILL: /slice-execute (Per-Story Implementation Protocol)

## Purpose
Implement a single PRD story following the proof plan from the premortem.
Fail-closed: missing inputs → STOP, not guess.

## When to use
- When implementing any PRD story (replaces ad-hoc implementation)
- Called per-story during slice work

## Inputs (must open)
- **Premortem**: `reviews/premortems/<STORY-ID>_premortem.md` — if missing, run `./plans/scaffold_premortem.sh <ID>` and fill it first
- **Prior postmortems**: `reviews/postmortems/<prior-story>_postmortem.md` for stories in the same slice/crate (if any)
- `specs/CONTRACT.md`
- `specs/DESIGN_PATTERNS.md` §0 (Principles — apply throughout)
- `plans/prd.json` — the target story
- Existing code in `scope.touch` files

## Task

### 0) Hard Gate — Premortem STOPLIGHT

Open `reviews/premortems/<STORY-ID>_premortem.md`. Read §10 (STOPLIGHT).

- **RED** → STOP. Do not implement. Fix the premortem first.
- **YELLOW** → Proceed only if all gaps are explicitly deferred with owner + target slice.
- **GREEN** → Proceed.

Verify the hard gates:
- §1 (clause audit): every AT traced to normative clause
- §4 (open decisions): no unresolved decisions remain
- §5 (wrong impl gate): every AT has a wrong impl identified and blocked
- §6 (proof plan): TRIP + NON-TRIP for all safety-critical ATs
- §8 (conflict scan): no CONTRACT.md conflicts

If the premortem does not exist or has unresolved gates → STOP. Fill the premortem first.

### 1) Implement Enforcement

For each AT in the story's `enforcing_contract_ats[]`:
1. Read the proof plan (premortem §6)
2. Implement the enforcement point
3. Follow fail-closed patterns:
   - Uncertain → restrict (`ReduceOnly`, not `Active`)
   - Unknown intent → treat as OPEN (most restrictive)
   - Latch on bad event, clear only on explicit reconciliation

### 2) Add TRIP / NON-TRIP Tests

For each safety-critical AT:
- TRIP test: condition triggers guard, OPEN is blocked
- NON-TRIP test: condition absent, OPEN proceeds

Each test MUST prove causality via at least one of:
- `dispatch_count` (0 vs 1)
- `reject_reason` (specific code)
- `latch_reason` (specific code)
- `cortex_override` value

### 3) Fix PRD Mapping

Update `plans/prd.json` for the story:
- `implementation_tests[]` — add all new test functions
- `enforcing_contract_ats[]` — verify completeness
- `partial_coverage_notes` — update if any gaps remain

### 4) Golden Vectors for Critical Gates

If this story adds or modifies a safety-critical gate, create or update a golden vector table
in the test file (table-driven test with 10-30 input cases):

```rust
let vectors = [
    // (inputs..., expected_outcome, expected_reason, label)
    (skew_input_healthy, Allowed, None, "healthy skew allows"),
    (skew_input_nan_delta, Rejected, Some(DeltaLimitInvalid), "NaN delta rejects"),
    // ... 10-30 rows covering: happy path, each reject reason, boundary, NaN/Inf, missing
];
```

The golden vector table must include:
- Every reject reason variant exercised at least once
- Boundary cases (at threshold, off-by-one)
- NaN/Inf/missing for each numeric input
- At least one case from the premortem §4 (wrong impl gate) — the tightened AT

This forces convergence: any agent implementing the gate must pass the same table.

### 5) Resolve Ambiguity with Behavioral ATs

For any ambiguity identified in the premortem (§4 open decisions, §5 wrong impl gate):
- Add a behavioral AT (golden vector row or property test)
- The AT must distinguish correct from wrong implementation
- Register in `specs/CONTRACT.md`

### 6) Add Observability

For every reject/latch/gate path:
- Structured log with `tracing` including context
- Reason code in the reject path
- Diagnostic info for debugging

## Self-Check (Before Declaring Done)

For every AT claimed by this story:
- [ ] Enforcement point exists in code?
- [ ] Proving test exists?
- [ ] Test proves causality (dispatch count OR reason code)?
- [ ] AT isolates one clause (removing enforcement fails exactly this AT)?
- [ ] TRIP test exists (if safety-critical)?
- [ ] NON-TRIP test exists (if safety-critical)?
- [ ] Golden vector table exists (if safety-critical gate)?
- [ ] No `unwrap()` in production paths?
- [ ] Fail-closed on error paths?
- [ ] Decisions use real quantities, not proxies (DESIGN_PATTERNS §0.1)?
- [ ] Premortem §4 wrong impls are blocked by tightened ATs?
- [ ] Decision record written for any non-obvious design choice?

## Output

- **A) Gate Result** — GO (preflight was GREEN/YELLOW-addressed) or NO-GO (blocked)
- **B) Unified Diff** — summary of changes made
- **C) Commands + Evidence** — test commands run and their output
- **D) Decision Record** — any design choice not specified in contract, justified by DESIGN_PATTERNS §0
- **E) Post-Run STOPLIGHT + Debt Register** — updated stoplight after implementation

## Hard Constraints

- No scope widening — only implement what the story claims
- No refactoring beyond the story's `scope.touch`
- Fail-closed for missing inputs — if preflight is missing or RED, stop
- No paper compliance — `passes=true` requires real proving tests, not just test existence
- No silent error drops in production code
