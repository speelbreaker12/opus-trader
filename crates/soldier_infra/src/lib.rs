#![forbid(unsafe_code)]

pub mod config;
pub mod deribit;
pub mod store;

pub fn infra_bootstrapped() -> bool {
    soldier_core::crate_bootstrapped()
}
