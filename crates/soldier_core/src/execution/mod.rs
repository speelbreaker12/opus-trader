//! Execution types, sizing logic, and dispatch mapping.

pub mod dispatch_map;
pub mod order_size;

pub use dispatch_map::{DispatchMapError, DispatchRequest, IntentClass, map_to_dispatch};
pub use order_size::{OrderSize, OrderSizeError, OrderSizeInput, build_order_size};
