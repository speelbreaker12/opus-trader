# SKILL: /recon-executor

## What this skill does

Executes reconciliation steps for one story under operator supervision.

This skill is command execution only. The operator owns gate decisions and external reviews.

## Hard boundaries

- Do not reorder `wf_step` phases.
- Do not mark steps complete without receipts.
- Do not run external reviewers (`codex`, `sonnet`, `kimi`, `gemini`) unless operator explicitly asks.
- If blocked or uncertain, stop and report exactly what is missing.

## Step command pattern

Use canonical step command:

```bash
plans/wf_step.sh <STORY_ID> <step_name>
```

Step order:
`preflight -> implement -> self_review -> cycle1 -> fix -> cycle2 -> resolution -> verify_full -> pass`

## Required closeout block (every step attempt)

Return this exact structure:

```text
STEP_CLOSEOUT
Commands run:
- <exact command 1>
- <exact command 2>

Files created/modified:
- <path 1>
- <path 2>

Strongest evidence:
- <single strongest artifact or command result>

Not done (forced admission):
- <what step asked that was not completed>
```

Rules:
- Never leave a section empty.
- If nothing changed, write `- none`.
- If failed, include first failing line and exit code in `Strongest evidence`.

## Receipt reporting

After each step, report expected receipt path:

```bash
.wf/receipts/<STORY_ID>/<NN_step>.json
```

If missing, explicitly state `RECEIPT_MISSING`.

## Failure behavior

If any command fails:
1. stop further commands for that step
2. report exact failing command + exit code
3. provide the closeout block
4. wait for operator instructions
