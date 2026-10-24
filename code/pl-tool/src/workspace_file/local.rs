use std::path::{Path, PathBuf};
use std::sync::Arc;

use pl_protocol::Result;

use crate::file::path::WorkspacePaths;
use crate::workspace::ToolWorkspace;

use super::backend::{
    WorkspaceFileBackend, WorkspaceFileListRequest, WorkspaceFileListResult,
    WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest, WorkspaceFileRemoveRequest,
    WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};
use super::local_create::LocalFileCreateOwner;
use super::local_io::LocalFileIoOwner;
use super::local_root::LocalWorkspaceRoot;
use crate::tool_error;

/// A shared local workspace lease. Hosts must drain `close_reads` before releasing a read
/// tool and separately drain `close_creates` for admitted atomic creates. Neither Drop nor
/// cloning a worker supervisor substitutes for the host's shutdown/registration ownership.
#[derive(Debug, Clone)]
pub struct LocalWorkspaceFileBackend {
    paths: WorkspacePaths,
    lsp_runtime: Option<pl_lsp::runtime::LspRuntimeRegistry>,
    workspace: Option<ToolWorkspace>,
    listings: super::listing::ListingPager,
    root: pl_remote_helper::workspace_dir::WorkspaceDir,
    create_owner: LocalFileCreateOwner,
    io: LocalFileIoOwner,
    host_read_access: bool,
}

impl LocalWorkspaceFileBackend {
    /// Convenience construction: the caller must retain and finish this future, then close
    /// reads. Cancellable host construction must use `new_with_io_owner` with a pre-owned owner.
    /// # Errors
    /// Reports path/root open failures; admitted creates have their separate close obligation.
    pub async fn new(root: PathBuf, allow_workspace_escape: bool) -> Result<Self> {
        Self::new_with_io_owner(root, allow_workspace_escape, LocalFileIoOwner::default()).await
    }

    /// Constructs under an IO owner already held by the host before this call.
    /// # Errors
    /// Reports path/root failures and admission after the host has sealed its owner.
    pub async fn new_with_io_owner(
        root: PathBuf,
        allow_workspace_escape: bool,
        io: LocalFileIoOwner,
    ) -> Result<Self> {
        let (paths, root) = io
            .run(move || {
                let paths =
                    futures::executor::block_on(WorkspacePaths::new(root, allow_workspace_escape))?;
                let root = pl_remote_helper::workspace_dir::WorkspaceDir::open(paths.root())?;
                Ok((paths, root))
            })
            .await?;
        Ok(Self {
            paths,
            lsp_runtime: None,
            workspace: None,
            listings: Default::default(),
            root,
            create_owner: Default::default(),
            io,
            host_read_access: allow_workspace_escape,
        })
    }

    /// Binds host policy to a safely acquired root without reopening that root by ambient path.
    /// The workspace must name the root's exact formal path; it is not another authority grant.
    /// # Errors
    /// Rejects mismatched workspace/policy paths, changed canonical display paths and closed IO.
    pub async fn confined_root(workspace: ToolWorkspace, root: LocalWorkspaceRoot) -> Result<Self> {
        if workspace.root() != root.path() {
            return Err(tool_error(
                "file",
                "workspace authorization does not match the managed root path",
            ));
        }
        let path = root.path.clone();
        let paths = root
            .io
            .run(move || {
                let paths = futures::executor::block_on(WorkspacePaths::new(path.clone(), false))?;
                if paths.root() != path {
                    return Err(tool_error(
                        "file",
                        "managed root display path changed or follows a link",
                    ));
                }
                Ok(paths)
            })
            .await?;
        Ok(Self {
            paths,
            lsp_runtime: workspace.lsp_runtime(),
            workspace: Some(workspace),
            listings: Default::default(),
            root: root.directory,
            create_owner: Default::default(),
            io: root.io,
            host_read_access: false,
        })
    }

    /// Opens a managed root beneath a trusted host grant, including its own no-follow entry.
    /// # Errors
    /// Rejects links, escaping relative roots, mismatched workspace policy and IO failures.
    pub async fn confined_beneath(
        workspace: ToolWorkspace,
        owner: LocalFileIoOwner,
        trusted_parent: PathBuf,
        relative_root: PathBuf,
    ) -> Result<Self> {
        let root = LocalWorkspaceRoot::open_beneath(owner, trusted_parent, relative_root).await?;
        Self::confined_root(workspace, root).await
    }

    /// Seals and drains this backend's IO owner. Clones share that lifecycle; a shared service
    /// must supply separate host-owned leases rather than letting one tool close other users.
    /// # Errors
    /// Individual root/read failures belong to their request; close waits physical completion.
    pub async fn close_reads(&self) -> Result<()> {
        self.io.close().await
    }

    /// Injects the Thread's shared Create lifecycle before this backend admits any creates.
    /// The host must retain and close the supplied owner; backend clones share it.
    pub fn with_create_owner(mut self, owner: LocalFileCreateOwner) -> Self {
        self.create_owner = owner;
        self
    }

    /// Seals this backend's Create lifecycle and waits for actual workers and cleanup.
    ///
    /// # Errors
    /// Retains failed cleanup for a later call. Other file backend operations are unaffected.
    pub async fn close_creates(&self) -> Result<()> {
        self.create_owner.close().await
    }

    /// Binds a confined file backend to the host's frozen write policy and LSP lease.
    /// Like `new`, the caller must finish this construction and later drain reads/creates;
    /// cancellable managed-root construction must use the explicit-owner/root entrypoints.
    ///
    /// # Errors
    /// Rejects an unavailable workspace root before any file operation is admitted.
    pub async fn confined(workspace: ToolWorkspace) -> Result<Self> {
        let mut backend = Self::new(workspace.root().to_path_buf(), false).await?;
        backend.lsp_runtime = workspace.lsp_runtime();
        backend.workspace = Some(workspace);
        Ok(backend)
    }

    /// Atomically creates raw bytes through the same physical path and assigned write policy.
    /// A same-directory staged file never replaces an existing target.
    ///
    /// # Errors
    /// Returns path, permission, conflicting-create, worker and filesystem failures.
    pub async fn create_bytes_atomic(
        &self,
        path: String,
        cwd: Option<String>,
        bytes: Arc<[u8]>,
    ) -> Result<()> {
        let path = self.resolve_for_write(cwd.as_deref(), &path).await?;
        if let Some(workspace) = &self.workspace {
            workspace.ensure_path_writable(&path)?;
        }
        let relative = path
            .strip_prefix(self.paths.root())
            .map_err(|_| {
                tool_error(
                    "write_file",
                    "atomic Create cannot escape its trusted workspace root",
                )
            })?
            .to_owned();
        self.create_owner
            .create(self.root.clone(), relative, bytes)
            .await?;
        self.notify_changed(&path).await;
        Ok(())
    }

    async fn read_local(&self, input_path: String, maximum: Option<usize>) -> Result<Vec<u8>> {
        let paths = self.paths.clone();
        let root = self.root.clone();
        let host_access = self.host_read_access;
        self.io
            .run(move || {
                // Reuse the existing cwd/absolute/parent input policy. Its ambient inspection
                // never authorizes the actual open, which is rooted in the pinned capability.
                let path = futures::executor::block_on(paths.resolve_existing(&input_path))?;
                if host_access {
                    // A host grant retains ambient external-path semantics; it is still a
                    // tracked, bounded ordinary-file read, never a new root confinement rule.
                    return pl_remote_helper::workspace_dir::read_ambient(&path, maximum)
                        .map_err(|error| tool_error("read_file", error));
                }
                let relative = path
                    .strip_prefix(paths.root())
                    .map_err(|_| tool_error("read_file", "confined read escapes its workspace"))?;
                root.read(relative, maximum)
                    .map_err(|error| tool_error("read_file", error))
            })
            .await
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
        backend.host_read_access = true;
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
        let bytes = self.read_local(input_path, None).await?;
        String::from_utf8(bytes).map_err(|error| tool_error("read_file", error))
    }

    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let input_path = self.with_cwd(request.cwd.as_deref(), &request.path)?;
        self.read_local(input_path, Some(request.max_bytes)).await
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
