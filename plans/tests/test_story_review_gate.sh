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
  local kimi_dir="$story_dir/kimi"
  local code_review_expert_dir="$story_dir/code_review_expert"

  mkdir -p "$self_dir" "$codex_dir" "$kimi_dir" "$code_review_expert_dir"

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

  cat > "$codex_dir/20260209T000100Z_review.md" <<EOF
# Codex review (second pass)
- Story: $story
- HEAD: $head_sha
EOF

  cat > "$kimi_dir/20260209T000050Z_review.md" <<EOF
# Kimi review
- Story: $story
- HEAD: $head_sha
EOF

  cat > "$code_review_expert_dir/20260209T000080Z_review.md" <<EOF
# Code-review-expert findings
- Story: $story
- HEAD: $head_sha
- Review Status: COMPLETE
- Blocking: none
- Major: none
- Medium: none
EOF

  cat > "$story_dir/review_resolution.md" <<EOF
Story: $story
HEAD: $head_sha
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Kimi final review file: kimi/20260209T000050Z_review.md
Codex final review file: codex/20260209T000100Z_review.md
Codex second review file: codex/20260209T000000Z_review.md
Code-review-expert final review file: code_review_expert/20260209T000080Z_review.md
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

# Case 3b: newest self review may target older HEAD; gate should still find matching HEAD artifact.
case3b="$tmp_dir/case3b"
write_valid_case "$case3b" "$story" "$head_sha"
cat > "$case3b/$story/self_review/20260210T000000Z_self_review.md" <<EOF
# Self Review (old head)
Story: $story
HEAD: deadbeef
Decision: PASS
Checklist:
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF
"$GATE" "$story" --head "$head_sha" --artifacts-root "$case3b" >/dev/null

# Case 4: must keep at least two codex reviews for HEAD.
case4="$tmp_dir/case4"
write_valid_case "$case4" "$story" "$head_sha"
rm -f "$case4/$story/codex/20260209T000100Z_review.md"
expect_fail "codex count minimum" "need at least two Codex review artifacts for HEAD" \
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
sed -i.bak "s#Codex final review file: codex/20260209T000100Z_review.md#Codex final review file: ../self_review/20260209T000000Z_self_review.md#" "$case6/$story/review_resolution.md"
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
cp "$case10/$story/codex/20260209T000100Z_review.md" "$case10/$story/codex/20260209T000100Z_digest.md"
sed -i.bak "s/Codex final review file: codex\\/20260209T000100Z_review.md/Codex final review file: codex\\/20260209T000100Z_digest.md/" "$case10/$story/review_resolution.md"
rm -f "$case10/$story/review_resolution.md.bak"
expect_fail "digest-only codex ref" "Codex final review file must be a *_review.md artifact" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case10"

# Case 11: missing Kimi review artifact for HEAD.
case11="$tmp_dir/case11"
write_valid_case "$case11" "$story" "$head_sha"
rm -f "$case11/$story/kimi/20260209T000050Z_review.md"
expect_fail "missing kimi review" "missing Kimi review artifact for HEAD" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case11"

# Case 12: codex symlink escape to kimi directory is rejected.
case12="$tmp_dir/case12"
write_valid_case "$case12" "$story" "$head_sha"
ln -s ../kimi/20260209T000050Z_review.md "$case12/$story/codex/20260209T000200Z_review.md"
sed -i.bak "s/Codex final review file: codex\\/20260209T000100Z_review.md/Codex final review file: codex\\/20260209T000200Z_review.md/" "$case12/$story/review_resolution.md"
rm -f "$case12/$story/review_resolution.md.bak"
expect_fail "codex symlink escape" "Codex final review file must be inside" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case12"

# Case 13: missing code-review-expert artifact for HEAD.
case13="$tmp_dir/case13"
write_valid_case "$case13" "$story" "$head_sha"
rm -f "$case13/$story/code_review_expert/20260209T000080Z_review.md"
expect_fail "missing code-review-expert review" "missing code-review-expert review artifact for HEAD" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case13"

# Case 14: code-review-expert ref escapes directory.
case14="$tmp_dir/case14"
write_valid_case "$case14" "$story" "$head_sha"
sed -i.bak "s#Code-review-expert final review file: code_review_expert/20260209T000080Z_review.md#Code-review-expert final review file: ../kimi/20260209T000050Z_review.md#" "$case14/$story/review_resolution.md"
rm -f "$case14/$story/review_resolution.md.bak"
expect_fail "code-review-expert ref escape" "Code-review-expert final review file must be inside" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case14"

# Case 15: code-review-expert review status must be COMPLETE.
case15="$tmp_dir/case15"
write_valid_case "$case15" "$story" "$head_sha"
sed -i.bak "s/- Review Status: COMPLETE/- Review Status: DRAFT/" "$case15/$story/code_review_expert/20260209T000080Z_review.md"
rm -f "$case15/$story/code_review_expert/20260209T000080Z_review.md.bak"
expect_fail "code-review-expert status complete" "code-review-expert review must be marked '- Review Status: COMPLETE'" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case15"

# Case 16: unresolved placeholders are rejected.
case16="$tmp_dir/case16"
write_valid_case "$case16" "$story" "$head_sha"
sed -i.bak "s/- Blocking: none/- Blocking: <none | summary>/" "$case16/$story/code_review_expert/20260209T000080Z_review.md"
rm -f "$case16/$story/code_review_expert/20260209T000080Z_review.md.bak"
expect_fail "code-review-expert unresolved placeholder" "code-review-expert review contains unresolved placeholder" \
  "$GATE" "$story" --head "$head_sha" --artifacts-root "$case16"

# Case 17: artifact-only top commit can fallback review HEAD to parent commit.
case17_repo="$tmp_dir/case17_repo"
mkdir -p "$case17_repo/plans"
cp "$GATE" "$case17_repo/plans/story_review_gate.sh"
chmod +x "$case17_repo/plans/story_review_gate.sh"

(
  cd "$case17_repo"
  git init -q
  git config user.name "story-review-gate-test"
  git config user.email "story-review-gate-test@example.com"
  git config commit.gpgsign false

  mkdir -p src
  echo "baseline" > src/baseline.txt
  git add src/baseline.txt
  git commit -q -m "baseline"
  parent_sha="$(git rev-parse HEAD)"

  write_valid_case "$case17_repo/artifacts/story" "$story" "$parent_sha"
  git add artifacts/story/"$story"
  git commit -q -m "artifact-only review bundle"
  child_sha="$(git rev-parse HEAD)"

  "$case17_repo/plans/story_review_gate.sh" "$story" --head "$child_sha" --artifacts-root "$case17_repo/artifacts/story" >/dev/null
)

echo "PASS: story review gate fixtures"
