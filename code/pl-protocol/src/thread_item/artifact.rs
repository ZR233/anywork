//! Explicit conversation publications, independent of workspace paths and external recipients.

use serde::{Deserialize, Serialize};

/// Product representation of an archived original's exact resource identity.
///
/// Studio converts a validated core resource reference into this DTO. Possession of the DTO,
/// resource id or digest does not authorize reading bytes or publishing them to another Thread.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadArtifactResource {
    pub id: String,
    /// Canonical reliable-resource digest, encoded as `sha256:<64hex>`.
    pub content_digest: String,
    /// Exact original length; zero-byte originals are valid publications.
    pub byte_len: u64,
    pub media_type: String,
}

/// An explicit publication committed by this Thread's trusted publishing tool.
///
/// The enclosing [`super::ThreadItem`] owns Thread, Turn, order and revision. This payload has
/// no source path or external target. Its terminal timestamp records publication, not history
/// durability or platform acceptance; those facts remain independently observable.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadPublicArtifactItem {
    pub publication_id: String,
    pub tool_call_id: String,
    pub display_name: String,
    pub resource: ThreadArtifactResource,
    pub published_at: i64,
}
