#!/usr/bin/env bash
# Tests for --proof-graph guard logic in plans/review_logged.sh
#
# Tests:
#   1. --proof-graph + --prompt generic → exit 2 with "requires --prompt enriched"
#   2. --proof-graph + --tool codex (no --files) → exit 2 with "requires --tool opus|kimi"
#   3. --proof-graph + --prompt enriched + --tool opus → guard passes (no guard error)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/review_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -x "$SCRIPT" ]] || fail "review_logged.sh not found or not executable: $SCRIPT"

# ── Test 1: --proof-graph + --prompt generic → exit 2 ─────────────

test_proof_graph_generic_rejected() {
  set +e
  output="$(bash "$SCRIPT" FAKE-001 --tool opus --prompt generic --uncommitted --proof-graph 2>&1)"
  rc=$?
  set -e

  [[ $rc -eq 2 ]] || fail "proof-graph+generic should exit 2, got $rc"
  echo "$output" | grep -q "requires --prompt enriched" \
    || fail "proof-graph+generic: expected 'requires --prompt enriched'. Output: $output"
  pass "--proof-graph + --prompt generic → exit 2"
}

# ── Test 2: --proof-graph + --tool codex (no --files) → exit 2 ────

test_proof_graph_codex_diff_rejected() {
  set +e
  output="$(bash "$SCRIPT" FAKE-001 --tool codex --prompt enriched --uncommitted --proof-graph 2>&1)"
  rc=$?
  set -e

  [[ $rc -eq 2 ]] || fail "proof-graph+codex should exit 2, got $rc"
  echo "$output" | grep -q "requires --tool opus|kimi or --tool codex --files" \
    || fail "proof-graph+codex: expected tool guard message. Output: $output"
  pass "--proof-graph + --tool codex (no --files) → exit 2"
}

# ── Test 3: Valid combo → guard does NOT fire ─────────────────────
# The script may still fail later (missing tool, missing story), but
# the exit should NOT be caused by the --proof-graph guards.

test_proof_graph_valid_combo_passes_guard() {
  set +e
  output="$(bash "$SCRIPT" FAKE-001 --tool opus --prompt enriched --uncommitted --proof-graph 2>&1)"
  rc=$?
  set -e

  # The guard messages should NOT appear
  if echo "$output" | grep -q "requires --prompt enriched"; then
    fail "valid combo: guard incorrectly rejected with 'requires --prompt enriched'"
  fi
  if echo "$output" | grep -q "requires --tool opus|kimi"; then
    fail "valid combo: guard incorrectly rejected with 'requires --tool opus|kimi'"
  fi

  # Guard exit code is 2; any other exit (0 or other) means guard did not fire
  [[ $rc -ne 2 ]] \
    || fail "valid combo: exit code 2 means the guard fired when it should not have"

  # Script may fail for other reasons (missing claude CLI, missing story)
  # but it should NOT have failed at the --proof-graph guard
  pass "--proof-graph + --prompt enriched + --tool opus → guard passes (exit $rc)"
}

# ── Run all tests ─────────────────────────────────────────────────

echo "=== review_logged.sh --proof-graph guard tests ==="
test_proof_graph_generic_rejected
test_proof_graph_codex_diff_rejected
test_proof_graph_valid_combo_passes_guard
echo "=== all tests passed ==="
