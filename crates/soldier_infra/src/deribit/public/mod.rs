//! Deribit public API response structs.
//!
//! These structs model the response from `/public/get_instruments` and related
//! public endpoints. They are the source of truth for instrument metadata
//! (CONTRACT.md §1.0.X, AT-333).

use serde::Deserialize;

/// Deribit instrument kind as returned by the venue API.
///
/// Maps to the `kind` field in `/public/get_instruments` responses.
/// This is the raw venue representation; downstream code maps this to
/// the contract's `InstrumentKind` enum (option | linear_future | inverse_future | perpetual).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeribitInstrumentKind {
    /// Vanilla option
    Option,
    /// Linear or inverse future (Deribit uses "future" for both)
    Future,
    /// Option combo / spread
    #[serde(rename = "option_combo")]
    OptionCombo,
    /// Future combo / spread
    #[serde(rename = "future_combo")]
    FutureCombo,
}

/// Settlement period as returned by Deribit.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SettlementPeriod {
    Perpetual,
    Day,
    Week,
    Month,
    Quarter,
}

/// Instrument metadata from Deribit `/public/get_instruments` response.
///
/// Contains the fields required by CONTRACT.md §1.0.X and AT-333:
/// - `tick_size`: minimum price increment
/// - `min_trade_amount`: minimum order size (`min_amount` in contract terms)
/// - `tick_size_steps`: optional per-price-range tick sizes
/// - `contract_size`: contract multiplier for futures/perps
///
/// Additional fields support instrument lifecycle (§1.0.Y) and
/// InstrumentKind derivation.
#[derive(Debug, Clone, Deserialize)]
pub struct DeribitInstrument {
    /// Instrument name (e.g., "BTC-PERPETUAL", "ETH-28MAR25-3000-C")
    pub instrument_name: String,

    /// Instrument kind from venue
    pub kind: DeribitInstrumentKind,

    /// Whether the instrument is currently active for trading
    pub is_active: bool,

    /// Settlement period (perpetual, day, week, month, quarter)
    pub settlement_period: SettlementPeriod,

    /// Settlement currency (e.g., "BTC", "ETH", "USDC")
    pub settlement_currency: String,

    /// Quote currency (e.g., "USD", "USDC")
    pub quote_currency: String,

    /// Base currency (e.g., "BTC", "ETH")
    pub base_currency: String,

    /// Minimum price increment (CONTRACT.md: tick_size)
    pub tick_size: f64,

    /// Minimum order amount (CONTRACT.md: min_amount)
    pub min_trade_amount: f64,

    /// Order size step (CONTRACT.md: amount_step)
    /// Deribit calls this `min_trade_amount` for the step in some cases,
    /// but the actual step is typically the same as min_trade_amount.
    /// Some instruments have a separate `amount_step` field.
    #[serde(default)]
    pub amount_step: Option<f64>,

    /// Contract size / multiplier (CONTRACT.md: contract_multiplier)
    /// For BTC perpetual this is typically 10 USD, for ETH it's 1 USD, etc.
    pub contract_size: f64,

    /// Expiration timestamp in milliseconds (None for perpetuals)
    #[serde(default)]
    pub expiration_timestamp: Option<i64>,

    /// Creation timestamp in milliseconds
    pub creation_timestamp: i64,

    /// Whether this is a perpetual instrument
    #[serde(default)]
    pub is_perpetual: Option<bool>,

    /// Optional tick size steps (per-price-range tick sizes)
    #[serde(default)]
    pub tick_size_steps: Vec<TickSizeStep>,
}

impl DeribitInstrument {
    /// Returns the contract multiplier (alias for `contract_size`).
    ///
    /// This is the CONTRACT.md `contract_multiplier` field.
    pub fn contract_multiplier(&self) -> f64 {
        self.contract_size
    }
}

/// Per-price-range tick size definition.
#[derive(Debug, Clone, Deserialize)]
pub struct TickSizeStep {
    /// Price threshold above which this tick size applies
    pub above_price: f64,
    /// Tick size for prices above the threshold
    pub tick_size: f64,
}
