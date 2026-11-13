use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Reset one server belonging to the caller's current Thread LSP association.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadLspResetRequest {
    pub thread_id: String,
    pub binding_id: String,
    pub server_id: String,
}
