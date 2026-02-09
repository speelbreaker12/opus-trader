//! Venue-derived instrument types per CONTRACT.md.
//!
//! `InstrumentKind` is derived from Deribit venue metadata and determines
//! canonical sizing units (qty_coin vs qty_usd) for order dispatch.

/// Internal instrument classification per CONTRACT.md §definitions.
///
/// CONTRACT.md: `instrument_kind: option | linear_future | inverse_future | perpetual`
///
/// Determines canonical sizing:
/// - `Option | LinearFuture` → canonical `qty_coin`
/// - `Perpetual | InverseFuture` → canonical `qty_usd`
///
/// **Linear Perpetuals (USDC-margined)**: treated as `LinearFuture` for sizing,
/// even if the venue symbol says "PERPETUAL" (CONTRACT.md §definitions).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum InstrumentKind {
    /// Vanilla option — canonical sizing: qty_coin
    Option,
    /// Linear future (including USDC-margined perpetuals) — canonical sizing: qty_coin
    LinearFuture,
    /// Inverse future (BTC/ETH-margined) — canonical sizing: qty_usd
    InverseFuture,
    /// Perpetual (BTC/ETH-margined) — canonical sizing: qty_usd
    Perpetual,
}

/// Input for InstrumentKind derivation from venue metadata.
///
/// This struct decouples the derivation logic from any specific venue struct
/// (avoids cyclic dependency between soldier_core and soldier_infra).
/// Callers construct this from venue-specific metadata before calling
/// `derive_instrument_kind`.
#[derive(Debug, Clone)]
pub struct InstrumentKindInput {
    /// Whether the venue instrument is an option
    pub is_option: bool,
    /// Whether the venue instrument is a future (including perpetuals)
    pub is_future: bool,
    /// Whether the settlement period is perpetual
    pub is_perpetual: bool,
    /// Whether settlement_currency == quote_currency (USDC-margined = linear)
    pub is_linear: bool,
}

/// Derives `InstrumentKind` from venue-agnostic input parameters.
///
/// Mapping rules (CONTRACT.md §definitions, §Dispatcher Rules):
/// - option → `InstrumentKind::Option`
/// - future + linear (settlement_currency == quote_currency, i.e. USDC-margined) → `LinearFuture`
/// - future + perpetual + NOT linear → `Perpetual`
/// - future + NOT perpetual + NOT linear → `InverseFuture`
/// - anything else → None (out of scope; callers should reject)
pub fn derive_instrument_kind(input: &InstrumentKindInput) -> Option<InstrumentKind> {
    if input.is_option {
        return Some(InstrumentKind::Option);
    }

    if input.is_future {
        if input.is_linear {
            // CONTRACT.md: "Linear Perpetuals (USDC-margined): treat as
            // linear_future for sizing (canonical qty_coin)"
            return Some(InstrumentKind::LinearFuture);
        }
        if input.is_perpetual {
            return Some(InstrumentKind::Perpetual);
        }
        // Non-perpetual, non-linear future → inverse future
        // (BTC/ETH-settled dated futures)
        return Some(InstrumentKind::InverseFuture);
    }

    // Combo instruments or unknown kinds
    None
}
