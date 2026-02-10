//! Instrument metadata cache with TTL-based freshness tracking.
//!
//! CONTRACT.md §1.0.X (Instrument Metadata Freshness):
//! The engine MUST track freshness of instrument metadata and set
//! `RiskState::Degraded` when metadata exceeds `instrument_cache_ttl_s`.
//!
//! Observability (contract-bound names):
//! - `instrument_cache_age_s` (gauge)
//! - `instrument_cache_hits_total` (counter)
//! - `instrument_cache_stale_total` (counter)
//! - `instrument_cache_refresh_errors_total` (counter, optional but recommended)

use std::collections::HashMap;
use std::time::Instant;

use crate::risk::RiskState;
use crate::venue::InstrumentKind;

/// Hard cap for queued TTL breach events to prevent unbounded growth.
pub const MAX_PENDING_BREACH_EVENTS: usize = 1024;

/// Result of an instrument cache lookup.
///
/// Contains the cached instrument kind, the freshness-derived risk state,
/// and the cache age in seconds (for observability).
#[derive(Debug, Clone, PartialEq)]
pub struct CacheLookupResult {
    /// Cached instrument classification.
    pub instrument_kind: InstrumentKind,
    /// Risk state derived from cache freshness vs TTL.
    /// `Healthy` if fresh, `Degraded` if stale.
    pub risk_state: RiskState,
    /// Age of the cached entry in seconds (for `instrument_cache_age_s` gauge).
    pub cache_age_s: f64,
}

/// Structured event emitted when a cache TTL breach is detected.
///
/// CONTRACT.md §1.0.X: callers SHOULD log this as a structured event
/// `InstrumentCacheTtlBreach { instrument_id, age_s, ttl_s }`.
#[derive(Debug, Clone, PartialEq)]
pub struct CacheTtlBreach {
    /// The instrument whose cache entry is stale.
    pub instrument_id: String,
    /// Actual cache age in seconds.
    pub age_s: f64,
    /// Configured TTL threshold that was exceeded.
    pub ttl_s: f64,
}

/// A single cached instrument entry.
#[derive(Debug, Clone)]
struct CacheEntry {
    instrument_kind: InstrumentKind,
    inserted_at: Instant,
}

/// Instrument metadata cache with TTL-based freshness tracking.
///
/// CONTRACT.md §1.0.X: stale metadata → `RiskState::Degraded` →
/// PolicyGuard computes `TradingMode::ReduceOnly` within one tick.
///
/// Time is injected via `_at` suffixed methods for deterministic testing.
/// Production callers use the convenience methods without the `_at` suffix.
#[derive(Debug)]
pub struct InstrumentCache {
    entries: HashMap<String, CacheEntry>,
    /// Running count of cache hits (for `instrument_cache_hits_total` counter).
    hits_total: u64,
    /// Running count of stale accesses (for `instrument_cache_stale_total` counter).
    stale_total: u64,
    /// Running count of metadata refresh errors
    /// (for `instrument_cache_refresh_errors_total` counter).
    refresh_errors_total: u64,
    /// Most recent cache age observed (for `instrument_cache_age_s` gauge).
    last_age_s: Option<f64>,
    /// Pending TTL breach events for the caller to drain and log.
    pending_breaches: Vec<CacheTtlBreach>,
}

impl Default for InstrumentCache {
    fn default() -> Self {
        Self::new()
    }
}

impl InstrumentCache {
    /// Create a new empty instrument cache.
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
            hits_total: 0,
            stale_total: 0,
            refresh_errors_total: 0,
            last_age_s: None,
            pending_breaches: Vec::new(),
        }
    }

    /// Insert or update an instrument in the cache, recording insertion time.
    ///
    /// Production entry point — uses `Instant::now()`.
    pub fn insert(&mut self, instrument_id: &str, kind: InstrumentKind) {
        self.insert_at(instrument_id, kind, Instant::now());
    }

    /// Insert or update an instrument with an explicit timestamp.
    ///
    /// Used by tests for deterministic time control.
    pub fn insert_at(&mut self, instrument_id: &str, kind: InstrumentKind, now: Instant) {
        self.entries.insert(
            instrument_id.to_string(),
            CacheEntry {
                instrument_kind: kind,
                inserted_at: now,
            },
        );
    }

    /// Look up an instrument, checking freshness against the configured TTL.
    ///
    /// Returns `None` if the instrument is not cached (caller must handle).
    /// Returns `Some(CacheLookupResult)` with:
    /// - `RiskState::Healthy` if `cache_age_s <= ttl_s`
    /// - `RiskState::Degraded` if `cache_age_s > ttl_s`
    ///
    /// Production entry point — uses `Instant::now()`.
    pub fn get(&mut self, instrument_id: &str, ttl_s: f64) -> Option<CacheLookupResult> {
        self.get_at(instrument_id, ttl_s, Instant::now())
    }

    /// Look up an instrument with an explicit "now" for deterministic testing.
    ///
    /// CONTRACT.md §1.0.X: cache age compared against `instrument_cache_ttl_s`.
    pub fn get_at(
        &mut self,
        instrument_id: &str,
        ttl_s: f64,
        now: Instant,
    ) -> Option<CacheLookupResult> {
        let entry = self.entries.get(instrument_id)?;

        self.hits_total += 1;

        // Use saturating_duration_since to avoid panic if clocks are anomalous.
        // If time went backwards (impossible with Instant::now(), but possible
        // via _at methods), saturates to zero → age=0 → fresh. This is
        // acceptable because _at methods are test-only; production uses
        // Instant::now() which is monotonic.
        let age = now.saturating_duration_since(entry.inserted_at);
        let cache_age_s = age.as_secs_f64();

        // Update gauge for instrument_cache_age_s observability.
        self.last_age_s = Some(cache_age_s);

        // CONTRACT.md §1.0.X: metadata age "exceeding" instrument_cache_ttl_s
        // → Degraded. "exceeding" = strictly greater than (>), so age == ttl
        // is still Healthy.
        // Fail closed: non-finite TTL cannot safely express a staleness bound.
        let ttl_invalid = !ttl_s.is_finite();
        let risk_state = if ttl_invalid || cache_age_s > ttl_s {
            self.stale_total += 1;
            if self.pending_breaches.len() >= MAX_PENDING_BREACH_EVENTS {
                // Keep the newest events while bounding memory growth.
                self.pending_breaches.remove(0);
            }
            self.pending_breaches.push(CacheTtlBreach {
                instrument_id: instrument_id.to_string(),
                age_s: cache_age_s,
                ttl_s,
            });
            RiskState::Degraded
        } else {
            RiskState::Healthy
        };

        Some(CacheLookupResult {
            instrument_kind: entry.instrument_kind,
            risk_state,
            cache_age_s,
        })
    }

    /// Fail-closed convenience: returns `RiskState` for an instrument,
    /// mapping cache miss to `Degraded`.
    ///
    /// This is the recommended API for dispatch eligibility checks.
    /// Missing metadata is treated the same as stale metadata — fail-closed.
    pub fn risk_state_for(&mut self, instrument_id: &str, ttl_s: f64) -> RiskState {
        self.risk_state_for_at(instrument_id, ttl_s, Instant::now())
    }

    /// Fail-closed convenience with explicit timestamp for testing.
    pub fn risk_state_for_at(
        &mut self,
        instrument_id: &str,
        ttl_s: f64,
        now: Instant,
    ) -> RiskState {
        match self.get_at(instrument_id, ttl_s, now) {
            Some(result) => result.risk_state,
            None => RiskState::Degraded, // fail-closed: unknown = degraded
        }
    }

    /// Total number of cache hits (for `instrument_cache_hits_total` counter).
    pub fn hits_total(&self) -> u64 {
        self.hits_total
    }

    /// Total number of stale accesses (for `instrument_cache_stale_total` counter).
    pub fn stale_total(&self) -> u64 {
        self.stale_total
    }

    /// Total number of metadata refresh errors
    /// (for `instrument_cache_refresh_errors_total` counter).
    pub fn refresh_errors_total(&self) -> u64 {
        self.refresh_errors_total
    }

    /// Record a metadata refresh error.
    ///
    /// Call this when a `/public/get_instruments` request fails.
    /// Increments `instrument_cache_refresh_errors_total`.
    pub fn record_refresh_error(&mut self) {
        self.refresh_errors_total += 1;
    }

    /// Most recent cache age observed (for `instrument_cache_age_s` gauge).
    ///
    /// Returns `None` if no lookups have been performed yet.
    pub fn last_age_s(&self) -> Option<f64> {
        self.last_age_s
    }

    /// Drain pending TTL breach events.
    ///
    /// Callers should log each `CacheTtlBreach` as a structured event
    /// (e.g., via `tracing::warn!`). Draining clears the buffer.
    pub fn drain_breaches(&mut self) -> Vec<CacheTtlBreach> {
        std::mem::take(&mut self.pending_breaches)
    }

    /// Number of cached instruments.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Whether the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// Returns `true` if OPEN intents should be blocked given the current `RiskState`.
///
/// CONTRACT.md §2.2.3: PolicyGuard computes `TradingMode::ReduceOnly` when
/// `RiskState` is `Degraded` or `Maintenance`, which blocks OPEN intents.
/// `Kill` blocks all new exposure. Only `Healthy` allows OPEN.
///
/// CLOSE, HEDGE, and CANCEL remain dispatchable in all non-Kill states
/// (subject to Kill semantics in §2.2.3).
pub fn opens_blocked(risk_state: RiskState) -> bool {
    match risk_state {
        RiskState::Healthy => false,
        RiskState::Degraded | RiskState::Maintenance | RiskState::Kill => true,
    }
}
