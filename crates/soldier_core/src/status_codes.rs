//! Contract status/reason code surface generated from manifest.

mod generated {
    include!("status_codes_generated.rs");
}

pub use generated::*;
