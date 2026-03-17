#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/obsidian-precommit-hook.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_hook() {
  local repo="$1"
  local command_text="$2"

  (
    cd "$repo"
    python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" \
      "$command_text" | bash "$HOOK"
  )
}

expect_block() {
  local label="$1"
  local pattern="$2"
  local repo="$3"
  local command_text="$4"

  local output=""
  set +e
  output="$(run_hook "$repo" "$command_text" 2>&1)"
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
  local repo="$2"
  local command_text="$3"

  local output=""
  set +e
  output="$(run_hook "$repo" "$command_text" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
}

write_project() {
  local path="$1"
  local debrief_line="$2"

  cat >"$path" <<EOF
---
status: in-progress
priority: P1
branch: main
pr:
started: "2026-03-17"
---

## Current State
Testing the Claude-side Obsidian hook.

## Key Files
- sample.txt

## Debriefs
$debrief_line

## Log
### 2026-03-17
- Updated project note.
EOF
}

write_debrief() {
  local path="$1"
  local project_name="$2"

  cat >"$path" <<EOF
---
project: "[[$project_name]]"
date: "2026-03-17"
---

## 0) What shipped
- Feature/behavior: Added a debrief.
- Value (what problem it solves): Leaves session context.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Missing debrief evidence.
- Time/token drain it caused: Follow-up cleanup.
- Workaround I used this session (exploit): Wrote the debrief directly.
- Next-agent default behavior (subordinate): Stage a debrief before commit.
- Permanent fix proposal (elevate): Add a commit guard.
- Smallest increment: Add a shell guard script.
- Validation (proof it got better): Guard blocks missing debrief commits.

## 2) Best follow-up
- Single best next step: Wire the guard into pre-commit.
- 1-3 upgrades worth considering:

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Stage a debrief before commit.
EOF
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

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

mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs"
write_project "$repo/obsidian/Projects/Test Project.md" "-"
git -C "$repo" add "obsidian/Projects/Test Project.md"

expect_block \
  "project-only staging blocks commit" \
  "No staged Obsidian debrief" \
  "$repo" \
  "git commit -m test"

write_debrief "$repo/obsidian/Debriefs/Test Project 2026-03-17 Hook.md" "Test Project"
git -C "$repo" add "obsidian/Debriefs/Test Project 2026-03-17 Hook.md"
write_project \
  "$repo/obsidian/Projects/Test Project.md" \
  "- [[Test Project 2026-03-17 Hook]]"
git -C "$repo" add "obsidian/Projects/Test Project.md"

expect_pass \
  "linked project and debrief allow commit" \
  "$repo" \
  "git commit -m test"

expect_pass \
  "non-commit commands are ignored" \
  "$repo" \
  "git status"

echo "test_obsidian_precommit_hook.sh: ok"
