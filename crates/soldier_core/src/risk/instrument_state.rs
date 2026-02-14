//! Instrument lifecycle state used by expiry/delist handling.

/// Lifecycle state for a single instrument.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum InstrumentState {
    /// Instrument is tradable.
    Active,
    /// Instrument has reached expiry or was delisted and must not open new risk.
    ExpiredOrDelisted,
}
