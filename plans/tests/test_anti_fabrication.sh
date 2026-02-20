#!/usr/bin/env bash
# Test anti-fabrication defenses in story_review_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/plans/story_review_gate.sh"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
STORY="ANTIFAB-TEST"
PASS=0
FAIL=0

# Lower thresholds for test speed (real reviews are much longer)
export MIN_TRANSCRIPT_BYTES=200
export MIN_REVIEW_DURATION=1
# Disable supervisor for Part 1/2 tests (tested separately in Part 3)
export REQUIRE_SUPERVISOR=0

cleanup_dir=""
setup() {
  cleanup_dir="$(mktemp -d)"
  local sd="$cleanup_dir/$STORY"
  mkdir -p "$sd/self_review" "$sd/kimi" "$sd/codex" "$sd/code_review_expert"
  cat > "$sd/self_review/20260219_self_review.md" <<EOF
Story: $STORY
HEAD: $HEAD_SHA
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF
}

teardown() {
  [[ -n "$cleanup_dir" ]] && rm -rf "$cleanup_dir"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Build a review artifact with controlled content
# Usage: build_review <outfile> <generator_script> <content> <duration> [<timestamp>]
build_review() {
  local outfile="$1" gen_script="$2" content="$3" duration="$4"
  local ts="${5:-20260219T120000Z}"
  local transcript_tmp
  transcript_tmp="$(mktemp)"
  printf '%s\n' "$content" > "$transcript_tmp"
  local t_hash t_bytes
  t_hash="$(sha256_of "$transcript_tmp")"
  t_bytes="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"
  {
    echo "# Review"
    echo ""
    echo "- Story: $STORY"
    echo "- Timestamp (UTC): $ts"
    echo "- HEAD: $HEAD_SHA"
    echo "- Artifact Provenance: logger-v1"
    echo "- Generator Script: $gen_script"
    echo "- Command Exit Code: 0"
    echo "- Transcript SHA256: $t_hash"
    echo "- Transcript Bytes: $t_bytes"
    echo "- Duration Seconds: $duration"
    echo ""
    echo "<<<REVIEW_TRANSCRIPT_BEGIN>>>"
  } > "$outfile"
  cat "$transcript_tmp" >> "$outfile"
  echo "<<<REVIEW_TRANSCRIPT_END>>>" >> "$outfile"
  rm -f "$transcript_tmp"
}

# Build code-review-expert findings artifact
build_cre_review() {
  local outfile="$1" content="$2" duration="$3"
  local ts="${4:-20260219T130000Z}"
  local findings_tmp
  findings_tmp="$(mktemp)"
  printf '%s\n' "$content" > "$findings_tmp"
  local f_hash f_bytes
  f_hash="$(sha256_of "$findings_tmp")"
  f_bytes="$(wc -c < "$findings_tmp" | tr -d '[:space:]')"
  {
    echo "# Code-review-expert findings"
    echo ""
    echo "- Story: $STORY"
    echo "- HEAD: $HEAD_SHA"
    echo "- Timestamp (UTC): $ts"
    echo "- Skill Path: ~/.agents/skills/code-review-expert/SKILL.md"
    echo "- Review Status: COMPLETE"
    echo "- Artifact Provenance: logger-v1"
    echo "- Generator Script: plans/code_review_expert_logged.sh"
    echo "- Content Source: from-file"
    echo "- Findings SHA256: $f_hash"
    echo "- Findings Bytes: $f_bytes"
    echo "- Duration Seconds: $duration"
    echo ""
    echo "## Findings"
    echo ""
    echo "<<<FINDINGS_BEGIN>>>"
  } > "$outfile"
  cat "$findings_tmp" >> "$outfile"
  echo "<<<FINDINGS_END>>>" >> "$outfile"
  rm -f "$findings_tmp"
}

run_gate() {
  bash "$GATE" "$STORY" --head "$HEAD_SHA" --artifacts-root "$cleanup_dir" 2>&1
}

assert_blocked() {
  local test_name="$1" expected_pattern="$2"
  local output rc
  set +e
  output="$(run_gate 2>&1)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]] && echo "$output" | grep -qE "$expected_pattern"; then
    echo "PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $test_name — exit=$rc"
    echo "$output" | tail -5
    FAIL=$((FAIL + 1))
  fi
}

assert_passes() {
  local test_name="$1"
  local output rc
  set +e
  output="$(run_gate 2>&1)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $test_name — exit=$rc"
    echo "$output" | tail -5
    FAIL=$((FAIL + 1))
  fi
}

# ── Shared content templates ──

PAD="Extra padding line to ensure transcript meets minimum byte threshold for the anti-fabrication validation gate checks."

# Get actual diff files from HEAD commit to ensure cross-reference checks pass
_DIFF_FILES="$(git -C "$ROOT" diff --name-only HEAD^..HEAD 2>/dev/null | head -3 || true)"
_DIFF_MENTION=""
while IFS= read -r _df; do
  [[ -n "$_df" ]] && _DIFF_MENTION+="$_df reviewed. "
done <<< "$_DIFF_FILES"
[[ -n "$_DIFF_MENTION" ]] || _DIFF_MENTION="crates/soldier_core/src/execution/pipeline.rs:42 reviewed. "

# Good review content (P2 only, no P0/P1)
GOOD_CONTENT="## P2 - Medium
$_DIFF_MENTION
crates/soldier_core/src/execution/mod.rs no rejection log.
specs/TRACE.yaml consistent. crates/soldier_core/src/venue/cache.rs:88 fine. $PAD"

# Cycle 1 content with P1 findings
CYCLE1_WITH_FINDINGS="## P1 - High
$_DIFF_MENTION
crates/soldier_core/src/execution/mod.rs drops error. specs/TRACE.yaml §2.3.
## P1 - High
**crates/soldier_core/src/venue/cache.rs:88** - Clock skew in TTL.
crates/soldier_core/tests/test_gate_ordering.rs:15 missing error tests. $PAD"

# Cycle 2 content with fewer findings (P1 count decreased to 0)
CYCLE2_IMPROVED="## P2 - Medium
$_DIFF_MENTION
specs/TRACE.yaml consistent. crates/soldier_core/src/execution/mod.rs good.
crates/soldier_core/src/venue/cache.rs TTL correct. $PAD"

# Cycle 2 content with MORE findings (regression)
CYCLE2_REGRESSION="## P1 - High
$_DIFF_MENTION
crates/soldier_core/src/execution/mod.rs drops errors.
## P1 - High
**crates/soldier_core/src/venue/cache.rs:88** - Clock skew unhandled.
## P1 - High
**crates/soldier_core/src/execution/pipeline.rs:100** - NEW null deref.
specs/TRACE.yaml inconsistent. $PAD"

# CRE content (always valid)
CRE_CONTENT="## P2 - Medium
$_DIFF_MENTION
specs/TRACE.yaml fine. crates/soldier_core/src/execution/mod.rs ok.
crates/soldier_core/src/venue/cache.rs:88 clean.
- Blocking: none
- Major: none
- Medium: style
- Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
$PAD"

# Helper: build a full artifact set with resolution
# Usage: build_full_set <cycle1_content> <cycle2_content> <resolution_extra> [<cycle1_ts> <cycle2_ts>]
build_full_set() {
  local c1_content="$1" c2_content="$2" resolution_extra="$3"
  local c1_ts="${4:-20260219T100000Z}" c2_ts="${5:-20260219T110000Z}"
  local sd="$cleanup_dir/$STORY"

  build_review "$sd/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "$GOOD_CONTENT" 60 "$c1_ts"
  build_review "$sd/codex/20260219_001_review.md" "plans/codex_review_logged.sh" "$c1_content" 60 "$c1_ts"
  build_review "$sd/codex/20260219_002_review.md" "plans/codex_review_logged.sh" "$c2_content" 60 "$c2_ts"
  build_cre_review "$sd/code_review_expert/20260219_001_review.md" "$CRE_CONTENT" 60 "$c2_ts"

  cat > "$sd/review_resolution.md" <<EOF
Story: $STORY
HEAD: $HEAD_SHA
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Kimi final review file: kimi/20260219_001_review.md
Codex final review file: codex/20260219_002_review.md
Codex second review file: codex/20260219_001_review.md
Code-review-expert final review file: code_review_expert/20260219_001_review.md
${resolution_extra}
EOF
}


# ══════════════════════════════════════════════════════════════════════
# PART 1: Anti-fabrication basics (Tests 1-6)
# These fail early (before full artifact processing) so they're fast
# ══════════════════════════════════════════════════════════════════════

echo "=== PART 1: Anti-fabrication basics ==="

echo "--- Test 1: Short transcript ---"
setup
build_review "$cleanup_dir/$STORY/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "Looks fine." 60
assert_blocked "short transcript" "transcript too short"
teardown

echo "--- Test 2: No file path references ---"
setup
LONG_NOPATH="The code looks good overall. No issues found in the review process. The implementation is solid and tested. The architecture is good. The error handling is comprehensive. No regressions detected. No security concerns. $PAD"
build_review "$cleanup_dir/$STORY/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "$LONG_NOPATH" 60
assert_blocked "no file paths" "no file path references"
teardown

echo "--- Test 3: File paths but no severity markers ---"
setup
NO_SEVERITY="The code in crates/soldier_core/src/execution/pipeline.rs looks good.
I reviewed crates/soldier_core/src/execution/mod.rs and found it clean.
Tests at crates/soldier_core/tests/test_gate_ordering.rs cover main scenarios.
Changes in specs/TRACE.yaml are well-structured. $PAD"
build_review "$cleanup_dir/$STORY/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "$NO_SEVERITY" 60
assert_blocked "no severity markers" "no severity markers"
teardown

echo "--- Test 4: Duration too short ---"
setup
build_review "$cleanup_dir/$STORY/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "$GOOD_CONTENT" 0
assert_blocked "too fast" "too fast for a real review"
teardown

echo "--- Test 5: Wrong diff files ---"
setup
WRONG_FILES="## P2 - Medium
**completely/made/up/file.rs:42** - Does not exist in diff.
another/fake/path.rs:10 does not log rejection. fake/test/file.rs:15 check.
bogus/module.rs:100 and nonexistent/code.rs:55 should be checked.
## P3 - Low
No other findings. bogus/module.rs:200 all invariants. $PAD"
build_review "$cleanup_dir/$STORY/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "$WRONG_FILES" 60
assert_blocked "diff cross-ref" "does not reference any files from the diff"
teardown

echo "--- Test 6: Missing codex ---"
setup
build_review "$cleanup_dir/$STORY/kimi/20260219_001_review.md" "plans/kimi_review_logged.sh" "$GOOD_CONTENT" 60
assert_blocked "missing codex" "need at least two Codex"
teardown


# ══════════════════════════════════════════════════════════════════════
# PART 2: Cycle-proof enforcement (Tests 7-12)
# ══════════════════════════════════════════════════════════════════════

echo ""
echo "=== PART 2: Cycle-proof enforcement ==="

# --- Test 7: Monotonicity violation — cycle 2 has MORE P1s ---
echo "--- Test 7: Cycle 2 regression (more P1s than cycle 1) ---"
setup
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_REGRESSION" ""
assert_blocked "monotonicity violation" "MORE high-severity findings"
teardown

# --- Test 8: Cycle 1 has findings, cycle 2 improved, but no finding disposition ---
echo "--- Test 8: Missing finding disposition section ---"
setup
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" ""
assert_blocked "missing disposition" "missing.*Finding Disposition"
teardown

# --- Test 9: Finding disposition present but undercounts cycle 1 ---
echo "--- Test 9: Disposition undercounts cycle 1 findings ---"
setup
DISPOSITION_UNDERCOUNT="
## Finding Disposition

Cycle 1 review: codex/20260219_001_review.md
Cycle 1 high-severity count: 1

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | pipeline.rs:42 | Error propagation | FIXED | commit abc1234 |

Cycle 2 review: codex/20260219_002_review.md
Cycle 2 high-severity count: 0
Cycle 2 new P0/P1 findings: 0"
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_UNDERCOUNT"
assert_blocked "undercount" "undercounting findings"
teardown

# --- Test 10: P0 finding with DEFERRED disposition ---
echo "--- Test 10: P0 finding cannot be DEFERRED ---"
setup
# Use content with P0
CYCLE1_P0="## P0 - Critical
$_DIFF_MENTION
crates/soldier_core/src/execution/mod.rs injection. specs/TRACE.yaml §4.1.
crates/soldier_core/src/venue/cache.rs fine. $PAD"

DISPOSITION_P0_DEFERRED="
## Finding Disposition

Cycle 1 review: codex/20260219_001_review.md
Cycle 1 high-severity count: 2

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P0 | pipeline.rs:42 | Security vulnerability | DEFERRED | debt D-001 slice 8 |
| F-2 | P1 | mod.rs:10 | Injection vector | FIXED | commit abc1234 |

Cycle 2 review: codex/20260219_002_review.md
Cycle 2 high-severity count: 0
Cycle 2 new P0/P1 findings: 0"
build_full_set "$CYCLE1_P0" "$CYCLE2_IMPROVED" "$DISPOSITION_P0_DEFERRED"
assert_blocked "P0 deferred" "P0 findings cannot be DEFERRED"
teardown

# --- Test 11: DEFERRED finding without debt reference ---
echo "--- Test 11: DEFERRED must reference debt item ---"
setup
DISPOSITION_NO_DEBT="
## Finding Disposition

Cycle 1 review: codex/20260219_001_review.md
Cycle 1 high-severity count: 2

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | pipeline.rs:42 | Error propagation | FIXED | commit abc1234 |
| F-2 | P1 | cache.rs:88 | Clock skew | DEFERRED | will fix later |

Cycle 2 review: codex/20260219_002_review.md
Cycle 2 high-severity count: 0
Cycle 2 new P0/P1 findings: 0"
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_NO_DEBT"
assert_blocked "deferred no debt" "DEFERRED finding must reference a debt item"
teardown

# --- Test 12: Happy path — findings tracked, disposition complete ---
echo "--- Test 12: Happy path — full cycle proof ---"
setup
DISPOSITION_COMPLETE="
## Finding Disposition

Cycle 1 review: codex/20260219_001_review.md
Cycle 1 high-severity count: 2

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | pipeline.rs:42 | Error propagation missing | FIXED | commit abc1234 |
| F-2 | P1 | cache.rs:88 | Clock skew in TTL cache | FIXED | commit def5678 |

Cycle 2 review: codex/20260219_002_review.md
Cycle 2 high-severity count: 0
Cycle 2 new P0/P1 findings: 0"
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_COMPLETE"
assert_passes "full cycle proof"
teardown

# --- Test 13: No findings in cycle 1 — disposition not required ---
echo "--- Test 13: Clean cycle 1, no disposition needed ---"
setup
build_full_set "$GOOD_CONTENT" "$GOOD_CONTENT" ""
assert_passes "clean cycle 1"
teardown

# ══════════════════════════════════════════════════════════════════════
# PART 3: Supervisor enforcement (Tests 14-17)
# ══════════════════════════════════════════════════════════════════════

echo ""
echo "=== PART 3: Supervisor enforcement ==="

# Helper: build supervisor artifact
# Usage: build_supervisor <outfile> <checkpoint> <verdict> <reason>
build_supervisor() {
  local outfile="$1" checkpoint="$2" verdict="$3" reason="$4"
  {
    echo "# Supervisor Check: $checkpoint"
    echo ""
    echo "- Story: $STORY"
    echo "- HEAD: $HEAD_SHA"
    echo "- Checkpoint: $checkpoint"
    echo "- Timestamp (UTC): 20260219T120000Z"
    echo "- Model: claude-sonnet-4-6"
    echo "- Verdict: $verdict"
    echo "- Reason: $reason"
    echo "- Duration Seconds: 15"
    echo "- Response SHA256: 0000000000000000000000000000000000000000000000000000000000000000"
    echo "- Response Bytes: 100"
    echo "- Artifact Provenance: supervisor-v1"
    echo "- Generator Script: plans/supervisor_check.sh"
    echo ""
    echo "## Response"
    echo ""
    echo "<<<SUPERVISOR_RESPONSE_BEGIN>>>"
    echo "VERDICT: $verdict"
    echo "REASON: $reason"
    echo "<<<SUPERVISOR_RESPONSE_END>>>"
  } > "$outfile"
}

# --- Test 14: Missing supervisor artifacts blocks gate ---
echo "--- Test 14: Missing supervisor blocks gate ---"
setup
export REQUIRE_SUPERVISOR=1
DISPOSITION_COMPLETE="
## Finding Disposition

Cycle 1 review: codex/20260219_001_review.md
Cycle 1 high-severity count: 2

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | pipeline.rs:42 | Error propagation | FIXED | commit abc1234 |
| F-2 | P1 | cache.rs:88 | Clock skew | FIXED | commit def5678 |

Cycle 2 review: codex/20260219_002_review.md
Cycle 2 high-severity count: 0
Cycle 2 new P0/P1 findings: 0"
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_COMPLETE"
# No supervisor artifacts created
assert_blocked "missing supervisor" "missing supervisor post-cycle1"
export REQUIRE_SUPERVISOR=0
teardown

# --- Test 15: Supervisor FAIL verdict blocks gate ---
echo "--- Test 15: Supervisor FAIL blocks gate ---"
setup
export REQUIRE_SUPERVISOR=1
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_COMPLETE"
mkdir -p "$cleanup_dir/$STORY/supervisor"
build_supervisor "$cleanup_dir/$STORY/supervisor/post-cycle1_20260219T120000Z.md" "post-cycle1" "PASS" "Findings are real"
build_supervisor "$cleanup_dir/$STORY/supervisor/post-fix_20260219T120100Z.md" "post-fix" "FAIL" "Diff does not address F-2"
build_supervisor "$cleanup_dir/$STORY/supervisor/post-cycle2_20260219T120200Z.md" "post-cycle2" "PASS" "Review is legitimate"
assert_blocked "supervisor FAIL" "supervisor post-fix verdict is FAIL"
export REQUIRE_SUPERVISOR=0
teardown

# --- Test 16: Supervisor artifacts for wrong HEAD ---
echo "--- Test 16: Supervisor wrong HEAD ---"
setup
export REQUIRE_SUPERVISOR=1
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_COMPLETE"
mkdir -p "$cleanup_dir/$STORY/supervisor"
# Create supervisor artifacts with wrong HEAD
for cp in post-cycle1 post-fix post-cycle2; do
  {
    echo "# Supervisor Check: $cp"
    echo ""
    echo "- Story: $STORY"
    echo "- HEAD: 0000000000000000000000000000000000000000"
    echo "- Checkpoint: $cp"
    echo "- Verdict: PASS"
    echo "- Reason: All good"
    echo "- Artifact Provenance: supervisor-v1"
    echo "- Generator Script: plans/supervisor_check.sh"
  } > "$cleanup_dir/$STORY/supervisor/${cp}_20260219T120000Z.md"
done
assert_blocked "wrong HEAD supervisor" "missing supervisor post-cycle1"
export REQUIRE_SUPERVISOR=0
teardown

# --- Test 17: All supervisor PASS — happy path ---
echo "--- Test 17: All supervisor PASS ---"
setup
export REQUIRE_SUPERVISOR=1
build_full_set "$CYCLE1_WITH_FINDINGS" "$CYCLE2_IMPROVED" "$DISPOSITION_COMPLETE"
mkdir -p "$cleanup_dir/$STORY/supervisor"
build_supervisor "$cleanup_dir/$STORY/supervisor/post-cycle1_20260219T120000Z.md" "post-cycle1" "PASS" "Findings match actual code"
build_supervisor "$cleanup_dir/$STORY/supervisor/post-fix_20260219T120100Z.md" "post-fix" "PASS" "Diff addresses all findings"
build_supervisor "$cleanup_dir/$STORY/supervisor/post-cycle2_20260219T120200Z.md" "post-cycle2" "PASS" "Review is legitimate"
assert_passes "all supervisor PASS"
export REQUIRE_SUPERVISOR=0
teardown

echo ""
echo "============================================"
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
