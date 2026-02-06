#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_SH="$ROOT/plans/verify.sh"
CHECKPOINT_LIB="$ROOT/plans/lib/verify_checkpoint.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$VERIFY_SH" ]] || fail "missing plans/verify.sh"
[[ -f "$CHECKPOINT_LIB" ]] || fail "missing plans/lib/verify_checkpoint.sh"

if ! rg -q '^[[:space:]]*decide_skip_gate\(\)' "$VERIFY_SH"; then
  fail "verify.sh must define decide_skip_gate entrypoint"
fi

if rg -n '\bis_cache_eligible\b' "$VERIFY_SH" >/dev/null; then
  fail "verify.sh must not call is_cache_eligible directly"
fi

if ! rg -q '^[[:space:]]*is_cache_eligible\(\)' "$CHECKPOINT_LIB"; then
  fail "verify_checkpoint.sh must define is_cache_eligible()"
fi

if ! rg -q '^[[:space:]]*checkpoint_decide_skip_gate\(\)' "$CHECKPOINT_LIB"; then
  fail "verify_checkpoint.sh must define checkpoint_decide_skip_gate()"
fi

# Structural guard (line-based, no function-body parsing):
# 1) exactly one definition
# 2) exactly one wrapper call
# 3) exactly one entrypoint call pattern
# 4) exactly three total references
def_refs="$(rg -n '^[[:space:]]*is_cache_eligible\(\)[[:space:]]*\{' "$CHECKPOINT_LIB" | wc -l | tr -d ' ')"
[[ "$def_refs" == "1" ]] || fail "expected exactly one is_cache_eligible() definition (found $def_refs)"

wrapper_refs="$(rg -n '^[[:space:]]*is_cache_eligible[[:space:]]*$' "$CHECKPOINT_LIB" | wc -l | tr -d ' ')"
[[ "$wrapper_refs" == "1" ]] || fail "expected exactly one wrapper call to is_cache_eligible (found $wrapper_refs)"

entry_refs="$(rg -n '^[[:space:]]*if ! is_cache_eligible; then$' "$CHECKPOINT_LIB" | wc -l | tr -d ' ')"
[[ "$entry_refs" == "1" ]] || fail "expected checkpoint_decide_skip_gate to call is_cache_eligible exactly once (found $entry_refs)"

total_refs="$(rg -n '\bis_cache_eligible\b' "$CHECKPOINT_LIB" | wc -l | tr -d ' ')"
[[ "$total_refs" == "3" ]] || fail "expected exactly three is_cache_eligible references total (found $total_refs)"

echo "PASS: skip entrypoint guard"
