//! Reliable user originals projected only into the currently bound Thread execution world.
use super::{StudioThreadFactory, tool_bindings::ToolBinding};
use pl_model::runtime::{
    MaterializedUserFile, UserFileAccess, UserFileError, UserFileMaterializer, UserFileRequest,
};
use pl_tool::{
    workspace::WorkspaceMutability,
    workspace_file::{
        LocalWorkspaceFileBackend, WorkspaceFileBackend, WorkspaceFileReadBytesRequest,
        WorkspaceFileStat, WorkspaceFileStatRequest,
    },
};
use std::sync::Arc;

impl StudioThreadFactory {
    /// Resolves the physical binding for each request, so deferred model refresh does not retain
    /// stale SSH leases or a previous activation's workspace. This grants only session uploads.
    pub(crate) fn user_file_access(&self) -> UserFileAccess {
        UserFileAccess::new(AttachmentFiles(self.clone()))
    }
}

#[derive(Debug, Clone)]
struct AttachmentFiles(StudioThreadFactory);

impl UserFileMaterializer for AttachmentFiles {
    async fn materialize(
        &self,
        request: UserFileRequest,
    ) -> Result<MaterializedUserFile, UserFileError> {
        request.reference.verify(&request.bytes)?;
        let binding = self.binding(&request.thread_id)?;
        let _operation = tokio::select! {
            biased;
            () = request.cancellation.cancelled() => return Err(UserFileError::Cancelled),
            () = binding.lifetime.cancellation.cancelled() => return Err(UserFileError::Cancelled),
            guard = binding.lifetime.uploads.lock() => guard,
        };
        self.ensure_current(&request, &binding)?;
        // Cancellation drops a remote transfer lease; the existing backend owns staging and
        // atomic commit. A local worker may finish a complete file, but no cancelled request
        // publishes its path and no incomplete target is ever installed.
        let result = tokio::select! {
            biased;
            () = request.cancellation.cancelled() => return Err(UserFileError::Cancelled),
            () = binding.lifetime.cancellation.cancelled() => return Err(UserFileError::Cancelled),
            result = materialize(&binding, &request) => result,
        }?;
        self.publish(&request, &binding, result)
    }
}

impl AttachmentFiles {
    fn binding(&self, thread_id: &str) -> Result<ToolBinding, UserFileError> {
        let bindings = self
            .0
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let binding = bindings.get(thread_id).ok_or_else(|| {
            unavailable(std::io::Error::other(
                "Thread execution binding is unavailable",
            ))
        })?;
        if binding.target_invalidated {
            return Err(unavailable(std::io::Error::other(
                "Thread execution target changed; reactivate this Thread",
            )));
        }
        Ok(binding.clone())
    }

    /// Used before IO and at final publication. Cancellation, target invalidation and the
    /// physical/authorization identity share the binding-map synchronization boundary.
    fn ensure_current(
        &self,
        request: &UserFileRequest,
        expected: &ToolBinding,
    ) -> Result<(), UserFileError> {
        let bindings = self
            .0
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if request.cancellation.is_cancelled() || expected.lifetime.cancellation.is_cancelled() {
            return Err(UserFileError::Cancelled);
        }
        let current = bindings.get(&request.thread_id).ok_or_else(|| {
            unavailable(std::io::Error::other(
                "Thread execution binding is unavailable",
            ))
        })?;
        if current.lifetime.cancellation.is_cancelled() {
            return Err(UserFileError::Cancelled);
        }
        if current.target_invalidated || !current.file_execution.matches(&expected.file_execution) {
            return Err(unavailable(std::io::Error::other(
                "Thread execution binding changed during user file preparation",
            )));
        }
        Ok(())
    }

    /// The final check linearizes path publication with execution/authorization replacement,
    /// SSH invalidation and shutdown. It never awaits an installation/core command.
    fn publish(
        &self,
        request: &UserFileRequest,
        expected: &ToolBinding,
        result: MaterializedUserFile,
    ) -> Result<MaterializedUserFile, UserFileError> {
        self.ensure_current(request, expected)?;
        Ok(result)
    }
}

async fn materialize(
    binding: &ToolBinding,
    request: &UserFileRequest,
) -> Result<MaterializedUserFile, UserFileError> {
    let files = binding
        .workspace
        .workspace()
        .session_files()
        .ok_or_else(|| unavailable(std::io::Error::other("Thread has no bound session files")))?;
    let digest = request
        .reference
        .content_digest()
        .strip_prefix("sha256:")
        .filter(|digest| digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit()))
        .ok_or_else(|| {
            unavailable(std::io::Error::other(
                "unsupported user file content identity",
            ))
        })?;
    let relative = files
        .uploads()
        .join(digest.to_ascii_lowercase())
        .join(safe_filename(&request.filename));
    let path = relative.to_string_lossy().replace('\\', "/");
    let backend = match &binding.remote {
        Some(host) => Files::Remote(host.files.clone()),
        // This narrow infrastructure port can write only the constructed uploads path. It
        // does not alter business writablePaths or grant host access to tools or commands.
        None => Files::Local(
            LocalWorkspaceFileBackend::new_with_io_owner(
                binding.workspace.root().to_owned(),
                false,
                binding.lifetime.file_io.clone(),
            )
            .await
            .map_err(unavailable)?
            .with_create_owner(binding.lifetime.file_creates.clone()),
        ),
    };
    if let Some(stat) = backend.stat(&path).await? {
        verify_copy(&backend, &path, stat, request).await?;
    } else {
        if binding.workspace.workspace().mutability() == WorkspaceMutability::ReadOnly {
            return Err(unavailable(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "Thread workspace is read-only; cannot materialize a user file",
            )));
        }
        backend.write(&path, request.bytes.clone()).await?;
        let stat = backend.stat(&path).await?.ok_or_else(|| {
            unavailable(std::io::Error::other(
                "materialized user file is missing after atomic write",
            ))
        })?;
        verify_copy(&backend, &path, stat, request).await?;
    }
    Ok(MaterializedUserFile { path })
}

async fn verify_copy(
    backend: &Files,
    path: &str,
    stat: WorkspaceFileStat,
    request: &UserFileRequest,
) -> Result<(), UserFileError> {
    if !stat.is_file || stat.is_dir || stat.len != Some(request.reference.byte_len()) {
        return Err(UserFileError::Conflict {
            path: path.to_owned(),
        });
    }
    let bytes = backend.read(path, request.bytes.len()).await?;
    if request.reference.verify(&bytes).is_err() {
        return Err(UserFileError::Conflict {
            path: path.to_owned(),
        });
    }
    Ok(())
}

// Prefix avoids Windows device names. ASCII and a byte bound make one safe component on
// every execution platform; the original display name remains in typed durable metadata.
fn safe_filename(filename: &str) -> String {
    let safe: String = filename
        .chars()
        .take(100)
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '.' | '-' | '_') {
                character
            } else {
                '_'
            }
        })
        .collect();
    let safe = safe.trim_matches('.');
    if safe.is_empty() {
        "file-attachment".into()
    } else {
        format!("file-{safe}")
    }
}

enum Files {
    Local(LocalWorkspaceFileBackend),
    Remote(pl_tool::remote::RemoteWorkspaceFileBackend),
}
impl Files {
    async fn stat(&self, path: &str) -> Result<Option<WorkspaceFileStat>, UserFileError> {
        match self {
            Self::Local(backend) => backend
                .stat_optional(WorkspaceFileStatRequest {
                    path: path.into(),
                    cwd: None,
                })
                .await
                .map_err(unavailable),
            Self::Remote(backend) => backend
                .stat_optional(path.into(), None)
                .await
                .map_err(unavailable),
        }
    }
    async fn read(&self, path: &str, max_bytes: usize) -> Result<Vec<u8>, UserFileError> {
        let request = WorkspaceFileReadBytesRequest {
            path: path.into(),
            cwd: None,
            max_bytes,
        };
        match self {
            Self::Local(backend) => backend.read_bytes(request).await,
            Self::Remote(backend) => backend.read_bytes(request).await,
        }
        .map_err(unavailable)
    }
    async fn write(&self, path: &str, bytes: Arc<[u8]>) -> Result<(), UserFileError> {
        match self {
            Self::Local(backend) => backend.create_bytes_atomic(path.into(), None, bytes).await,
            Self::Remote(backend) => backend.create_bytes_atomic(path.into(), None, &bytes).await,
        }
        .map_err(unavailable)
    }
}

fn unavailable(error: impl std::error::Error + Send + Sync + 'static) -> UserFileError {
    UserFileError::Unavailable {
        source: Box::new(error),
    }
}
