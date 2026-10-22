//! HTTP/2 transport shared by the SSH adapter and physical helper.
//! Domain responses live in DATA bodies. Only fixed-shape binary range metadata uses headers.
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_protocol::remote::{RemoteAllocation, RemoteOperationTiming, RemoteRequest, RemoteResponse};
use std::io;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use crate::budget::{ByteLease, ResourceBudget};
pub use bytes::Bytes;
pub use h2::{RecvStream, SendStream};
pub use http::{Request, Response};

pub const JSON_CONTENT: &str = "application/json";
pub const BINARY_CONTENT: &str = "application/octet-stream";
pub const EVENT_CONTENT: &str = "text/event-stream";

/// Joins owned SSH read/write halves without copying through an intermediate channel.
pub struct Io<R, W> {
    pub reader: R,
    pub writer: W,
}
impl<R: AsyncRead + Unpin, W: Unpin> AsyncRead for Io<R, W> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        out: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        Pin::new(&mut self.reader).poll_read(cx, out)
    }
}
impl<R: Unpin, W: AsyncWrite + Unpin> AsyncWrite for Io<R, W> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.writer).poll_write(cx, bytes)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.writer).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.writer).poll_shutdown(cx)
    }
}

#[derive(Debug)]
pub struct Reply {
    pub response: RemoteResponse,
    pub body: Bytes,
    pub timing: RemoteOperationTiming,
    pub(crate) _memory: Option<ByteLease>,
}
impl Reply {
    pub fn new(response: RemoteResponse, body: Bytes) -> Self {
        Self {
            response,
            body,
            timing: Default::default(),
            _memory: None,
        }
    }
}

struct DriverLifetime(CancellationToken);
impl Drop for DriverLifetime {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

#[derive(Clone)]
pub struct Client {
    _lifetime: Arc<DriverLifetime>,
    sender: h2::client::SendRequest<Bytes>,
    stopped: CancellationToken,
    reason: Arc<Mutex<Option<String>>>,
    allocation: watch::Sender<RemoteAllocation>,
    completion: Shared<BoxFuture<'static, Result<(), String>>>,
    ordinary: Arc<AdmissionLimit>,
    controls: Arc<AdmissionLimit>,
    metadata: Arc<AdmissionLimit>,
    lease: Arc<tokio::sync::Semaphore>,
    active_processes: Arc<std::sync::atomic::AtomicUsize>,
}
impl std::fmt::Debug for Client {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Http2Client")
            .field("closed", &self.stopped.is_cancelled())
            .finish()
    }
}
impl Client {
    pub async fn connect<T>(io: T, allocation: RemoteAllocation) -> io::Result<Self>
    where
        T: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let (sender, mut connection) = h2::client::Builder::new()
            .initial_window_size(allocation.stream_window)
            .initial_connection_window_size(allocation.connection_window)
            .initial_max_send_streams(u32::MAX as usize)
            .max_send_buffer_size(allocation.fragment_bytes)
            .max_header_list_size(allocation.fragment_bytes.min(u32::MAX as usize) as u32)
            .handshake(io)
            .await
            .map_err(io::Error::other)?;
        let stopped = CancellationToken::new();
        let cancellation = stopped.clone();
        let reason = Arc::new(Mutex::new(None));
        let failure = reason.clone();
        let (allocation, mut changes) = watch::channel(allocation);
        let task = tokio::spawn(async move {
            let mut pending_stream_window = None;
            let outcome = loop {
                tokio::select! {
                    _ = cancellation.cancelled() => break Ok(()),
                    result = futures::future::poll_fn(|cx| {
                        let result = Pin::new(&mut connection).poll(cx);
                        if let Some(window) = pending_stream_window
                            && connection.set_initial_window_size(window).is_ok() {
                                pending_stream_window = None;
                                cx.waker().wake_by_ref();
                            }
                        result
                    }) => break result.map_err(|error| error.to_string()),
                    result = changes.changed() => {
                        if result.is_err() { break Ok(()); }
                        let allocation = *changes.borrow_and_update();
                        connection.set_target_window_size(allocation.connection_window);
                        // A pending SETTINGS ACK wakes the protocol future. Retry there, without
                        // polling a business state or dropping the newest requested window.
                        pending_stream_window = Some(allocation.stream_window);
                    }
                }
            };
            if let Err(error) = &outcome {
                *failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(error.clone());
            }
            cancellation.cancel();
            outcome
        });
        let ordinary = Arc::new(AdmissionLimit::new(allocation.borrow().ordinary_operations));
        let controls = Arc::new(AdmissionLimit::new(allocation.borrow().ordinary_operations));
        let metadata = Arc::new(AdmissionLimit::new(allocation.borrow().ordinary_operations));
        Ok(Self {
            _lifetime: Arc::new(DriverLifetime(stopped.clone())),
            sender,
            stopped,
            reason,
            allocation,
            ordinary,
            controls,
            metadata,
            lease: Arc::new(tokio::sync::Semaphore::new(1)),
            active_processes: Default::default(),
            completion: async move {
                // A protocol/IO failure is already retained in `reason` and observed by active
                // exchanges. Joining the exited driver confirms transport cleanup; only a task
                // failure makes that cleanup unconfirmed.
                let _outcome = task.await.map_err(|error| error.to_string())?;
                Ok(())
            }
            .boxed()
            .shared(),
        })
    }
    pub fn is_closed(&self) -> bool {
        self.stopped.is_cancelled()
    }
    pub async fn closed(&self) {
        self.stopped.cancelled().await;
    }
    pub fn reason(&self) -> Option<String> {
        self.reason
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub fn allocation(&self) -> RemoteAllocation {
        *self.allocation.borrow()
    }
    pub fn resize(&self, mut allocation: RemoteAllocation) {
        self.ordinary.resize(allocation.ordinary_operations);
        self.controls.resize(allocation.ordinary_operations);
        self.metadata.resize(allocation.ordinary_operations);
        if self.ordinary.in_use() > 0
            || self
                .active_processes
                .load(std::sync::atomic::Ordering::Acquire)
                > 0
        {
            allocation.connection_window = allocation
                .connection_window
                .max(self.allocation.borrow().connection_window);
        }
        self.allocation.send_replace(allocation);
    }
    pub fn set_active_processes(&self, count: usize) {
        self.active_processes
            .store(count, std::sync::atomic::Ordering::Release);
    }
    pub async fn close(&self) -> io::Result<()> {
        self.stopped.cancel();
        self.completion.clone().await.map_err(io::Error::other)
    }
    pub async fn exchange(
        &self,
        request: Request<()>,
        bytes: Bytes,
    ) -> io::Result<Response<RecvStream>> {
        let mut sender = tokio::select! {
            _ = self.stopped.cancelled() => return Err(disconnected()),
            sender = self.sender.clone().ready() => sender.map_err(io::Error::other)?,
        };
        let (response, mut body) = sender
            .send_request(request, bytes.is_empty())
            .map_err(io::Error::other)?;
        let sending_wait = if bytes.is_empty() {
            0
        } else {
            send_bytes(&mut body, bytes, true, &self.stopped).await?
        };
        let mut response = tokio::select! {
            _ = self.stopped.cancelled() => Err(disconnected()),
            response = response => response.map_err(io::Error::other),
        }?;
        response.extensions_mut().insert(SendingWait(sending_wait));
        Ok(response)
    }
    pub async fn request(
        &self,
        id: &str,
        epoch: u64,
        request: &RemoteRequest,
        body: Bytes,
        budget: &ResourceBudget,
    ) -> io::Result<Reply> {
        self.request_reserved(id, epoch, request, body, budget, None)
            .await
    }
    pub async fn request_reserved(
        &self,
        id: &str,
        epoch: u64,
        request: &RemoteRequest,
        body: Bytes,
        budget: &ResourceBudget,
        reply_limit: Option<usize>,
    ) -> io::Result<Reply> {
        let control = request.is_control();
        let lease_operation = request.is_lease_control();
        let _lease = if lease_operation {
            Some(tokio::select! {
                _ = self.stopped.cancelled() => return Err(disconnected()),
                permit = self.lease.clone().acquire_owned() => permit.map_err(io::Error::other)?,
            })
        } else {
            None
        };
        let observes_work = request.is_observation()
            || matches!(
                request,
                RemoteRequest::CloseTransfer { .. } | RemoteRequest::CloseWorkspace { .. }
            );
        let _admission = if lease_operation
            || matches!(
                request,
                RemoteRequest::WaitProcess { .. } | RemoteRequest::Spawn(_)
            ) {
            None
        } else if request.is_metadata() {
            Some(self.metadata.acquire(&self.stopped).await?)
        } else if observes_work || !control {
            Some(self.ordinary.acquire(&self.stopped).await?)
        } else {
            Some(self.controls.acquire(&self.stopped).await?)
        };
        let mut builder = Request::builder()
            .method("POST")
            .uri(format!(
                "http://helper/{}/{id}",
                if lease_operation {
                    "lease"
                } else if request.is_metadata() {
                    "metadata"
                } else if control {
                    "control"
                } else {
                    "rpc"
                }
            ))
            .header("x-anywork-epoch", epoch.to_string());
        if let Some(limit) = reply_limit {
            builder = builder.header("x-anywork-reply-limit", limit);
        }
        let data = if control {
            let encoded = serde_json::to_vec(request).map_err(io::Error::other)?;
            if encoded.len() > self.allocation.borrow().fragment_bytes {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "control metadata exceeds its grant",
                ));
            }
            let mut value = http::HeaderValue::from_bytes(&encoded).map_err(io::Error::other)?;
            value.set_sensitive(true);
            builder = builder
                .header("x-anywork-control", value)
                .header("content-type", JSON_CONTENT);
            Bytes::new()
        } else if body.is_empty() {
            builder = builder.header("content-type", JSON_CONTENT);
            Bytes::from(serde_json::to_vec(request).map_err(io::Error::other)?)
        } else {
            if !matches!(
                request,
                RemoteRequest::WriteChunk { .. } | RemoteRequest::WriteStdin { .. }
            ) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "binary body requires a chunk operation",
                ));
            }
            builder = builder.header("content-type", BINARY_CONTENT).header(
                "x-anywork-operation",
                serde_json::to_string(request).map_err(io::Error::other)?,
            );
            body
        };
        let request = builder
            .header("content-length", data.len())
            .body(())
            .map_err(io::Error::other)?;
        let response = self.exchange(request, data).await?;
        let sending_wait = response
            .extensions()
            .get::<SendingWait>()
            .map_or(0, |wait| wait.0);
        let mut reply = match reply_limit {
            Some(limit) => receive_prepaid(response, limit, &self.stopped).await?,
            None => receive_reply(response, budget, &self.stopped).await?,
        };
        reply.timing.transfer_backpressure_micros = reply
            .timing
            .transfer_backpressure_micros
            .saturating_add(sending_wait);
        Ok(reply)
    }
    pub async fn output(
        &self,
        process_id: &str,
        sequence: u64,
        epoch: u64,
    ) -> io::Result<Response<RecvStream>> {
        let request = Request::builder()
            .method("GET")
            .uri(format!(
                "http://helper/output/{process_id}?after={sequence}"
            ))
            .header("x-anywork-epoch", epoch.to_string())
            .body(())
            .map_err(io::Error::other)?;
        self.exchange(request, Bytes::new()).await
    }
}

/// Sends only when both stream and connection capacity are available. h2 interleaves DATA frames.
pub async fn send_bytes(
    stream: &mut SendStream<Bytes>,
    mut bytes: Bytes,
    finish: bool,
    stop: &CancellationToken,
) -> io::Result<u64> {
    let mut waiting = 0_u64;
    while !bytes.is_empty() {
        stream.reserve_capacity(bytes.len());
        let started = std::time::Instant::now();
        let capacity = tokio::select! {
            _ = stop.cancelled() => return Err(disconnected()),
            capacity = futures::future::poll_fn(|cx| stream.poll_capacity(cx)) =>
                capacity.ok_or_else(disconnected)?.map_err(io::Error::other)?,
        };
        waiting = waiting.saturating_add(elapsed_micros(started));
        if capacity == 0 {
            continue;
        }
        let count = capacity.min(bytes.len());
        let piece = bytes.split_to(count);
        stream
            .send_data(piece, finish && bytes.is_empty())
            .map_err(io::Error::other)?;
    }
    Ok(waiting)
}

#[derive(Clone)]
struct SendingWait(u64);

pub async fn collect(
    stream: RecvStream,
    length: usize,
    budget: &ResourceBudget,
    stop: &CancellationToken,
) -> io::Result<(Bytes, ByteLease, u64)> {
    let (bytes, memory, _, _, waiting) = collect_reserved(stream, length, 0, budget, stop).await?;
    Ok((bytes, memory, waiting))
}

pub async fn collect_reserved(
    mut stream: RecvStream,
    length: usize,
    reply_reservation: usize,
    budget: &ResourceBudget,
    stop: &CancellationToken,
) -> io::Result<(Bytes, ByteLease, u64, u64, u64)> {
    let reservation = length
        .checked_add(reply_reservation)
        .ok_or_else(|| io::Error::other("body reservation overflow"))?;
    let started = std::time::Instant::now();
    let memory = budget.reserve(reservation, stop).await?;
    let admission_wait_micros = elapsed_micros(started);
    let receiving = std::time::Instant::now();
    let mut bytes = Vec::with_capacity(length);
    loop {
        let piece = tokio::select! {
            _ = stop.cancelled() => return Err(disconnected()),
            piece = stream.data() => piece,
        };
        let Some(piece) = piece else {
            break;
        };
        let piece = piece.map_err(io::Error::other)?;
        if piece.len() > length.saturating_sub(bytes.len()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "body exceeds declared resource reservation",
            ));
        }
        bytes.extend_from_slice(&piece);
        stream
            .flow_control()
            .release_capacity(piece.len())
            .map_err(io::Error::other)?;
    }
    if bytes.len() != length {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "incomplete HTTP body",
        ));
    }
    let waiting = receive_wait(&mut stream, stop).await?;
    Ok((
        bytes.into(),
        memory,
        admission_wait_micros,
        elapsed_micros(receiving),
        waiting,
    ))
}

pub fn body_length(headers: &http::HeaderMap) -> io::Result<usize> {
    headers
        .get("content-length")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing bounded content length"))
}

pub async fn receive_reply(
    response: Response<RecvStream>,
    budget: &ResourceBudget,
    stop: &CancellationToken,
) -> io::Result<Reply> {
    let mut timing = response_timing(response.headers())?;
    if let Some(value) = response.headers().get("x-anywork-control-result") {
        let memory = budget.reserve(value.len(), stop).await?;
        return Ok(Reply {
            response: serde_json::from_slice(value.as_bytes()).map_err(io::Error::other)?,
            body: Bytes::new(),
            timing,
            _memory: Some(memory),
        });
    }
    let length = body_length(response.headers())?;
    let binary = response
        .headers()
        .get("content-type")
        .is_some_and(|value| value == BINARY_CONTENT);
    let metadata = if binary {
        Some(
            serde_json::from_slice::<RemoteResponse>(
                response
                    .headers()
                    .get("x-anywork-result")
                    .ok_or_else(|| {
                        io::Error::new(io::ErrorKind::InvalidData, "missing range metadata")
                    })?
                    .as_bytes(),
            )
            .map_err(io::Error::other)?,
        )
    } else {
        None
    };
    let (bytes, memory, waiting) = collect(response.into_body(), length, budget, stop).await?;
    timing.transfer_backpressure_micros = waiting;
    let (response, body) = match metadata {
        Some(response) => (response, bytes),
        None => (
            serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            Bytes::new(),
        ),
    };
    Ok(Reply {
        response,
        body,
        timing,
        _memory: Some(memory),
    })
}

async fn receive_prepaid(
    response: Response<RecvStream>,
    limit: usize,
    stop: &CancellationToken,
) -> io::Result<Reply> {
    let mut timing = response_timing(response.headers())?;
    if let Some(value) = response.headers().get("x-anywork-control-result") {
        if value.len() > limit {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "control reply exceeds reserved grant",
            ));
        }
        return Ok(Reply {
            response: serde_json::from_slice(value.as_bytes()).map_err(io::Error::other)?,
            body: Bytes::new(),
            timing,
            _memory: None,
        });
    }
    let length = body_length(response.headers())?;
    if length > limit {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "response exceeds its reserved reply grant",
        ));
    }
    let metadata = response
        .headers()
        .get("x-anywork-result")
        .map(|value| {
            serde_json::from_slice::<RemoteResponse>(value.as_bytes()).map_err(io::Error::other)
        })
        .transpose()?;
    let mut body = response.into_body();
    let mut bytes = Vec::with_capacity(length);
    loop {
        let chunk = tokio::select! { _ = stop.cancelled() => return Err(disconnected()), chunk = body.data() => chunk };
        let Some(chunk) = chunk else {
            break;
        };
        let chunk = chunk.map_err(io::Error::other)?;
        if chunk.len() > length.saturating_sub(bytes.len()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "response body exceeds content length",
            ));
        }
        bytes.extend_from_slice(&chunk);
        body.flow_control()
            .release_capacity(chunk.len())
            .map_err(io::Error::other)?;
    }
    if bytes.len() != length {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "incomplete response body",
        ));
    }
    timing.transfer_backpressure_micros = receive_wait(&mut body, stop).await?;
    match metadata {
        Some(response) => Ok(Reply {
            response,
            body: bytes.into(),
            timing,
            _memory: None,
        }),
        None => Ok(Reply {
            response: serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            body: Bytes::new(),
            timing,
            _memory: None,
        }),
    }
}

/// Lifecycle controls contain bounded metadata only, so zero DATA credit cannot block cleanup.
pub fn respond_control(
    sender: &mut h2::server::SendResponse<Bytes>,
    reply: &Reply,
    limit: usize,
) -> io::Result<()> {
    let mut encoded = serde_json::to_vec(&reply.response).map_err(io::Error::other)?;
    if encoded.len() > limit {
        encoded = serde_json::to_vec(&RemoteResponse::Error(pl_protocol::remote::RemoteError {
            code: pl_protocol::remote::RemoteErrorCode::ResourceExhausted,
            message: "control response exceeds its metadata grant".into(),
        }))
        .map_err(io::Error::other)?;
    }
    let mut value = http::HeaderValue::from_bytes(&encoded).map_err(io::Error::other)?;
    value.set_sensitive(true);
    let response = Response::builder()
        .status(200)
        .header(
            "x-anywork-timing",
            serde_json::to_string(&reply.timing).map_err(io::Error::other)?,
        )
        .header("content-length", 0)
        .header("x-anywork-control-result", value)
        .body(())
        .map_err(io::Error::other)?;
    sender
        .send_response(response, true)
        .map_err(io::Error::other)?;
    Ok(())
}

pub async fn respond(
    sender: &mut h2::server::SendResponse<Bytes>,
    reply: &Reply,
    stop: &CancellationToken,
) -> io::Result<()> {
    let binary = matches!(reply.response, RemoteResponse::ByteRange { .. });
    let mut builder = Response::builder().status(200).header(
        "x-anywork-timing",
        serde_json::to_string(&reply.timing).map_err(io::Error::other)?,
    );
    let bytes = if binary {
        builder = builder.header("content-type", BINARY_CONTENT).header(
            "x-anywork-result",
            serde_json::to_string(&reply.response).map_err(io::Error::other)?,
        );
        reply.body.clone()
    } else {
        builder = builder.header("content-type", JSON_CONTENT);
        Bytes::from(serde_json::to_vec(&reply.response).map_err(io::Error::other)?)
    };
    let response = builder
        .header("content-length", bytes.len())
        .body(())
        .map_err(io::Error::other)?;
    let mut stream = sender
        .send_response(response, false)
        .map_err(io::Error::other)?;
    let waiting = send_bytes(&mut stream, bytes, false, stop).await?;
    let mut trailers = http::HeaderMap::new();
    trailers.insert("x-anywork-send-wait", http::HeaderValue::from(waiting));
    stream.send_trailers(trailers).map_err(io::Error::other)?;
    Ok(())
}

fn disconnected() -> io::Error {
    io::Error::new(io::ErrorKind::BrokenPipe, "HTTP/2 transport closed")
}

/// Actual wire progress, independent of request or business completion.
#[derive(Debug, Default)]
pub struct WireCounters {
    read: std::sync::atomic::AtomicU64,
    written: std::sync::atomic::AtomicU64,
}
impl WireCounters {
    pub fn snapshot(&self) -> (u64, u64) {
        (
            self.read.load(std::sync::atomic::Ordering::Relaxed),
            self.written.load(std::sync::atomic::Ordering::Relaxed),
        )
    }
}
pub struct MeasuredIo<T> {
    pub io: T,
    pub counters: Arc<WireCounters>,
}
impl<T: AsyncRead + Unpin> AsyncRead for MeasuredIo<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let before = buffer.filled().len();
        let result = Pin::new(&mut self.io).poll_read(cx, buffer);
        self.counters.read.fetch_add(
            (buffer.filled().len() - before) as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        result
    }
}
impl<T: AsyncWrite + Unpin> AsyncWrite for MeasuredIo<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        let result = Pin::new(&mut self.io).poll_write(cx, bytes);
        if let Poll::Ready(Ok(count)) = &result {
            self.counters
                .written
                .fetch_add(*count as u64, std::sync::atomic::Ordering::Relaxed);
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

/// Tokio owns fair one-request admission. Shrink debt is collected as existing permits return.
#[derive(Debug)]
pub struct AdmissionLimit {
    semaphore: Arc<tokio::sync::Semaphore>,
    state: Mutex<(usize, usize)>,
}
impl AdmissionLimit {
    pub fn new(limit: usize) -> Self {
        Self {
            semaphore: Arc::new(tokio::sync::Semaphore::new(limit)),
            state: Mutex::new((limit, limit)),
        }
    }
    pub fn in_use(&self) -> usize {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.0.saturating_sub(self.semaphore.available_permits())
    }
    pub fn resize(&self, target: usize) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.1 = target;
        if target > state.0 {
            self.semaphore.add_permits(target - state.0);
            state.0 = target;
        } else {
            let removed = self.semaphore.forget_permits(state.0 - target);
            state.0 -= removed;
        }
    }
    pub async fn acquire(self: &Arc<Self>, stop: &CancellationToken) -> io::Result<Admission> {
        let permit = tokio::select! {
            _ = stop.cancelled() => return Err(disconnected()),
            permit = self.semaphore.clone().acquire_owned() => permit.map_err(io::Error::other)?,
        };
        Ok(Admission {
            owner: self.clone(),
            permit: Some(permit),
        })
    }
}
pub struct Admission {
    owner: Arc<AdmissionLimit>,
    permit: Option<tokio::sync::OwnedSemaphorePermit>,
}
impl Drop for Admission {
    fn drop(&mut self) {
        let mut state = self
            .owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.0 > state.1
            && let Some(permit) = self.permit.take()
        {
            permit.forget();
            state.0 -= 1;
        }
    }
}

fn response_timing(headers: &http::HeaderMap) -> io::Result<RemoteOperationTiming> {
    let value = headers
        .get("x-anywork-timing")
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing operation timing"))?;
    serde_json::from_slice(value.as_bytes()).map_err(io::Error::other)
}
pub fn elapsed_micros(started: std::time::Instant) -> u64 {
    started.elapsed().as_micros().min(u64::MAX as u128) as u64
}

async fn receive_wait(stream: &mut RecvStream, stop: &CancellationToken) -> io::Result<u64> {
    let trailers = tokio::select! { _ = stop.cancelled() => return Err(disconnected()), trailers = stream.trailers() => trailers.map_err(io::Error::other)? };
    match trailers.and_then(|headers| headers.get("x-anywork-send-wait").cloned()) {
        Some(value) => value
            .to_str()
            .map_err(io::Error::other)?
            .parse()
            .map_err(io::Error::other),
        None => Ok(0),
    }
}
