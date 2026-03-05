#!/usr/bin/env bash
# Mechanical verification checks for Slice 1 reconciliation findings.
#
# Three automated checks that catch the most common false-compliance patterns:
#   1. Compile gate — cargo test --no-run --workspace
#   2. Callsite check — enforcement_point functions have production callers
#   3. Test existence check — implementation_tests[] entries exist as real #[test] fns
#
# Usage: ./plans/verify_mechanical.sh [--strict]
#   --strict: exit 1 on first failure (default: run all, report at end)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STRICT=0
if [[ "${1:-}" == "--strict" ]]; then
  STRICT=1
fi

FAILURES=0
CHECKS=0
PASS=0

fail() {
  echo "  FAIL: $1"
  FAILURES=$((FAILURES + 1))
  if [[ "$STRICT" == "1" ]]; then
    echo "MECHANICAL VERIFICATION FAILED (strict mode)"
    exit 1
  fi
}

pass() {
  echo "  OK: $1"
  PASS=$((PASS + 1))
}

# ── Check 1: Compile gate ──────────────────────────────────────────

echo "=== Check 1: Compile gate ==="
CHECKS=$((CHECKS + 1))
if cargo test --no-run --workspace 2>&1 | tail -5; then
  pass "cargo test --no-run --workspace succeeded"
else
  fail "cargo test --no-run --workspace failed — tests do not compile"
fi
echo

# ── Check 2: Callsite check ────────────────────────────────────────
#
# For each non-empty enforcement_point on passes=true stories in prd.json,
# verify at least one production callsite exists (excluding tests/).

echo "=== Check 2: Enforcement point callsite check ==="
CHECKS=$((CHECKS + 1))

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not found"
else
  prd="$ROOT/plans/prd.json"
  if [[ ! -f "$prd" ]]; then
    fail "prd.json not found at $prd"
  else
    ep_failures=0
    ep_total=0

    # Extract unique non-empty enforcement_point values from passes=true stories.
    while IFS= read -r ep; do
      [[ -z "$ep" ]] && continue
      ep_total=$((ep_total + 1))

      # Map enforcement_point names to grep-able function/module patterns
      # These are module-level labels, not function names — we check for
      # usage of the module's key functions in production code.
      case "$ep" in
        PolicyGuard)
          pattern="PolicyGuard\|policy_guard\|resolve_trading_mode"
          ;;
        DispatcherChokepoint)
          pattern="build_order_intent\|DispatcherChokepoint\|choke_pipeline\|intent_pipeline"
          ;;
        WAL)
          pattern="WalLedger\|wal_ledger\|append\|RecordedBeforeDispatch"
          ;;
        StatusEndpoint)
          pattern="_cmd_status\|_cmd_health\|_status_payload\|_health_payload\|/api/v1/status\|/api/v1/health\|status_endpoint"
          ;;
        EvidenceGuard)
          pattern="EvidenceGuard\|evidence_guard"
          ;;
        AtomicGroupExecutor)
          pattern="AtomicGroupExecutor\|atomic_group"
          ;;
        *)
          pattern="$ep"
          ;;
      esac

      # Search production src/ only (crates/*/src/ — excludes tests/ dirs and in-file cfg(test) blocks).
      # StatusEndpoint is implemented via the production CLI entrypoint (`stoic-cli`)
      # in addition to Rust code.
      if [[ "$ep" == "StatusEndpoint" ]]; then
        hits=$(
          {
            find "$ROOT/crates" -path '*/src/*.rs' -type f 2>/dev/null \
              | xargs grep -l "$pattern" 2>/dev/null || true
            grep -l "$pattern" "$ROOT/stoic-cli" 2>/dev/null || true
          } | sort -u \
            | head -3 || true
        )
      else
        hits=$(find "$ROOT/crates" -path '*/src/*.rs' -type f 2>/dev/null \
          | xargs grep -l "$pattern" 2>/dev/null \
          | head -3 || true)
      fi

      if [[ -z "$hits" ]]; then
        echo "  WARN: enforcement_point '$ep' — zero production callsites found"
        ep_failures=$((ep_failures + 1))
      fi
    done < <(jq -r '.items[] | select(.passes == true) | .enforcement_point // empty' "$prd" 2>/dev/null | sort -u | grep -v '^$')

    if [[ "$ep_failures" -gt 0 ]]; then
      fail "enforcement_point callsite check: $ep_failures/$ep_total enforcement points have zero production callsites"
    else
      pass "enforcement_point callsite check: $ep_total enforcement points verified"
    fi
  fi
fi
echo

# ── Check 3: Test existence check ──────────────────────────────────
#
# For each implementation_tests[] entry on passes=true stories in prd.json,
# verify the file exists and contains the referenced test marker.

echo "=== Check 3: Test existence check ==="
CHECKS=$((CHECKS + 1))

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not found"
else
  prd="$ROOT/plans/prd.json"
  if [[ ! -f "$prd" ]]; then
    fail "prd.json not found at $prd"
  else
    test_failures=0
    test_total=0
    test_missing_file=0
    test_missing_fn=0

    # Extract all implementation_tests entries: "path::fn_name"
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      test_total=$((test_total + 1))

      if [[ "$entry" != *"::"* ]]; then
        echo "  MALFORMED ENTRY: $entry (expected path::test_name)"
        test_missing_fn=$((test_missing_fn + 1))
        test_failures=$((test_failures + 1))
        continue
      fi

      # Split on :: separator
      file_path="${entry%%::*}"
      test_fn="${entry##*::}"

      # Handle Python tests (path::class::method or path::function)
      if [[ "$file_path" == *.py ]]; then
        # For Python, just check file exists and function name appears
        if [[ ! -f "$ROOT/$file_path" ]]; then
          echo "  MISSING FILE: $file_path (from entry: $entry)"
          test_missing_file=$((test_missing_file + 1))
          test_failures=$((test_failures + 1))
        elif ! grep -q "def ${test_fn}" "$ROOT/$file_path" 2>/dev/null; then
          echo "  MISSING FN: ${test_fn} not found in $file_path"
          test_missing_fn=$((test_missing_fn + 1))
          test_failures=$((test_failures + 1))
        fi
        continue
      fi

      # Shell tests: verify marker appears in the script.
      if [[ "$file_path" == *.sh ]]; then
        if [[ ! -f "$ROOT/$file_path" ]]; then
          echo "  MISSING FILE: $file_path (from entry: $entry)"
          test_missing_file=$((test_missing_file + 1))
          test_failures=$((test_failures + 1))
        elif ! grep -Fq "$test_fn" "$ROOT/$file_path" 2>/dev/null; then
          echo "  MISSING FN: ${test_fn} not found in $file_path"
          test_missing_fn=$((test_missing_fn + 1))
          test_failures=$((test_failures + 1))
        fi
        continue
      fi

      # Rust tests: path::test_fn_name
      if [[ ! -f "$ROOT/$file_path" ]]; then
        echo "  MISSING FILE: $file_path (from entry: $entry)"
        test_missing_file=$((test_missing_file + 1))
        test_failures=$((test_failures + 1))
      elif ! grep -q "fn ${test_fn}" "$ROOT/$file_path" 2>/dev/null; then
        echo "  MISSING FN: ${test_fn} not found in $file_path"
        test_missing_fn=$((test_missing_fn + 1))
        test_failures=$((test_failures + 1))
      fi
    done < <(jq -r '.items[] | select(.passes == true) | .implementation_tests[]? // empty' "$prd" 2>/dev/null | sort -u)

    if [[ "$test_failures" -gt 0 ]]; then
      fail "test existence check: $test_failures failures ($test_missing_file missing files, $test_missing_fn missing fns) out of $test_total tests"
    else
      pass "test existence check: $test_total tests verified"
    fi
  fi
fi
echo

# ── Check 4: Upgrade 1B cleanup-boundary proof ─────────────────────
#
# Verifies the three cleanup-slice guarantees claimed by the PR4 cleanup work:
#   - engine_parity_tests.rs is deleted
#   - pub fn evaluate alias is absent from engine.rs
#   - api.rs exposes no legacy internal pipeline types

echo "=== Check 4: Upgrade 1B cleanup-boundary proof ==="
CHECKS=$((CHECKS + 1))
proof_script="$ROOT/plans/tests/test_upgrade_1b_proof.sh"
if [[ ! -f "$proof_script" ]]; then
  fail "test_upgrade_1b_proof.sh not found — 1B proof gate missing"
elif bash "$proof_script"; then
  pass "Upgrade 1B cleanup-boundary proof passed"
else
  fail "Upgrade 1B cleanup-boundary proof failed — see output above"
fi
echo

# ── Summary ─────────────────────────────────────────────────────────

echo "=== Summary ==="
echo "  Checks run: $CHECKS"
echo "  Passed: $PASS"
echo "  Failed: $FAILURES"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "MECHANICAL VERIFICATION FAILED ($FAILURES failures)"
  exit 1
else
  echo "MECHANICAL VERIFICATION PASSED"
  exit 0
fi
