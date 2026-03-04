# Reconciliation Reference

> Use this for anti-patterns, escalation, and examples.
> For execution steps and gates, see [PROTOCOL.md](PROTOCOL.md).

---

## 1) Top Anti-Patterns (High Signal)

### 1. Paper Enforcement
Guard exists with tests but has zero production callers.
- Detection: wiring audit and caller-trace validation.
- Risk: false confidence; runtime safety absent.

### 2. Diff-Only Cycle 1 Review
Cycle 1 review scoped only to changed lines.
- Detection: require story-scope basis and pre-existing citations.
- Risk: vacuous reconciliation.

### 3. Fake Citations
`file:line` points to comments/helpers, not enforcement/test logic.
- Detection: citation validation and manual spot checks.
- Risk: poisoned downstream evidence.

### 4. Missing Debt Mapping
`DEFERRED` finding without debt-register entry.
- Detection: debt schema + gap mapping validation.
- Risk: silent backlog loss.

### 5. Weak Proof Treated As Proven
Test checks `is_err()` but not causal reason/guard.
- Detection: causal proof requirements (reject reason, latch, count, transition).
- Risk: wrong implementation can pass tests.

### 6. Single-Prompt External Review
Running only one prompt style.
- Detection: manifest/combo checks.
- Risk: systematic blind spots.

### 7. Skipping Cycle 2 Preconditions
Running cycle2 before self-review proof is complete.
- Detection: gate checks on receipts and self-review artifacts.
- Risk: unresolved regressions pass through.

### 8. Blanket Merge Conflict Resolution
Applying blanket `--theirs`/`--ours` on workflow/prompt files.
- Detection: diff inspection and targeted conflict resolution.
- Risk: silent workflow regressions.

### 9. Handoff Drift
Step executed but handoff not updated.
- Detection: compare receipts vs handoff status blocks.
- Risk: context loss and repeated work.

### 10. Premortem Bypass
Reconciling without valid premortem.
- Detection: readiness gate.
- Risk: ad-hoc audit with missing expected failure model.

---

## 2) Escalation Rules

### P0 At Any Stage
- Emit explicit blocker and stop forward progression.
- Record blocker in handoff with command, exit code, and failing line.
- Resume only after fix and gate re-run.

### Proof Ambiguity
- Treat as blocking until causal proof is explicit.
- Prefer adding/strengthening tests over narrative justification.

### Missing Artifact
- Fail closed.
- Do not substitute prose for missing machine artifact when gate expects structured data.

### Conflicting Guidance
Use precedence:
1. `specs/WORKFLOW_CONTRACT.md`
2. `plans/wf_step.sh` / `plans/prd_set_pass.sh`
3. `reviews/reconciliations/PROTOCOL.md`

---

## 3) Worked Example Patterns

### Causal TRIP Example (Good)
- Trigger bad input.
- Assert explicit reject reason and no dispatch.

### Causal NON-TRIP Example (Good)
- Trigger valid input.
- Assert explicit successful transition and expected dispatch behavior.

### Weak Test Example (Bad)
- Only asserts generic failure without showing which guard caused it.

---

## 4) Handoff Hygiene

Handoff is required for every story and every step attempt.

Required fields to keep current:
- Step status and receipt path
- Gate result and key artifact paths
- Blocker diagnostics (if any)
- HANDOFF footer (`Stopped at`, `What happened`, `Must read`, `Next steps`, `Resume command`)

If context is low, writing an accurate HANDOFF is the output.

---

## 5) Quick Troubleshooting

### `cycle1` blocked
- Check evidence ledger readiness.
- Check review artifacts + sidecars.
- Validate review basis/citations.

### `cycle2` blocked
- Confirm self-review gate artifacts exist and match HEAD.
- Confirm manifest mode and required combinations.

### `pass` blocked
- Run `./plans/prd_set_pass.sh <STORY_ID> true` and use exact failing check.
- Validate verify artifacts and receipt chain for current HEAD.

### Handoff mismatch
- Run `plans/wf_step.sh <STORY_ID> --status` and reconcile with HANDOFF.md.

---

## 6) Metrics (Operational)

Track per story:
- wall-clock duration by step
- blocker count and unblock time
- number of external findings (cycle1/cycle2)
- reopen loops (fix -> cycle2 -> fix)
- handoff freshness (receipts vs handoff consistency)

Use these to reduce friction without weakening gates.
