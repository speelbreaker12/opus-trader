use soldier_core::execution::GateResults;

/// Test helper: returns GateResults with ALL gates passing.
///
/// Use this in integration tests that need a passing baseline.
/// For tests that check specific gate failures, override individual fields:
/// `GateResults { some_gate: false, ..gate_results_all_passing() }`
pub fn gate_results_all_passing() -> GateResults {
    GateResults {
        preflight_passed: true,
        quantize_passed: true,
        dispatch_consistency_passed: true,
        fee_cache_passed: true,
        liquidity_gate_passed: true,
        net_edge_passed: true,
        pricer_passed: true,
        wal_recorded: true,
        requested_qty: None,
        max_dispatch_qty: None,
    }
}
