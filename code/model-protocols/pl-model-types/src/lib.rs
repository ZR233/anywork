//! Shared model requests, results and endpoint contracts.
pub mod completion;
pub mod config;
mod headers;
mod member;
pub mod model;
mod prompt;
pub mod protocol;
pub use headers::headers;
pub use member::ModelMemberState;
pub use pl_protocol::{PureError, Result};
pub use prompt::PromptPrefixChangedReason;

pub mod discovery;
mod discovery_error;
mod discovery_policy;

pub mod files;

pub use pl_protocol::credential as authorization;
