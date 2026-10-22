//! 目录枚举：先发元数据，再分页逐条发布 entry，最后显式终结。
//!
//! 枚举在已持有的目录能力上分页进行，不先收集、不排序整目录；消费者可以提前停止，只有它
//! 自己 drop 流。GUI 的完整列表聚合在消费端完成，`RemoteDirectoryListing` 不是 wire 记录。

use std::sync::Arc;

use pl_protocol::remote::{
    RemoteDirectoryEntry, RemoteDirectoryMetadata, RemoteErrorCode, RemotePathRequest,
    RemoteResponse,
};
use tokio::io::AsyncWrite;

use super::ServerState;
use super::path::{Directory, WorkspaceRoot, remote_error};
use super::records::{self, OperationError};
use super::resources::ResourceLease;
use crate::remote_transport::RecordWriter;

/// GUI 目录浏览：没有 workspace 身份，只按用户显式给出的远端绝对路径枚举目录本身。
pub(super) async fn browse<W>(
    state: &Arc<ServerState>,
    path: Option<String>,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let path = path.unwrap_or_else(home_directory);
    let mut directory = WorkspaceRoot::browse(&path, state.tasks.clone(), &lease).await?;
    let display = directory.display().to_path_buf();
    records::respond(
        writer,
        RemoteResponse::Directory(RemoteDirectoryMetadata {
            path: display.to_string_lossy().into_owned(),
            parent: display
                .parent()
                .map(|parent| parent.to_string_lossy().into_owned()),
        }),
    )
    .await?;
    entries(
        writer,
        &mut directory,
        EntryPaths::Absolute,
        Selection::DirectoriesOnly,
    )
    .await?;
    // 终结前释放枚举能力与本操作的 FD 预算。
    drop(directory);
    drop(lease);
    records::respond(writer, RemoteResponse::Complete).await
}

/// workspace 相对路径枚举；entry 路径保持调用方传入的相对形式，供本地编排继续使用。
pub(super) async fn list<W>(
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
    if !facts.is_directory {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "list path is not a directory",
        )
        .into());
    }
    let mut directory = root.directory(&request.path, &lease).await?;
    records::respond(
        writer,
        RemoteResponse::Directory(RemoteDirectoryMetadata {
            parent: display_parent(&request.path),
            path: request.path.clone(),
        }),
    )
    .await?;
    entries(
        writer,
        &mut directory,
        EntryPaths::Relative(request.path.as_str()),
        Selection::All,
    )
    .await?;
    // 终结前释放枚举能力与本操作的 FD 预算。
    drop(directory);
    drop(lease);
    records::respond(writer, RemoteResponse::Complete).await
}

/// entry 的展示路径命名空间：Browse 用绝对路径，ListDirectory 用 workspace 相对路径。
enum EntryPaths<'a> {
    Absolute,
    Relative(&'a str),
}

enum Selection {
    All,
    DirectoriesOnly,
}

async fn entries<W>(
    writer: &mut RecordWriter<W>,
    directory: &mut Directory,
    paths: EntryPaths<'_>,
    selection: Selection,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    loop {
        let page = directory.page().await?;
        if page.is_empty() {
            return Ok(());
        }
        for facts in page {
            if matches!(selection, Selection::DirectoriesOnly) && !facts.is_directory {
                continue;
            }
            let name = facts.name.to_string_lossy().into_owned();
            let path = match &paths {
                EntryPaths::Absolute => directory
                    .display()
                    .join(&facts.name)
                    .to_string_lossy()
                    .into_owned(),
                EntryPaths::Relative(display) => join_display(display, &name),
            };
            records::entry(
                writer,
                RemoteDirectoryEntry {
                    name,
                    path,
                    is_directory: facts.is_directory,
                    is_symlink: facts.is_symlink,
                },
            )
            .await?;
        }
    }
}

fn home_directory() -> String {
    std::env::var("HOME").unwrap_or_else(|_| "/".to_string())
}

fn join_display(display: &str, name: &str) -> String {
    let trimmed = display.trim_end_matches('/');
    if trimmed.is_empty() || trimmed == "." {
        name.to_string()
    } else {
        format!("{trimmed}/{name}")
    }
}

/// 相对父路径。
///
/// workspace 根返回 `None`，根下的直接子目录返回 `"."`，更深层保持 display 相对形式；
/// Browse 使用绝对路径，两者都是 POSIX 形式，父路径与 `path` 的命名空间保持一致。
fn display_parent(display: &str) -> Option<String> {
    let trimmed = display.trim_end_matches('/');
    if trimmed.is_empty() || trimmed == "." {
        return None;
    }
    match trimmed.rsplit_once('/') {
        Some((parent, _)) if !parent.is_empty() => Some(parent.to_string()),
        _ => Some(".".to_string()),
    }
}
