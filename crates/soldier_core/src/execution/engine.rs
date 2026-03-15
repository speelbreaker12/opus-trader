//! Execution engine: single public orchestration entrypoint.
//!
//! Upgrade 1B end-state:
//! - public callers construct engine-level domain inputs
//! - legacy wiring types stay crate-internal
//! - `ExecutionDecision` is authoritative output

use super::build_order_intent::{ChokeIntentClass, GateStep};
use super::quantize::Side;
use super::reject_reason::{GateRejectCodes, RejectReasonCode};
use super::routing::{route_open, route_pipeline};
use super::wal_gate::RecordedBeforeDispatchGate;
use crate::risk::{
    ExposureBudgetInput, FeeCacheSnapshot, FeeStalenessConfig, MarginGateInput,
    PendingExposureBook, ReservationId, RiskState,
};
use crate::venue::{BotFeatureFlags, ExpiryGuardInput, InstrumentKind, VenueCapabilities};

#[derive(Debug, Clone)]
pub struct ExecutionBaseInput<'a> {
    pub risk_state: RiskState,
    pub preflight: ExecutionPreflightInput<'a>,
    pub venue_capabilities: VenueCapabilities,
    pub bot_feature_flags: BotFeatureFlags,
    pub quantize: QuantizeExecutionInput,
    pub dispatch_consistency_passed: bool,
    pub fee_snapshot: FeeCacheSnapshot,
    pub fee_config: FeeStalenessConfig,
    pub expiry_guard: Option<ExpiryGuardInput>,
}

#[derive(Debug, Clone)]
pub struct ExecutionPreflightInput<'a> {
    pub instrument_kind: InstrumentKind,
    pub order_type: ExecutionOrderType,
    pub has_trigger: bool,
    pub linked_order_type: Option<&'a str>,
    pub linked_orders_allowed: bool,
    pub post_only: Option<ExecutionPostOnlyInput>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionOrderType {
    Limit,
    Market,
    StopMarket,
    StopLimit,
}

#[derive(Debug, Clone, Copy)]
pub struct ExecutionPostOnlyInput {
    pub post_only: bool,
    pub side: Side,
    pub limit_price: f64,
    pub best_ask: Option<f64>,
    pub best_bid: Option<f64>,
}

#[derive(Debug, Clone, Copy)]
pub struct QuantizeExecutionInput {
    pub raw_qty: f64,
    pub raw_limit_price: f64,
    pub side: Side,
    pub tick_size: f64,
    pub amount_step: f64,
    pub min_amount: f64,
}

#[derive(Debug, Clone)]
pub struct OpenExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
    pub gate_reject_codes: GateRejectCodes,
    pub current_delta: f64,
    pub delta_impact_est: f64,
    pub liquidity: LiquidityExecutionInput,
    pub net_edge: NetEdgeExecutionInput,
    pub inventory_skew: InventorySkewExecutionInput,
    pub pricer: PricerExecutionInput,
    pub exposure_budget: ExposureBudgetInput,
    pub margin_gate: MarginGateInput,
    pub reservation_id: ReservationId,
    pub instrument_id: String,
}

#[derive(Debug, Clone)]
pub struct CloseExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
}

#[derive(Debug, Clone)]
pub struct HedgeExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
}

#[derive(Debug, Clone)]
pub struct CancelExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
}

#[derive(Debug, Clone)]
pub struct LiquidityExecutionInput {
    pub order_qty: f64,
    pub side: Side,
    pub is_marketable: bool,
    pub l2_snapshot: Option<ExecutionL2BookSnapshot>,
    pub now_ms: u64,
    pub l2_book_snapshot_max_age_ms: u64,
    pub max_slippage_bps: f64,
}

#[derive(Debug, Clone)]
pub struct ExecutionL2BookSnapshot {
    pub asks: Vec<ExecutionL2Level>,
    pub bids: Vec<ExecutionL2Level>,
    pub timestamp_ms: u64,
}

#[derive(Debug, Clone, Copy)]
pub struct ExecutionL2Level {
    pub price: f64,
    pub qty: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct NetEdgeExecutionInput {
    pub gross_edge_usd: Option<f64>,
    pub fee_usd: Option<f64>,
    pub expected_slippage_usd: Option<f64>,
    pub min_edge_usd: Option<f64>,
}

#[derive(Debug, Clone, Copy)]
pub struct InventorySkewExecutionInput {
    pub current_delta: f64,
    pub pending_delta: f64,
    pub delta_limit: Option<f64>,
    pub side: Side,
    pub min_edge_usd: f64,
    pub net_edge_usd: f64,
    pub limit_price: f64,
    pub tick_size: f64,
    pub inventory_skew_k: f64,
    pub inventory_skew_tick_penalty_max: u8,
}

#[derive(Debug, Clone, Copy)]
pub struct PricerExecutionInput {
    pub fair_price: f64,
    pub gross_edge_usd: f64,
    pub min_edge_usd: f64,
    pub fee_estimate_usd: f64,
    pub expected_slippage_usd: f64,
    pub qty: f64,
    pub side: Side,
}

#[derive(Debug, Clone)]
#[allow(clippy::large_enum_variant)]
pub enum ExecutionInput<'a> {
    Open(OpenExecutionInput<'a>),
    Close(CloseExecutionInput<'a>),
    Hedge(HedgeExecutionInput<'a>),
    Cancel(CancelExecutionInput<'a>),
}

#[derive(Debug, Clone, PartialEq)]
pub enum ExecutionDecision {
    Approved(ApprovedExecution),
    Rejected(ExecutionRejection),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ApprovedExecution {
    pub effective_risk_state: RiskState,
    pub pending_reservation_id: Option<ReservationId>,
    pub adjusted_min_edge_usd: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExecutionRejection {
    pub code: RejectReasonCode,
    pub step: ExecutionStep,
    pub detail: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionStep {
    Runtime(RuntimeStep),
    Gate(GateStep),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeStep {
    BaseGates,
    PendingExposure,
    GlobalExposureBudget,
    InventorySkew,
    MarginGate,
    Assembly,
}

#[derive(Default)]
pub struct ExecutionRuntime<'a> {
    pub wal_gate: Option<&'a mut dyn RecordedBeforeDispatchGate>,
    pub pending_exposure_book: Option<&'a PendingExposureBook>,
}

impl<'a> ExecutionRuntime<'a> {
    pub fn new(
        wal_gate: Option<&'a mut dyn RecordedBeforeDispatchGate>,
        pending_exposure_book: Option<&'a PendingExposureBook>,
    ) -> Self {
        Self {
            wal_gate,
            pending_exposure_book,
        }
    }
}

pub struct ExecutionEngine;

impl ExecutionEngine {
    pub fn new() -> Self {
        Self
    }

    pub fn decide<'input, 'runtime>(
        &self,
        input: &ExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        match input {
            ExecutionInput::Open(open) => self.decide_open(open, runtime),
            ExecutionInput::Close(close) => {
                self.decide_pipeline(&close.base, ChokeIntentClass::Close, runtime)
            }
            ExecutionInput::Hedge(hedge) => {
                self.decide_pipeline(&hedge.base, ChokeIntentClass::Hedge, runtime)
            }
            ExecutionInput::Cancel(cancel) => {
                self.decide_pipeline(&cancel.base, ChokeIntentClass::CancelOnly, runtime)
            }
        }
    }

    #[deprecated(
        since = "0.2.0",
        note = "Use decide(); evaluate() is a compatibility alias."
    )]
    pub fn evaluate<'input, 'runtime>(
        &self,
        input: &ExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        self.decide(input, runtime)
    }

    fn decide_open<'input, 'runtime>(
        &self,
        input: &OpenExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        route_open(input, runtime)
    }

    fn decide_pipeline<'input, 'runtime>(
        &self,
        input: &ExecutionBaseInput<'input>,
        intent_class: ChokeIntentClass,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        route_pipeline(input, intent_class, runtime)
    }
}

impl Default for ExecutionEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
#[path = "engine_decision_tests.rs"]
mod engine_decision_tests;
