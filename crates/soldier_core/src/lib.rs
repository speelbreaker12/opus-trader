#![forbid(unsafe_code)]

pub mod execution;
pub mod risk;
pub mod venue;

pub fn crate_bootstrapped() -> bool {
    true
}
