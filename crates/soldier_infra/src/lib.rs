#![forbid(unsafe_code)]

pub mod bootstrap;
pub mod config;
pub mod deribit;
pub mod store;
pub mod wal;

pub fn infra_bootstrapped() -> bool {
    soldier_core::crate_bootstrapped()
}
