#!/usr/bin/env bash
# Upgrade 1B cleanup-boundary proof.
#
# Verifies the THREE cleanup guarantees shipped by the PR4 cleanup slice:
#
#   1. engine_parity_tests.rs is gone — the legacy evaluate()-alias test file
#      does not exist anywhere in the codebase.
#
#   2. No `pub fn evaluate` alias on ExecutionEngine — the legacy routing alias
#      has been removed and must not reappear.
#
#   3. api.rs re-exports only domain-level engine types, NOT internal pipeline
#      types (IntentPipelineInput, OpenRuntimeInput, evaluate_intent_pipeline,
#      build_open_order_intent_runtime).  If any of these appear in api.rs the
#      legacy surface has leaked back into the public API.
#
# This script is intentionally a BOUNDARY cleanup check.
# It proves the public surface stayed narrowed and the orphaned alias/test
# surface stayed deleted. It does NOT prove that engine.rs no longer routes
# through build_open_order_intent_runtime() or evaluate_intent_pipeline().
#
# Usage: bash plans/tests/test_upgrade_1b_proof.sh
# Exit code: 0 = all checks passed, 1 = one or more checks failed

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FAILURES=0
PASS=0

pass() { echo "  OK : $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL : $1"; FAILURES=$((FAILURES + 1)); }

echo "=== Upgrade 1B Cleanup Boundary Proof ==="
echo

# ── Check 1: engine_parity_tests.rs must NOT exist ──────────────────────────

echo "--- 1. engine_parity_tests.rs is deleted ---"
if [[ -n "$(find "$ROOT/crates" -name "engine_parity_tests.rs" -print -quit)" ]]; then
    fail "engine_parity_tests.rs still exists — legacy evaluate() test surface not fully removed"
else
    pass "engine_parity_tests.rs absent"
fi
echo

# ── Check 2: No 'pub fn evaluate' alias on ExecutionEngine ──────────────────

echo "--- 2. No pub fn evaluate alias in engine.rs ---"
ENGINE_RS="$ROOT/crates/soldier_core/src/execution/engine.rs"
if grep -Eq '^\s*pub\s+fn\s+evaluate\b' "$ENGINE_RS"; then
    fail "pub fn evaluate still present in engine.rs — legacy routing alias not removed"
else
    pass "pub fn evaluate absent from engine.rs"
fi
echo

# ── Check 3: api.rs must not expose legacy pipeline internals ────────────────

echo "--- 3. api.rs does not re-export legacy internal pipeline types ---"
API_RS="$ROOT/crates/soldier_core/src/execution/api.rs"

LEGACY_SYMBOLS=(
    "IntentPipelineInput"
    "OpenRuntimeInput"
    "evaluate_intent_pipeline"
    "build_open_order_intent_runtime"
    "QuantizePipelineInput"
    "IntentPipelineMetrics"
    "OpenRuntimeMetrics"
    "OpenRuntimeOutput"
)

LEAKED=0
for sym in "${LEGACY_SYMBOLS[@]}"; do
    if grep -q "$sym" "$API_RS"; then
        fail "legacy symbol '$sym' appears in api.rs public re-exports"
        LEAKED=$((LEAKED + 1))
    fi
done
if [[ "$LEAKED" -eq 0 ]]; then
    pass "no legacy pipeline symbols in api.rs (${#LEGACY_SYMBOLS[@]} symbols checked)"
fi
echo

# ── Summary ──────────────────────────────────────────────────────────────────

echo "=== Result: $PASS passed, $FAILURES failed ==="
if [[ "$FAILURES" -gt 0 ]]; then
    echo "UPGRADE 1B CLEANUP BOUNDARY PROOF FAILED"
    exit 1
fi
echo "UPGRADE 1B CLEANUP BOUNDARY PROOF PASSED"
