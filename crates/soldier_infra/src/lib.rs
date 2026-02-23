#![forbid(unsafe_code)]

pub mod bootstrap;
pub mod config;
pub mod deribit;
pub mod store;
pub mod wal;

pub use bootstrap::{FullBootstrapConfig, FullBootstrapResult, bootstrap_full};
pub use config::{GateConfig, RawThresholdConfig, build_gate_config_from_raw};

pub fn infra_bootstrapped() -> bool {
    soldier_core::crate_bootstrapped()
}
