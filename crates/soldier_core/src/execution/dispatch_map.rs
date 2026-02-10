//! Dispatcher amount mapping per CONTRACT.md Dispatcher Rules.
//!
//! Maps `OrderSize` to outbound Deribit request fields.
//! Exactly one canonical amount field is set per instrument_kind:
//! - `option | linear_future` → `amount = qty_coin`
//! - `perpetual | inverse_future` → `amount = qty_usd`
//!
//! CONTRACT.md AT-920: If `contracts` and canonical amount are both present
//! and mismatch beyond `CONTRACTS_AMOUNT_MATCH_TOLERANCE`, the intent is
//! rejected and `RiskState::Degraded` is returned.

use crate::execution::OrderSize;
use crate::risk::RiskState;
use crate::venue::InstrumentKind;

/// Tolerance for contracts-vs-amount consistency check (AT-920).
///
/// If `|contracts * multiplier - canonical_amount| / canonical_amount > tolerance`,
/// the sizing is rejected as a unit mismatch.
pub const CONTRACTS_AMOUNT_MATCH_TOLERANCE: f64 = 0.001;

/// Intent classification for dispatch authorization.
///
/// CONTRACT.md: if uncertain, treat as OPEN (most restrictive).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IntentClass {
    /// New exposure — blocked in ReduceOnly/Kill.
    Open,
    /// Risk-reducing — allowed in ReduceOnly.
    Close,
    /// Risk-reducing hedge — allowed in ReduceOnly.
    Hedge,
    /// Order cancellation — always allowed.
    Cancel,
}

/// Outbound Deribit order request fields.
///
/// CONTRACT.md: "always send exactly one canonical amount value."
#[derive(Debug, Clone, PartialEq)]
pub struct DispatchRequest {
    /// The single canonical amount to send to Deribit.
    /// For coin instruments: qty_coin. For USD instruments: qty_usd.
    pub amount: f64,
    /// Whether this is a reduce-only order.
    /// CLOSE/HEDGE → true; OPEN → false.
    pub reduce_only: bool,
}

/// Error returned when dispatch mapping fails.
#[derive(Debug, Clone, PartialEq)]
pub enum DispatchMapError {
    /// Coin-sized instrument but qty_coin is missing from OrderSize.
    MissingQtyCoin,
    /// USD-sized instrument but qty_usd is missing from OrderSize.
    MissingQtyUsd,
    /// `contracts` is populated; caller must run AT-920 validation first.
    /// Use [`validate_and_dispatch`] with `contract_multiplier`.
    ContractsRequireValidation,
    /// CONTRACT.md AT-920: contracts and canonical amount mismatch.
    /// Contains the relative mismatch delta.
    ContractsAmountMismatch {
        /// Relative delta: `|contracts_implied - canonical| / canonical`.
        delta: f64,
    },
}

/// Result of a validated dispatch, including risk assessment.
///
/// Returned by [`validate_and_dispatch`] when the sizing is valid.
#[derive(Debug, Clone, PartialEq)]
pub struct ValidatedDispatch {
    /// The dispatch request to send to the venue.
    pub request: DispatchRequest,
    /// Risk state resulting from validation.
    /// `Healthy` when all checks pass.
    pub risk_state: RiskState,
}

/// Mismatch rejection metrics (AT-920 observability).
///
/// Tracks the count of contract/amount mismatch rejections.
#[derive(Debug)]
pub struct MismatchMetrics {
    /// `order_intent_reject_unit_mismatch_total` counter.
    reject_unit_mismatch_total: u64,
}

impl MismatchMetrics {
    /// Create a new metrics tracker with all counters at zero.
    pub fn new() -> Self {
        Self {
            reject_unit_mismatch_total: 0,
        }
    }

    /// Increment the mismatch rejection counter.
    pub fn record_mismatch_rejection(&mut self) {
        self.reject_unit_mismatch_total += 1;
    }

    /// Current value of `order_intent_reject_unit_mismatch_total`.
    pub fn reject_unit_mismatch_total(&self) -> u64 {
        self.reject_unit_mismatch_total
    }
}

impl Default for MismatchMetrics {
    fn default() -> Self {
        Self::new()
    }
}

/// Map an `OrderSize` to a `DispatchRequest` for Deribit.
///
/// CONTRACT.md Dispatcher Rules:
/// - coin instruments (`option | linear_future`) → send `amount = qty_coin`
/// - USD instruments (`perpetual | inverse_future`) → send `amount = qty_usd`
/// - `reduce_only` is derived from intent classification only.
/// - If `contracts` is present, use [`validate_and_dispatch`] so AT-920
///   mismatch checks execute before mapping.
pub fn map_to_dispatch(
    order_size: &OrderSize,
    instrument_kind: InstrumentKind,
    intent: IntentClass,
) -> Result<DispatchRequest, DispatchMapError> {
    // Fail closed: if contracts are present, callers must route through
    // validate_and_dispatch so AT-920 mismatch checks run before mapping.
    if order_size.contracts.is_some() {
        return Err(DispatchMapError::ContractsRequireValidation);
    }

    map_to_dispatch_unchecked(order_size, instrument_kind, intent)
}

fn map_to_dispatch_unchecked(
    order_size: &OrderSize,
    instrument_kind: InstrumentKind,
    intent: IntentClass,
) -> Result<DispatchRequest, DispatchMapError> {
    let amount = match instrument_kind {
        InstrumentKind::Option | InstrumentKind::LinearFuture => order_size
            .qty_coin
            .ok_or(DispatchMapError::MissingQtyCoin)?,
        InstrumentKind::Perpetual | InstrumentKind::InverseFuture => {
            order_size.qty_usd.ok_or(DispatchMapError::MissingQtyUsd)?
        }
    };

    let reduce_only = match intent {
        IntentClass::Open => false,
        IntentClass::Close | IntentClass::Hedge | IntentClass::Cancel => true,
    };

    Ok(DispatchRequest {
        amount,
        reduce_only,
    })
}

/// Validate contracts/amount consistency and dispatch (AT-920).
///
/// CONTRACT.md AT-920: If `contracts` and canonical amount are both present,
/// validates that `|contracts * contract_multiplier - canonical_amount| / canonical_amount`
/// does not exceed [`CONTRACTS_AMOUNT_MATCH_TOLERANCE`].
///
/// On mismatch: returns `Err(ContractsAmountMismatch)` and the caller must
/// set `RiskState::Degraded` and increment the mismatch counter.
///
/// When `contracts` is `None` or `contract_multiplier` is `None`, the
/// consistency check is skipped (nothing to compare).
pub fn validate_and_dispatch(
    order_size: &OrderSize,
    instrument_kind: InstrumentKind,
    intent: IntentClass,
    contract_multiplier: Option<f64>,
    metrics: &mut MismatchMetrics,
) -> Result<ValidatedDispatch, DispatchMapError> {
    // AT-920: contracts/amount consistency check
    if let (Some(contracts), Some(multiplier)) = (order_size.contracts, contract_multiplier) {
        let canonical_amount = match instrument_kind {
            InstrumentKind::Option | InstrumentKind::LinearFuture => order_size
                .qty_coin
                .ok_or(DispatchMapError::MissingQtyCoin)?,
            InstrumentKind::Perpetual | InstrumentKind::InverseFuture => {
                order_size.qty_usd.ok_or(DispatchMapError::MissingQtyUsd)?
            }
        };

        let contracts_implied = contracts as f64 * multiplier;
        let delta = (contracts_implied - canonical_amount).abs() / canonical_amount;

        if delta > CONTRACTS_AMOUNT_MATCH_TOLERANCE {
            metrics.record_mismatch_rejection();
            return Err(DispatchMapError::ContractsAmountMismatch { delta });
        }
    }

    let request = map_to_dispatch_unchecked(order_size, instrument_kind, intent)?;
    Ok(ValidatedDispatch {
        request,
        risk_state: RiskState::Healthy,
    })
}
