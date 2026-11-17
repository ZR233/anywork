//! Workspace ownership shared by directory consumers.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// A standalone owner retains normal Thread storage without being a user project.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceKind {
    Project,
    Standalone,
}
