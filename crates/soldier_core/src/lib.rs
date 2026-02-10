#![forbid(unsafe_code)]

pub mod execution;
pub mod idempotency;
pub mod recovery;
pub mod risk;
pub mod venue;

pub fn crate_bootstrapped() -> bool {
    true
}
