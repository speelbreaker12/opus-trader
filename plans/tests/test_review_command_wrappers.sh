#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local pattern="$2"
  grep -Fq -- "$pattern" "$path" || fail "expected '$pattern' in $path"
}

assert_file_not_contains() {
  local path="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$path"; then
    fail "did not expect '$pattern' in $path"
  fi
}

review_cmd="$ROOT/.claude/commands/review-stack.md"
review_alias="$ROOT/.claude/commands/6.md"
review_skill_wrapper="$ROOT/.claude/skills/review-stack/SKILL.md"
claude_commit_cmd="$ROOT/.claude/commands/commit.md"
claude_push_pr_cmd="$ROOT/.claude/commands/push-pr.md"
codex_commit_cmd="$ROOT/.codex/commands/commit.md"
codex_push_pr_cmd="$ROOT/.codex/commands/push-pr.md"

[[ -f "$review_cmd" ]] || fail "missing review-stack command wrapper"
[[ -f "$review_alias" ]] || fail "missing /6 alias command wrapper"
[[ -f "$review_skill_wrapper" ]] || fail "missing review-stack skill wrapper"
[[ -f "$claude_commit_cmd" ]] || fail "missing claude /commit command wrapper"
[[ -f "$claude_push_pr_cmd" ]] || fail "missing claude /push-pr command wrapper"
[[ -f "$codex_commit_cmd" ]] || fail "missing codex /commit command wrapper"
[[ -f "$codex_push_pr_cmd" ]] || fail "missing codex /push-pr command wrapper"

assert_file_contains "$review_cmd" '# SKILL: /review-stack'
assert_file_contains "$review_cmd" 'git rev-parse HEAD'
assert_file_contains "$review_cmd" 'artifacts/pr-review-gate'

assert_file_contains "$review_alias" 'Alias for /review-stack'
assert_file_not_contains "$review_alias" 'full 6-skill review stack'

assert_file_contains "$review_skill_wrapper" 'git rev-parse --show-toplevel'
assert_file_contains "$review_skill_wrapper" '/SKILLS/review-stack.md'
assert_file_contains "$claude_commit_cmd" 'Use the `/commit` skill from `SKILLS/commit.md`'
assert_file_contains "$claude_push_pr_cmd" 'Use the `/push-pr` skill from `SKILLS/push-pr.md`'
assert_file_contains "$codex_commit_cmd" 'Use the `/commit` skill from `SKILLS/commit.md`'
assert_file_contains "$codex_push_pr_cmd" 'Use the `/push-pr` skill from `SKILLS/push-pr.md`'

echo "test_review_command_wrappers.sh: ok"
