//! Compile-time proof that intended facade symbols are reachable via
//! `soldier_core::execution::{...}`.

#[allow(unused_imports)]
use crate::execution::{
    ApprovedExecution, AtomicGroup, CancelExecutionInput, CloseExecutionInput,
    EmergencyClosePriceInput, EmergencyClosePriceSelection, EmergencyClosePriceSource,
    EmergencyTopOfBookSnapshot, EmergencyVenueBand, ExecutionBaseInput, ExecutionDecision,
    ExecutionEngine, ExecutionInput, ExecutionL2BookSnapshot, ExecutionL2Level, ExecutionOrderType,
    ExecutionPostOnlyInput, ExecutionPreflightInput, ExecutionRejection, ExecutionRuntime,
    ExecutionStep, GateRejectCodes, GateStep, GroupConfig, GroupError, GroupLock, GroupState,
    GroupStateTransition, HedgeExecutionInput, InventorySkewExecutionInput, LABEL_MAX_LEN,
    LabelError, LabelInput, LegResult, LiquidityExecutionInput, LockAcquisitionResult,
    NetEdgeExecutionInput, OpenExecutionInput, PersistedTransition, PricerExecutionInput,
    QuantizeExecutionInput, RecordedBeforeDispatchGate, RejectReasonCode, RuntimeStep, Side, Tlsm,
    TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult, derive_gid12, derive_sid8,
    encode_label, reject_reason_registry, reject_reason_registry_contains,
    select_emergency_close_best_price, try_acquire_group_lock,
};
use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use crate::venue::{BotFeatureFlags, InstrumentKind, VenueCapabilities};

#[test]
fn facade_symbols_reachable_via_execution_facade() {
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
            fee_model_cached_at_ts_ms: Some(1000),
            now_ms: 1001,
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
