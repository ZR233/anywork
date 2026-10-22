//! 一条物理 SSH/helper 连接的所有权：SSH 进程、stderr 排空、心跳、workspace 句柄与回收。
//!
//! 连接创建（含架构探测、helper bootstrap 与交接握手）复用既有的 OpenSSH 出口；一个 endpoint
//! 可以拥有多条这样的物理连接，每条连接只服务在其上取得租约的操作。连接状态是同步原子量，
//! 使 endpoint 能在同一个线性化临界区内完成 sealed 检查、hello 裁决与连接发布。

use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex as SyncMutex};
use std::time::Duration;

use pl_protocol::remote::RemoteHello;
use process_wrap::tokio::ChildWrapper;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::environment::ExecutionEnvironment;

use super::super::client::{RemoteClient, WorkspaceCache};
use super::super::error::RemoteClientError;
use super::super::ssh_config::SshConfigFile;
use super::SshServerProfile;
use super::asset::{RemoteHelperTarget, load_helper, upload_helper};
use super::ssh;

/// Handshake deadline of one new physical connection.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(25);
/// Period of the acknowledged control heartbeat.
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(5);
/// Bound on flushing the one-way shutdown frame before the local transport closes.
const SHUTDOWN_FLUSH: Duration = Duration::from_millis(250);
/// Retained tail of the SSH stderr stream; diagnostics only, never wire data.
const STDERR_TAIL_BYTES: usize = 4096;
/// Bounded wait for the stderr drain to reach EOF after the child was reaped.
const STDERR_DRAIN_DEADLINE: Duration = Duration::from_secs(3);
/// Bounded wait for the driver to observe the reaped SSH process closing the channel.
const TRANSPORT_OBSERVE: Duration = Duration::from_secs(2);
/// Bound on the teardown diagnostics retained across retries of one connection.
const MAX_TEARDOWN_DIAGNOSTICS: usize = 8;
/// Bound on one retained diagnostic entry: diagnostics never carry file bodies or credentials.
const MAX_DIAGNOSTIC_CHARS: usize = 512;

/// Lifecycle of one physical connection inside its endpoint pool.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub(in crate::remote) enum PhysicalState {
    /// Accepting new operations.
    Active = 0,
    /// No new operations; waiting for its outstanding responsibilities to end.
    Retiring = 1,
    /// Failed; kept in the registry until its cleanup is confirmed.
    Failed = 2,
    /// Confirmed closed and removed from the registry.
    Closed = 3,
}

impl PhysicalState {
    fn from_raw(raw: u8) -> Self {
        match raw {
            1 => Self::Retiring,
            2 => Self::Failed,
            3 => Self::Closed,
            _ => Self::Active,
        }
    }
}

enum Teardown {
    /// Not released yet, with what earlier attempts already observed: the first real cause and the
    /// bounded notes (for example an SSH stderr tail). Both survive into the result that finally
    /// releases the connection.
    Pending {
        notes: Vec<String>,
        failure: Option<RemoteClientError>,
    },
    /// Released, with the first teardown's real result so a repeated close reports it again instead of
    /// turning an abnormal close into a clean one.
    Closed {
        outcome: Result<(), RemoteClientError>,
    },
}

/// One physical connection's teardown result.
///
/// "Whether the local resources were released" and "what the close reported" are separate facts:
/// a connection can be fully released while its driver ended abnormally, and that real failure must
/// still reach the endpoint instead of being flattened into a clean close.
pub(in crate::remote) enum Reclaim {
    /// The driver, SSH process and stderr drain are confirmed released. `outcome` is the real
    /// teardown/driver result and may still be an error.
    Released {
        outcome: Result<(), RemoteClientError>,
    },
    /// Local resources could not be confirmed released; the connection keeps its owner so the pool
    /// can retry the teardown and must not report it as reclaimed.
    Pending { error: RemoteClientError },
}

impl std::fmt::Debug for Reclaim {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Released { outcome } => formatter
                .debug_struct("Reclaim::Released")
                .field("outcome", outcome)
                .finish(),
            Self::Pending { error } => formatter
                .debug_struct("Reclaim::Pending")
                .field("error", error)
                .finish(),
        }
    }
}

/// A failed startup, with the real physical ownership it could not release.
///
/// A failure that confirmed its cleanup is the whole story. One that could not hands every still owned
/// resource to its caller, so the endpoint keeps the obligation instead of a text record or a bool.
pub(in crate::remote) enum ConnectFailure {
    /// Nothing is owned any more; the error is the whole responsibility.
    Clean(RemoteClientError),
    /// A failed startup that still owns physical resources; the endpoint adopts `cleanup`.
    Pending {
        error: RemoteClientError,
        cleanup: Box<PendingStartup>,
    },
}

impl ConnectFailure {
    fn clean(error: RemoteClientError) -> Self {
        Self::Clean(error)
    }
}

impl std::fmt::Debug for ConnectFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Clean(error) => formatter
                .debug_tuple("ConnectFailure::Clean")
                .field(error)
                .finish(),
            Self::Pending { error, cleanup } => formatter
                .debug_struct("ConnectFailure::Pending")
                .field("error", error)
                .field("generation", &cleanup.generation())
                .finish(),
        }
    }
}

/// What a startup release observed, whether or not it finished.
///
/// The data is persistent: the first real cause and the bounded notes stay in
/// [`StartupResources`](StartupResources), so a later attempt that finally releases the startup (or the
/// endpoint's own result) still carries them instead of losing an earlier stderr tail.
#[derive(Debug, Default)]
pub(in crate::remote) struct StartupRelease {
    /// Whether every owned resource is confirmed released by this attempt.
    pub(in crate::remote) released: bool,
    /// Bounded stderr tail read so far, used only for diagnostics and auth classification.
    pub(in crate::remote) stderr_tail: Option<String>,
    /// Bounded notes; they never keep a resource owned.
    pub(in crate::remote) diagnostics: Vec<String>,
    /// The first real typed cause this startup could not resolve, if any.
    pub(in crate::remote) failure: Option<RemoteClientError>,
}

/// A failed startup that still owns a transport, an SSH child and its stderr drain.
///
/// The failure has already been reported to its caller; this owner keeps the real resources until
/// their release is confirmed, so nothing can be lost with a cancelled waiter, a diagnostic ring or a
/// later `close` that only remembers text.
pub(in crate::remote) struct PendingStartup {
    alias: String,
    generation: u64,
    stage: &'static str,
    resources: Mutex<StartupResources>,
}

#[derive(Default)]
struct StartupResources {
    client: Option<RemoteClient>,
    child: Option<Box<dyn ChildWrapper>>,
    stderr: Option<StderrDrain>,
    /// First real cause observed by any attempt; kept across retries.
    failure: Option<RemoteClientError>,
    /// Bounded notes observed by any attempt; kept across retries.
    notes: Vec<String>,
}

impl PendingStartup {
    /// Takes ownership of one failed startup's remaining physical resources.
    pub(in crate::remote) fn new(
        alias: String,
        generation: u64,
        stage: &'static str,
        client: Option<RemoteClient>,
        child: Box<dyn ChildWrapper>,
        stderr: Option<tokio::process::ChildStderr>,
    ) -> Self {
        let resources = StartupResources {
            client,
            child: Some(child),
            stderr: stderr.map(|stderr| spawn_stderr_drain(stderr, alias.clone(), generation)),
            failure: None,
            notes: Vec::new(),
        };
        Self {
            alias,
            generation,
            stage,
            resources: Mutex::new(resources),
        }
    }

    pub(in crate::remote) fn generation(&self) -> u64 {
        self.generation
    }

    /// Releases whatever it still owns and reports what any attempt has observed so far.
    ///
    /// The first real cause and the bounded notes are stored in the startup itself, so a later attempt
    /// that finally releases it (or the endpoint's own result) still carries an earlier stderr tail or
    /// source instead of losing it. Diagnostic read failures never keep a resource owned.
    pub(in crate::remote) async fn release(&self) -> StartupRelease {
        let mut resources = self.resources.lock().await;
        let mut retained = false;
        // Every slot is borrowed in place and cleared only after its confirmed terminal state, so a
        // cancelled release leaves the real ownership here for the next attempt.
        let client = resources.client.clone();
        if let Some(client) = client {
            if let Err(error) = client.close().await {
                // The source is archived, not just noted: a completed teardown still reports it.
                push_diagnostic(
                    &mut resources.notes,
                    format!("transport close reported: {error}"),
                );
                resources.failure.get_or_insert(error);
            }
            if client.is_teardown_complete() {
                resources.client = None;
            } else {
                resources.failure.get_or_insert_with(|| {
                    RemoteClientError::protocol("transport teardown did not finish")
                });
                retained = true;
            }
        }
        let reaped = match resources.child.as_mut() {
            Some(child) => Some(ssh::reap_ssh_child(child, self.stage).await),
            None => None,
        };
        match reaped {
            None => {}
            Some(Ok(outcome)) => {
                resources.child = None;
                let natural = outcome.natural_status();
                if let Some(error) = outcome.kill_error {
                    // A termination request that failed is not swallowed: it stays a typed cause.
                    resources.failure.get_or_insert(error);
                }
                // An exit is not success by itself: a natural non-zero exit is a real helper failure,
                // while a forced kill is this attempt's own teardown and carries no exit verdict.
                if let Some(status) = natural
                    && !status.success()
                {
                    push_diagnostic(
                        &mut resources.notes,
                        format!("SSH helper exited with {status}"),
                    );
                    resources.failure.get_or_insert_with(|| {
                        RemoteClientError::protocol(format!("SSH helper exited with {status}"))
                    });
                }
            }
            Some(Err(error)) => {
                resources.failure.get_or_insert(error);
                retained = true;
            }
        }
        if resources.stderr.is_some() {
            match join_stderr_drain(&mut resources.stderr, self.stage).await {
                Ok(tail) => {
                    if let Some(tail) = tail {
                        push_diagnostic(&mut resources.notes, format!("stderr tail: {tail}"));
                    }
                }
                Err(error) => {
                    // The drain task was aborted and joined, so its handle is released; the bounded
                    // tail and the real I/O source are kept as diagnostics.
                    if let Some(tail) = error.tail() {
                        push_diagnostic(&mut resources.notes, format!("stderr tail: {tail}"));
                    }
                    push_diagnostic(&mut resources.notes, error.to_string());
                    if let Some(failure) = error.into_client_error() {
                        resources.failure.get_or_insert(failure);
                    }
                }
            }
        }
        if !retained {
            tracing::debug!(
                alias = %self.alias,
                generation = self.generation,
                "released a failed startup's physical resources"
            );
        }
        StartupRelease {
            released: !retained,
            stderr_tail: resources
                .notes
                .iter()
                .find_map(|note| note.strip_prefix("stderr tail: ").map(str::to_owned)),
            diagnostics: resources.notes.clone(),
            failure: resources.failure.clone(),
        }
    }
}

impl std::fmt::Debug for PendingStartup {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PendingStartup")
            .field("alias", &self.alias)
            .field("generation", &self.generation)
            .field("stage", &self.stage)
            .finish_non_exhaustive()
    }
}

/// The helper bootstrap facts reused by every later connection of the same endpoint.
#[derive(Debug, Default)]
pub(in crate::remote) struct Bootstrap {
    remote_path: Option<String>,
}

/// Bounded stderr capture shared with the drain task, so an aborted drain still reports what it
/// actually read and which real I/O failure it hit.
struct StderrCapture {
    tail: Vec<u8>,
    /// The real read failure, moved out by the single joiner instead of being flattened to text.
    failure: Option<std::io::Error>,
}

impl StderrCapture {
    fn new() -> Self {
        Self {
            tail: Vec::new(),
            failure: None,
        }
    }
}

/// The owned stderr drain of one connection: the task and its shared capture.
pub(in crate::remote) struct StderrDrain {
    task: JoinHandle<()>,
    capture: Arc<SyncMutex<StderrCapture>>,
}

impl std::fmt::Debug for StderrDrain {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StderrDrain")
            .field("finished", &self.task.is_finished())
            .finish()
    }
}

/// Typed outcome of joining the stderr drain; never derived from diagnostic text.
#[derive(Debug)]
pub(in crate::remote) enum StderrDrainError {
    Read {
        stage: &'static str,
        source: std::sync::Arc<std::io::Error>,
    },
    Task {
        stage: &'static str,
        source: std::sync::Arc<tokio::task::JoinError>,
    },
    Timeout {
        stage: &'static str,
        deadline: Duration,
        /// Bounded tail actually read before the abort; part of the displayed failure.
        tail: Option<String>,
    },
}

impl std::fmt::Display for StderrDrainError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Read { stage, source } => {
                write!(formatter, "SSH stderr read failed during {stage}: {source}")
            }
            Self::Task { stage, source } => write!(
                formatter,
                "SSH stderr drain ended abnormally during {stage}: {source}"
            ),
            Self::Timeout {
                stage,
                deadline,
                tail,
            } => {
                write!(
                    formatter,
                    "SSH stderr drain did not reach EOF during {stage} within {deadline:?}"
                )?;
                if let Some(tail) = tail {
                    write!(formatter, "; tail: {tail}")?;
                }
                Ok(())
            }
        }
    }
}

impl std::error::Error for StderrDrainError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Read { source, .. } => Some(source.as_ref()),
            Self::Task { source, .. } => Some(source.as_ref()),
            Self::Timeout { .. } => None,
        }
    }
}

impl StderrDrainError {
    /// The bounded tail this failure already read, when it timed out.
    fn tail(&self) -> Option<&str> {
        match self {
            Self::Timeout { tail, .. } => tail.as_deref(),
            Self::Read { .. } | Self::Task { .. } => None,
        }
    }

    /// Maps a real read/task failure onto the shared typed error, keeping its source.
    fn into_client_error(self) -> Option<RemoteClientError> {
        match self {
            Self::Read { stage, source } => Some(RemoteClientError::Io { stage, source }),
            Self::Task { stage, source } => Some(RemoteClientError::Task { stage, source }),
            // The task is aborted and joined (the resource is released), but a drain that needed the
            // deadline is a real diagnostic failure, not a normal tail.
            Self::Timeout { stage, .. } => Some(RemoteClientError::protocol(format!(
                "SSH stderr drain timed out during {stage}"
            ))),
        }
    }
}

/// One owned physical connection.
pub(in crate::remote) struct PhysicalConnection {
    pub(in crate::remote) client: RemoteClient,
    pub(in crate::remote) hello: RemoteHello,
    pub(in crate::remote) environment: ExecutionEnvironment,
    /// Physical generation inside this endpoint; never reused for another connection.
    pub(in crate::remote) generation: u64,
    /// Logical endpoint generation observed when this connection was created.
    pub(in crate::remote) endpoint_generation: u64,
    pub(in crate::remote) alias: String,
    workspaces: Arc<WorkspaceCache>,
    heartbeat: CancellationToken,
    process: Mutex<Box<dyn ChildWrapper>>,
    stderr_drain: Mutex<Option<StderrDrain>>,
    /// The owned heartbeat task, joined in place on close so a cancelled close cannot detach it.
    heartbeat_task: Mutex<Option<JoinHandle<()>>>,
    /// Whether the SSH process reap was already confirmed, so a retried teardown never reaps twice.
    process_reaped: AtomicBool,
    state: AtomicU8,
    teardown: Mutex<Teardown>,
}

impl std::fmt::Debug for PhysicalConnection {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PhysicalConnection")
            .field("alias", &self.alias)
            .field("endpoint_generation", &self.endpoint_generation)
            .field("generation", &self.generation)
            .field("state", &self.state())
            .field("client", &self.client)
            .finish_non_exhaustive()
    }
}

impl PhysicalConnection {
    /// Current lifecycle state of this connection.
    pub(in crate::remote) fn state(&self) -> PhysicalState {
        PhysicalState::from_raw(self.state.load(Ordering::Acquire))
    }

    /// Publishes the confirmed-closed state of this connection.
    ///
    /// Every admission-relevant transition is published by the endpoint that owns this connection
    /// while it holds its pool state, so the pool's health, hello and generation decisions are made
    /// against one serialized fact instead of a value read from changing memory.
    pub(in crate::remote) fn mark_closed(&self) {
        self.state
            .store(PhysicalState::Closed as u8, Ordering::Release);
    }

    /// Whether the connection may still accept new operations.
    ///
    /// Admission-relevant transitions of this flag are published by the owning endpoint while it
    /// holds its pool state, so a pool decision reads a serialized fact together with the registry
    /// instead of a value that can change under it. The driver-liveness part is monotonic: once the
    /// shared transport ended it never reports healthy again.
    pub(in crate::remote) fn is_available(&self) -> bool {
        self.state() == PhysicalState::Active && !self.client.is_disconnected()
    }

    /// Marks a lost connection so no new operation is admitted on it.
    pub(in crate::remote) fn mark_failed(&self) {
        let _ = self.state.compare_exchange(
            PhysicalState::Active as u8,
            PhysicalState::Failed as u8,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
        let _ = self.state.compare_exchange(
            PhysicalState::Retiring as u8,
            PhysicalState::Failed as u8,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
    }

    /// Moves an active connection into retirement; `false` means it must stay admitted.
    pub(in crate::remote) fn begin_retirement(&self) -> bool {
        self.state
            .compare_exchange(
                PhysicalState::Active as u8,
                PhysicalState::Retiring as u8,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_ok()
    }

    /// The per-connection weak cache of physical workspace handles.
    pub(in crate::remote) fn cache(&self) -> &Arc<WorkspaceCache> {
        &self.workspaces
    }

    /// Bounded local teardown: heartbeat, shutdown frame, driver, SSH process and stderr drain.
    ///
    /// Releasing the resources and reporting what the close did are separate facts: an abnormal driver
    /// end still releases the connection, and it is still reported as an error. Only a confirmed
    /// release removes the connection from its pool; anything unconfirmed keeps its owner for a retry.
    pub(in crate::remote) async fn close(&self, stage: &'static str) -> Reclaim {
        let mut teardown = self.teardown.lock().await;
        // What earlier attempts observed is kept and folded into the result that finally releases this
        // connection. The first real cause and the bounded notes are separate facts: an SSH banner or a
        // log line is not a failure, while driver/reap/owner anomalies are.
        let (mut notes, mut first_failure) = match &*teardown {
            Teardown::Closed { outcome } => {
                // Already released: repeat the first teardown's real result instead of a clean one.
                return Reclaim::Released {
                    outcome: outcome.clone(),
                };
            }
            Teardown::Pending { notes, failure } => (notes.clone(), failure.clone()),
        };
        // Two independent facts: whether the real resources are released, and what the close reports.
        let mut unconfirmed = false;
        self.heartbeat.cancel();
        {
            // The heartbeat task is joined in place and only forgotten once it really ended, so a
            // cancelled close never detaches it and it can never touch the transport afterwards.
            let mut heartbeat = self.heartbeat_task.lock().await;
            if let Some(task) = heartbeat.as_mut()
                && let Err(join_error) = task.await
            {
                // A panicking heartbeat owner keeps its join source instead of a formatted string.
                let failure = RemoteClientError::task("heartbeat", join_error);
                first_failure.get_or_insert(failure);
            }
            *heartbeat = None;
        }
        if !self.client.is_disconnected() {
            match tokio::time::timeout(SHUTDOWN_FLUSH, self.client.request_shutdown()).await {
                Ok(Ok(())) => {}
                Ok(Err(error)) => tracing::warn!(
                    alias = %self.alias,
                    endpoint_generation = self.endpoint_generation,
                    generation = self.generation,
                    stage,
                    %error,
                    "SSH shutdown frame was not written"
                ),
                Err(_) => tracing::warn!(
                    alias = %self.alias,
                    endpoint_generation = self.endpoint_generation,
                    generation = self.generation,
                    stage,
                    "SSH shutdown frame flush timed out"
                ),
            }
        }
        // The driver result is reported as-is: an abnormal end is never rewritten into a clean close.
        let transport = self.client.close().await;
        // A repeated caller deadline can leave the shared client teardown unfinished; that is a real
        // owned obligation, judged by teardown completion rather than by parsing error text.
        if !self.client.is_teardown_complete() {
            unconfirmed = true;
            first_failure.get_or_insert_with(|| match &transport {
                Ok(()) => RemoteClientError::protocol("client teardown did not finish"),
                Err(error) => RemoteClientError::aggregate(
                    "client teardown did not finish",
                    Some(error.clone()),
                    &[],
                ),
            });
        }
        if self.process_reaped.load(Ordering::Acquire) {
            // A previous teardown attempt already confirmed the reap; retrying it would only re-enter
            // the finished child.
        } else {
            let mut process = self.process.lock().await;
            match ssh::reap_ssh_child(&mut process, stage).await {
                Ok(outcome) => {
                    self.process_reaped.store(true, Ordering::Release);
                    let natural = outcome.natural_status();
                    if let Some(error) = outcome.kill_error {
                        first_failure.get_or_insert(error);
                    }
                    tracing::debug!(
                        alias = %self.alias,
                        generation = self.generation,
                        stage,
                        status = ?outcome.status,
                        forced = outcome.forced,
                        "reaped SSH process"
                    );
                    // An observed exit is not success by itself: a natural non-zero exit is a real
                    // helper failure. A forced kill is this teardown's own decision.
                    if let Some(status) = natural
                        && !status.success()
                    {
                        push_diagnostic(&mut notes, format!("SSH helper exited with {status}"));
                        first_failure.get_or_insert_with(|| {
                            RemoteClientError::protocol(format!("SSH helper exited with {status}"))
                        });
                    }
                }
                Err(error) => {
                    unconfirmed = true;
                    first_failure.get_or_insert(error);
                }
            }
        }
        // Reaping the SSH process closes the channel; a driver that still has not ended is an
        // unreleased resource, not a note.
        if tokio::time::timeout(TRANSPORT_OBSERVE, self.client.wait_disconnected())
            .await
            .is_err()
        {
            unconfirmed = true;
            first_failure.get_or_insert_with(|| {
                RemoteClientError::protocol(
                    "transport did not end after the SSH process was reaped",
                )
            });
        }
        {
            // The drain task is joined in place: a cancelled caller releases only this borrow, so a
            // later close joins the same task instead of detaching it.
            let mut drain = self.stderr_drain.lock().await;
            match join_stderr_drain(&mut drain, stage).await {
                Ok(Some(tail)) => {
                    tracing::warn!(
                        alias = %self.alias,
                        endpoint_generation = self.endpoint_generation,
                        generation = self.generation,
                        diagnostic = %tail,
                        "SSH process stderr tail"
                    );
                    push_diagnostic(&mut notes, format!("stderr tail: {tail}"));
                }
                Ok(None) => {}
                Err(error) => {
                    if let Some(tail) = error.tail() {
                        tracing::warn!(
                            alias = %self.alias,
                            generation = self.generation,
                            diagnostic = %tail,
                            "SSH stderr tail before the drain was aborted"
                        );
                        push_diagnostic(&mut notes, format!("stderr tail: {tail}"));
                    }
                    // The task was aborted and joined, so the handle is released; a real read/task
                    // failure keeps its typed source, a deadline stays a note.
                    push_diagnostic(&mut notes, format!("stderr: {error}"));
                    if let Some(failure) = error.into_client_error() {
                        first_failure.get_or_insert(failure);
                    }
                }
            }
        }
        if unconfirmed {
            // A real resource is still owned: keep the owner, keep the first cause and notes, and let
            // the pool retry. A later confirmed release ends this connection.
            if let Err(transport_error) = &transport {
                push_diagnostic(&mut notes, format!("transport: {transport_error}"));
            }
            let error = RemoteClientError::aggregate(
                format!("SSH connection cleanup failed ({stage})"),
                first_failure.clone(),
                &notes,
            );
            *teardown = Teardown::Pending {
                notes,
                failure: first_failure,
            };
            return Reclaim::Pending { error };
        }
        // Every resource is released. An earlier abnormal cause still decides the reported result, but
        // it never keeps the connection pinned in the registry.
        for note in &notes {
            tracing::debug!(
                alias = %self.alias,
                generation = self.generation,
                stage,
                note,
                "SSH teardown note"
            );
        }
        let outcome = match (first_failure, transport) {
            (Some(failure), Err(transport_error)) => {
                tracing::debug!(%transport_error, "transport also reported a failure");
                Err(failure)
            }
            (Some(failure), Ok(())) => Err(failure),
            (None, transport) => transport,
        };
        *teardown = Teardown::Closed {
            outcome: outcome.clone(),
        };
        Reclaim::Released { outcome }
    }
}

/// Creates one client-role physical connection: bootstrap, OpenSSH stdio, handshake and ownership.
///
/// All inputs one endpoint owner must supply for a new connection are grouped here, so the call
/// site states the domain facts instead of a long positional argument list.
pub(in crate::remote) struct PhysicalConnect<'a> {
    pub(in crate::remote) profile: &'a SshServerProfile,
    pub(in crate::remote) ssh_config: &'a SshConfigFile,
    pub(in crate::remote) password: Option<&'a str>,
    pub(in crate::remote) assets: Option<Arc<dyn super::RemoteHelperAssets>>,
    pub(in crate::remote) alias: &'a str,
    pub(in crate::remote) endpoint_generation: u64,
    pub(in crate::remote) generation: u64,
    pub(in crate::remote) closing: &'a CancellationToken,
    pub(in crate::remote) bootstrap: Arc<Mutex<Bootstrap>>,
}

/// Creates one client-role physical connection: bootstrap, OpenSSH stdio, handshake and ownership.
///
/// # Errors
/// Reports platform, helper asset, SSH process, authentication, handshake and protocol failures.
pub(in crate::remote) async fn connect_physical(
    options: PhysicalConnect<'_>,
) -> Result<PhysicalConnection, ConnectFailure> {
    let PhysicalConnect {
        profile,
        ssh_config,
        password,
        assets,
        alias,
        endpoint_generation,
        generation,
        closing,
        bootstrap,
    } = options;
    let cached_path = { bootstrap.lock().await.remote_path.clone() };
    let remote_path = match cached_path {
        Some(path) => path,
        None => {
            // Nothing is started yet, so a failure here never owns an SSH child.
            let platform =
                ssh::run_ssh_capture(profile, ssh_config, password, "uname -s; uname -m")
                    .await
                    .map_err(ConnectFailure::clean)?;
            let target =
                RemoteHelperTarget::from_uname(&platform).map_err(ConnectFailure::clean)?;
            let assets = assets.ok_or_else(|| {
                ConnectFailure::clean(RemoteClientError::protocol(format!(
                    "helper artifact for {} is not available",
                    target.triple()
                )))
            })?;
            let helper = load_helper(assets, target)
                .await
                .map_err(ConnectFailure::clean)?;
            let path = upload_helper(profile, ssh_config, password, &helper)
                .await
                .map_err(ConnectFailure::clean)?;
            {
                let mut bootstrap = bootstrap.lock().await;
                bootstrap.remote_path = Some(path.clone());
            }
            path
        }
    };

    let mut prepared = ssh::ssh_command(profile, ssh_config, password)
        .await
        .map_err(ConnectFailure::clean)?;
    prepared
        .command
        .command_mut()
        .arg(ssh::posix_remote_command(&format!("exec {remote_path}")))
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    let mut child = prepared.command.spawn().map_err(|error| {
        ConnectFailure::clean(RemoteClientError::protocol(format!(
            "failed to start ssh: {error}"
        )))
    })?;
    // From here on this attempt owns a real SSH child, so every failure reports whether it was
    // reclaimed instead of leaving that fact to a string.
    let Some(stdin) = child.stdin().take() else {
        return Err(startup_failure(
            alias,
            generation,
            child,
            None,
            RemoteClientError::protocol("ssh process has no stdin"),
        )
        .await);
    };
    let Some(stdout) = child.stdout().take() else {
        return Err(startup_failure(
            alias,
            generation,
            child,
            None,
            RemoteClientError::protocol("ssh process has no stdout"),
        )
        .await);
    };

    // The transport owner is taken before this await, so a timeout or an endpoint close can really
    // close and join the driver instead of only reaping the SSH child.
    let mut startup = super::super::client::StartupOwner::start(stdout, stdin);
    let handshake = tokio::select! {
        biased;
        // An endpoint close is a real cancellation, so it keeps the typed closing cause instead of
        // pretending the peer broke the protocol.
        () = closing.cancelled() => Err(RemoteClientError::ManagerClosing),
        result = tokio::time::timeout(HANDSHAKE_TIMEOUT, startup.handshake()) => match result {
            Ok(result) => result,
            Err(_) => Err(RemoteClientError::protocol("helper handshake timed out")),
        },
    };
    if let Err(error) = handshake {
        let release = startup.release("helper handshake").await;
        let error = match release {
            Ok(()) => error,
            // A failed release is a real cleanup failure with its own typed source: when the handshake
            // itself only ended because of the close, that cleanup failure is the true cause; otherwise
            // the genuine handshake failure stays first and the release failure is a bounded note.
            Err(release_error) => match error {
                RemoteClientError::ManagerClosing => RemoteClientError::aggregate(
                    "helper handshake cancelled by endpoint close",
                    Some(release_error),
                    &[],
                ),
                error => RemoteClientError::aggregate(
                    "helper handshake failed",
                    Some(error),
                    &[release_error.to_string()],
                ),
            },
        };
        return Err(startup_failure(alias, generation, child, None, error).await);
    }
    let client = match startup.into_client() {
        Ok(client) => client,
        Err(error) => {
            return Err(startup_failure(alias, generation, child, None, error).await);
        }
    };

    let environment = match super::execution_environment_from_hello(client.hello()) {
        Ok(environment) => environment,
        Err(error) => {
            return Err(startup_failure(alias, generation, child, Some(client), error).await);
        }
    };

    let drain = child
        .stderr()
        .take()
        .map(|stderr| spawn_stderr_drain(stderr, alias.to_owned(), generation));
    let heartbeat = CancellationToken::new();
    let heartbeat_task = spawn_heartbeat(
        client.clone(),
        alias,
        generation,
        endpoint_generation,
        closing.clone(),
        heartbeat.clone(),
    );
    let connection = PhysicalConnection {
        hello: client.hello().clone(),
        client,
        environment,
        generation,
        endpoint_generation,
        alias: alias.to_owned(),
        workspaces: Arc::new(WorkspaceCache::default()),
        heartbeat,
        process: Mutex::new(child),
        stderr_drain: Mutex::new(drain),
        heartbeat_task: Mutex::new(Some(heartbeat_task)),
        process_reaped: AtomicBool::new(false),
        state: AtomicU8::new(PhysicalState::Active as u8),
        teardown: Mutex::new(Teardown::Pending {
            notes: Vec::new(),
            failure: None,
        }),
    };
    Ok(connection)
}

/// Releases what a failed startup owns, or hands the remaining ownership to the endpoint.
///
/// The released path keeps the real diagnostic (auth failure or bounded stderr tail) in the returned
/// error; the unconfirmed path returns a [`PendingStartup`] that the endpoint adopts, so no SSH child,
/// transport or stderr task is ever dropped with a bool or a text record.
async fn startup_failure(
    alias: &str,
    generation: u64,
    child: Box<dyn ChildWrapper>,
    client: Option<RemoteClient>,
    error: RemoteClientError,
) -> ConnectFailure {
    let mut child = child;
    let stderr = child.stderr().take();
    let cleanup = PendingStartup::new(
        alias.to_owned(),
        generation,
        "bootstrap",
        client,
        child,
        stderr,
    );
    let release = cleanup.release().await;
    if release.released {
        // No resource is owned any more. The bounded stderr tail keeps the authentication detail, and
        // otherwise the first real cause is preserved with its notes.
        if let Some(tail) = &release.stderr_tail
            && ssh::is_ssh_auth_failure(tail)
        {
            return ConnectFailure::clean(RemoteClientError::AuthenticationFailed(
                ssh::auth_failure(tail),
            ));
        }
        let error = match release.failure.clone() {
            Some(cause) => {
                RemoteClientError::aggregate(error.to_string(), Some(cause), &release.diagnostics)
            }
            None => {
                RemoteClientError::aggregate(error.to_string(), Some(error), &release.diagnostics)
            }
        };
        return ConnectFailure::clean(error);
    }
    // Still owned: keep the real cause and the notes in the startup so the retry (and the endpoint's
    // final result) still carry them.
    ConnectFailure::Pending {
        error: RemoteClientError::aggregate(
            error.to_string(),
            Some(release.failure.clone().unwrap_or_else(|| error.clone())),
            &release.diagnostics,
        ),
        cleanup: Box::new(cleanup),
    }
}

/// Retains one bounded note without duplicating or growing the history.
///
/// This is the single bounded entry every layer uses, so no diagnostic can bypass the entry/char
/// limits with a formatted tail.
pub(in crate::remote) fn push_diagnostic(
    diagnostics: &mut Vec<String>,
    message: impl Into<String>,
) {
    let message: String = message.into().chars().take(MAX_DIAGNOSTIC_CHARS).collect();
    if diagnostics.len() >= MAX_TEARDOWN_DIAGNOSTICS
        || diagnostics.iter().any(|known| known == &message)
    {
        return;
    }
    diagnostics.push(message);
}

/// Reads the SSH stderr stream to EOF into a bounded tail shared with the owner.
fn spawn_stderr_drain(
    mut stderr: tokio::process::ChildStderr,
    alias: String,
    generation: u64,
) -> StderrDrain {
    let capture = Arc::new(SyncMutex::new(StderrCapture::new()));
    let shared = capture.clone();
    let task = tokio::spawn(async move {
        use tokio::io::AsyncReadExt;

        let mut buffer = [0_u8; 1024];
        loop {
            match stderr.read(&mut buffer).await {
                Ok(0) => break,
                Ok(count) => {
                    let mut capture = shared
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    capture.tail.extend_from_slice(&buffer[..count]);
                    if capture.tail.len() > STDERR_TAIL_BYTES {
                        let excess = capture.tail.len() - STDERR_TAIL_BYTES;
                        capture.tail.drain(..excess);
                    }
                }
                Err(error) => {
                    let mut capture = shared
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    capture.failure = Some(error);
                    break;
                }
            }
        }
        let read = {
            let capture = shared
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            capture.tail.len()
        };
        tracing::debug!(%alias, generation, bytes = read, "SSH stderr drain finished");
    });
    StderrDrain { task, capture }
}

/// Joins the stderr drain in place with a bounded deadline.
///
/// The handle is borrowed until the task is confirmed terminated: a timeout aborts and then joins it,
/// the shared bounded capture keeps whatever tail was already read, and only a confirmed end clears the
/// slot. A cancelled caller therefore releases a borrow and never detaches the drain.
pub(in crate::remote) async fn join_stderr_drain(
    drain: &mut Option<StderrDrain>,
    stage: &'static str,
) -> Result<Option<String>, StderrDrainError> {
    let Some(owned) = drain.as_mut() else {
        return Ok(None);
    };
    let result = match tokio::time::timeout(STDERR_DRAIN_DEADLINE, &mut owned.task).await {
        Ok(Ok(())) => finish_stderr_capture(&owned.capture, stage),
        Ok(Err(join_error)) => Err(StderrDrainError::Task {
            stage,
            source: std::sync::Arc::new(join_error),
        }),
        Err(_) => {
            // Abort and join in place before reporting: the caller keeps the owner in place, so a
            // cancelled caller can never detach this task.
            owned.task.abort();
            let _ = (&mut owned.task).await;
            let tail = {
                let capture = owned
                    .capture
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let tail = String::from_utf8_lossy(&capture.tail).trim().to_string();
                (!tail.is_empty()).then_some(tail)
            };
            Err(StderrDrainError::Timeout {
                stage,
                deadline: STDERR_DRAIN_DEADLINE,
                tail,
            })
        }
    };
    // The task is confirmed terminated on every path, so the handle is released exactly here.
    *drain = None;
    result
}

fn finish_stderr_capture(
    capture: &Arc<SyncMutex<StderrCapture>>,
    stage: &'static str,
) -> Result<Option<String>, StderrDrainError> {
    let mut capture = capture
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(failure) = capture.failure.take() {
        return Err(StderrDrainError::Read {
            stage,
            source: std::sync::Arc::new(failure),
        });
    }
    let tail = String::from_utf8_lossy(&capture.tail).trim().to_string();
    Ok((!tail.is_empty()).then_some(tail))
}

/// Runs the acknowledged control heartbeat for one physical connection.
///
/// The returned task is owned by the connection and joined on close, so a cancelled close cannot
/// detach it. A heartbeat failure only asks the driver to end: it never starts a second teardown, so
/// the physical close keeps deciding when the connection is released.
fn spawn_heartbeat(
    client: RemoteClient,
    alias: &str,
    generation: u64,
    endpoint_generation: u64,
    closing: CancellationToken,
    token: CancellationToken,
) -> JoinHandle<()> {
    let alias = alias.to_owned();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(HEARTBEAT_INTERVAL);
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                biased;
                () = closing.cancelled() => return,
                () = token.cancelled() => return,
                () = client.wait_disconnected() => return,
                _ = interval.tick() => {}
            }
            let result = tokio::select! {
                biased;
                () = closing.cancelled() => return,
                () = token.cancelled() => return,
                result = client.heartbeat() => result,
            };
            if let Err(error) = result {
                tracing::warn!(
                    %alias,
                    endpoint_generation,
                    generation,
                    %error,
                    "SSH heartbeat failed; the connection owner ends the transport"
                );
                client.abort(format!("heartbeat failed: {error}"));
                return;
            }
        }
    })
}
