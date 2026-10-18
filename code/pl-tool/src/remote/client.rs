use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use std::collections::HashMap;
use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::task::{Context, Poll};

use pl_protocol::remote::{
    REMOTE_OUTPUT_CHUNK_BYTES, REMOTE_OUTPUT_WINDOW, RemoteError, RemoteEvent, RemoteMessage,
    RemoteOutputStream, RemoteProcessExit, RemoteRequest, RemoteResponse, RemoteSpawnRequest,
};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, DuplexStream, ReadBuf};
use tokio::sync::{Mutex, OwnedSemaphorePermit, Semaphore, mpsc, oneshot, watch};
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;
use tokio_util::task::TaskTracker;

use super::codec::{EncodedFrame, encode_frame, read_frame};

use pl_protocol::remote::REMOTE_REQUEST_CAPACITY as REQUEST_CAPACITY;

mod process;
pub(super) mod workspace;

struct PendingRequest {
    reply: oneshot::Sender<Result<RemoteReply, RemoteClientError>>,
    _permit: OwnedSemaphorePermit,
    _workspace: Option<Arc<workspace::WorkspaceLease>>,
}

struct ControlFrame {
    frame: EncodedFrame,
    written: oneshot::Sender<io::Result<()>>,
}

struct TransportLifetime {
    cancellation: CancellationToken,
    completion: Shared<BoxFuture<'static, Result<(), Arc<tokio::task::JoinError>>>>,
}

impl Drop for TransportLifetime {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

impl std::fmt::Debug for TransportLifetime {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("TransportLifetime")
            .field("cancellation", &self.cancellation)
            .finish_non_exhaustive()
    }
}

/// SSH 认证失败诊断：保留原始失败文本，并在能解析时附带服务器公布的认证方法。
///
/// `password_offered()` 在未能从 OpenSSH `Permission denied (...)` 文本解析出方法列表时返回
/// `None`，调用方应按需要密码处理，以保持旧行为。
#[derive(Debug, Clone)]
pub struct SshAuthFailure {
    reason: String,
    methods: Vec<String>,
}

impl SshAuthFailure {
    /// 用原始失败文本与已解析的认证方法构造诊断。
    pub fn new(reason: impl Into<String>, methods: Vec<String>) -> Self {
        Self {
            reason: reason.into(),
            methods,
        }
    }

    /// 服务器是否公布了密码类认证。
    ///
    /// - 方法列表含精确的 `password`，或前缀为 `keyboard-interactive`（容忍 `keyboard-interactive:pam` 等后缀）→ `Some(true)`
    /// - 解析到方法列表但两者都没有 → `Some(false)`
    /// - 解析不到方法列表 → `None`
    pub fn password_offered(&self) -> Option<bool> {
        if self.methods.is_empty() {
            None
        } else {
            Some(
                self.methods.iter().any(|method| {
                    method == "password" || method.starts_with("keyboard-interactive")
                }),
            )
        }
    }
}

impl std::fmt::Display for SshAuthFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.reason)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum RemoteClientError {
    /// The host has sealed SSH connection admission for shutdown.
    #[error("SSH manager is closing")]
    ManagerClosing,
    #[error("remoteDisconnected")]
    Disconnected,
    #[error("remote operation cancelled before admission")]
    Cancelled,
    /// SSH authentication failed (e.g. password required or rejected).
    #[error("SSH authentication required or failed: {0}")]
    AuthenticationFailed(SshAuthFailure),
    #[error("remote helper protocol failed: {0}")]
    Protocol(String),
    #[error("remote helper rejected the request ({code:?}): {message}")]
    Remote {
        code: pl_protocol::remote::RemoteErrorCode,
        message: String,
    },
}

impl From<io::Error> for RemoteClientError {
    fn from(error: io::Error) -> Self {
        Self::Protocol(error.to_string())
    }
}

#[derive(Debug)]
pub struct RemoteReply {
    pub response: RemoteResponse,
    pub body: Vec<u8>,
}

struct RemoteProcessChannels {
    output: Option<mpsc::Sender<(RemoteOutputStream, Vec<u8>)>>,
    exit: Option<oneshot::Sender<Result<RemoteProcessExit, RemoteClientError>>>,
}

impl std::fmt::Debug for RemoteProcessChannels {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RemoteProcessChannels")
            .finish_non_exhaustive()
    }
}

struct RemoteClientInner {
    writer: mpsc::Sender<EncodedFrame>,
    control_writer: mpsc::Sender<ControlFrame>,
    capacity: Arc<Semaphore>,
    control_capacity: Arc<Semaphore>,
    pending: Mutex<HashMap<u64, PendingRequest>>,
    processes: Mutex<HashMap<String, RemoteProcessChannels>>,
    next_request_id: AtomicU64,
    last_output_sequence: AtomicU64,
    disconnected: CancellationToken,
    disconnect_reason: std::sync::Mutex<Option<String>>,
    streams: TaskTracker,
    progress: watch::Sender<Instant>,
}

impl std::fmt::Debug for RemoteClientInner {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RemoteClientInner")
            .field("next_request_id", &self.next_request_id)
            .field("disconnected", &self.disconnected)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone)]
pub struct RemoteClient {
    inner: Arc<RemoteClientInner>,
    transport: Arc<TransportLifetime>,
}

impl RemoteClient {
    pub fn from_streams<R, W>(reader: R, writer: W) -> Self
    where
        R: AsyncRead + Send + Unpin + 'static,
        W: AsyncWrite + Send + Unpin + 'static,
    {
        let (sender, receiver) = mpsc::channel(REQUEST_CAPACITY);
        let (control_writer, control_frames) = mpsc::channel(1);
        let inner = Arc::new(RemoteClientInner {
            writer: sender,
            control_writer,
            capacity: Arc::new(Semaphore::new(REQUEST_CAPACITY)),
            control_capacity: Arc::new(Semaphore::new(REQUEST_CAPACITY)),
            pending: Mutex::new(HashMap::new()),
            processes: Mutex::new(HashMap::new()),
            next_request_id: AtomicU64::new(0),
            last_output_sequence: AtomicU64::new(0),
            disconnected: CancellationToken::new(),
            disconnect_reason: Default::default(),
            streams: TaskTracker::new(),
            progress: watch::channel(Instant::now()).0,
        });
        let buffer_capacity = REMOTE_OUTPUT_CHUNK_BYTES * REMOTE_OUTPUT_WINDOW;
        let reader = tokio::io::BufReader::with_capacity(
            buffer_capacity,
            ProgressIo {
                io: reader,
                progress: inner.progress.clone(),
            },
        );
        let writer = tokio::io::BufWriter::with_capacity(
            buffer_capacity,
            ProgressIo {
                io: writer,
                progress: inner.progress.clone(),
            },
        );
        let read = tokio::spawn(read_loop(reader, inner.clone()));
        let write = tokio::spawn(write_loop(writer, receiver, control_frames, inner.clone()));
        let streams = inner.streams.clone();
        let transport = Arc::new(TransportLifetime {
            cancellation: inner.disconnected.clone(),
            completion: async move {
                let (read, write) = tokio::join!(read, write);
                streams.close();
                streams.wait().await;
                read.and(write).map_err(Arc::new)
            }
            .boxed()
            .shared(),
        });
        Self { inner, transport }
    }

    /// Waits for bounded admission and then for the remote response.
    /// Canceling before admission sends nothing. Once admitted, the pending table
    /// retains the slot until response or transport closure, even if this wait is dropped.
    /// # Errors
    /// Reports validation, disconnection and remote rejection errors.
    pub async fn request(
        &self,
        request: RemoteRequest,
        body: &[u8],
    ) -> Result<RemoteReply, RemoteClientError> {
        request_inner(&self.inner, request, body).await
    }

    /// Starts an owned command. Dropping the start wait or returned command requests
    /// cancellation; a tracked supervisor retains startup and physical exit ownership.
    /// # Errors
    /// Reports failure to admit, start or validate the remote process.
    pub async fn spawn_process(
        &self,
        request: RemoteSpawnRequest,
    ) -> Result<crate::command::ManagedCommand, RemoteClientError> {
        process::spawn(self, request, None).await
    }

    pub fn is_disconnected(&self) -> bool {
        self.inner.disconnected.is_cancelled()
    }

    pub async fn wait_disconnected(&self) {
        self.inner.disconnected.cancelled().await;
    }

    /// Closes this transport and waits for both owned IO tasks to exit.
    ///
    /// Canceling this wait does not discard their completion handles.
    /// # Errors
    /// Reports a transport task panic after both tasks have been joined.
    pub async fn close(&self) -> Result<(), RemoteClientError> {
        self.inner.disconnected.cancel();
        self.transport.completion.clone().await.map_err(|error| {
            RemoteClientError::Protocol(format!("remote transport task failed: {error}"))
        })
    }

    /// Completes an application-level heartbeat without ordinary request capacity.
    pub(crate) async fn heartbeat(&self) -> Result<(), RemoteClientError> {
        let timeout = std::time::Duration::from_secs(15);
        let request = self.request(RemoteRequest::Heartbeat, &[]);
        tokio::pin!(request);
        let mut deadline = Instant::now() + timeout;
        loop {
            if let Ok(reply) = tokio::time::timeout_at(deadline, &mut request).await {
                return expect_ack(reply?);
            }
            // Control cannot overtake a partially transferred file frame. Actual
            // byte progress extends this wait; merely enqueueing work does not.
            deadline = *self.inner.progress.borrow() + timeout;
            if deadline <= Instant::now() {
                retain_disconnect_reason(
                    &self.inner,
                    "helper heartbeat response timed out without transport progress".into(),
                );
                self.inner.disconnected.cancel();
                return Err(RemoteClientError::Disconnected);
            }
        }
    }

    /// Flushes the one-way shutdown frame locally; remote cleanup is not acknowledged.
    pub(crate) async fn request_shutdown(&self) -> Result<(), RemoteClientError> {
        self.send_control(RemoteRequest::Shutdown).await
    }

    async fn send_control(&self, request: RemoteRequest) -> Result<(), RemoteClientError> {
        send_control(&self.inner, request).await
    }

    /// First transport failure, excluding request contents and credentials.
    pub fn disconnect_reason(&self) -> Option<String> {
        self.inner
            .disconnect_reason
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn is_same_connection(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
    pub(super) async fn workspace_request(
        &self,
        lease: Arc<workspace::WorkspaceLease>,
        request: RemoteRequest,
        body: &[u8],
    ) -> Result<RemoteReply, RemoteClientError> {
        submit_workspace_request(&self.inner, request, body, Some(lease))
            .await?
            .await
            .unwrap_or(Err(RemoteClientError::Disconnected))
    }
    pub(super) async fn spawn_workspace_process(
        &self,
        lease: Arc<workspace::WorkspaceLease>,
        request: RemoteSpawnRequest,
    ) -> Result<crate::command::ManagedCommand, RemoteClientError> {
        process::spawn(self, request, Some(lease)).await
    }
}

enum RequestAdmission<'a> {
    Ordinary(mpsc::Permit<'a, EncodedFrame>),
    Control(mpsc::Permit<'a, ControlFrame>),
}

type PendingReply = oneshot::Receiver<Result<RemoteReply, RemoteClientError>>;

async fn request_inner(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: &[u8],
) -> Result<RemoteReply, RemoteClientError> {
    submit_request(inner, request, body)
        .await?
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))
}

async fn submit_request(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: &[u8],
) -> Result<PendingReply, RemoteClientError> {
    submit_workspace_request(inner, request, body, None).await
}
async fn submit_workspace_request(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: &[u8],
    workspace: Option<Arc<workspace::WorkspaceLease>>,
) -> Result<PendingReply, RemoteClientError> {
    let control = matches!(
        request,
        RemoteRequest::Terminate { .. } | RemoteRequest::Heartbeat
    );
    let capacity = if control {
        &inner.control_capacity
    } else {
        &inner.capacity
    };
    let capacity = tokio::select! {
        biased;
        () = inner.disconnected.cancelled() => return Err(RemoteClientError::Disconnected),
        permit = capacity.clone().acquire_owned() => permit.map_err(|_| RemoteClientError::Disconnected)?,
    };
    let request_id = inner
        .next_request_id
        .try_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
        .map_err(|_| RemoteClientError::Protocol("remote request identity exhausted".into()))?
        + 1;
    let frame = encode_frame(Some(request_id), RemoteMessage::Request(request), body)?;
    let admission = tokio::select! {
        biased;
        () = inner.disconnected.cancelled() => return Err(RemoteClientError::Disconnected),
        permit = async {
            if control { inner.control_writer.reserve().await.map(RequestAdmission::Control) }
            else { inner.writer.reserve().await.map(RequestAdmission::Ordinary) }
        } => permit.map_err(|_| RemoteClientError::Disconnected)?,
    };
    let (reply, receiver) = oneshot::channel();
    {
        let mut pending = inner.pending.lock().await;
        if inner.disconnected.is_cancelled() {
            return Err(RemoteClientError::Disconnected);
        }
        pending.insert(
            request_id,
            PendingRequest {
                reply,
                _permit: capacity,
                _workspace: workspace,
            },
        );
    }
    // No suspension between registration and transfer to the single transport writer.
    match admission {
        RequestAdmission::Ordinary(permit) => {
            permit.send(frame);
        }
        RequestAdmission::Control(permit) => {
            let (written, _) = oneshot::channel();
            permit.send(ControlFrame { frame, written });
        }
    }
    Ok(receiver)
}

struct ProgressIo<T> {
    io: T,
    progress: watch::Sender<Instant>,
}

impl<T: AsyncRead + Unpin> AsyncRead for ProgressIo<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let before = buffer.filled().len();
        let result = Pin::new(&mut self.io).poll_read(cx, buffer);
        if buffer.filled().len() > before {
            self.progress.send_replace(Instant::now());
        }
        result
    }
}

impl<T: AsyncWrite + Unpin> AsyncWrite for ProgressIo<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        let result = Pin::new(&mut self.io).poll_write(cx, bytes);
        if let Poll::Ready(Ok(count)) = &result
            && *count > 0
        {
            self.progress.send_replace(Instant::now());
        }
        result
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.io).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.io).poll_shutdown(cx)
    }
}

async fn forward_output(
    inner: Arc<RemoteClientInner>,
    process_id: String,
    mut incoming: mpsc::Receiver<(RemoteOutputStream, Vec<u8>)>,
    mut stdout: DuplexStream,
    mut stderr: DuplexStream,
    discard: CancellationToken,
) {
    // This task alone may wait for a consumer. The frame reader never does.
    let result: Result<(), RemoteClientError> = tokio::select! {
        biased;
        () = inner.disconnected.cancelled() => return,
        result = async {
            while let Some((stream, body)) = incoming.recv().await {
                let writer = match stream {
                    RemoteOutputStream::Stdout => &mut stdout,
                    RemoteOutputStream::Stderr => &mut stderr,
                };
                let written = tokio::select! {
                    biased;
                    () = discard.cancelled() => Ok(()),
                    result = writer.write_all(&body) => result,
                };
                if let Err(error) = written && error.kind() != io::ErrorKind::BrokenPipe {
                    return Err(RemoteClientError::from(error));
                }
                send_control(&inner, RemoteRequest::OutputConsumed {
                    process_id: process_id.clone(),
                }).await?;
            }
            Ok(())
        } => result,
    };
    if let Err(error) = result {
        retain_disconnect_reason(&inner, format!("forward process output: {error}"));
        inner.disconnected.cancel();
    }
}

async fn send_control(
    inner: &RemoteClientInner,
    request: RemoteRequest,
) -> Result<(), RemoteClientError> {
    if inner.disconnected.is_cancelled() {
        return Err(RemoteClientError::Disconnected);
    }
    let frame = encode_frame(None, RemoteMessage::Request(request), &[])?;
    let (written, completed) = oneshot::channel();
    tokio::select! {
        biased;
        () = inner.disconnected.cancelled() => return Err(RemoteClientError::Disconnected),
        result = inner.control_writer.send(ControlFrame { frame, written }) => {
            result.map_err(|_| RemoteClientError::Disconnected)?;
        }
    }
    completed
        .await
        .map_err(|_| RemoteClientError::Disconnected)??;
    Ok(())
}

struct DisconnectOnExit(CancellationToken);

impl Drop for DisconnectOnExit {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

async fn write_loop<W>(
    mut writer: W,
    mut frames: mpsc::Receiver<EncodedFrame>,
    mut controls: mpsc::Receiver<ControlFrame>,
    inner: Arc<RemoteClientInner>,
) where
    W: AsyncWrite + Unpin,
{
    let _disconnect = DisconnectOnExit(inner.disconnected.clone());
    loop {
        let (frame, receipt) = tokio::select! {
            biased;
            _ = inner.disconnected.cancelled() => break,
            control = controls.recv() => match control {
                Some(control) => (control.frame, Some(control.written)),
                None => break,
            },
            frame = frames.recv() => match frame {
                Some(frame) => (frame, None),
                None => break,
            },
        };
        let result = tokio::select! {
            biased;
            _ = inner.disconnected.cancelled() => break,
            result = frame.write(&mut writer) => result,
        };
        if let Some(receipt) = receipt {
            let _ = receipt.send(
                result
                    .as_ref()
                    .map(|_| ())
                    .map_err(|error| io::Error::new(error.kind(), error.to_string())),
            );
        }
        if let Err(error) = result {
            retain_disconnect_reason(&inner, format!("write transport: {}", error.kind()));
            break;
        }
    }
    // Dropping the stream is mandatory even when cancellation interrupted a frame.
    drop(writer);
    drop(frames);
    mark_disconnected(&inner).await;
}

async fn read_loop<R>(reader: R, inner: Arc<RemoteClientInner>)
where
    R: AsyncRead + Unpin,
{
    let _disconnect = DisconnectOnExit(inner.disconnected.clone());
    tokio::select! {
        biased;
        _ = inner.disconnected.cancelled() => {},
        result = read_frames(reader, &inner) => {
            retain_disconnect_reason(&inner, match result {
                Ok(()) => "read transport: EOF".into(),
                Err(error) => format!("read transport: {error}"),
            });
        },
    }
    mark_disconnected(&inner).await;
}

async fn read_frames<R>(mut reader: R, inner: &Arc<RemoteClientInner>) -> io::Result<()>
where
    R: AsyncRead + Unpin,
{
    while let Some(frame) = read_frame(&mut reader).await? {
        match frame.message {
            RemoteMessage::Response(response) => {
                let Some(request_id) = frame.request_id else {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "response missing request identity",
                    ));
                };
                let result = match response {
                    RemoteResponse::Error(RemoteError { code, message }) => {
                        Err(RemoteClientError::Remote { code, message })
                    }
                    response => Ok(RemoteReply {
                        response,
                        body: frame.body,
                    }),
                };
                if let Some(sender) = inner.pending.lock().await.remove(&request_id)
                    && let Err(Ok(reply)) = sender.reply.send(result)
                    && let RemoteResponse::WorkspaceOpened(opened) = reply.response
                {
                    workspace::close_workspace(inner.clone(), opened.workspace_id);
                }
            }
            RemoteMessage::Event(event) => {
                handle_event(inner, event, frame.body).await?;
            }
            RemoteMessage::Request(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "unexpected helper request",
                ));
            }
        }
    }
    Ok(())
}

fn retain_disconnect_reason(inner: &RemoteClientInner, reason: String) {
    let mut stored = inner
        .disconnect_reason
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if stored.is_none() {
        *stored = Some(reason.chars().take(512).collect());
    }
}

async fn handle_event(
    inner: &RemoteClientInner,
    event: RemoteEvent,
    body: Vec<u8>,
) -> Result<(), io::Error> {
    match event {
        RemoteEvent::ProcessOutput(output) => {
            let previous = inner.last_output_sequence.load(Ordering::Relaxed);
            if output.sequence <= previous {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!(
                        "remote process output sequence {} is not greater than {previous}",
                        output.sequence
                    ),
                ));
            }
            inner
                .last_output_sequence
                .store(output.sequence, Ordering::Relaxed);
            if body.len() > REMOTE_OUTPUT_CHUNK_BYTES {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "oversized process output",
                ));
            }
            let processes = inner.processes.lock().await;
            let Some(channels) = processes.get(&output.process_id) else {
                return Ok(());
            };
            channels
                .output
                .as_ref()
                .ok_or_else(|| {
                    io::Error::new(io::ErrorKind::InvalidData, "output after process exit")
                })?
                .try_send((output.stream, body))
                .map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::InvalidData,
                        "process output exceeded its negotiated window",
                    )
                })
        }
        RemoteEvent::ProcessExit(exit) => {
            if let Some(channels) = inner.processes.lock().await.get_mut(&exit.process_id) {
                channels.output.take();
                if let Some(sender) = channels.exit.take() {
                    let result = match exit.failure.as_ref() {
                        Some(error) => Err(RemoteClientError::Remote {
                            code: error.code,
                            message: error.message.clone(),
                        }),
                        None => Ok(exit),
                    };
                    let _ = sender.send(result);
                }
            }
            Ok(())
        }
    }
}

async fn mark_disconnected(inner: &RemoteClientInner) {
    // Repeated drains are intentional: a canceled cleanup waiter must not prevent
    // another observer from finishing delivery of the disconnected result.
    inner.disconnected.cancel();
    for (_, sender) in inner.pending.lock().await.drain() {
        let _ = sender.reply.send(Err(RemoteClientError::Disconnected));
    }
    for (_, mut channels) in inner.processes.lock().await.drain() {
        if let Some(sender) = channels.exit.take() {
            let _ = sender.send(Err(RemoteClientError::Disconnected));
        }
    }
}

pub(super) fn expect_ack(reply: RemoteReply) -> Result<(), RemoteClientError> {
    match reply.response {
        RemoteResponse::Ack => Ok(()),
        response => Err(RemoteClientError::Protocol(format!(
            "expected ack, received {response:?}"
        ))),
    }
}
