//! Dispatcher amount mapping per CONTRACT.md Dispatcher Rules.
//!
//! Maps `OrderSize` to outbound Deribit request fields.
//! Exactly one canonical amount field is set per instrument_kind:
//! - `option | linear_future` → `amount = qty_coin`
//! - `perpetual | inverse_future` → `amount = qty_usd`

use crate::execution::OrderSize;
use crate::venue::InstrumentKind;

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
}

/// Map an `OrderSize` to a `DispatchRequest` for Deribit.
///
/// CONTRACT.md Dispatcher Rules:
/// - coin instruments (`option | linear_future`) → send `amount = qty_coin`
/// - USD instruments (`perpetual | inverse_future`) → send `amount = qty_usd`
/// - `reduce_only` is derived from intent classification only.
pub fn map_to_dispatch(
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
