//! Intent assembly: sizing derivation + dispatch mapping before gate evaluation.
//!
//! Wires `derive_instrument_kind`, `build_order_size`, and `validate_and_dispatch`
//! into a single production-path assembly step.

use super::build_order_intent::ChokeIntentClass;
use super::dispatch_map::{
    DispatchConsistencyProof, IntentClass, MismatchMetrics, validate_and_dispatch,
};
use super::order_size::{OrderSize, OrderSizeInput, build_order_size};
use crate::venue::{
    InstrumentKind, InstrumentKindInput, derive_instrument_kind,
};

// ─── Types ──────────────────────────────────────────────────────────────

/// Error from intent assembly (sizing + dispatch mapping).
#[derive(Debug, Clone, PartialEq)]
pub enum AssemblySizingError {
    /// Venue metadata does not map to any known InstrumentKind.
    UnknownInstrumentKind,
    /// OrderSize construction failed (invalid qty, price, or multiplier).
    InvalidOrderSize(String),
}

/// Input parameters for sizing derivation.
#[derive(Debug, Clone)]
pub struct SizingParams {
    /// Canonical quantity in the instrument's native unit.
    pub canonical_qty: f64,
    /// Current index price (BTC/ETH price in USD).
    pub index_price: f64,
    /// Contract multiplier (contract_size from venue metadata).
    pub contract_multiplier: Option<f64>,
}

/// Result of successful intent assembly.
#[derive(Debug, Clone, PartialEq)]
pub struct AssembledSizing {
    /// Derived instrument kind.
    pub instrument_kind: InstrumentKind,
    /// Canonical order sizing.
    pub order_size: OrderSize,
    /// AT-920 dispatch consistency proof.
    pub dispatch_consistency: DispatchConsistencyProof,
    /// Whether assembly detected a degraded condition (mismatch).
    pub risk_state_degraded: bool,
}

// ─── Helpers ────────────────────────────────────────────────────────────

/// Map chokepoint intent class to dispatch intent class.
pub fn choke_intent_to_dispatch(c: ChokeIntentClass) -> IntentClass {
    match c {
        ChokeIntentClass::Open => IntentClass::Open,
        ChokeIntentClass::Close => IntentClass::Close,
        ChokeIntentClass::Hedge => IntentClass::Hedge,
        ChokeIntentClass::CancelOnly => IntentClass::Cancel,
    }
}

// ─── Assembly ───────────────────────────────────────────────────────────

/// Derive instrument kind, build order size, and validate dispatch consistency.
///
/// This wires `derive_instrument_kind`, `build_order_size`, and
/// `validate_and_dispatch` into a single production-path function.
///
/// On success, returns the assembled sizing with dispatch consistency result.
/// On error, returns fail-closed `AssemblySizingError`.
pub fn assemble_sizing(
    meta: &InstrumentKindInput,
    params: &SizingParams,
    intent: IntentClass,
    mismatch_metrics: &mut MismatchMetrics,
) -> Result<AssembledSizing, AssemblySizingError> {
    // Step 1: Derive instrument kind from venue metadata.
    let instrument_kind =
        derive_instrument_kind(meta).ok_or(AssemblySizingError::UnknownInstrumentKind)?;

    // Step 2: Build canonical order sizing.
    let osi = OrderSizeInput {
        instrument_kind,
        canonical_qty: params.canonical_qty,
        index_price: params.index_price,
        contract_multiplier: params.contract_multiplier,
    };
    let order_size = build_order_size(&osi)
        .map_err(|e| AssemblySizingError::InvalidOrderSize(format!("{e:?}")))?;

    // Step 3: Validate dispatch consistency (AT-920).
    let (dispatch_consistency, risk_state_degraded) = match validate_and_dispatch(
        &order_size,
        instrument_kind,
        intent,
        params.contract_multiplier,
        mismatch_metrics,
    ) {
        Ok(ref validated) => (DispatchConsistencyProof::from_validated(validated), false),
        Err(_) => (DispatchConsistencyProof::failed(), true),
    };

    Ok(AssembledSizing {
        instrument_kind,
        order_size,
        dispatch_consistency,
        risk_state_degraded,
    })
}

#[cfg(test)]
#[path = "intent_assembly_tests.rs"]
mod intent_assembly_tests;
