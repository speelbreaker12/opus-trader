//! Shared WAL gate contract for execution routing.

/// Runtime adapter for the final RecordedBeforeDispatch gate.
///
/// Implementations perform the concrete WAL append attempt and return an
/// error when recording fails.
pub trait RecordedBeforeDispatchGate {
    fn record_before_dispatch(&mut self) -> Result<(), String>;
}
