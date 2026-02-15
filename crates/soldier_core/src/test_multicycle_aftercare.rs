// Test file for validating multi-cycle Copilot aftercare
// This file intentionally contains issues that Copilot will flag

use std::collections::HashMap;

/// Fee rate applied to trading orders (fraction of amount, e.g. 0.001 = 0.1%)
const FEE_RATE: f64 = 0.001;
const MIN_ORDER_AMOUNT: f64 = 0.0;
const MAX_ORDER_AMOUNT_EXCLUSIVE: f64 = 1_000_000.0;

/// Calculate trading fee for an order
pub fn calculate_fee(amount: f64) -> f64 {
    amount * FEE_RATE
}

/// Validate order amount is within acceptable range
pub fn validate_amount(amount: f64) -> bool {
    amount > MIN_ORDER_AMOUNT && amount < MAX_ORDER_AMOUNT_EXCLUSIVE
}

/// Process order data and return validated results
pub fn process_order_data(input: Vec<String>) -> Result<Vec<String>, String> {
    let result: Vec<String> = input
        .into_iter()
        .filter(|item| !item.is_empty())
        .collect();
    Ok(result)
}

/// Calculate total fees for multiple orders
pub fn calculate_total_fees(amounts: &[f64]) -> f64 {
    amounts.iter().map(|&amount| calculate_fee(amount)).sum()
}

/// Simple cache implementation
pub struct OrderCache {
    cache: HashMap<String, String>,
}

impl OrderCache {
    pub fn new() -> Self {
        Self {
            cache: HashMap::new(),
        }
    }

    pub fn get(&self, key: &str) -> Option<String> {
        self.cache.get(key).cloned()
    }

    pub fn insert(&mut self, key: String, value: String) {
        self.cache.insert(key, value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_fee() {
        let fee = calculate_fee(1000.0);
        assert!((fee - 1.0).abs() < 1e-9);
    }

    #[test]
    fn test_validate_amount() {
        assert!(validate_amount(100.0));
        assert!(!validate_amount(0.0));
        assert!(!validate_amount(2000000.0));
    }
}
