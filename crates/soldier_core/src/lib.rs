#![forbid(unsafe_code)]

mod telemetry;

pub mod execution;
pub mod idempotency;
pub mod recovery;
pub mod risk;
pub mod status_codes;
pub mod venue;

pub fn crate_bootstrapped() -> bool {
    true
}
