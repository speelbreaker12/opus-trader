#![forbid(unsafe_code)]

pub mod execution;
pub mod idempotency;
pub mod recovery;
pub mod risk;
pub mod venue;

#[cfg(test)]
mod test_multicycle_aftercare;

pub fn crate_bootstrapped() -> bool {
    true
}
