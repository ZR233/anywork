//! A managed root's physical authority and its non-authoritative execution display path.

use std::path::{Path, PathBuf};

use pl_protocol::Result;
use pl_remote_helper::workspace_dir::WorkspaceDir;

use super::local_io::LocalFileIoOwner;

/// A no-follow root opened below a host-granted parent, with a pre-owned IO lifecycle.
/// The path is display/policy material only. Physical reads and creates use `directory`.
#[derive(Debug, Clone)]
pub struct LocalWorkspaceRoot {
    pub(super) directory: WorkspaceDir,
    pub(super) path: PathBuf,
    pub(super) io: LocalFileIoOwner,
}

impl LocalWorkspaceRoot {
    /// Opens an existing managed root, including its own final component, without links.
    /// The host must retain `owner` before calling, and close it even if this future is dropped.
    /// # Errors
    /// Rejects links/reparse points, escaping relative roots, missing roots and IO failures.
    pub async fn open_beneath(
        owner: LocalFileIoOwner,
        trusted_parent: PathBuf,
        relative_root: PathBuf,
    ) -> Result<Self> {
        Self::beneath(owner, trusted_parent, relative_root, false).await
    }

    /// Creates/opens a managed root beneath the trusted host parent using no-follow handles.
    /// Cancellation does not roll back authorized directories; the host's owner joins the work.
    /// # Errors
    /// Rejects links/reparse points, escaping relative roots and IO failures.
    pub async fn ensure_beneath(
        owner: LocalFileIoOwner,
        trusted_parent: PathBuf,
        relative_root: PathBuf,
    ) -> Result<Self> {
        Self::beneath(owner, trusted_parent, relative_root, true).await
    }

    async fn beneath(
        io: LocalFileIoOwner,
        trusted_parent: PathBuf,
        relative_root: PathBuf,
        create: bool,
    ) -> Result<Self> {
        let (path, directory) = io
            .run(move || {
                // Only this host-selected ambient grant is canonicalized. Never canonicalize a
                // managed descendant and turn an external symlink target into a trusted root.
                let parent_path = dunce::canonicalize(trusted_parent)?;
                let parent = WorkspaceDir::open(&parent_path)?;
                let directory = if create {
                    parent.ensure_dir(&relative_root)?
                } else {
                    parent.open_dir(&relative_root)?
                };
                Ok((parent_path.join(relative_root), directory))
            })
            .await?;
        Ok(Self {
            directory,
            path,
            io,
        })
    }

    /// The formal execution/project path, not an ambient-open capability or immutable location.
    pub fn path(&self) -> &Path {
        &self.path
    }
}
