//! Idempotent execution-side layout preparation for sessions and worktree pools.
//!
//! Pool `.gitignore` files (`*\n`) are created only when absent; existing ignore
//! bytes are left untouched. Callers reuse [`WorkspaceFileBackend`] rather than a
//! second filesystem router.

use std::path::{Path, PathBuf};

use pl_protocol::Result;

use super::session_files::SessionFiles;
use crate::workspace::WriteMode;
use crate::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};

/// Contents written into a newly created pool `.gitignore`. Existing files are not replaced.
pub const POOL_GITIGNORE: &str = "*\n";

/// Relative path of the sessions pool inside a workspace.
pub const SESSIONS_POOL: &str = ".anywork/sessions";

/// Relative path of the worktree run pool inside a repository.
pub const WORKTREES_POOL: &str = ".anywork/worktrees";

/// Prepares one Thread's execution-side directories through an existing file backend.
///
/// Creates the sessions pool ignore (when missing), then this Thread's `temp`,
/// `artifacts`, and `temp/commands` directories. Existing ignore files keep their bytes.
///
/// # Errors
/// Returns backend I/O or workspace-escape errors from the underlying file backend.
pub async fn prepare_session_files<B>(backend: &B, files: &SessionFiles) -> Result<()>
where
    B: WorkspaceFileBackend,
{
    ensure_pool_gitignore(backend, SESSIONS_POOL).await?;
    create_directory(backend, files.scratch()).await?;
    create_directory(backend, files.artifacts()).await?;
    create_directory(backend, files.commands()).await?;
    Ok(())
}

/// Prepares the worktree run pool and its non-overwriting ignore file.
///
/// # Errors
/// Returns backend I/O or workspace-escape errors from the underlying file backend.
pub async fn prepare_worktree_pool<B>(backend: &B) -> Result<()>
where
    B: WorkspaceFileBackend,
{
    ensure_pool_gitignore(backend, WORKTREES_POOL).await
}

/// Ensures a command capture parent directory and the sessions pool exist before first write.
///
/// # Errors
/// Returns backend I/O or workspace-escape errors from the underlying file backend.
pub async fn prepare_command_capture<B>(backend: &B, capture_file: &Path) -> Result<()>
where
    B: WorkspaceFileBackend,
{
    ensure_pool_gitignore(backend, SESSIONS_POOL).await?;
    let Some(parent) = capture_file.parent() else {
        return Ok(());
    };
    create_directory(backend, parent.to_path_buf()).await
}

async fn ensure_pool_gitignore<B>(backend: &B, pool: &str) -> Result<()>
where
    B: WorkspaceFileBackend,
{
    create_directory(backend, PathBuf::from(pool)).await?;
    let ignore = format!("{pool}/.gitignore");
    if regular_ignore_file(backend, &ignore).await?.is_some() {
        return Ok(());
    }
    match backend
        .write_text(WorkspaceFileWriteRequest {
            mode: WriteMode::Create,
            path: ignore.clone(),
            cwd: None,
            content: POOL_GITIGNORE.to_string(),
        })
        .await
    {
        Ok(()) => Ok(()),
        Err(error) => match regular_ignore_file(backend, &ignore).await {
            Ok(Some(_)) => Ok(()),
            Ok(None) => Err(error),
            Err(observe) => Err(observe),
        },
    }
}

async fn regular_ignore_file<B>(backend: &B, path: &str) -> Result<Option<WorkspaceFileStat>>
where
    B: WorkspaceFileBackend,
{
    let Some(stat) = backend
        .stat_optional(WorkspaceFileStatRequest {
            path: path.to_string(),
            cwd: None,
        })
        .await?
    else {
        return Ok(None);
    };
    if stat.is_file && !stat.is_dir {
        return Ok(Some(stat));
    }
    Err(crate::tool_error(
        "workspace",
        format!("pool ignore '{path}' is not a regular file"),
    ))
}

async fn create_directory<B>(backend: &B, path: PathBuf) -> Result<()>
where
    B: WorkspaceFileBackend,
{
    let relative = posix_relative(&path);
    if relative == "." {
        return Ok(());
    }
    backend.create_directory(relative, None).await
}

fn posix_relative(path: &Path) -> String {
    let value = path.to_string_lossy().replace('\\', "/");
    let trimmed = value.trim_end_matches('/');
    if trimmed.is_empty() {
        ".".to_string()
    } else {
        trimmed.to_string()
    }
}
