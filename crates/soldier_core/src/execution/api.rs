//! Public execution facade.
//!
//! This file defines the intended public surface for `soldier_core::execution`.
//! Symbols not re-exported here remain implementation details.
//!
//! **Public:** execution engine + inputs, side, gate steps, reject reason
//! codes, group atomicity, TLSM + transitions, label encoding,
//! emergency-close selection, recorded-before-dispatch gate.
//!
//! **Private:** `base_gates`, `build_order_intent`, `dispatch_map`,
//! `domain_model`, `emergency_close`, `engine`, `gate`, `gate_outcome`,
//! `gates`, `group`, `intent_assembly`, `inventory_skew`, `label`,
//! `open_runtime`, `order_size`, `pipeline`, `post_only_guard`, `preflight`,
//! `pricer`, `quantize`, `reject_reason`, `routing`, `tlsm`, `wal_gate`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public execution surface.

// Execution engine
pub use super::engine::{
    ApprovedExecution, CancelExecutionInput, CloseExecutionInput, ExecutionBaseInput,
    ExecutionDecision, ExecutionEngine, ExecutionInput, ExecutionL2BookSnapshot, ExecutionL2Level,
    ExecutionOrderType, ExecutionPostOnlyInput, ExecutionPreflightInput, ExecutionRejection,
    ExecutionRuntime, ExecutionStep, HedgeExecutionInput, InventorySkewExecutionInput,
    LiquidityExecutionInput, NetEdgeExecutionInput, OpenExecutionInput, PricerExecutionInput,
    QuantizeExecutionInput, RuntimeStep,
};

// Emergency-close fallback selector
pub use super::emergency_close::{
    EmergencyClosePriceInput, EmergencyClosePriceSelection, EmergencyClosePriceSource,
    EmergencyTopOfBookSnapshot, EmergencyVenueBand, select_emergency_close_best_price,
};

// Chokepoint boundary
pub use super::build_order_intent::GateStep;
pub use super::wal_gate::RecordedBeforeDispatchGate;

// Reject reason
pub use super::reject_reason::{
    GateRejectCodes, RejectReasonCode, reject_reason_registry, reject_reason_registry_contains,
};

// Domain primitives
pub use super::quantize::Side;

// Label
pub use super::label::{
    LABEL_MAX_LEN, LabelError, LabelInput, derive_gid12, derive_sid8, encode_label,
};

// Group atomicity
pub use super::group::{
    AtomicGroup, GroupConfig, GroupError, GroupLock, GroupState, GroupStateTransition, LegResult,
    LockAcquisitionResult, try_acquire_group_lock,
};

// TLSM
pub use super::tlsm::{
    PersistedTransition, Tlsm, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
};
