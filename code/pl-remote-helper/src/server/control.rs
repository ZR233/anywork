//! 预留控制流：连接握手与有界控制事务的唯一 owner。
//!
//! 第一个被接受的子流必须是控制流；它的第一条记录必须是 `hello`。协议版本不匹配时明确回执
//! 并结束连接，只有握手成功后普通操作流才被接受。
//!
//! 控制事务由本任务串行执行到结果，调用方取消不会遗弃已经部分发送的事务。业务错误只回执给
//! 对应的控制请求；结构性损坏（非请求记录、正文、重复 hello、把普通操作放到控制流）是连接
//! 级违反，回执后结束连接。`shutdown` 是单向的：只结束连接，不产生响应。
//!
//! 控制流上的每个真实 IO 失败都带回连接终态，不会被“已决定关闭”吞掉：只有对端显式
//! shutdown 才算正常结束，未发送 shutdown 的 EOF 明确报告为意外结束。

use std::io;
use std::sync::Arc;

use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemoteCapability, RemoteError, RemoteErrorCode, RemoteHello,
    RemoteMessage, RemoteRequest, RemoteResponse, RemoteShellDescriptor,
};
use tokio::io::AsyncWrite;
use tokio::sync::oneshot;

use super::path::remote_error;
use super::{ConnectionEnd, ServerState, transport_failure};
use crate::ServerError;
use crate::remote_transport::{RecordReader, RecordWriter, RemoteStream};

pub(super) async fn lane(
    state: Arc<ServerState>,
    stream: RemoteStream,
    ready: oneshot::Sender<()>,
    ended: oneshot::Sender<ConnectionEnd>,
) {
    let end = serve(state, stream, ready).await;
    let _ = ended.send(end);
}

async fn serve(
    state: Arc<ServerState>,
    stream: RemoteStream,
    ready: oneshot::Sender<()>,
) -> ConnectionEnd {
    let (read, write) = tokio::io::split(stream);
    let mut reader = RecordReader::new(read);
    let mut writer = RecordWriter::new(write);
    if let Err(end) = handshake(&mut reader, &mut writer, &state.shell, &state.resources).await {
        return end;
    }
    if ready.send(()).is_err() {
        // 接受循环已经结束，本次连接不再可用。
        return ConnectionEnd::UnexpectedEof("the connection closed before admitting operations");
    }
    loop {
        let record = match reader.read().await {
            Ok(Some(record)) => record,
            Ok(None) => {
                // 未发送 shutdown 的控制流结束：清理路径相同，但终态必须区分。
                return ConnectionEnd::UnexpectedEof(
                    "the remote control stream ended without a shutdown request",
                );
            }
            Err(error) => return ConnectionEnd::Failed(transport_failure(error)),
        };
        if !record.body.is_empty() {
            return violate(
                &mut writer,
                remote_error(
                    RemoteErrorCode::InvalidRecord,
                    "control records must not carry a body",
                ),
            )
            .await;
        }
        let request = match record.message {
            RemoteMessage::Request(request) => request,
            other => {
                return violate(
                    &mut writer,
                    remote_error(
                        RemoteErrorCode::InvalidRecord,
                        format!("control accepts request records only, received {other:?}"),
                    ),
                )
                .await;
            }
        };
        match transaction(&state, request).await {
            Transaction::Reply(response) => {
                if let Err(end) = respond(&mut writer, response).await {
                    return end;
                }
            }
            Transaction::Shutdown => {
                // 单向关闭：先结束写半边，不再等待对端确认；真实失败必须反映到退出语义。
                return match writer.finish().await {
                    Ok(()) => ConnectionEnd::Shutdown,
                    Err(error) => ConnectionEnd::Failed(transport_failure(error)),
                };
            }
            Transaction::Violation(error) => return violate(&mut writer, error).await,
        }
    }
}

/// 控制流应答；真实 IO 失败作为连接终态交回。
async fn respond<W>(
    writer: &mut RecordWriter<W>,
    response: RemoteResponse,
) -> Result<(), ConnectionEnd>
where
    W: AsyncWrite + Unpin,
{
    writer
        .send(&RemoteMessage::Response(response), &[])
        .await
        .map_err(|error| ConnectionEnd::Failed(transport_failure(error)))
}

/// 严格握手；返回错误时连接必须结束，不接受任何普通操作。
async fn handshake<R, W>(
    reader: &mut RecordReader<R>,
    writer: &mut RecordWriter<W>,
    shell: &RemoteShellDescriptor,
    resources: &super::resources::Resources,
) -> Result<(), ConnectionEnd>
where
    R: tokio::io::AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let record = match reader.read().await {
        Ok(Some(record)) => record,
        Ok(None) => {
            return Err(ConnectionEnd::UnexpectedEof(
                "the connection ended before the hello handshake",
            ));
        }
        Err(error) => return Err(ConnectionEnd::Failed(transport_failure(error))),
    };
    if !record.body.is_empty() {
        let error = remote_error(
            RemoteErrorCode::InvalidRecord,
            "control records must not carry a body",
        );
        return Err(violate(writer, error).await);
    }
    let protocol_version = match record.message {
        RemoteMessage::Request(RemoteRequest::Hello { protocol_version }) => protocol_version,
        _ => {
            let error = remote_error(
                RemoteErrorCode::InvalidRequest,
                "the first control record must be hello",
            );
            return Err(violate(writer, error).await);
        }
    };
    if protocol_version != REMOTE_PROTOCOL_VERSION {
        return Err(
            violate(
                writer,
                remote_error(
                    RemoteErrorCode::ProtocolMismatch,
                    format!(
                        "protocol version {protocol_version} is incompatible with helper version {REMOTE_PROTOCOL_VERSION}"
                    ),
                ),
            )
            .await,
        );
    }
    respond(writer, RemoteResponse::Hello(hello(shell, resources))).await
}

enum Transaction {
    Reply(RemoteResponse),
    Shutdown,
    Violation(RemoteError),
}

async fn transaction(state: &Arc<ServerState>, request: RemoteRequest) -> Transaction {
    match request {
        RemoteRequest::Heartbeat => Transaction::Reply(RemoteResponse::Ack),
        RemoteRequest::Terminate { process_id } => {
            // 只确认终止意图已送达；实际退出与 capture 仍从那进程自己的流结算。
            Transaction::Reply(match state.processes.terminate(&process_id) {
                Ok(()) => RemoteResponse::Ack,
                Err(error) => RemoteResponse::Error(error),
            })
        }
        RemoteRequest::CloseWorkspace { workspace_id } => {
            // 只封闭新租赁；在途操作持有的租约自行完成。
            Transaction::Reply(match state.workspaces.close(&workspace_id) {
                Ok(()) => RemoteResponse::Ack,
                Err(error) => RemoteResponse::Error(error),
            })
        }
        RemoteRequest::Shutdown => Transaction::Shutdown,
        RemoteRequest::Hello { .. } => Transaction::Violation(remote_error(
            RemoteErrorCode::InvalidRequest,
            "hello is accepted once per connection",
        )),
        _ => Transaction::Violation(remote_error(
            RemoteErrorCode::InvalidRequest,
            "control accepts hello, heartbeat, terminate, closeWorkspace and shutdown only",
        )),
    }
}

/// 回执连接级违反并结束连接；如果回执本身失败，真实传输失败更优先。
async fn violate<W>(writer: &mut RecordWriter<W>, error: RemoteError) -> ConnectionEnd
where
    W: AsyncWrite + Unpin,
{
    let message = format!(
        "remote control violation ({:?}): {}",
        error.code, error.message
    );
    if let Err(transport) = writer
        .send(&RemoteMessage::Response(RemoteResponse::Error(error)), &[])
        .await
    {
        return ConnectionEnd::Failed(transport_failure(transport));
    }
    let message = match writer.finish().await {
        Ok(()) => message,
        Err(error) => format!("{message}; closing the control stream also failed: {error}"),
    };
    ConnectionEnd::Failed(ServerError::Io(io::Error::new(
        io::ErrorKind::InvalidData,
        message,
    )))
}

fn hello(shell: &RemoteShellDescriptor, resources: &super::resources::Resources) -> RemoteHello {
    RemoteHello {
        protocol_version: REMOTE_PROTOCOL_VERSION,
        helper_version: env!("CARGO_PKG_VERSION").to_string(),
        os: std::env::consts::OS.to_string(),
        architecture: std::env::consts::ARCH.to_string(),
        capabilities: vec![
            RemoteCapability::DirectoryBrowse,
            RemoteCapability::WorkspaceFiles,
            RemoteCapability::ObservableExec,
        ],
        shell: shell.clone(),
        // 本物理 helper 的真实 FD 预算；consumer 只消费，不复制成本常量。
        resources: resources.limits(),
    }
}
