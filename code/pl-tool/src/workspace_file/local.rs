use std::path::{Path, PathBuf};

use pl_protocol::Result;
use tokio::io::AsyncReadExt;

use crate::file::path::WorkspacePaths;
use crate::workspace::ToolWorkspace;

use super::backend::{
    WorkspaceFileBackend, WorkspaceFileListRequest, WorkspaceFileListResult,
    WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest, WorkspaceFileRemoveRequest,
    WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};
use crate::tool_error;

#[derive(Debug, Clone)]
pub struct LocalWorkspaceFileBackend {
    paths: WorkspacePaths,
    lsp_runtime: Option<pl_lsp::runtime::LspRuntimeRegistry>,
    workspace: Option<ToolWorkspace>,
    listings: super::listing::ListingPager,
}

impl LocalWorkspaceFileBackend {
    pub async fn new(root: PathBuf, allow_workspace_escape: bool) -> Result<Self> {
        Ok(Self {
            paths: WorkspacePaths::new(root, allow_workspace_escape).await?,
            lsp_runtime: None,
            workspace: None,
            listings: Default::default(),
        })
    }

    /// Binds a confined file backend to the host's frozen write policy and LSP lease.
    ///
    /// # Errors
    /// Rejects an unavailable workspace root before any file operation is admitted.
    pub async fn confined(workspace: ToolWorkspace) -> Result<Self> {
        let mut backend = Self::new(workspace.root().to_path_buf(), false).await?;
        backend.lsp_runtime = workspace.lsp_runtime();
        backend.workspace = Some(workspace);
        Ok(backend)
    }

    fn with_cwd(&self, cwd: Option<&str>, path: &str) -> Result<String> {
        let path_ref = Path::new(path);
        if path_ref.is_absolute() {
            return Ok(path.to_string());
        }
        let Some(cwd) = cwd.filter(|cwd| !cwd.trim().is_empty() && *cwd != ".") else {
            return Ok(path.to_string());
        };
        // Resolve the joined target through the same path policy as every other input.
        // This accepts absolute cwd inside a confined checkout without relaxing escape
        // or link checks, and still permits a missing relative directory for new files.
        Ok(Path::new(cwd).join(path_ref).to_string_lossy().into_owned())
    }

    async fn resolve_existing(&self, cwd: Option<&str>, path: &str) -> Result<PathBuf> {
        let path = self.with_cwd(cwd, path)?;
        self.paths.resolve_existing(&path).await
    }

    async fn resolve_for_write(&self, cwd: Option<&str>, path: &str) -> Result<PathBuf> {
        let path = self.with_cwd(cwd, path)?;
        self.paths.resolve_for_write(&path).await
    }

    async fn resolve_existing_or_parent(&self, cwd: Option<&str>, path: &str) -> Result<PathBuf> {
        let path = self.with_cwd(cwd, path)?;
        self.paths.resolve_existing_or_parent(&path).await
    }

    async fn notify_changed(&self, path: &Path) {
        if let Some(registry) = &self.lsp_runtime {
            registry.notify_file_changed(path.to_path_buf()).await;
        }
    }

    async fn notify_deleted(&self, path: &Path) {
        if let Some(registry) = &self.lsp_runtime {
            registry.notify_file_deleted(path.to_path_buf()).await;
        }
    }
}

impl WorkspaceFileBackend for LocalWorkspaceFileBackend {
    fn for_grant(&self, grant: &pl_core::tool::execution_policy::ExecutionGrant) -> Option<Self> {
        if !grant.contains(crate::approval::HOST_WORKSPACE_ACCESS)
            || !self
                .workspace
                .as_ref()
                .is_some_and(|workspace| workspace.workspace().boundary().allows_host_paths())
        {
            return None;
        }
        let mut backend = self.clone();
        backend.paths = self.paths.with_host_access();
        backend.listings = Default::default();
        Some(backend)
    }

    async fn default_cwd(&self) -> Result<String> {
        Ok(".".to_string())
    }

    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> Result<Option<WorkspaceFileStat>> {
        let path = self
            .resolve_existing_or_parent(request.cwd.as_deref(), &request.path)
            .await?;
        let metadata = match tokio::fs::metadata(&path).await {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        Ok(Some(WorkspaceFileStat {
            path: self.paths.display_relative(&path),
            is_file: metadata.is_file(),
            is_dir: metadata.is_dir(),
            len: metadata.is_file().then_some(metadata.len()),
            readonly: Some(metadata.permissions().readonly()),
            modified_at: metadata
                .modified()
                .ok()
                .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                .and_then(|duration| i64::try_from(duration.as_secs()).ok()),
        }))
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        let input_path = self.with_cwd(request.cwd.as_deref(), &request.path)?;
        let path = self.paths.resolve_existing(&input_path).await?;
        let metadata = tokio::fs::metadata(&path).await?;
        if !metadata.is_file() {
            return Err(tool_error(
                "read_file",
                format!("'{}' is not a regular file", request.path),
            ));
        }
        tokio::fs::read_to_string(&path).await.map_err(|error| {
            tool_error(
                "read_file",
                format!(
                    "failed to read '{}': {error}",
                    self.paths.display_relative(&path)
                ),
            )
        })
    }

    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let input_path = self.with_cwd(request.cwd.as_deref(), &request.path)?;
        let path = self.paths.resolve_existing(&input_path).await?;
        let metadata = tokio::fs::metadata(&path).await?;
        if !metadata.is_file() {
            return Err(tool_error(
                "view_image",
                format!("'{}' is not a regular file", request.path),
            ));
        }
        if metadata.len() > request.max_bytes as u64 {
            return Err(tool_error(
                "view_image",
                format!(
                    "'{}' exceeds the {} byte source limit",
                    self.paths.display_relative(&path),
                    request.max_bytes
                ),
            ));
        }
        let file = tokio::fs::File::open(&path).await.map_err(|error| {
            tool_error(
                "view_image",
                format!(
                    "failed to read '{}': {error}",
                    self.paths.display_relative(&path)
                ),
            )
        })?;
        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        file.take(request.max_bytes as u64 + 1)
            .read_to_end(&mut bytes)
            .await
            .map_err(|error| {
                tool_error(
                    "view_image",
                    format!(
                        "failed to read '{}': {error}",
                        self.paths.display_relative(&path)
                    ),
                )
            })?;
        if bytes.len() > request.max_bytes {
            return Err(tool_error(
                "view_image",
                format!(
                    "'{}' changed while reading and exceeds the {} byte source limit",
                    self.paths.display_relative(&path),
                    request.max_bytes
                ),
            ));
        }
        Ok(bytes)
    }

    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        let path = self
            .resolve_for_write(request.cwd.as_deref(), &request.path)
            .await?;
        if let Some(workspace) = &self.workspace {
            workspace.ensure_path_writable(&path)?;
        }
        let target = path.clone();
        tokio::task::spawn_blocking(move || {
            crate::workspace::write_file_with_mode(
                &target,
                request.content.as_bytes(),
                request.mode,
            )
        })
        .await
        .map_err(|error| tool_error("write_file", error))??;
        self.notify_changed(&path).await;
        Ok(())
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        let path = self
            .resolve_existing(request.cwd.as_deref(), &request.path)
            .await?;
        if let Some(workspace) = &self.workspace {
            workspace.ensure_path_writable(&path)?;
        }
        let metadata = tokio::fs::metadata(&path).await?;
        if !metadata.is_file() {
            return Err(tool_error(
                "apply_patch",
                format!("cannot delete '{}': path is not a file", request.path),
            ));
        }
        tokio::fs::remove_file(&path).await.map_err(|error| {
            tool_error(
                "apply_patch",
                format!(
                    "failed to delete '{}': {error}",
                    self.paths.display_relative(&path)
                ),
            )
        })?;
        self.notify_deleted(&path).await;
        Ok(())
    }

    async fn list(&self, request: WorkspaceFileListRequest) -> Result<WorkspaceFileListResult> {
        let path = request.path.clone();
        let cwd = request.cwd.clone();
        let implicit = request.implicit_recovery;
        self.listings
            .page(request, async {
                use futures::StreamExt;
                let root = self
                    .resolve_existing_or_parent(cwd.as_deref(), &path)
                    .await?;
                if !tokio::fs::try_exists(&root).await? {
                    return Ok(futures::stream::empty().boxed() as super::listing::Entries);
                }
                let paths = self.paths.clone();
                let mut builder = ignore::WalkBuilder::new(&root);
                builder
                    .hidden(false)
                    .ignore(false)
                    .git_ignore(false)
                    .git_global(false)
                    .git_exclude(false)
                    .parents(false)
                    .follow_links(false)
                    .filter_entry(move |entry| {
                        !entry.file_type().is_some_and(|kind| kind.is_symlink())
                            && !super::listing::skip_directory(
                                &entry.path().to_string_lossy().replace('\\', "/"),
                                implicit,
                            )
                    });
                let walk = builder.build();
                let entries = futures::stream::try_unfold(
                    (walk, paths, root),
                    |(mut walk, paths, root)| async move {
                        loop {
                            let (next, returned) = tokio::task::spawn_blocking(move || {
                                let next = walk.next();
                                (next, walk)
                            })
                            .await
                            .map_err(|e| tool_error("list_files", e))?;
                            walk = returned;
                            let Some(entry) = next else {
                                return Ok(None);
                            };
                            let entry = entry.map_err(|e| tool_error("list_files", e))?;
                            if entry.path() == root {
                                continue;
                            }
                            let Some(kind) = entry.file_type() else {
                                continue;
                            };
                            if !kind.is_file() && !kind.is_dir() {
                                continue;
                            }
                            let value = super::WorkspaceFileListEntry {
                                path: paths.display_relative(entry.path()),
                                is_dir: kind.is_dir(),
                            };
                            return Ok(Some((value, (walk, paths, root))));
                        }
                    },
                )
                .boxed();
                Ok(entries as super::listing::Entries)
            })
            .await
    }

    async fn close_listing(&self, cursor: String) -> Result<()> {
        self.listings.close(&cursor);
        Ok(())
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        let path = self.resolve_for_write(cwd.as_deref(), &path).await?;
        if let Some(workspace) = &self.workspace {
            workspace.ensure_path_writable(&path)?;
        }
        tokio::fs::create_dir_all(&path).await?;
        Ok(())
    }
}
