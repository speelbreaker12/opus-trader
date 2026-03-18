# SKILL: /reconcil (Premortem + Reconciliation Orchestrator)

## On invocation — do this first, always

### 1) Find active handoff

```bash
ls reviews/reconciliations/*/HANDOFF.md 2>/dev/null
```

#### No HANDOFF.md found → Fresh start

- Read `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` (your role, format, and all step references are in there).
- Ask: which slice? which stories?
- Copy template → `reviews/reconciliations/<SLICE_ID>/HANDOFF.md`, fill slice/story names, begin.

#### HANDOFF.md found → Update it first, then act

**Always do this regardless of whether this is a mid-session check or end-of-session handoff:**

1. **Audit completed steps for unfilled placeholders** — scan every step block that is marked
   `COMPLETE` or `IN_PROGRESS` for any remaining `{{...}}` tokens. Fill them with real values
   from artifacts on disk or from work already done this session.

2. **Update the status matrix** at the top — make sure every story's step symbols (`·` `→` `✓` `✗`)
   reflect the actual current state.

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

---

## Source-of-truth documents (use on demand via step Reference lines)

| Document | Path |
|----------|------|
| Protocol — execution order, gates, handoff cadence | `reviews/reconciliations/PROTOCOL.md` |
| Reference — anti-patterns and worked examples | `reviews/reconciliations/REFERENCE.md` |
| Handoff template — required status matrix and footer format | `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` |
| Step-local prompts | `plans/step_prompts/recon/*.md` |

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
- Resume command: `plans/wf_step.sh <STORY_ID> --status` (check receipt chain, then run next pending step)
