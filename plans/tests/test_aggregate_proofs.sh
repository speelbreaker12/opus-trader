#!/usr/bin/env bash
# Regression tests for plans/aggregate_proofs.sh
#
# Tests:
#   1. No base graph → exit 1 with error message
#   2. Base graph, zero reviewer graphs → exit 0 with warning
#   3. STORY_ARTIFACTS_ROOT override is honored for base + reviewer graphs
#   4. Base graph + 1 reviewer graph → exit 0, aggregation runs, verdict preserved
#   5. Base graph + 2 reviewer graphs → strictest verdict wins (PROVEN_UNIT > PROVEN_INTEGRATED), both sources in meta
#   6. Aggregated graph with BLOCKING → validate.py rejects with error message
#   7. Non-reviewer dirs ignored (simpler-than-correct blocker)
#   8. Validation failure preserves base graph (atomic write invariant)
#   9. Trading halt (exit 20) → CRITICAL message, merged graph written to base
#   10. KNOWN_TOOLS sync with review_logged.sh (drift detection)
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

# Detect python binary (same preference order as aggregate_proofs.sh)
if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  fail "python3 or python required"
fi
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
  local loss_level="${5:-}"  # optional: override story_meta.loss_mode.level
  local reviewer_dir="$story_dir/$tool"
  mkdir -p "$reviewer_dir"

  "$PY" -c "
import json
with open('$FIXTURE_BASE') as f:
    g = json.load(f)
for at in g.get('ats', []):
    at['at_verdict']['verdict'] = '$verdict'
    at['at_verdict']['severity'] = '$severity'
ll = '$loss_level'
if ll:
    g['story_meta']['loss_mode']['level'] = ll
    g.setdefault('meta', {}).setdefault('hints', {}).setdefault('AT-201', {})['loss_mode_level'] = ll
with open('$reviewer_dir/proof_graph.json', 'w') as f:
    json.dump(g, f, indent=2)
"
}

# Helper: copy base fixture with optional loss_mode level override
copy_base_with_level() {
  local story_dir="$1"
  local loss_level="$2"
  "$PY" -c "
import json
with open('$FIXTURE_BASE') as f:
    g = json.load(f)
g['story_meta']['loss_mode']['level'] = '$loss_level'
g.setdefault('meta', {}).setdefault('hints', {}).setdefault('AT-201', {})['loss_mode_level'] = '$loss_level'
with open('$story_dir/proof_graph.json', 'w') as f:
    json.dump(g, f, indent=2)
"
}

# Helper: read a JSON field from the merged graph
read_merged_field() {
  local merged="$1"
  local jq_expr="$2"
  "$PY" -c "
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

# ── Test 3: STORY_ARTIFACTS_ROOT override is honored ──────────────

test_story_artifacts_root_override() {
  local sid="TEST-STORY-ROOT"
  local story_root="$tmp_dir/custom_story_root"
  local story_dir="$story_root/$sid"
  mkdir -p "$story_dir"
  copy_base "$story_dir"
  create_reviewer_graph "$story_dir" "opus" "PROVEN_UNIT"

  set +e
  output="$(STORY_ARTIFACTS_ROOT="$story_root" bash "$SCRIPT" "$sid" 2>&1)"
  rc=$?
  set -e

  [[ $rc -eq 0 ]] || fail "story root override: expected exit 0, got $rc. Output: $output"
  echo "$output" | grep -q "Aggregated 1 reviewer" \
    || fail "story root override: expected 'Aggregated 1 reviewer' in output"
  [[ -f "$story_root/$sid/proof_graph.json" ]] \
    || fail "story root override: merged graph not found under STORY_ARTIFACTS_ROOT"
  [[ ! -e "$tmp_dir/artifacts/story/$sid/proof_graph.json" ]] \
    || fail "story root override: aggregate_proofs.sh should not fall back to default artifacts/story"

  local merged_verdict
  merged_verdict="$(read_merged_field "$story_root/$sid/proof_graph.json" "print(g['ats'][0]['at_verdict']['verdict'])")"
  [[ "$merged_verdict" == "PROVEN_UNIT" ]] \
    || fail "story root override: expected PROVEN_UNIT verdict, got $merged_verdict"

  pass "story root override → aggregate_proofs honors STORY_ARTIFACTS_ROOT"
}

# ── Test 4: Base + 1 reviewer → exit 0, verdict preserved ────────

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

# ── Test 5: Base + 2 reviewers → strictest verdict, both sources ──

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

# ── Test 6: BLOCKING severity → validate.py rejects with message ──

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

  [[ $rc -eq 1 ]] || fail "BLOCKING graph should exit 1 (validation failure), got $rc"
  echo "$output" | grep -qE "ERROR.*validation failed|CRITICAL.*Trading halt" \
    || fail "BLOCKING: expected error/critical message. Output: $output"
  pass "BLOCKING aggregation → validate.py rejects (exit $rc) with message"
}

# ── Test 7: Non-reviewer dirs ignored (simpler-than-correct gate) ──
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

# ── Test 7: Validation failure preserves base graph (atomic write) ──
# Devils-advocate mutation 5: if aggregate wrote directly to BASE (no temp),
# this test would fail because BASE would be overwritten with invalid data.

test_base_preserved_on_failure() {
  local sid="TEST-PRESERVE"
  local story_dir
  story_dir="$(setup_story "$sid")"
  copy_base "$story_dir"

  # Record base content before aggregation
  local base_before
  base_before="$(cat "$story_dir/proof_graph.json")"

  # Create a reviewer with FAIL_OPEN_RISK/BLOCKING — will fail validation
  create_reviewer_graph "$story_dir" "opus" "FAIL_OPEN_RISK" "BLOCKING"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  # Must fail validation (exit 1, not exit 20 — MED loss level doesn't trigger halt)
  [[ $rc -eq 1 ]] || fail "preserve: expected exit 1 (validation failure), got $rc"

  # Base graph must be byte-identical to pre-aggregation state
  local base_after
  base_after="$(cat "$story_dir/proof_graph.json")"
  [[ "$base_before" == "$base_after" ]] \
    || fail "preserve: base graph was modified despite validation failure (atomic write broken)"

  pass "validation failure → base graph preserved (atomic write invariant)"
}

# ── Test 8: Trading halt (exit 20) → CRITICAL message + graph written ──
# Exercises the rc=20 code path (lines 92-95 of aggregate_proofs.sh).
# Requires: safety_critical=true + loss_level=HIGH + FAIL_OPEN_RISK verdict.

test_trading_halt() {
  local sid="TEST-HALT"
  local story_dir
  story_dir="$(setup_story "$sid")"
  # Use HIGH loss_level (not MED) to trigger trading halt
  copy_base_with_level "$story_dir" "HIGH"

  # Create reviewer with FAIL_OPEN_RISK — with HIGH loss, triggers halt
  create_reviewer_graph "$story_dir" "opus" "FAIL_OPEN_RISK" "BLOCKING" "HIGH"

  set +e
  output="$(run_aggregate "$sid" 2>&1)"
  rc=$?
  set -e

  # Must exit 20 (trading halt)
  [[ $rc -eq 20 ]] || fail "trading halt: expected exit 20, got $rc. Output: $output"

  # Must contain CRITICAL message
  echo "$output" | grep -q "CRITICAL.*Trading halt" \
    || fail "trading halt: expected 'CRITICAL.*Trading halt' in output. Output: $output"

  # Must contain aggregation confirmation (graph is written for inspectability)
  echo "$output" | grep -q "Aggregated 1 reviewer" \
    || fail "trading halt: expected 'Aggregated 1 reviewer' in output"

  # Verify merged graph WAS written to base (exit 20 intentionally commits)
  local merged_verdict
  merged_verdict="$(read_merged_field "$story_dir/proof_graph.json" "print(g['ats'][0]['at_verdict']['verdict'])")"
  [[ "$merged_verdict" == "FAIL_OPEN_RISK" ]] \
    || fail "trading halt: expected FAIL_OPEN_RISK in base (written for forensics), got $merged_verdict"

  pass "trading halt → exit 20, CRITICAL message, merged graph written"
}

# ── Test 10: KNOWN_TOOLS sync with review_logged.sh ───────────────
# Verifies that the KNOWN_TOOLS list in aggregate_proofs.sh matches
# the tool case-statement in review_logged.sh, catching drift.

test_known_tools_sync() {
  local aggregate_tools review_tools
  # Extract KNOWN_TOOLS value from aggregate_proofs.sh
  aggregate_tools="$(grep '^KNOWN_TOOLS=' "$SCRIPT" | sed 's/KNOWN_TOOLS="//' | sed 's/"$//' | tr ' ' '\n' | sort | tr '\n' ' ' | xargs)"
  # Extract tool names from the case-statement in review_logged.sh
  local review_script="$ROOT/plans/review_logged.sh"
  [[ -f "$review_script" ]] || fail "known_tools_sync: review_logged.sh not found"
  review_tools="$(grep -E '^\s+codex\|opus\|kimi\|gemini\)' "$review_script" | sed 's/[);[:space:]]//g' | tr '|' '\n' | sort | tr '\n' ' ' | xargs)"

  [[ "$aggregate_tools" == "$review_tools" ]] \
    || fail "known_tools_sync: KNOWN_TOOLS='$aggregate_tools' != review_logged.sh tools='$review_tools'"
  pass "KNOWN_TOOLS in aggregate_proofs.sh matches review_logged.sh case-statement"
}

# ── Run all tests ─────────────────────────────────────────────────

echo "=== aggregate_proofs.sh tests ==="
test_no_base_graph
test_zero_reviewers
test_story_artifacts_root_override
test_single_reviewer
test_two_reviewers_strictest
test_blocking_rejected
test_non_reviewer_dirs_ignored
test_base_preserved_on_failure
test_trading_halt
test_known_tools_sync
echo "=== all tests passed ==="
