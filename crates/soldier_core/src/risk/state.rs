//! Risk state enum per CONTRACT.md §definitions.
//!
//! `RiskState` is the health/cause layer that feeds into PolicyGuard's
//! `TradingMode` resolution (§2.2).

/// Health/cause layer risk state.
///
/// CONTRACT.md: `RiskState: Healthy | Degraded | Maintenance | Kill`
///
/// This enum represents the system's health assessment. It is an input to
/// PolicyGuard, which maps it (along with other signals) to a `TradingMode`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RiskState {
    /// All systems nominal.
    Healthy,
    /// Degraded condition detected (e.g., stale instrument cache, stale fees).
    /// PolicyGuard should resolve to `TradingMode::ReduceOnly`.
    Degraded,
    /// Maintenance mode (e.g., exchange maintenance window).
    /// PolicyGuard should resolve to `TradingMode::ReduceOnly`.
    Maintenance,
    /// Fatal condition — immediate halt required.
    /// PolicyGuard should resolve to `TradingMode::Kill`.
    Kill,
}
