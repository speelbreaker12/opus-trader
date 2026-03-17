# SKILL: /recon-operator

## What this skill does

Runs reconciliation in a two-agent pattern:
- `operator` supervises, validates, and records evidence.
- `executor` runs workflow steps and produces artifacts.

Use this when you want a fail-closed audit trail for one story.

## Role split (hard rule)

`operator` owns:
- step sequencing and gate decisions
- receipt validation
- external reviews (`codex`, `sonnet`, `kimi`, `gemini`)
- ledgers (timing, receipt, failure, deltas)

`executor` owns:
- executing step commands
- producing step artifacts
- reporting exact closeout answers

`executor` must not run external reviewer CLIs unless operator explicitly delegates.

## One-story run setup

Set once:

```bash
STORY_ID="Sx-yyy"
SLICE_ID="Sx"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="reviews/reconciliations/${SLICE_ID}/experiments/${STORY_ID}-operator-${RUN_TS}"
mkdir -p "$RUN_ROOT"
```

Create required ledgers:

```bash
cat > "$RUN_ROOT/STEP_TIMING_LEDGER.md" <<'EOF'
# Step Timing Ledger

| Step | Start (UTC) | End (UTC) | Duration(s) | Retries | Result |
|---|---:|---:|---:|---:|---|
EOF

cat > "$RUN_ROOT/RECEIPT_LEDGER.md" <<'EOF'
# Receipt Ledger

| Step | Receipt Path | SHA256 | Exit | Notes |
|---|---|---|---:|---|
EOF

cat > "$RUN_ROOT/FAILURE_LOG.md" <<'EOF'
# Failure Log

| Time (UTC) | Step | Type | Evidence | Action |
|---|---|---|---|---|
EOF

cat > "$RUN_ROOT/DELTA_LIST.md" <<'EOF'
# Delta List

- TODO
EOF
```

## Mandatory step order

Use `plans/wf_step.sh` canonical order only:
`preflight -> implement -> self_review -> cycle1 -> fix -> cycle2 -> resolution -> verify_full -> pass`

## Executor step closeout contract (must answer every step)

After each step attempt, executor must provide:

1. `What exact commands did you run?` (copy/paste)
2. `What files did you create/modify?` (paths)
3. `What is the strongest evidence you produced this step?` (1 item)
4. `What did you not do that the step asked for?` (forced admission)

If any answer is empty/hand-wavy, mark step `FAILED` and log in `FAILURE_LOG.md`.

## Operator loop (for each step)

1. Record `start_ts`.
2. Instruct executor to run step command(s).
3. Collect executor closeout block.
4. Validate receipt exists and parses:

```bash
RECEIPT_PATH=".wf/receipts/${STORY_ID}/NN_step.json"
jq . "$RECEIPT_PATH" >/dev/null
shasum -a 256 "$RECEIPT_PATH"
```

5. Append rows to:
- `STEP_TIMING_LEDGER.md`
- `RECEIPT_LEDGER.md`
- `FAILURE_LOG.md` (if any confusion/guess/skip/hallucination)

6. Gate checks:
- run artifact validators for any produced recon artifacts
- fail-closed if validation fails

## External reviews (operator-only)

Run in parallel after cycle artifacts are ready:

```bash
timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool codex --commit HEAD --timeout-seconds 180
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=240 timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool sonnet --commit HEAD --timeout-seconds 180
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=240 timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool kimi --commit HEAD --timeout-seconds 180
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=240 timeout 540 bash plans/review_logged.sh "$STORY_ID" --tool gemini --commit HEAD --timeout-seconds 180
```

Record each tool exit code and artifact path in `RECEIPT_LEDGER.md`.

## Scoreboard update

After major transitions (at minimum after `cycle1`, `cycle2`, `pass`):

```bash
plans/recon_scoreboard.sh "${SLICE_ID#S}"
```

Use generated scoreboard table as story matrix source of truth.

## Failure types (log all)

Use these exact values in `FAILURE_LOG.md`:
- `CONFUSED`
- `GUESSED`
- `SKIPPED`
- `HALLUCINATED`
- `TOOL_TIMEOUT`
- `VALIDATION_FAIL`

## End of run (non-negotiable outputs)

Required:
- `STEP_TIMING_LEDGER.md`
- `RECEIPT_LEDGER.md`
- `FAILURE_LOG.md`
- `DELTA_LIST.md`

`DELTA_LIST.md` must capture concrete workflow changes to improve throughput and reduce rework.
