#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_tracked_file() {
  local relpath="$1"
  git -C "$ROOT" ls-files --error-unmatch "$relpath" >/dev/null 2>&1 \
    || fail "missing tracked file: $relpath"
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
codex_skills_root="$ROOT/.codex/skills"
claude_skills_root="$ROOT/.claude/skills"

[[ -f "$review_cmd" ]] || fail "missing review-stack command wrapper"
[[ -f "$review_alias" ]] || fail "missing /6 alias command wrapper"
[[ -f "$review_skill_wrapper" ]] || fail "missing review-stack skill wrapper"
[[ -f "$claude_commit_cmd" ]] || fail "missing claude /commit command wrapper"
[[ -f "$claude_push_pr_cmd" ]] || fail "missing claude /push-pr command wrapper"
[[ -f "$codex_commit_cmd" ]] || fail "missing codex /commit command wrapper"
[[ -f "$codex_push_pr_cmd" ]] || fail "missing codex /push-pr command wrapper"
[[ -d "$claude_skills_root" ]] || fail "missing .claude skill wrappers"
[[ -d "$codex_skills_root" ]] || fail "missing .codex skill mirrors"

assert_file_contains "$ROOT/.gitignore" '.codex/*'
assert_file_contains "$ROOT/.gitignore" '!.codex/commands/'
assert_file_contains "$ROOT/.gitignore" '!.codex/commands/*.md'
assert_file_contains "$ROOT/.gitignore" '!.codex/skills/'
assert_file_contains "$ROOT/.gitignore" '!.codex/skills/**'

assert_file_contains "$review_cmd" 'Invoke the review-stack skill'
assert_file_contains "$review_cmd" 'Use the Skill tool with skill name "review-stack"'
assert_file_contains "$review_cmd" 'git rev-parse HEAD'
assert_file_contains "$review_cmd" 'artifacts/pr-review-gate'

assert_file_contains "$review_alias" 'Alias for /review-stack'
assert_file_not_contains "$review_alias" 'full 6-skill review stack'

assert_file_contains "$review_skill_wrapper" 'name: review-stack'
assert_file_contains "$review_skill_wrapper" 'cat SKILLS/review-stack.md'
assert_file_contains "$claude_commit_cmd" 'Use the `/commit` skill from `SKILLS/commit.md`'
assert_file_contains "$claude_push_pr_cmd" 'Use the `/push-pr` skill from `SKILLS/push-pr.md`'
assert_file_contains "$codex_commit_cmd" '.codex/skills/commit/SKILL.md'
assert_file_contains "$codex_push_pr_cmd" '.codex/skills/push-pr/SKILL.md'

claude_skill_names=()
while IFS= read -r wrapper; do
  claude_skill_names+=("$(basename "$(dirname "$wrapper")")")
done < <(find "$claude_skills_root" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | sort)

[[ "${#claude_skill_names[@]}" -gt 0 ]] || fail "expected at least one .claude skill wrapper"

for skill_name in "${claude_skill_names[@]}"; do
  codex_skill_rel=".codex/skills/${skill_name}/SKILL.md"
  codex_command_rel=".codex/commands/${skill_name}.md"

  assert_tracked_file "$codex_skill_rel"
  assert_tracked_file "$codex_command_rel"
  assert_file_contains "$ROOT/$codex_skill_rel" "name: ${skill_name}"
  assert_file_contains "$ROOT/$codex_command_rel" ".codex/skills/${skill_name}/SKILL.md"
done

assert_tracked_file '.codex/commands/6.md'
assert_tracked_file '.codex/commands/external-review.md'
assert_tracked_file '.codex/commands/review.md'
assert_file_contains "$ROOT/.codex/commands/6.md" '.codex/skills/review-stack/SKILL.md'
assert_file_contains "$ROOT/.codex/commands/external-review.md" '.codex/skills/external-review-generic/SKILL.md'
assert_file_contains "$ROOT/.codex/commands/review.md" 'Invoke the code-review-expert skill'
assert_file_contains "$ROOT/.codex/commands/review.md" 'Use the Skill tool with skill name "code-review-expert"'

echo "test_review_command_wrappers.sh: ok"
