//! One logical helper session, with replaceable HTTP/2 attachment and independently owned operations.
use pl_protocol::remote::*;
use pl_remote_helper::transport::{self, Bytes, Client as WireClient};
use std::collections::HashMap;
use std::io;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as SyncMutex};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{Mutex, oneshot, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

mod error;
mod process;
pub(super) mod workspace;
pub use error::{RemoteClientError, SshAuthFailure};

#[derive(Debug)]
pub struct RemoteReply {
    pub response: RemoteResponse,
    pub body: Bytes,
    pub timing: RemoteRequestTiming,
}
/// Host and helper phases use monotonic clocks independently; durations never compare wall clocks.
#[derive(Debug, Clone, Copy, Default)]
pub struct RemoteRequestTiming {
    pub exchange_micros: u64,
    pub cleanup_micros: u64,
    pub remote: RemoteOperationTiming,
}
#[derive(Debug, Clone)]
enum Connection {
    Ready {
        generation: u64,
        wire: WireClient,
    },
    Detached {
        generation: u64,
        at: tokio::time::Instant,
    },
    Closed,
}
#[derive(Debug)]
struct RemoteClientInner {
    connection: watch::Sender<Connection>,
    hello: SyncMutex<Option<RemoteHello>>,
    next_request_id: AtomicU64,
    request_namespace: String,
    stopped: CancellationToken,
    streams: TaskTracker,
    attachment_transition: Mutex<()>,
    close_result: Mutex<Option<Result<(), RemoteClientError>>>,
    closing: std::sync::atomic::AtomicBool,
    closing_signal: CancellationToken,
    disconnect_reason: SyncMutex<Option<String>>,
    pending_releases: SyncMutex<Vec<RemoteRequest>>,
}
#[derive(Debug)]
struct SessionLifetime(CancellationToken);
impl Drop for SessionLifetime {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

#[derive(Debug, Clone)]
pub struct RemoteClient {
    inner: Arc<RemoteClientInner>,
    lifetime: Arc<SessionLifetime>,
}
impl RemoteClient {
    /// Identifies the logical helper session across transport reattachments.
    pub(in crate::remote) fn session_identity(&self) -> &str {
        &self.inner.request_namespace
    }

    /// Creates exactly one HTTP/2 connection. The initial Hello identifies the physical owner.
    pub async fn from_streams<R, W>(reader: R, writer: W) -> Result<Self, RemoteClientError>
    where
        R: AsyncRead + Send + Unpin + 'static,
        W: AsyncWrite + Send + Unpin + 'static,
    {
        let stopped = CancellationToken::new();
        let mut namespace = [0_u8; 16];
        getrandom::fill(&mut namespace).map_err(|error| {
            RemoteClientError::Protocol(format!("operation namespace: {error}"))
        })?;
        let wire = WireClient::connect(transport::Io { reader, writer }).await?;
        let inner = Arc::new(RemoteClientInner {
            connection: watch::channel(Connection::Ready {
                generation: 1,
                wire: wire.clone(),
            })
            .0,
            hello: SyncMutex::new(None),
            next_request_id: AtomicU64::new(0),
            request_namespace: hex::encode(namespace),
            stopped: stopped.clone(),
            streams: TaskTracker::new(),
            attachment_transition: Mutex::new(()),
            close_result: Mutex::new(None),
            closing: std::sync::atomic::AtomicBool::new(false),
            closing_signal: CancellationToken::new(),
            disconnect_reason: Default::default(),
            pending_releases: Default::default(),
        });
        monitor(&inner, 1, wire);
        Ok(Self {
            inner,
            lifetime: Arc::new(SessionLifetime(stopped)),
        })
    }
    pub async fn request(
        &self,
        request: RemoteRequest,
        body: &[u8],
    ) -> Result<RemoteReply, RemoteClientError> {
        submit(&self.inner, request, body, None)?
            .await
            .unwrap_or(Err(RemoteClientError::Disconnected))
    }
    pub(super) fn begin_close(&self) {
        self.inner.closing.store(true, Ordering::Release);
        self.inner.closing_signal.cancel();
    }
    pub(super) fn is_closing(&self) -> bool {
        self.inner.closing.load(Ordering::Acquire)
    }
    pub fn is_disconnected(&self) -> bool {
        if self.is_closing() {
            return true;
        }
        match &*self.inner.connection.borrow() {
            Connection::Ready { wire, .. } => wire.is_closed(),
            _ => true,
        }
    }
    pub async fn wait_disconnected(&self) {
        let current = self.inner.connection.borrow().clone();
        if let Connection::Ready { wire, .. } = current {
            wire.closed().await;
        }
    }
    pub fn generation(&self) -> u64 {
        match &*self.inner.connection.borrow() {
            Connection::Ready { generation, .. } | Connection::Detached { generation, .. } => {
                *generation
            }
            Connection::Closed => 0,
        }
    }
    pub(super) fn shell_argv(
        &self,
        command: &str,
    ) -> Result<(String, Vec<String>), RemoteClientError> {
        let hello = self
            .inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let hello = hello
            .as_ref()
            .ok_or_else(|| RemoteClientError::Protocol("helper handshake is missing".into()))?;
        let environment = super::manager::execution_environment_from_hello(hello)?;
        let mut argv =
            crate::command::shell::argv_for_environment(&environment, command).into_iter();
        let program = argv
            .next()
            .ok_or_else(|| RemoteClientError::Protocol("shell executable is missing".into()))?;
        Ok((program, argv.collect()))
    }
    pub(super) fn hello(&self) -> Option<RemoteHello> {
        self.inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub fn session(&self) -> Option<RemoteSession> {
        self.inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map(|h| h.session.clone())
    }
    /// Replaces only the transport; every workspace, process and in-flight operation keeps its owner.
    pub async fn reattach<R, W>(
        &self,
        reader: R,
        writer: W,
    ) -> Result<RemoteHello, RemoteClientError>
    where
        R: AsyncRead + Send + Unpin + 'static,
        W: AsyncWrite + Send + Unpin + 'static,
    {
        // Only physical attachment transitions use this ownership gate. Requests and command
        // streams continue independently. Close seals admission first, then joins the transition
        // before selecting the wire whose shutdown receipt it must observe.
        let _transition = tokio::select! {
            _ = self.inner.closing_signal.cancelled() => return Err(RemoteClientError::Cancelled),
            transition = self.inner.attachment_transition.lock() => transition,
        };
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(25);
        if self.is_closing() || self.inner.stopped.is_cancelled() {
            return Err(RemoteClientError::Cancelled);
        }
        let session = self
            .session()
            .ok_or_else(|| RemoteClientError::Protocol("helper identity is missing".into()))?;
        let wire = tokio::select! {
            _ = self.inner.closing_signal.cancelled() => return Err(RemoteClientError::Cancelled),
            result = tokio::time::timeout_at(deadline, WireClient::connect(transport::Io { reader, writer })) =>
                result.map_err(|_| RemoteClientError::Protocol("HTTP/2 replacement handshake timed out".into()))??,
        };
        if self.is_closing() {
            wire.close().await?;
            return Err(RemoteClientError::Cancelled);
        }
        // Once Attach is submitted, retain this owner until its physical fencing receipt or
        // the original deadline. Close then selects this confirmed attachment under the gate.
        let result = tokio::time::timeout_at(
            deadline,
            wire.request(
                "attach",
                0,
                &RemoteRequest::Attach { session },
                Bytes::new(),
            ),
        )
        .await;
        let result = match result {
            Ok(Ok(reply)) => reply,
            Ok(Err(error)) => {
                wire.close().await?;
                return Err(error.into());
            }
            Err(_) => {
                wire.close().await?;
                return Err(RemoteClientError::Remote {
                    removal_effect: None,
                    code: RemoteErrorCode::OutcomeUnknown,
                    message: "helper attachment receipt was not confirmed before its deadline"
                        .into(),
                });
            }
        };
        let RemoteResponse::Hello(hello) = result.response else {
            return Err(response_error(result.response));
        };
        let generation = self
            .generation()
            .checked_add(1)
            .ok_or_else(|| RemoteClientError::Protocol("connection generation exhausted".into()))?;
        *self
            .inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(hello.clone());
        let previous = self.inner.connection.send_replace(Connection::Ready {
            generation,
            wire: wire.clone(),
        });
        if let Connection::Ready { wire, .. } = previous {
            wire.close().await?;
        }
        monitor(&self.inner, generation, wire);
        let releases = self
            .inner
            .pending_releases
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        for request in releases {
            self.release_resource(request);
        }
        Ok(hello)
    }
    pub async fn close(&self) -> Result<(), RemoteClientError> {
        self.begin_close();
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
        let mut closed = self.inner.close_result.lock().await;
        if let Some(result) = &*closed {
            return result.clone();
        }
        let _transition = self.inner.attachment_transition.lock().await;
        let current = self.inner.connection.borrow().clone();
        let result = match current {
            Connection::Ready { wire, .. } if !wire.is_closed() => {
                let epoch = self.session().map_or(0, |session| session.epoch);
                match tokio::time::timeout_at(deadline,
                    wire.request("shutdown", epoch, &RemoteRequest::Shutdown, Bytes::new())).await {
                    Ok(Ok(reply)) if matches!(reply.response, RemoteResponse::Ack) => Ok(()),
                    Ok(Ok(reply)) => Err(response_error(reply.response)),
                    Ok(Err(error)) => Err(error.into()),
                    Err(_) => Err(RemoteClientError::Remote { removal_effect: None, code: RemoteErrorCode::OutcomeUnknown,
                        message: "helper cleanup did not confirm before the shutdown deadline; its lease still owns pending resources".into() }),
                }
            }
            _ if self.attachment_expired() => Err(RemoteClientError::Remote {
                removal_effect: None,
                code: RemoteErrorCode::SessionExpired,
                message: "helper lease expired; physical cleanup is no longer observable".into(),
            }),
            _ => Err(RemoteClientError::Remote {
                removal_effect: None,
                code: RemoteErrorCode::OutcomeUnknown,
                message: "helper cleanup cannot be confirmed on a detached transport".into(),
            }),
        };
        self.inner.stopped.cancel();
        let previous = self.inner.connection.send_replace(Connection::Closed);
        let transport = if let Connection::Ready { wire, .. } = previous {
            wire.close().await.map_err(RemoteClientError::from)
        } else {
            Ok(())
        };
        self.inner.streams.close();
        self.inner.streams.wait().await;
        let result = result.and(transport);
        if result.is_ok() {
            self.inner
                .pending_releases
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clear();
        }
        *closed = Some(result.clone());
        result
    }
    /// Closes the current channel while preserving the helper session and its external owners.
    pub(super) async fn detach(&self, reason: String) -> Result<(), RemoteClientError> {
        let current = self.inner.connection.borrow().clone();
        if let Connection::Ready { generation, wire } = current {
            mark_detached(&self.inner, generation, reason);
            wire.close().await?;
        }
        Ok(())
    }
    pub(crate) async fn heartbeat(&self) -> Result<(), RemoteClientError> {
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(15),
            self.request(RemoteRequest::Heartbeat, &[]),
        )
        .await;
        match result {
            Ok(Ok(RemoteReply {
                response: RemoteResponse::Heartbeat(heartbeat),
                ..
            })) => {
                if let Some(failure) = heartbeat.last_failure {
                    tracing::debug!(instance = ?self.session().map(|session| session.instance_id),
                        operation_id = %failure.operation_id, epoch = failure.epoch, phase = %failure.phase,
                        code = ?failure.code, request_bytes = failure.request_bytes, reply_bytes = failure.reply_bytes, "helper request failure diagnostic");
                }
            }
            Ok(Err(error)) => return Err(error),
            Ok(Ok(reply)) => return Err(response_error(reply.response)),
            Err(_) => return Err(RemoteClientError::HeartbeatTimeout),
        }
        Ok(())
    }
    pub fn disconnect_reason(&self) -> Option<String> {
        self.inner
            .disconnect_reason
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub(super) fn attachment_expired(&self) -> bool {
        matches!(&*self.inner.connection.borrow(), Connection::Detached { at, .. }
            if at.elapsed() >= std::time::Duration::from_secs(30))
    }
    pub(super) fn release_resource(&self, request: RemoteRequest) {
        let inner = self.inner.clone();
        self.inner.streams.spawn(async move {
            if !inner.stopped.is_cancelled()
                && let Err(error) = release_inner(&inner, request).await
            {
                tracing::warn!(%error, "remote resource release retained for reconnect or shutdown");
            }
        });
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
        submit(&self.inner, request, body, Some(lease))?
            .await
            .unwrap_or(Err(RemoteClientError::Disconnected))
    }
    pub async fn spawn_process(
        &self,
        request: RemoteSpawnRequest,
    ) -> Result<crate::command::ManagedCommand, RemoteClientError> {
        process::spawn(self, request, None, None).await
    }
    pub(super) async fn spawn_workspace_process(
        &self,
        lease: Arc<workspace::WorkspaceLease>,
        request: RemoteSpawnRequest,
        start: Option<crate::command::CommandStartControl>,
    ) -> Result<crate::command::ManagedCommand, RemoteClientError> {
        process::spawn(self, request, Some(lease), start).await
    }
    pub(super) async fn open_http_wire(
        &self,
    ) -> Result<(String, u64, u64, WireClient, CancellationToken), RemoteClientError> {
        if self.is_closing() {
            return Err(RemoteClientError::Disconnected);
        }
        let (generation, wire) = ready(&self.inner).await?;
        let epoch = self
            .inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map_or(0, |hello| hello.session.epoch);
        let exchange_id = format!(
            "http-{}-{}",
            self.inner.request_namespace,
            self.inner.next_request_id.fetch_add(1, Ordering::Relaxed)
        );
        Ok((
            exchange_id,
            generation,
            epoch,
            wire,
            self.inner.stopped.clone(),
        ))
    }
    pub(super) fn notify_wire_detached(&self, generation: u64, reason: String) {
        mark_detached(&self.inner, generation, reason);
    }
}

type PendingReply = oneshot::Receiver<Result<RemoteReply, RemoteClientError>>;
fn submit(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: &[u8],
    workspace: Option<Arc<workspace::WorkspaceLease>>,
) -> Result<PendingReply, RemoteClientError> {
    if inner.closing.load(Ordering::Acquire) && !request.is_control() {
        return Err(RemoteClientError::Disconnected);
    }
    Ok(submit_request(
        inner,
        request,
        Bytes::copy_from_slice(body),
        workspace,
        None,
    ))
}
#[derive(Clone, Copy)]
enum AcquiredResource {
    None,
    Workspace,
    Directory,
    Transfer,
    Process,
}
impl AcquiredResource {
    fn for_request(request: &RemoteRequest) -> Self {
        match request {
            RemoteRequest::OpenWorkspace { .. } => Self::Workspace,
            RemoteRequest::OpenRead(_) | RemoteRequest::BeginWrite(_) => Self::Transfer,
            RemoteRequest::Spawn(_) => Self::Process,
            RemoteRequest::BrowseDirectories { .. }
            | RemoteRequest::ListDirectory(_)
            | RemoteRequest::ContinueDirectory { .. } => Self::Directory,
            _ => Self::None,
        }
    }
}
fn submit_request(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: Bytes,
    workspace: Option<Arc<workspace::WorkspaceLease>>,
    start: Option<crate::command::CommandStartControl>,
) -> PendingReply {
    let id = format!(
        "{}-{}",
        inner.request_namespace,
        inner.next_request_id.fetch_add(1, Ordering::Relaxed)
    );
    let (reply, received) = oneshot::channel();
    let owner = inner.clone();
    let acquired = AcquiredResource::for_request(&request);
    inner.streams.spawn(async move {
        let _workspace = workspace;
        let result = perform(&owner, &id, request, body, start).await;
        if let Err(Ok(unclaimed)) = reply.send(result) {
            retire_unclaimed(&owner, acquired, unclaimed.response).await;
        }
    });
    received
}
async fn request_inner(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: &[u8],
) -> Result<RemoteReply, RemoteClientError> {
    submit(inner, request, body, None)?
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))
}
/// Keep failed releases on the same logical owner; reattachment retries these identities and
/// confirmed helper shutdown settles every remaining resource. No independent retry scheduler.
async fn release_inner(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
) -> Result<RemoteReply, RemoteClientError> {
    {
        let mut pending = inner
            .pending_releases
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !pending.contains(&request) {
            pending.push(request.clone());
        }
    }
    let reply = request_inner(inner, request.clone(), &[]).await?;
    if !matches!(reply.response, RemoteResponse::Ack) {
        return Err(response_error(reply.response));
    }
    inner
        .pending_releases
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .retain(|pending| pending != &request);
    Ok(reply)
}

async fn perform(
    inner: &Arc<RemoteClientInner>,
    id: &str,
    request: RemoteRequest,
    body: Bytes,
    start: Option<crate::command::CommandStartControl>,
) -> Result<RemoteReply, RemoteClientError> {
    let started = std::time::Instant::now();
    let control = request.is_control();
    let mut uncertain = false;
    let mut not_started_generation = None;
    let mut submitted_generation = None;
    let reply = loop {
        let (generation, wire) = if !uncertain {
            if let Some(start) = &start {
                tokio::select! {
                    biased;
                    _ = start.stopped() => return Err(RemoteClientError::Cancelled),
                    result = ready(inner) => result?,
                }
            } else {
                ready(inner).await?
            }
        } else {
            ready(inner).await?
        };
        let epoch = inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map_or(0, |hello| hello.session.epoch);
        let mut query = if uncertain && !control {
            RemoteRequest::OperationResult {
                operation_id: id.to_owned(),
            }
        } else {
            request.clone()
        };
        if !uncertain && let Some(start) = &start {
            start.check().map_err(|_| RemoteClientError::Cancelled)?;
            if let RemoteRequest::Spawn(request) = &mut query {
                request.remaining_timeout_ms = Some(
                    start
                        .deadline()
                        .saturating_duration_since(tokio::time::Instant::now())
                        .as_millis()
                        .min(u64::MAX as u128) as u64,
                );
            }
            start.mark_start_attempted();
        }
        let data = if uncertain && !control {
            Bytes::new()
        } else {
            body.clone()
        };
        if !uncertain && !control {
            submitted_generation = Some(generation);
        }
        tracing::debug!(
            operation_id = id,
            generation,
            phase = "exchange",
            restoring = uncertain,
            "remote request phase"
        );
        match wire.request(id, epoch, &query, data).await {
            Ok(reply) if matches!(&reply.response, RemoteResponse::Error(error) if error.code == RemoteErrorCode::StaleConnection) =>
            {
                mark_detached(
                    inner,
                    generation,
                    "attachment was fenced by a replacement".into(),
                );
                wire.close().await.ok();
                uncertain = true;
            }
            Ok(reply)
                if uncertain
                    && !control
                    && matches!(&reply.response,
                RemoteResponse::Error(error) if error.code == RemoteErrorCode::OperationNotStarted) =>
            {
                // The replacement attachment has fenced all earlier receivers. Absence of this
                // unacknowledged operation now proves no effect was admitted, so submission is safe.
                if submitted_generation == Some(generation) {
                    // An absent result on an unfenced stream does not prove absence of effects:
                    // its request parser could still be in flight. Replace the attachment first.
                    mark_detached(
                        inner,
                        generation,
                        "fencing an unconfirmed submission".into(),
                    );
                    wire.close().await.ok();
                    continue;
                }
                if not_started_generation == Some(generation) {
                    return Err(RemoteClientError::Remote {
                        removal_effect: None,
                        code: RemoteErrorCode::OutcomeUnknown,
                        message: "operation cannot make progress on the current attachment".into(),
                    });
                }
                not_started_generation = Some(generation);
                if let Some(start) = &start {
                    start.confirm_not_started();
                }
                uncertain = false;
            }
            Ok(reply) => break reply,
            Err(error) => {
                let connection_error = wire.is_closed()
                    || error
                        .get_ref()
                        .and_then(|source| source.downcast_ref::<h2::Error>())
                        .is_some_and(|error| error.is_io() || error.is_go_away());
                if !connection_error {
                    if error.kind() == io::ErrorKind::InvalidInput || uncertain {
                        return Err(RemoteClientError::Protocol(format!(
                            "operation stream failed: {error}"
                        )));
                    }
                    // A reset affects this exchange only. Resolve the retained result once on the
                    // still-healthy connection; do not turn stream errors into connection failure.
                    uncertain = true;
                    continue;
                }
                mark_detached(inner, generation, format!("operation transport: {error}"));
                wire.close().await.ok();
                uncertain = true;
            }
        }
    };
    tracing::debug!(
        operation_id = id,
        phase = "received",
        "remote request phase"
    );
    let exchange_micros = transport::elapsed_micros(started);
    let cleanup = std::time::Instant::now();
    if let RemoteResponse::Hello(hello) = &reply.response {
        *inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(hello.clone());
    }
    if !control {
        // Keep the result locally while retiring the remote receipt. Lost retirement ACKs are safe
        // to repeat; the original effect is never reissued after transport loss.
        loop {
            let (generation, wire) = ready(inner).await?;
            let epoch = inner
                .hello
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .as_ref()
                .map_or(0, |h| h.session.epoch);
            tracing::debug!(
                operation_id = id,
                generation,
                phase = "release-receipt",
                "remote request phase"
            );
            match wire
                .request(
                    &format!("release-{id}"),
                    epoch,
                    &RemoteRequest::ReleaseOperation {
                        operation_id: id.to_owned(),
                    },
                    Bytes::new(),
                )
                .await
            {
                Ok(reply) if matches!(reply.response, RemoteResponse::Ack) => break,
                Ok(reply) => {
                    let error = response_error(reply.response);
                    mark_detached(inner, generation, format!("receipt release: {error}"));
                    wire.close().await.ok();
                }
                Err(error) => {
                    mark_detached(inner, generation, format!("receipt release: {error}"));
                    wire.close().await.ok();
                }
            }
        }
    }
    let transport::Reply {
        response,
        body,
        timing,
        ..
    } = reply;
    let timing = RemoteRequestTiming {
        exchange_micros,
        cleanup_micros: transport::elapsed_micros(cleanup),
        remote: timing,
    };
    match response {
        RemoteResponse::Error(error) => Err(RemoteClientError::Remote {
            removal_effect: error.removal_effect,
            code: error.code,
            message: error.message,
        }),
        response => Ok(RemoteReply {
            response,
            body,
            timing,
        }),
    }
}
async fn ready(inner: &RemoteClientInner) -> Result<(u64, WireClient), RemoteClientError> {
    let mut state = inner.connection.subscribe();
    loop {
        if inner.stopped.is_cancelled() {
            return Err(RemoteClientError::Disconnected);
        }
        let current = state.borrow_and_update().clone();
        match current {
            Connection::Ready { generation, wire } if !wire.is_closed() => {
                return Ok((generation, wire));
            }
            Connection::Ready { generation, .. } => {
                mark_detached(inner, generation, "HTTP/2 connection closed".into())
            }
            Connection::Closed => return Err(RemoteClientError::Disconnected),
            Connection::Detached { at, .. } => {
                let deadline = at + std::time::Duration::from_secs(30);
                tokio::select! {
                    _ = inner.stopped.cancelled() => return Err(RemoteClientError::Disconnected),
                    changed = state.changed() => { if changed.is_err() { return Err(RemoteClientError::Disconnected); } },
                    _ = tokio::time::sleep_until(deadline) => return Err(RemoteClientError::Remote {
                        removal_effect: None,
                        code: RemoteErrorCode::SessionExpired, message: "helper attachment lease expired".into() }),
                }
            }
        }
    }
}
fn mark_detached(inner: &RemoteClientInner, generation: u64, reason: String) {
    inner.connection.send_if_modified(|state| {
        if matches!(state, Connection::Ready { generation: current, .. } if *current == generation)
        {
            *state = Connection::Detached {
                generation,
                at: tokio::time::Instant::now(),
            };
            *inner
                .disconnect_reason
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(reason);
            true
        } else {
            false
        }
    });
}
fn monitor(inner: &Arc<RemoteClientInner>, generation: u64, wire: WireClient) {
    let owner = inner.clone();
    inner.streams.spawn(async move {
        tokio::select! {
            _ = wire.closed() => mark_detached(&owner, generation, wire.reason().unwrap_or_else(|| "HTTP/2 EOF".into())),
            _ = owner.stopped.cancelled() => { let _ = wire.close().await; }
        }
    });
}
fn response_error(response: RemoteResponse) -> RemoteClientError {
    match response {
        RemoteResponse::Error(error) => RemoteClientError::Remote {
            removal_effect: error.removal_effect,
            code: error.code,
            message: error.message,
        },
        _ => RemoteClientError::Protocol("unexpected helper response".into()),
    }
}
pub(super) fn expect_ack(reply: RemoteReply) -> Result<(), RemoteClientError> {
    match reply.response {
        RemoteResponse::Ack => Ok(()),
        response => Err(response_error(response)),
    }
}

fn retire_unclaimed(
    inner: &Arc<RemoteClientInner>,
    acquired: AcquiredResource,
    response: RemoteResponse,
) -> futures::future::BoxFuture<'static, ()> {
    use futures::FutureExt;
    let inner = inner.clone();
    async move {
        let release = match (acquired, response) {
            (AcquiredResource::Workspace, RemoteResponse::WorkspaceOpened(workspace)) => {
                Some(RemoteRequest::CloseWorkspace {
                    workspace_id: workspace.workspace_id,
                })
            }
            (
                AcquiredResource::Directory,
                RemoteResponse::Directory(page) | RemoteResponse::Directories(page),
            ) => page
                .next_cursor
                .map(|cursor| RemoteRequest::CloseDirectory { cursor }),
            (AcquiredResource::Transfer, RemoteResponse::Transfer(transfer)) => {
                Some(RemoteRequest::CloseTransfer {
                    transfer_id: transfer.transfer_id,
                })
            }
            (AcquiredResource::Process, RemoteResponse::ProcessSpawned { process_id }) => {
                let _ = request_inner(
                    &inner,
                    RemoteRequest::Terminate {
                        process_id: process_id.clone(),
                    },
                    &[],
                )
                .await;
                Some(RemoteRequest::ReleaseProcess { process_id })
            }
            _ => None,
        };
        if let Some(release) = release
            && let Err(error) = release_inner(&inner, release).await
        {
            tracing::warn!(%error, "unclaimed remote resource cleanup failed");
        }
    }
    .boxed()
}

async fn wait_process(
    inner: &Arc<RemoteClientInner>,
    process_id: String,
) -> Result<RemoteReply, RemoteClientError> {
    // Terminal observation travels independently of the process output stream.
    let id = format!(
        "{}-{}",
        inner.request_namespace,
        inner.next_request_id.fetch_add(1, Ordering::Relaxed)
    );
    perform(
        inner,
        &id,
        RemoteRequest::WaitProcess { process_id },
        Bytes::new(),
        None,
    )
    .await
}
