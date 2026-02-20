#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/pre_pr_review_gate.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    fail "$label expected non-zero exit"
  fi
  if ! printf '%s\n' "$output" | grep -Fq -- "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

write_valid_case() {
  local base="$1"
  local story="$2"
  local head_sha="$3"

  local story_dir="$base/$story"
  local self_dir="$story_dir/self_review"
  local codex_dir="$story_dir/codex"
  local kimi_dir="$story_dir/kimi"
  local code_review_expert_dir="$story_dir/code_review_expert"

  local opus_dir="$story_dir/opus"
  local supervisor_dir="$story_dir/supervisor"

  mkdir -p "$self_dir" "$codex_dir" "$kimi_dir" "$code_review_expert_dir" "$opus_dir" "$supervisor_dir"

  # Compute dynamic diff file references for anti-fabrication cross-reference checks
  local _diff_mention=""
  local _diff_files_for_expert=""
  if git rev-parse --verify "$head_sha^" >/dev/null 2>&1; then
    local _df=""
    while IFS= read -r _df; do
      [[ -n "$_df" ]] || continue
      _diff_mention+="Reviewed $_df for correctness. "
      _diff_files_for_expert+="$_df, "
    done < <(git diff --name-only "${head_sha}^..${head_sha}" 2>/dev/null | head -3)
  fi
  [[ -n "$_diff_mention" ]] || _diff_mention="Reviewed crates/soldier_core/src/execution/pipeline.rs for correctness. "
  [[ -n "$_diff_files_for_expert" ]] || _diff_files_for_expert="crates/soldier_core/src/execution/pipeline.rs, "

  local codex_one_transcript="$story_dir/.codex_one_transcript.txt"
  local codex_two_transcript="$story_dir/.codex_two_transcript.txt"
  local kimi_transcript="$story_dir/.kimi_transcript.txt"
  local expert_findings="$story_dir/.expert_findings.txt"
  local codex_one_hash=""
  local codex_two_hash=""
  local kimi_hash=""
  local expert_findings_hash=""

  cat > "$self_dir/20260209T000000Z_self_review.md" <<EOF_SELF
# Self Review
Story: $story
HEAD: $head_sha
Decision: PASS
Checklist:
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF_SELF

  cat > "$codex_one_transcript" <<EOF_CODEX1_TRANSCRIPT
OpenAI Codex vfixture
session id: pre-pr-codex-one
${_diff_mention}
Verified crates/soldier_core/src/execution/pipeline.rs for safety gate correctness.
Checked crates/soldier_core/tests/test_gate_ordering.rs gate ordering invariants.
P2: Minor — the fee lookup in net_edge could be extracted for clarity.
P3: Low — unused import on line 14 of test file.
No P0 or P1 findings. All critical fail-closed paths verified against CONTRACT.md.
Overall: code is safe to merge. No blocking issues detected in this review cycle.
EOF_CODEX1_TRANSCRIPT
  codex_one_hash="$(sha256_file "$codex_one_transcript")"
  cat > "$codex_dir/20260209T000000Z_review.md" <<EOF_CODEX1
# Codex review
- Story: $story
- HEAD: $head_sha
- Artifact Provenance: logger-v1
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 120
- Transcript SHA256: $codex_one_hash

<<<REVIEW_TRANSCRIPT_BEGIN>>>
EOF_CODEX1
  cat "$codex_one_transcript" >> "$codex_dir/20260209T000000Z_review.md"
  cat >> "$codex_dir/20260209T000000Z_review.md" <<'EOF_CODEX1_END'
<<<REVIEW_TRANSCRIPT_END>>>
EOF_CODEX1_END

  cat > "$codex_two_transcript" <<EOF_CODEX2_TRANSCRIPT
OpenAI Codex vfixture
session id: pre-pr-codex-two
Adversarial review after cycle 1 fixes. ${_diff_mention}
Stress-tested crates/soldier_core/src/execution/pipeline.rs with edge cases.
Verified crates/soldier_core/tests/test_gate_ordering.rs assertions hold.
P3: Low — consider adding a comment explaining the quantizer rounding strategy.
No P0, P1, or P2 findings in this second pass. Cycle 1 fixes addressed all raised concerns.
Risk assessment: fail-closed behavior verified under NaN/Inf inputs and missing config.
Second pass complete. No regressions found.
EOF_CODEX2_TRANSCRIPT
  codex_two_hash="$(sha256_file "$codex_two_transcript")"
  cat > "$codex_dir/20260209T000100Z_review.md" <<EOF_CODEX2
# Codex review (second pass)
- Story: $story
- HEAD: $head_sha
- Artifact Provenance: logger-v1
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 90
- Transcript SHA256: $codex_two_hash

<<<REVIEW_TRANSCRIPT_BEGIN>>>
EOF_CODEX2
  cat "$codex_two_transcript" >> "$codex_dir/20260209T000100Z_review.md"
  cat >> "$codex_dir/20260209T000100Z_review.md" <<'EOF_CODEX2_END'
<<<REVIEW_TRANSCRIPT_END>>>
EOF_CODEX2_END

  cat > "$kimi_transcript" <<EOF_KIMI_TRANSCRIPT
TurnBegin(user_input="pre-pr fixture review of story changes")
ToolCall(name="Shell", input="cargo clippy -- -D warnings")
TextPart(text="${_diff_mention}")
TextPart(text="Verified crates/soldier_core/src/execution/pipeline.rs for correctness.")
TextPart(text="Checked crates/soldier_core/tests/test_gate_ordering.rs assertions.")
TextPart(text="P2: Minor — consider extracting the fee lookup into a helper for readability.")
TextPart(text="P3: Low — unused import in test file can be removed.")
TextPart(text="No P0 or P1 findings. All critical paths are covered by existing acceptance tests.")
TextPart(text="Overall assessment: code is correct and safe to merge. No blocking issues found.")
EOF_KIMI_TRANSCRIPT
  kimi_hash="$(sha256_file "$kimi_transcript")"
  cat > "$kimi_dir/20260209T000050Z_review.md" <<EOF_KIMI
# Kimi review
- Story: $story
- HEAD: $head_sha
- Artifact Provenance: logger-v1
- Generator Script: plans/kimi_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 60
- Transcript SHA256: $kimi_hash

<<<REVIEW_TRANSCRIPT_BEGIN>>>
EOF_KIMI
  cat "$kimi_transcript" >> "$kimi_dir/20260209T000050Z_review.md"
  cat >> "$kimi_dir/20260209T000050Z_review.md" <<'EOF_KIMI_END'
<<<REVIEW_TRANSCRIPT_END>>>
EOF_KIMI_END

  cat > "$expert_findings" <<EOF_EXPERT_FINDINGS
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
EOF_EXPERT_FINDINGS
  expert_findings_hash="$(sha256_file "$expert_findings")"
  cat > "$code_review_expert_dir/20260209T000080Z_review.md" <<EOF_EXPERT
# Code-review-expert findings
- Story: $story
- HEAD: $head_sha
- Review Status: COMPLETE
- Artifact Provenance: logger-v1
- Generator Script: plans/code_review_expert_logged.sh
- Duration Seconds: 45
- Content Source: template
- Findings SHA256: $expert_findings_hash

<<<FINDINGS_BEGIN>>>
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
<<<FINDINGS_END>>>
EOF_EXPERT

  cat > "$story_dir/review_resolution.md" <<EOF_RES
Story: $story
HEAD: $head_sha
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Kimi final review file: kimi/20260209T000050Z_review.md
Codex final review file: codex/20260209T000100Z_review.md
Codex second review file: codex/20260209T000000Z_review.md
Code-review-expert final review file: code_review_expert/20260209T000080Z_review.md
EOF_RES

  for checkpoint in post-cycle1 post-fix post-cycle2; do
    cat > "$supervisor_dir/${checkpoint}_20260209T000090Z.md" <<EOF_SUP
# Supervisor checkpoint
- Story: $story
- HEAD: $head_sha
- Checkpoint: $checkpoint
- Verdict: PASS
- Reason: All checks passed
- Artifact Provenance: supervisor-v1
- Generator Script: plans/supervisor_check.sh
EOF_SUP
  done

  rm -f "$codex_one_transcript" "$codex_two_transcript" "$kimi_transcript" "$expert_findings"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

story_root="$tmp_dir/story"
slice_root="$tmp_dir/slice_reviews"
story="S1-TEST"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

write_valid_case "$story_root" "$story" "$head_sha"

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root" >/dev/null

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story" --artifacts-root "$story_root" >/dev/null

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story-fix" --artifacts-root "$story_root" >/dev/null

expect_fail "missing story artifact" "missing self-review artifact" \
  "$SCRIPT" "S1-MISSING" --head "$head_sha" --branch "story/S1-MISSING/gate" --artifacts-root "$story_root"

expect_fail "invalid story id" "invalid STORY_ID value: ../escape" \
  "$SCRIPT" "../escape" --head "$head_sha" --branch "story/S1-TEST/gate" --artifacts-root "$story_root"

expect_fail "invalid slash story id" "invalid STORY_ID value: workflow/maintenance" \
  "$SCRIPT" "workflow/maintenance" --head "$head_sha" --branch "story/S1-TEST/gate" --artifacts-root "$story_root"

expect_fail "invalid branch format" "branch must be story-scoped" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "codex/$story/gate" --artifacts-root "$story_root"

expect_fail "branch/story mismatch" "story id mismatch" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "story/S9-999/gate" --artifacts-root "$story_root"

rm -f "$story_root/$story/kimi/20260209T000050Z_review.md"
expect_fail "story review gate failure propagates" "missing Kimi review artifact for HEAD" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root"

# Restore valid story artifacts for slice checks.
rm -rf "$story_root/$story"
write_valid_case "$story_root" "$story" "$head_sha"

expect_fail "slice review missing" "missing slice thinking-review artifact" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root" --slice-id "slice-1" --slice-artifacts-root "$slice_root"

mkdir -p "$slice_root/slice-1"
cat > "$slice_root/slice-1/thinking_review.md" <<EOF_SLICE
# Thinking Review (Slice Close)

- Slice ID: slice-1
- Integration HEAD: $head_sha
- Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md
- Reviewer: tester
- Timestamp (UTC): 2026-02-11T00:00:00Z

## Scope
- Stories merged in this slice: S1-001,S1-002
- Branch reviewed: run/slice1-clean

## Findings
- Blocking: none
- Major: none
- Medium: none

## Final Disposition
- Ready To Close Slice: YES
- Follow-ups: none
EOF_SLICE

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root" --slice-id "slice-1" --slice-artifacts-root "$slice_root" >/dev/null

echo "PASS: pre_pr_review_gate fixtures"
