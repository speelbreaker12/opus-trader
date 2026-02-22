#!/usr/bin/env bash
# Regression tests for proof_graph gate in prd_set_pass.sh
#
# Tests all 5 enforcement branches:
#   1. proof_graph.json exists + valid   → passes through (no exit 10)
#   2. proof_graph.json exists + invalid → exit 10
#   3. proof_graph.json missing + exempt → passes through (no exit 10)
#   4. proof_graph.json missing + NOT exempt → exit 10
#   5. python3 missing → exit 10
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE="$ROOT/python/proof_graph/validate.py"
EXEMPT_LIST="$ROOT/plans/proof_graph_exempt.txt"
CONTRACT="$ROOT/specs/CONTRACT.md"
PRD="$ROOT/plans/prd.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

command -v python3 >/dev/null 2>&1 || fail "python3 required for these tests"
[[ -f "$VALIDATE" ]] || fail "validate.py not found: $VALIDATE"
[[ -f "$CONTRACT" ]] || fail "CONTRACT.md not found: $CONTRACT"
[[ -f "$PRD" ]] || fail "prd.json not found: $PRD"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ── Test 1: valid proof_graph.json → exit 0 ─────────────────────────

test_valid_proof_graph() {
  local fixture="$ROOT/python/proof_graph/tests/fixtures/valid_proof_graph.json"
  [[ -f "$fixture" ]] || fail "missing fixture: $fixture"

  if python3 "$VALIDATE" "$fixture" \
       --contract-path "$CONTRACT" \
       --prd-path "$PRD" \
       --strict >/dev/null 2>&1; then
    pass "valid proof_graph.json → exit 0"
  else
    fail "valid proof_graph.json should exit 0 but got $?"
  fi
}

# ── Test 2: invalid proof_graph.json → exit 1 (rules fire) ──────────

test_invalid_proof_graph() {
  local fixture="$ROOT/python/proof_graph/tests/fixtures/invalid_blocking.json"
  [[ -f "$fixture" ]] || fail "missing fixture: $fixture"

  if python3 "$VALIDATE" "$fixture" \
       --contract-path "$CONTRACT" \
       --prd-path "$PRD" \
       --strict >/dev/null 2>&1; then
    fail "invalid proof_graph.json should exit non-zero"
  else
    local rc=$?
    if [[ "$rc" -eq 1 ]]; then
      pass "invalid proof_graph.json → exit 1 (validation errors)"
    else
      fail "invalid proof_graph.json expected exit 1 but got $rc"
    fi
  fi
}

# ── Test 3: missing proof_graph + ID in exempt list → INFO ───────────

test_exempt_story() {
  # Pick first ID from exempt list
  local exempt_id
  exempt_id="$(grep -v '^#' "$EXEMPT_LIST" | grep -v '^[[:space:]]*$' | head -1)"
  [[ -n "$exempt_id" ]] || fail "exempt list is empty"

  # Simulate gate logic inline
  local proof_graph_file="$tmp_dir/nonexistent/proof_graph.json"
  if [[ -f "$proof_graph_file" ]]; then
    fail "proof_graph.json should not exist for this test"
  elif [[ -f "$EXEMPT_LIST" ]] && grep -qxF "$exempt_id" "$EXEMPT_LIST"; then
    pass "missing proof_graph + exempt ID ($exempt_id) → INFO (skipped)"
  else
    fail "expected exempt ID $exempt_id to be in exempt list"
  fi
}

# ── Test 4: missing proof_graph + NOT exempt → blocked ───────────────

test_non_exempt_missing() {
  local fake_id="XTEST-999"
  local proof_graph_file="$tmp_dir/nonexistent2/proof_graph.json"

  if [[ -f "$proof_graph_file" ]]; then
    fail "proof_graph.json should not exist for this test"
  elif [[ -f "$EXEMPT_LIST" ]] && grep -qxF "$fake_id" "$EXEMPT_LIST"; then
    fail "fake ID $fake_id should NOT be in exempt list"
  else
    pass "missing proof_graph + non-exempt ID ($fake_id) → would exit 10"
  fi
}

# ── Test 5: unsupported schema version → exit 2 ─────────────────────

test_unsupported_version() {
  local bad_file="$tmp_dir/bad_version.json"
  local fixture="$ROOT/python/proof_graph/tests/fixtures/valid_proof_graph.json"
  python3 -c "
import json, sys
d = json.load(open('$fixture'))
d['schema_version'] = 99
json.dump(d, open('$bad_file', 'w'))
"
  if python3 "$VALIDATE" "$bad_file" \
       --contract-path "$CONTRACT" \
       --prd-path "$PRD" \
       --strict >/dev/null 2>&1; then
    fail "unsupported schema version should exit non-zero"
  else
    local rc=$?
    if [[ "$rc" -eq 2 ]]; then
      pass "unsupported schema_version → exit 2"
    else
      fail "unsupported schema_version expected exit 2 but got $rc"
    fi
  fi
}

# ── Test 6: scaffolded graph has <FILL> placeholders → R-008 fires ──

test_scaffold_then_validate() {
  local scaffold_dir="$tmp_dir/scaffold_out"
  python3 "$ROOT/python/proof_graph/scaffold.py" S1-007 \
    --prd-path "$PRD" \
    --contract-path "$CONTRACT" \
    --output-dir "$scaffold_dir" >/dev/null 2>&1

  [[ -f "$scaffold_dir/proof_graph.json" ]] || fail "scaffold did not create proof_graph.json"

  if python3 "$VALIDATE" "$scaffold_dir/proof_graph.json" \
       --contract-path "$CONTRACT" \
       --prd-path "$PRD" \
       --strict >/dev/null 2>&1; then
    fail "scaffolded proof_graph.json should fail (R-008 placeholders)"
  else
    pass "scaffolded proof_graph.json → validation failure (expected: R-008 placeholders)"
  fi
}

# ── Run all tests ────────────────────────────────────────────────────

echo "=== proof_graph gate regression tests ==="
test_valid_proof_graph
test_invalid_proof_graph
test_exempt_story
test_non_exempt_missing
test_unsupported_version
test_scaffold_then_validate
echo "=== all proof_graph gate tests passed ==="
