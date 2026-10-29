//! Physical helper operations; transport/session ownership lives in session.
use crate::path::{WorkspaceRegistry, io_error, remote_error};
use crate::transport::Bytes;
use pl_protocol::remote::*;
use std::io;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

mod directories;
mod process;
mod regular_file;
mod session;
mod transfers;

use process::ProcessRegistry;
pub use session::{attach_stdio, run_owner, run_stdio};

#[derive(Debug)]
struct ServerState {
    workspaces: WorkspaceRegistry,
    shell: RemoteShellDescriptor,
}

async fn handle_request(
    state: &Arc<Mutex<ServerState>>,
    processes: &ProcessRegistry,
    request: RemoteRequest,
    body: Bytes,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    match request {
        RemoteRequest::OpenWorkspace { path } => open_workspace(state, &path).await,
        RemoteRequest::CloseWorkspace { workspace_id } => {
            state.lock().await.workspaces.close(&workspace_id)?;
            Ok(ack())
        }
        RemoteRequest::Stat(request) => stat(state, request).await,
        RemoteRequest::CreateDirectory(request) => create_directory(state, request).await,
        RemoteRequest::RemovePath(request) => remove_path(state, request).await,
        RemoteRequest::RenamePath(request) => rename_path(state, request).await,
        RemoteRequest::CopyPath(request) => copy_path(state, request).await,
        RemoteRequest::Spawn(request) => {
            let (cwd, capture_path) = {
                let workspaces = state.lock().await.workspaces.clone();
                let cwd = workspaces
                    .resolve_existing(&request.workspace_id, &request.cwd)
                    .await?;
                let capture = match &request.capture {
                    pl_protocol::remote::RemoteCapture::None => None,
                    pl_protocol::remote::RemoteCapture::Files {
                        stdout_path,
                        stderr_path,
                        ..
                    } => Some((
                        workspaces
                            .resolve_for_write(&request.workspace_id, stdout_path)
                            .await?,
                        workspaces
                            .resolve_for_write(&request.workspace_id, stderr_path)
                            .await?,
                    )),
                };
                (cwd, capture)
            };
            let process_id = request.process_id.clone();
            processes.spawn(request, cwd, capture_path).await?;
            Ok((RemoteResponse::ProcessSpawned { process_id }, Vec::new()))
        }
        RemoteRequest::WriteStdin { process_id, offset } => {
            let offset = processes.write_stdin(&process_id, offset, &body).await?;
            Ok((RemoteResponse::InputOffset { offset }, Vec::new()))
        }
        RemoteRequest::CloseStdin { process_id } => {
            processes.close_stdin(&process_id).await?;
            Ok(ack())
        }
        RemoteRequest::Terminate { process_id } => {
            processes.terminate(&process_id).await?;
            Ok(ack())
        }
        RemoteRequest::Hello { .. }
        | RemoteRequest::Attach { .. }
        | RemoteRequest::Configure { .. }
        | RemoteRequest::Heartbeat
        | RemoteRequest::OutputConsumed { .. }
        | RemoteRequest::ReleaseProcess { .. }
        | RemoteRequest::WaitProcess { .. }
        | RemoteRequest::OperationResult { .. }
        | RemoteRequest::ReleaseOperation { .. }
        | RemoteRequest::BrowseDirectories { .. }
        | RemoteRequest::ListDirectory(_)
        | RemoteRequest::ContinueDirectory { .. }
        | RemoteRequest::CloseDirectory { .. }
        | RemoteRequest::OpenRead(_)
        | RemoteRequest::ReadFileChunk { .. }
        | RemoteRequest::BeginWrite(_)
        | RemoteRequest::WriteChunk { .. }
        | RemoteRequest::TransferStatus { .. }
        | RemoteRequest::CommitWrite { .. }
        | RemoteRequest::CloseTransfer { .. }
        | RemoteRequest::Shutdown => Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "operation requires its session owner",
        )),
    }
}

fn detect_shell() -> Result<RemoteShellDescriptor, RemoteError> {
    for (dialect, path) in [
        (RemoteShellDialect::Bash, "/bin/bash"),
        (RemoteShellDialect::Sh, "/bin/sh"),
    ] {
        if is_executable(Path::new(path)) {
            return Ok(RemoteShellDescriptor {
                dialect,
                path: path.to_string(),
            });
        }
    }
    Err(remote_error(
        RemoteErrorCode::Io,
        "remote helper could not find /bin/bash or /bin/sh",
    ))
}

fn is_executable(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

async fn open_workspace(
    state: &Arc<Mutex<ServerState>>,
    path: &str,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    let canonical_path = WorkspaceRegistry::resolve_workspace_root(path).await?;
    let (workspace_id, canonical_path) = state
        .lock()
        .await
        .workspaces
        .open_resolved(canonical_path)?;
    Ok((
        RemoteResponse::WorkspaceOpened(RemoteWorkspaceOpened {
            workspace_id,
            canonical_path: canonical_path.to_string_lossy().into_owned(),
        }),
        Vec::new(),
    ))
}

async fn stat(
    state: &Arc<Mutex<ServerState>>,
    request: RemotePathRequest,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    let workspaces = state.lock().await.workspaces.clone();
    let path = workspaces
        .resolve_existing(&request.workspace_id, &request.path)
        .await?;
    let metadata = tokio::fs::metadata(&path)
        .await
        .map_err(|error| io_error("failed to stat path", error))?;
    Ok((
        RemoteResponse::Stat(RemoteFileStat {
            path: request.path,
            is_file: metadata.is_file(),
            is_directory: metadata.is_dir(),
            len: metadata.is_file().then_some(metadata.len()),
            readonly: metadata.permissions().readonly(),
            modified_at: metadata
                .modified()
                .ok()
                .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                .and_then(|duration| i64::try_from(duration.as_secs()).ok()),
        }),
        Vec::new(),
    ))
}

async fn create_directory(
    state: &Arc<Mutex<ServerState>>,
    request: RemotePathRequest,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    let workspaces = state.lock().await.workspaces.clone();
    let path = workspaces
        .resolve_for_write(&request.workspace_id, &request.path)
        .await?;
    tokio::fs::create_dir_all(path)
        .await
        .map_err(|error| io_error("failed to create directory", error))?;
    Ok(ack())
}

async fn remove_path(
    state: &Arc<Mutex<ServerState>>,
    request: RemoteRemoveRequest,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    let workspaces = state.lock().await.workspaces.clone();
    let path = workspaces
        .resolve_existing(&request.workspace_id, &request.path)
        .await?;
    let metadata = tokio::fs::metadata(&path)
        .await
        .map_err(|error| io_error("failed to inspect removal target", error))?;
    if metadata.is_dir() {
        if request.recursive {
            tokio::fs::remove_dir_all(path)
                .await
                .map_err(|error| io_error("failed to remove directory", error))?;
        } else {
            tokio::fs::remove_dir(path)
                .await
                .map_err(|error| io_error("failed to remove empty directory", error))?;
        }
    } else {
        tokio::fs::remove_file(path)
            .await
            .map_err(|error| io_error("failed to remove file", error))?;
    }
    Ok(ack())
}

async fn rename_path(
    state: &Arc<Mutex<ServerState>>,
    request: RemoteRenameRequest,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    let workspaces = state.lock().await.workspaces.clone();
    let source = workspaces
        .resolve_existing(&request.workspace_id, &request.source)
        .await?;
    let target = workspaces
        .resolve_for_write(&request.workspace_id, &request.target)
        .await?;
    if let Some(parent) = target.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|error| io_error("failed to create rename directory", error))?;
    }
    tokio::fs::rename(source, target)
        .await
        .map_err(|error| io_error("failed to rename path", error))?;
    Ok(ack())
}

async fn copy_path(
    state: &Arc<Mutex<ServerState>>,
    request: RemoteCopyRequest,
) -> Result<(RemoteResponse, Vec<u8>), RemoteError> {
    let workspaces = state.lock().await.workspaces.clone();
    let source = workspaces
        .resolve_existing(&request.workspace_id, &request.source)
        .await?;
    let target = workspaces
        .resolve_for_write(&request.workspace_id, &request.target)
        .await?;
    if let Some(parent) = target.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|error| io_error("create copy directory", error))?;
    }
    regular_file::copy(source, target)
        .await
        .map_err(|error| io_error("copy file", error))?;
    Ok(ack())
}

fn ack() -> (RemoteResponse, Vec<u8>) {
    (RemoteResponse::Ack, Vec::new())
}
