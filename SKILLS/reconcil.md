# SKILL: /reconcil

## What this skill does

Manages the full lifecycle of a reconciliation session. Behavior adapts based on when it is invoked.

## On invocation — always do this sequence

### 1) Find active handoff

```bash
ls reviews/reconciliations/*/HANDOFF.md 2>/dev/null
```

---

### 2) Route based on state

#### No HANDOFF.md found → Fresh start

- Read `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` (your role, format, step references).
- Ask the user: which slice? which stories?
- Copy template → `reviews/reconciliations/<SLICE_ID>/HANDOFF.md`, fill slice/story names.
- Begin Step 1 (preflight) for the first story.

#### HANDOFF.md found → Update it first, then act

**Always do this regardless of whether this is a mid-session check or end-of-session handoff:**

1. **Audit completed steps for unfilled placeholders** — scan every step block that is marked
   `COMPLETE` or `IN_PROGRESS` for any remaining `{{...}}` tokens. Fill them with real values
   from artifacts on disk or from work already done this session.

2. **Update the status matrix** at the top:
   - Run `plans/recon_scoreboard.sh <SLICE_ID>` to generate `SCOREBOARD.md`/`SCOREBOARD.json`.
   - Paste the `SCOREBOARD.md` table into the Story Status Matrix section (or link it).
   - Keep reconciliation PATH sources deterministic:
     - Prefer `evidence_ledger.json` when present (JSON-first).
     - If JSON cannot yield GREEN/YELLOW (invalid/unusable), rely on markdown `PATH:` fallback.
     - Keep markdown ledgers with `PATH: GREEN|YELLOW` as the first line for prompt compatibility.

3. **Rewrite the HANDOFF section** at the bottom — always overwrite it with the current position:
   - Stopped at: current story + step
   - What happened: 2–5 bullets summarising this session's work
   - Must read first: the 2–3 artifacts a cold-start agent needs most
   - Next steps: exact actions (commands, not descriptions)
   - Resume command

4. **Then continue or stop:**
   - If context is healthy → resume work from where you are, using the step's `Reference:` line
     to find the governing doc section if needed.
   - If context is nearly full → stop after writing the HANDOFF. The filled handoff IS the output.

### 3) During execution (mandatory cadence)

After each wf_step attempt (pass or fail), immediately update handoff before running the next command:
1. Story matrix symbol for that step.
2. Step block `Status / Receipt / Gate` + key artifact paths.
3. For blocked steps, command + exit code + first failing line.
4. For external review steps (`cycle1`, `cycle2`), record per-tool outcomes:
   command, exit code, `timed_out` true/false, artifact path, and sidecar present/absent.

---

## Hard rule

Do not improvise the process. Every step block in the HANDOFF has a `Reference:` line pointing
to the exact section of the governing doc. Read that section if you are unsure how to run the step.

For the canonical mapping between `wf_step.sh` steps and reconciliation phases (R1–R7), always
use the table in `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 as the single source of truth.

---

## Two-agent mode (recommended for medium/high-risk stories)

If running with operator/executor separation:
- Operator skill: `SKILLS/recon_operator.md`
- Executor skill: `SKILLS/recon-executor.md` (or equivalent executor prompt)

Operator owns external reviews and all gate decisions. Executor runs step commands and emits strict
step closeout blocks only.

When users ask for supervised reconciliation, delegate to `/recon_operator` for the run orchestration
and use this skill for handoff/scoreboard hygiene.

Operator runs should use `plans/recon_operator_run.sh` as the default command entrypoint.
