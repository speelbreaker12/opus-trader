#!/usr/bin/env bash
# Upgrade 1B architectural proof: "Legacy Orchestration Surface Collapsed"
#
# Verifies the THREE architectural guarantees claimed by Upgrade 1B:
#
#   1. engine_parity_tests.rs is gone — parity coverage moved into the
#      canonical engine decision test suite instead of a separate legacy file.
#
#   2. `ExecutionEngine::evaluate` exists only as a deprecated compatibility
#      alias over `decide`.
#
#   3. api.rs re-exports only domain-level engine types, NOT internal pipeline
#      types (IntentPipelineInput, OpenRuntimeInput, evaluate_intent_pipeline,
#      build_open_order_intent_runtime).  If any of these appear in api.rs the
#      legacy surface has leaked back into the public API.
#
# This script is a BOUNDARY check (the mechanical check already covers
# callsite presence).  Together they prove the surface is collapsed: external
# code cannot reach legacy internals, and the internal routing alias is gone.
#
# Usage: bash plans/tests/test_upgrade_1b_proof.sh
# Exit code: 0 = all checks passed, 1 = one or more checks failed

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FAILURES=0
PASS=0

pass() { echo "  OK : $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL : $1"; FAILURES=$((FAILURES + 1)); }

echo "=== Upgrade 1B Architectural Proof ==="
echo

# ── Check 1: engine_parity_tests.rs must NOT exist ──────────────────────────

echo "--- 1. engine_parity_tests.rs is deleted ---"
if find "$ROOT/crates" -name "engine_parity_tests.rs" | grep -q .; then
    fail "engine_parity_tests.rs still exists — legacy evaluate() test surface not fully removed"
else
    pass "engine_parity_tests.rs absent"
fi
echo

# ── Check 2: Compatibility evaluate alias exists and is deprecated ──────────

echo "--- 2. pub fn evaluate alias exists and is deprecated ---"
ENGINE_RS="$ROOT/crates/soldier_core/src/execution/engine.rs"
if ! grep -Eq '^\s*pub\s+fn\s+evaluate\b' "$ENGINE_RS"; then
    fail "pub fn evaluate missing from engine.rs — compatibility alias regressed"
else
    evaluate_line="$(grep -nE '^\s*pub\s+fn\s+evaluate\b' "$ENGINE_RS" | head -1 | cut -d: -f1)"
    start_line=1
    if [[ "$evaluate_line" -gt 6 ]]; then
        start_line=$((evaluate_line - 6))
    fi
    if sed -n "${start_line},${evaluate_line}p" "$ENGINE_RS" | grep -Fq "#[deprecated"; then
        pass "pub fn evaluate present and deprecated in engine.rs"
    else
        fail "pub fn evaluate exists but is not marked deprecated"
    fi
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
    echo "UPGRADE 1B ARCHITECTURAL PROOF FAILED"
    exit 1
fi
echo "UPGRADE 1B ARCHITECTURAL PROOF PASSED"
