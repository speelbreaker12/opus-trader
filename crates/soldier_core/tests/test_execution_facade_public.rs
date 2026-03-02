//! External-surface smoke tests for `soldier_core::execution`.
//! These must import through `soldier_core::...` (integration test context).

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

#[allow(unused_imports)]
use soldier_core::execution::{
    AtomicGroup, ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateRejectCodes,
    GateResults, GateStep, GroupConfig, GroupError, GroupLock, GroupState, GroupStateTransition,
    LABEL_MAX_LEN, LabelError, LabelInput, LegResult, LockAcquisitionResult, OooCategory,
    OrderSize, PersistedTransition, RecordedBeforeDispatchGate, RejectReasonCode, Side, Tlsm,
    TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult, build_gate_results,
    build_order_intent_with_optional_wal_gate, build_order_intent_with_wal_gate, derive_gid12,
    derive_sid8, encode_label, reject_reason_from_chokepoint, reject_reason_registry,
    reject_reason_registry_contains, try_acquire_group_lock,
};

fn extract_symbol_set(file_path: &Path, anchor: &str) -> BTreeSet<String> {
    let content = fs::read_to_string(file_path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", file_path.display()));

    let start = content.find(anchor).unwrap_or_else(|| {
        panic!(
            "failed to find anchor `{anchor}` in {}",
            file_path.display()
        )
    });
    let rest = &content[start + anchor.len()..];
    let end = rest.find("};").unwrap_or_else(|| {
        panic!(
            "failed to find end of use block after anchor `{anchor}` in {}",
            file_path.display()
        )
    });

    rest[..end]
        .split(',')
        .map(str::trim)
        .filter(|symbol| !symbol.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn assert_facade_symbol_lists_in_sync() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let unit_test_file = manifest_dir.join("src/execution/facade_completeness_contract_tests.rs");
    let integration_test_file = manifest_dir.join("tests/test_execution_facade_public.rs");

    let unit_symbols = extract_symbol_set(&unit_test_file, "use crate::execution::{");
    let integration_symbols =
        extract_symbol_set(&integration_test_file, "use soldier_core::execution::{");

    let missing_in_integration: Vec<String> = unit_symbols
        .difference(&integration_symbols)
        .cloned()
        .collect();
    let missing_in_unit: Vec<String> = integration_symbols
        .difference(&unit_symbols)
        .cloned()
        .collect();

    assert!(
        missing_in_integration.is_empty() && missing_in_unit.is_empty(),
        "facade symbol lists drifted.\nmissing in integration test: {:?}\nmissing in unit test: {:?}",
        missing_in_integration,
        missing_in_unit
    );
}

#[test]
fn execution_facade_symbols_publicly_reachable() {
    let gates = build_gate_results(
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        Some(1.0),
        Some(1.0),
    );
    assert!(gates.preflight_passed);
    assert!(gates.pricer_passed);
    assert!(gates.wal_recorded);

    let registry = reject_reason_registry();
    assert!(
        !registry.is_empty(),
        "reject reason registry must not be empty"
    );
    assert!(
        reject_reason_registry_contains(RejectReasonCode::RecordedBeforeDispatchFailed),
        "expected RecordedBeforeDispatchFailed in facade reject reason registry"
    );

    let mapped = reject_reason_from_chokepoint(
        &ChokeRejectReason::RiskStateNotHealthy,
        &GateRejectCodes::default(),
    );
    assert_eq!(mapped, RejectReasonCode::MarginHeadroomRejectOpens);
}

#[test]
fn execution_chokepoint_symbols_publicly_reachable() {
    #[allow(unused_imports)]
    use soldier_core::execution::{
        build_gate_results, build_order_intent_with_optional_wal_gate,
        build_order_intent_with_wal_gate,
    };
}

#[test]
fn facade_symbol_lists_stay_in_sync() {
    assert_facade_symbol_lists_in_sync();
}
