#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/obsidian-context-hook.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
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

expect_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if ! printf '%s\n' "$haystack" | grep -Fq "$needle"; then
    fail "$label missing expected text '$needle' in output: $haystack"
  fi
}

write_project() {
  local path="$1"
  local status="$2"
  local state="$3"
  local key_file="$4"
  local log_line="$5"

  cat >"$path" <<EOF
---
status: $status
priority: P1
branch: main
pr:
started: "2026-03-17"
---

## Current State
$state

## Key Files
- $key_file

## Debriefs
- None yet.

## Log
### 2026-03-17
- $log_line
EOF
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/obsidian/Projects" "$repo/.tmp"

write_project \
  "$repo/obsidian/Projects/Execution Facade Refactor.md" \
  "in-progress" \
  "Telemetry event seams are landing in execution and fee gate refactors." \
  "crates/soldier_core/src/execution/gate.rs" \
  "Typed execution telemetry pilots are in progress."

write_project \
  "$repo/obsidian/Projects/Obsidian Work Tracking.md" \
  "done" \
  "Obsidian hook routing and debrief guard work is complete." \
  ".claude/hooks/obsidian-context-hook.sh" \
  "Tracking hooks and debrief enforcement landed."

write_project \
  "$repo/obsidian/Projects/Hook Routing Alpha.md" \
  "in-progress" \
  "First prompt hook routing for obsidian project matching is under review." \
  ".claude/hooks/obsidian-context-hook.sh" \
  "Project hook routing notes are pending."

write_project \
  "$repo/obsidian/Projects/Hook Routing Beta.md" \
  "in-progress" \
  "First prompt hook routing for obsidian project matching is under review." \
  ".claude/hooks/obsidian-context-hook.sh" \
  "Project hook routing notes are pending."

single_output="$(run_hook "$repo" "session-single" "Please continue the execution telemetry refactor for the fee gate.")"
expect_contains "single match path" "$single_output" "Matched Obsidian project: obsidian/Projects/Execution Facade Refactor.md"
expect_contains "single match instruction" "$single_output" "Confirm you found and read obsidian/Projects/Execution Facade Refactor.md before proceeding."
expect_contains "single match content" "$single_output" "Telemetry event seams are landing in execution and fee gate refactors."

repeat_output="$(run_hook "$repo" "session-single" "Second prompt in the same session should not re-route.")"
if [[ -n "$repeat_output" ]]; then
  fail "repeat prompt should not emit router output, got: $repeat_output"
fi

ambiguous_output="$(run_hook "$repo" "session-ambiguous" "I want to improve first prompt obsidian project hook routing.")"
expect_contains "ambiguous prompt" "$ambiguous_output" "Ambiguous Obsidian project match for first prompt."
expect_contains "ambiguous alpha" "$ambiguous_output" "obsidian/Projects/Hook Routing Alpha.md"
expect_contains "ambiguous beta" "$ambiguous_output" "obsidian/Projects/Hook Routing Beta.md"
expect_contains "ambiguous instruction" "$ambiguous_output" "Tell the user you found multiple likely Obsidian project notes and ask them to choose one before proceeding."

ambiguous_follow_up="$(run_hook "$repo" "session-ambiguous" "Use Hook Routing Alpha for this session.")"
expect_contains "ambiguous follow-up resolves" "$ambiguous_follow_up" "Matched Obsidian project: obsidian/Projects/Hook Routing Alpha.md"

no_match_output="$(run_hook "$repo" "session-no-match" "Please help me tune a freqtrade paper bot strategy for BTC.")"
expect_contains "no match banner" "$no_match_output" "No related Obsidian project note matched the first prompt."
expect_contains "no match instruction" "$no_match_output" "Tell the user no related project note was found in obsidian/Projects and propose a new one."
expect_contains "no match suggestion" "$no_match_output" "Suggested new project note:"

no_match_follow_up="$(run_hook "$repo" "session-no-match" "This belongs in Execution Facade Refactor.")"
expect_contains "no match follow-up resolves" "$no_match_follow_up" "Matched Obsidian project: obsidian/Projects/Execution Facade Refactor.md"

echo "test_obsidian_context_hook.sh: ok"
