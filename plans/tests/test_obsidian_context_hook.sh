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
  local aliases="${6:-}"
  local keywords="${7:-}"
  local worktree="${8:-}"

  {
    cat <<EOF
---
status: $status
priority: P1
branch: main
pr:
started: "2026-03-17"
EOF
    if [[ -n "$aliases" ]]; then
      echo "aliases:"
      while IFS= read -r alias; do
        [[ -n "$alias" ]] || continue
        printf -- "- %s\n" "$alias"
      done <<< "$aliases"
    fi
    if [[ -n "$keywords" ]]; then
      echo "keywords:"
      while IFS= read -r keyword; do
        [[ -n "$keyword" ]] || continue
        printf -- "- %s\n" "$keyword"
      done <<< "$keywords"
    fi
    if [[ -n "$worktree" ]]; then
      printf 'worktree: %s\n' "$worktree"
    fi
    cat <<EOF
---

## Current State
$state

## Key Files
- $key_file

## Debriefs
- None yet.

## Handoffs
- None active.

## Log
### 2026-03-17
- $log_line
EOF
  } >"$path"
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/obsidian/Projects" "$repo/.tmp"
(
  cd "$repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  printf '.worktrees/\n' > .gitignore
  printf 'root\n' > README.md
  git add .gitignore README.md
  git commit -q -m "init"
)

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

write_project \
  "$repo/obsidian/Projects/Session Matching.md" \
  "in-progress" \
  "General routing backlog." \
  ".claude/hooks/obsidian-context-hook.sh" \
  "Alias scoring needs verification." \
  "vault router"

write_project \
  "$repo/obsidian/Projects/Tracker Heuristics.md" \
  "in-progress" \
  "General scoring maintenance." \
  ".claude/hooks/obsidian-context-hook.sh" \
  "Keyword scoring needs verification." \
  "" \
  "strategy garden"

single_output="$(run_hook "$repo" "session-single" "Please continue the execution telemetry refactor for the fee gate.")"
expect_contains "single match skill hint" "$single_output" "Companion skill: /obsidian-workflow"
expect_contains "single match path" "$single_output" "Matched Obsidian project: obsidian/Projects/Execution Facade Refactor.md"
expect_contains "single match worktree" "$single_output" "Project worktree: .worktrees/execution-facade-refactor"
expect_contains "single match branch" "$single_output" "Project branch: project/execution-facade-refactor"
expect_contains "single match consult skill" "$single_output" "Consult /obsidian-workflow for the project-note and debrief checklist."
expect_contains "single match instruction" "$single_output" "Confirm you found and read obsidian/Projects/Execution Facade Refactor.md before proceeding."
expect_contains "single match worktree instruction" "$single_output" "will use the project worktree"
expect_contains "single match content" "$single_output" "Telemetry event seams are landing in execution and fee gate refactors."
[[ -d "$repo/.worktrees/execution-facade-refactor" ]] || fail "matched project worktree was not created"
grep -Fq 'worktree: .worktrees/execution-facade-refactor' "$repo/obsidian/Projects/Execution Facade Refactor.md" \
  || fail "matched project note missing worktree field"
grep -Fq 'branch: project/execution-facade-refactor' "$repo/obsidian/Projects/Execution Facade Refactor.md" \
  || fail "matched project note missing project branch"

repeat_output="$(run_hook "$repo" "session-single" "Second prompt in the same session should not re-route.")"
if [[ -n "$repeat_output" ]]; then
  fail "repeat prompt should not emit router output, got: $repeat_output"
fi

alias_output="$(run_hook "$repo" "session-alias" "Need help with the vault router follow-up.")"
expect_contains "alias match path" "$alias_output" "Matched Obsidian project: obsidian/Projects/Session Matching.md"

keyword_output="$(run_hook "$repo" "session-keyword" "Need help with the strategy garden follow-up.")"
expect_contains "keyword match path" "$keyword_output" "Matched Obsidian project: obsidian/Projects/Tracker Heuristics.md"

ambiguous_output="$(run_hook "$repo" "session-ambiguous" "I want to improve first prompt obsidian project hook routing.")"
expect_contains "ambiguous prompt" "$ambiguous_output" "Ambiguous Obsidian project match for first prompt."
expect_contains "ambiguous consult skill" "$ambiguous_output" "Consult /obsidian-workflow for the project-note and debrief checklist."
expect_contains "ambiguous alpha" "$ambiguous_output" "obsidian/Projects/Hook Routing Alpha.md"
expect_contains "ambiguous beta" "$ambiguous_output" "obsidian/Projects/Hook Routing Beta.md"
expect_contains "ambiguous instruction" "$ambiguous_output" "Tell the user you found multiple likely Obsidian project notes and ask them to choose one before proceeding."

ambiguous_follow_up="$(run_hook "$repo" "session-ambiguous" "Use Hook Routing Alpha for this session.")"
expect_contains "ambiguous follow-up resolves" "$ambiguous_follow_up" "Matched Obsidian project: obsidian/Projects/Hook Routing Alpha.md"

no_match_output="$(run_hook "$repo" "session-no-match" "Please help me tune a freqtrade paper bot strategy for BTC.")"
expect_contains "no match banner" "$no_match_output" "No related Obsidian project note matched the first prompt. Created a new project note and dedicated worktree."
expect_contains "no match consult skill" "$no_match_output" "Consult /obsidian-workflow for the project-note and debrief checklist."
expect_contains "no match created note" "$no_match_output" "Created Obsidian project:"
expect_contains "no match created worktree" "$no_match_output" "Project worktree: .worktrees/"
expect_contains "no match instruction" "$no_match_output" "Tell the user you created"
created_project_rel="$(printf '%s\n' "$no_match_output" | sed -n 's/^Created Obsidian project: //p' | head -n 1)"
[[ -n "$created_project_rel" ]] || fail "no-match output missing created project path"
[[ -f "$repo/$created_project_rel" ]] || fail "auto-created project note missing at $created_project_rel"
created_worktree_rel="$(printf '%s\n' "$no_match_output" | sed -n 's/^Project worktree: //p' | head -n 1)"
[[ -n "$created_worktree_rel" ]] || fail "no-match output missing created worktree path"
[[ -d "$repo/$created_worktree_rel" ]] || fail "auto-created worktree missing at $created_worktree_rel"

no_match_follow_up="$(run_hook "$repo" "session-no-match" "This belongs in Execution Facade Refactor.")"
if [[ -n "$no_match_follow_up" ]]; then
  fail "no-match session should not re-route after auto-creation, got: $no_match_follow_up"
fi

empty_repo="$tmp_dir/empty-repo"
mkdir -p "$empty_repo/obsidian/Projects" "$empty_repo/.tmp"
(
  cd "$empty_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  printf '.worktrees/\n' > .gitignore
  printf 'root\n' > README.md
  git add .gitignore README.md
  git commit -q -m "init"
)
empty_output="$(run_hook "$empty_repo" "session-empty" "Set up a fresh execution telemetry workstream.")"
expect_contains "empty repo create note" "$empty_output" "Created Obsidian project:"
expect_contains "empty repo create worktree" "$empty_output" "Project worktree: .worktrees/"

echo "test_obsidian_context_hook.sh: ok"
