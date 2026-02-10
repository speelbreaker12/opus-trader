//! Deribit account summary / fee tier data per CONTRACT.md §4.2.
//!
//! Parses `/private/get_account_summary` response to extract fee tier
//! and caches with epoch-ms timestamp for staleness tracking.

/// Fee tier data from Deribit account summary.
#[derive(Debug, Clone, PartialEq)]
pub struct FeeTierData {
    /// Maker fee rate (e.g., 0.0001 = 1 bps).
    pub maker_fee_rate: f64,
    /// Taker fee rate (e.g., 0.0005 = 5 bps).
    pub taker_fee_rate: f64,
    /// Fee tier name (e.g., "tier_1").
    pub tier_name: String,
    /// Epoch milliseconds when this data was fetched.
    /// CONTRACT.md: "fee_model_cached_at_ts MUST be epoch milliseconds."
    pub cached_at_ts_ms: u64,
}

/// Fee cache holding the most recent fee tier data.
#[derive(Debug, Clone)]
pub struct FeeCache {
    /// Current fee tier data, if available.
    data: Option<FeeTierData>,
}

impl FeeCache {
    /// Create a new empty fee cache.
    pub fn new() -> Self {
        Self { data: None }
    }

    /// Update the cache with fresh fee tier data.
    pub fn update(&mut self, data: FeeTierData) {
        self.data = Some(data);
    }

    /// Get the current fee tier data, if available.
    pub fn get(&self) -> Option<&FeeTierData> {
        self.data.as_ref()
    }

    /// Get the cached-at timestamp in epoch milliseconds.
    /// Returns None if no data has been cached.
    pub fn cached_at_ts_ms(&self) -> Option<u64> {
        self.data.as_ref().map(|d| d.cached_at_ts_ms)
    }

    /// Get the taker fee rate, if available.
    pub fn taker_fee_rate(&self) -> Option<f64> {
        self.data.as_ref().map(|d| d.taker_fee_rate)
    }

    /// Get the maker fee rate, if available.
    pub fn maker_fee_rate(&self) -> Option<f64> {
        self.data.as_ref().map(|d| d.maker_fee_rate)
    }
}

impl Default for FeeCache {
    fn default() -> Self {
        Self::new()
    }
}
