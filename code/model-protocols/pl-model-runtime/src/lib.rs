//! Shared model invocation and session execution.
pub mod runtime;
mod stream;
use pl_model_types::{completion, config, model};
mod protocol;
pub use pl_protocol::{PureError, Result};

#[cfg(feature = "live-examples")]
pub mod live_example;
