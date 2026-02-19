# Quality Gates Reference

> Compact directive lives in CLAUDE.md §Quality Gates. This file has the details.

## Scorecard Tiers

| Story risk tier | Proof | Safety | Operability |
|-----------------|-------|--------|-------------|
| **Safety-critical** (`DispatcherChokepoint`, `WAL`, `PolicyGuard`) | Required | Required | Required |
| **Structural** (`EvidenceGuard`, `AtomicGroupExecutor`) | Required | Required | — |
| **Trivial** (`StatusEndpoint`, logging, docs) | Required | — | — |

Tier is determined by `enforcement_point` in `prd.json`. If unclear, use the higher tier.

### Proof (all tiers)
- [ ] Enforcement exists (code implements the contract clause)
- [ ] AT-SCOPE: a test proves *this gate/module* owns the obligation (not deferred to nothing)
- [ ] AT-BEHAVIOR: a test proves the runtime behavior is correct
- [ ] Negative AT check: "What wrong implementation would also pass?" — if one exists, tighten the AT or add a golden vector

### Safety (safety-critical + structural tiers)
- [ ] Fail-closed for missing/invalid inputs (missing config → reject opens, not allow)
- [ ] No new bypass paths (no `unwrap_or(Active)`, no silent `Ok(())` on error)
- [ ] Explicit reason codes on every reject path
- [ ] Abuse-case tests (at least 2): NaN/Inf, missing config, boundary, retry/dedup

### Operability (safety-critical tier only)
- [ ] Diagnostics returned: key numbers + reason in structured log on reject/degrade
- [ ] Counters: allowed/rejected/degraded totals via metrics struct
- [ ] Pre-mortem documented (see §Pre-Mortem below)

## AT Taxonomy

| AT type | Purpose | Example |
|---------|---------|---------|
| **AT-SCOPE** | Proves the right gate owns the obligation | "per-instrument limit enforced in pending exposure, not deferred" |
| **AT-BEHAVIOR** | Proves runtime result is correct | "hedged portfolio: signed math allows, abs math rejects" |

Every **normative, testable** contract clause needs both types.
- Normative = MUST / MUST NOT / SHALL / NEVER or changes allowed behavior.
- Testable = you can write a deterministic test.
- Non-normative text (definitions, rationale, examples, operational guidance) does NOT need an AT.

### Clause-Level AT Isolation

Each AT must isolate exactly one contract clause. Two tests:

1. **Remove enforcement** → exactly this AT fails (not zero, not many)
2. **Two agents, same AT suite** → forced to converge on the same implementation

If removing the enforcement breaks zero ATs, the clause has no proving test.
If removing the enforcement breaks many ATs, the clause is tested by proxy — only one AT should own the obligation directly.

**Example**: BTC per-instrument exposure limit. Bad: one test checks "total portfolio under budget" (BTC failure masked by ETH headroom). Good: test checks "BTC-specific reservation at limit → rejected" — removing the per-instrument check fails exactly this test.

## Pre-Implementation AT Audit

Before coding any PRD story:

```
For each normative, testable clause:
  1. Is there a SCOPE AT proving which gate/module owns this obligation?
  2. Is there a BEHAVIOR AT that fails if the implementation is wrong?
  3. Does the BEHAVIOR AT isolate this clause? (Negative AT: "What wrong impl passes?")
  4. If any answer is NO → write the missing AT before implementing.
```

## Wrong-Implementation Gate

For every AT in a story, answer:

> "What wrong implementation would still pass this test?"

If a plausible wrong implementation passes:
- Tighten the AT to isolate the correct behavior, OR
- Add a golden vector row that distinguishes correct from wrong, OR
- Add a property invariant that the wrong implementation violates

## Golden Vectors

For pure gates (input → output), maintain vector files at `specs/vectors/<gate>.toml`.

**Tier 1 — Required:** inventory skew, net edge, liquidity gate, pricer, margin headroom, global exposure budget.

**Tier 2 — Recommended:** pending exposure (sequence vectors), TLSM transitions.

Every vector row must justify itself: "This row catches [describe wrong implementation]." If you can't write that line, delete the row — it isn't pulling its weight.

Rows must be boundary-heavy:
- Thresholds (just below / at / just above)
- Sign flips (positive / zero / negative)
- Saturation (max / min / overflow)
- Missing/invalid (None / NaN / Inf / empty)

## Property Invariants

For each safety-critical gate, define properties that must always hold:
- **Monotonicity**: tightening never loosens under risk-increasing
- **Floors/ceilings**: min_edge never goes negative, bias_ticks ≤ max
- **Fail-closed**: missing limit/input → reject opens
- **Determinism**: same input → same output

Test with boundary sweeps or small randomized input sets.

## Pre-Mortem Format

Max 10 bullets. Each must include:
- **Failure mode** — what goes wrong
- **Detection** — how you'd know (metric, log, alert)
- **Mitigation** — how the code prevents or contains it

If a failure mode has no mitigation, it is debt — log with target slice.

## Economic Risk (safety-critical tier only)

```
loss_mode:
  worst_case: "If this fails open, max loss = [describe]"
  fail_closed_cap: "How the code caps loss: [describe]"
  drift_metric: "What metric tells us we're drifting: [describe]"
```

## Stoplight + Debt

| Stoplight | Meaning | Gate behavior |
|-----------|---------|---------------|
| **GREEN** | All scorecard items satisfied, no known debt | `prd_set_pass.sh` proceeds |
| **YELLOW** | All required items satisfied, known debt logged with target slice | `prd_set_pass.sh` proceeds |
| **RED** | Required item missing or unmitigated | `prd_set_pass.sh` BLOCKED |

Debt in `prd.json`:
```json
{
  "stoplight": "YELLOW",
  "debt": [
    { "item": "No idempotent reservations", "target": "PX-1" }
  ]
}
```

YELLOW with untracked debt (no target slice) = RED.

## Builder/Auditor Separation

| Role | Responsibility |
|------|---------------|
| **Builder** | Implements, writes tests, produces pre-mortem and abuse-case tests |
| **Auditor** | Tries to find fail-open paths, missing proofs, wrong-impl-passes-AT gaps |

Auditor verdict is **binding**: RED = builder must fix before `prd_set_pass.sh`.

In current workflow: codex reviews (story loop steps 6-7) serve as auditor.

**Anti-pattern:** Builder sees RED, marks "won't fix" without justification, proceeds.

**Correct pattern:** Builder fixes or documents why it's YELLOW (with target slice) → re-runs auditor → auditor confirms → proceed.
