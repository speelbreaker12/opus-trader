//! Canonical execution domain model per CONTRACT.md definitions.
//!
//! This module provides first-class types for instrument semantics, canonical
//! order-size input, normalized sizing outputs, quantized wrappers, and
//! deterministic intent identity.

use serde::{Deserialize, Serialize};

/// Product family (not sizing semantics).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum InstrumentFamily {
    Option,
    Future,
    Perpetual,
}

/// Authoritative sizing semantics for a normalized instrument.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AmountSemantics {
    Coin,
    Usd,
}

/// Normalized instrument metadata consumed by sizing/quantization logic.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InstrumentMeta {
    pub instrument_id: String,
    pub instrument_family: InstrumentFamily,
    pub amount_semantics: AmountSemantics,
    pub tick_size: f64,
    pub amount_step: f64,
    pub min_amount: f64,
    pub contract_size_usd: Option<f64>,
}

/// Strategy-supplied canonical size input (exactly one variant).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum OrderSizeInput {
    CoinQty(f64),
    UsdQty(f64),
    Contracts(i64),
}

/// Canonical size representation after normalization.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CanonicalSizeKind {
    CoinQty,
    UsdQty,
    Contracts,
}

/// Runtime-normalized size with canonical + derived fields.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NormalizedOrderSize {
    pub canonical_size_kind: CanonicalSizeKind,
    pub contracts: Option<i64>,
    pub qty_coin: Option<f64>,
    pub qty_usd: Option<f64>,
    pub notional_usd: f64,
}

/// Integer count of amount-step units for canonical quantity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct QuantizedQtySteps(pub i64);

/// Integer count of tick-size units for canonical price.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct QuantizedPriceTicks(pub i64);

/// Deterministic 64-bit intent identity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct IntentId(pub u64);

impl From<u64> for IntentId {
    fn from(value: u64) -> Self {
        Self(value)
    }
}

impl From<IntentId> for u64 {
    fn from(value: IntentId) -> Self {
        value.0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum DomainModelError {
    InvalidIndexPrice(f64),
    InvalidQuantity,
    MissingContractSizeUsd,
    AmountSemanticsMismatch {
        expected: AmountSemantics,
        got: CanonicalSizeKind,
    },
}

/// Normalize canonical order-size input into runtime size fields.
///
/// Enforces semantics alignment: coin-semantics instruments accept CoinQty or
/// Contracts; usd-semantics instruments accept UsdQty or Contracts.
pub fn normalize_order_size(
    meta: &InstrumentMeta,
    input: OrderSizeInput,
    index_price: f64,
) -> Result<NormalizedOrderSize, DomainModelError> {
    if !index_price.is_finite() || index_price <= 0.0 {
        return Err(DomainModelError::InvalidIndexPrice(index_price));
    }

    match input {
        OrderSizeInput::CoinQty(qty_coin) => {
            validate_positive_finite(qty_coin)?;
            if meta.amount_semantics != AmountSemantics::Coin {
                return Err(DomainModelError::AmountSemanticsMismatch {
                    expected: meta.amount_semantics,
                    got: CanonicalSizeKind::CoinQty,
                });
            }
            let qty_usd = qty_coin * index_price;
            let contracts = derive_contracts(qty_usd, meta.contract_size_usd)?;
            Ok(NormalizedOrderSize {
                canonical_size_kind: CanonicalSizeKind::CoinQty,
                contracts,
                qty_coin: Some(qty_coin),
                qty_usd: Some(qty_usd),
                notional_usd: qty_usd,
            })
        }
        OrderSizeInput::UsdQty(qty_usd) => {
            validate_positive_finite(qty_usd)?;
            if meta.amount_semantics != AmountSemantics::Usd {
                return Err(DomainModelError::AmountSemanticsMismatch {
                    expected: meta.amount_semantics,
                    got: CanonicalSizeKind::UsdQty,
                });
            }
            let qty_coin = qty_usd / index_price;
            let contracts = derive_contracts(qty_usd, meta.contract_size_usd)?;
            Ok(NormalizedOrderSize {
                canonical_size_kind: CanonicalSizeKind::UsdQty,
                contracts,
                qty_coin: Some(qty_coin),
                qty_usd: Some(qty_usd),
                notional_usd: qty_usd,
            })
        }
        OrderSizeInput::Contracts(contracts) => {
            if contracts <= 0 {
                return Err(DomainModelError::InvalidQuantity);
            }
            let contract_size = meta
                .contract_size_usd
                .ok_or(DomainModelError::MissingContractSizeUsd)?;
            if !contract_size.is_finite() || contract_size <= 0.0 {
                return Err(DomainModelError::MissingContractSizeUsd);
            }
            let qty_usd = contracts as f64 * contract_size;
            if !qty_usd.is_finite() {
                return Err(DomainModelError::InvalidQuantity);
            }
            let qty_coin = qty_usd / index_price;
            Ok(NormalizedOrderSize {
                canonical_size_kind: CanonicalSizeKind::Contracts,
                contracts: Some(contracts),
                qty_coin: Some(qty_coin),
                qty_usd: Some(qty_usd),
                notional_usd: qty_usd,
            })
        }
    }
}

fn validate_positive_finite(value: f64) -> Result<(), DomainModelError> {
    if !value.is_finite() || value <= 0.0 {
        return Err(DomainModelError::InvalidQuantity);
    }
    Ok(())
}

fn derive_contracts(
    qty_usd: f64,
    contract_size_usd: Option<f64>,
) -> Result<Option<i64>, DomainModelError> {
    match contract_size_usd {
        None => Ok(None),
        Some(step) if !step.is_finite() || step <= 0.0 => {
            Err(DomainModelError::MissingContractSizeUsd)
        }
        Some(step) => {
            let rounded = (qty_usd / step).round();
            if !rounded.is_finite() || rounded > i64::MAX as f64 || rounded < i64::MIN as f64 {
                return Err(DomainModelError::InvalidQuantity);
            }
            Ok(Some(rounded as i64))
        }
    }
}

#[cfg(test)]
#[path = "domain_model_tests.rs"]
mod domain_model_tests;
