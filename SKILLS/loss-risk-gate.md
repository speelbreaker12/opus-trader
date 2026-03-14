# SKILL: /loss-risk-gate (Trading Loss / Profit-Block Gate)

## Purpose
Detect whether a proposed or implemented change can create avoidable loss, silently block valid profit, widen risk, or preserve unnecessary complexity in an autonomous crypto options trading system.

This skill does **not** replace contract review or AT proof audit.
It is an advisory economic-safety review.
The mechanically enforced workflow gate is the Trading Risk Hard Gate in premortem schema v2, validated by `plans/premortem_gate.sh`.

## When to use
- On every PR that touches risk, dispatch, reconciliation, position state, intent classification, market-data freshness, permissions, or fail-closed logic
- Before `passes=true` or merge when you want an explicit economic-safety review verdict for a safety-critical diff
- After `/slice-execute` when a second trading-safety read is warranted
- On suspicious commits that touch safety-critical paths

## Inputs (must open)
- `reviews/premortems/<STORY-ID>_premortem.md`
- `specs/CONTRACT.md`
- `plans/prd.json` (story entry)
- `git diff --base <integration-branch>` for PR review, or `git show <commit>` for commit review
- Files changed in the diff
- Relevant tests for changed enforcement points
- Prior postmortem for this story/slice if present

## Review stop conditions
If the premortem is missing, RED, or mechanically invalid, return `NO-GO`.
If the story changes safety-critical behavior and there is no causal proof, return `NO-GO`.
This is a reviewer verdict, not a separate workflow hook; the fail-closed workflow enforcement lives in `plans/premortem_gate.sh`.

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
For each question, answer: `YES | NO | UNKNOWN` + one-sentence reason + proof (contract clause, enforcement file, test/artifact). `UNKNOWN` = treat as `YES`.

- Can this change create avoidable loss through wrong dispatch, widened exposure, duplicate action, stale-state execution, reconciliation drift, or fail-open behavior?
- Are there missing guards for None / stale / NaN / Inf / contradictory / partial-state inputs?
- Can a normal-operation path bypass the intended restriction?
- Does the design remain correct under bad inputs, retries, partial failures, exchange/API errors, replay, restart, and reconciliation?

If yes (or unknown) to any, mark `LOSS_RISK_BLOCKING`.

### 3) Profit-block audit
Same format: `YES | NO | UNKNOWN` + reason + proof. `UNKNOWN` = treat as `YES`.

- Can this change silently block valid profit through false rejects, unnecessary restrictions, degraded signal interpretation, delayed valid action, or incorrect intent classification?
- Does the system reject safely **and** specifically, or does it over-block because uncertainty is being handled too crudely?

If yes (or unknown) to any, mark `PROFIT_BLOCK_BLOCKING`.

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

> **Format**: Express verdict and trading lens as labeled inline values on a single line — label and value together, e.g. `**Verdict**: GO` and `**Trading Lens**: BLOCKING`.

### A) Verdict
`**Verdict**: GO` or `**Verdict**: NO-GO`

### B) Trading Lens
`**Trading Lens**: PASS` or `**Trading Lens**: BLOCKING` or `**Trading Lens**: HARDENING`

Derivation: `BLOCKING` if any finding is `*_BLOCKING`. `HARDENING` if no blocking findings but fragility noted. `PASS` otherwise. Verdict is `NO-GO` when Trading Lens is `BLOCKING`.

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

### F) Pre-gate confirmation
Before applying the gate rule, confirm all three:
1. This change cannot create avoidable loss through incorrect orders, widened risk, blocked reductions, duplicate actions, stale state, or fail-open behavior.
2. This change will not silently block valid profit through false rejects, unnecessary restrictions, bad intent classification, delayed actions, or degraded signal handling.
3. This is the simplest fail-closed design that satisfies the contract and expected edge. If a safer or simpler design was found, it is recorded as a blocker, not ignored.

If any statement cannot be confirmed with proof, return `NO-GO`.

### G) Final gate rule
Return `GO` only when all six audits produce no BLOCKING findings and every safety-critical enforcement point has causal proof.

Return `NO-GO` if any finding shows:
- avoidable loss risk,
- silent valid-profit block in normal operation,
- fail-open behavior,
- missing causal proof on a safety-critical gate,
- or a wrong implementation that is easier than the correct one and still survives.

## Constraints
- No production edits in this skill
- No guessing; if you cannot prove safety, it is not safe
- Proof, not belief: every critical claim must be tied to a specific contract clause, enforcement point, and verification artifact — not intuition or prose
- Optimize for capital protection first, expected edge preservation second, simplicity third
- Prefer the smallest fix that removes the economic risk without widening scope
