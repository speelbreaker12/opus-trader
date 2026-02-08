#![forbid(unsafe_code)]

pub fn infra_bootstrapped() -> bool {
    soldier_core::crate_bootstrapped()
}
