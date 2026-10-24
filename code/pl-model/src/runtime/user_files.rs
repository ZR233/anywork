//! Host-owned projection of a reliable user file into its current execution workspace.
use futures::future::BoxFuture;
pub use pl_core::context::{ResourceError, ResourceReference};
use std::{fmt, future::Future, sync::Arc};
use tokio_util::sync::CancellationToken;

/// Original user bytes and display metadata, never a host storage path.
#[derive(Clone)]
pub struct UserFileRequest {
    pub thread_id: String,
    pub reference: ResourceReference,
    pub filename: String,
    pub bytes: Arc<[u8]>,
    pub cancellation: CancellationToken,
}

impl fmt::Debug for UserFileRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserFileRequest")
            .field("thread_id", &self.thread_id)
            .field("reference", &self.reference)
            .field("filename", &self.filename)
            .field("byte_len", &self.bytes.len())
            .field("cancelled", &self.cancellation.is_cancelled())
            .finish()
    }
}

/// A verified file in the bound Thread execution workspace. This is request-local only.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MaterializedUserFile {
    /// Workspace-relative POSIX path, not a local absolute path or SSH address.
    pub path: String,
}

/// Workspace failures never mean that the provider merely lacks a native capability.
#[derive(Debug, thiserror::Error)]
pub enum UserFileError {
    #[error("user file preparation cancelled")]
    Cancelled,
    #[error("user file integrity failed: {0}")]
    Integrity(#[from] ResourceError),
    #[error("user file conflicts with existing workspace content at {path}")]
    Conflict { path: String },
    #[error("user file workspace is unavailable: {source}")]
    Unavailable {
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
}

/// Narrow host capability; implementations own binding, permissions, integrity and atomic writes.
/// No provider or filesystem policy belongs in the model adapter.
pub trait UserFileMaterializer: Send + Sync + fmt::Debug + 'static {
    /// Verifies or atomically creates the complete original file before publishing its path.
    /// Cancellation must not publish a partially written file or a stale binding's path.
    fn materialize(
        &self,
        request: UserFileRequest,
    ) -> impl Future<Output = Result<MaterializedUserFile, UserFileError>> + Send;
}

trait ErasedMaterializer: Send + Sync + fmt::Debug {
    fn materialize(
        &self,
        request: UserFileRequest,
    ) -> BoxFuture<'_, Result<MaterializedUserFile, UserFileError>>;
}
impl<T: UserFileMaterializer> ErasedMaterializer for T {
    fn materialize(
        &self,
        request: UserFileRequest,
    ) -> BoxFuture<'_, Result<MaterializedUserFile, UserFileError>> {
        Box::pin(UserFileMaterializer::materialize(self, request))
    }
}

/// Shared host lease captured by execution, estimation and compaction of one model configuration.
#[derive(Debug, Clone)]
pub struct UserFileAccess(Arc<dyn ErasedMaterializer>);
impl UserFileAccess {
    pub fn new(materializer: impl UserFileMaterializer) -> Self {
        Self(Arc::new(materializer))
    }

    /// Projects verified originals through the configured host. No fallback hides host failures.
    ///
    /// # Errors
    /// Rejects cancellation, changed bytes, invalid paths and any materialization failure.
    pub async fn materialize(
        &self,
        request: UserFileRequest,
    ) -> Result<MaterializedUserFile, UserFileError> {
        request.reference.verify(&request.bytes)?;
        let cancellation = request.cancellation.clone();
        if cancellation.is_cancelled() {
            return Err(UserFileError::Cancelled);
        }
        let materialized = self.0.materialize(request).await?;
        if cancellation.is_cancelled() {
            return Err(UserFileError::Cancelled);
        }
        if materialized.path.is_empty()
            || materialized.path.starts_with('/')
            || materialized.path.contains(['\\', '\0', '\n', '\r'])
            || materialized
                .path
                .split('/')
                .any(|part| part.is_empty() || matches!(part, "." | "..") || part.contains(':'))
        {
            return Err(UserFileError::Unavailable {
                source: Box::new(std::io::Error::other(
                    "user file host returned a non-relative POSIX path",
                )),
            });
        }
        Ok(materialized)
    }
}
