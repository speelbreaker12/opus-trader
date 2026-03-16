#![forbid(unsafe_code)]

mod api;
mod bootstrap;
mod config;
mod deribit;
mod store;
mod wal;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use api::*;

pub fn infra_bootstrapped() -> bool {
    soldier_core::crate_bootstrapped()
}
