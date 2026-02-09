//! Tests for venue capabilities matrix and feature flags per CONTRACT.md §1.4.4.
//!
//! AT-028, AT-004, AT-915.

use soldier_core::venue::{
    BotFeatureFlags, EvaluatedCapabilities, VenueCapabilities, evaluate_capabilities,
};

// ─── Defaults ───────────────────────────────────────────────────────────

#[test]
fn test_venue_default_linked_orders_not_supported() {
    let caps = VenueCapabilities::default();
    assert!(!caps.linked_orders_supported);
}

#[test]
fn test_deribit_v51_default_linked_orders_not_supported() {
    let caps = VenueCapabilities::deribit_v51_default();
    assert!(!caps.linked_orders_supported);
}

#[test]
fn test_feature_flags_default_linked_orders_disabled() {
    let flags = BotFeatureFlags::default();
    assert!(!flags.enable_linked_orders);
}

#[test]
fn test_feature_flags_default_flags_linked_orders_disabled() {
    let flags = BotFeatureFlags::default_flags();
    assert!(!flags.enable_linked_orders);
}

// ─── Default configuration → linked orders NOT allowed ──────────────────

#[test]
fn test_default_config_oco_not_supported() {
    let caps = VenueCapabilities::default();
    let flags = BotFeatureFlags::default();
    let eval = evaluate_capabilities(&caps, &flags);
    assert!(!eval.linked_orders_allowed);
}

// ─── Both flags true → linked orders allowed ────────────────────────────

#[test]
fn test_both_flags_true_linked_orders_allowed() {
    let caps = VenueCapabilities {
        linked_orders_supported: true,
    };
    let flags = BotFeatureFlags {
        enable_linked_orders: true,
    };
    let eval = evaluate_capabilities(&caps, &flags);
    assert!(eval.linked_orders_allowed);
}

// ─── Only venue supported → still not allowed ───────────────────────────

#[test]
fn test_only_venue_supported_not_allowed() {
    let caps = VenueCapabilities {
        linked_orders_supported: true,
    };
    let flags = BotFeatureFlags {
        enable_linked_orders: false,
    };
    let eval = evaluate_capabilities(&caps, &flags);
    assert!(!eval.linked_orders_allowed);
}

// ─── Only feature flag → still not allowed ──────────────────────────────

#[test]
fn test_only_feature_flag_not_allowed() {
    let caps = VenueCapabilities {
        linked_orders_supported: false,
    };
    let flags = BotFeatureFlags {
        enable_linked_orders: true,
    };
    let eval = evaluate_capabilities(&caps, &flags);
    assert!(!eval.linked_orders_allowed);
}

// ─── Neither flag → not allowed ─────────────────────────────────────────

#[test]
fn test_neither_flag_not_allowed() {
    let caps = VenueCapabilities {
        linked_orders_supported: false,
    };
    let flags = BotFeatureFlags {
        enable_linked_orders: false,
    };
    let eval = evaluate_capabilities(&caps, &flags);
    assert!(!eval.linked_orders_allowed);
}

// ─── Table-driven: all combinations ─────────────────────────────────────

#[test]
fn test_all_flag_combinations() {
    let cases = [
        // (venue_supported, flag_enabled, expected_allowed)
        (false, false, false),
        (false, true, false),
        (true, false, false),
        (true, true, true),
    ];
    for (venue_supported, flag_enabled, expected) in cases {
        let caps = VenueCapabilities {
            linked_orders_supported: venue_supported,
        };
        let flags = BotFeatureFlags {
            enable_linked_orders: flag_enabled,
        };
        let eval = evaluate_capabilities(&caps, &flags);
        assert_eq!(
            eval.linked_orders_allowed, expected,
            "venue={venue_supported}, flag={flag_enabled}: expected {expected}"
        );
    }
}

// ─── Determinism ────────────────────────────────────────────────────────

#[test]
fn test_deterministic_evaluation() {
    let caps = VenueCapabilities {
        linked_orders_supported: true,
    };
    let flags = BotFeatureFlags {
        enable_linked_orders: true,
    };
    let r1 = evaluate_capabilities(&caps, &flags);
    let r2 = evaluate_capabilities(&caps, &flags);
    assert_eq!(r1, r2);
}

// ─── EvaluatedCapabilities equality ─────────────────────────────────────

#[test]
fn test_evaluated_capabilities_eq() {
    let a = EvaluatedCapabilities {
        linked_orders_allowed: true,
    };
    let b = EvaluatedCapabilities {
        linked_orders_allowed: true,
    };
    assert_eq!(a, b);
}

#[test]
fn test_evaluated_capabilities_ne() {
    let a = EvaluatedCapabilities {
        linked_orders_allowed: true,
    };
    let b = EvaluatedCapabilities {
        linked_orders_allowed: false,
    };
    assert_ne!(a, b);
}
