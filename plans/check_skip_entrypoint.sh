#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_FORK="$ROOT/plans/verify_fork.sh"
VERIFY_WRAPPER="$ROOT/plans/verify.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$VERIFY_WRAPPER" ]] || fail "missing plans/verify.sh"
[[ -f "$VERIFY_FORK" ]] || fail "missing plans/verify_fork.sh"

# Wrapper must exec verify_fork.sh
if ! rg -q 'exec.*verify_fork\.sh' "$VERIFY_WRAPPER"; then
  fail "verify.sh wrapper must exec verify_fork.sh"
fi

# Fork verify must source shared logging utils.
if ! rg -q 'source.*verify_utils\.sh' "$VERIFY_FORK"; then
  fail "verify_fork.sh must source plans/lib/verify_utils.sh"
fi

# Checkpoint/skip-entrypoint logic is intentionally removed in fork mode.
if rg -q '^[[:space:]]*decide_skip_gate\(\)' "$VERIFY_FORK"; then
  fail "verify_fork.sh must not define decide_skip_gate() in fork mode"
fi

if rg -n 'source.*verify_checkpoint\.sh|source.*change_detection\.sh' "$VERIFY_FORK" >/dev/null; then
  fail "verify_fork.sh must not source checkpoint/change-detection libs"
fi

if rg -n '\bcheckpoint_decide_skip_gate\b|\bis_cache_eligible\b|\bVERIFY_CHECKPOINT_' "$VERIFY_FORK" >/dev/null; then
  fail "verify_fork.sh must not reference checkpoint skip-entrypoint internals"
fi

echo "PASS: fork verify skip-entrypoint guard"
