#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/pr-review-gate-hook.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_block() {
  local label="$1"
  local pattern="$2"
  local command_text="$3"

  local output=""
  set +e
  output="$(python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" "$command_text" | bash "$HOOK" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 2 ]]; then
    fail "$label expected exit 2, got $rc with output: $output"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected text '$pattern' in output: $output"
  fi
}

expect_pass() {
  local label="$1"
  local command_text="$2"

  local output=""
  set +e
  output="$(python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" "$command_text" | bash "$HOOK" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
}

expect_pass_with_output() {
  local label="$1"
  local pattern="$2"
  local command_text="$3"

  local output=""
  set +e
  output="$(python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" "$command_text" | bash "$HOOK" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected text '$pattern' in output: $output"
  fi
}

write_review_marker() {
  local path="$1"
  local verdict="$2"
  local field_name="$3"
  local field_value="$4"

  python3 -c "
import json, sys
verdict, field, value = sys.argv[1:4]
print(json.dumps({'verdict': verdict, field: value}))
" "$verdict" "$field_name" "$field_value" > "$path"
}

write_external_marker() {
  local path="$1"
  local field_name="$2"
  local field_value="$3"

  python3 -c "
import json, sys
field, value = sys.argv[1:3]
print(json.dumps({field: value}))
" "$field_name" "$field_value" > "$path"
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo"

git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" checkout -qb "story/S1-pr-gate-hook"

echo "seed" > "$repo/sample.txt"
git -C "$repo" add sample.txt
git -C "$repo" commit -qm "seed"

branch_name="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
safe_branch="${branch_name//\//_}"
marker_dir="$repo/artifacts/pr-review-gate"
marker_path="$marker_dir/${safe_branch}.json"
external_marker_path="$marker_dir/${safe_branch}.external.json"
mkdir -p "$marker_dir"

write_review_marker "$marker_path" "PASS" "head" "$(git -C "$repo" rev-parse HEAD)"

(
  cd "$repo"
  expect_pass "fresh marker permits gh pr create with --repo" "gh --repo owner/repo pr create --title ready"
)

write_review_marker "$marker_path" "CONDITIONAL_PASS" "head_commit" "$(git -C "$repo" rev-parse HEAD)"

(
  cd "$repo"
  expect_pass "env-wrapped gh pr create still triggers gate" "env GH_TOKEN=test gh pr create --title ready"
)

(
  cd "$repo"
  expect_pass "command-wrapped gh pr create still triggers gate" "command gh pr create --title ready"
)

rm -f "$marker_path"
(
  cd "$repo"
  expect_block "plain gh pr create blocks without marker" "No review-stack result" "gh pr create --title ready"
)

(
  cd "$repo"
  expect_block "gh global flags still trigger gate" "No review-stack result" "gh -R owner/repo pr create --title ready"
)

old_head="$(git -C "$repo" rev-parse HEAD)"
echo "next" >> "$repo/sample.txt"
git -C "$repo" add sample.txt
git -C "$repo" commit -qm "advance head"
new_head="$(git -C "$repo" rev-parse HEAD)"

write_review_marker "$marker_path" "PASS" "head" "$old_head"

(
  cd "$repo"
  expect_block "stale marker blocks current head" "targets HEAD '$old_head' but current HEAD is '$new_head'" "gh pr create --title ready"
)

write_review_marker "$marker_path" "PASS" "head_commit" "$new_head"
write_external_marker "$external_marker_path" "head" "$old_head"

(
  cd "$repo"
  expect_pass_with_output "stale external marker warns without blocking" "targets HEAD '$old_head' but current HEAD is '$new_head'" "gh pr create --title ready"
)

echo "test_pr_review_gate_hook.sh: ok"
