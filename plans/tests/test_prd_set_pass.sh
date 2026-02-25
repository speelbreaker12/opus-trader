#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/prd_set_pass.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
command -v jq >/dev/null 2>&1 || fail "jq is required for this test"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

head_sha="$(git -C "$ROOT" rev-parse HEAD)"
real_git="$(command -v git)"
story_id="S1-001"

setup_story_review_artifacts() {
  local case_dir="$1"
  local review_head="$2"
  local story_root="$case_dir/story_artifacts/$story_id"

  local opus_dir="$story_root/opus"
  local supervisor_dir="$story_root/supervisor"

  mkdir -p \
    "$story_root/self_review" \
    "$story_root/codex" \
    "$story_root/opus"

  cat > "$story_root/self_review/20260214T000000Z_self_review.md" <<EOF
Story: $story_id
HEAD: $review_head
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF

  cat > "$story_root/codex/20260214T000001Z_review.md" <<EOF
- Story: $story_id
- HEAD: $review_head
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 120

<<<REVIEW_TRANSCRIPT_BEGIN>>>
No P0 or P1 findings. All critical fail-closed paths verified.
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$story_root/codex/20260214T000002Z_review.md" <<EOF
- Story: $story_id
- HEAD: $review_head
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 90

<<<REVIEW_TRANSCRIPT_BEGIN>>>
Second pass complete. No regressions found.
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$story_root/review_resolution.md" <<EOF
Story: $story_id
HEAD: $review_head
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
EOF

  # Proof graph that passes validate.py --strict (V1 schema)
  cat > "$story_root/proof_graph.json" <<EOF
{
  "schema_version": 1,
  "head_sha": "$review_head",
  "generated_at": "2026-02-22T00:00:00+00:00",
  "story_meta": {
    "story_id": "$story_id",
    "category": "infrastructure",
    "enforcement_point": "WAL",
    "loss_mode": {"worst_case": "test", "fail_closed_cap": "test cap", "drift_metric": "test metric", "level": "LOW"},
    "safety_critical": false,
    "scope_touch": ["crates/soldier_infra/src/wal.rs"]
  },
  "ats": [{
    "at_id": "AT-001",
    "enforcement": {"status": "FOUND", "evidence": ["wal.rs:42"]},
    "tests": [
      {"test_name": "test_wal_write", "kind": "TRIP", "causal_proof": {"mechanism": "dispatch_count_assert", "dispatch_count_assert": "0"}, "execution": {"ran_at_head_sha": "$review_head", "pass_result": true}},
      {"test_name": "test_wal_read", "kind": "NON-TRIP", "causal_proof": {"mechanism": "dispatch_count_assert", "dispatch_count_assert": "1"}, "execution": {"ran_at_head_sha": "$review_head", "pass_result": true}}
    ],
    "wiring": {"status": "PROVEN_INTEGRATED", "evidence": "test calls wal directly"},
    "observability": {"metric": "wal_write_latency_ms", "alert": "wal_write_alert"},
    "premortem_checks": {"stoplight": "GREEN", "sections_filled": 10},
    "at_verdict": {"verdict": "PROVEN_INTEGRATED", "severity": "INFO", "rationale": "proven"}
  }],
  "story_verdict": {"reconciliation_status": "RECONCILED", "blocking_count": 0, "hardening_count": 0, "summary": "all proven"},
  "debt_register": []
}
EOF
}

setup_case() {
  local case_dir="$1"
  local verify_head="$2"
  local review_head="${3:-$verify_head}"

  mkdir -p "$case_dir/artifacts"
  cat > "$case_dir/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":{"worst_case":"test worst case","fail_closed_cap":"test cap","drift_metric":"test metric"}}
  ]
}
EOF

  cat > "$case_dir/artifacts/verify.meta.json" <<EOF
{
  "mode": "full",
  "head_sha": "$verify_head"
}
EOF

  printf '0\n' > "$case_dir/artifacts/preflight.rc"
  cat > "$case_dir/artifacts/contract_review.json" <<'EOF'
{
  "decision": "PASS"
}
EOF
  setup_story_review_artifacts "$case_dir" "$review_head"
}

# ── Test 1: Success case ─────────────────────────────────────────────
success_case="$tmp_dir/success"
mkdir -p "$success_case"
setup_case "$success_case" "$head_sha"

success_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$success_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$success_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$success_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$success_case/artifacts/contract_review.json"
)"

echo "$success_output" | grep -Fq "Updated task $story_id: passes=true" || fail "missing success output"
echo "$success_output" | grep -Fq "OK: review gate passed for $story_id @ $head_sha" || fail "inline review check did not pass for current HEAD"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==true)' "$success_case/prd.json" >/dev/null || fail "passes was not updated to true"

# ── Test 2: HEAD mismatch in verify.meta.json ─────────────────────────
mismatch_case="$tmp_dir/mismatch"
mkdir -p "$mismatch_case"
setup_case "$mismatch_case" "deadbeef" "$head_sha"

set +e
mismatch_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$mismatch_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$mismatch_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$mismatch_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$mismatch_case/artifacts/contract_review.json" 2>&1
)"
mismatch_rc=$?
set -e

[[ "$mismatch_rc" -ne 0 ]] || fail "expected head mismatch to fail"
echo "$mismatch_output" | grep -Fq "ERROR: verify metadata HEAD mismatch" || fail "missing head mismatch diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$mismatch_case/prd.json" >/dev/null || fail "passes changed despite head mismatch failure"

# ── Test 3: Mid-run HEAD change detected ────────────────────────────
head_flip_case="$tmp_dir/head_flip"
mkdir -p "$head_flip_case"
setup_case "$head_flip_case" "$head_sha"

alt_head="$head_sha"
if [[ "${alt_head:0:1}" == "a" ]]; then
  alt_head="b${alt_head:1}"
else
  alt_head="a${alt_head:1}"
fi

git_wrapper_dir="$tmp_dir/git-wrapper"
mkdir -p "$git_wrapper_dir"
cat > "$git_wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

count_file="${TEST_GIT_COUNT_FILE:?missing TEST_GIT_COUNT_FILE}"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

if [[ "$#" -ge 2 && "$1" == "rev-parse" && "$2" == "HEAD" ]]; then
  if [[ "$count" -eq 1 ]]; then
    printf '%s\n' "${TEST_GIT_HEAD_FIRST:?missing TEST_GIT_HEAD_FIRST}"
  else
    printf '%s\n' "${TEST_GIT_HEAD_SECOND:?missing TEST_GIT_HEAD_SECOND}"
  fi
  exit 0
fi

exec "${TEST_GIT_REAL:?missing TEST_GIT_REAL}" "$@"
EOF
chmod +x "$git_wrapper_dir/git"

set +e
head_flip_output="$(
  cd "$ROOT" && \
  PATH="$git_wrapper_dir:$PATH" \
  TEST_GIT_REAL="$real_git" \
  TEST_GIT_COUNT_FILE="$head_flip_case/git.count" \
  TEST_GIT_HEAD_FIRST="$head_sha" \
  TEST_GIT_HEAD_SECOND="$alt_head" \
  WF_STEP=/bin/true \
  PRD_FILE="$head_flip_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$head_flip_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$head_flip_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$head_flip_case/artifacts/contract_review.json" 2>&1
)"
head_flip_rc=$?
set -e

[[ "$head_flip_rc" -ne 0 ]] || fail "expected pass flip to fail when HEAD changes mid-run"
echo "$head_flip_output" | grep -Fq "ERROR: HEAD changed during pass flip validation" || fail "missing mid-run head-change diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$head_flip_case/prd.json" >/dev/null || fail "passes changed despite mid-run head-change failure"
echo "$head_flip_output" | grep -Fq "OK: review gate passed for $story_id @ $head_sha" || fail "inline review check should run with the initial HEAD before final check"

# ── Test 4: No-flock locking (mkdir-based) ──────────────────────────
noflock_case="$tmp_dir/noflock_lock_cleanup"
mkdir -p "$noflock_case"
cat > "$noflock_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":true}
  ]
}
EOF

noflock_bin="$tmp_dir/noflock-bin"
mkdir -p "$noflock_bin"
for tool in bash dirname jq mkdir rmdir mktemp mv; do
  tool_path="$(command -v "$tool" || true)"
  [[ -n "$tool_path" ]] || fail "missing required tool for no-flock case: $tool"
  ln -s "$tool_path" "$noflock_bin/$tool"
done

for run in 1 2; do
  noflock_output="$(
    cd "$ROOT" && \
    PATH="$noflock_bin" \
    PRD_FILE="$noflock_case/prd.json" \
    VERIFY_ARTIFACTS_DIR="$noflock_case/unused_artifacts" \
    "$SCRIPT" "$story_id" false 2>&1
  )"
  echo "$noflock_output" | grep -Fq "Updated task $story_id: passes=false" || fail "no-flock run $run did not complete successfully"
  [[ ! -d "$noflock_case/prd.json.lock.d" ]] || fail "no-flock run $run left stale lock dir"
done

# ── Test 5: loss_mode gate — incomplete drift_metric blocks pass flip (exit 9) ──
loss_mode_case="$tmp_dir/loss_mode_gate"
mkdir -p "$loss_mode_case"
setup_case "$loss_mode_case" "$head_sha"
# Override prd.json with empty drift_metric
cat > "$loss_mode_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":{"worst_case":"wc","fail_closed_cap":"cap","drift_metric":""}}
  ]
}
EOF

set +e
loss_mode_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$loss_mode_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$loss_mode_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$loss_mode_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$loss_mode_case/artifacts/contract_review.json" 2>&1
)"
loss_mode_rc=$?
set -e

[[ "$loss_mode_rc" -eq 9 ]] || fail "expected exit 9 for incomplete loss_mode, got $loss_mode_rc"
echo "$loss_mode_output" | grep -Fq "loss_mode incomplete for $story_id" || fail "missing loss_mode gate diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$loss_mode_case/prd.json" >/dev/null || fail "passes changed despite loss_mode gate failure"

# ── Test 6: loss_mode gate — malformed loss_mode (non-object) blocks pass flip ──
malformed_loss_case="$tmp_dir/malformed_loss"
mkdir -p "$malformed_loss_case"
setup_case "$malformed_loss_case" "$head_sha"
cat > "$malformed_loss_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":"not-an-object"}
  ]
}
EOF

set +e
malformed_loss_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$malformed_loss_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$malformed_loss_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$malformed_loss_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$malformed_loss_case/artifacts/contract_review.json" 2>&1
)"
malformed_loss_rc=$?
set -e

[[ "$malformed_loss_rc" -ne 0 ]] || fail "expected failure for malformed loss_mode"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$malformed_loss_case/prd.json" >/dev/null || fail "passes changed despite malformed loss_mode"

# ── Test 7: loss_mode gate — policy stories are exempt ──────────────
policy_exempt_case="$tmp_dir/policy_exempt"
mkdir -p "$policy_exempt_case"
setup_case "$policy_exempt_case" "$head_sha"
cat > "$policy_exempt_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"policy","enforcing_contract_ats":[],"enforcement_point":"","loss_mode":{"worst_case":"N/A","fail_closed_cap":"N/A","drift_metric":"N/A"}}
  ]
}
EOF

# Policy stories skip AT ownership + loss_mode gates but still need artifacts
# This should fail at artifacts/verify check (exit 4), NOT at loss_mode (exit 9) or AT ownership (exit 6)
set +e
policy_exempt_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$policy_exempt_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$policy_exempt_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$policy_exempt_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$policy_exempt_case/artifacts/contract_review.json" 2>&1
)"
policy_exempt_rc=$?
set -e

# Should NOT exit 9 (loss_mode) or 6 (AT ownership) — policy is exempt from both
[[ "$policy_exempt_rc" -ne 9 ]] || fail "policy story should be exempt from loss_mode gate"
[[ "$policy_exempt_rc" -ne 6 ]] || fail "policy story should be exempt from AT ownership gate"

# ── Test 8: Inline review check — no review artifact fails ──────────
no_review_case="$tmp_dir/no_review"
mkdir -p "$no_review_case"
setup_case "$no_review_case" "$head_sha"
# Remove all review artifacts
rm -rf "$no_review_case/story_artifacts/$story_id/codex"
rm -rf "$no_review_case/story_artifacts/$story_id/opus"

set +e
no_review_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$no_review_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$no_review_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$no_review_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$no_review_case/artifacts/contract_review.json" 2>&1
)"
no_review_rc=$?
set -e

[[ "$no_review_rc" -eq 4 ]] || fail "expected exit 4 for missing review artifacts, got $no_review_rc"
echo "$no_review_output" | grep -Fq "no review artifact for HEAD=" || fail "missing inline review check diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$no_review_case/prd.json" >/dev/null || fail "passes changed despite missing review artifacts"

# loss_mode gate: incomplete drift_metric blocks pass flip (exit 9)
loss_mode_case="$tmp_dir/loss_mode_gate"
mkdir -p "$loss_mode_case"
setup_case "$loss_mode_case" "$head_sha"
# Override prd.json with empty drift_metric
cat > "$loss_mode_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":{"worst_case":"wc","fail_closed_cap":"cap","drift_metric":""}}
  ]
}
EOF

set +e
loss_mode_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$loss_mode_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$loss_mode_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$loss_mode_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$loss_mode_case/artifacts/contract_review.json" 2>&1
)"
loss_mode_rc=$?
set -e

[[ "$loss_mode_rc" -eq 9 ]] || fail "expected exit 9 for incomplete loss_mode, got $loss_mode_rc"
echo "$loss_mode_output" | grep -Fq "loss_mode incomplete for $story_id" || fail "missing loss_mode gate diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$loss_mode_case/prd.json" >/dev/null || fail "passes changed despite loss_mode gate failure"

# ── Test 6: loss_mode gate — malformed loss_mode (non-object) blocks pass flip ──
malformed_loss_case="$tmp_dir/malformed_loss"
mkdir -p "$malformed_loss_case"
setup_case "$malformed_loss_case" "$head_sha"
cat > "$malformed_loss_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":"not-an-object"}
  ]
}
EOF

set +e
malformed_loss_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$malformed_loss_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$malformed_loss_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$malformed_loss_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$malformed_loss_case/artifacts/contract_review.json" 2>&1
)"
malformed_loss_rc=$?
set -e

[[ "$malformed_loss_rc" -ne 0 ]] || fail "expected failure for malformed loss_mode"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$malformed_loss_case/prd.json" >/dev/null || fail "passes changed despite malformed loss_mode"

# ── Test 7: loss_mode gate — policy stories are exempt ──────────────
policy_exempt_case="$tmp_dir/policy_exempt"
mkdir -p "$policy_exempt_case"
setup_case "$policy_exempt_case" "$head_sha"
cat > "$policy_exempt_case/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"policy","enforcing_contract_ats":[],"enforcement_point":"","loss_mode":{"worst_case":"N/A","fail_closed_cap":"N/A","drift_metric":"N/A"}}
  ]
}
EOF

# Policy stories skip AT ownership + loss_mode gates but still need artifacts
# This should fail at artifacts/verify check (exit 4), NOT at loss_mode (exit 9) or AT ownership (exit 6)
set +e
policy_exempt_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$policy_exempt_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$policy_exempt_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$policy_exempt_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$policy_exempt_case/artifacts/contract_review.json" 2>&1
)"
policy_exempt_rc=$?
set -e

# Should NOT exit 9 (loss_mode) or 6 (AT ownership) — policy is exempt from both
[[ "$policy_exempt_rc" -ne 9 ]] || fail "policy story should be exempt from loss_mode gate"
[[ "$policy_exempt_rc" -ne 6 ]] || fail "policy story should be exempt from AT ownership gate"

# ── Test 8: Inline review check — no review artifact fails ──────────
no_review_case="$tmp_dir/no_review"
mkdir -p "$no_review_case"
setup_case "$no_review_case" "$head_sha"
# Remove all review artifacts
rm -rf "$no_review_case/story_artifacts/$story_id/codex"
rm -rf "$no_review_case/story_artifacts/$story_id/opus"

set +e
no_review_output="$(
  cd "$ROOT" && \
  WF_STEP=/bin/true \
  PRD_FILE="$no_review_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$no_review_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$no_review_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$no_review_case/artifacts/contract_review.json" 2>&1
)"
no_review_rc=$?
set -e

[[ "$no_review_rc" -eq 4 ]] || fail "expected exit 4 for missing review artifacts, got $no_review_rc"
echo "$no_review_output" | grep -Fq "no review artifact for HEAD=" || fail "missing inline review check diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$no_review_case/prd.json" >/dev/null || fail "passes changed despite missing review artifacts"

echo "PASS: prd_set_pass"
