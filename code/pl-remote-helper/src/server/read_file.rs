//! 文件读取流：同一普通文件句柄声明总长度后按绝对偏移分块传输。
//!
//! 句柄由 workspace 目录能力 no-follow 打开（见 [`super::path`]），元数据在打开那一刻确定，
//! 正文只从该句柄产出，不每块重新打开文件。实际读长、文件长度变化或声明长度不一致时以
//! `TransferIncomplete` 终结，不能用 EOF 冒充成功。
//!
//! FD 责任：句柄是 [`LeasedFd<std::fs::File>`]，真实 FD 与本次操作的预算属于同一个对象，整份
//! 在阻塞任务之间移交。因此不存在 `tokio::fs::File` 那种隐藏的、不受跟踪的 `spawn_blocking`，
//! 也不会出现「闭包已返回、结果还停在 oneshot 里却不再计费」的空窗：调用方取消后 owner 仍
//! 真实 join，句柄在何处析构都在预算归还之前关闭。

use std::io::{Read, Seek, SeekFrom};
use std::sync::Arc;

use pl_protocol::remote::{RemoteErrorCode, RemoteFileMetadata, RemoteReadRequest, RemoteResponse};
use tokio::io::AsyncWrite;

use super::ServerState;
use super::path::{io_error, remote_error};
use super::records::{self, OperationError};
use super::resources::ResourceLease;
use crate::remote_transport::{DATA_CHUNK_BYTES, RecordWriter};

pub(super) async fn read_file<W>(
    state: &Arc<ServerState>,
    request: RemoteReadRequest,
    lease: ResourceLease,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.workspace_id)?;
    let target = root.target(&request.path, &lease).await?;
    let mut handle = target.open_read().await?;
    // 文件句柄已取得：parent 能力可以立刻释放，句柄自带预算进入每次阻塞 IO。
    drop(target);
    let tasks = state.tasks.clone();

    // 同一句柄上取总长度；之后不再重新打开文件。
    let (kept, total_len) = tasks
        .run(move || {
            let handle = handle;
            let total_len = handle
                .get()
                .metadata()
                .map_err(|error| io_error("failed to inspect read file", error))?
                .len();
            Ok((handle, total_len))
        })
        .await?;
    handle = kept;
    if request.offset > total_len {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            format!(
                "read offset {} is beyond the {total_len} byte file",
                request.offset
            ),
        )
        .into());
    }
    let remaining = total_len - request.offset;
    let transfer_len = match request.max_bytes {
        Some(limit) => remaining.min(limit),
        None => remaining,
    };
    let offset = request.offset;
    let (kept, ()) = tasks
        .run(move || {
            let mut handle = handle;
            handle
                .get_mut()
                .seek(SeekFrom::Start(offset))
                .map_err(|error| io_error("failed to seek read file", error))?;
            Ok((handle, ()))
        })
        .await?;
    handle = kept;
    records::respond(
        writer,
        RemoteResponse::File(RemoteFileMetadata {
            offset: request.offset,
            total_len,
            transfer_len,
        }),
    )
    .await?;
    let mut offset = request.offset;
    let mut transferred = 0_u64;
    while transferred < transfer_len {
        // 单条记录正文受传输预算约束：内存单位不代表文件总量上限。
        let wanted = (transfer_len - transferred).min(DATA_CHUNK_BYTES as u64) as usize;
        let (kept, chunk, count) = tasks
            .run(move || {
                let mut handle = handle;
                let mut chunk = vec![0_u8; wanted];
                let count = handle
                    .get_mut()
                    .read(&mut chunk)
                    .map_err(|error| io_error("failed to read file", error))?;
                Ok((handle, chunk, count))
            })
            .await?;
        handle = kept;
        if count == 0 {
            return Err(remote_error(
                RemoteErrorCode::TransferIncomplete,
                format!("file ended after {transferred} of {transfer_len} declared bytes"),
            )
            .into());
        }
        records::data(writer, offset, &chunk[..count]).await?;
        offset += count as u64;
        transferred += count as u64;
    }
    // 元数据来自打开时的句柄；发布成功终态前再确认文件没有变长或变短。
    let (handle, final_len) = tasks
        .run(move || {
            let handle = handle;
            let final_len = handle
                .get()
                .metadata()
                .map_err(|error| io_error("failed to re-inspect read file", error))?
                .len();
            Ok((handle, final_len))
        })
        .await?;
    if final_len != total_len {
        return Err(remote_error(
            RemoteErrorCode::TransferIncomplete,
            format!("file length changed from {total_len} to {final_len} while reading"),
        )
        .into());
    }
    // 终结前关闭句柄、归还预算，随后不再打开新 FD。
    drop(handle);
    records::respond(writer, RemoteResponse::Transferred { bytes: transferred }).await
}
