#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/plans/story_review_gate.sh"

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
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

write_valid_case() {
  local base="$1"
  local story="$2"
  local head_sha="$3"

  local story_dir="$base/$story"
  local self_dir="$story_dir/self_review"
  local codex_dir="$story_dir/codex"

  mkdir -p "$self_dir" "$codex_dir"

  cat > "$self_dir/20260209T000000Z_self_review.md" <<EOF
# Self Review
Story: $story
HEAD: $head_sha
Decision: PASS
Checklist:
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF

  cat > "$codex_dir/20260209T000000Z_review.md" <<EOF
# Codex review
- Story: $story
- HEAD: $head_sha
EOF

  cat > "$story_dir/review_resolution.md" <<EOF
Story: $story
HEAD: $head_sha
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Codex final review file: codex/20260209T000000Z_review.md
EOF
}

[[ -x "$GATE" ]] || fail "missing executable gate: $GATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

story="S1-TEST"
head_sha="abc123def456"

# Case 1: valid fixture passes.
case1="$tmp_dir/case1"
write_valid_case "$case1" "$story" "$head_sha"
"$GATE" "$story" --head "$head_sha" --artifacts-root "$case1" >/dev/null

# Case 2: missing self review.
case2="$tmp_dir/case2"
write_valid_case "$case2" "$story" "$head_sha"
rm -f "$case2/$story/self_review/"*_self_review.md
expect_fail "missing self review" "missing self-review artifact" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case2"

# Case 3: self review HEAD mismatch.
case3="$tmp_dir/case3"
write_valid_case "$case3" "$story" "$head_sha"
sed -i.bak "s/HEAD: $head_sha/HEAD: deadbeef/" "$case3/$story/self_review/20260209T000000Z_self_review.md"
rm -f "$case3/$story/self_review/20260209T000000Z_self_review.md.bak"
expect_fail "self review head mismatch" "self-review not for current HEAD" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case3"

# Case 4: codex review missing for HEAD.
case4="$tmp_dir/case4"
write_valid_case "$case4" "$story" "$head_sha"
sed -i.bak "s/- HEAD: $head_sha/- HEAD: deadbeef/" "$case4/$story/codex/20260209T000000Z_review.md"
rm -f "$case4/$story/codex/20260209T000000Z_review.md.bak"
expect_fail "codex head mismatch" "missing Codex review artifact for HEAD" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case4"

# Case 5: resolution unresolved findings.
case5="$tmp_dir/case5"
write_valid_case "$case5" "$story" "$head_sha"
sed -i.bak "s/Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0/Remaining findings: BLOCKING=0 MAJOR=1 MEDIUM=0/" "$case5/$story/review_resolution.md"
rm -f "$case5/$story/review_resolution.md.bak"
expect_fail "resolution unresolved findings" "resolution must assert no BLOCKING/MAJOR/MEDIUM remain" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case5"

# Case 6: codex ref escapes codex directory.
case6="$tmp_dir/case6"
write_valid_case "$case6" "$story" "$head_sha"
sed -i.bak "s#Codex final review file: codex/20260209T000000Z_review.md#Codex final review file: ../self_review/20260209T000000Z_self_review.md#" "$case6/$story/review_resolution.md"
rm -f "$case6/$story/review_resolution.md.bak"
expect_fail "codex ref escape" "Codex final review file must be inside" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case6"

# Case 7: self review decision must be exactly PASS.
case7="$tmp_dir/case7"
write_valid_case "$case7" "$story" "$head_sha"
sed -i.bak "s/Decision: PASS/Decision: PASSING/" "$case7/$story/self_review/20260209T000000Z_self_review.md"
rm -f "$case7/$story/self_review/20260209T000000Z_self_review.md.bak"
expect_fail "self review decision exact" "self-review Decision is not PASS" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case7"

# Case 8: blocking addressed must be exactly YES.
case8="$tmp_dir/case8"
write_valid_case "$case8" "$story" "$head_sha"
sed -i.bak "s/Blocking addressed: YES/Blocking addressed: YES_BUT_NOT_REALLY/" "$case8/$story/review_resolution.md"
rm -f "$case8/$story/review_resolution.md.bak"
expect_fail "blocking addressed exact" "resolution missing 'Blocking addressed: YES'" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case8"

# Case 9: remaining findings line must be exact.
case9="$tmp_dir/case9"
write_valid_case "$case9" "$story" "$head_sha"
sed -i.bak "s/Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0/Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0 EXTRA=1/" "$case9/$story/review_resolution.md"
rm -f "$case9/$story/review_resolution.md.bak"
expect_fail "remaining findings exact" "resolution must assert no BLOCKING/MAJOR/MEDIUM remain" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case9"

# Case 10: digest-only codex artifacts are rejected.
case10="$tmp_dir/case10"
write_valid_case "$case10" "$story" "$head_sha"
mv "$case10/$story/codex/20260209T000000Z_review.md" "$case10/$story/codex/20260209T000000Z_digest.md"
sed -i.bak "s/Codex final review file: codex\\/20260209T000000Z_review.md/Codex final review file: codex\\/20260209T000000Z_digest.md/" "$case10/$story/review_resolution.md"
rm -f "$case10/$story/review_resolution.md.bak"
expect_fail "digest-only codex" "missing Codex review artifact for HEAD" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case10"

echo "PASS: story review gate fixtures"
