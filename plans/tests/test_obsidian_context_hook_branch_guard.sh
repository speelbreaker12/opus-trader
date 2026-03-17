#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/obsidian-context-hook.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if ! printf '%s\n' "$haystack" | grep -Fq "$needle"; then
    fail "$label missing expected text '$needle' in output: $haystack"
  fi
}

run_hook() {
  local repo="$1"
  local session_id="$2"
  local message="$3"

  (
    cd "$repo"
    python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "message": sys.argv[2]}))' \
      "$session_id" "$message" | \
      OBSIDIAN_CONTEXT_STATE_DIR="$repo/.tmp/obsidian-context-state" bash "$HOOK"
  )
}

write_project() {
  local path="$1"
  local branch="$2"
  local state="$3"
  local key_file="$4"

  cat >"$path" <<EOF
---
status: in-progress
priority: P1
branch: $branch
base: main
pr:
started: "2026-03-17"
scope_paths:
  - $key_file
  - ${path#*/Projects/}
---

## Current State
$state

## Key Files
- $key_file

## Debriefs
- None yet.

## Log
### 2026-03-17
- Added branch-routing fixture.
EOF
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/obsidian/Projects" "$repo/.tmp" "$repo/src"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" checkout -qb "project/current-note"

echo "seed" >"$repo/src/current.txt"
git -C "$repo" add src/current.txt
git -C "$repo" commit -qm "seed"

write_project \
  "$repo/obsidian/Projects/Current Note.md" \
  "project/current-note" \
  "Current branch fixture." \
  "src/current.txt"
write_project \
  "$repo/obsidian/Projects/Other Note.md" \
  "project/other-note" \
  "Scope guard follow-up lives on the other branch." \
  "src/other.txt"

output="$(run_hook "$repo" "branch-mismatch" "Please continue the scope guard follow-up on the other note.")"
expect_contains "matched project present" "$output" "Matched Obsidian project: obsidian/Projects/Other Note.md"
expect_contains "branch mismatch warning" "$output" "BRANCH/WORKTREE MISMATCH"
expect_contains "current branch named" "$output" "Current branch: project/current-note"
expect_contains "matched branch named" "$output" "Matched project branch: project/other-note"
expect_contains "switch instruction" "$output" "Switch or create the matched project's worktree before editing."

echo "test_obsidian_context_hook_branch_guard.sh: ok"
