//! 单条操作的记录出口。
//!
//! 每条记录恒定由一份 typed 元数据和一份原始正文组成，正文为空也保留独立帧；编码、长度
//! 校验与发布由共用传输负责。业务失败以 typed error 终结所属操作流。
//!
//! 读、写两侧的传输失败语义不同，因此分别映射，且对 [`TransportError`] 的每个变体都显式
//! 表态：写前被本地拒绝的记录（`RecordTooLarge`/`Encoding`/正文与消息不匹配）在发布任何
//! 字节前失败，流仍然可用，可以回执 typed error；读侧的对端记录问题只终结该操作；连接
//! 关闭、取消与物理 IO 失败则无法再回执。

use pl_protocol::remote::{
    RemoteDirectoryEntry, RemoteError, RemoteErrorCode, RemoteEvent, RemoteMessage, RemoteResponse,
};
use tokio::io::AsyncWrite;

use super::path::remote_error;
use crate::remote_transport::{RecordWriter, TransportError};

/// 操作流的终态。业务错误尽力回执；流错误无法再回执，只结束该操作。
#[derive(Debug)]
pub(super) enum OperationError {
    Business(RemoteError),
    Stream,
}

impl From<RemoteError> for OperationError {
    fn from(error: RemoteError) -> Self {
        Self::Business(error)
    }
}

/// 读记录失败：对端记录问题可以（尽力）作为 typed error 回执，其余无法应答。
pub(super) fn read_failure(error: TransportError) -> OperationError {
    match error {
        // 对端交来的记录违反契约或超出单记录预算：本端 reader 已永久失效，
        // 但写半边仍可用，因此回执 InvalidRecord 并结束该操作。
        error @ (TransportError::InvalidRecord { .. }
        | TransportError::RecordTooLarge { .. }
        | TransportError::Encoding { .. }) => OperationError::Business(remote_error(
            RemoteErrorCode::InvalidRecord,
            format!("remote record could not be read: {error}"),
        )),
        // 连接关闭、操作取消、物理 IO、复用器、控制流抢占或 driver 异常：无法应答。
        TransportError::Closed
        | TransportError::Cancelled
        | TransportError::ControlAlreadyOpened
        | TransportError::Io(_)
        | TransportError::Multiplex(_)
        | TransportError::DriverTask(_) => OperationError::Stream,
    }
}

/// 写记录失败：只有发布前被本地拒绝的记录还能回执。
pub(super) fn send_failure(error: TransportError) -> OperationError {
    match error {
        // 这三类由本端在发布任何字节之前拒绝（超预算、编码失败、正文与消息不匹配），
        // 记录不会出现在流上，因此可以回执 InvalidRequest 并保持连接可用。
        error @ (TransportError::RecordTooLarge { .. }
        | TransportError::Encoding { .. }
        | TransportError::InvalidRecord { .. }) => OperationError::Business(remote_error(
            RemoteErrorCode::InvalidRequest,
            format!("remote record was rejected locally: {error}"),
        )),
        // 其余说明该流或物理连接已经不可用。
        TransportError::Closed
        | TransportError::Cancelled
        | TransportError::ControlAlreadyOpened
        | TransportError::Io(_)
        | TransportError::Multiplex(_)
        | TransportError::DriverTask(_) => OperationError::Stream,
    }
}

/// 需要一个 typed 原因（例如进程终态）时的传输失败映射。
pub(super) fn stream_failure(context: &str, error: TransportError) -> RemoteError {
    let code = match &error {
        TransportError::InvalidRecord { .. }
        | TransportError::RecordTooLarge { .. }
        | TransportError::Encoding { .. } => RemoteErrorCode::InvalidRecord,
        TransportError::Cancelled => RemoteErrorCode::Cancelled,
        TransportError::Closed
        | TransportError::ControlAlreadyOpened
        | TransportError::Io(_)
        | TransportError::Multiplex(_)
        | TransportError::DriverTask(_) => RemoteErrorCode::RemoteDisconnected,
    };
    remote_error(code, format!("{context}: {error}"))
}

pub(super) async fn respond<W>(
    writer: &mut RecordWriter<W>,
    response: RemoteResponse,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    writer
        .send(&RemoteMessage::Response(response), &[])
        .await
        .map_err(send_failure)
}

pub(super) async fn respond_error<W>(
    writer: &mut RecordWriter<W>,
    error: RemoteError,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    respond(writer, RemoteResponse::Error(error)).await
}

pub(super) async fn entry<W>(
    writer: &mut RecordWriter<W>,
    entry: RemoteDirectoryEntry,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    writer
        .send(&RemoteMessage::DirectoryEntry(entry), &[])
        .await
        .map_err(send_failure)
}

pub(super) async fn data<W>(
    writer: &mut RecordWriter<W>,
    offset: u64,
    body: &[u8],
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    writer
        .send(&RemoteMessage::Data { offset }, body)
        .await
        .map_err(send_failure)
}

pub(super) async fn event<W>(
    writer: &mut RecordWriter<W>,
    event: RemoteEvent,
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    writer
        .send(&RemoteMessage::Event(event), &[])
        .await
        .map_err(send_failure)
}

/// 进程输出携带原始字节；sequence 由每个进程自己维护。
pub(super) async fn event_body<W>(
    writer: &mut RecordWriter<W>,
    event: RemoteEvent,
    body: &[u8],
) -> Result<(), OperationError>
where
    W: AsyncWrite + Unpin,
{
    writer
        .send(&RemoteMessage::Event(event), body)
        .await
        .map_err(send_failure)
}

/// 以 typed error 终结一个操作流并关闭其写半边。
pub(super) async fn fail<W>(writer: &mut RecordWriter<W>, error: RemoteError)
where
    W: AsyncWrite + Unpin,
{
    let _ = respond_error(writer, error).await;
    let _ = finish(writer).await;
}

/// 关闭写半边，向 peer 明确该操作的正常结束。
///
/// 失败只属于这一个操作流：调用方决定是否忽略它，绝不能因此结束其他流。
pub(super) async fn finish<W>(writer: &mut RecordWriter<W>) -> Result<(), TransportError>
where
    W: AsyncWrite + Unpin,
{
    writer.finish().await
}
