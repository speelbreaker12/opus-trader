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
---

## 0) What shipped
- Feature/behavior: Added hook scope fixture.
- Value (what problem it solves): Tests raw `gh pr create` scope blocking.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Raw PR creation could ignore project scope.
- Time/token drain it caused: Review churn.
- Workaround I used this session (exploit): Added a fixture debrief.
- Next-agent default behavior (subordinate): Keep PR diffs inside scope.
- Permanent fix proposal (elevate): Run the project scope guard before PR creation.
- Smallest increment: Reuse the shared guard from the hook.
- Validation (proof it got better): Raw PR create blocks on out-of-scope files.

## 2) Best follow-up
- Single best next step: Keep the branch diff scoped.
- 1-3 upgrades worth considering:

## 3) Enforceable rules
- Do not open a PR when the branch diff escapes the project note scope.

## Commits
- `pending`
EOF
}

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/obsidian/Projects" "$repo/obsidian/Debriefs" "$repo/src" "$repo/other" "$repo/artifacts/pr-review-gate"
mkdir -p "$repo/plans"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" checkout -qb "project/scope-test"

cp "$ROOT/plans/project_scope_guard.sh" "$repo/plans/project_scope_guard.sh"
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
