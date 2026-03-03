//! Public execution facade.
//!
//! This file defines the intended public surface for `soldier_core::execution`.
//! Symbols not re-exported here are implementation details.

// Execution engine (11)
pub use super::engine::{
    CancelOnlyExecutionInput, CloseExecutionInput, ExecutionDecision, ExecutionEngine,
    ExecutionInput, ExecutionRuntime, HedgeExecutionInput, OpenExecutionInput, OpenMetadata,
    open_runtime_to_decision, pipeline_result_to_decision,
};

// Chokepoint boundary (10)
pub use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    RecordedBeforeDispatchGate, build_gate_results, build_order_intent_with_optional_wal_gate,
    build_order_intent_with_wal_gate,
};

// Reject reason (5)
pub use super::reject_reason::{
    GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint, reject_reason_registry,
    reject_reason_registry_contains,
};

// Domain primitives (2)
pub use super::domain_model::{
    AmountSemantics, CanonicalSizeKind, DomainModelError, InstrumentFamily, InstrumentMeta,
    IntentId, NormalizedOrderSize, OrderSizeInput, QuantizedPriceTicks, QuantizedQtySteps,
    normalize_order_size,
};
pub use super::order_size::OrderSize;
pub use super::quantize::Side;

// Label (8)
pub use super::label::{
    EXCHANGE_LABEL_PREFIX, HUMAN_LABEL_PREFIX, LABEL_MAX_LEN, LabelError, LabelInput, derive_gid12,
    derive_sid8, encode_label,
};

// Group atomicity (9)
pub use super::group::{
    AtomicGroup, GroupConfig, GroupError, GroupLock, GroupState, GroupStateTransition, LegResult,
    LockAcquisitionResult, try_acquire_group_lock,
};

// TLSM (8)
pub use super::tlsm::{
    OooCategory, PersistedTransition, Tlsm, TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink,
    TransitionResult,
};
