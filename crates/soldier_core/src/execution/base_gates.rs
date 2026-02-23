//! Shared base gate evaluator (gates 1-6) for the execution chokepoint.
//!
//! Both `pipeline.rs` (CLOSE/HEDGE/CANCEL path) and `open_runtime.rs` (OPEN path)
//! call `evaluate_base_gates()` to eliminate dual-orchestration drift risk (Q1).
//!
//! Returns a `BaseGatesPassed` proof token that cannot be constructed externally,
//! guaranteeing that downstream gates only run after gates 1-6 pass.

use super::ChokeIntentClass;
use crate::execution::build_order_intent::GateStep;
use crate::execution::gate_outcome::GateOutcome;
use crate::execution::pipeline::QuantizePipelineInput;
use crate::execution::preflight::{PreflightInput, PreflightMetrics, preflight_intent};
use crate::execution::quantize::{QuantizeMetrics, QuantizedValues, quantize};
use crate::execution::reject_reason::RejectReasonCode;
use crate::risk::{
    FeeCacheSnapshot, FeeEvaluation, FeeMetrics, FeeStalenessConfig, RiskState,
    evaluate_fee_staleness,
};
use crate::venue::{
    BotFeatureFlags, ExpiryGuardInput, ExpiryGuardMetrics, LifecycleIntent, VenueCapabilities,
    bump_expiry_guard_reject, evaluate_capabilities, evaluate_expiry_guard,
};

// ─── Input ──────────────────────────────────────────────────────────────

/// Input for the shared base gates (1-6).
#[derive(Debug, Clone)]
pub struct BaseGatesInput<'a> {
    pub intent_class: ChokeIntentClass,
    pub risk_state: RiskState,
    pub preflight: PreflightInput<'a>,
    pub venue_capabilities: VenueCapabilities,
    pub bot_feature_flags: BotFeatureFlags,
    pub quantize: QuantizePipelineInput,
    /// AT-920 dispatch consistency pre-evaluated by the caller.
    /// The actual contracts/amount check happens in dispatch_map.rs
    /// and requires venue-specific data not available at this layer.
    pub dispatch_consistency_passed: bool,
    pub fee_snapshot: FeeCacheSnapshot,
    pub fee_config: FeeStalenessConfig,
    pub expiry_guard: Option<ExpiryGuardInput>,
}

// ─── Metrics ────────────────────────────────────────────────────────────

/// Metrics aggregated by `evaluate_base_gates()`.
#[derive(Debug, Default)]
pub struct BaseGatesMetrics {
    pub preflight: PreflightMetrics,
    pub quantize: QuantizeMetrics,
    pub fee: FeeMetrics,
    pub expiry: ExpiryGuardMetrics,
}

impl BaseGatesMetrics {
    pub fn new() -> Self {
        Self::default()
    }
}

// ─── Proof token ────────────────────────────────────────────────────────

/// Proof that gates 1-6 passed. Cannot be constructed outside this module.
///
/// Carries intermediate results needed by downstream gates (7-10).
/// Fields are private to prevent forgery — only `evaluate_base_gates()` creates this.
///
/// When `dispatch_auth_short_circuit` is true (CancelOnly or OPEN + !Healthy),
/// `quantized()` and `fee_evaluation()` return `None` because the chokepoint
/// will short-circuit before using them.
#[derive(Debug)]
#[non_exhaustive]
pub struct BaseGatesPassed {
    quantized: QuantizedValues,
    fee_evaluation: FeeEvaluation,
    gate_outcomes: Vec<GateOutcome>,
    dispatch_auth_short_circuit: bool,
    lifecycle_intent: LifecycleIntent,
}

impl BaseGatesPassed {
    /// Quantized order quantity from gate 3.
    /// Returns `None` when dispatch auth short-circuited (placeholder values).
    pub fn quantized(&self) -> Option<&QuantizedValues> {
        if self.dispatch_auth_short_circuit {
            None
        } else {
            Some(&self.quantized)
        }
    }

    /// Fee evaluation from gate 5.
    /// Returns `None` when dispatch auth short-circuited (placeholder values).
    pub fn fee_evaluation(&self) -> Option<&FeeEvaluation> {
        if self.dispatch_auth_short_circuit {
            None
        } else {
            Some(&self.fee_evaluation)
        }
    }

    /// Gate outcomes (all Allow) for gates that were evaluated.
    pub fn gate_outcomes(&self) -> &[GateOutcome] {
        &self.gate_outcomes
    }

    /// Whether dispatch auth short-circuited (CancelOnly or OPEN + !Healthy).
    pub fn dispatch_auth_short_circuit(&self) -> bool {
        self.dispatch_auth_short_circuit
    }

    /// The lifecycle intent derived from intent_class (authoritative).
    pub fn lifecycle_intent(&self) -> LifecycleIntent {
        self.lifecycle_intent
    }
}

// ─── Rejection ──────────────────────────────────────────────────────────

/// Rejection from base gates, preserving which gate failed and why.
#[derive(Debug)]
pub struct BaseGatesRejection {
    /// Which gate failed.
    pub gate: GateStep,
    /// Reason code for the failure.
    pub reason_code: RejectReasonCode,
    /// Partial gate outcomes up to the failure point.
    pub gate_outcomes: Vec<GateOutcome>,
}

// ─── Legacy conversion helpers ──────────────────────────────────────────

/// Convert a `BaseGatesPassed` to the legacy gate bools and reject codes
/// needed by the chokepoint.
pub struct BaseGatesLegacy {
    pub preflight_passed: bool,
    pub quantize_passed: bool,
    pub dispatch_consistency_passed: bool,
    pub fee_cache_passed: bool,
    pub expiry_guard_passed: bool,
    pub preflight_reject_code: Option<RejectReasonCode>,
    pub quantize_reject_code: Option<RejectReasonCode>,
    pub fee_cache_reject_code: Option<RejectReasonCode>,
    pub expiry_guard_reject_code: Option<RejectReasonCode>,
}

impl From<&BaseGatesPassed> for BaseGatesLegacy {
    fn from(_proof: &BaseGatesPassed) -> Self {
        // All gates passed
        Self {
            preflight_passed: true,
            quantize_passed: true,
            dispatch_consistency_passed: true,
            fee_cache_passed: true,
            expiry_guard_passed: true,
            preflight_reject_code: None,
            quantize_reject_code: None,
            fee_cache_reject_code: None,
            expiry_guard_reject_code: None,
        }
    }
}

impl From<&BaseGatesRejection> for BaseGatesLegacy {
    fn from(rejection: &BaseGatesRejection) -> Self {
        let mut legacy = Self {
            preflight_passed: true,
            quantize_passed: true,
            dispatch_consistency_passed: true,
            fee_cache_passed: true,
            expiry_guard_passed: true,
            preflight_reject_code: None,
            quantize_reject_code: None,
            fee_cache_reject_code: None,
            expiry_guard_reject_code: None,
        };
        // Legacy semantics are non-cascading: mark only the failed gate as failed,
        // leaving later gate bools as-is. Tests rely on this behavior.
        match rejection.gate {
            GateStep::DispatchAuth => {
                // DispatchAuth failure is handled by the chokepoint, not by gate bools.
                // Set all to true — the chokepoint will reject based on risk_state/intent_class.
            }
            GateStep::Preflight => {
                legacy.preflight_passed = false;
                legacy.preflight_reject_code = Some(rejection.reason_code);
            }
            GateStep::Quantize => {
                legacy.quantize_passed = false;
                legacy.quantize_reject_code = Some(rejection.reason_code);
            }
            GateStep::DispatchConsistency => {
                legacy.dispatch_consistency_passed = false;
            }
            GateStep::FeeCacheCheck => {
                legacy.fee_cache_passed = false;
                legacy.fee_cache_reject_code = Some(rejection.reason_code);
            }
            GateStep::ExpiryGuard => {
                legacy.expiry_guard_passed = false;
                legacy.expiry_guard_reject_code = Some(rejection.reason_code);
            }
            // Gates 7-10 are never produced by evaluate_base_gates().
            // Enumerate explicitly so adding a new GateStep variant triggers
            // a compile error rather than silently falling through.
            GateStep::LiquidityGate
            | GateStep::NetEdgeGate
            | GateStep::Pricer
            | GateStep::RecordedBeforeDispatch => {}
        }
        legacy
    }
}

// ─── Core evaluator ─────────────────────────────────────────────────────

/// Evaluate gates 1-6 in canonical order. Early-exit on first failure.
///
/// Gate order:
/// 1. DispatchAuth (RiskState + intent_class)
/// 2. Preflight (order type validation)
/// 3. Quantize (qty/price quantization)
/// 4. DispatchConsistency (AT-920 contracts/amount)
/// 5. FeeCacheCheck (fee cache staleness)
/// 6. ExpiryGuard (instrument expiry/delist)
pub fn evaluate_base_gates(
    input: &BaseGatesInput<'_>,
    metrics: &mut BaseGatesMetrics,
) -> Result<BaseGatesPassed, BaseGatesRejection> {
    let mut gate_outcomes: Vec<GateOutcome> = Vec::new();

    // Derive lifecycle intent from intent_class (authoritative source).
    let lifecycle_intent = match input.intent_class {
        ChokeIntentClass::Open => LifecycleIntent::Open,
        ChokeIntentClass::Close => LifecycleIntent::Close,
        ChokeIntentClass::Hedge => LifecycleIntent::Hedge,
        ChokeIntentClass::CancelOnly => LifecycleIntent::Cancel,
    };

    // ── Gate 1: DispatchAuth ────────────────────────────────────────────
    // Mirror chokepoint early-exit: CancelOnly bypasses all gates.
    // OPEN + !Healthy is rejected by the chokepoint's dispatch_auth gate.
    let dispatch_auth_short_circuit = input.intent_class == ChokeIntentClass::CancelOnly
        || (input.intent_class == ChokeIntentClass::Open && input.risk_state != RiskState::Healthy);

    if dispatch_auth_short_circuit {
        // CancelOnly: all gates pass, chokepoint handles approval.
        // OPEN + !Healthy: all gates set to true, chokepoint handles rejection.
        // In both cases, we return Ok with default quantized values since
        // the chokepoint will short-circuit before using them.
        // IMPORTANT: Callers MUST check `dispatch_auth_short_circuit` before
        // reading `quantized` or `fee_evaluation` — these are placeholder values.
        return Ok(BaseGatesPassed {
            quantized: QuantizedValues {
                qty_q: 0.0,
                limit_price_q: 0.0,
                qty_steps: 0,
                price_ticks: 0,
            },
            fee_evaluation: FeeEvaluation {
                staleness: crate::risk::FeeStaleness::Fresh,
                fee_rate_effective: 0.0,
                cache_age_s: None,
                risk_state: RiskState::Healthy,
            },
            gate_outcomes,
            dispatch_auth_short_circuit: true,
            lifecycle_intent,
        });
    }

    // ── Gate 2: Preflight ───────────────────────────────────────────────
    let evaluated_caps = evaluate_capabilities(&input.venue_capabilities, &input.bot_feature_flags);
    let mut preflight_input = input.preflight.clone();
    preflight_input.linked_orders_allowed = evaluated_caps.linked_orders_allowed;

    let preflight_result = preflight_intent(&preflight_input, &mut metrics.preflight);
    let preflight_outcome = GateOutcome::from_preflight(GateStep::Preflight, &preflight_result);
    let preflight_passed = preflight_outcome.is_allowed();
    gate_outcomes.push(preflight_outcome.clone());

    if !preflight_passed && let GateOutcome::Reject { reason_code, .. } = &preflight_outcome {
        return Err(BaseGatesRejection {
            gate: GateStep::Preflight,
            reason_code: *reason_code,
            gate_outcomes,
        });
    }

    // ── Gate 3: Quantize ────────────────────────────────────────────────
    let quantize_result = quantize(
        input.quantize.raw_qty,
        input.quantize.raw_limit_price,
        input.quantize.side,
        &input.quantize.constraints,
        &mut metrics.quantize,
    );
    let quantize_outcome = GateOutcome::from_quantize(GateStep::Quantize, &quantize_result);
    let quantize_passed = quantize_outcome.is_allowed();
    gate_outcomes.push(quantize_outcome.clone());

    if !quantize_passed && let GateOutcome::Reject { reason_code, .. } = &quantize_outcome {
        return Err(BaseGatesRejection {
            gate: GateStep::Quantize,
            reason_code: *reason_code,
            gate_outcomes,
        });
    }

    // Safe: quantize_passed is true here (early-return above handles the Err case).
    let Ok(quantized) = quantize_result else {
        // Defensive: should be unreachable since quantize_passed && !early-return
        // implies Ok. Fail-closed rather than panic.
        return Err(BaseGatesRejection {
            gate: GateStep::Quantize,
            reason_code: RejectReasonCode::TooSmallAfterQuantization,
            gate_outcomes,
        });
    };

    // ── Gate 4: DispatchConsistency ─────────────────────────────────────
    if !input.dispatch_consistency_passed {
        gate_outcomes.push(GateOutcome::Reject {
            gate: GateStep::DispatchConsistency,
            reason_code: RejectReasonCode::ContractsAmountMismatch,
        });
        return Err(BaseGatesRejection {
            gate: GateStep::DispatchConsistency,
            reason_code: RejectReasonCode::ContractsAmountMismatch,
            gate_outcomes,
        });
    }
    gate_outcomes.push(GateOutcome::Allow {
        gate: GateStep::DispatchConsistency,
    });

    // ── Gate 5: FeeCacheCheck ───────────────────────────────────────────
    let fee_eval = evaluate_fee_staleness(&input.fee_snapshot, &input.fee_config);
    let fee_outcome = GateOutcome::from_fee_eval(GateStep::FeeCacheCheck, &fee_eval);
    let fee_passed = fee_outcome.is_allowed();
    gate_outcomes.push(fee_outcome.clone());

    if !fee_passed {
        // Not collapsed into `if !fee_passed && let ...` because we must
        // record the metric unconditionally before extracting the reason code.
        metrics.fee.record_refresh_fail();
        if let GateOutcome::Reject { reason_code, .. } = &fee_outcome {
            return Err(BaseGatesRejection {
                gate: GateStep::FeeCacheCheck,
                reason_code: *reason_code,
                gate_outcomes,
            });
        }
    }

    // ── Gate 6: ExpiryGuard ─────────────────────────────────────────────
    if let Some(ref expiry_input) = input.expiry_guard {
        // Override the caller-provided intent with the authoritative one.
        let corrected_input = ExpiryGuardInput {
            intent: lifecycle_intent,
            ..*expiry_input
        };
        let expiry_result = evaluate_expiry_guard(&corrected_input, &mut metrics.expiry);
        let expiry_outcome = GateOutcome::from_expiry_guard(GateStep::ExpiryGuard, &expiry_result);
        let expiry_passed = expiry_outcome.is_allowed();
        gate_outcomes.push(expiry_outcome.clone());

        if !expiry_passed && let GateOutcome::Reject { reason_code, .. } = &expiry_outcome {
            return Err(BaseGatesRejection {
                gate: GateStep::ExpiryGuard,
                reason_code: *reason_code,
                gate_outcomes,
            });
        }
    } else if lifecycle_intent == LifecycleIntent::Open {
        // FAIL-CLOSED: missing expiry data blocks OPEN intents.
        // Bump both per-request struct counter and global static counter.
        metrics.expiry.record_reject();
        bump_expiry_guard_reject();
        gate_outcomes.push(GateOutcome::Reject {
            gate: GateStep::ExpiryGuard,
            reason_code: RejectReasonCode::InstrumentExpiredOrDelisted,
        });
        return Err(BaseGatesRejection {
            gate: GateStep::ExpiryGuard,
            reason_code: RejectReasonCode::InstrumentExpiredOrDelisted,
            gate_outcomes,
        });
    }
    // Non-OPEN with None expiry: allowed (no gate outcome needed)

    // ── All gates passed ────────────────────────────────────────────────
    Ok(BaseGatesPassed {
        quantized,
        fee_evaluation: fee_eval,
        gate_outcomes,
        dispatch_auth_short_circuit: false,
        lifecycle_intent,
    })
}
