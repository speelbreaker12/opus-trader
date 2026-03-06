# Reconciliation Handoff — S5

---

## Role

You are a reconciliation operator auditing already-passing stories for contract-proof integrity.

Operational rule:
- If a story cannot pass the same gates required today, it must not remain `passes=true`.

---

## Source Of Truth

| Document | Use |
|---|---|
| `reviews/reconciliations/PROTOCOL.md` | Required. Execution order, gates, handoff cadence. |
| `reviews/reconciliations/REFERENCE.md` | Anti-patterns, escalation, troubleshooting. |
| `plans/step_prompts/recon/<step>.md` | Step-specific prompt details. |
| `specs/WORKFLOW_CONTRACT.md` | Workflow contract authority when in doubt. |
| `plans/wf_step.sh` | Canonical step order and receipt enforcement. |
| `plans/verify.sh` | Canonical verify entrypoint. |
| `plans/prd_set_pass.sh` | Canonical pass-flip gate. |

---

## Quick Orientation

- Stories: `plans/prd.json` via `.items[] | select(.id=="S5-000")`
- Premortems: `reviews/premortems/S5-000_premortem.md`
- Slice artifacts: `reviews/reconciliations/S5/`
- Story artifacts: `artifacts/story/S5-000/`
- Receipts: `.wf/receipts/S5-000/`

---

## Slice Context

| Field | Value |
|---|---|
| Slice ID | S5 |
| Integration branch | recon/S5-000 |
| Stories in scope | S5-000 |
| Started | 2026-03-05 |
| Last updated | 2026-03-05 |

---

## Story Status Matrix

Symbols: `·` not started · `→` in progress · `✓` done · `✗` blocked

| Story | Step 1 preflight | Step 2 implement | Step 3 self_review | Step 4 cycle1 | Step 5 fix | Step 6 cycle2 | Step 7 resolution | Step 8 verify_full | Step 9 pass | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| S5-000 | → | · | · | · | · | · | · | · | · | — |

---

## Per-Story Work Log

### S5-000

#### Hard Evidence Summary

| Gate | Status | Artifact |
|---|---|---|
| Preflight | IN_PROGRESS | `artifacts/story/S5-000/preflight/audit.md` |
| Self-review | — | — |
| External C1 | — | — |
| External C2 | — | — |
| Verify full | — | — |

#### Step Log

```text
Step 1 · preflight
Status: IN_PROGRESS
Receipt: (pending)
Gate: (pending)
Artifacts: artifacts/story/S5-000/preflight/audit.md, reviews/premortems/S5-000_premortem.md
Notes: Premortem filled, audit written. STOPLIGHT: GREEN. All 5 ATs have TRIP+NON-TRIP.
Friction:
```

---

## Process Backlog

| # | Step | Rule | Severity | Fix target | Owner | Status |
|---|---|---|---|---|---|---|

---

## HANDOFF (Required)

### Stopped At

- Story: `S5-000`
- Step: `preflight`
- Status: Premortem filled, audit written, receipt pending
- HEAD at stop: `5a7500988aa1fe4801cc07ccbffec755a67ec60c`

### What Happened (2-5 bullets)

- Scaffolded and filled `S5-000_premortem.md` with full clause audit, proof plan, fail-closed sweep
- Wrote preflight audit with AT proof table — STOPLIGHT: GREEN, all 5 ATs PASS
- Created HANDOFF.md for S5 slice

### Must Read First (ordered)

1. `artifacts/story/S5-000/preflight/audit.md` — AT proof table and stoplight
2. `reviews/premortems/S5-000_premortem.md` — full premortem with proof plan
3. `reviews/reconciliations/PROTOCOL.md` — execution order authority

### Next Steps (exact commands/actions)

1. `WF_RECON_MODE=1 plans/wf_step.sh S5-000 preflight` — stamp receipt
2. `WF_RECON_MODE=1 plans/wf_step.sh S5-000 implement` — R1 read-only baseline
3. Continue through pipeline

### Open Decisions / Blockers

- none

### Resume Command

```bash
/reconcil
plans/wf_step.sh S5-000 --status
```

---

## Mandatory Cadence

After **every** `wf_step.sh` attempt (pass or fail), update:
1. Matrix symbol for that step.
2. Step block `Status / Receipt / Gate / Artifacts`.
3. Blocker details (command + exit + first failing line) if blocked.
4. HANDOFF footer (`Stopped At`, `What Happened`, `Must Read`, `Next Steps`, `Resume`).

No story is exempt from handoff updates.
