# Premortem + Reconciliation Orchestrator Prompt

> **Tool-agnostic.** This prompt works with any LLM agent (Claude, Codex, Kimi, Opus, etc.).
> For Claude Code users: this is also available as `/reconcil`.

## Purpose

Historically: full orchestration spec for premortem authoring (Mode A) and reconciliation audit (Mode B).

**Current usage (v3.1)**: this file is a thin redirect. The single source of truth for
reconciliation steps and gates is:

- `/reconcil` skill (`SKILLS/reconcil.md`) for orchestration
- `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 for step mapping
- `reviews/premortems/PREMORTEM_RECON_POLICY.md` for verdicts and gates

Do **not** implement new workflows by editing this file; update the Runbook/Policy instead.

## When to use

- As a prompt stub for external tools that cannot invoke `/reconcil` directly.
- As a pointer to the governing documents and the `/reconcil` skill.

For actual execution in this repo:

- **Preferred**: run `/reconcil <STORY_ID>` (Claude Code skill).
- **Receipts**: use `plans/wf_step.sh <STORY_ID> <step>` for `preflight → implement → self_review → cycle1 → fix → cycle2 → resolution → verify_full → pass`.

---

## Dispatch Examples

### Claude Code
```
/reconcil S1-007
```

### Codex / other agents
```bash
# Substitute variables and feed as system prompt
STORY_ID=S1-007 BASE_BRANCH=feature/slice4-cherry-pick HEAD=$(git rev-parse HEAD) \
  envsubst < plans/prompts/reconcil.md | agent-run --prompt -
```

### wf_step integration (preferred)
```bash
# Preferred orchestration: /reconcil
# Preferred receipt execution:
WF_RECON_MODE=1 plans/wf_step.sh S1-007 <step>
```
