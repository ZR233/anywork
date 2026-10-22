//! 文件上传流：`Ready` 之后接收声明长度的正文，显式结束校验通过才提交。
//!
//! create/overwrite 在目标目录能力内的请求独占暂存区（[`super::upload::StagedUpload`]）接收正文，
//! 完整长度、偏移连续性、显式结束与 sync 全部通过后才原子发布；提交前失败、取消或断流都不
//! 暴露半文件。append 在已持有的 parent 能力上 no-follow 打开真实文件，追加副作用无法回滚，
//! 失败时保留已写入字节并显式报错。任何模式都不放宽普通文件、`O_NOFOLLOW` 与 workspace 越界。
//!
//! FD 责任：写句柄是 [`LeasedFd<std::fs::File>`]，真实 FD 与本次操作的预算属于同一个对象，
//! 每次写入与 `sync` 都整份移入连接 owner 的阻塞任务并交回。因此没有 `tokio::fs::File` 那样的
//! 隐藏、不受跟踪的阻塞任务，也不存在「闭包已返回、结果还停在 oneshot 里却不再计费」的空窗：
//! 取消后 owner 仍 join 到真实结束，句柄在何处析构都在预算归还之前关闭。正文阶段的任何失败
//! （`Ready` 发送失败、非法 offset、超长正文、记录损坏、写错误、提前 EOF、长度不符、sync
//! 失败）都在**返回前显式 `await` 暂存清理**，操作流一直持有到删除真实结束。只有整条连接被
//! abort 或结果接收者已被取消时，暂存区才经 `Drop` 兜底移交。

use std::io::Write;
use std::sync::Arc;

use pl_protocol::remote::{
    RemoteError, RemoteErrorCode, RemoteMessage, RemoteResponse, RemoteWriteMode,
    RemoteWriteRequest,
};
use tokio::io::{AsyncRead, AsyncWrite};

use super::ServerState;
use super::fd::LeasedFd;
use super::path::{WorkspaceRoot, io_error, remote_error};
use super::records::{self, OperationError};
use super::resources::ResourceLease;
use super::tasks::BlockingTasks;
use super::upload::{StagedUpload, stage};
use crate::remote_transport::{RecordReader, RecordWriter};

pub(super) async fn write_file<R, W>(
    state: &Arc<ServerState>,
    request: RemoteWriteRequest,
    lease: ResourceLease,
    reader: &mut RecordReader<R>,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let root = state.workspace(&request.target.workspace_id)?;
    let total_len = request.total_len;
    // 本次操作的准入预算在这里交出：目标能力、暂存区与写句柄都各自持有同一份 lease 的副本，
    // 因此每个真实 FD 从打开到关闭都在计费，不依赖本函数栈帧的存活。
    let mut upload = Upload::prepare(&root, &request, state.tasks.clone(), &lease).await?;
    // 正文阶段失败必须先真正收束暂存区再返回，所以这里不用 `?` 提前返回。
    let outcome = transfer(&mut upload, total_len, reader, writer).await;
    match outcome {
        Ok(()) => {
            upload.commit(state).await?;
            records::respond(writer, RemoteResponse::Transferred { bytes: total_len }).await
        }
        Err(primary) => Err(merge(primary, upload.cleanup(state).await)),
    }
}

/// `Ready` 之后的正文阶段：所有失败都交回调用方，由它先收束暂存区再决定返回值。
async fn transfer<R, W>(
    upload: &mut Upload,
    total_len: u64,
    reader: &mut RecordReader<R>,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    records::respond(writer, RemoteResponse::Ready).await?;
    let mut received = 0_u64;
    loop {
        let Some(record) = reader.read().await.map_err(records::read_failure)? else {
            return Err(incomplete(format!(
                "upload stream ended after {received} of {total_len} bytes"
            ))
            .into());
        };
        // 正文与元数据分开持有：正文长度就是这次声明的进度。
        let message = record.message;
        let body = record.body;
        match message {
            RemoteMessage::Data { offset } => {
                if offset != received {
                    return Err(invalid_record(format!(
                        "upload chunk offset {offset} does not continue at {received}"
                    ))
                    .into());
                }
                let next = received.checked_add(body.len() as u64).ok_or_else(|| {
                    OperationError::Business(invalid_record("upload length overflowed".to_string()))
                })?;
                if next > total_len {
                    return Err(invalid_record(format!(
                        "upload body exceeds the declared {total_len} bytes"
                    ))
                    .into());
                }
                upload.write(&body).await?;
                received = next;
            }
            RemoteMessage::UploadFinished {
                total_len: finished,
            } => {
                if !body.is_empty() {
                    return Err(
                        invalid_record("uploadFinished must not carry a body".to_string()).into(),
                    );
                }
                if finished != total_len {
                    return Err(invalid_record(format!(
                        "uploadFinished declares {finished} bytes but the request declared {total_len}"
                    ))
                    .into());
                }
                break;
            }
            _ => {
                return Err(invalid_record(
                    "upload streams accept data and uploadFinished records only".to_string(),
                )
                .into());
            }
        }
    }
    if received != total_len {
        return Err(incomplete(format!(
            "upload received {received} of {total_len} declared bytes"
        ))
        .into());
    }
    Ok(())
}

/// 已准备的上传目标：`staged` 为 `None` 时是 append 的真实追加句柄。
struct Upload {
    /// 写句柄（FD + 预算）：只通过连接 owner 的阻塞任务使用（`take`/交回），不在异步上下文直接 IO。
    writer: Option<LeasedFd<std::fs::File>>,
    staged: Option<StagedUpload>,
    tasks: BlockingTasks,
}

impl Upload {
    async fn prepare(
        root: &WorkspaceRoot,
        request: &RemoteWriteRequest,
        tasks: BlockingTasks,
        lease: &ResourceLease,
    ) -> Result<Self, OperationError> {
        let target = root.ensure_target(&request.target.path, lease).await?;
        match request.mode {
            // append 保留已有真实副作用：直接在 parent 能力上打开现有普通文件。
            RemoteWriteMode::Append => Ok(Self {
                writer: Some(target.open_append().await?),
                staged: None,
                tasks,
            }),
            RemoteWriteMode::Create | RemoteWriteMode::Overwrite => {
                let (staged, file) = stage(target, request.mode).await?;
                Ok(Self {
                    writer: Some(file),
                    staged: Some(staged),
                    tasks,
                })
            }
        }
    }

    async fn write(&mut self, body: &[u8]) -> Result<(), OperationError> {
        let Some(handle) = self.writer.take() else {
            return Err(
                remote_error(RemoteErrorCode::Io, "upload writer is no longer available").into(),
            );
        };
        let tasks = self.tasks.clone();
        let body = body.to_vec();
        let (handle, ()) = tasks
            .run(move || {
                let mut handle = handle;
                // 句柄自带预算：闭包在真实写结束后才把它交回。
                handle
                    .get_mut()
                    .write_all(&body)
                    .map_err(|error| io_error("failed to write upload body", error))?;
                Ok((handle, ()))
            })
            .await?;
        self.writer = Some(handle);
        Ok(())
    }

    /// 失败路径的显式收束：暂存区在返回前真正删除，操作流一直持有到清理结束。
    ///
    /// 返回清理失败（已同时归档到连接 owner）；`None` 表示没有残留资源：append 的字节已经
    /// 写进真实文件，失败不能伪装成回滚，也没有暂存区要删。
    async fn cleanup(self, state: &ServerState) -> Option<RemoteError> {
        let Self { writer, staged, .. } = self;
        // 先关掉写入句柄（FD 与预算同源），再删除它所在的暂存目录。
        drop(writer);
        let staged = staged?;
        discard(state, staged).await
    }

    /// 完整长度与显式结束已由调用方确认；这里只做 sync 与原子发布。
    ///
    /// sync 与发布都提交给连接的 [`super::tasks::BlockingTasks`]：调用方取消不会让它们逃出
    /// 清理责任，连接终态会等到真实终态。
    ///
    /// 提交线性化点是「publish job 被连接 owner 接纳」（`BlockingTasks::run` 的交接），不是之后
    /// `hard_link`/`rename` 开始：受理之后的取消仍由 owner 裁决到真实终态，受理之前的失败或取
    /// 消只丢弃本次暂存区（显式 `discard`），因此不会偷偷发布；ACK 丢失不得重放。
    async fn commit(mut self, state: &ServerState) -> Result<(), OperationError> {
        // 写入句柄是 `std::fs::File`：没有用户态缓冲，直接 sync 持久化（句柄在闭包内关闭）。
        let Some(handle) = self.writer.take() else {
            return Err(
                remote_error(RemoteErrorCode::Io, "upload writer is no longer available").into(),
            );
        };
        let tasks = self.tasks.clone();
        let synced = tasks
            .run(move || {
                // 句柄与预算同源：sync 完成后句柄随闭包关闭，预算随后归还。
                handle
                    .get()
                    .sync_all()
                    .map_err(|error| io_error("failed to sync uploaded file", error))
            })
            .await;
        if let Err(error) = synced {
            // sync 失败：暂存区内容不能发布，必须在返回前显式收束，不留待兜底清理。
            return Err(merge(error.into(), self.cleanup(state).await));
        }
        let Some(staged) = self.staged.take() else {
            // append：字节已经写进真实文件，失败不能伪装成回滚。
            return Ok(());
        };
        // 暂存区仍持有本操作的预算：publish 的真实终态在预算内完成。
        state
            .tasks
            .run(move || staged.publish())
            .await
            .map_err(Into::into)
    }
}

/// 在阻塞 owner 里删除暂存区；失败既归档到连接 owner，也返回给调用方合并进原错误。
async fn discard(state: &ServerState, staged: StagedUpload) -> Option<RemoteError> {
    match state.tasks.run(move || staged.discard()).await {
        Ok(()) => None,
        Err(error) => {
            state.tasks.report_failure(error.clone());
            Some(error)
        }
    }
}

/// 保留原始失败，并把清理失败并入仍可回执的响应；流已不可用时清理失败已由 owner 归档。
fn merge(primary: OperationError, cleanup: Option<RemoteError>) -> OperationError {
    match (primary, cleanup) {
        (primary, None) => primary,
        (OperationError::Business(primary), Some(cleanup)) => {
            OperationError::Business(RemoteError {
                code: primary.code,
                message: format!(
                    "{}; upload cleanup also failed: {}",
                    primary.message, cleanup.message
                ),
            })
        }
        (OperationError::Stream, Some(_)) => OperationError::Stream,
    }
}

fn incomplete(message: String) -> RemoteError {
    remote_error(RemoteErrorCode::TransferIncomplete, message)
}

fn invalid_record(message: String) -> RemoteError {
    remote_error(RemoteErrorCode::InvalidRecord, message)
}
