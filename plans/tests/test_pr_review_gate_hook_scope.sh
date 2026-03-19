#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/pr-review-gate-hook.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_block() {
  local label="$1"
  local pattern="$2"
  local repo="$3"
  local command_text="$4"

  local output=""
  set +e
  output="$(
    cd "$repo" &&
    python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" \
      "$command_text" | bash "$HOOK" 2>&1
  )"
  local rc=$?
  set -e

  if [[ $rc -ne 2 ]]; then
    fail "$label expected exit 2, got $rc with output: $output"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected text '$pattern' in output: $output"
  fi
}

write_project_note() {
  local path="$1"

  cat >"$path" <<'EOF'
---
status: in-progress
priority: P1
branch: project/scope-test
base: main
pr:
started: "2026-03-17"
scope_paths:
  - src/**
  - obsidian/Projects/Scope Test.md
  - obsidian/Debriefs/Scope Test *.md
---

## Current State
Testing PR create scope enforcement.

## Commits
- `pending` — 2026-03-17 — add hook fixture.

## Key Files
- src/in_scope.txt

## Debriefs
- [[Scope Test 2026-03-17]]

## Log
### 2026-03-17
- Added hook fixture metadata.
EOF
}

write_debrief() {
  local path="$1"

  cat >"$path" <<'EOF'
---
project: "[[Scope Test]]"
date: "2026-03-17"
type: debrief
---

## Commits
- `pending`

## Session Handoff

### Context
- Project: Scope Test
- Branch: project/scope-test
- Worktree: repo fixture
- PR state:
- Lifecycle: testing

### State
- Task: Add hook scope fixture.
- Goal: Test raw `gh pr create` scope blocking.
- Stop point: Fixture written before the hook run.
- Validation: Raw PR create should block on out-of-scope files.
- Open decisions / blockers: none
- Resume command: bash plans/tests/test_pr_review_gate_hook_scope.sh

### Touch List
- Files touched: obsidian/Projects/Scope Test.md, obsidian/Debriefs/Scope Test 2026-03-17.md
- Tests touched: plans/tests/test_pr_review_gate_hook_scope.sh
- Contract/docs touched: AGENTS.md Obsidian Project Tracking

### Shipped
- Feature/behavior: Added hook scope fixture.
- Value: Tests raw `gh pr create` scope blocking.

### Constraint (ONE)
- Constraint: Raw PR creation could ignore project scope.
- Symptoms: Review churn from out-of-scope branch diffs.
- Workaround: Added a fixture debrief.
- Permanent fix: Run the project scope guard before PR creation.
- Smallest increment: Reuse the shared guard from the hook.
- Proof: Raw PR create blocks on out-of-scope files.

### Best Follow-Up - Project
- Next step: Keep the branch diff scoped.
- Upgrades:

### Best Follow-Up - Workflow
- Issue: Raw PR creation can bypass project-scope expectations.
- Smallest fix: Reuse the scope guard from the hook.

### Best Follow-Up - Non-Task
- Issue:
- Owner/path:

### Rules
- Rule 1: Do not open a PR when the branch diff escapes the project note scope.
- Rule 2:
- Rule 3:
EOF
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs" "$repo/src" "$repo/other" "$repo/artifacts/pr-review-gate"
mkdir -p "$repo/plans" "$repo/plans/lib"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" checkout -qb "project/scope-test"

cp "$ROOT/plans/project_scope_guard.sh" "$repo/plans/project_scope_guard.sh"
cp "$ROOT/plans/lib/obsidian_frontmatter.py" "$repo/plans/lib/obsidian_frontmatter.py"
chmod +x "$repo/plans/project_scope_guard.sh"

echo "seed" >"$repo/src/in_scope.txt"
write_project_note "$repo/obsidian/Projects/Scope Test.md"
write_debrief "$repo/obsidian/Debriefs/Scope Test 2026-03-17.md"
git -C "$repo" add .
git -C "$repo" commit -qm "seed"
git -C "$repo" branch -q main HEAD

echo "outside" >"$repo/other/out_of_scope.txt"
git -C "$repo" add other/out_of_scope.txt
git -C "$repo" commit -qm "out of scope"

cat >"$repo/artifacts/pr-review-gate/project_scope-test.json" <<EOF
{"verdict":"PASS","head":"$(git -C "$repo" rev-parse --short HEAD)"}
EOF

expect_block \
  "raw gh pr create blocks when project scope guard fails" \
  "OUTSIDE PROJECT SCOPE" \
  "$repo" \
  "gh pr create --title ready"

echo "test_pr_review_gate_hook_scope.sh: ok"
