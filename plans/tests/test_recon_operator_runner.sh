#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/plans/recon_operator_run.sh"
TRACE_SCRIPT="$ROOT/plans/recon_trace.sh"
STEP_VALIDATOR="$ROOT/plans/validate_recon_step_report.py"
ARTIFACT_VALIDATOR="$ROOT/plans/validate_recon_artifact.sh"
HASH_UTILS="$ROOT/plans/lib/hash_utils.sh"
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
[[ -f "$HASH_UTILS" ]] || fail "missing hash utils helper: $HASH_UTILS"
[[ -f "$RUN_CARD_TEMPLATE" ]] || fail "missing run card template: $RUN_CARD_TEMPLATE"
[[ -f "$STEP_REPORT_SCHEMA" ]] || fail "missing step report schema: $STEP_REPORT_SCHEMA"
[[ -f "$TRACE_RECEIPT_SCHEMA" ]] || fail "missing trace receipt schema: $TRACE_RECEIPT_SCHEMA"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans/tests" "$repo/plans/lib" "$repo/specs/schemas/recon" "$repo/reviews/reconciliations"
git -C "$tmp_dir" init -q repo
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config core.hooksPath /dev/null

cp "$RUNNER" "$repo/plans/recon_operator_run.sh"
cp "$TRACE_SCRIPT" "$repo/plans/recon_trace.sh"
cp "$STEP_VALIDATOR" "$repo/plans/validate_recon_step_report.py"
cp "$ARTIFACT_VALIDATOR" "$repo/plans/validate_recon_artifact.sh"
cp "$HASH_UTILS" "$repo/plans/lib/hash_utils.sh"
cp "$RUN_CARD_TEMPLATE" "$repo/plans/recon_run_card_template.md"
cp "$STEP_REPORT_SCHEMA" "$repo/specs/schemas/recon/recon_step_report.schema.json"
cp "$TRACE_RECEIPT_SCHEMA" "$repo/specs/schemas/recon/recon_trace_receipt.schema.json"
chmod +x "$repo/plans/recon_operator_run.sh" "$repo/plans/recon_trace.sh" "$repo/plans/validate_recon_artifact.sh"

grep -Fq 'for f in "${changed_before_fingerprints_file:-}" "${changed_after_fingerprints_file:-}" "${changed_delta_file:-}"; do' \
  "$repo/plans/recon_operator_run.sh" \
  || fail "cleanup() must delete fingerprint temp files"
if grep -Fq 'for f in "${changed_before_file:-}" "${changed_after_file:-}" "${changed_new_file:-}"; do' "$repo/plans/recon_operator_run.sh"; then
  fail "cleanup() must not reference stale temp-file variable names"
fi

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
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true
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
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true
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
if [[ "$story" == "S2-002" && "$step" == "self_review" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo deadbee)"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  receipt=".wf/receipts/$story/02_self_review.json"
  mkdir -p "$(dirname "$receipt")"
  mkdir -p crates/soldier_core/src
  if [[ "${FORCE_ILLEGAL_EDIT:-0}" == "1" ]]; then
    echo "// forbidden edit from non-write step" > crates/soldier_core/src/non_write_forbidden.rs
  fi
  if [[ "${FORCE_ILLEGAL_EDIT_MUTATE_DIRTY:-0}" == "1" ]]; then
    echo "// forbidden same-file mutation from non-write step" >> crates/soldier_core/src/lib.rs
  fi
  if [[ "${FORCE_ILLEGAL_EDIT_AND_FAIL:-0}" == "1" ]]; then
    echo "// forbidden mutation on failing non-write step" >> crates/soldier_core/src/lib.rs
    echo "wf_step blocked after illegal production edit" >&2
    exit 3
  fi
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
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true
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
mkdir -p "$repo/crates/soldier_core/src"
echo "// baseline production file" > "$repo/crates/soldier_core/src/lib.rs"
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

# Scenario B: stale ACTIVE_RUN lock with dead pid should be cleaned and not block run.
stale_run="$repo/.wf/trace/S2-002/stale-run"
mkdir -p "$stale_run"
printf '%s\t%s\n' "$stale_run" "999999" > "$repo/.wf/trace/S2-002/ACTIVE_RUN"
(
  cd "$repo"
  plans/recon_operator_run.sh --story S2-002 --step preflight --mode B >/dev/null
)
[[ ! -f "$repo/.wf/trace/S2-002/ACTIVE_RUN" ]] || fail "stale ACTIVE_RUN lock should be removed after successful run"

# Scenario C: explicit blocked story + scoreboard failure should be fail-soft:
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

# Scenario D: non-write step must fail closed if it introduces production code edits.
set +e
(
  cd "$repo"
  FORCE_ILLEGAL_EDIT=1 plans/recon_operator_run.sh --story S2-002 --step self_review --mode B >/dev/null 2>&1
)
illegal_rc=$?
set -e
[[ "$illegal_rc" -ne 0 ]] || fail "expected illegal non-write production edit to block run"

trace_root_illegal="$(find "$repo/.wf/trace/S2-002" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r d; do
  [[ -f "$d/step_timing.jsonl" ]] || continue
  if grep -Fq '"step":"self_review"' "$d/step_timing.jsonl"; then
    echo "$d"
  fi
done | LC_ALL=C sort | tail -n 1 || true)"
[[ -n "$trace_root_illegal" ]] || fail "trace root missing for illegal non-write edit run"
illegal_log="$trace_root_illegal/logs/self_review_attempt1.log"
[[ -f "$illegal_log" ]] || fail "expected illegal self_review log at $illegal_log"
grep -Fq "NON_WRITE_STEP_PROD_EDIT_BLOCKED" "$illegal_log" || fail "missing illegal non-write guard marker"
grep -Fq '"category":"CEREMONY"' "$trace_root_illegal/failures.jsonl" || fail "illegal non-write run should classify as CEREMONY"

# Scenario E: non-write step must fail when mutating an already-dirty production file.
(
  cd "$repo"
  echo "// preexisting dirty change before self_review" >> crates/soldier_core/src/lib.rs
)
set +e
(
  cd "$repo"
  FORCE_ILLEGAL_EDIT_MUTATE_DIRTY=1 plans/recon_operator_run.sh --story S2-002 --step self_review --mode B >/dev/null 2>&1
)
illegal_dirty_rc=$?
set -e
[[ "$illegal_dirty_rc" -ne 0 ]] || fail "expected illegal same-file mutation on already-dirty production file to block run"

trace_root_illegal_dirty="$(find "$repo/.wf/trace/S2-002" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r d; do
  [[ -f "$d/step_timing.jsonl" ]] || continue
  if grep -Fq '"step":"self_review"' "$d/step_timing.jsonl"; then
    echo "$d"
  fi
done | LC_ALL=C sort | tail -n 1 || true)"
[[ -n "$trace_root_illegal_dirty" ]] || fail "trace root missing for already-dirty illegal edit run"
illegal_dirty_log="$trace_root_illegal_dirty/logs/self_review_attempt1.log"
[[ -f "$illegal_dirty_log" ]] || fail "expected illegal same-file self_review log at $illegal_dirty_log"
grep -Fq "NON_WRITE_STEP_PROD_EDIT_BLOCKED" "$illegal_dirty_log" || fail "missing illegal same-file non-write guard marker"
grep -Fq '"category":"CEREMONY"' "$trace_root_illegal_dirty/failures.jsonl" || fail "illegal same-file non-write run should classify as CEREMONY"

# Scenario F: non-write step failing after production edit must still record marker/classification.
set +e
(
  cd "$repo"
  FORCE_ILLEGAL_EDIT_AND_FAIL=1 plans/recon_operator_run.sh --story S2-002 --step self_review --mode B >/dev/null 2>&1
)
illegal_fail_rc=$?
set -e
[[ "$illegal_fail_rc" -ne 0 ]] || fail "expected illegal production edit on failing self_review step to block run"

trace_root_illegal_fail="$(find "$repo/.wf/trace/S2-002" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r d; do
  [[ -f "$d/step_timing.jsonl" ]] || continue
  if grep -Fq '"step":"self_review"' "$d/step_timing.jsonl"; then
    echo "$d"
  fi
done | LC_ALL=C sort | tail -n 1 || true)"
[[ -n "$trace_root_illegal_fail" ]] || fail "trace root missing for failing-step illegal edit run"
illegal_fail_log="$trace_root_illegal_fail/logs/self_review_attempt1.log"
[[ -f "$illegal_fail_log" ]] || fail "expected failing-step illegal self_review log at $illegal_fail_log"
grep -Fq "NON_WRITE_STEP_PROD_EDIT_BLOCKED" "$illegal_fail_log" || fail "missing illegal failing-step non-write guard marker"
grep -Fq '"category":"CEREMONY"' "$trace_root_illegal_fail/failures.jsonl" || fail "failing-step illegal non-write run should classify as CEREMONY"

# Scenario G: no eligible stories should provide diagnostics, not generic-only error.
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
