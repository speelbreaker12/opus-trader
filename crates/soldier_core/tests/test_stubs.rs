#![allow(dead_code)]

use soldier_core::execution::{GateResults, RecordedBeforeDispatchGate, build_gate_results};

/// Stub WAL gate for contract-level tests that need the WAL-safe path.
pub struct StubWalGate;

impl RecordedBeforeDispatchGate for StubWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        Ok(())
    }
}

/// Failing WAL gate for tests that verify RecordedBeforeDispatch rejection.
pub struct FailingWalGate;

impl RecordedBeforeDispatchGate for FailingWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        Err("wal append failed".to_string())
    }
}

/// All-passing gate results with fail-closed WAL.
///
/// `wal_recorded` defaults to false so callsites must pass a WAL gate adapter
/// when exercising OPEN approval paths.
pub fn gate_results_all_passing_failclosed_wal() -> GateResults {
    build_gate_results(
        true,  // preflight_passed
        true,  // quantize_passed
        true,  // dispatch_consistency_passed
        true,  // fee_cache_passed
        true,  // expiry_guard_passed
        true,  // liquidity_gate_passed
        true,  // net_edge_passed
        true,  // pricer_passed
        false, // wal_recorded
        None,  // requested_qty
        None,  // max_dispatch_qty
    )
}
