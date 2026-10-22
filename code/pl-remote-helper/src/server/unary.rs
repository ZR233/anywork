//! 一元操作：一个请求对应一个 typed 响应。
//!
//! 所有文件原语都通过 workspace 目录能力完成（见 [`super::path`]），不把校验过的路径交回
//! ambient API；解析与 IO 都在租约上进行，不持有 registry 锁跨 await。
//!
//! FD 责任：每条操作在收到请求时已按类别取得整份预算（见 [`super::resources`]），lease 随
//! `Target`/`Directory` 进入 blocking 闭包，取消后仍在运行的 syscall 继续计费；终结响应发出
//! 之前先释放本次操作应释放的 FD 与清理。

use std::sync::Arc;

use pl_protocol::remote::{
    RemoteCopyRequest, RemoteErrorCode, RemoteFileStat, RemotePathRequest, RemoteRemoveRequest,
    RemoteRenameRequest, RemoteResponse, RemoteWorkspaceOpened,
};
use tokio::io::AsyncWrite;

use super::ServerState;
use super::path::remote_error;
use super::records::{self, OperationError};
use super::resources::{ResourceLease, WorkspaceLeases};
use crate::remote_transport::RecordWriter;

pub(super) async fn open_workspace<W>(
    state: &Arc<ServerState>,
    path: String,
    leases: WorkspaceLeases,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    // 登记即由 claim 持有撤销责任：成功响应完整发出后才把关闭责任交给 client；失败或取消时
    // 撤销登记并随 `WorkspaceRoot` 释放持久 retained 预算。
    let claim = state
        .workspaces
        .open(&path, state.tasks.clone(), leases)
        .await?;
    records::respond(
        writer,
        RemoteResponse::WorkspaceOpened(RemoteWorkspaceOpened {
            workspace_id: claim.workspace_id().to_string(),
            canonical_path: claim.root().canonical_path().to_string_lossy().into_owned(),
        }),
    )
    .await?;
    claim.commit();
    Ok(())
}

pub(super) async fn stat<W>(
    state: &Arc<ServerState>,
    request: RemotePathRequest,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.workspace_id)?;
    let facts = root.facts(&request.path, &lease).await?;
    drop(lease);
    records::respond(
        writer,
        RemoteResponse::Stat(RemoteFileStat {
            path: request.path,
            is_file: facts.is_file,
            is_directory: facts.is_directory,
            len: facts.is_file.then_some(facts.len),
            readonly: facts.readonly,
            modified_at: facts.modified_at,
        }),
    )
    .await
}

pub(super) async fn create_directory<W>(
    state: &Arc<ServerState>,
    request: RemotePathRequest,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.workspace_id)?;
    // 新建目录句柄显式关闭后才归还本次预算，之后才发终结响应。
    let created = root.ensure_directory(&request.path, &lease).await?;
    drop(created);
    drop(lease);
    records::respond(writer, RemoteResponse::Ack).await
}

pub(super) async fn remove_path<W>(
    state: &Arc<ServerState>,
    request: RemoteRemoveRequest,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.workspace_id)?;
    let target = root.target(&request.path, &lease).await?;
    target.remove(request.recursive).await?;
    drop(lease);
    records::respond(writer, RemoteResponse::Ack).await
}

pub(super) async fn rename_path<W>(
    state: &Arc<ServerState>,
    request: RemoteRenameRequest,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.workspace_id)?;
    let source = root.target(&request.source, &lease).await?;
    // 目标父目录按既有语义创建；重命名本身仍在两个 parent capability 内定位。
    let destination = root.ensure_target(&request.target, &lease).await?;
    source.rename_to(destination).await?;
    drop(lease);
    records::respond(writer, RemoteResponse::Ack).await
}

pub(super) async fn copy_path<W>(
    state: &Arc<ServerState>,
    request: RemoteCopyRequest,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.workspace_id)?;
    let facts = root.facts(&request.source, &lease).await?;
    if facts.is_directory {
        if !request.recursive {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "directory copy requires recursive=true",
            )
            .into());
        }
        // 递归类在准入时已独占整个 operation 池：仍然使用成熟 cap 递归与既有 DFS。
        let source = root.directory(&request.source, &lease).await?;
        let target = root.ensure_directory(&request.target, &lease).await?;
        source.copy_tree_to(target).await?;
    } else {
        let source = root.target(&request.source, &lease).await?;
        let target = root.ensure_target(&request.target, &lease).await?;
        source.copy_file_to(target).await?;
    }
    drop(lease);
    records::respond(writer, RemoteResponse::Ack).await
}
