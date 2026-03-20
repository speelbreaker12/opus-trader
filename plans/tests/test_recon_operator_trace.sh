#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRACE_SCRIPT="$ROOT/plans/recon_trace.sh"
REPORT_VALIDATOR="$ROOT/plans/validate_recon_step_report.py"
ARTIFACT_VALIDATOR="$ROOT/plans/validate_recon_artifact.sh"
RUN_CARD_TEMPLATE="$ROOT/plans/recon_run_card_template.md"
STEP_REPORT_SCHEMA="$ROOT/specs/schemas/recon/recon_step_report.schema.json"
TRACE_RECEIPT_SCHEMA="$ROOT/specs/schemas/recon/recon_trace_receipt.schema.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$TRACE_SCRIPT" ]] || fail "missing executable trace script: $TRACE_SCRIPT"
[[ -f "$REPORT_VALIDATOR" ]] || fail "missing report validator: $REPORT_VALIDATOR"
[[ -x "$ARTIFACT_VALIDATOR" ]] || fail "missing artifact validator: $ARTIFACT_VALIDATOR"
[[ -f "$RUN_CARD_TEMPLATE" ]] || fail "missing run card template: $RUN_CARD_TEMPLATE"
[[ -f "$STEP_REPORT_SCHEMA" ]] || fail "missing step report schema: $STEP_REPORT_SCHEMA"
[[ -f "$TRACE_RECEIPT_SCHEMA" ]] || fail "missing trace receipt schema: $TRACE_RECEIPT_SCHEMA"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans/tests" "$repo/specs/schemas/recon"
git -C "$tmp_dir" init -q repo
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config core.hooksPath /dev/null

cp "$TRACE_SCRIPT" "$repo/plans/recon_trace.sh"
cp "$REPORT_VALIDATOR" "$repo/plans/validate_recon_step_report.py"
cp "$ARTIFACT_VALIDATOR" "$repo/plans/validate_recon_artifact.sh"
cp "$RUN_CARD_TEMPLATE" "$repo/plans/recon_run_card_template.md"
cp "$STEP_REPORT_SCHEMA" "$repo/specs/schemas/recon/recon_step_report.schema.json"
cp "$TRACE_RECEIPT_SCHEMA" "$repo/specs/schemas/recon/recon_trace_receipt.schema.json"
chmod +x "$repo/plans/recon_trace.sh" "$repo/plans/validate_recon_artifact.sh"

echo "seed" > "$repo/seed.txt"
(
  cd "$repo"
  git add -A
  git commit -q -m "seed"
)

story_id="S9-001"
slice_id="S9"
run_root="$repo/reviews/reconciliations/$slice_id/experiments/${story_id}-operator-test"

(
  cd "$repo"
  plans/recon_trace.sh init "$story_id" "$slice_id" --run-root "$run_root" >/dev/null
)

for f in RUN_CARD.md STEP_TIMING_LEDGER.md RECEIPT_LEDGER.md FAILURE_LOG.md DELTA_LIST.md step_timing.jsonl failures.jsonl; do
  [[ -f "$run_root/$f" ]] || fail "missing run artifact: $run_root/$f"
done

head_sha="$(git -C "$repo" rev-parse HEAD)"
created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

wf_receipt="$repo/.wf/receipts/$story_id/00_preflight.json"
mkdir -p "$(dirname "$wf_receipt")"
cat > "$wf_receipt" <<EOF
{"schema_version":"review_receipt.v1","head_commit":"$head_sha","created_at":"$created_at","story_id":"$story_id","review_basis":"STORY_SCOPE","review_basis_cycle":1,"tool":"codex","prompt_style":"enriched","phase_equivalent":"R3","citations":[],"findings":[],"finding_counts":{"P0":0,"P1":0,"P2":0,"INFO":0}}
EOF

step_report="$repo/reports/00_preflight.step_report.json"
mkdir -p "$(dirname "$step_report")"
cat > "$step_report" <<EOF
{
  "schema_version": "recon_step_report.v1",
  "head_commit": "$head_sha",
  "created_at": "$created_at",
  "story_id": "$story_id",
  "step_name": "preflight",
  "step_index": 0,
  "status": "PASS",
  "exit_code": 0,
  "commands_run": [
    "plans/premortem_ready.sh $story_id",
    "plans/wf_step.sh $story_id preflight"
  ],
  "files_changed": [
    "reviews/reconciliations/$slice_id/${story_id}_reconciliation.md"
  ],
  "strongest_evidence": "Premortem gate passed and preflight receipt exists at .wf/receipts/$story_id/00_preflight.json",
  "not_done": "none",
  "artifacts": [
    ".wf/receipts/$story_id/00_preflight.json"
  ]
}
EOF

(
  cd "$repo"
  python3 plans/validate_recon_step_report.py "$step_report" >/dev/null
  plans/validate_recon_artifact.sh recon_step_report "$step_report" >/dev/null
)

start_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
sleep 1
end_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

(
  cd "$repo"
  plans/recon_trace.sh record-step "$story_id" preflight \
    --run-root "$run_root" \
    --start "$start_at" \
    --end "$end_at" \
    --status PASS \
    --attempt 1 \
    --kind gate \
    --retries 0 \
    --log-path "$wf_receipt" \
    --wf-receipt "$wf_receipt" \
    --step-report "$step_report" \
    --notes "preflight completed" >/dev/null
)

trace_receipt="$(find "$run_root/receipts" -maxdepth 1 -type f -name '*_preflight*_trace_receipt.json' | head -n 1 || true)"
[[ -n "$trace_receipt" && -f "$trace_receipt" ]] || fail "missing generated trace receipt"
(
  cd "$repo"
  plans/validate_recon_artifact.sh recon_trace_receipt "$trace_receipt" >/dev/null
)

grep -Fq "| preflight | $start_at | $end_at |" "$run_root/STEP_TIMING_LEDGER.md" \
  || fail "step timing ledger row missing"
grep -Fq "| preflight | $wf_receipt |" "$run_root/RECEIPT_LEDGER.md" \
  || fail "receipt ledger row missing"
grep -Fq '"step":"preflight"' "$run_root/step_timing.jsonl" \
  || fail "step_timing.jsonl entry missing"

(
  cd "$repo"
  plans/recon_trace.sh log-failure "$story_id" preflight \
    --run-root "$run_root" \
    --type TOOLING \
    --evidence "fixture failure event" \
    --action "blocked until report corrected" >/dev/null
  plans/recon_trace.sh add-delta --run-root "$run_root" --item "Add stricter report prompts for executor." >/dev/null
)

grep -Fq "TOOLING" "$run_root/FAILURE_LOG.md" || fail "failure log entry missing"
grep -Fq '"category":"TOOLING"' "$run_root/failures.jsonl" || fail "failures.jsonl entry missing"
grep -Fq "Add stricter report prompts for executor." "$run_root/DELTA_LIST.md" || fail "delta list entry missing"

bad_report="$repo/reports/01_bad.step_report.json"
cat > "$bad_report" <<EOF
{
  "schema_version": "recon_step_report.v1",
  "head_commit": "$head_sha",
  "created_at": "$created_at",
  "story_id": "$story_id",
  "step_name": "preflight",
  "step_index": 0,
  "status": "PASS",
  "exit_code": 0,
  "commands_run": ["plans/wf_step.sh $story_id preflight"],
  "files_changed": ["none"],
  "strongest_evidence": "n/a",
  "not_done": "none"
}
EOF

set +e
(
  cd "$repo"
  python3 plans/validate_recon_step_report.py "$bad_report" >/dev/null 2>&1
)
bad_rc=$?
set -e
[[ "$bad_rc" -eq 1 ]] || fail "expected bad step report to fail with exit 1, got $bad_rc"

echo "test_recon_operator_trace.sh: ok"
