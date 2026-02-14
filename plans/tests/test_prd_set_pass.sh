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
story_id="WF-001"

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

  mkdir -p \
    "$story_root/self_review" \
    "$story_root/kimi" \
    "$story_root/codex" \
    "$story_root/code_review_expert"

  cat > "$self_file" <<EOF
Story: $story_id
HEAD: $review_head
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF

  cat > "$kimi_file" <<EOF
- Story: $story_id
- HEAD: $review_head
EOF

  cat > "$codex_final_file" <<EOF
- Story: $story_id
- HEAD: $review_head
EOF

  cat > "$codex_second_file" <<EOF
- Story: $story_id
- HEAD: $review_head
EOF

  cat > "$expert_file" <<EOF
- Story: $story_id
- HEAD: $review_head
- Review Status: COMPLETE
- Blocking: none
- Major: none
- Medium: none
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
}

setup_case() {
  local case_dir="$1"
  local verify_head="$2"
  local review_head="${3:-$verify_head}"

  mkdir -p "$case_dir/artifacts"
  cat > "$case_dir/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false}
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

echo "PASS: prd_set_pass"
