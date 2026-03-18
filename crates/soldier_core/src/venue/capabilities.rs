//! Venue capabilities matrix and feature flags per CONTRACT.md §1.4.4.
//!
//! Gating linked/OCO orders behind both venue capability AND runtime
//! feature flag. Both must be true for linked orders to be allowed.
//!
//! AT-028, AT-004, AT-915.

// ─── Venue capabilities ─────────────────────────────────────────────────

/// Venue-reported capabilities for a specific instrument or venue context.
///
/// These reflect what the venue actually supports, independent of what
/// the bot is configured to use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VenueCapabilities {
    /// Whether the venue supports linked/OCO orders for this context.
    ///
    /// CONTRACT.md: "MUST be `false` for v5.1"
    /// (Deribit Venue Facts Addendum F-08: VERIFIED (NOT SUPPORTED))
    pub linked_orders_supported: bool,
}

impl VenueCapabilities {
    /// Default capabilities for Deribit v5.1.
    ///
    /// Fail-closed: all advanced features default to off.
    pub fn deribit_v51_default() -> Self {
        Self {
            linked_orders_supported: false,
        }
    }
}

impl Default for VenueCapabilities {
    /// Default is fail-closed: nothing advanced is supported.
    fn default() -> Self {
        Self::deribit_v51_default()
    }
}

// ─── Feature flags ──────────────────────────────────────────────────────

/// Runtime feature flags for the bot.
///
/// These are operator-controlled flags that gate bot behavior,
/// independent of venue capabilities.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BotFeatureFlags {
    /// `ENABLE_LINKED_ORDERS_FOR_BOT` — runtime config feature flag.
    ///
    /// CONTRACT.md: "default `false` (fail-closed if missing/unset)"
    pub enable_linked_orders: bool,
}

impl BotFeatureFlags {
    /// Default feature flags — all advanced features off (fail-closed).
    pub fn default_flags() -> Self {
        Self {
            enable_linked_orders: false,
        }
    }
}

impl Default for BotFeatureFlags {
    fn default() -> Self {
        Self::default_flags()
    }
}

// ─── Evaluated capabilities ─────────────────────────────────────────────

/// Evaluated (resolved) capabilities: the intersection of what the venue
/// supports AND what the bot is configured to use.
///
/// This is what the preflight guard should consume.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvaluatedCapabilities {
    /// Whether linked/OCO orders are allowed.
    ///
    /// True only if BOTH `linked_orders_supported` AND
    /// `enable_linked_orders` are true.
    pub linked_orders_allowed: bool,
}

// ─── Evaluation function ────────────────────────────────────────────────

/// Evaluate capabilities by intersecting venue support with feature flags.
///
/// CONTRACT.md §1.4.4 B: "Reject ... unless `linked_orders_supported == true`
/// AND feature flag `ENABLE_LINKED_ORDERS_FOR_BOT == true`"
///
/// This function is deterministic and fail-closed: if either input is
/// restrictive, the output is restrictive.
pub fn evaluate_capabilities(
    venue: &VenueCapabilities,
    flags: &BotFeatureFlags,
) -> EvaluatedCapabilities {
    EvaluatedCapabilities {
        linked_orders_allowed: venue.linked_orders_supported && flags.enable_linked_orders,
    }
}
