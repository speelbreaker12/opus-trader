//! Execution types, sizing logic, and dispatch mapping.

pub mod dispatch_map;
pub mod order_size;

pub use dispatch_map::{
    CONTRACTS_AMOUNT_MATCH_TOLERANCE, DispatchMapError, DispatchRequest, IntentClass,
    MismatchMetrics, ValidatedDispatch, map_to_dispatch, validate_and_dispatch,
};
pub use order_size::{OrderSize, OrderSizeError, OrderSizeInput, build_order_size};
