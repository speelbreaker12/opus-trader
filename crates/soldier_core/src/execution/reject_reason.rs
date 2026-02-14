//! Reject reason registry for pre-dispatch intent rejections.

use super::build_order_intent::{ChokeRejectReason, GateStep};

/// Contract token for pre-dispatch rejection causes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RejectReasonCode {
    TooSmallAfterQuantization,
    InstrumentMetadataMissing,
    ChurnBreakerActive,
    LiquidityGateNoL2,
    EmergencyCloseNoPrice,
    ExpectedSlippageTooHigh,
    InsufficientDepthWithinBudget,
    NetEdgeTooLow,
    NetEdgeInputMissing,
    InventorySkew,
    InventorySkewDeltaLimitMissing,
    PendingExposureBudgetExceeded,
    GlobalExposureBudgetExceeded,
    ContractsAmountMismatch,
    MarginHeadroomRejectOpens,
    OrderTypeMarketForbidden,
    OrderTypeStopForbidden,
    LinkedOrderTypeForbidden,
    PostOnlyWouldCross,
    RiskIncreasingCancelReplaceForbidden,
    RateLimitBrownout,
    InstrumentExpiredOrDelisted,
    FeedbackLoopGuardActive,
    LabelTooLong,
}

/// Typed per-gate rejection codes produced by real gate evaluators.
///
/// The chokepoint only knows gate pass/fail booleans; this sidecar carries
/// concrete gate causes so reject-reason code translation does not rely on
/// brittle text matching.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct GateRejectCodes {
    pub preflight: Option<RejectReasonCode>,
    pub quantize: Option<RejectReasonCode>,
    pub liquidity_gate: Option<RejectReasonCode>,
    pub net_edge_gate: Option<RejectReasonCode>,
    pub pricer: Option<RejectReasonCode>,
}

impl RejectReasonCode {
    pub fn as_str(self) -> &'static str {
        match self {
            RejectReasonCode::TooSmallAfterQuantization => "TooSmallAfterQuantization",
            RejectReasonCode::InstrumentMetadataMissing => "InstrumentMetadataMissing",
            RejectReasonCode::ChurnBreakerActive => "ChurnBreakerActive",
            RejectReasonCode::LiquidityGateNoL2 => "LiquidityGateNoL2",
            RejectReasonCode::EmergencyCloseNoPrice => "EmergencyCloseNoPrice",
            RejectReasonCode::ExpectedSlippageTooHigh => "ExpectedSlippageTooHigh",
            RejectReasonCode::InsufficientDepthWithinBudget => "InsufficientDepthWithinBudget",
            RejectReasonCode::NetEdgeTooLow => "NetEdgeTooLow",
            RejectReasonCode::NetEdgeInputMissing => "NetEdgeInputMissing",
            RejectReasonCode::InventorySkew => "InventorySkew",
            RejectReasonCode::InventorySkewDeltaLimitMissing => "InventorySkewDeltaLimitMissing",
            RejectReasonCode::PendingExposureBudgetExceeded => "PendingExposureBudgetExceeded",
            RejectReasonCode::GlobalExposureBudgetExceeded => "GlobalExposureBudgetExceeded",
            RejectReasonCode::ContractsAmountMismatch => "ContractsAmountMismatch",
            RejectReasonCode::MarginHeadroomRejectOpens => "MarginHeadroomRejectOpens",
            RejectReasonCode::OrderTypeMarketForbidden => "OrderTypeMarketForbidden",
            RejectReasonCode::OrderTypeStopForbidden => "OrderTypeStopForbidden",
            RejectReasonCode::LinkedOrderTypeForbidden => "LinkedOrderTypeForbidden",
            RejectReasonCode::PostOnlyWouldCross => "PostOnlyWouldCross",
            RejectReasonCode::RiskIncreasingCancelReplaceForbidden => {
                "RiskIncreasingCancelReplaceForbidden"
            }
            RejectReasonCode::RateLimitBrownout => "RateLimitBrownout",
            RejectReasonCode::InstrumentExpiredOrDelisted => "InstrumentExpiredOrDelisted",
            RejectReasonCode::FeedbackLoopGuardActive => "FeedbackLoopGuardActive",
            RejectReasonCode::LabelTooLong => "LabelTooLong",
        }
    }
}

const REGISTRY: &[RejectReasonCode] = &[
    RejectReasonCode::TooSmallAfterQuantization,
    RejectReasonCode::InstrumentMetadataMissing,
    RejectReasonCode::ChurnBreakerActive,
    RejectReasonCode::LiquidityGateNoL2,
    RejectReasonCode::EmergencyCloseNoPrice,
    RejectReasonCode::ExpectedSlippageTooHigh,
    RejectReasonCode::InsufficientDepthWithinBudget,
    RejectReasonCode::NetEdgeTooLow,
    RejectReasonCode::NetEdgeInputMissing,
    RejectReasonCode::InventorySkew,
    RejectReasonCode::InventorySkewDeltaLimitMissing,
    RejectReasonCode::PendingExposureBudgetExceeded,
    RejectReasonCode::GlobalExposureBudgetExceeded,
    RejectReasonCode::ContractsAmountMismatch,
    RejectReasonCode::MarginHeadroomRejectOpens,
    RejectReasonCode::OrderTypeMarketForbidden,
    RejectReasonCode::OrderTypeStopForbidden,
    RejectReasonCode::LinkedOrderTypeForbidden,
    RejectReasonCode::PostOnlyWouldCross,
    RejectReasonCode::RiskIncreasingCancelReplaceForbidden,
    RejectReasonCode::RateLimitBrownout,
    RejectReasonCode::InstrumentExpiredOrDelisted,
    RejectReasonCode::FeedbackLoopGuardActive,
    RejectReasonCode::LabelTooLong,
];

pub fn reject_reason_registry() -> &'static [RejectReasonCode] {
    REGISTRY
}

pub fn reject_reason_registry_contains(code: RejectReasonCode) -> bool {
    REGISTRY.contains(&code)
}

/// Map chokepoint rejection output to a contract registry token.
pub fn reject_reason_from_chokepoint(
    reason: &ChokeRejectReason,
    gate_reject_codes: &GateRejectCodes,
) -> RejectReasonCode {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => RejectReasonCode::MarginHeadroomRejectOpens,
        ChokeRejectReason::GateRejected {
            gate: GateStep::Preflight,
            ..
        } => gate_reject_codes
            .preflight
            .unwrap_or(RejectReasonCode::OrderTypeStopForbidden),
        ChokeRejectReason::GateRejected {
            gate: GateStep::Quantize,
            ..
        } => gate_reject_codes
            .quantize
            .unwrap_or(RejectReasonCode::InstrumentMetadataMissing),
        ChokeRejectReason::GateRejected {
            gate: GateStep::DispatchConsistency,
            ..
        } => RejectReasonCode::ContractsAmountMismatch,
        ChokeRejectReason::GateRejected {
            gate: GateStep::FeeCacheCheck,
            ..
        } => RejectReasonCode::RateLimitBrownout,
        ChokeRejectReason::GateRejected {
            gate: GateStep::LiquidityGate,
            ..
        } => gate_reject_codes
            .liquidity_gate
            .unwrap_or(RejectReasonCode::ExpectedSlippageTooHigh),
        ChokeRejectReason::GateRejected {
            gate: GateStep::NetEdgeGate,
            ..
        } => gate_reject_codes
            .net_edge_gate
            .unwrap_or(RejectReasonCode::NetEdgeTooLow),
        ChokeRejectReason::GateRejected {
            gate: GateStep::Pricer,
            ..
        } => gate_reject_codes
            .pricer
            .unwrap_or(RejectReasonCode::NetEdgeTooLow),
        ChokeRejectReason::GateRejected {
            gate: GateStep::RecordedBeforeDispatch,
            ..
        } => RejectReasonCode::RiskIncreasingCancelReplaceForbidden,
        ChokeRejectReason::GateRejected {
            gate: GateStep::DispatchAuth,
            ..
        } => RejectReasonCode::MarginHeadroomRejectOpens,
    }
}
