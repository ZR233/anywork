use std::path::{Path, PathBuf};

use pl_patch::{PatchBackend, PatchError, PatchPathDisplay, PatchResult};
use pl_protocol::PureError;

use super::backend::*;

use pl_patch::PatchOutput;

pub async fn apply_patch_to_backend<B: WorkspaceFileBackend>(
    backend: &B,
    cwd: String,
    patch: &str,
) -> std::result::Result<PatchOutput, pl_patch::PatchFailure> {
    backend
        .apply_patch(cwd.clone(), patch)
        .await
        .map(|report| report.into_output(cwd))
}

pub(super) async fn apply_via_files<B: WorkspaceFileBackend>(
    backend: &B,
    cwd: String,
    patch: &str,
) -> std::result::Result<pl_patch::PatchReport, pl_patch::PatchFailure> {
    use pl_tool_filesystem::apply_patch::PatchExecutor;
    let adapter = WorkspacePatchBackend { backend, cwd: &cwd };
    adapter.execute_patch(cwd.clone(), patch).await
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
            .stat_optional(WorkspaceFileStatRequest {
                path: path.clone(),
                cwd: Some(self.cwd.to_string()),
            })
            .await
            .map_err(patch_error)?;
        if !stat.is_some_and(|stat| stat.is_file) {
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
