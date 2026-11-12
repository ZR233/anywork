//! Workspace policy binding over one immutable executor and target root.
mod directory;
mod download;
use super::SshError;
use crate::workspace::{WorkspaceInstructionDocument, WorkspaceInstructions};
use crate::{tool_error, workspace_file::*};
pub use directory::RemoteDirectoryReader;
pub use download::RemoteDownloadError;
use pl_protocol::Result;
use pl_remote_helper::{Executor, TargetPath};
use std::path::PathBuf;
const DEFAULT_INSTRUCTION_FILENAMES: &[&str] = &["AGENTS.override.md", "AGENTS.md", "Agents.md"];

#[derive(Debug, Clone)]
pub struct RemoteWorkspaceFileBackend {
    executor: Executor,
    root: TargetPath,
}
impl RemoteWorkspaceFileBackend {
    pub fn new(executor: Executor, root: &str) -> std::result::Result<Self, SshError> {
        let root = executor.path(root)?;
        Ok(Self { executor, root })
    }
    pub fn executor(&self) -> &Executor {
        &self.executor
    }
    pub fn canonical_path(&self) -> &str {
        self.root.as_str()
    }
    pub(super) fn binding_identity(&self) -> String {
        format!("executor:{:?}:{}", self.executor.id(), self.root.as_str())
    }
    pub fn is_same_binding(&self, other: &Self) -> bool {
        self.executor.id() == other.executor.id() && self.root == other.root
    }
    pub(super) fn path_request(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> std::result::Result<TargetPath, SshError> {
        let path = resolve_remote_path(path, cwd)?;
        Ok(self.executor.join_path(&self.root, &path)?)
    }
    async fn bound(
        &self,
        path: TargetPath,
        follow_final: bool,
    ) -> std::result::Result<TargetPath, SshError> {
        // Workspace confinement is product policy, not an executor/server restriction.
        let mut existing = if follow_final {
            path.as_str().to_owned()
        } else {
            parent(path.as_str()).to_owned()
        };
        loop {
            let candidate = self.executor.path(&existing)?;
            if self.executor.fs().metadata(&candidate).await?.is_some() {
                let canonical = self.executor.fs().canonicalize(&candidate).await?;
                let root = self.root.as_str().trim_end_matches('/');
                if root.is_empty()
                    || canonical.as_str() == root
                    || canonical.as_str().starts_with(&format!("{root}/"))
                {
                    return Ok(path);
                }
                return Err(SshError::Remote {
                    code: super::RemoteErrorCode::WorkspaceEscape,
                    message: "path resolves outside workspace".into(),
                });
            }
            let next = parent(&existing);
            if next == existing {
                return Err(SshError::Protocol(
                    "workspace ancestor is unavailable".into(),
                ));
            }
            existing = next.into();
        }
    }
    pub async fn stat_optional(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> std::result::Result<Option<WorkspaceFileStat>, SshError> {
        let path = self.bound(self.path_request(path, cwd)?, true).await?;
        Ok(self
            .executor
            .fs()
            .metadata(&path)
            .await?
            .map(|stat| WorkspaceFileStat {
                path: path.as_str().into(),
                is_file: stat.is_file,
                is_dir: stat.is_dir,
                len: Some(stat.len),
                readonly: Some(stat.readonly),
                modified_at: stat.modified_at,
            }))
    }
    pub async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        let path = self
            .bound(
                self.path_request(path, cwd).map_err(remote_file_error)?,
                true,
            )
            .await
            .map_err(remote_file_error)?;
        self.executor
            .fs()
            .create_dir(&path, true)
            .await
            .map_err(|error| remote_file_error(error.into()))
    }
    pub async fn write_bytes_atomic(
        &self,
        path: String,
        cwd: Option<String>,
        body: &[u8],
    ) -> Result<()> {
        let path = resolve_remote_path(path, cwd).map_err(remote_file_error)?;
        self.copy_file_from(
            &path,
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
    ) -> std::result::Result<(), SshError> {
        let path = self.bound(self.path_request(path, cwd)?, false).await?;
        if self.executor.fs().symlink_metadata(&path).await?.is_none() {
            return Ok(());
        }
        self.executor
            .fs()
            .remove(&path, recursive)
            .await
            .map_err(super::SshError::Removal)?;
        Ok(())
    }
    pub async fn rename_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
    ) -> Result<()> {
        let source = self
            .bound(
                self.path_request(source, cwd.clone())
                    .map_err(remote_file_error)?,
                false,
            )
            .await
            .map_err(remote_file_error)?;
        let target = self
            .bound(
                self.path_request(target, cwd).map_err(remote_file_error)?,
                false,
            )
            .await
            .map_err(remote_file_error)?;
        let parent = self
            .executor
            .path(parent(target.as_str()))
            .map_err(|error| remote_file_error(error.into()))?;
        self.executor
            .fs()
            .create_dir(&parent, true)
            .await
            .map_err(|error| remote_file_error(error.into()))?;
        self.executor
            .fs()
            .rename(&source, &target)
            .await
            .map_err(|error| remote_file_error(error.into()))
    }
    pub async fn copy_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
        recursive: bool,
    ) -> Result<()> {
        let source = self
            .bound(
                self.path_request(source, cwd.clone())
                    .map_err(remote_file_error)?,
                true,
            )
            .await
            .map_err(remote_file_error)?;
        let target = self
            .bound(
                self.path_request(target, cwd).map_err(remote_file_error)?,
                true,
            )
            .await
            .map_err(remote_file_error)?;
        let parent = self
            .executor
            .path(parent(target.as_str()))
            .map_err(|error| remote_file_error(error.into()))?;
        self.executor
            .fs()
            .create_dir(&parent, true)
            .await
            .map_err(|error| remote_file_error(error.into()))?;
        self.executor
            .fs()
            .copy_path(&source, &target, recursive)
            .await
            .map_err(|error| remote_file_error(error.into()))
    }
}
pub(in crate::remote) fn parent(path: &str) -> &str {
    path.trim_end_matches('/')
        .rsplit_once('/')
        .map(|(parent, _)| if parent.is_empty() { "/" } else { parent })
        .unwrap_or("/")
}

/// 在本地 core 中选择、解码并截断远端 workspace 根目录的项目说明文档。
pub async fn load_remote_workspace_instructions(
    backend: &RemoteWorkspaceFileBackend,
    max_bytes: usize,
    fallback_filenames: &[String],
) -> Result<WorkspaceInstructions> {
    if max_bytes == 0 {
        return Ok(WorkspaceInstructions {
            documents: Vec::new(),
        });
    }
    let mut seen = std::collections::HashSet::new();
    let candidates = DEFAULT_INSTRUCTION_FILENAMES
        .iter()
        .map(|name| (*name).to_string())
        .chain(
            fallback_filenames
                .iter()
                .map(|name| name.trim())
                .filter(|name| !name.is_empty())
                .map(ToOwned::to_owned),
        )
        .filter(|name| seen.insert(name.clone()));
    for path in candidates {
        let Some(stat) = backend
            .stat_optional(path.clone(), None)
            .await
            .map_err(remote_file_error)?
        else {
            continue;
        };
        if !stat.is_file {
            continue;
        }
        let bytes = backend
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: path.clone(),
                cwd: None,
                max_bytes,
            })
            .await?;
        let take = bytes.len().min(max_bytes);
        return Ok(WorkspaceInstructions {
            documents: vec![WorkspaceInstructionDocument {
                path: PathBuf::from(backend.canonical_path()).join(&path),
                content: String::from_utf8_lossy(&bytes[..take]).into_owned(),
                bytes: take,
            }],
        });
    }
    Ok(WorkspaceInstructions {
        documents: Vec::new(),
    })
}

impl WorkspaceFileBackend for RemoteWorkspaceFileBackend {
    async fn default_cwd(&self) -> Result<String> {
        Ok(".".into())
    }
    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> Result<Option<WorkspaceFileStat>> {
        self.stat_optional(request.path, request.cwd)
            .await
            .map_err(remote_file_error)
    }
    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        let path = resolve_remote_path(request.path, request.cwd).map_err(remote_file_error)?;
        let mut bytes = Vec::new();
        self.copy_file_to(&path, &mut bytes)
            .await
            .map_err(|error| tool_error("file", error))?;
        String::from_utf8(bytes).map_err(|error| tool_error("file", error))
    }
    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let path = resolve_remote_path(request.path, request.cwd).map_err(remote_file_error)?;
        let mut bytes = Vec::new();
        self.copy_capture_bounded(&path, &mut bytes, request.max_bytes as u64)
            .await
            .map_err(|error| tool_error("file", error))?;
        Ok(bytes)
    }
    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        let path = resolve_remote_path(request.path, request.cwd).map_err(remote_file_error)?;
        self.copy_file_from(
            &path,
            request.mode,
            request.content.len() as u64,
            &mut request.content.as_bytes(),
        )
        .await
        .map(|_| ())
    }
    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        self.remove_path(request.path, request.cwd, false)
            .await
            .map_err(remote_file_error)
    }
    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        self.create_directory(path, cwd).await
    }
}
fn resolve_remote_path(path: String, cwd: Option<String>) -> std::result::Result<String, SshError> {
    if path.starts_with('/') {
        return Ok(path);
    }
    let mut base = cwd.unwrap_or_else(|| ".".into());
    if !base.ends_with('/') {
        base.push('/');
    }
    base.push_str(&path);
    Ok(base)
}
pub(super) fn remote_file_error(error: SshError) -> pl_protocol::PureError {
    tool_error("file", error)
}
