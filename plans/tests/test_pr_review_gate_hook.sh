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

write_git_wrapper() {
  local path="$1"
  local real_git="$2"
  local ambiguous_short="$3"

  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "rev-parse" && "\${2:-}" == "${ambiguous_short}^{commit}" ]]; then
  echo "fatal: ambiguous short SHA" >&2
  exit 128
fi
exec "$real_git" "\$@"
EOF
  chmod +x "$path"
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

write_review_marker "$marker_path" "PASS" "head" "$(git -C "$repo" rev-parse --short HEAD)"

(
  cd "$repo"
  expect_pass "fresh marker permits gh pr create with --repo" "gh --repo owner/repo pr create --title ready"
)

target_repo="$tmp_dir/target-repo"
mkdir -p "$target_repo"
git -C "$target_repo" init -q
git -C "$target_repo" config user.name "Target User"
git -C "$target_repo" config user.email "target@example.com"
git -C "$target_repo" checkout -qb "story/S2-pr-gate-hook"
echo "target" > "$target_repo/target.txt"
git -C "$target_repo" add target.txt
git -C "$target_repo" commit -qm "target seed"

target_branch_name="$(git -C "$target_repo" rev-parse --abbrev-ref HEAD)"
target_safe_branch="${target_branch_name//\//_}"
mkdir -p "$target_repo/artifacts/pr-review-gate"
write_review_marker "$target_repo/artifacts/pr-review-gate/${target_safe_branch}.json" "PASS" "head" "$(git -C "$target_repo" rev-parse --short HEAD)"

rm -f "$marker_path"
(
  cd "$repo"
  expect_pass "env -C target repo resolves marker state in target repo" "env -C "$target_repo" GH_TOKEN=test gh pr create --title ready"
)

write_review_marker "$marker_path" "PASS" "head" "$(git -C "$repo" rev-parse --short HEAD)"

mkdir -p "$repo/nested/worktree"
(
  cd "$repo/nested/worktree"
  expect_pass "subdirectory invocation still finds repo-root marker" "gh pr create --title ready"
)

rm -f "$marker_path"
mkdir -p "$repo/nested/worktree/artifacts/pr-review-gate"
write_review_marker "$repo/nested/worktree/artifacts/pr-review-gate/${safe_branch}.json" "PASS" "head" "$(git -C "$repo" rev-parse --short HEAD)"

(
  cd "$repo/nested/worktree"
  expect_pass "subdirectory invocation accepts cwd-relative marker during migration" "gh pr create --title ready"
)

write_review_marker "$marker_path" "PASS" "head" "deadbeef"
write_review_marker "$repo/nested/worktree/artifacts/pr-review-gate/${safe_branch}.json" "PASS" "head" "$(git -C "$repo" rev-parse --short HEAD)"

(
  cd "$repo/nested/worktree"
  expect_pass "subdirectory invocation falls back to fresh cwd marker when repo marker is stale" "gh pr create --title ready"
)

rm -f "$repo/nested/worktree/artifacts/pr-review-gate/${safe_branch}.json"
write_review_marker "$marker_path" "CONDITIONAL_PASS" "head_commit" "$(git -C "$repo" rev-parse --short HEAD)"

(
  cd "$repo"
  expect_pass "env-wrapped gh pr create still triggers gate" "env GH_TOKEN=test gh pr create --title ready"
)

(
  cd "$repo"
  expect_pass "env -C wrapped gh pr create still triggers gate" "env -C . GH_TOKEN=test gh pr create --title ready"
)

(
  cd "$repo"
  expect_pass "env --chdir wrapped gh pr create still triggers gate" "env --chdir=. GH_TOKEN=test gh pr create --title ready"
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
  expect_pass "gh help pr create is not gated" "gh help pr create"
)

(
  cd "$repo"
  expect_pass "gh --help pr create is not gated" "gh --help pr create"
)

(
  cd "$repo"
  expect_pass "gh pr create --help is not gated" "gh pr create --help"
)

(
  cd "$repo"
  expect_block "gh pr create with title containing help still blocks when marker missing" "No review-stack result" "gh pr create --title help"
)

(
  cd "$repo"
  expect_block "gh pr create with quoted ampersand still blocks when marker missing" "No review-stack result" "gh pr create --title 'a & b'"
)

(
  cd "$repo"
  expect_block "gh pr create with quoted pipe still blocks when marker missing" "No review-stack result" "gh pr create --body 'a | b'"
)

(
  cd "$repo"
  expect_block "gh pr create with quoted semicolon still blocks when marker missing" "No review-stack result" "gh pr create --body 'a ; b'"
)

(
  cd "$repo"
  expect_block "gh pr create with body containing version still blocks when marker missing" "No review-stack result" "gh pr create --body version"
)

(
  cd "$repo"
  expect_block "env -C wrapped gh pr create still blocks without marker" "No review-stack result" "env -C . GH_TOKEN=test gh pr create --title ready"
)

(
  cd "$repo"
  expect_block "env --chdir wrapped gh pr create still blocks without marker" "No review-stack result" "env --chdir=. GH_TOKEN=test gh pr create --title ready"
)

(
  cd "$repo"
  expect_block "env -S wrapped gh pr create still blocks without marker" "No review-stack result" "env -S 'GH_TOKEN=test gh pr create --title ready'"
)

(
  cd "$repo"
  expect_block "gh global flags still trigger gate" "No review-stack result" "gh -R owner/repo pr create --title ready"
)

old_head="$(git -C "$repo" rev-parse --short HEAD)"
echo "next" >> "$repo/sample.txt"
git -C "$repo" add sample.txt
git -C "$repo" commit -qm "advance head"
new_head_short="$(git -C "$repo" rev-parse --short HEAD)"
new_head_full="$(git -C "$repo" rev-parse HEAD)"

write_review_marker "$marker_path" "PASS" "head" "$old_head"

(
  cd "$repo"
  # MARKER_HEAD ($old_head) appears as-is; HEAD_SHA is full SHA ($new_head_full)
  expect_block "stale marker blocks current head" "targets HEAD '$old_head' but current HEAD is '$new_head_full'" "gh pr create --title ready"
)

write_review_marker "$marker_path" "PASS" "head_commit" "$new_head_short"
write_external_marker "$external_marker_path" "head" "$old_head"

(
  cd "$repo"
  expect_pass_with_output "stale external marker warns without blocking" "targets HEAD '$old_head' but current HEAD is '$new_head_full'" "gh pr create --title ready"
)

very_short_head="${new_head_short:0:6}"
write_review_marker "$marker_path" "PASS" "head" "$very_short_head"

(
  cd "$repo"
  expect_pass "legacy marker heads shorter than 7 chars still match current HEAD prefix" "gh pr create --title ready"
)

real_git="$(command -v git)"
mock_git_dir="$tmp_dir/mock_git"
mkdir -p "$mock_git_dir"
write_git_wrapper "$mock_git_dir/git" "$real_git" "$new_head_short"

(
  cd "$repo"
  set +e
  ambiguous_output="$(PATH="$mock_git_dir:$PATH" python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" "gh pr create --title ready" | bash "$HOOK" 2>&1)"
  ambiguous_rc=$?
  set -e
  [[ $ambiguous_rc -eq 0 ]] || fail "ambiguous short marker that still matches current HEAD should pass, got rc=$ambiguous_rc output=$ambiguous_output"
)

grep -Fq 'git rev-parse HEAD' "$ROOT/.claude/commands/review-stack.md" || fail "review-stack marker writer should use full HEAD SHA"
grep -Fq 'git rev-parse HEAD' "$ROOT/.claude/commands/external-review.md" || fail "external-review marker writer should use full HEAD SHA"

echo "test_pr_review_gate_hook.sh: ok"
