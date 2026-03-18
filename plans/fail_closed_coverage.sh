#!/usr/bin/env bash
# fail_closed_coverage.sh — Convention-based fail-closed test coverage checker.
#
# Validates that every safety gate has:
#   1. >= 3 fail-closed tests (matching name patterns)
#   2. >= 1 TRIP test (reject/trip/block/fail)
#   3. >= 1 NON-TRIP test (allow/pass/accept/non_trip)
# Also validates GateStep count matches gate map key count.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GATE_MAP="$ROOT/plans/fail_closed_gate_map.json"
SOLDIER_CORE_DIR="$ROOT/crates/soldier_core"
DEFAULT_TEST_DIR="$SOLDIER_CORE_DIR/tests"
BUILD_ORDER_INTENT="$ROOT/crates/soldier_core/src/execution/build_order_intent.rs"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }
[[ -f "$GATE_MAP" ]] || { echo "ERROR: missing gate map: $GATE_MAP" >&2; exit 1; }

# ── GateStep count validation ────────────────────────────────────────────

# Count enum variants inside the GateStep block.
# Assumes trailing comma on each variant (enforced by rustfmt).
gate_step_count="$(sed -n '/pub enum GateStep/,/^}/p' "$BUILD_ORDER_INTENT" | grep -cE '^\s+\w+,' || echo 0)"
gate_map_count="$(jq 'keys | length' "$GATE_MAP")"

if [[ "$gate_step_count" -ne "$gate_map_count" ]]; then
  echo "ERROR: GateStep variant count ($gate_step_count) != gate map key count ($gate_map_count)" >&2
  echo "  Update plans/fail_closed_gate_map.json when adding/removing gates." >&2
  exit 1
fi

# ── Fail-closed name patterns ────────────────────────────────────────────

# Pattern for fail-closed test names
FAIL_CLOSED_PATTERN='(nan|NaN|missing|absent|stale|cache_miss|expired|expiry|fail_closed|fails_closed|failure|infinity|inf_|Inf|invalid|forbidden|not_healthy|degraded|no_l2|mismatch|non_finite|negative_)'

# TRIP patterns (guard triggers / rejects)
TRIP_PATTERN='(reject|trip|block|fail|forbidden|degraded|stale|mismatch|too_low|too_small|too_high|expired)'

# NON-TRIP patterns (guard allows)
NON_TRIP_PATTERN='(allow|pass|accept|non_trip|fresh|healthy|success|approved|within|happy|ok_|_ok$)'

# Assertion patterns (verify test body contains rejection logic)
ASSERTION_PATTERN='(GateDecision::Reject|GateOutcome::Reject|assert!\(!|assert_eq!.*Reject|RejectReasonCode::|ChokeResult::Rejected|Rejected|is_err|Err\()'

# ── Check each gate ─────────────────────────────────────────────────────

failures=0
warnings=0

check_gate() {
  local gate_name="$1"
  local gate_failed=0

  # Get test files for this gate
  local test_files
  test_files="$(jq -r --arg g "$gate_name" '.[$g][]' "$GATE_MAP" 2>/dev/null)"

  if [[ -z "$test_files" ]]; then
    echo "FAIL: gate '$gate_name' has no test files in gate map" >&2
    failures=$((failures + 1))
    return
  fi

  # Validate all test files exist
  local all_test_content=""
  while IFS= read -r tf; do
    if [[ "$tf" == /* || "$tf" == *".."* ]]; then
      echo "FAIL: gate '$gate_name' has unsafe test path entry: $tf" >&2
      failures=$((failures + 1))
      return
    fi

    local full_path
    if [[ "$tf" == */* ]]; then
      full_path="$SOLDIER_CORE_DIR/$tf"
    else
      full_path="$DEFAULT_TEST_DIR/$tf"
    fi
    if [[ ! -f "$full_path" ]]; then
      echo "FAIL: gate '$gate_name' test file not found: $full_path" >&2
      failures=$((failures + 1))
      return
    fi
    all_test_content="$all_test_content$(cat "$full_path")"$'\n'
  done <<< "$test_files"

  # Extract test function names
  local test_names
  test_names="$(echo "$all_test_content" | grep -oE 'fn (test_[a-zA-Z0-9_]+)' | sed 's/fn //' || true)"

  if [[ -z "$test_names" ]]; then
    echo "FAIL: gate '$gate_name' has no test functions" >&2
    gate_failed=1
  fi

  # Count fail-closed tests
  local fc_tests
  fc_tests="$(echo "$test_names" | grep -iE "$FAIL_CLOSED_PATTERN" || true)"
  local fc_count=0
  if [[ -n "$fc_tests" ]]; then
    fc_count="$(echo "$fc_tests" | wc -l | tr -d ' ')"
  fi

  if [[ "$fc_count" -lt 3 ]]; then
    echo "FAIL: gate '$gate_name' has $fc_count fail-closed tests (minimum 3)" >&2
    echo "  Tests found: $(echo "$fc_tests" | tr '\n' ', ')" >&2
    gate_failed=1
  fi

  # Check TRIP tests
  local trip_tests
  trip_tests="$(echo "$test_names" | grep -iE "$TRIP_PATTERN" || true)"
  local trip_count=0
  if [[ -n "$trip_tests" ]]; then
    trip_count="$(echo "$trip_tests" | wc -l | tr -d ' ')"
  fi

  if [[ "$trip_count" -lt 1 ]]; then
    echo "FAIL: gate '$gate_name' has no TRIP tests (reject/trip/block/fail)" >&2
    gate_failed=1
  fi

  # Check NON-TRIP tests
  local non_trip_tests
  non_trip_tests="$(echo "$test_names" | grep -iE "$NON_TRIP_PATTERN" || true)"
  local non_trip_count=0
  if [[ -n "$non_trip_tests" ]]; then
    non_trip_count="$(echo "$non_trip_tests" | wc -l | tr -d ' ')"
  fi

  if [[ "$non_trip_count" -lt 1 ]]; then
    echo "FAIL: gate '$gate_name' has no NON-TRIP tests (allow/pass/accept)" >&2
    gate_failed=1
  fi

  # Assertion-presence heuristic for fail-closed tests
  if [[ -n "$fc_tests" ]]; then
    while IFS= read -r test_fn; do
      [[ -n "$test_fn" ]] || continue
      # Extract function body (heuristic: from fn declaration to next fn or EOF).
      # Limitation: ^} matches first column-0 brace, which may truncate early in
      # files with nested mod blocks. Acceptable since this is advisory-only.
      local fn_body
      fn_body="$(echo "$all_test_content" | sed -n "/fn ${test_fn}/,/^fn test_\|^}/p" || true)"
      if [[ -n "$fn_body" ]] && ! echo "$fn_body" | grep -qE "$ASSERTION_PATTERN"; then
        echo "  WARN: gate '$gate_name' test '$test_fn' may lack rejection assertion" >&2
        warnings=$((warnings + 1))
      fi
    done <<< "$fc_tests"
  fi

  if [[ "$gate_failed" -ne 0 ]]; then
    failures=$((failures + 1))
  else
    echo "  OK: gate '$gate_name' — fc=$fc_count trip=$trip_count non_trip=$non_trip_count"
  fi
}

echo "fail_closed_coverage: checking gate test coverage"
echo "  GateStep variants: $gate_step_count, gate map keys: $gate_map_count"

# Iterate over all gates in the map
gate_names="$(jq -r 'keys[]' "$GATE_MAP")"
while IFS= read -r gate; do
  check_gate "$gate"
done <<< "$gate_names"

echo ""
echo "fail_closed_coverage summary: failures=$failures warnings=$warnings"

if [[ "$failures" -gt 0 ]]; then
  echo "FAIL: $failures gate(s) failed coverage check" >&2
  exit 1
fi

echo "fail_closed_coverage: PASS"
exit 0
