#!/usr/bin/env bash
# Regression tests for plans/aggregate_proofs.sh
#
# Tests:
#   1. No base graph → exit 1 with error message
#   2. Base graph, zero reviewer graphs → exit 0 with warning
#   3. Base graph + 1 reviewer graph → exit 0, aggregation runs, verdict preserved
#   4. Base graph + 2 reviewer graphs → strictest verdict wins (PROVEN_UNIT > PROVEN_INTEGRATED), both sources in meta
#   5. Aggregated graph with BLOCKING → validate.py rejects with error message
#   6. Non-reviewer dirs ignored (simpler-than-correct blocker)
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

# Helper: read a JSON field from the merged graph
read_merged_field() {
  local merged="$1"
  local jq_expr="$2"
  python3 -c "
import json
with open('$merged') as f:
    g = json.load(f)
$jq_expr
"
}

# Helper: run aggregate_proofs.sh with AGGREGATE_ROOT pointing to tmp_dir
run_aggregate() {
  local sid="$1"
  AGGREGATE_ROOT="$tmp_dir" bash "$SCRIPT" "$sid"
}

# ── Test 1: No base graph → exit 1 with error message ────────────

test_no_base_graph() {
  local sid="TEST-NO-BASE"
  setup_story "$sid" >/dev/null

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  [[ $rc -eq 1 ]] || fail "no base graph should exit 1, got $rc"
  echo "$output" | grep -q "ERROR.*Base proof_graph.json not found" \
    || fail "no base graph: expected error message about missing base"
  pass "no base graph → exit 1 with error message"
}

# ── Test 2: Base graph, zero reviewer graphs → exit 0 ────────────

test_zero_reviewers() {
  local sid="TEST-ZERO-REV"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  [[ $rc -eq 0 ]] || fail "zero reviewers should exit 0, got $rc. Output: $output"
  echo "$output" | grep -q "WARN.*No reviewer" \
    || fail "zero reviewers: expected warning about no reviewers"
  pass "zero reviewers → exit 0 with warning"
}

# ── Test 3: Base + 1 reviewer → exit 0, verdict preserved ────────

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

  [[ $rc -eq 0 ]] || fail "single reviewer: expected exit 0, got $rc. Output: $output"
  echo "$output" | grep -q "Aggregated 1 reviewer" \
    || fail "single reviewer: expected 'Aggregated 1 reviewer' in output"

  local merged="$story_dir/proof_graph.json"
  [[ -f "$merged" ]] || fail "single reviewer: merged graph not found at $merged"

  # Verify verdict was applied from reviewer
  local merged_verdict
  merged_verdict="$(read_merged_field "$merged" "print(g['ats'][0]['at_verdict']['verdict'])")"
  [[ "$merged_verdict" == "PROVEN_UNIT" ]] \
    || fail "single reviewer: expected PROVEN_UNIT verdict, got $merged_verdict"

  # Verify review_count in meta
  local review_count
  review_count="$(read_merged_field "$merged" "print(g.get('meta', {}).get('review_count', 'MISSING'))")"
  [[ "$review_count" == "1" ]] \
    || fail "single reviewer: expected review_count=1, got $review_count"

  pass "single reviewer → exit 0, verdict=PROVEN_UNIT, review_count=1"
}

# ── Test 4: Base + 2 reviewers → strictest verdict, both sources ──

test_two_reviewers_strictest() {
  local sid="TEST-TWO-REV"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"
  # Use PROVEN_INTEGRATED (rank 0) and PROVEN_UNIT (rank 1) —
  # both pass validate.py --strict, but PROVEN_UNIT is stricter.
  create_reviewer_graph "$story_dir" "opus" "PROVEN_INTEGRATED"
  create_reviewer_graph "$story_dir" "codex" "PROVEN_UNIT"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  [[ $rc -eq 0 ]] || fail "two reviewers: expected exit 0, got $rc. Output: $output"
  echo "$output" | grep -q "Aggregated 2 reviewer" \
    || fail "two reviewers: expected 'Aggregated 2 reviewer' in output"

  local merged="$story_dir/proof_graph.json"
  [[ -f "$merged" ]] || fail "two reviewers: merged graph not found at $merged"

  # Verify strictest verdict wins (PROVEN_UNIT > PROVEN_INTEGRATED)
  local merged_verdict
  merged_verdict="$(read_merged_field "$merged" "print(g['ats'][0]['at_verdict']['verdict'])")"
  [[ "$merged_verdict" == "PROVEN_UNIT" ]] \
    || fail "two reviewers: expected PROVEN_UNIT (strictest), got $merged_verdict"

  # Verify both reviewers recorded in meta.review_sources
  local sources
  sources="$(read_merged_field "$merged" "
s = g.get('meta', {}).get('review_sources', [])
print(','.join(sorted(s)))
")"
  [[ "$sources" == "codex,opus" ]] \
    || fail "two reviewers: expected review_sources=[codex,opus], got $sources"

  # Verify review_count
  local review_count
  review_count="$(read_merged_field "$merged" "print(g.get('meta', {}).get('review_count', 'MISSING'))")"
  [[ "$review_count" == "2" ]] \
    || fail "two reviewers: expected review_count=2, got $review_count"

  pass "two reviewers → strictest verdict (PROVEN_UNIT), both sources in meta"
}

# ── Test 5: BLOCKING severity → validate.py rejects with message ──

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

  [[ $rc -ne 0 ]] || fail "BLOCKING graph should fail validation, got exit 0"
  echo "$output" | grep -qE "ERROR.*validation failed|CRITICAL.*Trading halt" \
    || fail "BLOCKING: expected error/critical message. Output: $output"
  pass "BLOCKING aggregation → validate.py rejects (exit $rc) with message"
}

# ── Test 6: Non-reviewer dirs ignored (simpler-than-correct gate) ──
# If a `self_review/` or `premortem/` directory contains a proof_graph.json,
# it must NOT be included in aggregation. Only KNOWN_TOOLS dirs count.
# This blocks the simpler-than-correct exploit where `cp REVIEWS[0] BASE`
# would pass if stray dirs were included.

test_non_reviewer_dirs_ignored() {
  local sid="TEST-STRAY-DIR"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"

  # Create a valid reviewer graph with a known tool
  create_reviewer_graph "$story_dir" "opus" "PROVEN_UNIT"

  # Create a stray proof_graph.json in a non-reviewer directory
  # This graph has a DIFFERENT verdict — if included, strictest would differ
  create_reviewer_graph "$story_dir" "self_review" "FAIL_OPEN_RISK" "BLOCKING"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  # Aggregation should succeed (only opus counted, self_review ignored)
  [[ $rc -eq 0 ]] || fail "stray dir: expected exit 0 (self_review ignored), got $rc. Output: $output"

  # Should aggregate exactly 1 reviewer (opus), not 2
  echo "$output" | grep -q "Aggregated 1 reviewer" \
    || fail "stray dir: expected 'Aggregated 1 reviewer' (self_review should be ignored)"

  # Verify verdict is from opus (PROVEN_UNIT), not from self_review (FAIL_OPEN_RISK)
  local merged="$story_dir/proof_graph.json"
  local merged_verdict
  merged_verdict="$(read_merged_field "$merged" "print(g['ats'][0]['at_verdict']['verdict'])")"
  [[ "$merged_verdict" == "PROVEN_UNIT" ]] \
    || fail "stray dir: expected PROVEN_UNIT (opus only), got $merged_verdict"

  pass "non-reviewer dir (self_review) correctly ignored"
}

# ── Run all tests ─────────────────────────────────────────────────

echo "=== aggregate_proofs.sh tests ==="
test_no_base_graph
test_zero_reviewers
test_single_reviewer
test_two_reviewers_strictest
test_blocking_rejected
test_non_reviewer_dirs_ignored
echo "=== all tests passed ==="
