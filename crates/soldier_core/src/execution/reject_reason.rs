//! Reject reason registry for pre-dispatch intent rejections.

use super::build_order_intent::{ChokeRejectReason, GateStep};

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
    NetEdgeTooLow,
    NetEdgeInputMissing,
    PricerInputMissing,
    PricerInputInvalid,
    GateCascadeSkip,
    InsufficientDepthWithinBudget,
    FeeCacheStale,
    RecordedBeforeDispatchFailed,
    AssemblyFailed,
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
            RejectReasonCode::NetEdgeTooLow => "NetEdgeTooLow",
            RejectReasonCode::NetEdgeInputMissing => "NetEdgeInputMissing",
            RejectReasonCode::PricerInputMissing => "PricerInputMissing",
            RejectReasonCode::PricerInputInvalid => "PricerInputInvalid",
            RejectReasonCode::GateCascadeSkip => "GateCascadeSkip",
            RejectReasonCode::InsufficientDepthWithinBudget => "InsufficientDepthWithinBudget",
            RejectReasonCode::FeeCacheStale => "FeeCacheStale",
            RejectReasonCode::RecordedBeforeDispatchFailed => "RecordedBeforeDispatchFailed",
            RejectReasonCode::AssemblyFailed => "AssemblyFailed",
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
    RejectReasonCode::PricerInputMissing,
    RejectReasonCode::PricerInputInvalid,
    RejectReasonCode::GateCascadeSkip,
    RejectReasonCode::InsufficientDepthWithinBudget,
    RejectReasonCode::FeeCacheStale,
    RejectReasonCode::RecordedBeforeDispatchFailed,
    RejectReasonCode::AssemblyFailed,
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
///
/// Fallback codes (`.unwrap_or(...)`) are safety nets for direct callers that
/// bypass `evaluate_intent_pipeline`. The production pipeline always populates
/// `GateRejectCodes` from typed gate results, making the fallbacks dead code
/// in the normal execution path.
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
        } => gate_reject_codes
            .fee_cache
            .unwrap_or(RejectReasonCode::FeeCacheStale),
        ChokeRejectReason::GateRejected {
            gate: GateStep::ExpiryGuard,
            ..
        } => gate_reject_codes
            .expiry_guard
            .unwrap_or(RejectReasonCode::InstrumentExpiredOrDelisted),
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
            .unwrap_or(RejectReasonCode::EmergencyCloseNoPrice),
        ChokeRejectReason::GateRejected {
            gate: GateStep::RecordedBeforeDispatch,
            ..
        } => gate_reject_codes
            .recorded_before_dispatch
            .unwrap_or(RejectReasonCode::RecordedBeforeDispatchFailed),
        ChokeRejectReason::GateRejected {
            gate: GateStep::DispatchAuth,
            ..
        } => RejectReasonCode::MarginHeadroomRejectOpens,
        ChokeRejectReason::AssemblyFailed => RejectReasonCode::AssemblyFailed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use std::collections::BTreeSet;

    #[derive(Debug, Deserialize)]
    struct Manifest {
        registries: Registries,
    }

    #[derive(Debug, Deserialize)]
    struct Registries {
        #[serde(rename = "RejectReasonCode")]
        reject_reason_code: RejectReasonCodeRegistry,
    }

    #[derive(Debug, Deserialize)]
    struct RejectReasonCodeRegistry {
        values: Vec<String>,
    }

    fn manifest_reject_reason_codes() -> Vec<String> {
        let manifest: Manifest = serde_json::from_str(include_str!(
            "../../../../specs/status/status_reason_registries_manifest.json"
        ))
        .expect("status reason manifest must parse");

        manifest.registries.reject_reason_code.values
    }

    #[test]
    fn manifest_reject_reason_codes_match_rust_registry() {
        let manifest_codes = manifest_reject_reason_codes();
        let rust_codes: Vec<String> = reject_reason_registry()
            .iter()
            .map(|code| code.as_str().to_owned())
            .collect();

        assert_eq!(
            rust_codes, manifest_codes,
            "Rust RejectReasonCode registry drifted from specs/status/status_reason_registries_manifest.json",
        );
    }

    #[test]
    fn manifest_reject_reason_codes_are_unique() {
        let manifest_codes = manifest_reject_reason_codes();
        let unique: BTreeSet<_> = manifest_codes.iter().cloned().collect();

        assert_eq!(
            unique.len(),
            manifest_codes.len(),
            "Manifest RejectReasonCode values must be unique",
        );
    }

    #[test]
    fn manifest_lookup_uses_pascal_case_not_serde_wire_format() {
        let code = RejectReasonCode::NetEdgeTooLow;

        assert_eq!(code.as_str(), "NetEdgeTooLow");
        assert_eq!(
            serde_json::to_string(&code).expect("reject reason code must serialize"),
            "\"NET_EDGE_TOO_LOW\"",
        );
        assert_ne!(code.as_str(), "NET_EDGE_TOO_LOW");
    }
}
