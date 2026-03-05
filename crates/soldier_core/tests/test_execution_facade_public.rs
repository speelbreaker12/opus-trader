//! External-surface smoke tests for `soldier_core::execution`.
//! These must import through `soldier_core::...` (integration test context).

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use soldier_core::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use soldier_core::venue::{BotFeatureFlags, InstrumentKind, VenueCapabilities};

static TEMP_SOURCE_FILE_SEQ: AtomicU64 = AtomicU64::new(0);

#[allow(unused_imports)]
use soldier_core::execution::{
    ApprovedExecution, AtomicGroup, CancelExecutionInput, CloseExecutionInput, ExecutionBaseInput,
    ExecutionDecision, ExecutionEngine, ExecutionInput, ExecutionL2BookSnapshot, ExecutionL2Level,
    ExecutionOrderType, ExecutionPostOnlyInput, ExecutionPreflightInput, ExecutionRejection,
    ExecutionRuntime, ExecutionStep, GateRejectCodes, GateStep, GroupConfig, GroupError, GroupLock,
    GroupState, GroupStateTransition, HedgeExecutionInput, InventorySkewExecutionInput,
    LABEL_MAX_LEN, LabelError, LabelInput, LegResult, LiquidityExecutionInput,
    LockAcquisitionResult, NetEdgeExecutionInput, OpenExecutionInput, PersistedTransition,
    PricerExecutionInput, QuantizeExecutionInput, RecordedBeforeDispatchGate, RejectReasonCode,
    RuntimeStep, Side, Tlsm, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
    derive_gid12, derive_sid8, encode_label, reject_reason_registry,
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

#[derive(Default)]
struct ScopeScanState {
    depth: usize,
    in_block_comment: bool,
    in_string: bool,
    in_char: bool,
    raw_string_hashes: Option<usize>,
}

fn try_start_raw_string(bytes: &[u8], idx: usize) -> Option<(usize, usize)> {
    let mut cursor = idx;

    if bytes.get(cursor) == Some(&b'b') {
        cursor += 1;
        if bytes.get(cursor) != Some(&b'r') {
            return None;
        }
        cursor += 1;
    } else if bytes.get(cursor) == Some(&b'r') && bytes.get(cursor + 1) == Some(&b'b') {
        cursor += 2;
    } else if bytes.get(cursor) == Some(&b'r') {
        cursor += 1;
    } else {
        return None;
    }

    let mut hashes = 0usize;
    while bytes.get(cursor) == Some(&b'#') {
        hashes += 1;
        cursor += 1;
    }

    if bytes.get(cursor) == Some(&b'"') {
        Some((hashes, cursor - idx + 1))
    } else {
        None
    }
}

fn update_scope_depth(line: &str, state: &mut ScopeScanState) {
    let bytes = line.as_bytes();
    let mut idx = 0usize;

    while idx < bytes.len() {
        if let Some(hashes) = state.raw_string_hashes {
            if bytes[idx] == b'"'
                && idx + 1 + hashes <= bytes.len()
                && bytes[idx + 1..idx + 1 + hashes]
                    .iter()
                    .all(|ch| *ch == b'#')
            {
                state.raw_string_hashes = None;
                idx += 1 + hashes;
            } else {
                idx += 1;
            }
            continue;
        }

        if state.in_block_comment {
            if idx + 1 < bytes.len() && bytes[idx] == b'*' && bytes[idx + 1] == b'/' {
                state.in_block_comment = false;
                idx += 2;
            } else {
                idx += 1;
            }
            continue;
        }

        if state.in_string {
            if bytes[idx] == b'\\' && idx + 1 < bytes.len() {
                idx += 2;
                continue;
            }
            if bytes[idx] == b'"' {
                state.in_string = false;
            }
            idx += 1;
            continue;
        }

        if state.in_char {
            if bytes[idx] == b'\\' && idx + 1 < bytes.len() {
                idx += 2;
                continue;
            }
            if bytes[idx] == b'\'' {
                state.in_char = false;
            }
            idx += 1;
            continue;
        }

        if idx + 1 < bytes.len() && bytes[idx] == b'/' && bytes[idx + 1] == b'/' {
            break;
        }
        if idx + 1 < bytes.len() && bytes[idx] == b'/' && bytes[idx + 1] == b'*' {
            state.in_block_comment = true;
            idx += 2;
            continue;
        }

        if let Some((hashes, consumed)) = try_start_raw_string(bytes, idx) {
            state.raw_string_hashes = Some(hashes);
            idx += consumed;
            continue;
        }

        match bytes[idx] {
            b'"' => state.in_string = true,
            b'\'' => state.in_char = true,
            b'{' => state.depth += 1,
            b'}' => state.depth = state.depth.saturating_sub(1),
            _ => {}
        }
        idx += 1;
    }
}

fn extract_symbol_set(file_path: &Path, anchor: &str) -> BTreeSet<String> {
    let content = fs::read_to_string(file_path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", file_path.display()));

    let mut state = ScopeScanState::default();
    let mut lines = content.lines();

    while let Some(line) = lines.next() {
        let trimmed = line.trim_start();
        if state.depth == 0
            && !state.in_block_comment
            && state.raw_string_hashes.is_none()
            && !state.in_string
            && !state.in_char
            && trimmed.starts_with(anchor)
        {
            let mut block = String::new();
            let start = line
                .find(anchor)
                .unwrap_or_else(|| panic!("anchor `{anchor}` vanished in {}", file_path.display()))
                + anchor.len();
            block.push_str(&line[start..]);
            block.push('\n');

            while !block.contains("};") {
                let next = lines.next().unwrap_or_else(|| {
                    panic!(
                        "failed to find end of use block after anchor `{anchor}` in {}",
                        file_path.display()
                    )
                });
                block.push_str(next);
                block.push('\n');
            }

            let end = block.find("};").unwrap_or_else(|| {
                panic!(
                    "failed to find end of use block after anchor `{anchor}` in {}",
                    file_path.display()
                )
            });
            return parse_use_block_symbols(&block[..end]);
        }

        update_scope_depth(line, &mut state);
    }

    panic!(
        "failed to find top-level anchor `{anchor}` in {}",
        file_path.display()
    );
}

fn write_temp_source_file(contents: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock before UNIX_EPOCH")
        .as_nanos();
    let seq = TEMP_SOURCE_FILE_SEQ.fetch_add(1, Ordering::Relaxed);
    let path = std::env::temp_dir().join(format!(
        "facade_symbol_extract_{}_{}_{}.rs",
        std::process::id(),
        nanos,
        seq
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
    let _snapshot = ExecutionL2BookSnapshot {
        asks: vec![ExecutionL2Level {
            price: 100.0,
            qty: 1.0,
        }],
        bids: vec![ExecutionL2Level {
            price: 99.0,
            qty: 1.0,
        }],
        timestamp_ms: 1,
    };

    let registry = reject_reason_registry();
    assert!(
        !registry.is_empty(),
        "reject reason registry must not be empty"
    );
    assert!(
        reject_reason_registry_contains(RejectReasonCode::RecordedBeforeDispatchFailed),
        "expected RecordedBeforeDispatchFailed in facade reject reason registry"
    );

    let base = ExecutionBaseInput {
        risk_state: RiskState::Healthy,
        preflight: ExecutionPreflightInput {
            instrument_kind: InstrumentKind::Option,
            order_type: ExecutionOrderType::Limit,
            has_trigger: false,
            linked_order_type: None,
            linked_orders_allowed: false,
            post_only: None,
        },
        venue_capabilities: VenueCapabilities::default(),
        bot_feature_flags: BotFeatureFlags::default(),
        quantize: QuantizeExecutionInput {
            raw_qty: 1.0,
            raw_limit_price: 100.0,
            side: Side::Buy,
            tick_size: 0.1,
            amount_step: 0.1,
            min_amount: 0.1,
        },
        dispatch_consistency_passed: true,
        fee_snapshot: FeeCacheSnapshot {
            fee_rate: 0.0005,
            fee_model_cached_at_ts_ms: Some(1_000),
            now_ms: 1_001,
        },
        fee_config: FeeStalenessConfig::default(),
        expiry_guard: None,
    };

    let mut runtime = ExecutionRuntime::default();
    let decision = ExecutionEngine::new().decide(
        &ExecutionInput::Cancel(CancelExecutionInput { base }),
        &mut runtime,
    );
    assert!(matches!(decision, ExecutionDecision::Approved(_)));
}

#[test]
fn facade_symbol_lists_stay_in_sync() {
    assert_facade_symbol_lists_in_sync();
}

#[test]
fn extract_symbol_set_prefers_top_level_use_block_when_anchor_repeats() {
    let path = write_temp_source_file(
        r#"
use soldier_core::execution::{ExecutionEngine,};

fn nested() {
    use soldier_core::execution::{
        ExecutionEngine,
        ExecutionInput,
    };
}
"#,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = ["ExecutionEngine".to_string()].into_iter().collect();
    assert_eq!(symbols, expected);
}

#[test]
fn extract_symbol_set_ignores_inline_comments() {
    let path = write_temp_source_file(
        r#"
use soldier_core::execution::{
    ExecutionEngine, // engine entrypoint
    ExecutionInput, // execution request enum
};
"#,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = ["ExecutionEngine".to_string(), "ExecutionInput".to_string()]
        .into_iter()
        .collect();
    assert_eq!(symbols, expected);
}

#[test]
fn extract_symbol_set_ignores_anchor_text_inside_comments_and_strings() {
    let path = write_temp_source_file(
        r#"
use soldier_core::execution::{ExecutionEngine,};

// use soldier_core::execution::{ExecutionEngine, ExecutionInput,};
let _fixture = "use soldier_core::execution::{ExecutionEngine, ExecutionInput,};";
"#,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = ["ExecutionEngine".to_string()].into_iter().collect();
    assert_eq!(symbols, expected);
}

#[test]
fn extract_symbol_set_ignores_anchor_text_inside_block_comments() {
    let path = write_temp_source_file(
        r#"
/*
use soldier_core::execution::{
    ExecutionEngine,
    ExecutionInput,
};
*/
use soldier_core::execution::{ExecutionEngine,};
"#,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = ["ExecutionEngine".to_string()].into_iter().collect();
    assert_eq!(symbols, expected);
}

#[test]
fn extract_symbol_set_ignores_anchor_text_inside_multiline_raw_strings() {
    let path = write_temp_source_file(
        r##"
const FIXTURE: &str = r#"
use soldier_core::execution::{
    ExecutionEngine,
    ExecutionInput,
};
"#;
use soldier_core::execution::{ExecutionEngine,};
"##,
    );

    let symbols = extract_symbol_set(&path, "use soldier_core::execution::{");
    let _ = fs::remove_file(&path);

    let expected: BTreeSet<String> = ["ExecutionEngine".to_string()].into_iter().collect();
    assert_eq!(symbols, expected);
}
