# SKILL: /slice-execute (Per-Story Implementation Protocol)

## Purpose
Implement a single PRD story following the proof plan from the premortem.
Fail-closed: missing inputs → STOP, not guess.

## When to use
- When implementing any PRD story (replaces ad-hoc implementation)
- Called per-story during slice work

## Inputs (must open)
- **Premortem**: `reviews/premortems/<STORY-ID>_premortem.md` — if missing, run `./plans/scaffold_premortem.sh <ID>` and fill it first
- **Prior postmortems**: `artifacts/story/<prior-story>/postmortem.md` — read section 8 (Next-Story Startup Note) for carry-forward constraints
- `specs/CONTRACT.md`
- `specs/DESIGN_PATTERNS.md` §0 (Principles — apply throughout)
- `plans/prd.json` — the target story
- Existing code in `scope.touch` files

## Task

### 0) Hard Gate — Premortem STOPLIGHT

Open `reviews/premortems/<STORY-ID>_premortem.md`. Read §10 (STOPLIGHT).
Run `./plans/premortem_gate.sh <STORY-ID>`.

- Any failure from `./plans/premortem_gate.sh <STORY-ID>` → STOP. Fix the premortem first.
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

### 0A) Trading-System Implementation Lens

Before writing code, confirm all three statements are true:

- This implementation cannot create avoidable loss through incorrect orders, widened risk,
  blocked reductions, duplicate actions, stale state, or fail-open behavior.
- This implementation will not silently block valid profit through false rejects, unnecessary
  restrictions, bad intent classification, delayed actions, or degraded signal handling.
- This is still the simplest fail-closed implementation that satisfies the premortem, contract,
  and expected edge. If a safer or simpler implementation is found during coding, stop and
  record it as a decision or blocker instead of improvising.

If any statement is not proven, STOP and resolve it through the premortem/decision path before
continuing. Record the block explicitly (`needs_human_decision=true` in `plans/prd.json` when
scope/decision clarity is missing, or output a NO-GO blocker reason in this step artifact).

### 1) Implement Enforcement

For each AT in the story's `enforcing_contract_ats[]`:
1. Read the proof plan (premortem §6)
2. Implement the enforcement point
3. Follow fail-closed patterns:
   - Uncertain → restrict (`ReduceOnly`, not `Active`)
   - Unknown intent → classify as OPEN for gating (apply OPEN restrictions; if OPEN is not permitted, block)
   - Latch on bad event, clear only on explicit reconciliation

Safety-critical AT = any AT that can open or add risk, block a valid reduction, change permission or trading mode, affect reconciliation correctness, or affect order dispatch.

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
- `loss_mode.drift_metric` — copy from premortem §7; verify `worst_case` and `fail_closed_cap` still accurate post-implementation and update if not

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
- At least one case from the premortem §5 (wrong impl gate) — the tightened AT

This forces convergence: any agent implementing the gate must pass the same table.

### 5) Resolve Ambiguity with Behavioral ATs

For any ambiguity identified in the premortem (§4 open decisions, §5 wrong impl gate):
- Add a behavioral AT (golden vector row or property test)
- The AT must distinguish correct from wrong implementation
- If contract text/AT registration must change:
  - If `specs/CONTRACT.md` is in the story `scope.touch`, update it and run the required contract gates.
  - If it is not in scope, do not widen scope ad-hoc. Set `needs_human_decision=true`, record owner + target slice, and stop for owner direction.

### 6) Add Observability

For every reject/latch/gate path:
- Structured log with `tracing` including context
- Reason code in the reject path
- Diagnostic info for debugging

## Hard Gate: Mechanical Verification (Implementation Step)

Before declaring the implementation step ready for the workflow `implement` receipt: `./plans/verify_mechanical.sh` must pass.
Any failure = not done.

`./plans/verify_mechanical.sh` is a partial mechanical check: it confirms compileability and validates PRD metadata only for stories that already have `passes=true`.
It does NOT prove the current in-flight story's new enforcement point or `implementation_tests[]` mapping.
Use targeted tests plus the full story review loop for story-specific proof.

## Workflow Verification Handoff (Required Before Final Done/Pass)

This skill covers the implementation step only; it does not replace self-review, external review, resolution, or pass gating.
See `specs/WORKFLOW_CONTRACT.md` §6 and `docs/PRD_STORY_WORKFLOW.md` for the canonical full story loop.

`verify_mechanical.sh` is necessary but not sufficient for story completion. The full story loop still requires:
- self-review artifacts for a single `REVIEW_SHA`
- external review cycles and resolution artifacts for that same `REVIEW_SHA`
- `./plans/verify.sh quick` during iteration and after review-fix checkpoints
- `./plans/verify.sh full` before pass-flip
- `plans/prd_set_pass.sh` for the `passes=true` mutation only after full verify is green

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
- [ ] Premortem §5 wrong impls are blocked by tightened ATs?
- [ ] Decision record written for any non-obvious design choice?
- [ ] No implementation path can create avoidable loss through wrong dispatch, widened risk, blocked reduction, duplicate action, stale-state execution, or fail-open behavior?
- [ ] No implementation path can silently block valid profit through false reject, unnecessary restriction, delayed valid action, or degraded signal handling?
- [ ] I checked for a simpler safer implementation and did not keep extra complexity without justification?

## Output

- **A) Gate Result** — GO (premortem STOPLIGHT was GREEN/YELLOW-addressed) or NO-GO (blocked)
- **B) Unified Diff** — summary of changes made
- **C) Commands + Evidence** — test commands run and their output
- **D) Decision Record** — any design choice not specified in contract, justified by DESIGN_PATTERNS §0
- **E) Post-Run STOPLIGHT + Debt Register** — updated stoplight after implementation

## Hard Constraints

- No scope widening — only implement what the story claims
- No refactoring beyond the story's `scope.touch`
- Fail-closed for missing inputs — if the premortem is missing, mechanically invalid, or RED, stop
- No paper compliance — `passes=true` requires real proving tests, not just test existence
- No silent error drops in production code
