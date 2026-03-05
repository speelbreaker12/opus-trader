//! Public execution facade.
//!
//! This file defines the intended public surface for `soldier_core::execution`.
//! Symbols not re-exported here are implementation details.

// Execution engine
pub use super::engine::{
    ApprovedExecution, CancelExecutionInput, CloseExecutionInput, ExecutionBaseInput,
    ExecutionDecision, ExecutionEngine, ExecutionInput, ExecutionL2BookSnapshot, ExecutionL2Level,
    ExecutionOrderType, ExecutionPostOnlyInput, ExecutionPreflightInput, ExecutionRejection,
    ExecutionRuntime, ExecutionStep, HedgeExecutionInput, InventorySkewExecutionInput,
    LiquidityExecutionInput, NetEdgeExecutionInput, OpenExecutionInput, PricerExecutionInput,
    QuantizeExecutionInput, RuntimeStep,
};

// Chokepoint boundary
pub use super::build_order_intent::{GateStep, RecordedBeforeDispatchGate};

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
