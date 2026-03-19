#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/plans/obsidian_commit_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_block() {
  local label="$1"
  local pattern="$2"
  local repo="$3"

  local output=""
  set +e
  output="$(cd "$repo" && bash "$GUARD" 2>&1)"
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

  local output=""
  set +e
  output="$(cd "$repo" && bash "$GUARD" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
}

write_project() {
  local path="$1"
  local debrief_line="$2"
  local log_line="${3:-- Updated project note.}"

  cat >"$path" <<EOF
---
status: in-progress
priority: P1
branch: main
pr:
started: "2026-03-17"
---

## Current State
Testing the Obsidian commit guard.

## Key Files
- sample.txt

## Debriefs
$debrief_line

## Log
### 2026-03-17
$log_line
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
- Branch: main
- Worktree: repo fixture
- PR state:
- Lifecycle: testing

### State
- Task: Add a debrief fixture.
- Goal: Leave session context for the commit guard tests.
- Stop point: Fixture written and staged.
- Validation: Guard should accept valid debrief/project linkage.
- Open decisions / blockers: none
- Resume command: bash plans/tests/test_obsidian_commit_guard.sh

### Touch List
- Files touched: obsidian/Projects/Test Project.md, obsidian/Debriefs/*.md
- Tests touched: plans/tests/test_obsidian_commit_guard.sh
- Contract/docs touched: AGENTS.md Obsidian Project Tracking

### Shipped
- Feature/behavior: Added a debrief fixture.
- Value: Leaves session context.

### Constraint (ONE)
- Constraint: Missing debrief evidence.
- Symptoms: Follow-up cleanup and missing session history.
- Workaround: Wrote the debrief directly.
- Permanent fix: Add a commit guard.
- Smallest increment: Add a shell guard script.
- Proof: Guard blocks missing debrief commits.

### Best Follow-Up - Project
- Next step: Wire the guard into pre-commit.
- Upgrades:

### Best Follow-Up - Workflow
- Issue: Missing debriefs can slip through without a shared guard.
- Smallest fix: Reuse the guard in every commit entrypoint.

### Best Follow-Up - Non-Task
- Issue:
- Owner/path:

### Rules
- Rule 1: Stage a debrief before commit.
- Rule 2:
- Rule 3:
EOF
}

write_linked_project() {
  local path="$1"
  local debrief_name="$2"
  write_project "$path" "- [[${debrief_name}]]"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"

echo "seed" >"$repo/sample.txt"
git -C "$repo" add sample.txt
git -C "$repo" commit -qm "seed"

echo "changed" >"$repo/sample.txt"
git -C "$repo" add sample.txt
expect_block "missing project note blocks" "No staged Obsidian project note" "$repo"

mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs"
write_project "$repo/obsidian/Projects/Test Project.md" "-"
git -C "$repo" add "obsidian/Projects/Test Project.md"
expect_block "missing debrief blocks" "No staged Obsidian debrief" "$repo"

write_debrief "$repo/obsidian/Debriefs/Test Project 2026-03-17 Hook.md" "Test Project"
git -C "$repo" add "obsidian/Debriefs/Test Project 2026-03-17 Hook.md"
expect_block "missing project link blocks" "must link at least one staged debrief" "$repo"

write_project \
  "$repo/obsidian/Projects/Test Project.md" \
  "-" \
  "- Mentioned Test Project 2026-03-17 Hook only in the log."
git -C "$repo" add "obsidian/Projects/Test Project.md"
expect_block "log mention does not satisfy debrief link" "must link at least one staged debrief" "$repo"

write_project \
  "$repo/obsidian/Projects/Test Project.md" \
  "- [[Test Project 2026-03-17 Hook]]"
git -C "$repo" add "obsidian/Projects/Test Project.md"
expect_pass "project note linked to staged debrief passes" "$repo"

git -C "$repo" reset --hard -q HEAD
mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs"
write_linked_project \
  "$repo/obsidian/Projects/Test Project.md" \
  "Test Project 2026-03-17 Hook"
write_debrief "$repo/obsidian/Debriefs/Test Project 2026-03-17 Hook.md" "Test Project"
write_debrief "$repo/obsidian/Debriefs/Other Project 2026-03-17 Hook.md" "Other Project"
git -C "$repo" add \
  "obsidian/Projects/Test Project.md" \
  "obsidian/Debriefs/Test Project 2026-03-17 Hook.md" \
  "obsidian/Debriefs/Other Project 2026-03-17 Hook.md"
expect_block "unrelated debrief blocks" "belongs to a different project" "$repo"

git -C "$repo" reset --hard -q HEAD
mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs"
write_linked_project \
  "$repo/obsidian/Projects/Test Project.md" \
  "Test Project 2026-03-17 Hook"
write_linked_project \
  "$repo/obsidian/Projects/Other Project.md" \
  "Other Project 2026-03-17 Hook"
write_debrief "$repo/obsidian/Debriefs/Test Project 2026-03-17 Hook.md" "Test Project"
git -C "$repo" add \
  "obsidian/Projects/Test Project.md" \
  "obsidian/Projects/Other Project.md" \
  "obsidian/Debriefs/Test Project 2026-03-17 Hook.md"
expect_block "multiple project notes block" "Stage Obsidian files for exactly one project note per commit." "$repo"

echo "test_obsidian_commit_guard.sh: ok"
