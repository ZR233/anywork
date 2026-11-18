//! Shared model requests, results and endpoint contracts.
pub mod completion;
pub mod config;
mod headers;
mod member;
pub mod model;
mod prompt;
pub use headers::headers;
pub use member::ModelMemberState;
pub use pl_protocol::{PureError, Result};
pub use prompt::PromptPrefixChangedReason;

pub use pl_protocol::credential as authorization;

pub mod transport;

mod protocol_id;
pub use protocol_id::{InvalidProtocolId, ProtocolId};
