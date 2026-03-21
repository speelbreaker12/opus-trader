#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/plans/project_scope_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_block() {
  local label="$1"
  local pattern="$2"
  local repo="$3"
  shift 3

  local output=""
  set +e
  output="$(cd "$repo" && bash "$GUARD" "$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    fail "$label expected non-zero exit"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected text '$pattern' in output: $output"
  fi
}

expect_pass() {
  local label="$1"
  local repo="$2"
  shift 2

  local output=""
  set +e
  output="$(cd "$repo" && bash "$GUARD" "$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
}

write_project_note() {
  local path="$1"
  local branch="$2"
  local base="$3"
  local pr_value="$4"
  local scope_block="$5"

  cat >"$path" <<EOF
---
status: in-progress
priority: P1
branch: $branch
base: $base
pr: $pr_value
started: "2026-03-17"
scope_paths:
$scope_block
---

## Current State
Testing project scope enforcement.

## Commits
- \`pending\` — 2026-03-17 — test fixture commit.

## Key Files
- src/in_scope.txt

## Debriefs
- [[Scope Test 2026-03-17]]

## Log
### 2026-03-17
- Added test fixture metadata.
EOF
}

write_debrief() {
  local path="$1"
  local project_name="$2"

  cat >"$path" <<EOF
---
project: "[[$project_name]]"
date: "2026-03-17"
type: debrief
---

## Commits
- \`pending\`

## Session Handoff

### Context
- Project: $project_name
- Branch: project/scope-test
- Worktree: repo fixture
- PR state:
- Lifecycle: testing

### State
- Task: Add a scope debrief fixture.
- Goal: Leave a trace for this scope-guard test fixture.
- Stop point: Fixture written and staged.
- Validation: Guard blocks unrelated files.
- Open decisions / blockers: none
- Resume command: bash plans/tests/test_project_scope_guard.sh

### Touch List
- Files touched: obsidian/Projects/*.md, obsidian/Debriefs/*.md
- Tests touched: plans/tests/test_project_scope_guard.sh
- Contract/docs touched: AGENTS.md Obsidian Project Tracking

### Shipped
- Feature/behavior: Added a scope debrief fixture.
- Value: Leaves a trace for this test fixture.

### Constraint (ONE)
- Constraint: Scope drift needed a guard.
- Symptoms: Branches could stage unrelated files and project notes.
- Workaround: Added a fixture debrief.
- Permanent fix: Add branch and scope guards.
- Smallest increment: Add a shared guard script.
- Proof: Guard blocks unrelated files.

### Best Follow-Up - Project
- Next step: Keep fixture scope small.
- Upgrades:

### Best Follow-Up - Workflow
- Issue: Project metadata can drift from actual branch scope.
- Smallest fix: Run the scope guard before commit and PR creation.

### Best Follow-Up - Non-Task
- Issue:
- Owner/path:

### Rules
- Rule 1: Keep staged files inside the declared scope.
- Rule 2:
- Rule 3:
EOF
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" checkout -qb "project/scope-test"

mkdir -p \
  "$repo/obsidian/Projects" \
  "$repo/obsidian/Debriefs" \
  "$repo/plans/lib" \
  "$repo/src" \
  "$repo/notes" \
  "$repo/other"
cp "$ROOT/plans/lib/obsidian_frontmatter.py" "$repo/plans/lib/obsidian_frontmatter.py"
echo "seed" >"$repo/src/in_scope.txt"
echo "seed" >"$repo/other/out_of_scope.txt"
write_project_note \
  "$repo/obsidian/Projects/Scope Test.md" \
  "project/scope-test" \
  "main" \
  "" \
  "  - src/**"$'\n'"  - obsidian/Projects/Scope Test.md"$'\n'"  - obsidian/Debriefs/Scope Test *.md"
write_debrief "$repo/obsidian/Debriefs/Scope Test 2026-03-17.md" "Scope Test"
git -C "$repo" add .
git -C "$repo" commit -qm "seed"

echo "changed" >"$repo/src/in_scope.txt"
git -C "$repo" add src/in_scope.txt
expect_pass "commit mode passes for in-scope file" "$repo" commit

git -C "$repo" reset -q HEAD src/in_scope.txt
echo "changed" >"$repo/other/out_of_scope.txt"
git -C "$repo" add other/out_of_scope.txt
expect_block "commit mode blocks out-of-scope file" "OUTSIDE PROJECT SCOPE" "$repo" commit
git -C "$repo" reset -q HEAD other/out_of_scope.txt

write_project_note \
  "$repo/obsidian/Projects/Other Project.md" \
  "project/other" \
  "main" \
  "" \
  "  - notes/**"
git -C "$repo" add "obsidian/Projects/Other Project.md"
expect_block "commit mode blocks foreign staged project note" "staged Obsidian project note belongs to a different branch-owned project" "$repo" commit
git -C "$repo" reset -q HEAD "obsidian/Projects/Other Project.md"
rm -f "$repo/obsidian/Projects/Other Project.md"

git -C "$repo" checkout -qb "project/no-scope"
write_project_note \
  "$repo/obsidian/Projects/No Scope.md" \
  "project/no-scope" \
  "main" \
  "" \
  ""
write_debrief "$repo/obsidian/Debriefs/No Scope 2026-03-17.md" "No Scope"
git -C "$repo" add "obsidian/Projects/No Scope.md" "obsidian/Debriefs/No Scope 2026-03-17.md"
git -C "$repo" commit -qm "add no-scope note"
echo "touch" >"$repo/notes/missing_scope.txt"
git -C "$repo" add notes/missing_scope.txt
expect_block "commit mode blocks missing scope_paths" "declares no scope_paths" "$repo" commit
git -C "$repo" reset -q HEAD notes/missing_scope.txt

git -C "$repo" checkout -q "project/scope-test"
git -C "$repo" branch -q main HEAD
echo "branch change" >"$repo/src/in_scope.txt"
git -C "$repo" add src/in_scope.txt
git -C "$repo" commit -qm "in scope commit"
expect_pass "push mode passes when full diff is in scope" "$repo" push

echo "branch change" >"$repo/other/out_of_scope.txt"
git -C "$repo" add other/out_of_scope.txt
git -C "$repo" commit -qm "out of scope commit"
expect_block "push mode blocks full branch diff outside scope" "OUTSIDE PROJECT SCOPE" "$repo" push

echo "test_project_scope_guard.sh: ok"
