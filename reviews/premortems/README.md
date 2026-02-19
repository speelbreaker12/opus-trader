# Story Premortems

## Purpose
Each story must have a filled premortem **before implementation begins**.
Replaces both the old premortem and `/slice-preflight` — single pre-implementation artifact
covering contract traceability, risk analysis, proof planning, wrong implementations,
economic risk, and open decisions.

## Naming
- `<STORY-ID>_premortem.md` (e.g., `S7-001_premortem.md`)

## Rules
- Fill the premortem from `STORY_PREMORTEM_TEMPLATE.md` before writing any implementation code.
- §0 Risk rating must be filled. HIGH stories get extra scrutiny on §7 (economic risk) and §8 (conflict scan).
- §1 (clause audit) is a hard gate: every AT must trace to a normative contract clause.
- §4 (open decisions) is a hard gate: no unresolved ambiguities before coding. Each decision must cite evidence (file + line).
- §5 (wrong implementation gate) is a hard gate: every AT must have at least one wrong impl identified and blocked.
- §6 (proof plan) is a hard gate: safety-critical ATs must have TRIP + NON-TRIP with causality proof.
- §7 (economic risk) is required for any story touching dispatch, risk, pricing, or position management.
- §8 (conflict scan): if any conflict with CONTRACT.md is found, STOP — resolve before proceeding.
- §10 STOPLIGHT must be GREEN or YELLOW-with-deferrals before `/slice-execute` proceeds.
- Revisit the premortem after implementation — update "Validated?" columns and note any failure modes that were missed.

## Scaffold
```bash
./plans/scaffold_premortem.sh <STORY-ID>
```

## Sections

| § | Section | Purpose | Gate? |
|---|---------|---------|-------|
| 0 | What we're building | Scope + risk rating | — |
| 1 | Clause audit | AT → contract § traceability | Hard gate |
| 2 | Assumptions | Force guesses into tests | — |
| 3 | Failure modes | Top 5 with detection + mitigation | — |
| 4 | Open decisions | Resolve ambiguity before coding | Hard gate |
| 5 | Wrong impl gate | Block checkbox compliance | Hard gate |
| 6 | Proof plan | AT → enforcement → TRIP/NON-TRIP | Hard gate |
| 7 | Economic risk | Loss mode + rollback | Required for HIGH |
| 8 | Conflict scan & hot zones | Invariants + file churn | Hard gate |
| 9 | Constraint | Expected friction + workaround | — |
| 10 | STOPLIGHT + exit criteria | GO/NO-GO + definition of done | — |

## Why agents diverge (and which sections prevent it)

Agents given the same contract and PRD will produce different implementations. This isn't a bug in the agents — it's a bug in the inputs. Three root causes:

### 1) Contract specifies outcomes, not design choices

The contract says "Inventory Skew adjusts `min_edge_usd`; Net Edge MUST be re-evaluated against the adjusted value." It doesn't say "call `net_edge_gate()` a second time with the adjusted input" vs "compare the output against a threshold." Both satisfy the outcome. One agent picks the lean path, another picks the explicit path.

**This is correct** — contracts should specify outcomes, not function signatures. But the degree of freedom must be resolved somewhere.

**Fix: §4 (Open decisions).** The agent must identify the design choice, cite the contract evidence, list options with blast radius, and pick one *before coding*. The decision is recorded; the next agent reads it instead of re-inventing.

### 2) PRD under-specifies boundary strictness

The contract says "missing/unparseable ⇒ reject fail-closed." But it doesn't always say "reject NaN/Inf" or "emit metrics for every gate." One agent adds systematic validation everywhere. Another does the minimum. Both pass the ATs because the ATs don't test `NaN` inputs.

**Fix: §5 (Wrong impl gate).** The agent must describe a wrong implementation that passes. "Wrong impl: skip NaN check on `delta_limit` — passes because no AT sends NaN." Then tighten: add a golden vector `{ delta_limit: NaN } → Rejected(InventorySkewDeltaLimitInvalid)`. The boundary behavior is now encoded in a test, not left to agent judgment.

### 3) Agents mirror local codebase patterns

If the codebase has result-rich gates with diagnostics, the agent adds diagnostics. If it has lean gates with configs, the agent stays lean. Same spec, different house style. This is usually fine — unless the house style conflicts with the contract.

**Fix: §8 (Conflict scan).** The agent checks "I'm following the lean pattern from crate X, but the contract requires a log with WAP + slippage on rejection — conflict." Pattern-following is fine; pattern-following that violates a MUST is not.

### Summary

| Root cause | Degree of freedom | Section that eliminates it |
|-----------|-------------------|---------------------------|
| Contract specifies outcomes not design | Multiple valid design paths | §3 Open decisions |
| PRD under-specifies strictness | Boundary behavior undefined | §4 Wrong impl gate |
| Agents mirror local patterns | House style may conflict with contract | §6 Conflict scan |

The premortem doesn't prevent divergence by adding more rules. It prevents divergence by forcing the agent to **confront the degrees of freedom before coding**, when the cost of resolving them is near zero.

## Worked Example: Inventory Skew (why premortems prevent agent divergence)

Two agents implemented the same Inventory Skew story. Both passed the ATs. Both were wrong in different ways. A premortem would have caught this before a single line of code was written.

### The problem

CONTRACT.md requires:
- "If Inventory Skew adjusts `min_edge_usd`, Net Edge **MUST** be re-evaluated against the adjusted value before dispatch."
- "Skew must tighten only for risk-increasing and loosen only for risk-reducing."
- "bias=1.0 ⇒ exactly 3 ticks" (deterministic tick shifting).

Agent A used a multiplier threshold — never compared `net_edge_usd` vs `adjusted_min_edge_usd`. Agent B validated everything was finite but used a different decision path. Both passed the existing ATs because the ATs didn't enforce the specific comparison.

### What §3 (Open decisions) would have caught

```
### Decision: How does Inventory Skew interact with Net Edge?
- **What is ambiguous**: Contract says "re-evaluate Net Edge against adjusted value"
  but doesn't specify the code path — new gate? modify existing NetEdge input? rerun?
- **Evidence**: specs/CONTRACT.md §X.Y — "Net Edge MUST be re-evaluated against
  the adjusted value before dispatch"
- **Options**:
  1. Rerun NetEdge gate with adjusted min_edge_usd — blast radius: touches
     pipeline ordering; verification: golden vector with skew active
  2. Multiplier threshold on skew output — blast radius: minimal; verification:
     unit test on multiplier. BUT: never compares net_edge vs adjusted min_edge,
     so doesn't satisfy "re-evaluate Net Edge" requirement
- **Chosen**: Option 1 — contract says "re-evaluate," not "apply threshold"
- **Why not Option 2**: violates MUST — contract requires the comparison, not a proxy
```

This forces the agent to confront the contract language before choosing an approach. Option 2 gets killed by evidence, not by a reviewer 3 days later.

### What §4 (Wrong impl gate) would have caught

```
| AT | Wrong impl that passes | Why it's wrong | Tightening |
|----|----------------------|----------------|------------|
| AT-SKEW-001 | Use multiplier threshold without comparing net_edge vs adjusted_min_edge | Bypasses the "re-evaluate Net Edge" MUST — skew could approve orders that adjusted Net Edge would reject | Add golden vector: skew adjusts min_edge above current net_edge → must reject |
| AT-SKEW-002 | Skip tick-size price adjustment, pass bias through as multiplier only | Contract requires "bias=1.0 ⇒ exactly 3 ticks" — deterministic, not approximate | Add golden vector: bias=1.0, tick_size=0.01 → limit_price shifted by exactly 0.03 |
```

The wrong implementations are **easier** than the correct ones (multiplier is simpler than re-evaluation). That's the signal. If a wrong impl is easier and passes, the ATs are too weak.

### What §6 (Conflict scan) would have caught

```
- **Invariants/gates impacted**: NetEdge gate (must accept adjusted min_edge),
  Pricer (must apply tick penalty), LiquidityGate (must log WAP + slippage)
- **If conflict with CONTRACT.md**: The "re-evaluate" requirement means pipeline
  ordering matters — Skew must run before or feed back into NetEdge
```

This catches the structural issue (pipeline ordering dependency) before implementation.

### The lesson

Agents diverge because **degrees of freedom exist**. Every time the contract says "adjust X" without the premortem forcing "how exactly?", two agents will invent two mechanisms. The premortem eliminates degrees of freedom by:

1. **§3**: Resolving ambiguity with evidence before coding (not after)
2. **§4**: Proving the ATs distinguish correct from wrong (not just "it passes")
3. **§6**: Checking invariant impact before touching code (not during review)

The golden-vector table in §4 is the strongest lever. If you can describe a wrong implementation that passes, you must tighten until it can't. This is how you stop checkbox compliance.
