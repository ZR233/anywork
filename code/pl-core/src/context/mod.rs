//! Thread-owned context semantics and producer-owned opaque content.

pub use serde_json::Value;

mod content;
mod payload;

pub use content::{
    AgentMessageKind, ContextContent, ContextError, ContextRecord, ContextSnapshot, ContextSource,
    ResourceError, ResourceReference,
};
pub use payload::{OpaquePayload, PayloadError};

mod resource;
pub use resource::{ResourceAccess, ResourceReadError, ResourceReader};

mod hash;
pub use hash::{canonical_json_hash, content_hash};
