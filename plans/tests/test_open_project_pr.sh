#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/open_project_pr.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_pass() {
  local label="$1"
  local repo="$2"
  local vault="$3"
  local path_dir="$4"
  shift 4

  local output=""
  set +e
  output="$(cd "$repo" && PATH="$path_dir:$PATH" OBSIDIAN_VAULT_PATH="$vault" bash "$SCRIPT" "$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
vault="$tmp_dir/vault"
mock_bin="$tmp_dir/bin"
mkdir -p "$vault/Projects" "$vault/Debriefs" "$repo/src" "$mock_bin"
mkdir -p "$repo/plans" "$repo/plans/lib"

git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" checkout -qb "project/scope-test"

cp "$ROOT/plans/project_scope_guard.sh" "$repo/plans/project_scope_guard.sh"
cp "$ROOT/plans/lib/obsidian_frontmatter.py" "$repo/plans/lib/obsidian_frontmatter.py"
cp "$ROOT/plans/lib/obsidian_vault.sh" "$repo/plans/lib/obsidian_vault.sh"
chmod +x "$repo/plans/project_scope_guard.sh"

cat >"$vault/Projects/Scope Test.md" <<'EOF'
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
Testing the PR wrapper.

## Commits
- `pending` — 2026-03-17 — create wrapper fixture.

## Key Files
- src/in_scope.txt

## Debriefs
- [[Scope Test 2026-03-17]]

## Log
### 2026-03-17
- Added wrapper fixture.
EOF

cat >"$vault/Debriefs/Scope Test 2026-03-17.md" <<'EOF'
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
- Task: Add a wrapper fixture.
- Goal: Test note PR writeback.
- Stop point: Fixture written before wrapper run.
- Validation: Project note PR field should update automatically.
- Open decisions / blockers: none
- Resume command: bash plans/tests/test_open_project_pr.sh

### Touch List
- Files touched: obsidian/Projects/Scope Test.md, obsidian/Debriefs/Scope Test 2026-03-17.md
- Tests touched: plans/tests/test_open_project_pr.sh
- Contract/docs touched: AGENTS.md Obsidian Project Tracking

### Shipped
- Feature/behavior: Added a wrapper fixture.
- Value: Tests note PR writeback.

### Constraint (ONE)
- Constraint: PR numbers were not written back.
- Symptoms: Manual bookkeeping after PR creation.
- Workaround: Fake gh output.
- Permanent fix: Write the PR number into the note.
- Smallest increment: Add `open_project_pr.sh`.
- Proof: Note frontmatter updates automatically.

### Best Follow-Up - Project
- Next step: Keep using the wrapper.
- Upgrades:

### Best Follow-Up - Workflow
- Issue: Project notes can drift from live PR state.
- Smallest fix: Keep PR creation behind the wrapper.

### Best Follow-Up - Non-Task
- Issue:
- Owner/path:

### Rules
- Rule 1: Use the PR wrapper for project-scoped branches.
- Rule 2:
- Rule 3:
EOF

echo "seed" >"$repo/src/in_scope.txt"
git -C "$repo" add .
git -C "$repo" commit -qm "seed"
git -C "$repo" branch -q main

cat >"$mock_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

if [[ "${1:-}" == "pr" && "${2:-}" == "create" ]]; then
  echo "https://github.com/example/repo/pull/321"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":321,"headRefName":"project/scope-test","baseRefName":"main","state":"OPEN"}
JSON
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$mock_bin/gh"

expect_pass "wrapper creates PR and updates note" "$repo" "$vault" "$mock_bin" --title "scope test"

pr_line="$(sed -n 's/^pr:[[:space:]]*//p' "$vault/Projects/Scope Test.md" | head -1)"
[[ "$pr_line" == "321" ]] || fail "expected project note pr to be 321, got '$pr_line'"

echo "test_open_project_pr.sh: ok"
