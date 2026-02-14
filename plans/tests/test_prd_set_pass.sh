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

setup_case() {
  local case_dir="$1"
  local verify_head="$2"

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

  cat > "$case_dir/fake_story_review_gate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" > "${STORY_GATE_ARGS_FILE:?missing STORY_GATE_ARGS_FILE}"
EOF
  chmod +x "$case_dir/fake_story_review_gate.sh"
}

success_case="$tmp_dir/success"
mkdir -p "$success_case"
setup_case "$success_case" "$head_sha"

success_output="$(
  cd "$ROOT" && \
  PRD_FILE="$success_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$success_case/artifacts" \
  STORY_REVIEW_GATE="$success_case/fake_story_review_gate.sh" \
  STORY_GATE_ARGS_FILE="$success_case/gate.args" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$success_case/artifacts/contract_review.json"
)"

echo "$success_output" | grep -Fq "Updated task $story_id: passes=true" || fail "missing success output"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==true)' "$success_case/prd.json" >/dev/null || fail "passes was not updated to true"
grep -Fxq "$story_id --head $head_sha" "$success_case/gate.args" || fail "story review gate did not receive current HEAD"

mismatch_case="$tmp_dir/mismatch"
mkdir -p "$mismatch_case"
setup_case "$mismatch_case" "deadbeef"

set +e
mismatch_output="$(
  cd "$ROOT" && \
  PRD_FILE="$mismatch_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$mismatch_case/artifacts" \
  STORY_REVIEW_GATE="$mismatch_case/fake_story_review_gate.sh" \
  STORY_GATE_ARGS_FILE="$mismatch_case/gate.args" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$mismatch_case/artifacts/contract_review.json" 2>&1
)"
mismatch_rc=$?
set -e

[[ "$mismatch_rc" -ne 0 ]] || fail "expected head mismatch to fail"
echo "$mismatch_output" | grep -Fq "ERROR: verify metadata HEAD mismatch" || fail "missing head mismatch diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$mismatch_case/prd.json" >/dev/null || fail "passes changed despite head mismatch failure"
[[ ! -f "$mismatch_case/gate.args" ]] || fail "story review gate should not run on head mismatch"

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
  STORY_REVIEW_GATE="$head_flip_case/fake_story_review_gate.sh" \
  STORY_GATE_ARGS_FILE="$head_flip_case/gate.args" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$head_flip_case/artifacts/contract_review.json" 2>&1
)"
head_flip_rc=$?
set -e

[[ "$head_flip_rc" -ne 0 ]] || fail "expected pass flip to fail when HEAD changes mid-run"
echo "$head_flip_output" | grep -Fq "ERROR: HEAD changed during pass flip validation" || fail "missing mid-run head-change diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$head_flip_case/prd.json" >/dev/null || fail "passes changed despite mid-run head-change failure"
grep -Fxq "$story_id --head $head_sha" "$head_flip_case/gate.args" || fail "story review gate should run with the initial HEAD before final check"

echo "PASS: prd_set_pass"
