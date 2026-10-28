//! One logical helper session, with replaceable HTTP/2 attachment and independently owned operations.
use pl_protocol::remote::*;
use pl_remote_helper::budget::{ResourceBudget, ResourcePolicy};
use pl_remote_helper::transport::{self, Bytes, Client as WireClient};
use std::collections::HashMap;
use std::io;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as SyncMutex};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{Mutex, oneshot, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

mod buffer;
mod error;
mod process;
pub(super) mod workspace;
pub use error::{RemoteClientError, SshAuthFailure};

#[derive(Debug)]
enum ReplyMemory {
    Owned {
        _lease: pl_remote_helper::budget::ByteLease,
    },
    Shared {
        _lease: Arc<pl_remote_helper::budget::ByteLease>,
    },
}
#[derive(Debug)]
pub struct RemoteReply {
    pub response: RemoteResponse,
    pub body: Bytes,
    pub timing: RemoteRequestTiming,
    _memory: Option<ReplyMemory>,
}
/// Host and helper phases use monotonic clocks independently; durations never compare wall clocks.
#[derive(Debug, Clone, Copy, Default)]
pub struct RemoteRequestTiming {
    pub admission_wait_micros: u64,
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
    budget: ResourceBudget,
    policy: ResourcePolicy,
    connection_registration: SyncMutex<Option<pl_remote_helper::budget::ConnectionRegistration>>,
    connection_credit: SyncMutex<pl_remote_helper::budget::ByteLease>,
    configuring: Mutex<()>,
    attachment_transition: Mutex<()>,
    close_result: Mutex<Option<Result<(), RemoteClientError>>>,
    closing: std::sync::atomic::AtomicBool,
    closing_signal: CancellationToken,
    control: ResourceBudget,
    metadata: ResourceBudget,
    lease_control: ResourceBudget,
    process_slots: Arc<transport::AdmissionLimit>,
    disconnect_reason: SyncMutex<Option<String>>,
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
    /// Creates exactly one HTTP/2 connection. The initial Hello identifies the physical owner.
    pub async fn from_streams<R, W>(reader: R, writer: W) -> Result<Self, RemoteClientError>
    where
        R: AsyncRead + Send + Unpin + 'static,
        W: AsyncWrite + Send + Unpin + 'static,
    {
        let allocation = tokio::task::spawn_blocking(|| ResourcePolicy::default().allocation())
            .await
            .map_err(|e| RemoteClientError::Protocol(e.to_string()))??;
        Self::with_budget(
            reader,
            writer,
            ResourceBudget::new(allocation)?,
            ResourcePolicy::default(),
        )
        .await
    }
    pub(super) async fn with_budget<R, W>(
        reader: R,
        writer: W,
        budget: ResourceBudget,
        policy: ResourcePolicy,
    ) -> Result<Self, RemoteClientError>
    where
        R: AsyncRead + Send + Unpin + 'static,
        W: AsyncWrite + Send + Unpin + 'static,
    {
        let registration = budget.register_connection();
        let allocation = budget.connection_allocation()?;
        let stopped = CancellationToken::new();
        let credit = budget
            .reserve(connection_cost(allocation), &stopped)
            .await?;
        let mut namespace = [0_u8; 16];
        getrandom::fill(&mut namespace).map_err(|error| {
            RemoteClientError::Protocol(format!("operation namespace: {error}"))
        })?;
        let wire = WireClient::connect(transport::Io { reader, writer }, allocation).await?;
        let mut control_allocation = allocation;
        control_allocation.resident_bytes = allocation.fragment_bytes.saturating_mul(4);
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
            budget,
            policy,
            connection_registration: SyncMutex::new(Some(registration)),
            connection_credit: SyncMutex::new(credit),
            configuring: Mutex::new(()),
            attachment_transition: Mutex::new(()),
            close_result: Mutex::new(None),
            closing: std::sync::atomic::AtomicBool::new(false),
            closing_signal: CancellationToken::new(),
            control: ResourceBudget::new(control_allocation)?,
            lease_control: ResourceBudget::new(control_allocation)?,
            metadata: ResourceBudget::new(control_allocation)?,
            process_slots: Arc::new(transport::AdmissionLimit::new(
                allocation.ordinary_operations,
            )),
            disconnect_reason: Default::default(),
        });
        monitor(&inner, 1, wire);
        monitor_budget(&inner);
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
        submit(&self.inner, request, body, None)
            .await?
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
        let mut allocation = self.inner.budget.connection_allocation()?;
        let active = self.inner.process_slots.in_use();
        let promised = active
            .saturating_add(allocation.ordinary_operations)
            .saturating_add(1)
            .saturating_mul(allocation.stream_window as usize)
            .min((1usize << 31) - 1) as u32;
        allocation.connection_window = allocation.connection_window.max(promised);
        if !self
            .inner
            .connection_credit
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .resize(connection_cost(allocation))
        {
            return Err(RemoteClientError::Remote {
                code: RemoteErrorCode::ResourceExhausted,
                message: "replacement connection credit unavailable".into(),
            });
        }
        let wire = tokio::select! {
            _ = self.inner.closing_signal.cancelled() => return Err(RemoteClientError::Cancelled),
            result = tokio::time::timeout_at(deadline, WireClient::connect(transport::Io { reader, writer }, allocation)) =>
                result.map_err(|_| RemoteClientError::Protocol("HTTP/2 replacement handshake timed out".into()))??,
        };
        wire.set_active_processes(active);
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
                &self.inner.control,
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
                    wire.request("shutdown", epoch, &RemoteRequest::Shutdown, Bytes::new(), &self.inner.lease_control)).await {
                    Ok(Ok(reply)) if matches!(reply.response, RemoteResponse::Ack) => Ok(()),
                    Ok(Ok(reply)) => Err(response_error(reply.response)),
                    Ok(Err(error)) => Err(error.into()),
                    Err(_) => Err(RemoteClientError::Remote { code: RemoteErrorCode::OutcomeUnknown,
                        message: "helper cleanup did not confirm before the shutdown deadline; its lease still owns pending resources".into() }),
                }
            }
            _ if self.attachment_expired() => Err(RemoteClientError::Remote {
                code: RemoteErrorCode::SessionExpired,
                message: "helper lease expired; physical cleanup is no longer observable".into(),
            }),
            _ => Err(RemoteClientError::Remote {
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
        // The closed wire cannot receive more DATA. An unresolved remote cleanup still retains
        // its diagnostic owner and corresponding resident metadata charge until that owner drops.
        let retained = result.as_ref().err().map_or(0, |error| {
            std::mem::size_of::<RemoteClientInner>()
                .saturating_add(error.to_string().len().saturating_mul(2))
        });
        self.inner
            .connection_credit
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .resize(retained);
        self.inner
            .connection_registration
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        *closed = Some(result.clone());
        result
    }
    /// Closes the current channel while preserving the helper session and its external owners.
    pub(super) async fn detach(&self) -> Result<(), RemoteClientError> {
        let current = self.inner.connection.borrow().clone();
        if let Connection::Ready { generation, wire } = current {
            mark_detached(&self.inner, generation, "transport detached".into());
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
                        code = ?failure.code, request_bytes = failure.request_bytes, reserved_bytes = failure.reserved_bytes,
                        wait_reason = ?failure.wait_reason, reply_bytes = failure.reply_bytes, "helper request failure diagnostic");
                }
            }
            Ok(Err(error)) => return Err(error),
            Ok(Ok(reply)) => return Err(response_error(reply.response)),
            Err(_) => {
                self.detach().await?;
                return Err(RemoteClientError::Disconnected);
            }
        }
        let policy = self.inner.policy;
        let allocation = tokio::task::spawn_blocking(move || policy.allocation())
            .await
            .map_err(|e| RemoteClientError::Protocol(e.to_string()))??;
        self.inner.budget.resize(allocation)?;
        configure_budget(&self.inner).await
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
    pub(super) fn reserve_page(
        &self,
        bytes: usize,
    ) -> Result<pl_remote_helper::budget::ByteLease, RemoteClientError> {
        self.inner
            .budget
            .try_reserve(bytes)
            .ok_or_else(|| RemoteClientError::Remote {
                code: RemoteErrorCode::ResourceExhausted,
                message: "directory page resource grant exhausted".into(),
            })
    }
    pub fn process_capacity(&self) -> usize {
        let local = self.inner.budget.allocation().ordinary_operations;
        self.inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map_or(local, |hello| {
                local.min(hello.allocation.ordinary_operations)
            })
    }
    pub(super) fn resident_buffer(
        &self,
        limit: usize,
    ) -> Result<buffer::ResidentBuffer, RemoteClientError> {
        buffer::ResidentBuffer::new(&self.inner.budget, limit.min(self.content_budget()))
            .map_err(Into::into)
    }
    pub fn content_budget(&self) -> usize {
        self.inner.budget.allocation().resident_bytes / 2
    }
    pub(super) fn release_resource(&self, request: RemoteRequest) {
        let inner = self.inner.clone();
        self.inner.streams.spawn(async move {
            if !inner.stopped.is_cancelled()
                && let Err(error) = request_inner(&inner, request, &[]).await
            {
                tracing::warn!(%error, "remote resource release failed");
            }
        });
    }
    pub fn fragment_bytes(&self) -> usize {
        let local = self.inner.budget.fragment_bytes();
        self.inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map_or(local, |hello| local.min(hello.allocation.fragment_bytes))
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
        submit(&self.inner, request, body, Some(lease))
            .await?
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
}

/// A complete next-step reservation: staging bytes, wire request and retained reply.
/// Dropping before submission has no remote side effects.
pub(super) struct UploadReservation {
    inner: Arc<RemoteClientInner>,
    workspace: Arc<workspace::WorkspaceLease>,
    request: RemoteRequest,
    memory: pl_remote_helper::budget::ByteLease,
    reply_limit: usize,
}
impl UploadReservation {
    pub(super) fn submit(
        self,
        bytes: Vec<u8>,
    ) -> impl Future<Output = Result<RemoteReply, RemoteClientError>> + Send {
        use sha2::{Digest, Sha256};
        let mut request = self.request;
        if let RemoteRequest::WriteChunk { sha256, .. } = &mut request {
            *sha256 = hex::encode(Sha256::digest(&bytes));
        }
        let received = submit_reserved(
            &self.inner,
            request,
            Bytes::from(bytes),
            Some(self.workspace),
            ReplyMemory::Owned {
                _lease: self.memory,
            },
            self.reply_limit,
            SubmissionControl::default(),
        );
        async move {
            received
                .await
                .unwrap_or(Err(RemoteClientError::Disconnected))
        }
    }
}
impl RemoteClient {
    pub(super) async fn reserve_upload(
        &self,
        workspace: Arc<workspace::WorkspaceLease>,
        transfer_id: String,
        offset: u64,
        count: usize,
        wait: bool,
    ) -> Result<Option<UploadReservation>, RemoteClientError> {
        if self.is_closing() {
            return Err(RemoteClientError::Disconnected);
        }
        let request = RemoteRequest::WriteChunk {
            transfer_id,
            offset,
            sha256: "0".repeat(64),
        };
        let (budget, cost, reply_limit) = request_cost(&self.inner, &request, count)?;
        let memory = if wait {
            Some(budget.reserve(cost, &self.inner.stopped).await?)
        } else {
            budget.try_reserve(cost)
        };
        Ok(memory.map(|memory| UploadReservation {
            inner: self.inner.clone(),
            workspace,
            request,
            memory,
            reply_limit,
        }))
    }
}

fn connection_cost(allocation: RemoteAllocation) -> usize {
    // Promised incoming DATA plus both independent lifecycle pools. These remain charged
    // even when the peer has not sent its DATA, so connection count cannot multiply credit.
    (allocation.connection_window as usize)
        .saturating_add(allocation.fragment_bytes.saturating_mul(12))
}
fn intersect(local: RemoteAllocation, remote: RemoteAllocation) -> RemoteAllocation {
    RemoteAllocation {
        resident_bytes: local.resident_bytes.min(remote.resident_bytes),
        fragment_bytes: local.fragment_bytes.min(remote.fragment_bytes),
        ordinary_operations: local.ordinary_operations.min(remote.ordinary_operations),
        stream_window: local.stream_window.min(remote.stream_window),
        connection_window: local.connection_window.min(remote.connection_window),
    }
}
async fn configure_budget(inner: &Arc<RemoteClientInner>) -> Result<(), RemoteClientError> {
    let _configure = inner.configuring.lock().await;
    let current = inner.connection.borrow().clone();
    let Connection::Ready { wire, .. } = current else {
        return Ok(());
    };
    if wire.is_closed()
        || inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_none()
    {
        return Ok(());
    }
    let mut allocation = inner.budget.connection_allocation()?;
    let active = inner.process_slots.in_use();
    wire.set_active_processes(active);
    if active > 0 {
        allocation.connection_window = allocation
            .connection_window
            .max(wire.allocation().connection_window);
    }
    let cost = connection_cost(allocation);
    {
        let mut credit = inner
            .connection_credit
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Growth is admitted atomically; a smaller future grant never revokes existing promises.
        if cost > credit.bytes() && !credit.resize(cost) {
            return Ok(());
        }
    }
    let reply = request_inner(inner, RemoteRequest::Configure { allocation }, &[]).await?;
    let RemoteResponse::Capacity(remote) = reply.response else {
        return Err(response_error(reply.response));
    };
    wire.resize(intersect(allocation, remote));
    let allocation = wire.allocation();
    inner
        .connection_credit
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .resize(connection_cost(allocation));
    let mut control = allocation;
    control.resident_bytes = allocation.fragment_bytes.saturating_mul(4);
    inner.control.resize(control)?;
    inner.lease_control.resize(control)?;
    inner.metadata.resize(control)?;
    inner.process_slots.resize(remote.ordinary_operations);
    if let Some(hello) = inner
        .hello
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_mut()
    {
        hello.allocation = remote;
    }
    Ok(())
}
fn monitor_budget(inner: &Arc<RemoteClientInner>) {
    let owner = inner.clone();
    inner.streams.spawn(async move {
        let mut previous = None;
        loop {
            let changed = owner.budget.changed();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let candidate = owner.budget.connection_allocation().ok();
            let connected = owner
                .hello
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_some();
            if connected && candidate != previous {
                match configure_budget(&owner).await {
                    Ok(()) => previous = candidate,
                    Err(error) => tracing::debug!(%error, "resource grant update deferred"),
                }
            }
            tokio::select! { _ = owner.stopped.cancelled() => break, _ = changed => {} }
        }
    });
}

type PendingReply = oneshot::Receiver<Result<RemoteReply, RemoteClientError>>;
async fn submit(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: &[u8],
    workspace: Option<Arc<workspace::WorkspaceLease>>,
) -> Result<PendingReply, RemoteClientError> {
    if inner.closing.load(Ordering::Acquire) && !request.is_control() {
        return Err(RemoteClientError::Disconnected);
    }
    let (budget, cost, reply_limit) = request_cost(inner, &request, body.len())?;
    let started = std::time::Instant::now();
    let memory = budget
        .reserve_with_intent(cost, &inner.stopped, &inner.budget)
        .await?;
    let admission = transport::elapsed_micros(started);
    Ok(submit_reserved(
        inner,
        request,
        Bytes::copy_from_slice(body),
        workspace,
        ReplyMemory::Owned { _lease: memory },
        reply_limit,
        SubmissionControl {
            admission_wait_micros: admission,
            ..Default::default()
        },
    ))
}
fn request_cost<'a>(
    inner: &'a RemoteClientInner,
    request: &RemoteRequest,
    body_len: usize,
) -> Result<(&'a ResourceBudget, usize, usize), RemoteClientError> {
    let control = request.is_control();
    let budget = if request.is_lease_control() {
        &inner.lease_control
    } else if request.is_metadata() {
        &inner.metadata
    } else if request.is_observation() {
        &inner.budget
    } else if control {
        &inner.control
    } else {
        &inner.budget
    };
    let encoded_length = serde_json::to_vec(&request)
        .map_err(|e| RemoteClientError::Protocol(e.to_string()))?
        .len();
    let reply_limit = match &request {
        RemoteRequest::ReadFileChunk { max_bytes, .. } => *max_bytes,
        RemoteRequest::WriteStdin { .. } | RemoteRequest::CloseStdin { .. } => {
            std::mem::size_of::<RemoteResponse>().saturating_add(encoded_length.saturating_mul(2))
        }
        _ if control && !request.is_lease_control() && !request.is_observation() => {
            std::mem::size_of::<RemoteResponse>()
                .saturating_add(std::mem::size_of::<RemoteRequest>())
                .saturating_add(encoded_length.saturating_mul(2))
        }
        _ => inner
            .hello
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map_or(budget.allocation().fragment_bytes, |hello| {
                hello
                    .allocation
                    .fragment_bytes
                    .min(budget.allocation().fragment_bytes)
            }),
    };
    let cost = body_len
        .saturating_add(encoded_length)
        .saturating_add(reply_limit.saturating_mul(2));
    Ok((budget, cost, reply_limit))
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
#[derive(Default)]
struct SubmissionControl {
    admission_wait_micros: u64,
    start: Option<crate::command::CommandStartControl>,
}
fn submit_reserved(
    inner: &Arc<RemoteClientInner>,
    request: RemoteRequest,
    body: Bytes,
    workspace: Option<Arc<workspace::WorkspaceLease>>,
    mut memory: ReplyMemory,
    reply_limit: usize,
    control: SubmissionControl,
) -> PendingReply {
    let id = format!(
        "{}-{}",
        inner.request_namespace,
        inner.next_request_id.fetch_add(1, Ordering::Relaxed)
    );
    let (reply, received) = oneshot::channel();
    let SubmissionControl {
        admission_wait_micros,
        start,
    } = control;
    let owner = inner.clone();
    let acquired = AcquiredResource::for_request(&request);
    inner.streams.spawn(async move {
        let _workspace = workspace;
        let mut result = perform(&owner, &id, request, body, reply_limit, start).await;
        if let Ok(reply) = &mut result {
            // The request and unused response promise are no longer resident. Keeping their
            // whole admission quantum in a tiny control reply can deadlock the next heartbeat
            // merely because a caller still holds its previous statistics snapshot.
            if let ReplyMemory::Owned { _lease: lease } = &mut memory {
                let metadata = serde_json::to_vec(&reply.response)
                    .map_or(lease.bytes(), |bytes| bytes.len().saturating_mul(2));
                let retained = reply.body.len().saturating_add(metadata).min(lease.bytes());
                lease.resize(retained);
            }
            reply._memory = Some(memory);
            reply.timing.admission_wait_micros = admission_wait_micros;
        }
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
    submit(inner, request, body, None)
        .await?
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))
}
async fn perform(
    inner: &Arc<RemoteClientInner>,
    id: &str,
    request: RemoteRequest,
    body: Bytes,
    reply_limit: usize,
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
        let budget = if control {
            &inner.control
        } else {
            &inner.budget
        };
        tracing::debug!(
            operation_id = id,
            generation,
            phase = "exchange",
            restoring = uncertain,
            "remote request phase"
        );
        match wire
            .request_reserved(id, epoch, &query, data, budget, Some(reply_limit))
            .await
        {
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
        inner
            .process_slots
            .resize(hello.allocation.ordinary_operations);
        if let Connection::Ready { wire, .. } = &*inner.connection.borrow() {
            wire.set_active_processes(inner.process_slots.in_use());
            wire.resize(intersect(wire.allocation(), hello.allocation));
        }
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
                    &inner.control,
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
        admission_wait_micros: 0,
        exchange_micros,
        cleanup_micros: transport::elapsed_micros(cleanup),
        remote: timing,
    };
    match response {
        RemoteResponse::Error(error) => Err(RemoteClientError::Remote {
            code: error.code,
            message: error.message,
        }),
        response => Ok(RemoteReply {
            response,
            body,
            timing,
            _memory: None,
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
            && let Err(error) = request_inner(&inner, release, &[]).await
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
    // The command already owns its IO/replay progress reservation. A terminal observation must
    // not acquire another data permit while those buffers are being drained or canceled.
    let id = format!(
        "{}-{}",
        inner.request_namespace,
        inner.next_request_id.fetch_add(1, Ordering::Relaxed)
    );
    let limit = inner
        .hello
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
        .map_or(inner.budget.allocation().fragment_bytes, |hello| {
            hello.allocation.fragment_bytes
        });
    perform(
        inner,
        &id,
        RemoteRequest::WaitProcess { process_id },
        Bytes::new(),
        limit,
        None,
    )
    .await
}
