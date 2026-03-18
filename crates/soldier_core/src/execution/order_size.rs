//! OrderSize canonical sizing per CONTRACT.md §1.0.
//!
//! CONTRACT.md: `OrderSize` encodes canonical sizing for dispatch.
//! - `option | linear_future` → canonical `qty_coin`
//! - `perpetual | inverse_future` → canonical `qty_usd`
//! - `notional_usd` is always populated.

use crate::venue::InstrumentKind;

/// Canonical order sizing per CONTRACT.md.
///
/// Construct only via [`build_order_size`] to enforce precision and validity guards.
///
/// ```text
/// pub struct OrderSize {
///   pub contracts: Option<i64>,     // integer contracts when applicable
///   pub qty_coin: Option<f64>,      // BTC/ETH amount when applicable
///   pub qty_usd: Option<f64>,       // USD amount when applicable
///   pub notional_usd: f64,          // always populated (derived)
/// }
/// ```
///
/// Sizing rules (CONTRACT.md §1.0, Dispatcher Rules):
/// - `option | linear_future`: canonical = `qty_coin`;
///   `notional_usd = qty_coin * index_price`
/// - `perpetual | inverse_future`: canonical = `qty_usd`;
///   `notional_usd = qty_usd`
/// - For options: `qty_usd` MUST be unset (AT-277).
#[derive(Debug, Clone, PartialEq)]
pub struct OrderSize {
    /// Integer contracts when applicable.
    pub(crate) contracts: Option<i64>,
    /// BTC/ETH amount — canonical for `option | linear_future`.
    pub(crate) qty_coin: Option<f64>,
    /// USD amount — canonical for `perpetual | inverse_future`.
    /// MUST be `None` for options (CONTRACT.md AT-277).
    pub(crate) qty_usd: Option<f64>,
    /// Always populated. Derived from the canonical quantity.
    pub(crate) notional_usd: f64,
}

/// Input parameters for building an `OrderSize`.
///
/// Decouples construction from any specific venue or strategy struct.
#[derive(Debug, Clone)]
pub struct OrderSizeInput {
    /// Instrument classification (determines canonical sizing unit).
    pub instrument_kind: InstrumentKind,
    /// The canonical quantity in the instrument's native unit.
    /// - For `option | linear_future`: this is `qty_coin` (BTC/ETH).
    /// - For `perpetual | inverse_future`: this is `qty_usd` (USD).
    pub canonical_qty: f64,
    /// Current index price (BTC/ETH price in USD).
    /// Required for coin-sized instruments to compute `notional_usd`.
    /// Also used for USD-sized instruments to derive `qty_coin`.
    pub index_price: f64,
    /// Contract multiplier (contract_size from venue metadata).
    /// When provided, `contracts` is derived from the canonical quantity.
    pub contract_multiplier: Option<f64>,
}

/// Error returned when OrderSize cannot be built.
#[derive(Debug, Clone, PartialEq)]
pub enum OrderSizeError {
    /// Index price must be positive and finite.
    InvalidIndexPrice(f64),
    /// Canonical quantity must be positive and finite.
    InvalidCanonicalQty(f64),
    /// Contract multiplier must be positive and finite when provided.
    InvalidContractMultiplier(f64),
    /// Computed notional_usd is not finite (NaN/Inf output guard).
    InvalidNotional(f64),
    /// Computed contracts value overflows i64 range.
    ContractsOverflow { value: f64 },
    /// Computed contracts value exceeds 2^53, making i64→f64 conversion lossy.
    ContractsPrecisionLoss { value: f64 },
}

// TODO(slice-N): Wire into production dispatch — currently only called from unit tests
/// Build an `OrderSize` from the given input parameters.
///
/// CONTRACT.md Dispatcher Rules:
/// - `option | linear_future`: canonical = `qty_coin`;
///   derive `notional_usd = qty_coin * index_price`;
///   derive `contracts = round(qty_coin / contract_multiplier)` if multiplier defined.
/// - `perpetual | inverse_future`: canonical = `qty_usd`;
///   `notional_usd = qty_usd`;
///   derive `qty_coin = qty_usd / index_price`;
///   derive `contracts = round(qty_usd / contract_size_usd)` if multiplier defined.
///
/// For options, `qty_usd` is always `None` (CONTRACT.md AT-277).
pub fn build_order_size(input: &OrderSizeInput) -> Result<OrderSize, OrderSizeError> {
    // Validate inputs — fail-closed on bad data
    if !input.index_price.is_finite() || input.index_price <= 0.0 {
        return Err(OrderSizeError::InvalidIndexPrice(input.index_price));
    }
    if !input.canonical_qty.is_finite() || input.canonical_qty <= 0.0 {
        return Err(OrderSizeError::InvalidCanonicalQty(input.canonical_qty));
    }
    if let Some(mult) = input.contract_multiplier
        && (!mult.is_finite() || mult <= 0.0)
    {
        return Err(OrderSizeError::InvalidContractMultiplier(mult));
    }

    match input.instrument_kind {
        InstrumentKind::Option | InstrumentKind::LinearFuture => {
            // Canonical = qty_coin
            let qty_coin = input.canonical_qty;
            let notional_usd = qty_coin * input.index_price;

            // Output guard: reject non-finite notional (NaN/Inf from overflow).
            if !notional_usd.is_finite() {
                return Err(OrderSizeError::InvalidNotional(notional_usd));
            }

            let contracts = match input.contract_multiplier {
                Some(mult) => {
                    let rounded = (qty_coin / mult).round();
                    if rounded > i64::MAX as f64 || rounded < i64::MIN as f64 {
                        return Err(OrderSizeError::ContractsOverflow { value: rounded });
                    }
                    // Guard: i64→f64 conversion is lossy for values > 2^53.
                    // Reject before the cast so downstream float math is precise.
                    if rounded.abs() > (1i64 << 53) as f64 {
                        return Err(OrderSizeError::ContractsPrecisionLoss { value: rounded });
                    }
                    Some(rounded as i64)
                }
                None => None,
            };

            // CONTRACT.md AT-277: option qty_usd MUST be unset
            // For linear_future, qty_usd is also not the canonical unit,
            // so we leave it None for consistency.
            Ok(OrderSize {
                contracts,
                qty_coin: Some(qty_coin),
                qty_usd: None,
                notional_usd,
            })
        }
        InstrumentKind::Perpetual | InstrumentKind::InverseFuture => {
            // Canonical = qty_usd
            let qty_usd = input.canonical_qty;
            let notional_usd = qty_usd;
            let qty_coin = qty_usd / input.index_price;

            // Output guard: reject non-finite qty_coin (NaN/Inf from overflow).
            if !qty_coin.is_finite() {
                return Err(OrderSizeError::InvalidNotional(qty_coin));
            }

            let contracts = match input.contract_multiplier {
                Some(mult) => {
                    let rounded = (qty_usd / mult).round();
                    if rounded > i64::MAX as f64 || rounded < i64::MIN as f64 {
                        return Err(OrderSizeError::ContractsOverflow { value: rounded });
                    }
                    // Guard: i64→f64 conversion is lossy for values > 2^53.
                    // Reject before the cast so downstream float math is precise.
                    if rounded.abs() > (1i64 << 53) as f64 {
                        return Err(OrderSizeError::ContractsPrecisionLoss { value: rounded });
                    }
                    Some(rounded as i64)
                }
                None => None,
            };

            Ok(OrderSize {
                contracts,
                qty_coin: Some(qty_coin),
                qty_usd: Some(qty_usd),
                notional_usd,
            })
        }
    }
}

#[cfg(test)]
#[path = "order_size_tests.rs"]
mod order_size_tests;
