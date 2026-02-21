# Story Premortem: <STORY-ID>

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story:
- Contract clause(s): §
- Acceptance tests: AT-XXX
- Touch scope: (files/crates)
- **Risk rating**: LOW / MED / HIGH
  - HIGH if touching: persistence/replay/idempotency, order placement/funds movement,
    risk limits, auth/keys, or anything that can silently weaken gates.

## 1) Clause audit (contract → AT traceability)

For each `enforcing_contract_ats` claimed by this story, find the AT in CONTRACT.md,
extract the normative clause, and classify. Skip informational clauses.

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
|    |           |                           |                        |           |
|    |           |                           |                        |           |

- [ ] Every claimed AT traced to a normative clause
- [ ] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 |           |               |                     |            |
| 2 |           |               |                     |            |
| 3 |           |               |                     |            |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 |                |           |                      |                   |
| 2 |                |           |                      |                   |
| 3 |                |           |                      |                   |
| 4 |                |           |                      |                   |
| 5 |                |           |                      |                   |

## 4) Open decisions (resolve before coding)
For each ambiguity, design choice, or spec gap:

### Decision: <short title>
- **What is ambiguous / missing**:
- **Evidence** (file + anchor or snippet):
- **Options**:
  1. Option A — Why it works; blast radius; verification
  2. Option B — Why it works; blast radius; verification
- **Chosen**: (A/B) — deciding factor:
- **Why not others**: (the key failure mode)
- **Scope control**:
  - What we're NOT doing yet (subordinate):
  - What unblocks us if this choice is wrong (elevate):

- [ ] No unresolved decisions remain
- [ ] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
|    |                      |                |                                                   |
|    |                      |                |                                                   |

- [ ] Every AT has at least one wrong impl identified
- [ ] Every wrong impl is blocked by a tightened AT or new test
- [ ] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

For each AT, map the full proof chain. Safety-critical ATs MUST have both TRIP and NON-TRIP.

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
|    |                   |                 |       |           |                 |           |
|    |                   |                 |       |           |                 |           |

Causality proof must be one of: `dispatch_count`, `reject_reason`, `latch_reason`, `cortex_override`.

If a test exists in `implementation_tests[]` but doesn't prove the AT → mark **CLAIMED-NOT-PROVEN**.
If 2+ ATs interact (e.g., reservation + exposure limit) → require a combined AT or note its absence.

**Isolation check**: Each AT should isolate exactly one clause. Ask: "If I remove or break this enforcement point, does exactly this AT fail — and no other AT covers it?" If the answer is no, the AT is either too broad (testing multiple clauses) or redundant (another AT already covers this clause).

- [ ] Every safety-critical AT has TRIP + NON-TRIP
- [ ] Every test proves causality (not just existence)
- [ ] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**:
- **Fail-closed cap on loss** (what restricts exposure):
- **Drift metric** (what tells us it's going wrong before it blows up):
- **Loss boundary** (ReduceOnly? Kill? Position limit? Time bound?):
- **Rollback plan** (how to revert if it fails):

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**:
- **If conflict with CONTRACT.md**: STOP — do not proceed until resolved
- Files with recent churn or shared ownership:
- Struct fields I'm assuming exist (verify before coding):
- State machine transitions affected:

## 9) Constraint I expect to hit

> The supervisor injects the prior postmortem path. Read section 8 (Next-Story Startup Note).

Prior Postmortem: <path or NONE>
Reused Guardrail: <one concrete rule carried forward, or NONE if no prior postmortem>

- Carry-forward from prior postmortem (paste startup note):
- What will slow me down:
- Exploit (workaround for this story):
- Smallest fix that prevents it next time:

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN / YELLOW / RED

- **GREEN**: All gates pass, proof plan complete, no unresolved ambiguities
- **YELLOW**: All gaps explicitly deferred with owner + target slice
- **RED**: Unresolved gates — do not implement

**Exit criteria (definition of done, before I start):**
- [ ] §1 clause audit: every AT traced to normative clause
- [ ] §2 all assumptions validated or killed
- [ ] §3 all failure modes have detection + mitigation
- [ ] §4 all decisions resolved, grounded in evidence
- [ ] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [ ] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [ ] §7 loss_mode documented with fail-closed boundary + rollback plan
- [ ] §8 conflict scan clean (no CONTRACT.md conflicts)
- [ ] No new debt without owner + target slice
