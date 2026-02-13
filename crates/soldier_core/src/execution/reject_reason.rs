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

impl RejectReasonCode {
    pub fn as_str(self) -> &'static str {
        match self {
            RejectReasonCode::TooSmallAfterQuantization => "TooSmallAfterQuantization",
            RejectReasonCode::InstrumentMetadataMissing => "InstrumentMetadataMissing",
            RejectReasonCode::ChurnBreakerActive => "ChurnBreakerActive",
            RejectReasonCode::LiquidityGateNoL2 => "LiquidityGateNoL2",
            RejectReasonCode::EmergencyCloseNoPrice => "EmergencyCloseNoPrice",
            RejectReasonCode::ExpectedSlippageTooHigh => "ExpectedSlippageTooHigh",
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
pub fn reject_reason_from_chokepoint(reason: &ChokeRejectReason) -> RejectReasonCode {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => RejectReasonCode::MarginHeadroomRejectOpens,
        ChokeRejectReason::GateRejected {
            gate: GateStep::Preflight,
            reason,
        } => {
            if reason.contains("linked") {
                RejectReasonCode::LinkedOrderTypeForbidden
            } else if reason.contains("market") {
                RejectReasonCode::OrderTypeMarketForbidden
            } else {
                RejectReasonCode::OrderTypeStopForbidden
            }
        }
        ChokeRejectReason::GateRejected {
            gate: GateStep::Quantize,
            reason,
        } => {
            if reason.contains("too small") {
                RejectReasonCode::TooSmallAfterQuantization
            } else {
                RejectReasonCode::InstrumentMetadataMissing
            }
        }
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
            reason,
        } => {
            if reason.contains("no l2") {
                RejectReasonCode::LiquidityGateNoL2
            } else {
                RejectReasonCode::ExpectedSlippageTooHigh
            }
        }
        ChokeRejectReason::GateRejected {
            gate: GateStep::NetEdgeGate,
            reason,
        } => {
            if reason.contains("missing") {
                RejectReasonCode::NetEdgeInputMissing
            } else {
                RejectReasonCode::NetEdgeTooLow
            }
        }
        ChokeRejectReason::GateRejected {
            gate: GateStep::Pricer,
            ..
        } => RejectReasonCode::NetEdgeTooLow,
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
