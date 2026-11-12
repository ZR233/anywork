//! Workspace policy over one immutable executor and target root.
mod directory;
mod download;
mod patch;
mod policy;
use super::*;
use crate::workspace::{WorkspaceInstructionDocument, WorkspaceInstructions};
pub use directory::WorkspaceDirectoryReader;
pub use download::WorkspaceDownloadError;
use pl_protocol::Result;
use pl_remote_helper::{ExecutionError, Executor, TargetPath};
use std::path::PathBuf;

#[derive(Debug, Clone, thiserror::Error)]
pub enum WorkspaceFileError {
    #[error(transparent)]
    Execution(#[from] ExecutionError),
    /// An attempted removal can have changed its target even when its final reply is lost.
    #[error("removal result is unconfirmed: {0}")]
    Removal(#[source] ExecutionError),
    #[error("{0}")]
    Policy(String),
}
impl WorkspaceFileError {
    pub fn is_not_found(&self) -> bool {
        match self {
            Self::Execution(ExecutionError::TargetIo(error)) => {
                error.kind == pl_remote_helper::IoErrorKind::NotFound
            }
            Self::Execution(ExecutionError::Io { source, .. }) => {
                source.kind() == std::io::ErrorKind::NotFound
            }
            _ => false,
        }
    }
}
pub(crate) fn file_error(error: impl std::fmt::Display) -> pl_protocol::PureError {
    tool_error("file", error)
}

#[derive(Debug, Clone)]
pub struct ExecutorWorkspaceFileBackend {
    executor: Executor,
    root: TargetPath,
    allow_workspace_escape: bool,
    workspace: Option<ToolWorkspace>,
}
impl ExecutorWorkspaceFileBackend {
    /// Binds an already canonical target root selected by the host.
    pub fn new(executor: Executor, root: &str) -> std::result::Result<Self, WorkspaceFileError> {
        Ok(Self {
            root: executor.path(root)?,
            executor,
            allow_workspace_escape: false,
            workspace: None,
        })
    }
    pub async fn local(root: PathBuf, allow_workspace_escape: bool) -> Result<Self> {
        let executor = Executor::local().map_err(file_error)?;
        let path = executor
            .path(
                root.to_str()
                    .ok_or_else(|| file_error("workspace path is not UTF-8"))?,
            )
            .map_err(file_error)?;
        let root = executor
            .fs()
            .canonicalize(&path)
            .await
            .map_err(file_error)?;
        let mut backend = Self::new(executor, root.as_str()).map_err(file_error)?;
        backend.allow_workspace_escape = allow_workspace_escape;
        Ok(backend)
    }
    pub async fn confined(workspace: ToolWorkspace) -> Result<Self> {
        Ok(Self::local(workspace.root().to_owned(), false)
            .await?
            .with_workspace(workspace))
    }
    pub fn with_workspace(mut self, workspace: ToolWorkspace) -> Self {
        self.workspace = Some(workspace);
        self
    }
    pub fn executor(&self) -> &Executor {
        &self.executor
    }
    pub fn canonical_path(&self) -> &str {
        self.root.as_str()
    }
    pub(crate) fn binding_identity(&self) -> String {
        format!("executor:{:?}:{}", self.executor.id(), self.root.as_str())
    }
    pub fn is_same_binding(&self, other: &Self) -> bool {
        self.executor.id() == other.executor.id() && self.root == other.root
    }
    pub(crate) fn path_request(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> std::result::Result<TargetPath, WorkspaceFileError> {
        let base = self.executor.join_path(
            &self.root,
            cwd.as_deref().filter(|s| !s.is_empty()).unwrap_or("."),
        )?;
        Ok(self.executor.join_path(&base, &path)?)
    }
    pub(crate) fn display_path(&self, path: &TargetPath) -> String {
        let path = self
            .executor
            .relative_path(&self.root, path)
            .ok()
            .flatten()
            .unwrap_or_else(|| path.as_str().into());
        if self.executor.target_info().os == "windows" {
            path.replace('\\', "/")
        } else {
            path
        }
    }
    async fn notify_changed(&self, path: &TargetPath) {
        if let Some(workspace) = &self.workspace {
            workspace
                .notify_changed(std::path::Path::new(path.as_str()))
                .await;
        }
    }
    async fn notify_deleted(&self, path: &TargetPath) {
        if let Some(workspace) = &self.workspace {
            workspace
                .notify_deleted(std::path::Path::new(path.as_str()))
                .await;
        }
    }
    /// Resolves a tool locator on its target under the same invocation policy as file reads.
    pub async fn resolve_query_path(
        &self,
        path: &str,
        require_file: bool,
    ) -> std::result::Result<TargetPath, WorkspaceFileError> {
        let target = self
            .bound(self.path_request(path.into(), None)?, true)
            .await?;
        if require_file
            && !self
                .executor
                .fs()
                .metadata(&target)
                .await?
                .is_some_and(|metadata| metadata.is_file)
        {
            return Err(WorkspaceFileError::Policy(
                "query path is not an existing regular file".into(),
            ));
        }
        Ok(target)
    }
    pub async fn inspect_path(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> std::result::Result<Option<WorkspaceFileStat>, WorkspaceFileError> {
        let path = self.bound(self.path_request(path, cwd)?, true).await?;
        Ok(self
            .executor
            .fs()
            .metadata(&path)
            .await?
            .map(|stat| WorkspaceFileStat {
                path: self.display_path(&path),
                is_file: stat.is_file,
                is_dir: stat.is_dir,
                len: stat.is_file.then_some(stat.len),
                readonly: Some(stat.readonly),
                modified_at: stat.modified_at,
            }))
    }
    pub async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        let path = self
            .bound(self.path_request(path, cwd).map_err(file_error)?, true)
            .await
            .map_err(file_error)?;
        self.ensure_writable(&path).await?;
        self.executor
            .fs()
            .create_dir(&path, true)
            .await
            .map_err(file_error)
    }
    pub async fn write_bytes_atomic(
        &self,
        path: String,
        cwd: Option<String>,
        body: &[u8],
    ) -> Result<()> {
        let path = self.path_request(path, cwd).map_err(file_error)?;
        self.copy_file_from(
            path.as_str(),
            crate::workspace::WriteMode::Overwrite,
            body.len() as u64,
            &mut &*body,
        )
        .await
        .map(|_| ())
    }
    pub async fn remove_path(
        &self,
        path: String,
        cwd: Option<String>,
        recursive: bool,
    ) -> std::result::Result<(), WorkspaceFileError> {
        let path = self.bound(self.path_request(path, cwd)?, false).await?;
        self.ensure_writable(&path)
            .await
            .map_err(|error| WorkspaceFileError::Policy(error.to_string()))?;
        if self.executor.fs().symlink_metadata(&path).await?.is_none() {
            return Ok(());
        }
        self.executor
            .fs()
            .remove(&path, recursive)
            .await
            .map_err(WorkspaceFileError::Removal)?;
        self.notify_deleted(&path).await;
        Ok(())
    }
    pub async fn rename_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
        collision: pl_tool_filesystem::PathCollision,
    ) -> Result<()> {
        let source = self
            .bound(
                self.path_request(source, cwd.clone()).map_err(file_error)?,
                false,
            )
            .await
            .map_err(file_error)?;
        let target = self
            .bound(self.path_request(target, cwd).map_err(file_error)?, false)
            .await
            .map_err(file_error)?;
        self.ensure_writable(&source).await?;
        self.ensure_writable(&target).await?;
        self.create_parent(&target).await?;
        self.executor
            .fs()
            .rename(&source, &target, target_collision(collision))
            .await
            .map_err(file_error)?;
        self.notify_deleted(&source).await;
        self.notify_changed(&target).await;
        Ok(())
    }
    async fn create_parent(&self, target: &TargetPath) -> Result<()> {
        if let Some(parent) = self.executor.parent_path(target).map_err(file_error)? {
            self.executor
                .fs()
                .create_dir(&parent, true)
                .await
                .map_err(file_error)?;
        }
        Ok(())
    }
    pub async fn copy_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
        recursive: bool,
        collision: pl_tool_filesystem::PathCollision,
    ) -> Result<()> {
        let source = self
            .bound(
                self.path_request(source, cwd.clone()).map_err(file_error)?,
                true,
            )
            .await
            .map_err(file_error)?;
        let target = self
            .bound(self.path_request(target, cwd).map_err(file_error)?, true)
            .await
            .map_err(file_error)?;
        self.ensure_writable(&target).await?;
        self.create_parent(&target).await?;
        self.executor
            .fs()
            .copy_path(&source, &target, recursive, target_collision(collision))
            .await
            .map_err(file_error)?;
        self.notify_changed(&target).await;
        Ok(())
    }
}

impl WorkspaceFileBackend for ExecutorWorkspaceFileBackend {
    async fn apply_patch(
        &self,
        cwd: String,
        patch: &str,
    ) -> std::result::Result<pl_patch::PatchReport, pl_patch::PatchFailure> {
        self.execute_patch(cwd, patch).await
    }
    fn for_grant(&self, grant: &pl_core::tool::execution_policy::ExecutionGrant) -> Option<Self> {
        if !grant.contains(crate::approval::HOST_WORKSPACE_ACCESS)
            || !self
                .workspace
                .as_ref()
                .is_some_and(|w| w.workspace().boundary().allows_host_paths())
        {
            return None;
        }
        let mut backend = self.clone();
        backend.allow_workspace_escape = true;
        Some(backend)
    }
    async fn default_cwd(&self) -> Result<String> {
        Ok(".".into())
    }
    async fn local_file_path(&self, request: WorkspaceFileStatRequest) -> Result<Option<String>> {
        if !self.executor.is_local() {
            return Ok(None);
        }
        let path = self
            .bound(
                self.path_request(request.path, request.cwd)
                    .map_err(file_error)?,
                true,
            )
            .await
            .map_err(file_error)?;
        self.executor
            .fs()
            .canonicalize(&path)
            .await
            .map(|path| Some(path.as_str().into()))
            .map_err(file_error)
    }
    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> Result<Option<WorkspaceFileStat>> {
        self.inspect_path(request.path, request.cwd)
            .await
            .map_err(file_error)
    }
    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        let path = self
            .path_request(request.path, request.cwd)
            .map_err(file_error)?;
        let mut bytes = Vec::new();
        self.copy_file_to(path.as_str(), &mut bytes)
            .await
            .map_err(file_error)?;
        String::from_utf8(bytes).map_err(file_error)
    }
    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let path = self
            .path_request(request.path, request.cwd)
            .map_err(file_error)?;
        let mut bytes = Vec::new();
        self.copy_capture_bounded(path.as_str(), &mut bytes, request.max_bytes as u64)
            .await
            .map_err(file_error)?;
        Ok(bytes)
    }
    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        let path = self
            .path_request(request.path, request.cwd)
            .map_err(file_error)?;
        self.copy_file_from(
            path.as_str(),
            request.mode,
            request.content.len() as u64,
            &mut request.content.as_bytes(),
        )
        .await
        .map(|_| ())
    }
    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        let stat = self
            .stat(WorkspaceFileStatRequest {
                path: request.path.clone(),
                cwd: request.cwd.clone(),
            })
            .await?;
        if !stat.is_file {
            return Err(file_error("cannot delete: path is not a file"));
        }
        self.remove_path(request.path, request.cwd, false)
            .await
            .map_err(file_error)
    }
    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        self.create_directory(path, cwd).await
    }
}

/// Select and decode the first existing target-side workspace instruction file.
pub async fn load_workspace_instructions(
    backend: &ExecutorWorkspaceFileBackend,
    max_bytes: usize,
    fallback_filenames: &[String],
) -> Result<WorkspaceInstructions> {
    if max_bytes == 0 {
        return Ok(WorkspaceInstructions {
            documents: Vec::new(),
        });
    }
    let mut seen = std::collections::HashSet::new();
    let candidates = ["AGENTS.override.md", "AGENTS.md", "Agents.md"]
        .into_iter()
        .map(str::to_owned)
        .chain(
            fallback_filenames
                .iter()
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
                .map(str::to_owned),
        )
        .filter(|s| seen.insert(s.clone()));
    for path in candidates {
        if !backend
            .inspect_path(path.clone(), None)
            .await
            .map_err(file_error)?
            .is_some_and(|s| s.is_file)
        {
            continue;
        }
        let mut bytes = Vec::new();
        // Instruction selection intentionally permits a truncated prefix.
        let target = backend
            .bound(
                backend
                    .path_request(path.clone(), None)
                    .map_err(file_error)?,
                true,
            )
            .await
            .map_err(file_error)?;
        let reader = backend
            .executor
            .fs()
            .read(&target)
            .await
            .map_err(file_error)?;
        use tokio::io::AsyncReadExt;
        reader
            .take(max_bytes as u64)
            .read_to_end(&mut bytes)
            .await
            .map_err(file_error)?;
        return Ok(WorkspaceInstructions {
            documents: vec![WorkspaceInstructionDocument {
                path: PathBuf::from(target.as_str()),
                content: String::from_utf8_lossy(&bytes).into_owned(),
                bytes: bytes.len(),
            }],
        });
    }
    Ok(WorkspaceInstructions {
        documents: Vec::new(),
    })
}

fn target_collision(
    collision: pl_tool_filesystem::PathCollision,
) -> pl_remote_helper::fs::PathCollision {
    match collision {
        pl_tool_filesystem::PathCollision::FailIfExists => {
            pl_remote_helper::fs::PathCollision::FailIfExists
        }
        pl_tool_filesystem::PathCollision::Overwrite => {
            pl_remote_helper::fs::PathCollision::Overwrite
        }
    }
}
