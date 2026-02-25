# SKILL: /reconcil (Premortem + Reconciliation Orchestrator)

## On invocation — do this first, always

### 1) Find active handoff

```bash
ls reviews/reconciliations/*/HANDOFF.md 2>/dev/null
```

**If HANDOFF.md exists:**
- Read it. Multiple files → pick most recently modified (or ask).
- Go to the **HANDOFF** section at the bottom.
- Follow "Next steps" exactly as written.
- Each step block has a `Reference:` line — use it if you need the governing doc for that step.
- Do NOT read all 5 source-of-truth docs upfront. Read only what the current step's Reference line points to.

**If no HANDOFF.md exists (fresh start):**
- Read `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` (your role, format, and all step references are in there).
- Ask: which slice? which stories?
- Copy template → `reviews/reconciliations/<SLICE_ID>/HANDOFF.md`, fill slice/story names, begin.

---

## Source-of-truth documents (use on demand via step Reference lines)

| Document | Path |
|----------|------|
| Index + R1 prompt (Appendix A) | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` |
| Runbook — operator instructions | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` |
| Policy — verdicts, gates, schemas | `reviews/premortems/PREMORTEM_RECON_POLICY.md` |
| Anti-patterns (26) | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` |
| Metrics + worked examples | `reviews/premortems/PREMORTEM_RECON_METRICS.md` |

---

## Hard constraints

- R1 (preflight) is READ-ONLY — no file modifications
- R5 (implement) fixes only listed gaps — no unrelated refactors
- Cycle 1 scope: STORY_SCOPE · Cycle 2 scope: FIX_DIFF + AT_REGRESSION
- Every review artifact must include the Review Basis line
- No Cycle 2 without `R5B_SELF_REVIEW_PROVEN` gate passed
- No fake citations — every file:line must contain actual enforcement/test code
- No DEFERRED without a debt register entry (schema-validated, no TBD fields)

---

## When context is running low

Fill the **HANDOFF** section of the active `HANDOFF.md` before stopping:
- Stopped at: story + step
- What happened: 2–5 bullets
- Must read first: ordered list of artifact paths
- Next steps: exact commands or actions
- Resume command: `STEP_SUPERVISOR_BASE_BRANCH=<branch> plans/step_supervisor.sh <ID> prompt --recon`
