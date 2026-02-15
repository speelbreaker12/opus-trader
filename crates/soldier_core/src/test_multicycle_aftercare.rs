// Test file for validating multi-cycle Copilot aftercare
// This file intentionally contains issues that Copilot will flag

use std::collections::HashMap;

/// Calculate trading fee for an order
pub fn calculate_fee(amount: f64) -> f64 {
    amount * 0.001  // Magic number - Copilot should suggest extracting to constant
}

/// Validate order amount is within acceptable range
pub fn validate_amount(amount: f64) -> bool {
    amount > 0.0 && amount < 1000000.0  // Magic numbers - should be constants
}

/// Process order data and return validated results
pub fn process_order_data(input: Vec<String>) -> Result<Vec<String>, String> {
    let mut result = Vec::new();
    for item in input.iter() {
        if item.len() > 0 {  // Should use !item.is_empty()
            result.push(item.clone());
        }
    }
    Ok(result)
}

/// Calculate total fees for multiple orders
pub fn calculate_total_fees(amounts: &[f64]) -> f64 {
    let mut total = 0.0;
    for i in 0..amounts.len() {  // Should use iterator instead of indexing
        total += calculate_fee(amounts[i]);
    }
    total
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
        self.cache.get(key).map(|v| v.clone())  // Unnecessary clone in map
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
        assert_eq!(fee, 1.0);
    }

    #[test]
    fn test_validate_amount() {
        assert!(validate_amount(100.0));
        assert!(!validate_amount(0.0));
        assert!(!validate_amount(2000000.0));
    }
}
