//! SSH helper 服务端：一条 Yamux 连接、一个预留控制流与按操作划分的子流。
//!
//! 装配顺序固定为：`hello` 握手（控制流）→ 接受普通操作流 → 每个操作若干记录 → 显式终结。
//! 业务、编码和文件错误只终结所属操作流；连接级损坏、EOF 或物理 IO 失败才结束整条连接。
//!
//! 连接拥有控制任务、操作任务、原子提交登记表与进程登记表。任何终态都走同一条清理路径：
//! 封闭录用 → 停在途操作 → 等待进入提交阶段的上传裁决 → 终止并回收全部子进程 → 确认驱动
//! 真实终止。慢的目录枚举、文件传输或进程输出只阻塞自己的子流，不影响控制面与其他操作。
//! 入站字节租约在连接开始时启动，握手与首个控制流同样受它约束。

use std::future::Future;
use std::io;
use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;

use pl_protocol::remote::{
    RemoteError, RemoteErrorCode, RemoteMessage, RemoteRequest, RemoteShellDescriptor,
    RemoteShellDialect,
};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{oneshot, watch};
use tokio::task::JoinSet;
use tokio::time::Instant;

use crate::ServerError;
use crate::remote_transport::{
    ConnectionOwner, IncomingStreams, RecordReader, RecordWriter, RemoteStream, Role,
    TransportError,
};

mod control;
mod directory;
mod fd;
mod lease;
mod path;
mod process;
mod read_file;
mod records;
mod resources;
mod tasks;
mod unary;
mod upload;
mod write_file;

use lease::LeaseReader;
use path::{WorkspaceRegistry, remote_error};
use process::ProcessRegistry;
use records::OperationError;
use resources::{Grants, Resources};
use tasks::BlockingTasks;

/// 整条连接的终态原因；单个操作失败不会产生这里的状态。
pub(super) enum ConnectionEnd {
    /// 对端发送单向 shutdown。
    Shutdown,
    /// 对端在没有 shutdown 的情况下结束了控制通道。
    UnexpectedEof(&'static str),
    /// 入站活动租约过期。
    LeaseExpired,
    /// 连接级协议违反或传输失败。
    Failed(ServerError),
}

impl ConnectionEnd {
    fn into_result(self) -> Result<(), ServerError> {
        match self {
            Self::Shutdown => Ok(()),
            Self::UnexpectedEof(what) => Err(ServerError::Io(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                what,
            ))),
            Self::LeaseExpired => Err(ServerError::Io(io::Error::new(
                io::ErrorKind::TimedOut,
                "remote helper heartbeat lease expired",
            ))),
            Self::Failed(error) => Err(error),
        }
    }
}

/// 连接内共享状态：workspace 租约表、原子提交登记表与进程登记表只保护短事务。
pub(super) struct ServerState {
    shell: RemoteShellDescriptor,
    /// 本物理 helper 的 FD 预算（两个互不挪用的池）。
    resources: Resources,
    workspaces: WorkspaceRegistry,
    tasks: BlockingTasks,
    processes: ProcessRegistry,
}

impl ServerState {
    fn new(shell: RemoteShellDescriptor, resources: Resources) -> Self {
        Self {
            shell,
            resources,
            workspaces: WorkspaceRegistry::new(),
            tasks: BlockingTasks::new(),
            processes: ProcessRegistry::new(),
        }
    }

    /// 取得所属 workspace 的租约；registry 只保护这一次查找，不跨文件 IO。
    fn workspace(&self, workspace_id: &str) -> Result<Arc<path::WorkspaceRoot>, RemoteError> {
        self.workspaces.lease(workspace_id)
    }
}

/// 由 `lib.rs` 公开的 SSH helper 入口；只接受 stdio 上的一条 Yamux 连接。
pub async fn run_stdio() -> Result<(), ServerError> {
    let shell = detect_shell()?;
    // 任何测量失败都在接受连接之前明确失败，不发布带有猜测预算的 Hello。
    let resources = Resources::measure()?;
    run(tokio::io::stdin(), tokio::io::stdout(), shell, resources).await
}

async fn run<R, W>(
    reader: R,
    writer: W,
    shell: RemoteShellDescriptor,
    resources: Resources,
) -> Result<(), ServerError>
where
    R: AsyncRead + Unpin + Send + 'static,
    W: AsyncWrite + Unpin + Send + 'static,
{
    // 入站字节进度直接续租，不需要为租约另建心跳通道。
    let (reader, activity) = LeaseReader::new(reader);
    let (owner, _observer, incoming) = ConnectionOwner::start(reader, writer, Role::Server);
    serve(owner, incoming, activity, shell, resources).await
}

async fn serve(
    owner: ConnectionOwner,
    mut incoming: IncomingStreams,
    activity: watch::Receiver<Instant>,
    shell: RemoteShellDescriptor,
    resources: Resources,
) -> Result<(), ServerError> {
    let state = Arc::new(ServerState::new(shell, resources));
    // 租约从连接建立时就开始计时：首个控制流与半条 hello 同样不能无限等待。
    let expiry = lease::wait_expired(activity);
    tokio::pin!(expiry);
    // 第一条子流必须是控制流；握手完成前不接受普通操作。
    let control_stream = tokio::select! {
        biased;
        _ = &mut expiry => {
            return end_connection(owner, state, JoinSet::new(), None, ConnectionEnd::LeaseExpired)
                .await;
        }
        accepted = incoming.accept() => match accepted {
            Ok(Some(stream)) => stream,
            Ok(None) => {
                return end_connection(
                    owner,
                    state,
                    JoinSet::new(),
                    None,
                    ConnectionEnd::UnexpectedEof("the connection ended before the control stream"),
                )
                .await;
            }
            // 首个 accept 失败同样是连接终态：已经启动的 owner 必须走统一收尾。
            Err(error) => {
                return end_connection(
                    owner,
                    state,
                    JoinSet::new(),
                    None,
                    ConnectionEnd::Failed(transport_failure(error)),
                )
                .await;
            }
        },
    };
    let (admitted, ready) = oneshot::channel();
    let (ended, end) = oneshot::channel();
    let control = tokio::spawn(control::lane(
        state.clone(),
        control_stream,
        admitted,
        ended,
    ));
    let operations = JoinSet::new();
    // 握手完成前不接受普通操作；握手失败、控制任务提前结束与租约过期都走同一收尾。
    tokio::select! {
        biased;
        _ = &mut expiry => {
            return end_connection(
                owner,
                state,
                operations,
                Some(control),
                ConnectionEnd::LeaseExpired,
            )
            .await;
        }
        admitted = ready => {
            if admitted.is_err() {
                // 控制任务在握手完成前结束：等它交回自己的终态。
                let cause = match end.await {
                    Ok(cause) => cause,
                    Err(_) => ConnectionEnd::Failed(lost_control()),
                };
                return end_connection(owner, state, operations, Some(control), cause).await;
            }
        }
    }
    let (cause, operations) =
        accept_operations(&state, &mut incoming, operations, expiry.as_mut(), end).await;
    end_connection(owner, state, operations, Some(control), cause).await
}

/// 接受普通操作流直到连接终态；控制流终态、driver 结束与租约过期都会终止接受。
async fn accept_operations<F>(
    state: &Arc<ServerState>,
    incoming: &mut IncomingStreams,
    mut operations: JoinSet<()>,
    mut expiry: Pin<&mut F>,
    ended: oneshot::Receiver<ConnectionEnd>,
) -> (ConnectionEnd, JoinSet<()>)
where
    F: Future<Output = ()>,
{
    tokio::pin!(ended);
    let cause = loop {
        tokio::select! {
            biased;
            // 控制流终态优先：它是连接终态的唯一正常来源。
            outcome = &mut ended => {
                break match outcome {
                    Ok(cause) => cause,
                    Err(_) => ConnectionEnd::Failed(lost_control()),
                };
            }
            // helper 层面的阻塞失败（任务 panic、兜底清理失败）必须主动结束连接，否则 panic 之后
            // 的兜底清理与进程回收永远不会启动。
            failure = state.tasks.failed() => {
                break ConnectionEnd::Failed(ServerError::Cleanup(failure));
            }
            // 进程侧的 helper 层面失败（真实回收失败、panic 救援失败、job 异常结束）同样必须
            // 主动结束连接；正常命令退出码与普通操作错误不经过这条通知。
            failure = state.processes.failed() => {
                break ConnectionEnd::Failed(ServerError::Cleanup(failure));
            }
            // 操作任务异常结束（panic）同样是连接级失败；正常结束只释放自己的资源。
            // 放在接收之前：持续有业务输入时也必须立即观测，不能等下一次新流才 try_join。
            Some(result) = operations.join_next(), if !operations.is_empty() => {
                if let Err(error) = result {
                    break ConnectionEnd::Failed(operation_failure(error));
                }
            }
            accepted = incoming.accept() => match accepted {
                Ok(Some(stream)) => {
                    // 每个操作只拥有自己的子流；进程流在内部转交进程监督任务。
                    operations.spawn(operation(state.clone(), stream));
                }
                // 传输层关闭：对端可能在发出 shutdown 之后立即关闭物理连接，因此物理关闭本身
                // 不是连接原因，以控制流自己的终态为准（驱动已结束，控制流读取会立即返回；
                // 租约仍是这里的安全上界）。其他 accept 失败仍按传输失败处理。
                Ok(None) | Err(TransportError::Closed) => {
                    break tokio::select! {
                        outcome = &mut ended => match outcome {
                            Ok(cause) => cause,
                            Err(_) => ConnectionEnd::Failed(lost_control()),
                        },
                        _ = &mut expiry => ConnectionEnd::LeaseExpired,
                    };
                }
                Err(error) => {
                    break ConnectionEnd::Failed(transport_failure(error));
                }
            },
            _ = &mut expiry => break ConnectionEnd::LeaseExpired,
        }
    };
    (cause, operations)
}

/// 操作任务异常结束（panic 或被 runtime 取消）：连接级失败，不能静默丢弃。
fn operation_failure(error: tokio::task::JoinError) -> ServerError {
    ServerError::Io(io::Error::other(format!(
        "remote operation task ended abnormally: {error}"
    )))
}

/// 统一收尾：封闭准入 → 停在途操作 → 回收进程树 → 等待阻塞阶段真实终态 → 合成终态事实。
async fn end_connection(
    owner: ConnectionOwner,
    state: Arc<ServerState>,
    mut operations: JoinSet<()>,
    control: Option<tokio::task::JoinHandle<()>>,
    cause: ConnectionEnd,
) -> Result<(), ServerError> {
    // close 会等待真实终态，并把连接自身（含 shutdown 期间的）IO 失败交回这里。
    let close = owner.close().await;
    // 停在途操作：它们的析构（例如上传暂存区）在这里把阻塞清理移交给连接 owner。
    operations.shutdown().await;
    // 先回收进程（job 仍可使用目录能力），再封闭阻塞任务准入并等它们真实结束。
    // 顺序保证：操作任务与进程 job 都已经结束，之后不会再有新的阻塞工作递交，
    // 而 `close_and_wait` 还会执行它们析构时移交的清理，因此清理责任不会在下游丢失。
    let processes = state.processes.terminate_all().await;
    let tasks = state.tasks.close_and_wait().await;
    if let Some(control) = control {
        // 连接已经结束：控制任务不必再观察对端行为，直接结束并等待回收。
        control.abort();
        let _ = control.await;
    }
    finish_report(cause, close, processes, tasks)
}

/// 把「连接结束主因」与「收尾阶段的真实失败」合成一个可报告的终态。
///
/// 正常 shutdown 只有在物理关闭与全部清理都真实成功时才算成功；主因优先，清理失败既不覆盖
/// 主因也不被主因掩盖（合成一条有界消息，最多两类附加事实）。
fn finish_report(
    cause: ConnectionEnd,
    close: Result<(), TransportError>,
    processes: Result<(), RemoteError>,
    tasks: Result<(), RemoteError>,
) -> Result<(), ServerError> {
    let mut notes: Vec<String> = Vec::new();
    if let Err(error) = &processes {
        notes.push(format!("process cleanup failed: {}", error.message));
    }
    if let Err(error) = &tasks {
        notes.push(format!("blocking cleanup failed: {}", error.message));
    }
    if let Err(error) = &close {
        notes.push(format!("transport ended with: {error}"));
    }
    let primary = match cause {
        ConnectionEnd::Failed(error) => Some(error),
        other => other.into_result().err(),
    };
    match (primary, notes.is_empty()) {
        (None, true) => Ok(()),
        (None, false) => Err(ServerError::Io(io::Error::other(notes.join("; ")))),
        (Some(primary), true) => Err(primary),
        (Some(primary), false) => Err(ServerError::Io(io::Error::other(format!(
            "{primary}; {}",
            notes.join("; ")
        )))),
    }
}

/// 一个普通操作流：首条记录必须是请求，随后按该请求的响应序列收束。
async fn operation(state: Arc<ServerState>, stream: RemoteStream) {
    let (read, write) = tokio::io::split(stream);
    let mut reader = RecordReader::new(read);
    let mut writer = RecordWriter::new(write);
    let request = match read_request(&mut reader).await {
        Ok(Some(request)) => request,
        Ok(None) => return,
        Err(error) => {
            settle(&mut writer, Err(error)).await;
            return;
        }
    };
    // 收到完整请求后立刻按类别整份准入；不够立即是这条操作的 typed 错误，不进入任何等待。
    let grants = match state.resources.admit(&request) {
        Ok(grants) => grants,
        Err(error) => {
            settle(&mut writer, Err(error.into())).await;
            return;
        }
    };
    match request {
        // 进程流全双工：读写两侧都转交进程监督任务。
        RemoteRequest::Spawn(request) => match grants.expect_operation() {
            Ok(lease) => process::spawn(&state, request, lease, reader, writer).await,
            Err(error) => {
                let mut writer = writer;
                records::fail(&mut writer, error).await;
            }
        },
        request => {
            let outcome = dispatch(&state, request, grants, &mut reader, &mut writer).await;
            settle(&mut writer, outcome).await;
        }
    }
}

/// 一个操作的收束方式：业务失败回执 typed error，流失败直接结束，成功关闭写半边。
async fn settle<W>(writer: &mut RecordWriter<W>, outcome: Result<(), OperationError>)
where
    W: AsyncWrite + Unpin,
{
    match outcome {
        // 关闭写半边失败只属于这个操作流，不影响连接与其他操作。
        Ok(()) => {
            let _ = records::finish(writer).await;
        }
        Err(OperationError::Business(error)) => records::fail(writer, error).await,
        Err(OperationError::Stream) => {}
    }
}

async fn read_request<R>(
    reader: &mut RecordReader<R>,
) -> Result<Option<RemoteRequest>, OperationError>
where
    R: AsyncRead + Unpin,
{
    let Some(record) = reader.read().await.map_err(records::read_failure)? else {
        // 干净的记录边界 EOF：没有请求，也就没有需要应答的操作。
        return Ok(None);
    };
    if !record.body.is_empty() {
        return Err(invalid_record("request records must not carry a body").into());
    }
    match record.message {
        RemoteMessage::Request(request) => Ok(Some(request)),
        other => Err(invalid_record(format!(
            "operation streams accept a request first, received {other:?}"
        ))
        .into()),
    }
}

async fn dispatch<R, W>(
    state: &Arc<ServerState>,
    request: RemoteRequest,
    grants: Grants,
    reader: &mut RecordReader<R>,
    writer: &mut RecordWriter<W>,
) -> Result<(), OperationError>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    match request {
        RemoteRequest::BrowseDirectories { path } => {
            let lease = grants.expect_operation()?;
            directory::browse(state, path, lease, writer).await
        }
        RemoteRequest::OpenWorkspace { path } => {
            let leases = grants.expect_workspace()?;
            unary::open_workspace(state, path, leases, writer).await
        }
        RemoteRequest::Stat(request) => {
            let lease = grants.expect_operation()?;
            unary::stat(state, request, lease, writer).await
        }
        RemoteRequest::ReadFile(request) => {
            let lease = grants.expect_operation()?;
            read_file::read_file(state, request, lease, writer).await
        }
        RemoteRequest::WriteFile(request) => {
            let lease = grants.expect_operation()?;
            write_file::write_file(state, request, lease, reader, writer).await
        }
        RemoteRequest::ListDirectory(request) => {
            let lease = grants.expect_operation()?;
            directory::list(state, request, lease, writer).await
        }
        RemoteRequest::CreateDirectory(request) => {
            let lease = grants.expect_operation()?;
            unary::create_directory(state, request, lease, writer).await
        }
        RemoteRequest::RemovePath(request) => {
            let lease = grants.expect_operation()?;
            unary::remove_path(state, request, lease, writer).await
        }
        RemoteRequest::RenamePath(request) => {
            let lease = grants.expect_operation()?;
            unary::rename_path(state, request, lease, writer).await
        }
        RemoteRequest::CopyPath(request) => {
            let lease = grants.expect_operation()?;
            unary::copy_path(state, request, lease, writer).await
        }
        RemoteRequest::Spawn(_) => {
            Err(invalid_record("spawn transfers its stream before dispatch").into())
        }
        RemoteRequest::Hello { .. }
        | RemoteRequest::Heartbeat
        | RemoteRequest::CloseWorkspace { .. }
        | RemoteRequest::Terminate { .. }
        | RemoteRequest::Shutdown => Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "connection control must use the control lane",
        )
        .into()),
    }
}

/// 连接级传输失败；保留原始错误作为 source。
pub(super) fn transport_failure(error: TransportError) -> ServerError {
    ServerError::Io(io::Error::other(error))
}

fn lost_control() -> ServerError {
    ServerError::Io(io::Error::other("remote control lane ended unexpectedly"))
}

fn invalid_record(message: impl Into<String>) -> RemoteError {
    remote_error(RemoteErrorCode::InvalidRecord, message)
}

fn detect_shell() -> Result<RemoteShellDescriptor, ServerError> {
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
    Err(ServerError::Io(io::Error::new(
        io::ErrorKind::NotFound,
        "remote helper could not find /bin/bash or /bin/sh",
    )))
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
