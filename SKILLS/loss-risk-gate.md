# SKILL: /loss-risk-gate (Trading Loss / Profit-Block Gate)

## Purpose
Detect whether a proposed or implemented change can create avoidable loss, silently block valid profit, widen risk, or preserve unnecessary complexity in an autonomous crypto options trading system.

This skill does **not** replace contract review or AT proof audit.
It is a specialized economic-safety gate.

## When to use
- On every PR that touches risk, dispatch, reconciliation, position state, intent classification, market-data freshness, permissions, or fail-closed logic
- Before `passes=true`
- After `/slice-execute` and before merge
- On suspicious commits that touch safety-critical paths

## Inputs (must open)
- `reviews/premortems/<STORY-ID>_premortem.md`
- `specs/CONTRACT.md`
- `plans/prd.json` (story entry)
- `git diff --base <integration-branch>` for PR review, or `git show <commit>` for commit review
- Files changed in the diff
- Relevant tests for changed enforcement points
- Prior postmortem for this story/slice if present

## Hard Gate
If the premortem is missing, RED, or mechanically invalid → STOP and return `NO-GO`.
If the story changes safety-critical behavior and there is no causal proof, return `NO-GO`.

## Task

### 1) Risk-surface classification
For each changed file / function, classify whether it can:
- Open or add risk
- Block a valid reduction
- Dispatch or suppress orders
- Change trading mode / permission / latch state
- Affect reconciliation correctness
- Depend on freshness / cache / retry / restart behavior
- Convert a real quantity into a proxy decision

### 2) Loss-risk audit
Answer with file:line evidence:
- Can this change create avoidable loss through wrong dispatch, widened exposure, duplicate action, stale-state execution, reconciliation drift, or fail-open behavior?
- Are there missing guards for None / stale / NaN / Inf / contradictory / partial-state inputs?
- Can a normal-operation path bypass the intended restriction?

If yes to any, mark `LOSS_RISK_BLOCKING`.

### 3) Profit-block audit
Answer with file:line evidence:
- Can this change silently block valid profit through false rejects, unnecessary restrictions, degraded signal interpretation, delayed valid action, or incorrect intent classification?
- Does the system reject safely **and** specifically, or does it over-block because uncertainty is being handled too crudely?

If yes to any, mark `PROFIT_BLOCK_BLOCKING`.

### 4) Simpler-safer alternative audit
Ask:
- Is there a simpler fail-closed design that satisfies the same contract?
- Did the implementation add moving parts, hidden coupling, or statefulness that increases the error surface without improving capital protection?
- Is there a safer place to enforce this rule closer to the true risk boundary?

If a materially simpler / safer design exists, mark:
- `BLOCKING` if current design creates economic risk in normal operation
- `HARDENING` if current design is contract-safe but unnecessarily fragile

### 5) Proof quality audit
For every safety-critical AT touched by the diff:
- Enforcement point exists?
- TRIP test exists?
- NON-TRIP test exists?
- Golden vector exists if the gate is safety-critical?
- Test proves causality via `dispatch_count`, `reject_reason`, `latch_reason`, `mode_transition`, or equivalent?
- Premortem §5 wrong implementation is explicitly blocked?

Any missing item for a safety-critical path = blocker.

### 6) Observability audit
For each reject / degrade / latch path:
- Structured log exists?
- Reason code exists?
- Metric / counter exists?
- Enough diagnostic context to debug a missed trade or prevented trade?

Silent capital-protection logic or silent profit-block logic = blocker.

## Required Output

### A) Verdict
`GO | NO-GO`

### B) Trading Lens
`PASS | BLOCKING | HARDENING`

### C) Economic Risk Findings
For each finding:
- Type: `LOSS_RISK_BLOCKING | PROFIT_BLOCK_BLOCKING | HARDENING | INFO`
- Why it matters economically
- Exact file:line evidence
- Smallest safe fix

### D) Safety-Critical Proof Table
| AT | Enforcement point | TRIP | NON-TRIP | Wrong impl blocked? | Causal proof? | Verdict |
|----|-------------------|------|----------|----------------------|---------------|---------|

### E) Simpler-Safer Alternative
- Current design:
- Simpler/safer alternative:
- Why current was rejected or must be fixed:

### F) Final gate rule
Return `NO-GO` if any finding shows:
- avoidable loss risk,
- silent valid-profit block in normal operation,
- fail-open behavior,
- missing causal proof on a safety-critical gate,
- or a wrong implementation that is easier than the correct one and still survives.

## Constraints
- No production edits in this skill
- No guessing; if you cannot prove safety, it is not safe
- Optimize for capital protection first, expected edge preservation second, simplicity third
- Prefer the smallest fix that removes the economic risk without widening scope
