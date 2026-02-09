//! Execution types, sizing logic, dispatch mapping, quantization, labeling, and preflight.

pub mod dispatch_map;
pub mod gate;
pub mod gates;
pub mod label;
pub mod order_size;
pub mod post_only_guard;
pub mod preflight;
pub mod pricer;
pub mod quantize;
pub mod tlsm;

pub use dispatch_map::{
    CONTRACTS_AMOUNT_MATCH_TOLERANCE, DispatchMapError, DispatchRequest, IntentClass,
    MismatchMetrics, ValidatedDispatch, map_to_dispatch, validate_and_dispatch,
};
pub use gate::{
    GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput, LiquidityGateMetrics,
    LiquidityGateRejectReason, LiquidityGateResult, evaluate_liquidity_gate,
};
pub use gates::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
};
pub use label::{
    LABEL_MAX_LEN, LabelError, LabelInput, ParsedLabel, decode_label, derive_gid12, derive_sid8,
    encode_label,
};
pub use order_size::{OrderSize, OrderSizeError, OrderSizeInput, build_order_size};
pub use post_only_guard::{PostOnlyInput, PostOnlyMetrics, PostOnlyResult, check_post_only};
pub use preflight::{
    OrderType, PreflightInput, PreflightMetrics, PreflightReject, PreflightResult, preflight_intent,
};
pub use pricer::{
    PricerInput, PricerMetrics, PricerRejectReason, PricerResult, PricerSide, compute_limit_price,
};
pub use quantize::{
    QuantizeConstraints, QuantizeError, QuantizeMetrics, QuantizedValues, Side, quantize,
};
pub use tlsm::{Tlsm, TlsmEvent, TlsmState, TransitionResult};
