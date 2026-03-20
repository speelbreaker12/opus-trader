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

expect_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if printf '%s\n' "$haystack" | grep -Fq "$needle"; then
    fail "$label should NOT contain '$needle' but did. Output: $haystack"
  fi
}

write_project() {
  local path="$1"
  local status="$2"
  local branch="$3"
  local state="$4"
  local key_file="$5"
  local log_line="$6"

  cat >"$path" <<EOF
---
status: $status
priority: P1
branch: $branch
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
mkdir -p "$repo/obsidian/Projects" "$repo/.tmp" "$repo/plans/lib"
cp "$ROOT/plans/lib/obsidian_frontmatter.py" "$repo/plans/lib/"

# Initialize a git repo so the hook can detect the current branch
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
# Disable hooks in temp repo so parent repo's GIT_DIR/core.hooksPath doesn't leak
git -C "$repo" config core.hooksPath /dev/null
echo "seed" >"$repo/seed.txt"
git -C "$repo" add seed.txt
git -C "$repo" commit -qm "seed"

# --- Test 1: Branch-ownership match ---
# Create a branch that matches a project note
git -C "$repo" checkout -qb "feature/facade-refactor"

write_project \
  "$repo/obsidian/Projects/Execution Facade Refactor.md" \
  "in-progress" \
  "feature/facade-refactor" \
  "Telemetry event seams are landing in execution and fee gate refactors." \
  "crates/soldier_core/src/execution/gate.rs" \
  "Typed execution telemetry pilots are in progress."

write_project \
  "$repo/obsidian/Projects/Obsidian Work Tracking.md" \
  "done" \
  "workflow/obsidian-fixes" \
  "Obsidian hook routing and debrief guard work is complete." \
  ".claude/hooks/obsidian-context-hook.sh" \
  "Tracking hooks and debrief enforcement landed."

write_project \
  "$repo/obsidian/Projects/Unrelated Project.md" \
  "in-progress" \
  "feature/other-work" \
  "Some other work." \
  "src/other.rs" \
  "Other project started."

single_output="$(run_hook "$repo" "session-single" "Please continue the execution telemetry refactor.")"
expect_contains "branch match project" "$single_output" "Matched existing project: Execution Facade Refactor"
expect_contains "branch match branch name" "$single_output" "Branch: feature/facade-refactor"
expect_contains "active projects listed" "$single_output" "OBSIDIAN PROJECT CONTEXT"
expect_contains "routing decision present" "$single_output" "Routing decision:"
expect_contains "continue instruction" "$single_output" "Continue in this project scope."

# --- Test 2: Session dedup ---
# Second prompt in the same session should be silent
repeat_output="$(run_hook "$repo" "session-single" "Second prompt in the same session should not re-route.")"
if [[ -n "$repeat_output" ]]; then
  fail "repeat prompt should not emit router output, got: $repeat_output"
fi

# --- Test 3: No branch match ---
# Switch to a branch that no project owns
git -C "$repo" checkout -qb "feature/unknown-work"

no_match_output="$(run_hook "$repo" "session-no-match" "Please help me with something unrelated.")"
expect_contains "no match routing" "$no_match_output" "No branch-owned project matched."
expect_contains "no match skill ref" "$no_match_output" "Read SKILLS/obsidian-workflow.md to route this task."

# --- Test 4: Done projects are still listed but not matched ---
# Switch to the branch owned by the "done" project
git -C "$repo" checkout -qb "workflow/obsidian-fixes"

done_output="$(run_hook "$repo" "session-done" "Continue obsidian work.")"
# Branch ownership match should still work even for done projects.
expect_contains "done project matched" "$done_output" "Matched existing project: Obsidian Work Tracking"

# --- Test 5: Recent debriefs ---
# Create a debriefs directory with a file
mkdir -p "$repo/obsidian/Debriefs"
cat >"$repo/obsidian/Debriefs/Test Debrief 2026-03-19.md" <<'EOF'
---
project: "[[Execution Facade Refactor]]"
---
## Debrief content
EOF

git -C "$repo" checkout -q "feature/facade-refactor"

debrief_output="$(run_hook "$repo" "session-debrief" "Check debrief state.")"
expect_contains "debrief listed" "$debrief_output" "Recent debriefs"
expect_contains "debrief file" "$debrief_output" "Test Debrief 2026-03-19"

echo "test_obsidian_context_hook.sh: ok"
