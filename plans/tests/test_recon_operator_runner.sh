#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/plans/recon_operator_run.sh"
TRACE_SCRIPT="$ROOT/plans/recon_trace.sh"
STEP_VALIDATOR="$ROOT/plans/validate_recon_step_report.py"
ARTIFACT_VALIDATOR="$ROOT/plans/validate_recon_artifact.sh"
RUN_CARD_TEMPLATE="$ROOT/plans/recon_run_card_template.md"
STEP_REPORT_SCHEMA="$ROOT/specs/schemas/recon/recon_step_report.schema.json"
TRACE_RECEIPT_SCHEMA="$ROOT/specs/schemas/recon/recon_trace_receipt.schema.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$RUNNER" ]] || fail "missing executable runner: $RUNNER"
[[ -x "$TRACE_SCRIPT" ]] || fail "missing executable trace script: $TRACE_SCRIPT"
[[ -f "$STEP_VALIDATOR" ]] || fail "missing step validator: $STEP_VALIDATOR"
[[ -x "$ARTIFACT_VALIDATOR" ]] || fail "missing artifact validator: $ARTIFACT_VALIDATOR"
[[ -f "$RUN_CARD_TEMPLATE" ]] || fail "missing run card template: $RUN_CARD_TEMPLATE"
[[ -f "$STEP_REPORT_SCHEMA" ]] || fail "missing step report schema: $STEP_REPORT_SCHEMA"
[[ -f "$TRACE_RECEIPT_SCHEMA" ]] || fail "missing trace receipt schema: $TRACE_RECEIPT_SCHEMA"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans/tests" "$repo/specs/schemas/recon" "$repo/reviews/reconciliations"
git -C "$tmp_dir" init -q repo
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

cp "$RUNNER" "$repo/plans/recon_operator_run.sh"
cp "$TRACE_SCRIPT" "$repo/plans/recon_trace.sh"
cp "$STEP_VALIDATOR" "$repo/plans/validate_recon_step_report.py"
cp "$ARTIFACT_VALIDATOR" "$repo/plans/validate_recon_artifact.sh"
cp "$RUN_CARD_TEMPLATE" "$repo/plans/recon_run_card_template.md"
cp "$STEP_REPORT_SCHEMA" "$repo/specs/schemas/recon/recon_step_report.schema.json"
cp "$TRACE_RECEIPT_SCHEMA" "$repo/specs/schemas/recon/recon_trace_receipt.schema.json"
chmod +x "$repo/plans/recon_operator_run.sh" "$repo/plans/recon_trace.sh" "$repo/plans/validate_recon_artifact.sh"

cat > "$repo/plans/prd.json" <<'EOF'
{
  "items": [
    {"id": "S2-001", "slice": 2, "passes": true},
    {"id": "S2-002", "slice": 2, "passes": true},
    {"id": "S2-003", "slice": 2, "passes": true},
    {"id": "S2-004", "slice": 2, "passes": false}
  ]
}
EOF

mkdir -p "$repo/reviews/reconciliations/S2"
cat > "$repo/reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md" <<'EOF'
# Reconciliation Handoff — {{SLICE_ID}}
EOF
cat > "$repo/reviews/reconciliations/S2/HANDOFF.md" <<'EOF'
# Reconciliation Handoff — S2

### Stopped at
- Story: `S2-001`
EOF

mkdir -p "$repo/.wf/receipts/S2-001"
cat > "$repo/.wf/receipts/S2-001/08_pass.json" <<'EOF'
{"story_id":"S2-001","head_sha":"abcdef1","timestamp_utc":"2026-02-28T00:00:00Z"}
EOF

cat > "$repo/plans/premortem_ready.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
story="${1:-}"
if [[ "$story" == "S2-002" ]]; then
  echo "ready"
  exit 0
fi
echo "blocked: premortem not ready" >&2
exit 1
EOF
chmod +x "$repo/plans/premortem_ready.sh"

cat > "$repo/plans/wf_step.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
story="${1:-}"
step="${2:-}"
if [[ "$story" == "S2-002" && "$step" == "preflight" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo deadbee)"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  receipt=".wf/receipts/$story/00_preflight.json"
  mkdir -p "$(dirname "$receipt")"
  cat > "$receipt" <<JSON
{"story_id":"$story","head_sha":"$head_sha","timestamp_utc":"$ts"}
JSON
  exit 0
fi
echo "wf_step blocked for $story/$step" >&2
exit 3
EOF
chmod +x "$repo/plans/wf_step.sh"

cat > "$repo/plans/recon_scoreboard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
slice="${1:-}"
mkdir -p "reviews/reconciliations/S${slice#S}"
echo "# Scoreboard" > "reviews/reconciliations/S${slice#S}/SCOREBOARD.md"
echo '{"ok":true}' > "reviews/reconciliations/S${slice#S}/SCOREBOARD.json"
echo "call:$slice" >> ".scoreboard_calls.log"
if [[ "${SCOREBOARD_FAIL:-0}" == "1" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$repo/plans/recon_scoreboard.sh"

echo "seed" > "$repo/seed.txt"
(
  cd "$repo"
  git add -A
  git commit -q -m "seed"
)

# Scenario A: no --story provided -> should pick first eligible unreconciled story (S2-002),
# run preflight, and refresh scoreboard/handoff.
(
  cd "$repo"
  plans/recon_operator_run.sh --slice S2 --step preflight --mode B >/dev/null
)

[[ -f "$repo/.wf/receipts/S2-002/00_preflight.json" ]] || fail "runner did not execute preflight for S2-002"
[[ -f "$repo/reviews/reconciliations/S2/SCOREBOARD.md" ]] || fail "scoreboard markdown missing"
[[ -f "$repo/reviews/reconciliations/S2/SCOREBOARD.json" ]] || fail "scoreboard json missing"
grep -Fq "Operator Hook Update" "$repo/reviews/reconciliations/S2/HANDOFF.md" \
  || fail "handoff hook update missing"

trace_root_ok="$(find "$repo/.wf/trace/S2-002" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
[[ -n "$trace_root_ok" ]] || fail "trace root missing for S2-002"
[[ -f "$trace_root_ok/step_timing.jsonl" ]] || fail "step_timing.jsonl missing for S2-002"
grep -Fq '"step":"preflight"' "$trace_root_ok/step_timing.jsonl" || fail "preflight timing entry missing for S2-002"

# Scenario B: explicit blocked story + scoreboard failure should be fail-soft:
# still emit trace artifacts and handoff hook, while exiting non-zero.
set +e
(
  cd "$repo"
  SCOREBOARD_FAIL=1 plans/recon_operator_run.sh --story S2-003 --step preflight --mode B >/dev/null 2>&1
)
blocked_rc=$?
set -e
[[ "$blocked_rc" -ne 0 ]] || fail "expected blocked run to exit non-zero"

trace_root_blocked="$(find "$repo/.wf/trace/S2-003" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
[[ -n "$trace_root_blocked" ]] || fail "trace root missing for blocked S2-003 run"
[[ -f "$trace_root_blocked/step_timing.jsonl" ]] || fail "step_timing.jsonl missing for blocked run"
[[ -f "$trace_root_blocked/failures.jsonl" ]] || fail "failures.jsonl missing for blocked run"
grep -Fq '"category":"AMBIGUITY"' "$trace_root_blocked/failures.jsonl" || fail "blocked failure category missing"

missing_wf_receipt="$(find "$trace_root_blocked/receipts" -maxdepth 1 -type f -name '*wf_missing.json' | head -n 1 || true)"
[[ -n "$missing_wf_receipt" ]] || fail "expected synthetic wf missing receipt for blocked run"

grep -Fq "Operator Hook Update" "$repo/reviews/reconciliations/S2/HANDOFF.md" \
  || fail "handoff hook update missing after blocked run"
[[ -f "$repo/.scoreboard_calls.log" ]] || fail "scoreboard hook marker missing"
calls_count="$(wc -l < "$repo/.scoreboard_calls.log" | tr -d '[:space:]')"
[[ "$calls_count" -ge 2 ]] || fail "expected at least 2 scoreboard hook calls, got $calls_count"

# Scenario C: no eligible stories should provide diagnostics, not generic-only error.
set +e
(
  cd "$repo"
  plans/recon_operator_run.sh --slice S9 --step preflight --mode B >/dev/null 2>"$tmp_dir/no_eligible.err"
)
no_eligible_rc=$?
set -e
[[ "$no_eligible_rc" -ne 0 ]] || fail "expected no-eligible run to exit non-zero"
grep -Fq "ERROR: no eligible unreconciled story found" "$tmp_dir/no_eligible.err" \
  || fail "missing no-eligible top-level error"
grep -Fq "Eligibility diagnostics" "$tmp_dir/no_eligible.err" \
  || fail "missing no-eligible diagnostics section"
grep -Fq "no matching pass=true candidates for slice 9" "$tmp_dir/no_eligible.err" \
  || fail "missing no-eligible slice-filter diagnostic"

echo "test_recon_operator_runner.sh: ok"
