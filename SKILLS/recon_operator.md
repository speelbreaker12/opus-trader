# SKILL: /recon_operator

## Goal

Supervise reconciliation for one story or one slice with a relay pattern:

- Operator orchestrates, validates, logs, and decides GO/NO-GO.
- Executor performs the current step work.
- External reviewer agents produce independent C1/C2 artifacts.

The operator never treats executor self-judgment as external review.

## Why this mode

Use when you need reconciliation that is:
- measurable
- resume-safe
- receipt-driven
- resistant to shortcutting

## Authority matrix

### Operator

Can:
- choose story
- create/update handoff
- create/update run card
- run prerequisite gates
- dispatch executor
- dispatch reviewers
- validate outputs
- update scoreboard
- stop workflow
- write failure/confusion logs
- write delta list

Cannot:
- count own review as external review
- waive missing artifacts
- skip receipt validation
- replace executor implementation work in `implement` / `fix`

### Executor

Can:
- run assigned step
- edit production code only in `implement` and `fix`
- create/update step artifacts
- write mandatory step report

Cannot:
- self-certify external review
- advance step without operator validation
- skip forced-admission fields
- edit production code outside `implement` / `fix`

### External reviewers

Can:
- produce independent C1/C2 review artifacts
- flag gaps/blockers

Cannot:
- resolve own findings
- replace operator gate decision

## Step chain (must not change)

`preflight -> implement -> self_review -> cycle1 -> fix -> cycle2 -> resolution -> verify_full -> pass`

Receipts: `.wf/receipts/<STORY_ID>/`

## Prerequisite gate (Mode B)

Before starting reconciliation for a story, operator must run:

```bash
plans/premortem_ready.sh <STORY_ID>
```

Must pass:
- premortem exists
- premortem gate passes
- STOPLIGHT not RED
- no AT ownership conflicts
- required context files exist

## Run setup

Primary operator entrypoint:

```bash
plans/recon_operator_run.sh [--story Sx-yyy] [--slice N] [--step preflight] [--mode A|B]
```

Invocation behavior:
- no `--story`: prefer active `reviews/reconciliations/*/HANDOFF.md` story when eligible
- otherwise: pick first eligible unreconciled story from `plans/prd.json`
- eligibility gates: `passes=true`, no `08_pass` receipt, no active conflicting run, and (Mode B) `plans/premortem_ready.sh` passes

1. Initialize run trace:

```bash
STORY_ID="Sx-yyy"
SLICE_ID="Sx"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT=".wf/trace/${STORY_ID}/${RUN_TS}-${STORY_ID}"
plans/recon_trace.sh init "$STORY_ID" "$SLICE_ID" --run-root "$RUN_ROOT"
```

`plans/recon_operator_run.sh` performs this initialization automatically when `RUN_ROOT` is omitted.

2. Ensure handoff exists and is current:
- `reviews/reconciliations/<SLICE_ID>/HANDOFF.md`
- update after every step attempt (pass or fail)

3. Refresh scoreboard:

```bash
plans/recon_scoreboard.sh "${SLICE_ID#S}"
```

## Mandatory executor step report

Executor must submit a JSON step report validated by:

```bash
python3 plans/validate_recon_step_report.py <step_report.json>
```

Must include non-hand-wavy answers for:
- exact commands
- files created/modified
- strongest evidence (one item)
- what was not done (forced admission)

If missing/hand-wavy: step = FAILED.

## Operator loop per step

1. Dispatch executor for one step.
2. Collect:
- wf receipt path
- step report JSON path
- executor closeout
3. Validate:

```bash
jq empty <wf_receipt.json>
python3 plans/validate_recon_step_report.py <step_report.json>
```

4. Record trace:

```bash
plans/recon_trace.sh record-step "$STORY_ID" <step_name> \
  --run-root "$RUN_ROOT" \
  --start <ISO8601Z> \
  --end <ISO8601Z> \
  --status PASS|FAIL|BLOCKED \
  --retries <N> \
  --wf-receipt <path> \
  --step-report <path> \
  --notes "<context>"
```

5. If confusion/guess/skip/hallucination occurred:

```bash
plans/recon_trace.sh log-failure "$STORY_ID" <step_name> \
  --run-root "$RUN_ROOT" \
  --type SEARCH|CEREMONY|CONTEXT_LOSS|TOOLING|AMBIGUITY|HALLUCINATION \
  --evidence "<proof>" \
  --action "<fail-closed action>"
```

6. Update handoff and scoreboard.

## External reviews (operator-owned)

Run external reviewers independently for C1/C2 artifacts. Example:

```bash
timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool codex --commit HEAD --timeout-seconds 180
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=240 timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool opus --commit HEAD --timeout-seconds 180
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=240 timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool kimi --commit HEAD --timeout-seconds 180
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=240 timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool gemini --commit HEAD --timeout-seconds 180
```

Do not accept executor output as external review.

## End-of-run outputs (non-negotiable)

Under `RUN_ROOT`, operator must produce:
- `RUN_CARD.md`
- `STEP_TIMING_LEDGER.md`
- `RECEIPT_LEDGER.md`
- `FAILURE_LOG.md`
- `DELTA_LIST.md`

`DELTA_LIST.md` must list concrete workflow changes for bottlenecks observed.
