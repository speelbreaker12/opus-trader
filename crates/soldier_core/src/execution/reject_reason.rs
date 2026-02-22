//! Reject reason registry for pre-dispatch intent rejections.

use super::build_order_intent::{ChokeRejectReason, ChokeResult, GateStep};

/// Contract token for pre-dispatch rejection causes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RejectReasonCode {
    TooSmallAfterQuantization,
    InstrumentMetadataMissing,
    ChurnBreakerActive,
    LiquidityGateNoL2,
    EmergencyCloseNoPrice,
    ExpectedSlippageTooHigh,
    InsufficientDepthWithinBudget,
    FeeCacheStale,
    RecordedBeforeDispatchFailed,
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
    pub fee_cache: Option<RejectReasonCode>,
    pub expiry_guard: Option<RejectReasonCode>,
    pub liquidity_gate: Option<RejectReasonCode>,
    pub net_edge_gate: Option<RejectReasonCode>,
    pub recorded_before_dispatch: Option<RejectReasonCode>,
    pub pricer: Option<RejectReasonCode>,
}

impl RejectReasonCode {
    /// PascalCase variant name for log messages and registry lookups.
    ///
    /// NOTE: serde serializes as SCREAMING_SNAKE_CASE (`NET_EDGE_TOO_LOW`), while
    /// `as_str()` returns PascalCase (`NetEdgeTooLow`). These are intentionally
    /// different formats for different audiences. `as_str()` is used only in tests
    /// and internal diagnostics; serde is the sole wire-format serialization path.
    pub fn as_str(self) -> &'static str {
        match self {
            RejectReasonCode::TooSmallAfterQuantization => "TooSmallAfterQuantization",
            RejectReasonCode::InstrumentMetadataMissing => "InstrumentMetadataMissing",
            RejectReasonCode::ChurnBreakerActive => "ChurnBreakerActive",
            RejectReasonCode::LiquidityGateNoL2 => "LiquidityGateNoL2",
            RejectReasonCode::EmergencyCloseNoPrice => "EmergencyCloseNoPrice",
            RejectReasonCode::ExpectedSlippageTooHigh => "ExpectedSlippageTooHigh",
            RejectReasonCode::InsufficientDepthWithinBudget => "InsufficientDepthWithinBudget",
            RejectReasonCode::FeeCacheStale => "FeeCacheStale",
            RejectReasonCode::RecordedBeforeDispatchFailed => "RecordedBeforeDispatchFailed",
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
    RejectReasonCode::FeeCacheStale,
    RejectReasonCode::RecordedBeforeDispatchFailed,
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

/// Resolve typed gate reject code, warning on fallback (P14).
fn resolve_or_warn(
    gate_name: &str,
    typed: Option<RejectReasonCode>,
    fallback: RejectReasonCode,
) -> RejectReasonCode {
    match typed {
        Some(code) => code,
        None => {
            tracing::warn!(
                gate = gate_name,
                fallback = fallback.as_str(),
                "reject_reason_from_chokepoint: gate reject code missing, using fallback"
            );
            fallback
        }
    }
}

/// Map chokepoint rejection output to a contract registry token.
///
/// Fallback codes (via `resolve_or_warn`) are safety nets for direct callers
/// that bypass `evaluate_intent_pipeline`. The production pipeline always
/// populates `GateRejectCodes` from typed gate results, making the fallbacks
/// dead code in the normal execution path.
pub fn reject_reason_from_chokepoint(
    reason: &ChokeRejectReason,
    gate_reject_codes: &GateRejectCodes,
) -> RejectReasonCode {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => RejectReasonCode::MarginHeadroomRejectOpens,
        ChokeRejectReason::GateRejected {
            gate: GateStep::Preflight,
            ..
        } => resolve_or_warn(
            "Preflight",
            gate_reject_codes.preflight,
            RejectReasonCode::OrderTypeStopForbidden,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::Quantize,
            ..
        } => resolve_or_warn(
            "Quantize",
            gate_reject_codes.quantize,
            RejectReasonCode::InstrumentMetadataMissing,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::DispatchConsistency,
            ..
        } => RejectReasonCode::ContractsAmountMismatch,
        ChokeRejectReason::GateRejected {
            gate: GateStep::FeeCacheCheck,
            ..
        } => resolve_or_warn(
            "FeeCacheCheck",
            gate_reject_codes.fee_cache,
            RejectReasonCode::FeeCacheStale,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::ExpiryGuard,
            ..
        } => resolve_or_warn(
            "ExpiryGuard",
            gate_reject_codes.expiry_guard,
            RejectReasonCode::InstrumentExpiredOrDelisted,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::LiquidityGate,
            ..
        } => resolve_or_warn(
            "LiquidityGate",
            gate_reject_codes.liquidity_gate,
            RejectReasonCode::ExpectedSlippageTooHigh,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::NetEdgeGate,
            ..
        } => resolve_or_warn(
            "NetEdgeGate",
            gate_reject_codes.net_edge_gate,
            RejectReasonCode::NetEdgeTooLow,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::Pricer,
            ..
        } => resolve_or_warn(
            "Pricer",
            gate_reject_codes.pricer,
            RejectReasonCode::EmergencyCloseNoPrice,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::RecordedBeforeDispatch,
            ..
        } => resolve_or_warn(
            "RecordedBeforeDispatch",
            gate_reject_codes.recorded_before_dispatch,
            RejectReasonCode::RecordedBeforeDispatchFailed,
        ),
        ChokeRejectReason::GateRejected {
            gate: GateStep::DispatchAuth,
            ..
        } => RejectReasonCode::MarginHeadroomRejectOpens,
    }
}

/// Extract reject reason code from a chokepoint result.
///
/// Returns `None` for approved decisions, or the mapped `RejectReasonCode`
/// for rejections. This helper avoids mentioning `ChokeResult::Approved`
/// in caller modules (preserved by the architectural guard in
/// `test_dispatch_chokepoint_no_bypass_approved`).
pub fn extract_reject_reason_code(
    result: &ChokeResult,
    gate_reject_codes: &GateRejectCodes,
) -> Option<RejectReasonCode> {
    match result {
        ChokeResult::Rejected { reason, .. } => {
            Some(reject_reason_from_chokepoint(reason, gate_reject_codes))
        }
        // Wildcard intentional: ChokeResult::Approved must not be named outside
        // build_order_intent.rs (enforced by test_dispatch_chokepoint_no_bypass_approved).
        _ => None,
    }
}
