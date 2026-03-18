//! Pipeline-level gate decision type.
//!
//! GateOutcome is **decision-only**. Gate-specific operational data
//! (allowed_qty, limit_price, wap, slippage_bps, etc.) MUST remain
//! in gate result types. Do NOT add generics, Box<dyn Any>, or
//! metadata fields to this type.

use super::build_order_intent::GateStep;
use super::gate::{LiquidityGateDecision, LiquidityGateRejectReason, LiquidityGateResult};
use super::gates::{NetEdgeRejectReason, NetEdgeResult};
use super::preflight::{PreflightReject, PreflightResult};
use super::pricer::{PricerRejectReason, PricerResult};
use super::quantize::QuantizeError;
use super::reject_reason::RejectReasonCode;
use crate::risk::{FeeEvaluation, RiskState};
use crate::venue::{ExpiryGuardResult, LifecycleTerminalReason};

/// Pipeline-level decision from a single gate evaluation.
///
/// Eliminates illegal representational states:
/// - Allow cannot carry a reason code
/// - Reject always carries a reason code
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GateOutcome {
    /// Gate allows the intent to proceed.
    Allow { gate: GateStep },
    /// Gate rejects the intent.
    Reject {
        gate: GateStep,
        reason_code: RejectReasonCode,
    },
}

#[deny(clippy::wildcard_enum_match_arm)]
impl GateOutcome {
    /// Convert to the legacy `(bool, Option<RejectReasonCode>)` representation
    /// used by `GateResults` and `GateRejectCodes`.
    pub fn to_legacy(&self) -> (bool, Option<RejectReasonCode>) {
        match self {
            GateOutcome::Allow { .. } => (true, None),
            GateOutcome::Reject { reason_code, .. } => (false, Some(*reason_code)),
        }
    }

    /// Returns `true` if the gate allowed the intent.
    pub fn is_allowed(&self) -> bool {
        matches!(self, GateOutcome::Allow { .. })
    }

    /// Convert a `PreflightResult` to a `GateOutcome`.
    ///
    /// Exhaustive match — compiler forces update when `PreflightReject` adds a variant.
    pub fn from_preflight(gate: GateStep, result: &PreflightResult) -> Self {
        match result {
            PreflightResult::Allowed => GateOutcome::Allow { gate },
            PreflightResult::Rejected(reason) => {
                let code = match reason {
                    PreflightReject::OrderTypeMarketForbidden => {
                        RejectReasonCode::OrderTypeMarketForbidden
                    }
                    PreflightReject::OrderTypeStopForbidden => {
                        RejectReasonCode::OrderTypeStopForbidden
                    }
                    PreflightReject::LinkedOrderTypeForbidden => {
                        RejectReasonCode::LinkedOrderTypeForbidden
                    }
                    PreflightReject::PostOnlyWouldCross => RejectReasonCode::PostOnlyWouldCross,
                };
                GateOutcome::Reject {
                    gate,
                    reason_code: code,
                }
            }
        }
    }

    /// Convert a `Result<T, QuantizeError>` to a `GateOutcome`.
    ///
    /// Generic over `T` since only the error variant determines the outcome.
    /// Exhaustive match — compiler forces update when `QuantizeError` adds a variant.
    pub fn from_quantize<T>(gate: GateStep, result: &Result<T, QuantizeError>) -> Self {
        match result {
            Ok(_) => GateOutcome::Allow { gate },
            Err(reason) => {
                // NOTE: InvalidInput maps to InstrumentMetadataMissing for backward
                // compatibility with the original pipeline.rs inline logic. Phase 2
                // debt: introduce a dedicated RejectReasonCode::InvalidInput variant.
                let code = match reason {
                    QuantizeError::TooSmallAfterQuantization { .. } => {
                        RejectReasonCode::TooSmallAfterQuantization
                    }
                    QuantizeError::InstrumentMetadataMissing { .. }
                    | QuantizeError::InvalidInput { .. } => {
                        RejectReasonCode::InstrumentMetadataMissing
                    }
                };
                GateOutcome::Reject {
                    gate,
                    reason_code: code,
                }
            }
        }
    }

    /// Convert a `FeeEvaluation` to a `GateOutcome`.
    ///
    /// Fee evaluation passes if `risk_state` is `Healthy` (Fresh or SoftStale);
    /// non-Healthy rejects with `FeeCacheStale`.
    /// Matches the pipeline's existing `fee_eval.risk_state == RiskState::Healthy` check.
    pub fn from_fee_eval(gate: GateStep, eval: &FeeEvaluation) -> Self {
        if eval.risk_state == RiskState::Healthy {
            GateOutcome::Allow { gate }
        } else {
            GateOutcome::Reject {
                gate,
                reason_code: RejectReasonCode::FeeCacheStale,
            }
        }
    }

    /// Convert an `ExpiryGuardResult` to a `GateOutcome`.
    ///
    /// Exhaustive match — compiler forces update when `LifecycleTerminalReason` adds a variant.
    pub fn from_expiry_guard(gate: GateStep, result: &ExpiryGuardResult) -> Self {
        match result {
            ExpiryGuardResult::Allowed => GateOutcome::Allow { gate },
            ExpiryGuardResult::Rejected(reason) => {
                let code = match reason {
                    LifecycleTerminalReason::InstrumentExpiredOrDelisted => {
                        RejectReasonCode::InstrumentExpiredOrDelisted
                    }
                };
                GateOutcome::Reject {
                    gate,
                    reason_code: code,
                }
            }
        }
    }

    /// Convert a `LiquidityGateResult` to a `GateOutcome`.
    ///
    /// Exhaustive match — compiler forces update when `LiquidityGateRejectReason` adds a variant.
    pub fn from_liquidity(gate: GateStep, result: &LiquidityGateResult) -> Self {
        match &result.decision {
            LiquidityGateDecision::Allowed => GateOutcome::Allow { gate },
            LiquidityGateDecision::Rejected { reason } => {
                let code = match reason {
                    LiquidityGateRejectReason::LiquidityGateNoL2 => {
                        RejectReasonCode::LiquidityGateNoL2
                    }
                    LiquidityGateRejectReason::ExpectedSlippageTooHigh => {
                        RejectReasonCode::ExpectedSlippageTooHigh
                    }
                    LiquidityGateRejectReason::InsufficientDepthWithinBudget => {
                        RejectReasonCode::InsufficientDepthWithinBudget
                    }
                };
                GateOutcome::Reject {
                    gate,
                    reason_code: code,
                }
            }
        }
    }

    /// Convert a `NetEdgeResult` to a `GateOutcome`.
    ///
    /// Exhaustive match — compiler forces update when `NetEdgeRejectReason` adds a variant.
    pub fn from_net_edge(gate: GateStep, result: &NetEdgeResult) -> Self {
        match result {
            NetEdgeResult::Allowed { .. } => GateOutcome::Allow { gate },
            NetEdgeResult::Rejected { reason, .. } => {
                let code = match reason {
                    NetEdgeRejectReason::NetEdgeTooLow => RejectReasonCode::NetEdgeTooLow,
                    NetEdgeRejectReason::NetEdgeInputMissing => {
                        RejectReasonCode::NetEdgeInputMissing
                    }
                };
                GateOutcome::Reject {
                    gate,
                    reason_code: code,
                }
            }
        }
    }

    /// Convert a `PricerResult` to a `GateOutcome`.
    ///
    /// Exhaustive match — compiler forces update when `PricerRejectReason` adds a variant.
    pub fn from_pricer(gate: GateStep, result: &PricerResult) -> Self {
        match result {
            PricerResult::LimitPrice { .. } => GateOutcome::Allow { gate },
            PricerResult::Rejected { reason, .. } => {
                let code = match reason {
                    PricerRejectReason::NetEdgeTooLow => RejectReasonCode::NetEdgeTooLow,
                    PricerRejectReason::InvalidInput => RejectReasonCode::PricerInputInvalid,
                };
                GateOutcome::Reject {
                    gate,
                    reason_code: code,
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "gate_outcome_tests.rs"]
mod gate_outcome_tests;
