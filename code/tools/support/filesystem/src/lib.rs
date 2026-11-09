//! Shared file-domain values and narrow, host-supplied filesystem capabilities.
//!
//! Implementations retain path confinement, authorization and physical mutation
//! semantics. Tools do not obtain a host context or an unrestricted filesystem.

use std::{error::Error as StdError, future::Future};

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize, schemars::JsonSchema,
)]
#[serde(rename_all = "lowercase")]
pub enum WriteMode {
    Create,
    Overwrite,
    Append,
}

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PathInput {
    /// Workspace-relative or permitted absolute path.
    pub path: String,
}

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CopyMoveInput {
    /// Existing source path.
    pub from: String,
    /// Destination path.
    pub to: String,
    /// Behavior when the destination already exists.
    pub collision: PathCollision,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum PathCollision {
    FailIfExists,
    Overwrite,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileStat {
    pub path: String,
    pub is_file: bool,
    pub is_dir: bool,
    pub len: Option<u64>,
    pub readonly: Option<bool>,
    pub modified_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatRequest {
    pub path: String,
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WriteRequest {
    pub mode: WriteMode,
    pub path: String,
    pub cwd: Option<String>,
    pub content: String,
}

pub trait StatBackend: Send + Sync {
    type Error: StdError + Send + Sync + 'static;
    /// Absence means a missing path, never denied access or failed transport.
    fn stat_optional(
        &self,
        request: StatRequest,
    ) -> impl Future<Output = Result<Option<FileStat>, Self::Error>> + Send;
}

pub trait WriteBackend: Send + Sync {
    type Error: StdError + Send + Sync + 'static;
    /// Create is exclusive, overwrite replaces, append creates or appends.
    /// Errors may follow partial writes; implementations must not claim rollback.
    fn write_text(
        &self,
        request: WriteRequest,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

/// File mutation primitives over host-authorized, opaque resolved paths.
///
/// Resolution and writable checks retain the host's path/symlink policy.
/// Primitive mutations retain backend-specific replacement and notification
/// semantics; tools own delete-mode and destination-collision validation.
pub trait MutationBackend: Send + Sync {
    type Error: StdError + Send + Sync + 'static;
    type Path: Send + Sync;

    fn resolve_existing(
        &self,
        path: &str,
    ) -> impl Future<Output = Result<Self::Path, Self::Error>> + Send;
    fn resolve_for_write(
        &self,
        path: &str,
    ) -> impl Future<Output = Result<Self::Path, Self::Error>> + Send;
    fn ensure_writable(&self, path: &Self::Path) -> Result<(), Self::Error>;
    fn display_path(&self, path: &Self::Path) -> String;
    fn diagnostic_path(&self, path: &Self::Path) -> String;
    fn is_directory(
        &self,
        path: &Self::Path,
    ) -> impl Future<Output = Result<bool, Self::Error>> + Send;
    fn exists(&self, path: &Self::Path) -> impl Future<Output = Result<bool, Self::Error>> + Send;
    fn create_directory(
        &self,
        path: &Self::Path,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn remove_file(
        &self,
        path: &Self::Path,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn remove_directory(
        &self,
        path: &Self::Path,
        recursive: bool,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn copy(
        &self,
        from: &Self::Path,
        to: &Self::Path,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
    fn rename(
        &self,
        from: &Self::Path,
        to: &Self::Path,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

#[derive(Debug, thiserror::Error)]
pub enum MutationError<E: StdError + Send + Sync + 'static> {
    #[error("{0}")]
    Backend(#[source] E),
    #[error("delete mode requires a directory but path is a file")]
    RequiresDirectory,
    #[error("delete mode file cannot delete a directory")]
    RequiresFile,
    #[error(
        "target '{0}' already exists; use overwrite mode or apply_patch for an intentional replacement"
    )]
    DestinationExists(String),
}
