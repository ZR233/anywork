use std::path::{Path, PathBuf};

use pl_patch::{PatchBackend, PatchError, PatchPathDisplay, PatchResult};
use pl_protocol::{PureError, Result};

use super::backend::*;
use super::schema::TOOL_APPLY_PATCH;
use crate::tool_error;

use pl_tool_filesystem::apply_patch::PatchOutput;

pub async fn apply_patch_to_backend<B>(backend: &B, cwd: String, patch: &str) -> Result<PatchOutput>
where
    B: WorkspaceFileBackend,
{
    let patch_backend = WorkspacePatchBackend { backend, cwd: &cwd };
    pl_tool_filesystem::apply_patch::apply_patch(&patch_backend, cwd.clone(), patch)
        .await
        .map_err(|error| tool_error(TOOL_APPLY_PATCH, error.into_message()))
}

#[derive(Debug)]
struct WorkspacePatchBackend<'a, B> {
    backend: &'a B,
    cwd: &'a str,
}

impl<B> PatchPathDisplay for WorkspacePatchBackend<'_, B> {
    fn display_path(&self, path: &Path) -> String {
        path.to_string_lossy().replace('\\', "/")
    }
}

impl<B> PatchBackend for WorkspacePatchBackend<'_, B>
where
    B: WorkspaceFileBackend,
{
    async fn resolve_existing<'a>(&'a self, path: &'a str) -> PatchResult<PathBuf> {
        self.backend
            .stat(WorkspaceFileStatRequest {
                path: path.to_string(),
                cwd: Some(self.cwd.to_string()),
            })
            .await
            .map_err(patch_error)?;
        Ok(PathBuf::from(path))
    }

    async fn resolve_for_write<'a>(&'a self, path: &'a str) -> PatchResult<PathBuf> {
        Ok(PathBuf::from(path))
    }

    async fn reject_symlink_write<'a>(&'a self, _path: &'a Path) -> PatchResult<()> {
        Ok(())
    }

    async fn ensure_file<'a>(&'a self, path: &'a Path) -> PatchResult<()> {
        let stat = self
            .backend
            .stat(WorkspaceFileStatRequest {
                path: self.display_path(path),
                cwd: Some(self.cwd.to_string()),
            })
            .await
            .map_err(patch_error)?;
        if stat.is_file {
            Ok(())
        } else {
            Err(PatchError::new(format!(
                "cannot delete '{}': path is not a file",
                self.display_path(path)
            )))
        }
    }

    async fn read_to_string<'a>(&'a self, path: &'a Path) -> PatchResult<String> {
        self.backend
            .read_text(WorkspaceFileReadRequest {
                path: self.display_path(path),
                cwd: Some(self.cwd.to_string()),
            })
            .await
            .map_err(patch_error)
    }

    async fn read_optional_text<'a>(&'a self, path: &'a Path) -> PatchResult<Option<String>> {
        let path = self.display_path(path);
        let stat = self
            .backend
            .stat(WorkspaceFileStatRequest {
                path: path.clone(),
                cwd: Some(self.cwd.to_string()),
            })
            .await;
        if !stat.is_ok_and(|stat| stat.is_file) {
            return Ok(None);
        }
        self.backend
            .read_text(WorkspaceFileReadRequest {
                path,
                cwd: Some(self.cwd.to_string()),
            })
            .await
            .map(Some)
            .map_err(patch_error)
    }

    async fn create_parent_dirs<'a>(&'a self, _path: &'a Path) -> PatchResult<()> {
        Ok(())
    }

    async fn write_text<'a>(&'a self, path: &'a Path, content: &'a str) -> PatchResult<()> {
        self.backend
            .write_text(WorkspaceFileWriteRequest {
                mode: crate::workspace::WriteMode::Overwrite,
                path: self.display_path(path),
                cwd: Some(self.cwd.to_string()),
                content: content.to_string(),
            })
            .await
            .map_err(patch_error)
    }

    async fn remove_file<'a>(&'a self, path: &'a Path) -> PatchResult<()> {
        self.backend
            .remove_file(WorkspaceFileRemoveRequest {
                path: self.display_path(path),
                cwd: Some(self.cwd.to_string()),
            })
            .await
            .map_err(patch_error)
    }
}

fn patch_error(error: PureError) -> PatchError {
    let message = match error {
        PureError::ToolExecutionFailed { error, .. } => error,
        error => error.to_string(),
    };
    PatchError::new(message)
}
