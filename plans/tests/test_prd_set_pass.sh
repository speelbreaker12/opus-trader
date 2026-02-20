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

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

head_sha="$(git -C "$ROOT" rev-parse HEAD)"
real_git="$(command -v git)"
story_id="WF-001"
export REQUIRE_RECEIPT_CHAIN=0  # this test validates review + contract gates, not receipt chain

# Compute dynamic diff file references for anti-fabrication cross-reference checks
_diff_mention=""
_diff_files_for_expert=""
if git -C "$ROOT" rev-parse --verify "${head_sha}^" >/dev/null 2>&1; then
  while IFS= read -r _df; do
    [[ -n "$_df" ]] || continue
    _diff_mention+="Reviewed $_df for correctness. "
    _diff_files_for_expert+="$_df, "
  done < <(git -C "$ROOT" diff --name-only "${head_sha}^..${head_sha}" 2>/dev/null | head -3)
fi
[[ -n "$_diff_mention" ]] || _diff_mention="Reviewed crates/soldier_core/src/execution/pipeline.rs for correctness. "
[[ -n "$_diff_files_for_expert" ]] || _diff_files_for_expert="crates/soldier_core/src/execution/pipeline.rs, "

setup_story_review_artifacts() {
  local case_dir="$1"
  local review_head="$2"
  local story_root="$case_dir/story_artifacts/$story_id"
  local self_file="$story_root/self_review/20260214T000000Z_self_review.md"
  local kimi_file="$story_root/kimi/20260214T000000Z_review.md"
  local codex_final_file="$story_root/codex/20260214T000001Z_review.md"
  local codex_second_file="$story_root/codex/20260214T000002Z_review.md"
  local expert_file="$story_root/code_review_expert/20260214T000003Z_review.md"
  local resolution_file="$story_root/review_resolution.md"
  local codex_one_transcript="$story_root/codex/.codex_one_transcript.txt"
  local codex_two_transcript="$story_root/codex/.codex_two_transcript.txt"
  local kimi_transcript="$story_root/kimi/.kimi_transcript.txt"
  local expert_findings="$story_root/code_review_expert/.expert_findings.txt"
  local codex_one_hash=""
  local codex_two_hash=""
  local kimi_hash=""
  local expert_findings_hash=""

  local opus_dir="$story_root/opus"
  local supervisor_dir="$story_root/supervisor"

  mkdir -p \
    "$story_root/self_review" \
    "$story_root/kimi" \
    "$story_root/codex" \
    "$story_root/opus" \
    "$story_root/code_review_expert" \
    "$supervisor_dir"

  cat > "$self_file" <<EOF
Story: $story_id
HEAD: $review_head
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF

  cat > "$kimi_transcript" <<EOF
TurnBegin(user_input="prd_set_pass fixture review of story changes")
ToolCall(name="Shell", input="cargo clippy -- -D warnings")
TextPart(text="${_diff_mention}")
TextPart(text="Verified crates/soldier_core/src/execution/pipeline.rs for correctness.")
TextPart(text="Checked crates/soldier_core/tests/test_gate_ordering.rs assertions.")
TextPart(text="P2: Minor — consider extracting the fee lookup into a helper for readability.")
TextPart(text="P3: Low — unused import in test file can be removed.")
TextPart(text="No P0 or P1 findings. All critical paths are covered by existing acceptance tests.")
TextPart(text="Overall assessment: code is correct and safe to merge. No blocking issues found.")
EOF
  kimi_hash="$(sha256_file "$kimi_transcript")"
  cat > "$kimi_file" <<EOF
- Story: $story_id
- HEAD: $review_head
- Artifact Provenance: logger-v1
- Generator Script: plans/kimi_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 60
- Transcript SHA256: $kimi_hash

<<<REVIEW_TRANSCRIPT_BEGIN>>>
$(cat "$kimi_transcript")
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$codex_one_transcript" <<EOF
OpenAI Codex vfixture
session id: prd-set-pass-codex-final
${_diff_mention}
Verified crates/soldier_core/src/execution/pipeline.rs for safety gate correctness.
Checked crates/soldier_core/tests/test_gate_ordering.rs gate ordering invariants.
P2: Minor — the fee lookup in net_edge could be extracted for clarity.
P3: Low — unused import on line 14 of test file.
No P0 or P1 findings. All critical fail-closed paths verified against CONTRACT.md.
Overall: code is safe to merge. No blocking issues detected in this review cycle.
EOF
  codex_one_hash="$(sha256_file "$codex_one_transcript")"
  cat > "$codex_final_file" <<EOF
- Story: $story_id
- HEAD: $review_head
- Artifact Provenance: logger-v1
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 120
- Transcript SHA256: $codex_one_hash

<<<REVIEW_TRANSCRIPT_BEGIN>>>
$(cat "$codex_one_transcript")
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$codex_two_transcript" <<EOF
OpenAI Codex vfixture
session id: prd-set-pass-codex-second
Adversarial review after cycle 1 fixes. ${_diff_mention}
Stress-tested crates/soldier_core/src/execution/pipeline.rs with edge cases.
Verified crates/soldier_core/tests/test_gate_ordering.rs assertions hold.
P3: Low — consider adding a comment explaining the quantizer rounding strategy.
No P0, P1, or P2 findings in this second pass. Cycle 1 fixes addressed all raised concerns.
Risk assessment: fail-closed behavior verified under NaN/Inf inputs and missing config.
Second pass complete. No regressions found.
EOF
  codex_two_hash="$(sha256_file "$codex_two_transcript")"
  cat > "$codex_second_file" <<EOF
- Story: $story_id
- HEAD: $review_head
- Artifact Provenance: logger-v1
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 90
- Transcript SHA256: $codex_two_hash

<<<REVIEW_TRANSCRIPT_BEGIN>>>
$(cat "$codex_two_transcript")
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$expert_findings" <<EOF
## Code Review Summary
Files reviewed: ${_diff_files_for_expert}crates/soldier_core/tests/test_gate_ordering.rs
Overall assessment: APPROVE — no blocking or major findings

### P0 - Critical
(none found)

### P1 - High
(none found)

### P2 - Medium
- crates/soldier_core/src/execution/pipeline.rs:42 — fee lookup could be extracted into a helper for testability and reuse across multiple gate stages

### P3 - Low
- crates/soldier_core/tests/test_gate_ordering.rs:14 — unused import can be removed to satisfy clippy warnings

## Additional Notes
All safety-critical paths verified against CONTRACT.md. Fail-closed behavior confirmed for degraded and kill risk states.

- Blocking: none
- Major: none
- Medium: 1 (P2 — fee lookup extraction, non-blocking)
EOF
  expert_findings_hash="$(sha256_file "$expert_findings")"
  cat > "$expert_file" <<EOF
- Story: $story_id
- HEAD: $review_head
- Review Status: COMPLETE
- Artifact Provenance: logger-v1
- Generator Script: plans/code_review_expert_logged.sh
- Duration Seconds: 45
- Content Source: template
- Findings SHA256: $expert_findings_hash

<<<FINDINGS_BEGIN>>>
$(cat "$expert_findings")
<<<FINDINGS_END>>>
EOF

  cat > "$resolution_file" <<EOF
Story: $story_id
HEAD: $review_head
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Kimi final review file: $kimi_file
Codex final review file: $codex_final_file
Codex second review file: $codex_second_file
Code-review-expert final review file: $expert_file
EOF

  for checkpoint in post-cycle1 post-fix post-cycle2; do
    cat > "$supervisor_dir/${checkpoint}_20260214T000090Z.md" <<EOF
# Supervisor checkpoint
- Story: $story_id
- HEAD: $review_head
- Checkpoint: $checkpoint
- Verdict: PASS
- Reason: All checks passed
- Artifact Provenance: supervisor-v1
- Generator Script: plans/supervisor_check.sh
EOF
  done

  rm -f "$codex_one_transcript" "$codex_two_transcript" "$kimi_transcript" "$expert_findings"
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

success_case="$tmp_dir/success"
mkdir -p "$success_case"
setup_case "$success_case" "$head_sha"

success_output="$(
  cd "$ROOT" && \
  PRD_FILE="$success_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$success_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$success_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$success_case/artifacts/contract_review.json"
)"

echo "$success_output" | grep -Fq "Updated task $story_id: passes=true" || fail "missing success output"
echo "$success_output" | grep -Fq "OK: review gate passed for $story_id @ $head_sha" || fail "story review gate did not run for current HEAD"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==true)' "$success_case/prd.json" >/dev/null || fail "passes was not updated to true"

mismatch_case="$tmp_dir/mismatch"
mkdir -p "$mismatch_case"
setup_case "$mismatch_case" "deadbeef" "$head_sha"

set +e
mismatch_output="$(
  cd "$ROOT" && \
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
echo "$head_flip_output" | grep -Fq "OK: review gate passed for $story_id @ $head_sha" || fail "story review gate should run with the initial HEAD before final check"

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

# Phase-0 prerequisite guard: non-phase0 pass flip is blocked until all phase0 items pass.
phase0_guard_case="$tmp_dir/phase0_guard"
mkdir -p "$phase0_guard_case"
setup_case "$phase0_guard_case" "$head_sha"
cat > "$phase0_guard_case/prd.json" <<EOF
{
  "items": [
    {"id":"S0-000","phase":0,"passes":false,"category":"policy","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":{"worst_case":"N/A","fail_closed_cap":"N/A","drift_metric":"N/A"}},
    {"id":"$story_id","phase":1,"passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":{"worst_case":"test","fail_closed_cap":"test","drift_metric":"test"}}
  ]
}
EOF

set +e
phase0_guard_output="$(
  cd "$ROOT" && \
  PRD_FILE="$phase0_guard_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$phase0_guard_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$phase0_guard_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$phase0_guard_case/artifacts/contract_review.json" 2>&1
)"
phase0_guard_rc=$?
set -e

[[ "$phase0_guard_rc" -ne 0 ]] || fail "expected non-phase0 pass flip to fail when phase0 stories are incomplete"
echo "$phase0_guard_output" | grep -Fq "Phase-0 stories are incomplete: S0-000" || fail "missing phase0 guard diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$phase0_guard_case/prd.json" >/dev/null || fail "passes changed despite phase0 guard failure"

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

# loss_mode gate: malformed loss_mode (non-object) blocks pass flip (exit 9)
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

# loss_mode gate: policy stories are exempt (should not check loss_mode)
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

echo "PASS: prd_set_pass"
