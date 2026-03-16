#!/usr/bin/env bash
# PreToolUse hook: runs `cargo fmt` before verify.sh
# Reads tool input JSON from stdin, checks if command contains verify.sh

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE '(plans/)?verify\.sh'; then
  cd "$(git rev-parse --show-toplevel)"
  cargo fmt --all 2>&1 | head -20
  echo "cargo fmt completed before verify.sh"
fi

exit 0
