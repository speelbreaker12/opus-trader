#!/usr/bin/env bash
# Tests for plans/doc_sync_check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/doc_sync"
GATE_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/doc_sync_check.sh"

pass=0
fail=0
total=0

run_test() {
  local name="$1"
  local fixture_dir="$2"
  local expected_exit="$3"
  local expected_pattern="${4:-}"
  total=$((total + 1))

  # Create a temporary git repo in a temp dir, copy fixture into it
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" RETURN 2>/dev/null || true

  cp -r "$fixture_dir"/* "$tmpdir/"
  # Rename IMPLEMENTATION_PLAN.md to specs/ location if not already there
  if [[ -f "$tmpdir/IMPLEMENTATION_PLAN.md" && ! -d "$tmpdir/specs" ]]; then
    mkdir -p "$tmpdir/specs"
    mv "$tmpdir/IMPLEMENTATION_PLAN.md" "$tmpdir/specs/IMPLEMENTATION_PLAN.md"
  fi
  # Move prd.json to plans/ if not already there
  if [[ -f "$tmpdir/prd.json" && ! -d "$tmpdir/plans" ]]; then
    mkdir -p "$tmpdir/plans"
    mv "$tmpdir/prd.json" "$tmpdir/plans/prd.json"
  fi

  (cd "$tmpdir" && git init -q && git add -A && git commit -q -m "fixture" --allow-empty)

  local output
  local actual_exit=0
  output="$(cd "$tmpdir" && bash "$GATE_SCRIPT" 2>&1)" || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $name — expected exit $expected_exit, got $actual_exit"
    echo "  output: $output"
    fail=$((fail + 1))
    rm -rf "$tmpdir"
    return
  fi

  if [[ -n "$expected_pattern" ]]; then
    if ! echo "$output" | grep -qF "$expected_pattern"; then
      echo "FAIL: $name — output missing expected pattern: $expected_pattern"
      echo "  output: $output"
      fail=$((fail + 1))
      rm -rf "$tmpdir"
      return
    fi
  fi

  echo "PASS: $name"
  pass=$((pass + 1))
  rm -rf "$tmpdir"
}

# ── Test 1: Valid fixture passes ──────────────────────────────────
run_test "valid fixture passes" "$FIXTURES_DIR/valid" 0

# ── Test 2: Orphan IMPL_PLAN story triggers failure ───────────────
run_test "orphan IMPL_PLAN story" "$FIXTURES_DIR/invalid_story_mismatch" 1 "S99.1"

# ── Test 3: Missing evidence file triggers failure ────────────────
run_test "missing evidence file" "$FIXTURES_DIR/invalid_evidence_missing" 1 "nonexistent.md"

# ── Test 4: Missing test file triggers failure ────────────────────
run_test "missing test file" "$FIXTURES_DIR/invalid_test_missing" 1 "missing_test.rs"

# ── Test 5: Path traversal evidence triggers failure ──────────────
run_test "path traversal evidence" "$FIXTURES_DIR/invalid_path_traversal" 1 "escapes repo root"

# ── Test 6: Prose and template evidence entries are silently filtered ─
# The valid fixture now includes prose ("This is a prose description")
# and template ("<template_placeholder>") evidence entries alongside a
# real path. The gate should pass — is_path_like filters non-paths.
# (Test 1 already covers this via the valid fixture.)

# ── Test 7: Kill switch DOC_SYNC_GATE=0 skips gate ───────────────
run_kill_switch_test() {
  total=$((total + 1))
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Use a fixture that would normally FAIL — if kill switch works, it exits 0
  cp -r "$FIXTURES_DIR/invalid_evidence_missing"/* "$tmpdir/"
  if [[ -f "$tmpdir/IMPLEMENTATION_PLAN.md" && ! -d "$tmpdir/specs" ]]; then
    mkdir -p "$tmpdir/specs"
    mv "$tmpdir/IMPLEMENTATION_PLAN.md" "$tmpdir/specs/IMPLEMENTATION_PLAN.md"
  fi
  if [[ -f "$tmpdir/prd.json" && ! -d "$tmpdir/plans" ]]; then
    mkdir -p "$tmpdir/plans"
    mv "$tmpdir/prd.json" "$tmpdir/plans/prd.json"
  fi
  (cd "$tmpdir" && git init -q && git add -A && git commit -q -m "fixture" --allow-empty)

  local output actual_exit=0
  output="$(cd "$tmpdir" && DOC_SYNC_GATE=0 bash "$GATE_SCRIPT" 2>&1)" || actual_exit=$?

  if [[ "$actual_exit" -ne 0 ]]; then
    echo "FAIL: kill switch — expected exit 0, got $actual_exit"
    echo "  output: $output"
    fail=$((fail + 1))
  elif ! echo "$output" | grep -qF "skipped"; then
    echo "FAIL: kill switch — output missing 'skipped'"
    echo "  output: $output"
    fail=$((fail + 1))
  else
    echo "PASS: kill switch skips gate"
    pass=$((pass + 1))
  fi
  rm -rf "$tmpdir"
}
run_kill_switch_test

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "doc_sync_check tests: $pass passed, $fail failed, $total total"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
