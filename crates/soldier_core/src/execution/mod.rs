//! Execution types and sizing logic.

pub mod order_size;

pub use order_size::{OrderSize, OrderSizeError, OrderSizeInput, build_order_size};
