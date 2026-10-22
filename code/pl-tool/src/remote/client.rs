//! 单物理连接的 typed client。
//!
//! 一个 [`RemoteClient`] 只拥有一条 T1 共用传输的物理连接：握手与之后的长驻控制事务由一个独立
//! owner 串行执行，普通操作各自取得真实子流预留。连接、操作、进程与 workspace 句柄的责任计数
//! 供端点裁决基线/扩展连接的收缩，client 本身不猜测容量上限。每条连接另有两个由 helper 公告的
//! 描述符预算：发送请求前同时取得该业务类别的整份 FD 峰值与物理子流，二者都不是可调大的常量。

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock, Weak};
use std::time::Duration;

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_protocol::remote::{
    RemoteHello, RemoteReadRequest, RemoteRequest, RemoteResourceClass, RemoteResponse,
    RemoteSpawnRequest, RemoteWorkspaceOpened, RemoteWriteRequest,
};
use pl_remote_helper::remote_transport::{
    ConnectionHandle, ConnectionOwner, IncomingStreams, Role, TransportError,
};
use tokio::sync::{Mutex, Notify, mpsc, oneshot};
use tokio::time::Instant;
use tokio_util::task::TaskTracker;

use self::control::ControlChannel;
use self::session::describe_transport_error;
use super::error::RemoteClientError;

mod control;
mod directory;
mod fds;
mod files;
mod process;
mod session;
pub(in crate::remote) mod workspace;

pub use self::directory::RemoteDirectoryStream;
pub(in crate::remote) use self::fds::{FdAcquire, FdAdmission, FdBudget, WorkspaceRetained};
pub use self::files::RemoteFileReader;
pub(in crate::remote) use self::session::{StreamLease, response_kind};
pub(in crate::remote) use self::workspace::{WorkspaceCache, WorkspaceLease};

/// Bounded queue of close/abort signals; only the owner task consumes it.
const CLOSE_QUEUE: usize = 8;
/// A heartbeat without any transport byte progress for this long ends the connection.
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(15);
/// Bound on observing the driver after a heartbeat abort was requested.
const ABORT_OBSERVE: Duration = Duration::from_secs(2);
/// Bound on the whole close request, observed terminal state and supervised-task join.
const CLOSE_TOTAL: Duration = Duration::from_secs(8);
/// Handshake budget of a caller-owned startup, so a peer that never answers cannot hang it.
const CONNECT_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(25);
/// Retry cadence while driving an unaccepted client's teardown to its terminal state.
const ABANDON_RETRY: Duration = Duration::from_millis(200);

static NEXT_CLIENT_INSTANCE: AtomicU64 = AtomicU64::new(0);

/// Bound on waiting for an in-flight shutdown frame to settle before classifying a terminal state.
const SHUTDOWN_SETTLE_WAIT: Duration = Duration::from_millis(250);

/// Progress of the one-way shutdown frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShutdownProgress {
    NotStarted = 0,
    InFlight = 1,
    Published = 2,
    Failed = 3,
}

/// Shared progress of the one-way shutdown frame.
struct ShutdownState {
    progress: std::sync::atomic::AtomicU8,
    settled: Notify,
}

impl ShutdownState {
    fn new() -> Self {
        Self {
            progress: std::sync::atomic::AtomicU8::new(ShutdownProgress::NotStarted as u8),
            settled: Notify::new(),
        }
    }

    fn current(&self) -> ShutdownProgress {
        match self.progress.load(Ordering::Acquire) {
            1 => ShutdownProgress::InFlight,
            2 => ShutdownProgress::Published,
            3 => ShutdownProgress::Failed,
            _ => ShutdownProgress::NotStarted,
        }
    }
}

/// One owned physical connection with its long-lived control transaction owner.
#[derive(Clone)]
pub struct RemoteClient {
    pub(super) inner: Arc<ClientInner>,
}

impl std::fmt::Debug for RemoteClient {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RemoteClient")
            .field("instance", &self.inner.instance)
            .field("protocol_version", &self.inner.hello.protocol_version)
            .field("activity", &self.inner.activity())
            .field("workspace_roots", &self.inner.active_workspaces())
            .field("closed", &self.inner.handle.is_closed())
            .finish_non_exhaustive()
    }
}

/// Shared state of one physical connection.
pub(super) struct ClientInner {
    instance: u64,
    handle: ConnectionHandle,
    hello: RemoteHello,
    control: ControlChannel,
    close: mpsc::Sender<CloseRequest>,
    /// The shared terminal observation of this connection; carries the driver's real result.
    closed: OnceLock<Shared<BoxFuture<'static, Result<(), RemoteClientError>>>>,
    /// The shared real teardown; per-call waiting deadlines never complete or replace it.
    teardown: OnceLock<Shared<BoxFuture<'static, Result<(), RemoteClientError>>>>,
    disconnect_reason: std::sync::Mutex<Option<String>>,
    /// Progress of the one-way shutdown frame; the terminal classification depends on it being
    /// published, so an expected end is never mistaken for an unexpected one.
    shutdown: ShutdownState,
    /// Local admission gate: sealed before the driver close so new work fails fast instead of
    /// queueing behind a teardown. Physical capacity is owned by the shared transport only.
    admission_sealed: std::sync::atomic::AtomicBool,
    /// Outstanding responsibilities: operations, processes, workspace handles, workspace closes.
    active: AtomicU64,
    /// Physical workspace handles whose `closeWorkspace` is still owed on this connection.
    pending_workspace_closes: AtomicU64,
    workspace_closes: std::sync::Mutex<HashSet<String>>,
    /// Descriptor admission of this physical helper, independent of the multiplexer's stream budget.
    fds: FdBudget,
    /// Active workspace roots whose persistent descriptor peak is still owed on this connection.
    ///
    /// The entry is the authority for that charge: it is dropped when the helper acknowledged the
    /// release or when the connection reached its terminal state, and real users keep their own share
    /// so permits return only after the last one ends. It never holds a `RemoteClient`.
    workspaces: std::sync::Mutex<HashMap<String, Arc<WorkspaceRetained>>>,
    idle: Notify,
    /// Every supervised task of this connection; the close path closes and drains it.
    pub(super) tasks: TaskTracker,
    /// Kept so inbound polling stays owned by the shared driver for the connection's lifetime.
    _incoming: Mutex<IncomingStreams>,
}

impl ClientInner {
    fn instance(&self) -> u64 {
        self.instance
    }

    fn activity(&self) -> u64 {
        self.active.load(Ordering::Acquire)
    }

    fn begin_activity(&self) {
        self.active.fetch_add(1, Ordering::AcqRel);
    }

    /// Seals local admission before the driver is asked to close, so a new operation fails fast
    /// instead of queueing behind the teardown.
    fn seal_admission(&self) {
        self.admission_sealed.store(true, Ordering::Release);
        // Both descriptor pools stop admitting and wake every waiter with the real closed state, so no
        // reservation can queue behind the teardown.
        self.fds.close();
    }

    fn admission_is_sealed(&self) -> bool {
        self.admission_sealed.load(Ordering::Acquire)
    }

    fn end_activity(&self) {
        if self.active.fetch_sub(1, Ordering::AcqRel) == 1 {
            self.wake_if_idle();
        }
    }

    fn is_idle(&self) -> bool {
        self.activity() == 0
            && self.pending_workspace_closes() == 0
            && self.active_workspaces() == 0
    }

    /// Active workspace roots still charged on this connection.
    fn active_workspaces(&self) -> usize {
        self.workspaces
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .len()
    }

    fn pending_workspace_closes(&self) -> u64 {
        self.pending_workspace_closes.load(Ordering::Acquire)
    }

    fn wake_if_idle(&self) {
        if self.is_idle() {
            self.idle.notify_waiters();
        }
    }

    /// Takes responsibility for releasing one physical workspace handle.
    ///
    /// The handle stays in this registry until the helper confirmed the release or the whole
    /// connection ended, so a healthy baseline never keeps a remote handle that the local table
    /// already forgot.
    fn begin_workspace_close(&self, workspace_id: &str) {
        let mut closes = self
            .workspace_closes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if closes.insert(workspace_id.to_string()) {
            self.pending_workspace_closes.fetch_add(1, Ordering::AcqRel);
        }
    }

    /// Drops one release responsibility after a confirmed release.
    fn finish_workspace_close(&self, workspace_id: &str) {
        let removed = {
            let mut closes = self
                .workspace_closes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            closes.remove(workspace_id)
        };
        if removed {
            self.pending_workspace_closes.fetch_sub(1, Ordering::AcqRel);
            self.wake_if_idle();
        }
    }

    /// Clears every release responsibility once the connection itself ended; the helper reclaims
    /// all handles when the control stream ends.
    fn clear_workspace_closes(&self, reason: &str) {
        let drained = {
            let mut closes = self
                .workspace_closes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let drained = closes.len();
            closes.clear();
            drained
        };
        if drained > 0 {
            tracing::debug!(
                connection = self.instance,
                drained,
                reason,
                "helper reclaims workspace handles after connection end"
            );
            self.pending_workspace_closes.store(0, Ordering::Release);
            self.wake_if_idle();
        }
    }

    /// Registers the persistent charge of one active workspace root on this connection.
    ///
    /// A second open that the helper answered with the same opaque handle shares the existing charge
    /// instead of charging twice; the newly split permit is then dropped and simply returns.
    fn charge_workspace(
        &self,
        id: &str,
        permit: tokio::sync::OwnedSemaphorePermit,
    ) -> Option<Arc<WorkspaceRetained>> {
        let mut workspaces = self
            .workspaces
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(existing) = workspaces.get(id) {
            return Some(Arc::clone(existing));
        }
        if self.admission_is_sealed() || self.handle.is_closed() {
            // The connection is already ending, so the helper reclaims every handle with it: registering
            // a charge now could only survive a table that was already cleared at the terminal state.
            return None;
        }
        let retained = Arc::new(WorkspaceRetained::new(id.to_string(), permit));
        workspaces.insert(id.to_string(), Arc::clone(&retained));
        Some(retained)
    }

    /// Drops the registry responsibility of a root the helper confirmed as released.
    ///
    /// Real users keep their own share, so the permits themselves return only when the last of them
    /// ends; a root that nobody else holds releases them here.
    fn release_workspace_root(&self, id: &str) {
        let removed = {
            let mut workspaces = self
                .workspaces
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            workspaces.remove(id)
        };
        if let Some(retained) = removed {
            tracing::debug!(
                connection = self.instance,
                workspace = %retained.id(),
                permits = retained.permits(),
                "workspace root charge released"
            );
            self.wake_if_idle();
        }
    }

    /// The live persistent charge of one active root, read under the same lock that removes it.
    ///
    /// An operation that captured the share before an acknowledgement keeps the descriptors until its
    /// own local end; an id this connection no longer knows yields `None`, so nothing is invented.
    fn capture_workspace(&self, id: &str) -> Option<Arc<WorkspaceRetained>> {
        self.workspaces
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .cloned()
    }

    /// Clears every active root once the connection itself ended.
    ///
    /// The helper reclaims its handles when the control stream ends, so no release is owed any more;
    /// the local descriptor charge of every root returns with this table.
    fn clear_active_workspaces(&self, reason: &str) {
        let drained = {
            let mut workspaces = self
                .workspaces
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let drained = workspaces.len();
            workspaces.clear();
            drained
        };
        if drained > 0 {
            tracing::debug!(
                connection = self.instance,
                drained,
                reason,
                "helper reclaims workspace roots after connection end"
            );
            self.wake_if_idle();
        }
    }

    /// Retains the first bounded failure reason of this connection.
    fn retain_reason(&self, reason: String) {
        let mut stored = self
            .disconnect_reason
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if stored.is_none() {
            *stored = Some(reason.chars().take(512).collect());
        }
    }

    /// Marks the start of the one-way shutdown frame, so a terminal state observed while it is in
    /// flight waits for its verdict instead of being classified too early.
    fn begin_shutdown(&self) {
        let _ = self.shutdown.progress.compare_exchange(
            ShutdownProgress::NotStarted as u8,
            ShutdownProgress::InFlight as u8,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
    }

    /// Publishes the verdict of the one-way shutdown frame.
    ///
    /// Only an in-flight frame can be settled, so a cancellation before the request reaches the control
    /// owner or a late guard can never overwrite a verdict the owner already published.
    fn settle_shutdown(&self, published: bool) {
        let state = if published {
            ShutdownProgress::Published
        } else {
            ShutdownProgress::Failed
        };
        if self
            .shutdown
            .progress
            .compare_exchange(
                ShutdownProgress::InFlight as u8,
                state as u8,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_ok()
        {
            self.shutdown.settled.notify_waiters();
        }
    }

    /// Whether a complete shutdown frame was published to the helper.
    fn shutdown_published(&self) -> bool {
        self.shutdown.current() == ShutdownProgress::Published
    }

    /// Waits for an in-flight shutdown frame to settle, bounded so observation never blocks a close.
    async fn settle_shutdown_wait(&self) {
        if self.shutdown.current() != ShutdownProgress::InFlight {
            return;
        }
        let notified = self.shutdown.settled.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        let _ = tokio::time::timeout(SHUTDOWN_SETTLE_WAIT, notified).await;
    }

    /// Observes the driver's real terminal state once, shared by every waiter.
    ///
    /// The observed `Result` is preserved instead of being flattened into a diagnostic: a driver
    /// that ended abnormally must never be reported as a clean close.
    fn observe_closed(
        self: &Arc<Self>,
    ) -> Shared<BoxFuture<'static, Result<(), RemoteClientError>>> {
        self.closed
            .get_or_init(|| {
                let handle = self.handle.clone();
                let client = Arc::downgrade(self);
                async move {
                    let outcome = handle.wait_closed().await;
                    let reason = match &outcome {
                        Ok(()) => "SSH transport closed".to_string(),
                        Err(error) => {
                            format!("SSH transport closed: {}", describe_transport_error(error))
                        }
                    };
                    let Some(inner) = client.upgrade() else {
                        // No connection state is left: only a clean end can be reported.
                        return match outcome {
                            Ok(()) => Ok(()),
                            Err(_) => Err(RemoteClientError::Disconnected),
                        };
                    };
                    // An expected terminal state depends on the shutdown frame being published, so a
                    // frame in flight is settled first instead of being classified too early.
                    inner.settle_shutdown_wait().await;
                    let result = match outcome {
                        Ok(()) => Ok(()),
                        Err(error) => inner.classify_terminal(error),
                    };
                    inner.retain_reason(reason.clone());
                    inner.clear_workspace_closes(&reason);
                    inner.clear_active_workspaces(&reason);
                    result
                }
                .boxed()
                .shared()
            })
            .clone()
    }

    /// Classifies the driver's real terminal error.
    ///
    /// A published shutdown makes the helper's own close the expected local terminal state; every real
    /// I/O, driver-task, multiplex or record failure stays a failure with its typed source, and an EOF
    /// without a published shutdown is a disconnect. No string and no `is_closed` is used here.
    fn classify_terminal(&self, error: TransportError) -> Result<(), RemoteClientError> {
        let published = self.shutdown_published();
        match error {
            TransportError::Closed if published => Ok(()),
            TransportError::Closed => Err(RemoteClientError::Disconnected),
            // T1 already owns these sources in an `Arc`, so they move straight into the typed
            // variants instead of being formatted.
            TransportError::Io(source) => Err(RemoteClientError::Io {
                stage: "transport",
                source,
            }),
            TransportError::DriverTask(source) => Err(RemoteClientError::Task {
                stage: "transport driver",
                source,
            }),
            TransportError::Multiplex(source) => Err(RemoteClientError::protocol(format!(
                "transport multiplexer failed: {source}"
            ))),
            TransportError::InvalidRecord { .. }
            | TransportError::RecordTooLarge { .. }
            | TransportError::Encoding { .. }
            | TransportError::ControlAlreadyOpened
            | TransportError::Cancelled => Err(RemoteClientError::protocol(format!(
                "transport ended: {}",
                describe_transport_error(&error)
            ))),
        }
    }

    /// Runs this connection's one real teardown, shared so repeated closes observe one result.
    ///
    /// Admission is sealed synchronously before the shared future is returned. The future carries no
    /// caller deadline: a waiting caller that times out only stops waiting, so its deadline can never
    /// be cached as this connection's result and a later caller keeps observing the same unfinished
    /// teardown instead of a permanent failure.
    fn teardown_once(
        self: &Arc<Self>,
    ) -> Shared<BoxFuture<'static, Result<(), RemoteClientError>>> {
        self.teardown
            .get_or_init(|| {
                self.seal_admission();
                let client = Arc::downgrade(self);
                async move {
                    let Some(inner) = client.upgrade() else {
                        return Ok(());
                    };
                    let request = inner.request_close().await;
                    let observed = inner.observe_closed().await;
                    // Closing the tracker and waiting for it happens inside this shared teardown, so
                    // abandoning a caller never abandons the supervised tasks.
                    inner.tasks.close();
                    inner.tasks.wait().await;
                    match (request, observed) {
                        // A real terminal failure keeps its typed source whichever fact carried it.
                        (_, Err(error)) if !matches!(&error, RemoteClientError::Disconnected) => {
                            Err(error)
                        }
                        // A close request that itself failed is a real close failure.
                        (CloseCause::Failed(error), _) => {
                            let reason = format!(
                                "close SSH transport: {}",
                                describe_transport_error(&error)
                            );
                            inner.retain_reason(reason.clone());
                            Err(RemoteClientError::protocol(reason))
                        }
                        // This side ended the transport, so closing it without a shutdown frame is the
                        // expected result of that deliberate close.
                        (CloseCause::Requested, _) => Ok(()),
                        // The driver ended before it was asked: only a fully published shutdown frame
                        // makes that the expected transport end.
                        (CloseCause::NotRequested, observed) => observed,
                    }
                }
                .boxed()
                .shared()
            })
            .clone()
    }

    /// Whether the real teardown finished and every supervised task ended.
    ///
    /// The shared teardown future resolves only after `tasks.wait()` returned, so a resolved teardown
    /// plus an empty tracker is the internal proof that client cleanup is complete. Callers must not
    /// infer this from an error string or from `wait_disconnected`.
    fn teardown_is_complete(&self) -> bool {
        self.teardown.get().and_then(Shared::peek).is_some() && self.tasks.is_empty()
    }

    /// Asks the owner to close the driver and reports how that request relates to its real end.
    ///
    /// The distinction is a transport fact, not a formatted result: this call returning
    /// [`CloseCause::Requested`] means the driver ended because this request closed it, while
    /// [`CloseCause::NotRequested`] means the driver had already ended on its own, and the shared
    /// terminal observation in [`Self::teardown_once`] then decides whether that end was expected.
    async fn request_close(self: &Arc<Self>) -> CloseCause {
        // The owner is always notified, even when the driver already ended: the local owner task must
        // observe the request and end, or `tasks.wait()` would keep waiting for a task nobody wakes.
        let (done, completed) = oneshot::channel();
        if self.close.send(CloseRequest::Close { done }).await.is_err() {
            // The owner already finished, so this request cannot claim the end it never caused.
            return CloseCause::NotRequested;
        }
        match completed.await {
            Ok(Ok(())) => CloseCause::Requested,
            // The driver had already ended: the terminal observation decides whether that was expected.
            Ok(Err(TransportError::Closed)) | Err(_) => CloseCause::NotRequested,
            Ok(Err(error)) => CloseCause::Failed(error),
        }
    }

    /// Requests connection abort after a connection-level protocol violation.
    fn request_abort(&self, reason: String) {
        self.retain_reason(reason.clone());
        let close = self.close.clone();
        let instance = self.instance;
        tokio::spawn(async move {
            if close.send(CloseRequest::Abort { reason }).await.is_err() {
                tracing::debug!(instance, "connection owner already finished");
            }
        });
    }

    /// Waits until no responsibility remains on this connection.
    async fn wait_idle(&self) {
        loop {
            let notified = self.idle.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if self.is_idle() {
                return;
            }
            notified.await;
        }
    }
}

enum CloseRequest {
    /// Close the driver and report its observed terminal state.
    Close {
        done: oneshot::Sender<Result<(), TransportError>>,
    },
    /// Abort after a protocol violation; observers read the retained reason.
    Abort { reason: String },
}

/// How this connection's driver end relates to a local close request.
///
/// The two facts are independent: an expected transport end needs either a fully published shutdown
/// frame or a close this connection itself requested, and neither may be inferred from an error text.
enum CloseCause {
    /// The driver ended because this call's close request closed it.
    Requested,
    /// The driver had already ended, or the owner had finished, before it could be asked.
    NotRequested,
    /// The close request itself failed.
    Failed(TransportError),
}

/// One physical transport that is owned before the handshake can be cancelled.
///
/// The transport owner is taken synchronously, so a handshake timeout or a cancelled caller can still
/// close and join the driver. Nothing here is a second connection manager: the pool and the public
/// [`RemoteClient::connect`] use this one startup path.
pub(in crate::remote) struct StartupOwner {
    owner: ConnectionOwner,
    handle: ConnectionHandle,
    incoming: IncomingStreams,
    negotiated: Option<control::NegotiatedControl>,
}

impl StartupOwner {
    /// Takes ownership of the transport before any cancellable await.
    pub(in crate::remote) fn start<R, W>(reader: R, writer: W) -> Self
    where
        R: tokio::io::AsyncRead + Unpin + Send + 'static,
        W: tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let (owner, handle, incoming) = ConnectionOwner::start(reader, writer, Role::Client);
        Self {
            owner,
            handle,
            incoming,
            negotiated: None,
        }
    }

    /// Runs the hello transaction on the reserved control stream.
    ///
    /// The transport stays owned here, so a caller that cancels this wait must call
    /// [`Self::release`] to close and join it.
    pub(in crate::remote) async fn handshake(&mut self) -> Result<(), RemoteClientError> {
        let negotiated = control::negotiate(&self.handle).await?;
        self.negotiated = Some(negotiated);
        Ok(())
    }

    /// Converts a completed handshake into the typed client.
    ///
    /// # Errors
    /// Reports a startup whose handshake never completed; the caller then releases it.
    pub(in crate::remote) fn into_client(self) -> Result<RemoteClient, RemoteClientError> {
        let Self {
            owner,
            handle,
            incoming,
            negotiated,
        } = self;
        let negotiated = negotiated.ok_or_else(|| {
            RemoteClientError::protocol("helper handshake was not completed before assembling")
        })?;
        Ok(RemoteClient::assemble(owner, handle, incoming, negotiated))
    }

    /// Drives this startup in an owned task and hands the client to the caller.
    ///
    /// The task owns the transport for the whole startup, so a cancelled caller neither abandons a
    /// started driver nor keeps a client it never accepted: the task closes and joins the driver on a
    /// failed handshake, and tears down a client no waiter claimed. Cancelling before the first poll
    /// owns nothing, because the task is spawned only when this future is first polled.
    pub(in crate::remote) async fn connect_owned(self) -> Result<RemoteClient, RemoteClientError> {
        let (mut ready, accepted) = oneshot::channel::<Result<RemoteClient, RemoteClientError>>();
        let (claim, claimed) = oneshot::channel::<()>();
        tokio::spawn(async move {
            let mut startup = self;
            // The caller dropping its receiver, or a peer that never answers, ends this wait; the
            // transport is still owned here, so it is closed and joined below instead of hanging.
            let handshake = tokio::select! {
                biased;
                () = ready.closed() => None,
                result = tokio::time::timeout(CONNECT_HANDSHAKE_TIMEOUT, startup.handshake()) => {
                    match result {
                        Ok(result) => Some(result),
                        Err(_) => Some(Err(RemoteClientError::protocol(
                            "helper handshake timed out",
                        ))),
                    }
                }
            };
            let Some(handshake) = handshake else {
                // No caller will ever accept this startup: release the transport here.
                if let Err(error) = startup.release("cancelled helper handshake").await {
                    tracing::debug!(%error, "cancelled helper startup cleanup reported");
                }
                return;
            };
            if let Err(error) = handshake {
                // The transport is still owned here, so the release is real and its failure is
                // reported instead of being swallowed.
                let error = match startup.release("helper handshake").await {
                    Ok(()) => error,
                    Err(release_error) => RemoteClientError::aggregate(
                        "helper handshake failed",
                        Some(error),
                        &[release_error.to_string()],
                    ),
                };
                let _ = ready.send(Err(error));
                return;
            }
            let client = match startup.into_client() {
                Ok(client) => client,
                Err(error) => {
                    let _ = ready.send(Err(error));
                    return;
                }
            };
            let owned = client.clone();
            if ready.send(Ok(client)).is_err() {
                // No caller is waiting any more: this task owns the release to a real terminal state.
                release_unaccepted(&owned).await;
                return;
            }
            // The caller claims synchronously after receiving; a dropped caller is cleaned up here.
            if claimed.await.is_err() {
                release_unaccepted(&owned).await;
            }
        });
        match accepted.await {
            Ok(Ok(client)) => {
                // Claimed without an intervening await, so no cancellation can lose this client.
                let _ = claim.send(());
                Ok(client)
            }
            Ok(Err(error)) => Err(error),
            // The startup task ended without a result: the transport is already released.
            Err(_) => Err(RemoteClientError::Disconnected),
        }
    }

    /// Closes and joins the transport of a startup that never produced a client.
    ///
    /// # Errors
    /// Reports the driver's real terminal failure instead of swallowing it.
    pub(in crate::remote) async fn release(
        self,
        stage: &'static str,
    ) -> Result<(), RemoteClientError> {
        match self.owner.close().await {
            Ok(()) => Ok(()),
            // A startup never published a shutdown frame, so its terminal state is classified like any
            // other unexpected end: real I/O and driver-task sources are kept, EOF is a disconnect.
            Err(error) => Err(match error {
                TransportError::Closed => RemoteClientError::Disconnected,
                TransportError::Io(source) => RemoteClientError::Io { stage, source },
                TransportError::DriverTask(source) => RemoteClientError::Task {
                    stage: "transport driver",
                    source,
                },
                TransportError::Multiplex(source) => RemoteClientError::protocol(format!(
                    "{stage}: transport multiplexer failed: {source}"
                )),
                TransportError::Cancelled => RemoteClientError::Cancelled,
                TransportError::ControlAlreadyOpened
                | TransportError::InvalidRecord { .. }
                | TransportError::RecordTooLarge { .. }
                | TransportError::Encoding { .. } => RemoteClientError::protocol(format!(
                    "{stage}: transport close failed: {}",
                    describe_transport_error(&error)
                )),
            }),
        }
    }
}

impl RemoteClient {
    /// Starts one client-role connection and completes the v9 hello handshake.
    ///
    /// The returned client owns its control stream and never shares a request/response table with
    /// other connections. The startup runs in a task that owns the transport, so cancelling this call
    /// still closes and joins the driver instead of detaching it.
    ///
    /// # Errors
    /// Reports a transport failure, an application hello rejection, or a protocol mismatch.
    pub async fn connect<R, W>(reader: R, writer: W) -> Result<Self, RemoteClientError>
    where
        R: tokio::io::AsyncRead + Unpin + Send + 'static,
        W: tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        StartupOwner::start(reader, writer).connect_owned().await
    }

    /// Builds the typed client from an owned transport with a completed handshake.
    fn assemble(
        owner: ConnectionOwner,
        handle: ConnectionHandle,
        incoming: IncomingStreams,
        negotiated: control::NegotiatedControl,
    ) -> Self {
        let (control, control_requests) = ControlChannel::channel();
        let (close, close_requests) = mpsc::channel(CLOSE_QUEUE);
        // The advertised peaks are logged from the one copy this connection validates and then keeps;
        // they are public hello facts, so no payload, path or credential is involved.
        let limits = negotiated.fds.limits();
        let inner = Arc::new(ClientInner {
            instance: NEXT_CLIENT_INSTANCE.fetch_add(1, Ordering::Relaxed) + 1,
            handle: handle.clone(),
            hello: negotiated.hello,
            fds: negotiated.fds,
            control,
            close,
            closed: OnceLock::new(),
            teardown: OnceLock::new(),
            shutdown: ShutdownState::new(),
            disconnect_reason: Default::default(),
            admission_sealed: std::sync::atomic::AtomicBool::new(false),
            active: AtomicU64::new(0),
            pending_workspace_closes: AtomicU64::new(0),
            workspace_closes: Default::default(),
            workspaces: Default::default(),
            idle: Notify::new(),
            tasks: TaskTracker::new(),
            _incoming: Mutex::new(incoming),
        });
        // Both driver-side tasks are owned by this connection's task tracker: closing the
        // connection seals the tracker and waits for the real end of its owners.
        let control_task = inner.tasks.track_future(control::run(
            negotiated.reader,
            negotiated.writer,
            control_requests,
            Arc::downgrade(&inner),
        ));
        tokio::spawn(control_task);
        let owner_task = inner.tasks.track_future(run_connection_owner(
            owner,
            close_requests,
            Arc::downgrade(&inner),
        ));
        tokio::spawn(owner_task);
        tracing::debug!(
            connection = inner.instance(),
            helper_version = %inner.hello.helper_version,
            os = %inner.hello.os,
            architecture = %inner.hello.architecture,
            operation_fds = limits.operation_fds,
            workspace_fds = limits.workspace_fds,
            cost_workspace_open = limits.costs.workspace_open,
            cost_workspace_retained = limits.costs.workspace_retained,
            cost_metadata = limits.costs.metadata,
            cost_directory = limits.costs.directory,
            cost_read_file = limits.costs.read_file,
            cost_write_file = limits.costs.write_file,
            cost_copy_file = limits.costs.copy_file,
            cost_spawn = limits.costs.spawn,
            "connected remote helper"
        );
        Self { inner }
    }

    /// The helper handshake observed on this connection.
    pub fn hello(&self) -> &RemoteHello {
        &self.inner.hello
    }

    /// Stable in-process identity of this physical connection.
    pub(in crate::remote) fn instance(&self) -> u64 {
        self.inner.instance()
    }

    /// Whether both clients are the same physical connection.
    pub fn is_same_connection(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }

    pub fn is_disconnected(&self) -> bool {
        self.inner.handle.is_closed()
    }

    /// Completes when the driver reached its terminal state; repeated waits share one observation.
    pub async fn wait_disconnected(&self) {
        // The observation carries the real terminal result; callers of this signal-only wait read
        // the retained reason instead of receiving a fabricated success.
        let _ = self.inner.observe_closed().await;
    }

    /// First transport failure reason, excluding payloads, environment and credentials.
    pub fn disconnect_reason(&self) -> Option<String> {
        self.inner
            .disconnect_reason
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    /// Whether this connection's client cleanup is confirmed complete.
    ///
    /// The caller uses it to decide between "resources released" and "still owned", so it never has to
    /// parse an error string or mistake a dead driver for a drained task set.
    pub(in crate::remote) fn is_teardown_complete(&self) -> bool {
        self.inner.teardown_is_complete()
    }

    /// Last actual byte progress observed by the shared transport.
    pub fn last_progress(&self) -> Instant {
        self.inner.handle.last_progress()
    }

    /// Closes this transport once and returns the real teardown result.
    ///
    /// The remote helper also reclaims its handles when the control stream ends, so no remote
    /// acknowledgement is required here. The teardown itself carries no deadline: this call only
    /// bounds how long *it* waits, so a timed-out caller can never cache its timeout as the result and
    /// the next call keeps observing the same real teardown, which is idempotently `Ok` on success and
    /// a stable `Err` after a real driver failure.
    ///
    /// # Errors
    /// Reports the driver's abnormal terminal state or a supervised task that did not finish; the
    /// failure is retained as this connection's reason so the caller keeps the resource owned.
    pub async fn close(&self) -> Result<(), RemoteClientError> {
        let teardown = self.inner.teardown_once();
        match tokio::time::timeout(CLOSE_TOTAL, teardown).await {
            Ok(result) => result,
            // A caller deadline is not a terminal state: the shared teardown keeps running for the
            // next caller, and the residual ownership is reported here instead of being hidden.
            Err(_) => {
                let residual = self.inner.tasks.len();
                let reason = format!(
                    "SSH close did not finish within {CLOSE_TOTAL:?}; {residual} supervised remote task(s) remain"
                );
                self.inner.retain_reason(reason.clone());
                Err(RemoteClientError::protocol(reason))
            }
        }
    }

    /// Runs one unary or control request.
    ///
    /// File, directory and process requests own their own streams and are rejected here.
    ///
    /// # Errors
    /// Reports admission, transport, protocol and typed helper errors.
    pub async fn request(
        &self,
        request: RemoteRequest,
    ) -> Result<RemoteResponse, RemoteClientError> {
        match request {
            RemoteRequest::Hello { .. } => Err(RemoteClientError::protocol(
                "the helper handshake is completed by connect()",
            )),
            RemoteRequest::Shutdown => Err(RemoteClientError::protocol(
                "shutdown is a one-way frame; use request_shutdown()",
            )),
            RemoteRequest::Heartbeat => {
                self.heartbeat().await?;
                Ok(RemoteResponse::Ack)
            }
            request @ (RemoteRequest::Terminate { .. } | RemoteRequest::CloseWorkspace { .. }) => {
                let workspace_id = match &request {
                    RemoteRequest::CloseWorkspace { workspace_id } => Some(workspace_id.clone()),
                    _ => None,
                };
                let response = self.inner.control.transaction(&self.inner, request).await?;
                if let Some(workspace_id) = workspace_id
                    && matches!(response, RemoteResponse::Ack)
                {
                    // The helper confirmed the release: the release responsibility and the persistent
                    // root charge are no longer owed here. Real users keep their own share, so the
                    // descriptors themselves return only after the last of them ends.
                    self.inner.finish_workspace_close(&workspace_id);
                    self.inner.release_workspace_root(&workspace_id);
                }
                Ok(response)
            }
            request @ (RemoteRequest::ReadFile(_)
            | RemoteRequest::WriteFile(_)
            | RemoteRequest::ListDirectory(_)
            | RemoteRequest::BrowseDirectories { .. }
            | RemoteRequest::Spawn(_)) => Err(RemoteClientError::protocol(format!(
                "{} owns a dedicated operation stream",
                session::method_name(&request)
            ))),
            // Every workspace open — including this public entry point — runs on its own tracked owner
            // that keeps the persistent root charge and hands the result to this caller.
            RemoteRequest::OpenWorkspace { path } => self.open_workspace_request(path).await,
            request => {
                // The addressed root is captured before the request is sent, so a concurrent release
                // acknowledgement can never return its descriptors while this operation still runs.
                let class = request.resource_class();
                let workspace_id = session::request_workspace_id(&request);
                self.lease_for(class, workspace_id)
                    .await?
                    .request(request)
                    .await
            }
        }
    }

    /// Opens one workspace for a direct caller and keeps its persistent charge on this connection.
    ///
    /// The transaction runs on its own tracked owner, so a cancelled caller cannot leave a half-open
    /// handle: an unclaimed result is closed on this same connection. The active table keeps the root
    /// charged until a matching `closeWorkspace` is acknowledged or the connection ends.
    async fn open_workspace_request(
        &self,
        path: String,
    ) -> Result<RemoteResponse, RemoteClientError> {
        let lease = self.lease(RemoteResourceClass::OpenWorkspace).await?;
        let opened = self
            .open_workspace_owned(lease, path)
            .await
            .map_err(|_| RemoteClientError::Disconnected)??;
        // The caller accepts the root here: the response and the connection's active table keep it
        // alive, and the registry charge returns when a matching `closeWorkspace` is acknowledged or
        // the link ends.
        let (workspace_id, canonical_path, _retained) = opened.into_parts();
        Ok(RemoteResponse::WorkspaceOpened(RemoteWorkspaceOpened {
            workspace_id,
            canonical_path,
        }))
    }

    /// Opens one incremental directory or browse sequence.
    ///
    /// # Errors
    /// Rejects every request that is not a directory/browse request, plus admission and
    /// transport failures.
    pub async fn directory(
        &self,
        request: RemoteRequest,
    ) -> Result<RemoteDirectoryStream, RemoteClientError> {
        match request {
            request @ (RemoteRequest::ListDirectory(_)
            | RemoteRequest::BrowseDirectories { .. }) => {
                let workspace_id = session::request_workspace_id(&request);
                self.lease_for(RemoteResourceClass::Directory, workspace_id)
                    .await?
                    .directory(request)
                    .await
            }
            other => Err(RemoteClientError::protocol(format!(
                "{} does not produce a directory sequence",
                session::method_name(&other)
            ))),
        }
    }

    /// Opens one file read stream; EOF is reported only after a verified transfer end.
    ///
    /// # Errors
    /// Reports admission, transport, protocol and typed helper errors.
    pub async fn read_file(
        &self,
        request: RemoteReadRequest,
    ) -> Result<RemoteFileReader, RemoteClientError> {
        self.lease_for(
            RemoteResourceClass::ReadFile,
            Some(request.workspace_id.as_str()),
        )
        .await?
        .read_file(request)
        .await
    }

    /// Uploads exactly `request.total_len` bytes and returns the confirmed transferred length.
    ///
    /// # Errors
    /// Reports admission, transport, protocol, short-source and typed helper errors.
    pub async fn write_file<R>(
        &self,
        request: RemoteWriteRequest,
        reader: &mut R,
    ) -> Result<u64, RemoteClientError>
    where
        R: tokio::io::AsyncRead + Unpin + Send,
    {
        self.lease_for(
            RemoteResourceClass::WriteFile,
            Some(request.target.workspace_id.as_str()),
        )
        .await?
        .write_file(request, reader)
        .await
    }

    /// Starts one remote process and transfers its supervision into the returned command lease.
    ///
    /// # Errors
    /// Reports admission, transport, protocol and typed helper startup errors.
    pub async fn spawn_process(
        &self,
        request: RemoteSpawnRequest,
    ) -> Result<crate::command::ManagedCommand, RemoteClientError> {
        self.lease_for(
            RemoteResourceClass::Spawn,
            Some(request.workspace_id.as_str()),
        )
        .await?
        .spawn_process(request)
        .await
    }

    /// Completes one acknowledged control heartbeat.
    ///
    /// The wait is extended only by actual transport byte progress, so a slow but live transfer is
    /// never mistaken for a lost connection.
    ///
    /// # Errors
    /// Reports a typed rejection, a closed connection, or a no-progress timeout after aborting it.
    pub async fn heartbeat(&self) -> Result<(), RemoteClientError> {
        let reply = self
            .inner
            .control
            .transaction(&self.inner, RemoteRequest::Heartbeat);
        tokio::pin!(reply);
        let mut deadline = Instant::now() + HEARTBEAT_TIMEOUT;
        loop {
            match tokio::time::timeout_at(deadline, reply.as_mut()).await {
                Ok(result) => {
                    session::expect_ack(result?)?;
                    return Ok(());
                }
                Err(_) => {
                    let next = self.inner.handle.last_progress() + HEARTBEAT_TIMEOUT;
                    if next <= Instant::now() {
                        self.inner.request_abort(
                            "helper heartbeat response timed out without transport progress"
                                .to_string(),
                        );
                        let _ =
                            tokio::time::timeout(ABORT_OBSERVE, self.inner.observe_closed()).await;
                        return Err(RemoteClientError::Disconnected);
                    }
                    deadline = next;
                }
            }
        }
    }

    /// Asks the driver to end after a connection-level failure, without waiting for teardown.
    ///
    /// The connection owner observes it exactly like any other close, so no caller can mistake this
    /// connection for a clean one, and no second teardown is started beside the physical teardown.
    pub(in crate::remote) fn abort(&self, reason: String) {
        self.inner.request_abort(reason);
    }

    /// Publishes the one-way shutdown frame locally; remote cleanup is not acknowledged.
    ///
    /// # Errors
    /// Reports a control admission or transport failure.
    pub async fn request_shutdown(&self) -> Result<(), RemoteClientError> {
        self.inner
            .control
            .one_way(&self.inner, RemoteRequest::Shutdown)
            .await
    }

    /// Cancellable admission for a direct caller: this connection's own capacity decides.
    ///
    /// Both budgets are taken in one fixed order — descriptors first, then the physical stream — and a
    /// failure or cancellation of the second step drops the first, so no half reservation survives.
    /// Waiting uses the real semaphores: a released descriptor or stream wakes the waiter, and sealing
    /// or a driver close ends it with the real error instead of a poll/yield loop.
    ///
    /// # Errors
    /// Reports a closed connection, a control class misuse, or a reserve failure.
    pub(in crate::remote) async fn lease(
        &self,
        class: RemoteResourceClass,
    ) -> Result<StreamLease, RemoteClientError> {
        self.lease_for(class, None).await
    }

    /// Admits one operation of `class` and keeps the workspace root it addresses charged until it ends.
    ///
    /// The root share is captured under the same lock that `closeWorkspace` acknowledgement uses, so an
    /// acknowledgement that lands while this operation is still running removes only the registry entry:
    /// the descriptors stay with the running operation until its own local completion.
    pub(in crate::remote) async fn lease_for(
        &self,
        class: RemoteResourceClass,
        workspace_id: Option<&str>,
    ) -> Result<StreamLease, RemoteClientError> {
        if class == RemoteResourceClass::Control {
            return Err(RemoteClientError::protocol(
                "control requests reserve the stream for their own class on the control stream",
            ));
        }
        if self.inner.admission_is_sealed() || self.inner.handle.is_closed() {
            return Err(RemoteClientError::Disconnected);
        }
        let root = workspace_id.and_then(|id| self.inner.capture_workspace(id));
        let fds = tokio::select! {
            biased;
            _ = self.inner.observe_closed() => return Err(RemoteClientError::Disconnected),
            admission = self.inner.fds.acquire(class) => admission,
        };
        let fds = match fds {
            FdAcquire::Granted(lease) => lease,
            FdAcquire::Closed => return Err(RemoteClientError::Disconnected),
        };
        // The shared transport owns the physical permit and its close linearization: waiting for a
        // real released slot is the only stream admission wait here (no local capacity estimate, no
        // timer/yield loop), and a driver close or a local seal ends it with the real error.
        let reservation = tokio::select! {
            biased;
            _ = self.inner.observe_closed() => return Err(RemoteClientError::Disconnected),
            result = self.inner.handle.reserve() => result.map_err(|error| {
                self.transport_failure("reserve operation stream", error)
            })?,
        };
        if self.inner.admission_is_sealed() {
            // Both reservations return to their real budgets when this scope ends.
            drop(reservation);
            return Err(RemoteClientError::Disconnected);
        }
        let (operation_fds, workspace_fds) = fds.permits();
        tracing::trace!(
            connection = self.instance(),
            class = ?class,
            operation_fds,
            workspace_fds,
            "reserved remote operation descriptors"
        );
        Ok(StreamLease::new(self.clone(), reservation, fds, root))
    }

    /// Non-blocking admission for the endpoint pool; `None` means this healthy connection cannot give
    /// the whole demand — no free physical stream, or no free descriptor of this class — and the pool
    /// may extend.
    ///
    /// # Errors
    /// Reports a sealed/closed connection as [`RemoteClientError::Disconnected`]; a live connection
    /// without capacity is `Ok(None)`, never an error.
    pub(in crate::remote) fn try_lease(
        &self,
        class: RemoteResourceClass,
    ) -> Result<Option<StreamLease>, RemoteClientError> {
        if class == RemoteResourceClass::Control {
            return Err(RemoteClientError::protocol(
                "control requests reserve the stream for their own class on the control stream",
            ));
        }
        if self.inner.admission_is_sealed() || self.inner.handle.is_closed() {
            return Err(RemoteClientError::Disconnected);
        }
        let fds = match self.inner.fds.try_lease(class) {
            FdAdmission::Granted(lease) => lease,
            FdAdmission::Exhausted => return Ok(None),
            FdAdmission::Closed => return Err(RemoteClientError::Disconnected),
        };
        match self.inner.handle.try_reserve() {
            Ok(Some(reservation)) => {
                let (operation_fds, workspace_fds) = fds.permits();
                tracing::trace!(
                    connection = self.instance(),
                    class = ?class,
                    operation_fds,
                    workspace_fds,
                    "reserved remote operation descriptors"
                );
                Ok(Some(StreamLease::new(self.clone(), reservation, fds, None)))
            }
            // A live connection without a free stream releases the descriptor lease with this scope.
            Ok(None) => Ok(None),
            Err(error) => Err(self.transport_failure("reserve operation stream", error)),
        }
    }

    /// Waits until every operation, process, workspace handle and workspace close has ended.
    pub(in crate::remote) async fn wait_idle(&self) {
        self.inner.wait_idle().await;
    }

    /// Maps one transport failure, retaining the first reason only when the connection is gone.
    pub(in crate::remote) fn transport_failure(
        &self,
        stage: &'static str,
        error: TransportError,
    ) -> RemoteClientError {
        let description = describe_transport_error(&error);
        match error {
            // A closed connection or a multiplexer failure is connection-terminal and keeps the real
            // cause as this connection's first failure.
            TransportError::Closed | TransportError::Multiplex(_) => {
                self.inner.retain_reason(format!("{stage}: {description}"));
                RemoteClientError::Disconnected
            }
            // A real I/O failure keeps its source. It is connection-fatal, so the typed source never
            // makes a broken connection look healthy.
            TransportError::Io(source) => {
                self.inner.retain_reason(format!("{stage}: {description}"));
                tracing::debug!(
                    connection = self.instance(),
                    stage,
                    io = %source,
                    "remote stream I/O failure"
                );
                RemoteClientError::Io { stage, source }
            }
            // An abnormally ended driver keeps its join source as a task failure.
            TransportError::DriverTask(source) => {
                self.inner.retain_reason(format!("{stage}: {description}"));
                RemoteClientError::Task {
                    stage: "transport driver",
                    source,
                }
            }
            // A locally abandoned operation is not a physical failure.
            TransportError::Cancelled => RemoteClientError::Cancelled,
            // A second control claim is a client defect, not a transport outage.
            TransportError::ControlAlreadyOpened => {
                RemoteClientError::protocol(format!("{stage}: {description}"))
            }
            // Record and I/O problems end only the affected stream and leave the connection usable.
            TransportError::InvalidRecord { .. }
            | TransportError::RecordTooLarge { .. }
            | TransportError::Encoding { .. } => {
                tracing::debug!(
                    connection = self.instance(),
                    stage,
                    %description,
                    "remote stream failure"
                );
                RemoteClientError::Protocol(format!("{stage}: {description}"))
            }
        }
    }
}

/// Drives a client that no caller accepted to its real terminal state.
///
/// One `close` call only bounds the wait and leaves the shared teardown for the next caller, so this
/// loop keeps observing it until the client reports a completed teardown. The abnormal terminal cause
/// stays in the client's retained reason instead of being formatted away.
async fn release_unaccepted(client: &RemoteClient) {
    loop {
        match client.close().await {
            Ok(()) => return,
            Err(error) => {
                if client.is_teardown_complete() {
                    tracing::debug!(
                        %error,
                        "unaccepted helper transport was released after an abnormal end"
                    );
                    return;
                }
                tracing::debug!(%error, "unaccepted helper transport teardown is not finished yet");
                tokio::time::sleep(ABANDON_RETRY).await;
            }
        }
    }
}

/// The single owner of the driver's lifetime: one close/abort, then cancellation on drop.
async fn run_connection_owner(
    owner: ConnectionOwner,
    mut requests: mpsc::Receiver<CloseRequest>,
    client: Weak<ClientInner>,
) {
    let closed = match client.upgrade() {
        Some(inner) => inner.observe_closed(),
        None => return,
    };
    tokio::select! {
        biased;
        // The driver already reached its terminal state: this owner has no further work, so it ends
        // here and can be joined instead of waiting for a request nobody will send.
        _ = closed => {}
        request = requests.recv() => match request {
            Some(CloseRequest::Close { done }) => {
                let result = owner.close().await;
                if let Err(error) = &result
                    && let Some(inner) = client.upgrade()
                {
                    inner.retain_reason(format!(
                        "close SSH transport: {}",
                        describe_transport_error(error)
                    ));
                }
                let _ = done.send(result);
            }
            Some(CloseRequest::Abort { reason }) => {
                if let Err(error) = owner.close().await
                    && let Some(inner) = client.upgrade()
                {
                    inner.retain_reason(format!(
                        "abort SSH transport after {reason}: {}",
                        describe_transport_error(&error)
                    ));
                }
            }
            None => {}
        },
    }
    // Dropping the owner here requests driver cancellation when no explicit close arrived.
}
