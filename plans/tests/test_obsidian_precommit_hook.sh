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

  local payload
  payload="$(python3 -c "import json,sys; print(json.dumps({'tool_input':{'command':sys.argv[1]}}))" "$command_text")"

  (
    cd "$repo"
    printf '%s\n' "$payload" | bash "$HOOK"
  )
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

[[ -x "$HOOK" ]] || fail "missing executable hook: $HOOK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
# Disable hooks in temp repo so parent repo's GIT_DIR/core.hooksPath doesn't leak
git -C "$repo" config core.hooksPath /dev/null

echo "seed" >"$repo/sample.txt"
git -C "$repo" add sample.txt
git -C "$repo" commit -qm "seed"

# The precommit hook is intentionally disabled (no-op, exit 0).
# The git pre-commit hook (.githooks/pre-commit) handles commit gating.
# This test verifies the hook remains a no-op.

expect_pass \
  "disabled hook allows git commit" \
  "$repo" \
  "git commit -m test"

expect_pass \
  "disabled hook allows non-commit commands" \
  "$repo" \
  "git status"

echo "test_obsidian_precommit_hook.sh: ok"
