//! External-surface smoke tests for `soldier_core::execution`.
//! These must import through `soldier_core::...` (integration test context).

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use soldier_core::risk::RiskState;

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

fn parse_use_block_symbols(block: &str) -> BTreeSet<String> {
    let without_line_comments = block
        .lines()
        .map(|line| line.split("//").next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n");

    without_line_comments
        .split(',')
        .map(str::trim)
        .filter(|symbol| !symbol.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn extract_symbol_set(file_path: &Path, anchor: &str) -> BTreeSet<String> {
    let content = fs::read_to_string(file_path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", file_path.display()));

    let mut parsed_sets = Vec::new();
    let mut search_offset = 0usize;

    while let Some(relative_start) = content[search_offset..].find(anchor) {
        let start = search_offset + relative_start + anchor.len();
        let rest = &content[start..];
        if let Some(end) = rest.find("};") {
            parsed_sets.push(parse_use_block_symbols(&rest[..end]));
            search_offset = start + end + 2;
        } else {
            // Ignore non-block occurrences (for example, anchor text in string literals).
            search_offset = start + 1;
        }
    }

    parsed_sets
        .into_iter()
        .max_by_key(|set| set.len())
        .unwrap_or_else(|| {
            panic!(
                "failed to find anchor `{anchor}` in {}",
                file_path.display()
            )
        })
}

fn write_temp_source_file(contents: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock before UNIX_EPOCH")
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "facade_symbol_extract_{}_{}.rs",
        std::process::id(),
        nanos
    ));
    fs::write(&path, contents)
        .unwrap_or_else(|err| panic!("failed to write {}: {err}", path.display()));
    path
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

    struct StubWalGate;

    impl RecordedBeforeDispatchGate for StubWalGate {
        fn record_before_dispatch(&mut self) -> Result<(), String> {
            Ok(())
        }
    }

    let mut metrics = ChokeMetrics::new();
    let gates = build_gate_results(
        true,  // preflight_passed
        true,  // quantize_passed
        true,  // dispatch_consistency_passed
        true,  // fee_cache_passed
        true,  // expiry_guard_passed
        true,  // liquidity_gate_passed
        true,  // net_edge_passed
        true,  // pricer_passed
        false, // wal_recorded (ignored by explicit wal gate path below)
        None,  // requested_qty
        None,  // max_dispatch_qty
    );
    let mut wal_gate = StubWalGate;

    let with_wal_gate = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );
    assert!(
        matches!(with_wal_gate, ChokeResult::Approved { .. }),
        "explicit WAL gate path should approve when gate recording succeeds"
    );

    let missing_wal_gate = build_order_intent_with_optional_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        None,
    );
    assert!(
        matches!(
            missing_wal_gate,
            ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: GateStep::RecordedBeforeDispatch,
                    ..
                },
                ..
            }
        ),
        "optional WAL path should fail-closed when adapter is omitted for OPEN intents"
    );
}

#[test]
fn facade_symbol_lists_stay_in_sync() {
    assert_facade_symbol_lists_in_sync();
}

#[test]
fn extract_symbol_set_prefers_largest_use_block_when_anchor_repeats() {
    let path = write_temp_source_file(
        r#"
use soldier_core::execution::{build_gate_results,};

fn nested() {
    use soldier_core::execution::{
        build_gate_results,
        build_order_intent_with_wal_gate,
    };
}
"#,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = [
        "build_gate_results".to_string(),
        "build_order_intent_with_wal_gate".to_string(),
    ]
    .into_iter()
    .collect();
    assert_eq!(symbols, expected);
}

#[test]
fn extract_symbol_set_ignores_inline_comments() {
    let path = write_temp_source_file(
        r#"
use soldier_core::execution::{
    build_gate_results, // shared in both contract + external smoke tests
    build_order_intent_with_wal_gate, // compile-only reachability check
};
"#,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = [
        "build_gate_results".to_string(),
        "build_order_intent_with_wal_gate".to_string(),
    ]
    .into_iter()
    .collect();
    assert_eq!(symbols, expected);
}
