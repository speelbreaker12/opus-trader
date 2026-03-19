#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/open_project_pr.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_pass() {
  local label="$1"
  local repo="$2"
  local path_dir="$3"
  shift 3

  local output=""
  set +e
  output="$(cd "$repo" && PATH="$path_dir:$PATH" bash "$SCRIPT" "$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "$label expected exit 0, got $rc with output: $output"
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mock_bin="$tmp_dir/bin"
mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs" "$repo/src" "$mock_bin"
mkdir -p "$repo/plans"

git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" checkout -qb "project/scope-test"

cp "$ROOT/plans/project_scope_guard.sh" "$repo/plans/project_scope_guard.sh"
chmod +x "$repo/plans/project_scope_guard.sh"

cat >"$repo/obsidian/Projects/Scope Test.md" <<'EOF'
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

cat >"$repo/obsidian/Debriefs/Scope Test 2026-03-17.md" <<'EOF'
---
project: "[[Scope Test]]"
date: "2026-03-17"
---

## 0) What shipped
- Feature/behavior: Added a wrapper fixture.
- Value (what problem it solves): Tests note PR writeback.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): PR numbers were not written back.
- Time/token drain it caused: Manual bookkeeping.
- Workaround I used this session (exploit): Fake gh output.
- Next-agent default behavior (subordinate): Use the wrapper.
- Permanent fix proposal (elevate): Write the PR number into the note.
- Smallest increment: Add `open_project_pr.sh`.
- Validation (proof it got better): Note frontmatter updates automatically.

## 2) Best follow-up
- Single best next step: Keep using the wrapper.
- 1-3 upgrades worth considering:

## 3) Enforceable rules
- Use the PR wrapper for project-scoped branches.

## Commits
- `pending`
EOF

echo "seed" >"$repo/src/in_scope.txt"
git -C "$repo" add .
git -C "$repo" commit -qm "seed"
git -C "$repo" branch -q main

cat >"$mock_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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

expect_pass "wrapper creates PR and updates note" "$repo" "$mock_bin" --title "scope test"

pr_line="$(sed -n 's/^pr:[[:space:]]*//p' "$repo/obsidian/Projects/Scope Test.md" | head -1)"
[[ "$pr_line" == "321" ]] || fail "expected project note pr to be 321, got '$pr_line'"

echo "test_open_project_pr.sh: ok"
