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

[[ -f "$review_cmd" ]] || fail "missing review-stack command wrapper"
[[ -f "$review_alias" ]] || fail "missing /6 alias command wrapper"
[[ -f "$review_skill_wrapper" ]] || fail "missing review-stack skill wrapper"

assert_file_contains "$review_cmd" 'Use the Skill tool with skill name "review-stack"'
assert_file_contains "$review_cmd" 'git rev-parse HEAD'
assert_file_contains "$review_cmd" 'artifacts/pr-review-gate'
assert_file_not_contains "$review_cmd" '6-Skill Review Stack'

assert_file_contains "$review_alias" 'Alias for /review-stack'
assert_file_not_contains "$review_alias" 'full 6-skill review stack'

assert_file_contains "$review_skill_wrapper" 'git rev-parse --show-toplevel'
assert_file_contains "$review_skill_wrapper" '/SKILLS/review-stack.md'

echo "test_review_command_wrappers.sh: ok"
