#!/usr/bin/env bash
# Regression tests for plans/aggregate_proofs.sh
#
# Tests:
#   1. No base graph → exit 1 with error
#   2. Base graph, zero reviewer graphs → exit 0 with warning
#   3. Base graph + 1 reviewer graph → aggregation works, warning
#   4. Base graph + 2 reviewer graphs → strictest verdict wins
#   5. Aggregated graph with BLOCKING → validate.py rejects
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/aggregate_proofs.sh"
AGGREGATE_PY="$ROOT/python/proof_graph/aggregate.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

command -v python3 >/dev/null 2>&1 || fail "python3 required"
[[ -x "$SCRIPT" ]] || fail "aggregate_proofs.sh not found or not executable: $SCRIPT"
[[ -f "$AGGREGATE_PY" ]] || fail "aggregate.py not found: $AGGREGATE_PY"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

FIXTURE_BASE="$ROOT/python/proof_graph/tests/fixtures/valid_proof_graph_v2.json"
[[ -f "$FIXTURE_BASE" ]] || fail "missing fixture: $FIXTURE_BASE"

# Create a minimal specs/ and plans/ in tmp_dir so validate.py can find them
mkdir -p "$tmp_dir/specs" "$tmp_dir/plans"
cp "$ROOT/specs/CONTRACT.md" "$tmp_dir/specs/CONTRACT.md"
cp "$ROOT/plans/prd.json" "$tmp_dir/plans/prd.json"

# Helper: create a minimal artifacts/story/<ID>/ layout in tmp
setup_story() {
  local sid="$1"
  local story_dir="$tmp_dir/artifacts/story/$sid"
  mkdir -p "$story_dir"
  echo "$story_dir"
}

# Helper: copy base fixture into story dir
copy_base() {
  local story_dir="$1"
  cp "$FIXTURE_BASE" "$story_dir/proof_graph.json"
}

# Helper: create a reviewer graph with a specific verdict
create_reviewer_graph() {
  local story_dir="$1"
  local tool="$2"
  local verdict="$3"
  local severity="${4:-INFO}"
  local reviewer_dir="$story_dir/$tool"
  mkdir -p "$reviewer_dir"

  python3 -c "
import json
with open('$FIXTURE_BASE') as f:
    g = json.load(f)
for at in g.get('ats', []):
    at['at_verdict']['verdict'] = '$verdict'
    at['at_verdict']['severity'] = '$severity'
with open('$reviewer_dir/proof_graph.json', 'w') as f:
    json.dump(g, f, indent=2)
"
}

# Helper: run aggregate_proofs.sh with AGGREGATE_ROOT pointing to tmp_dir
run_aggregate() {
  local sid="$1"
  AGGREGATE_ROOT="$tmp_dir" bash "$SCRIPT" "$sid"
}

# ── Test 1: No base graph → exit 1 ──────────────────────────────────

test_no_base_graph() {
  local sid="TEST-NO-BASE"
  setup_story "$sid" >/dev/null

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 1 ]]; then
    pass "no base graph → exit 1"
  else
    fail "no base graph should exit 1, got $rc"
  fi
}

# ── Test 2: Base graph, zero reviewer graphs → exit 0 ────────────────

test_zero_reviewers() {
  local sid="TEST-ZERO-REV"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    pass "zero reviewers → exit 0 with warning"
  else
    fail "zero reviewers should exit 0, got $rc. Output: $output"
  fi
}

# ── Test 3: Base + 1 reviewer → aggregation + single-reviewer warn ───

test_single_reviewer() {
  local sid="TEST-SINGLE-REV"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"
  create_reviewer_graph "$story_dir" "opus" "PROVEN_UNIT"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  if echo "$output" | grep -q "Aggregated 1 reviewer"; then
    pass "single reviewer → aggregation ran"
  elif echo "$output" | grep -q "WARN.*1 reviewer"; then
    pass "single reviewer → aggregation ran with corroboration warning"
  else
    fail "single reviewer: expected aggregation log. rc=$rc Output: $output"
  fi
}

# ── Test 4: Base + 2 reviewers → strictest verdict wins ──────────────

test_two_reviewers_strictest() {
  local sid="TEST-TWO-REV"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"
  create_reviewer_graph "$story_dir" "opus" "PROVEN_UNIT"
  create_reviewer_graph "$story_dir" "codex" "WEAK_PROOF" "HARDENING"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  if echo "$output" | grep -q "Aggregated 2 reviewer"; then
    local merged="$story_dir/proof_graph.json"
    if [[ -f "$merged" ]]; then
      local merged_verdict
      merged_verdict="$(python3 -c "
import json
with open('$merged') as f:
    g = json.load(f)
print(g['ats'][0]['at_verdict']['verdict'])
")"
      if [[ "$merged_verdict" == "WEAK_PROOF" ]]; then
        pass "two reviewers → strictest verdict (WEAK_PROOF) wins"
      else
        fail "two reviewers: expected WEAK_PROOF, got $merged_verdict"
      fi
    else
      fail "two reviewers: merged graph not found at $merged"
    fi
  else
    fail "two reviewers: expected aggregation. rc=$rc Output: $output"
  fi
}

# ── Test 5: Aggregated graph with BLOCKING severity → validate rejects ─

test_blocking_rejected() {
  local sid="TEST-BLOCKING"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"
  create_reviewer_graph "$story_dir" "opus" "FAIL_OPEN_RISK" "BLOCKING"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    pass "BLOCKING aggregation → validate.py rejects (exit $rc)"
  else
    fail "BLOCKING graph should fail validation, got exit 0"
  fi
}

# ── Run all tests ─────────────────────────────────────────────────────

echo "=== aggregate_proofs.sh tests ==="
test_no_base_graph
test_zero_reviewers
test_single_reviewer
test_two_reviewers_strictest
test_blocking_rejected
echo "=== all tests passed ==="
