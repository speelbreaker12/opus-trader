# SKILL: /step-supervisor (One-Step-At-A-Time)

## Purpose
Prevent step skipping by issuing exactly one step to the builder, validating the receipt, and only then advancing. The builder never sees future steps and never runs gate scripts.

## Prerequisites
- `plans/step_supervisor.sh` (orchestration wrapper)
- `plans/wf_step.sh` (progress tracker)
- `STEP_SUPERVISOR_BASE_BRANCH` env var set (for review diff base)

## Inputs (must read)
- plans/step_supervisor.sh
- plans/wf_step.sh
- plans/prd.json (to identify story)
- artifacts/story/<ID>/… (step artifacts)

## Protocol

1) Determine the next step:
   ```bash
   ./plans/step_supervisor.sh <ID> next
   ```

2) Present ONLY that step's instructions to the builder:
   ```bash
   STEP_SUPERVISOR_BASE_BRANCH=<branch> ./plans/step_supervisor.sh <ID> prompt
   ```
   Paste the prompt to the builder verbatim. Do NOT paraphrase or add steps.

3) After builder completes the step, validate + record receipt:
   ```bash
   ./plans/step_supervisor.sh <ID> run
   ```

4) Interpret exit codes:
   - 0: step passed → go to step 1
   - 1: validation failed → tell builder what's missing, re-issue same step
   - 5: HEAD mismatch → `./plans/step_supervisor.sh <ID> reset` and restart

5) Repeat until next == "pass".

6) When next == pass:
   ```bash
   ./plans/step_supervisor.sh <ID> run
   ```
   Then manually run: `./plans/prd_set_pass.sh <ID> true`

## Hard Constraints
- **Never provide two steps at once.**
- If a step fails validation, stop and request the missing artifact.
- No "helpful shortcuts." Sequence is the product.
- Builder must NOT run any plans/*.sh gate scripts.
- Supervisor runs ALL gates, builder produces artifacts only.

## Progress Check
```bash
./plans/step_supervisor.sh <ID> status
```

## Rollback
```bash
./plans/step_supervisor.sh <ID> reset
# If passes was already flipped:
./plans/prd_set_pass.sh <ID> false
```
