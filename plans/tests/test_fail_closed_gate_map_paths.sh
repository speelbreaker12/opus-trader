#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAP="$ROOT/plans/fail_closed_gate_map.json"
COVERAGE="$ROOT/plans/fail_closed_coverage.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$MAP" ]] || fail "missing fail-closed gate map: $MAP"
[[ -f "$COVERAGE" ]] || fail "missing fail-closed coverage script: $COVERAGE"

recorded_path="$(
  jq -r '.recorded_before_dispatch[0] // ""' "$MAP"
)"

[[ "$recorded_path" == "src/execution/recorded_before_dispatch_gate_tests.rs" ]] \
  || fail "recorded_before_dispatch path must target src execution unit tests; got: $recorded_path"

grep -Fq 'DEFAULT_TEST_DIR="$SOLDIER_CORE_DIR/tests"' "$COVERAGE" \
  || fail "coverage script missing default tests dir guard"
grep -Fq 'if [[ "$tf" == */* ]]; then' "$COVERAGE" \
  || fail "coverage script missing subpath resolution branch"
grep -Fq 'full_path="$SOLDIER_CORE_DIR/$tf"' "$COVERAGE" \
  || fail "coverage script missing soldier_core-relative path resolution"
grep -Fq 'full_path="$DEFAULT_TEST_DIR/$tf"' "$COVERAGE" \
  || fail "coverage script missing tests-dir filename fallback"

echo "PASS: fail-closed gate map path handling"
