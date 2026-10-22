//! 逻辑 endpoint：一个服务器的物理连接集合、按需扩容、真实预留准入与收缩裁决。
//!
//! 逻辑工作区只由 endpoint 代次与 canonical 路径标识；每次操作在当前健康连接上取得真实子流
//! 预留与同一连接的 workspace 句柄，物理 id 与进程 id 都不跨连接使用。没有可用容量时建立新的
//! SSH/helper 连接（合并需求、串行创建），扩展连接在操作、进程与 workspace 释放责任全部结束后
//! 才关闭并回收。
//!
//! 准入（唯一策略）：
//! 1. 需求是类型化事实：[`Demand::Operation`] 只需要一条该业务类别的普通流；
//!    [`Demand::WorkspaceAndOperation`] 需要同一连接上的操作流 + `openWorkspace` 事务。
//! 2. 所有真实预留都在 endpoint 状态临界区内取得：同一把锁里检查 `sealed`、每个连接的
//!    [`PhysicalConnection::is_available`]、该业务类别的 FD 预算以及真实子流余量。双流需求要么
//!    两条都拿到（或命中该连接的 workspace 句柄、只需一条），要么一条也不留——单条余量绝不会被
//!    当成双流需求已满足，流有余量但 FD 不足的连接同样不算可服务。
//! 3. 没有连接能满足需求时合并出一次建连尝试并等待它，然后回到第 2 步重新判定。等待从不发生在
//!    已满连接上，也不使用定时轮询；池成员变更通知只用于收缩观察。
//! 4. 退休（Retiring）与封闸（sealed）同样在这把锁内迁移，因此不会有预留越过 `close` 的封闸，
//!    也不会有预留落在已退休的连接上。
//!
//! 责任（owner 任务）：
//! - 建连 + 安装/拒绝清理由一个 endpoint owner 任务持有：调用方取消只撤销自己的等待，owner 继续
//!   完成发布或回收，绝不会因为 future 被 drop 而丢掉一个已启动的 SSH 进程。
//! - endpoint 用一个 supervisor 持有一个 [`JoinSet`]，持续 join 已完成的 owner 并移除其句柄；
//!   无法确认回收的失败按有界历史归档，供 `close` 报告。`close` 先封闸再取消收缩观察，然后真正
//!   等待 supervisor 把在途 owner 全部 drain，最后回收仍被持有的连接。
//!
//! 逻辑 backend 捕获创建时的 endpoint 实例与代次；每个操作都携带该绑定，准入与返回前都会复核，
//! 旧代次的 backend 不会静默使用当前连接。

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex as SyncMutex, OnceLock, Weak};
use std::time::Duration;

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_protocol::remote::{RemoteHello, RemoteResourceClass};
use tokio::sync::{Mutex, Notify, mpsc};
use tokio::task::{JoinHandle, JoinSet};
use tokio_util::sync::CancellationToken;

use crate::environment::ExecutionEnvironment;

use super::super::client::{StreamLease, WorkspaceLease};
use super::super::error::RemoteClientError;
use super::physical::{
    ConnectFailure, PendingStartup, PhysicalConnection, PhysicalState, Reclaim, push_diagnostic,
};

/// Creates one additional physical connection for this endpoint.
pub(in crate::remote) type GrowFuture =
    BoxFuture<'static, Result<PhysicalConnection, ConnectFailure>>;
pub(in crate::remote) type GrowFn = Arc<dyn Fn() -> GrowFuture + Send + Sync>;

/// Bound on archived diagnostics for owners that ended without a recoverable responsibility.
const MAX_UNRESOLVED: usize = 8;
/// Retry cadence for a failed startup that still owns resources.
const STARTUP_RETRY: Duration = Duration::from_millis(200);
/// One caller's wait budget for `close`. The real cleanup is never completed or dropped by it.
const CLOSE_WAIT_BUDGET: Duration = Duration::from_secs(30);

/// The logical binding a backend was created for: endpoint instance and generation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::remote) struct BindingId {
    instance: u64,
    generation: u64,
}

/// One real admission demand of a logical operation.
///
/// The demand states how many real streams one connection must be able to give: a single operation,
/// or an operation plus the `openWorkspace` transaction that has to run beside it. Admission and the
/// growth decision re-probe exactly this, so a single free stream is never mistaken for a satisfied
/// dual demand.
enum Demand {
    /// One ordinary operation stream of this class is enough (browsing, standalone workspace open).
    Operation { class: RemoteResourceClass },
    /// The same connection must host an operation plus an `openWorkspace` transaction for this path.
    WorkspaceAndOperation {
        class: RemoteResourceClass,
        canonical_path: String,
    },
}

impl Demand {
    /// The descriptor class of the operation this demand is admitted for.
    fn class(&self) -> RemoteResourceClass {
        match self {
            Self::Operation { class } | Self::WorkspaceAndOperation { class, .. } => *class,
        }
    }
}

/// Keeps a not-yet-registered connection owned so a cancelled or panicking owner cannot drop it.
///
/// The guard hands the connection to the pool with [`Self::disarm`]; if the owner ends before that,
/// the resource set adopts the connection and the supervisor reclaims it.
struct PendingConnection {
    resources: Arc<ResourceSet>,
    connection: Option<Arc<PhysicalConnection>>,
}

impl PendingConnection {
    fn new(resources: Arc<ResourceSet>, connection: PhysicalConnection) -> Self {
        Self {
            resources,
            connection: Some(Arc::new(connection)),
        }
    }

    fn connection(&self) -> &Arc<PhysicalConnection> {
        self.connection
            .as_ref()
            .expect("a pending connection stays owned until it is disarmed")
    }

    /// Hands the connection to the pool; the guard stops owning it.
    fn disarm(&mut self) {
        self.connection = None;
    }
}

impl Drop for PendingConnection {
    fn drop(&mut self) {
        if let Some(connection) = self.connection.take() {
            self.resources.adopt_connection(connection);
        }
    }
}

/// A connection that already holds every real reservation one demand needs.
struct Acquisition {
    connection: Arc<PhysicalConnection>,
    operation: StreamLease,
    /// Handle already open on this connection for the demanded path; held until the caller uses it.
    workspace: Option<Arc<WorkspaceLease>>,
    /// Second real reservation for the `openWorkspace` transaction when no handle exists yet.
    pending_open: Option<StreamLease>,
}

/// The outcome of one admission decision taken under the endpoint's state.
enum Admission {
    /// Real reservations are held for the caller; boxed so the enum stays small on the common
    /// no-admission paths.
    Admitted(Box<Acquisition>),
    /// The endpoint is sealed; nothing may be admitted any more.
    Sealed,
    /// No owned connection can serve this demand right now.
    Unavailable,
}

/// Result of one in-flight connector/install attempt, shared by every coalesced waiter.
type Attempt = Shared<BoxFuture<'static, Result<(), RemoteClientError>>>;

/// One endpoint owner task. It returns `()`: anything it still owns is adopted by a resource set, so
/// only a task panic or an abnormal join can leave an unresolved responsibility.
type OwnerFuture = BoxFuture<'static, ()>;

/// What one install decided inside the endpoint's single publication critical section.
enum InstallOutcome {
    Published,
    /// The endpoint was already sealed; the connection must be retired and reclaimed.
    Sealed,
    /// The connection reports a different execution environment than this serving pool.
    EnvironmentMismatch(RemoteClientError),
}

/// What one reclaim pass or close could not confirm, with the first real typed cause.
///
/// Notes are bounded observation (SSH stderr tails, stages); they never turn a released resource into
/// a failure. The first cause is kept once, so repeated passes never nest contexts.
#[derive(Default)]
struct ReclaimFailures {
    notes: Vec<String>,
    first: Option<RemoteClientError>,
}

impl ReclaimFailures {
    fn push(&mut self, note: impl Into<String>, cause: Option<RemoteClientError>) {
        push_diagnostic(&mut self.notes, note);
        if let Some(cause) = cause {
            self.first.get_or_insert(cause);
        }
    }

    fn extend(&mut self, other: Self) {
        for note in other.notes {
            push_diagnostic(&mut self.notes, note);
        }
        if let Some(cause) = other.first {
            self.first.get_or_insert(cause);
        }
    }

    fn is_empty(&self) -> bool {
        self.notes.is_empty() && self.first.is_none()
    }
}

/// Physical resources that must be reclaimed even after the endpoint's last reference is gone.
///
/// The supervisor owns this set alongside `Endpoint`, so an accepted connector attempt can keep its
/// real ownership when no pool is reachable any more; it is not a second manager, only the resource
/// state the endpoint's own tasks share.
struct ResourceSet {
    startups: SyncMutex<Vec<Arc<PendingStartup>>>,
    connections: SyncMutex<Vec<Arc<PhysicalConnection>>>,
}

impl ResourceSet {
    fn new() -> Self {
        Self {
            startups: SyncMutex::new(Vec::new()),
            connections: SyncMutex::new(Vec::new()),
        }
    }

    fn adopt_startup(&self, cleanup: PendingStartup) -> Arc<PendingStartup> {
        let cleanup = Arc::new(cleanup);
        self.startups
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(cleanup.clone());
        cleanup
    }

    fn forget_startup(&self, cleanup: &Arc<PendingStartup>) {
        self.startups
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .retain(|registered| !Arc::ptr_eq(registered, cleanup));
    }

    fn adopt_connection(&self, connection: Arc<PhysicalConnection>) {
        self.connections
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(connection);
    }

    fn connections(&self) -> Vec<Arc<PhysicalConnection>> {
        self.connections
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn forget_connection(&self, connection: &Arc<PhysicalConnection>) {
        self.connections
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .retain(|registered| !Arc::ptr_eq(registered, connection));
    }

    fn is_empty(&self) -> bool {
        self.startups
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_empty()
            && self
                .connections
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_empty()
    }

    /// Retries every adopted startup in parallel; only a confirmed release removes it.
    async fn reclaim_startups(&self, stage: &'static str) -> ReclaimFailures {
        let pending = self
            .startups
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let outcomes =
            futures::future::join_all(pending.iter().map(|cleanup| cleanup.release())).await;
        let mut failures = ReclaimFailures::default();
        for (cleanup, release) in pending.iter().zip(outcomes) {
            if release.released {
                self.forget_startup(cleanup);
            }
            // A released startup is only worth reporting when it ended abnormally; notes alone are
            // observation, never a failure.
            match (&release.failure, release.released) {
                (Some(failure), _) => failures.push(
                    format!("{stage}: startup generation {}", cleanup.generation()),
                    Some(failure.clone()),
                ),
                (None, false) => failures.push(
                    format!(
                        "{stage}: startup generation {}: cleanup did not confirm",
                        cleanup.generation()
                    ),
                    None,
                ),
                (None, true) => {}
            }
        }
        failures
    }

    /// Releases adopted connections that no pool can install any more.
    ///
    /// The adopted list is only a snapshot: a connection is forgotten after its confirmed release, so a
    /// cancelled wait never leaves the registry empty while a local clone is the only owner.
    async fn reclaim_connections(&self, stage: &'static str) -> ReclaimFailures {
        let adopted = self.connections();
        let outcomes =
            futures::future::join_all(adopted.iter().map(|connection| connection.close(stage)))
                .await;
        let mut failures = ReclaimFailures::default();
        for (connection, outcome) in adopted.iter().zip(outcomes) {
            match outcome {
                Reclaim::Released { outcome } => {
                    self.forget_connection(connection);
                    if let Err(error) = outcome {
                        // Released, but the close reported a real abnormal end: never hidden.
                        failures.push(
                            format!("{stage}: connection {}", connection.generation),
                            Some(error),
                        );
                    }
                }
                Reclaim::Pending { error } => failures.push(
                    format!("{stage}: connection {}", connection.generation),
                    Some(error),
                ),
            }
        }
        failures
    }
}

struct PoolState {
    /// Every owned connection, including retiring and failed ones; the baseline is kept first.
    connections: Vec<Arc<PhysicalConnection>>,
    baseline: Option<Arc<PhysicalConnection>>,
    hello: Option<RemoteHello>,
    environment: Option<ExecutionEnvironment>,
    sealed: bool,
    /// The in-flight connector/install attempt, coalescing concurrent demand into one handshake.
    attempt: Option<Attempt>,
}

/// A logical endpoint generation with its elastic physical connection pool.
pub(in crate::remote) struct Endpoint {
    instance: u64,
    alias: String,
    generation: Arc<AtomicU64>,
    state: Mutex<PoolState>,
    /// Serializes connection creation so concurrent demand cannot start a handshake storm.
    growth: Mutex<()>,
    capacity: Notify,
    health: Notify,
    /// Weak self-reference for the connection watchers, so no watcher extends the endpoint.
    self_ref: Weak<Endpoint>,
    grow: GrowFn,
    closing: CancellationToken,
    monitored: AtomicBool,
    /// Inbox of endpoint owner tasks; the supervisor below owns and joins them.
    owners_tx: mpsc::UnboundedSender<OwnerFuture>,
    /// Set once the endpoint is sealed: from then on no owner can be registered, so the supervisor may
    /// finish after draining instead of waiting for a sender that will never be dropped.
    owners_closed: Arc<AtomicBool>,
    /// The one supervisor task that continuously joins finished owners.
    supervisor: SyncMutex<Option<JoinHandle<()>>>,
    /// The supervisor's shared join: the future owns the handle, so a cancelled close never detaches it
    /// and the terminal result is observed exactly once.
    supervisor_join: OnceLock<Shared<BoxFuture<'static, Result<(), RemoteClientError>>>>,
    /// Physical resources shared with the supervisor so they are reclaimed even without a pool.
    resources: Arc<ResourceSet>,
    /// Bounded diagnostics for owners that ended without a recoverable responsibility.
    unresolved: SyncMutex<Vec<RemoteClientError>>,
}

impl Drop for Endpoint {
    fn drop(&mut self) {
        // The last pool reference is gone: cancel so loss/retire watchers stop waiting for a signal
        // nobody will send, which lets the supervisor drain and reclaim what it still owns.
        self.closing.cancel();
    }
}

impl std::fmt::Debug for Endpoint {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Endpoint")
            .field("alias", &self.alias)
            .field("instance", &self.instance)
            .field("generation", &self.generation.load(Ordering::Acquire))
            .finish_non_exhaustive()
    }
}

impl Endpoint {
    pub(in crate::remote) fn new(
        instance: u64,
        alias: String,
        generation: Arc<AtomicU64>,
        grow: GrowFn,
        closing: CancellationToken,
    ) -> Arc<Self> {
        let (owners_tx, owners_rx) = mpsc::unbounded_channel();
        let resources = Arc::new(ResourceSet::new());
        let supervisor_resources = Arc::clone(&resources);
        let owners_closed = Arc::new(AtomicBool::new(false));
        let supervisor_closed = Arc::clone(&owners_closed);
        let supervisor_closing = closing.clone();
        Arc::new_cyclic(|self_ref| {
            let endpoint = Self {
                instance,
                alias,
                generation,
                state: Mutex::new(PoolState {
                    connections: Vec::new(),
                    baseline: None,
                    hello: None,
                    environment: None,
                    sealed: false,
                    attempt: None,
                }),
                growth: Mutex::new(()),
                capacity: Notify::new(),
                health: Notify::new(),
                self_ref: self_ref.clone(),
                grow,
                closing,
                monitored: AtomicBool::new(false),
                owners_tx,
                owners_closed,
                supervisor: SyncMutex::new(None),
                supervisor_join: OnceLock::new(),
                resources,
                unresolved: SyncMutex::new(Vec::new()),
            };
            // Started eagerly so registering an owner never needs the supervisor lock, which `close`
            // holds while it joins it.
            let supervisor = tokio::spawn(run_supervisor(
                self_ref.clone(),
                supervisor_resources,
                supervisor_closed,
                owners_rx,
                supervisor_closing,
            ));
            *endpoint
                .supervisor
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(supervisor);
            endpoint
        })
    }

    /// Stable identity of this logical binding generation.
    pub(in crate::remote) fn identity(&self) -> String {
        format!("{}-{}", self.instance, self.generation())
    }

    /// The binding every backend of this endpoint must carry into its operations.
    pub(in crate::remote) fn binding(&self) -> BindingId {
        BindingId {
            instance: self.instance,
            generation: self.generation(),
        }
    }

    pub(in crate::remote) fn generation(&self) -> u64 {
        self.generation.load(Ordering::Acquire)
    }

    /// Rejects an operation created for a different endpoint instance or generation.
    fn verify_binding(&self, binding: BindingId) -> Result<(), RemoteClientError> {
        if binding.instance == self.instance && binding.generation == self.generation() {
            return Ok(());
        }
        tracing::debug!(
            alias = %self.alias,
            expected_instance = binding.instance,
            expected_generation = binding.generation,
            current_instance = self.instance,
            current_generation = self.generation(),
            "rejecting an operation from a stale remote binding"
        );
        // A stale binding is the remote-session-changed failure; the host must be re-opened for the
        // new generation instead of silently running on current connections.
        Err(RemoteClientError::Disconnected)
    }

    /// The helper handshake facts of the endpoint's first connection.
    pub(in crate::remote) async fn hello_identity(&self) -> Option<(String, String)> {
        self.state
            .lock()
            .await
            .hello
            .as_ref()
            .map(|hello| (hello.helper_version.clone(), hello.architecture.clone()))
    }

    /// The verified execution environment shared by every connection of this endpoint.
    pub(in crate::remote) async fn execution_environment(
        &self,
    ) -> Result<ExecutionEnvironment, RemoteClientError> {
        self.state
            .lock()
            .await
            .environment
            .clone()
            .ok_or(RemoteClientError::Disconnected)
    }

    /// Whether at least one connection can serve a new operation.
    pub(in crate::remote) async fn has_healthy(&self) -> bool {
        let state = self.state.lock().await;
        state
            .connections
            .iter()
            .any(|connection| connection.is_available())
    }

    /// Completes when the endpoint has no healthy connection left.
    pub(in crate::remote) async fn wait_unhealthy(&self) {
        loop {
            let notified = self.health.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if !self.has_healthy().await {
                return;
            }
            notified.await;
        }
    }

    /// Claims the single reconnect monitor of this endpoint.
    pub(in crate::remote) fn claim_monitor(&self) -> bool {
        self.monitored
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
    }

    /// Ensures a healthy connection exists.
    ///
    /// Sealing and health are read under the same state, so a sealed endpoint never reports ready and
    /// a healthy pool never starts a connector.
    ///
    /// # Errors
    /// Reports a sealed endpoint or a connection bootstrap failure.
    pub(in crate::remote) async fn ensure_ready(&self) -> Result<(), RemoteClientError> {
        loop {
            {
                let state = self.state.lock().await;
                if state.sealed {
                    return Err(RemoteClientError::ManagerClosing);
                }
                if state
                    .connections
                    .iter()
                    .any(|connection| connection.is_available())
                {
                    return Ok(());
                }
            }
            self.ensure_connection().await?;
        }
    }

    /// Resolves the canonical POSIX root of one logical workspace for `binding`.
    ///
    /// The temporary physical handle taken for this validation is released before returning, so an
    /// idle logical backend never keeps a physical workspace handle or an extra connection alive.
    ///
    /// # Errors
    /// Reports a stale binding, admission, transport, path and typed helper errors.
    pub(in crate::remote) async fn open_workspace(
        &self,
        path: String,
        binding: BindingId,
    ) -> Result<String, RemoteClientError> {
        loop {
            self.verify_binding(binding)?;
            if let Some(workspace) = self.cached_workspace(&path).await? {
                self.verify_binding(binding)?;
                return Ok(workspace.path().to_owned());
            }
            let acquisition = self
                .reserve_acquisition(&Demand::Operation {
                    class: RemoteResourceClass::OpenWorkspace,
                })
                .await?;
            let opened = acquisition
                .connection
                .client
                .open_workspace_owned(acquisition.operation, path.clone());
            match opened.await {
                Ok(Ok(opened)) => {
                    let workspace = WorkspaceLease::bind(
                        acquisition.connection.client.clone(),
                        opened,
                        self.alias.clone(),
                        acquisition.connection.cache().clone(),
                    );
                    self.verify_binding(binding)?;
                    return Ok(workspace.path().to_owned());
                }
                Ok(Err(error)) if error.is_disconnect() => continue,
                Ok(Err(error)) => return Err(error),
                // The tracked owner ended without deciding: no handle and no charge may be assumed.
                Err(_) => {
                    return Err(RemoteClientError::protocol(
                        "workspace open owner ended without a decision",
                    ));
                }
            }
        }
    }

    /// Admits one operation on a healthy connection with a workspace handle of that same connection.
    ///
    /// # Errors
    /// Reports a stale binding, a sealed endpoint, a bootstrap failure, or a path/typed helper error.
    pub(in crate::remote) async fn acquire(
        &self,
        path: &str,
        binding: BindingId,
        class: RemoteResourceClass,
    ) -> Result<StreamLease, RemoteClientError> {
        let demand = Demand::WorkspaceAndOperation {
            class,
            canonical_path: path.to_owned(),
        };
        loop {
            self.verify_binding(binding)?;
            let acquisition = self.reserve_acquisition(&demand).await?;
            let Acquisition {
                connection,
                operation,
                workspace,
                pending_open,
            } = acquisition;
            let workspace = match workspace {
                Some(workspace) => workspace,
                None => {
                    let Some(open) = pending_open else {
                        // Neither a handle nor the reservation that opens one: re-select with a fresh
                        // acquisition instead of reusing a half-built one.
                        continue;
                    };
                    let opened = connection
                        .client
                        .open_workspace_owned(open, path.to_owned());
                    match opened.await {
                        Ok(Ok(opened)) => WorkspaceLease::bind(
                            connection.client.clone(),
                            opened,
                            self.alias.clone(),
                            connection.cache().clone(),
                        ),
                        Ok(Err(error)) if error.is_disconnect() => continue,
                        Ok(Err(error)) => return Err(error),
                        Err(_) => {
                            return Err(RemoteClientError::protocol(
                                "workspace open owner ended without a decision",
                            ));
                        }
                    }
                }
            };
            self.verify_binding(binding)?;
            return Ok(operation.with_workspace(workspace));
        }
    }

    /// Admits one operation that needs no workspace handle (directory browsing).
    ///
    /// # Errors
    /// Reports a sealed endpoint or a bootstrap failure.
    pub(in crate::remote) async fn acquire_any(
        &self,
        class: RemoteResourceClass,
    ) -> Result<StreamLease, RemoteClientError> {
        let acquisition = self
            .reserve_acquisition(&Demand::Operation { class })
            .await?;
        Ok(acquisition.operation)
    }

    /// Reclaims connections whose cleanup was never confirmed, best effort.
    ///
    /// # Errors
    /// Aggregates the connections whose cleanup still did not confirm.
    pub(in crate::remote) async fn reap_failed(&self) -> Result<(), RemoteClientError> {
        let stale = {
            let state = self.state.lock().await;
            state
                .connections
                .iter()
                .filter(|connection| {
                    matches!(
                        connection.state(),
                        PhysicalState::Failed | PhysicalState::Closed
                    )
                })
                .cloned()
                .collect::<Vec<_>>()
        };
        // Reclaimed in parallel: one slow teardown must not multiply the wait for the others.
        let outcomes = futures::future::join_all(
            stale
                .iter()
                .map(|connection| self.teardown(connection, "failed connection")),
        )
        .await;
        let mut failures = Vec::new();
        for (connection, outcome) in stale.iter().zip(outcomes) {
            if let Err(error) = outcome {
                failures.push(format!("connection {}: {error}", connection.generation));
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(RemoteClientError::protocol(format!(
                "failed SSH connections were not reclaimed: {}",
                failures.join("; ")
            )))
        }
    }

    /// Seals admission, drains every endpoint owner task, and reclaims all owned connections.
    ///
    /// A connection whose cleanup does not confirm stays in the registry.
    ///
    /// # Errors
    /// Aggregates unresolved owner failures, the supervisor's own failure and the connections whose
    /// teardown did not confirm.
    pub(in crate::remote) async fn close(
        &self,
        stage: &'static str,
    ) -> Result<(), RemoteClientError> {
        // One wait budget for this caller, from the very start: it also covers waiting for the growth
        // and pool-state locks. The real cleanup is never completed, discarded or cached as terminal by
        // it, and a timed-out close neither rolls back the seal nor loses an owner.
        let reclaim = async {
            {
                // One serialized window: after the seal no reservation, retirement, connector or
                // watcher registration can start, so the supervisor drain below joins every owner.
                let _growth = self.growth.lock().await;
                let mut state = self.state.lock().await;
                state.sealed = true;
                state.baseline = None;
                drop(state);
                // Only after the seal may the existing owners observe the close and stop. No owner can
                // be registered from here on, so the supervisor may finish once it has drained.
                self.owners_closed.store(true, Ordering::Release);
                self.closing.cancel();
            }
            let mut failures = ReclaimFailures::default();
            // The shared join owns the supervisor handle: a cancelled wait never detaches it.
            if let Err(supervisor_failure) = self.supervisor_join().await {
                failures.push("endpoint supervisor", Some(supervisor_failure));
            }
            let connections = self.snapshot().await;
            let outcomes = futures::future::join_all(
                connections
                    .iter()
                    .map(|connection| self.teardown(connection, stage)),
            )
            .await;
            for (connection, outcome) in connections.iter().zip(outcomes) {
                if let Err(error) = outcome {
                    failures.push(format!("connection {}", connection.generation), Some(error));
                }
            }
            // Any failed startup or adopted connection that still owns resources stays owned here, so
            // a second close can never report a success it did not confirm.
            failures.extend(self.resources.reclaim_startups(stage).await);
            failures.extend(self.resources.reclaim_connections(stage).await);
            let unresolved = std::mem::take(
                &mut *self
                    .unresolved
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner),
            );
            for error in unresolved {
                failures.push("owner diagnostic", Some(error));
            }
            failures
        };
        let failures = match tokio::time::timeout(CLOSE_WAIT_BUDGET, reclaim).await {
            Ok(failures) => failures,
            Err(_) => {
                let mut failures = ReclaimFailures::default();
                failures.push(
                    format!(
                        "SSH endpoint close did not observe its owners within {CLOSE_WAIT_BUDGET:?}; resources stay owned for the next close"
                    ),
                    None,
                );
                failures
            }
        };
        if failures.is_empty() {
            Ok(())
        } else {
            // One meaningful context around the first real cause, with bounded notes attached. A
            // repeated close never nests these contexts because each aggregate starts from the
            // current pass's first cause.
            Err(RemoteClientError::aggregate(
                format!("SSH endpoint cleanup ({stage}) did not confirm"),
                failures.first,
                &failures.notes,
            ))
        }
    }

    /// Admits `demand` under the pool's one serialized state, creating capacity when none exists.
    async fn reserve_acquisition(&self, demand: &Demand) -> Result<Acquisition, RemoteClientError> {
        loop {
            match self.admit(demand).await? {
                Admission::Admitted(acquisition) => return Ok(*acquisition),
                Admission::Sealed => return Err(RemoteClientError::ManagerClosing),
                // No owned connection can serve this demand: coalesce one connector and re-decide.
                Admission::Unavailable => self.ensure_connection().await?,
            }
        }
    }

    /// Takes every real reservation `demand` needs, inside the endpoint's state linearization.
    ///
    /// Sealing, each connection's physical state, the descriptor budget of the demand's class and the
    /// real stream permits are read and claimed under the same lock, so no admission can pass a `close`
    /// seal and none can land on a connection that is being retired.
    async fn admit(&self, demand: &Demand) -> Result<Admission, RemoteClientError> {
        let state = self.state.lock().await;
        if state.sealed {
            return Ok(Admission::Sealed);
        }
        for connection in &state.connections {
            if !connection.is_available() {
                continue;
            }
            if let Some(acquisition) = Self::try_reserve(connection, demand)? {
                return Ok(Admission::Admitted(Box::new(acquisition)));
            }
        }
        Ok(Admission::Unavailable)
    }

    /// Takes every real reservation `demand` needs on one connection, or nothing at all.
    ///
    /// Nothing is returned when the connection cannot give all of them, so a partially filled
    /// connection is released instead of being mistaken for an admission.
    fn try_reserve(
        connection: &Arc<PhysicalConnection>,
        demand: &Demand,
    ) -> Result<Option<Acquisition>, RemoteClientError> {
        // Descriptor admission runs first, then the physical stream; a stream that is not available
        // drops the descriptor lease with this scope instead of holding half of a demand.
        let operation = match connection.client.try_lease(demand.class()) {
            Ok(Some(lease)) => lease,
            Ok(None) => return Ok(None),
            Err(error) if error.is_disconnect() => return Ok(None),
            Err(error) => return Err(error),
        };
        match demand {
            Demand::Operation { .. } => Ok(Some(Acquisition {
                connection: connection.clone(),
                operation,
                workspace: None,
                pending_open: None,
            })),
            Demand::WorkspaceAndOperation { canonical_path, .. } => {
                if let Some(workspace) = connection
                    .client
                    .cached_workspace(connection.cache(), canonical_path)
                {
                    // The handle is already open here, so one stream is enough; the handle itself is
                    // held by this acquisition until the caller starts the operation.
                    return Ok(Some(Acquisition {
                        connection: connection.clone(),
                        operation,
                        workspace: Some(workspace),
                        pending_open: None,
                    }));
                }
                match connection
                    .client
                    .try_lease(RemoteResourceClass::OpenWorkspace)
                {
                    Ok(Some(open)) => Ok(Some(Acquisition {
                        connection: connection.clone(),
                        operation,
                        workspace: None,
                        pending_open: Some(open),
                    })),
                    // A single free stream — or a helper without a free workspace descriptor — can
                    // never complete a workspace acquisition.
                    Ok(None) => Ok(None),
                    Err(error) if error.is_disconnect() => Ok(None),
                    Err(error) => Err(error),
                }
            }
        }
    }

    /// Registers and starts one connector attempt, coalescing with an attempt already in flight.
    async fn ensure_connection(&self) -> Result<(), RemoteClientError> {
        let attempt = {
            let _growth = self.growth.lock().await;
            let mut state = self.state.lock().await;
            if state.sealed {
                return Err(RemoteClientError::ManagerClosing);
            }
            match state.attempt.clone() {
                Some(attempt) => attempt,
                None => {
                    let attempt = self.start_attempt();
                    state.attempt = Some(attempt.clone());
                    attempt
                }
            }
        };
        attempt.await
    }

    /// Registers one connector/install attempt and starts the task that owns it.
    fn start_attempt(&self) -> Attempt {
        let endpoint = self.self_ref.clone();
        let attempt_endpoint = self.self_ref.clone();
        let resources = Arc::clone(&self.resources);
        let grow = self.grow.clone();
        let attempt: Attempt = async move {
            let result = run_connector(endpoint, resources, grow).await;
            // Publish the end of this attempt before the shared result completes, so the next demand
            // starts a real connector instead of coalescing onto a finished one.
            if let Some(endpoint) = attempt_endpoint.upgrade() {
                endpoint.state.lock().await.attempt = None;
            }
            result
        }
        .boxed()
        .shared();
        // The supervisor polls the same shared attempt, so its work and any adopted ownership complete
        // even when no caller ever waits for it. This owner is also the only place that observes an
        // attempt to its end, so an unexpected failure stays observable after its caller stopped
        // waiting instead of being dropped with the shared result.
        let supervised = attempt.clone();
        // Plain identity values only: this owner never holds the endpoint, so no reference cycle can
        // extend it, and the record never invents a missing attribution.
        let instance = self.instance;
        let alias = self.alias.clone();
        let generation = self.generation.load(Ordering::Acquire);
        self.spawn_owner(
            async move {
                if let Err(error) = supervised.await {
                    record_attempt_end(instance, &alias, generation, &error);
                }
            }
            .boxed(),
        );
        attempt
    }

    /// Hands one owner task to the endpoint supervisor.
    ///
    /// Registration happens under the publication lock and never takes the supervisor lock, so sealing
    /// the endpoint and enqueueing an owner are one linearized fact.
    fn spawn_owner(&self, future: OwnerFuture) {
        if let Err(unsent) = self.owners_tx.send(future) {
            // The supervisor already finished (it only does so after the endpoint closed and drained).
            // The owner future itself owns its cleanup, so it is handed to a real task instead of being
            // dropped with the failed send, and the abnormal shutdown stays a diagnostic.
            self.record_unresolved(RemoteClientError::protocol(
                "endpoint supervisor had already finished; the owner task runs on its own",
            ));
            tokio::spawn(unsent.0);
        }
    }

    /// The endpoint's one supervisor join, shared by every close caller.
    fn supervisor_join(&self) -> Shared<BoxFuture<'static, Result<(), RemoteClientError>>> {
        self.supervisor_join
            .get_or_init(|| {
                let handle = self
                    .supervisor
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .take();
                async move {
                    match handle {
                        // A panicking supervisor may have dropped a started connection, so its join
                        // failure is kept as a close failure instead of being flattened away.
                        Some(handle) => handle
                            .await
                            .map_err(|error| RemoteClientError::task("endpoint supervisor", error)),
                        None => Ok(()),
                    }
                }
                .boxed()
                .shared()
            })
            .clone()
    }

    /// Adopts the still-owned resources of one failed startup and keeps retrying their release.
    fn adopt_startup_cleanup(&self, cleanup: PendingStartup) {
        let cleanup = self.resources.adopt_startup(cleanup);
        let resources = Arc::clone(&self.resources);
        let endpoint = self.self_ref.clone();
        let closing = self.closing.clone();
        let retrier = async move {
            loop {
                // The resource set owns it, so this retry works even if the endpoint disappears.
                let release = cleanup.release().await;
                if release.released {
                    resources.forget_startup(&cleanup);
                    // A released startup that still ended abnormally is archived instead of being
                    // forgotten, so a later close can still report its typed cause.
                    if let Some(failure) = release.failure
                        && let Some(endpoint) = endpoint.upgrade()
                    {
                        endpoint.record_unresolved(failure);
                    }
                    return;
                }
                if closing.is_cancelled() {
                    // `close` retries the set itself and reports anything still owned.
                    return;
                }
                tokio::time::sleep(STARTUP_RETRY).await;
            }
        };
        self.spawn_owner(retrier.boxed());
    }

    /// Archives one cleanup obligation that no owner could resolve.
    fn record_unresolved(&self, error: RemoteClientError) {
        tracing::warn!(
            alias = %self.alias,
            %error,
            "endpoint owner left an unresolved cleanup responsibility"
        );
        let mut unresolved = self
            .unresolved
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if unresolved.len() >= MAX_UNRESOLVED {
            unresolved.remove(0);
        }
        unresolved.push(error);
    }

    async fn snapshot(&self) -> Vec<Arc<PhysicalConnection>> {
        self.state.lock().await.connections.clone()
    }

    /// Looks up an already open workspace handle under the endpoint state.
    async fn cached_workspace(
        &self,
        path: &str,
    ) -> Result<Option<Arc<WorkspaceLease>>, RemoteClientError> {
        let state = self.state.lock().await;
        if state.sealed {
            return Err(RemoteClientError::ManagerClosing);
        }
        for connection in &state.connections {
            if !connection.is_available() {
                continue;
            }
            if let Some(lease) = connection.client.cached_workspace(connection.cache(), path) {
                return Ok(Some(lease));
            }
        }
        Ok(None)
    }

    async fn is_registered(&self, connection: &Arc<PhysicalConnection>) -> bool {
        self.state
            .lock()
            .await
            .connections
            .iter()
            .any(|registered| Arc::ptr_eq(registered, connection))
    }

    async fn is_sealed(&self) -> bool {
        self.state.lock().await.sealed
    }

    /// Installs one new connection.
    ///
    /// Health, the hello verdict, the logical generation, publication and the registration of this
    /// connection's watchers are decided inside one critical section, and every admission-relevant
    /// connection state transition is published under that same state. A rejected or sealed connection
    /// joins the registry as `Failed` *before* its cleanup starts, so a failed cleanup keeps its owner.
    async fn install(&self, connection: &Arc<PhysicalConnection>) -> Result<(), RemoteClientError> {
        let outcome = {
            let mut state = self.state.lock().await;
            if state.sealed {
                connection.mark_failed();
                state.connections.push(connection.clone());
                InstallOutcome::Sealed
            } else {
                // `had_healthy` is part of the publication decision: the last healthy connection dying
                // must not let a recovery keep the previous generation.
                let had_healthy = state
                    .connections
                    .iter()
                    .any(|registered| registered.is_available());
                let existing = state.hello.clone();
                // A first connection or a full-pool recovery adopts the environment it found; only an
                // additional connection joining a serving pool must match exactly.
                let adopt = existing.is_none() || !had_healthy;
                if !adopt
                    && existing
                        .as_ref()
                        .is_some_and(|existing| hello_mismatch(existing, &connection.hello))
                {
                    connection.mark_failed();
                    state.connections.push(connection.clone());
                    InstallOutcome::EnvironmentMismatch(RemoteClientError::protocol(format!(
                        "helper connection {} of '{}' reported a different execution environment ({}, {}, {}) than this endpoint already uses",
                        connection.generation,
                        self.alias,
                        connection.hello.os,
                        connection.hello.architecture,
                        connection.hello.shell.path
                    )))
                } else {
                    if adopt {
                        state.hello = Some(connection.hello.clone());
                    }
                    if !had_healthy {
                        // Only a first connection or a real recovery advances the logical generation,
                        // so backends bound to the previous generation are rejected instead of being
                        // silently served by the new pool.
                        self.generation.fetch_add(1, Ordering::AcqRel);
                    }
                    let baseline = state
                        .baseline
                        .as_ref()
                        .is_none_or(|baseline| !baseline.is_available());
                    if baseline {
                        state.baseline = Some(connection.clone());
                        state.environment = Some(connection.environment.clone());
                        state.connections.insert(0, connection.clone());
                    } else {
                        state.connections.push(connection.clone());
                    }
                    // Watchers are registered in this same critical section: after `close` sealed the
                    // endpoint no watcher can be added any more, so draining the supervisor is a real
                    // join of every registered owner.
                    self.spawn_loss_watcher(connection.clone());
                    if !baseline {
                        self.spawn_retire_watcher(connection.clone());
                    }
                    self.health.notify_waiters();
                    self.record_pool_change();
                    InstallOutcome::Published
                }
            }
        };
        match outcome {
            InstallOutcome::Published => Ok(()),
            InstallOutcome::Sealed => {
                self.reject_unpublished(
                    connection,
                    "sealed endpoint",
                    RemoteClientError::ManagerClosing,
                )
                .await
            }
            InstallOutcome::EnvironmentMismatch(rejection) => {
                self.reject_unpublished(connection, "rejected connection", rejection)
                    .await
            }
        }
    }

    /// Closes a connection that was never published.
    ///
    /// A retained connection is owned by the registry, so this attempt itself settled either way.
    async fn reject_unpublished(
        &self,
        connection: &Arc<PhysicalConnection>,
        stage: &'static str,
        rejection: RemoteClientError,
    ) -> Result<(), RemoteClientError> {
        match self.teardown(connection, stage).await {
            Ok(()) => Err(rejection),
            Err(cleanup_error) => Err(RemoteClientError::protocol(format!(
                "{rejection}; rejected connection cleanup was not confirmed: {cleanup_error}"
            ))),
        }
    }

    /// Runs one connection's local teardown and publishes its serialized terminal state.
    ///
    /// A released connection is forgotten by the pool even when its close reports a real driver
    /// failure; an unconfirmed release keeps its owner for a later retry.
    async fn teardown(
        &self,
        connection: &Arc<PhysicalConnection>,
        stage: &'static str,
    ) -> Result<(), RemoteClientError> {
        match connection.close(stage).await {
            Reclaim::Released { outcome } => {
                {
                    let mut state = self.state.lock().await;
                    connection.mark_closed();
                    state.connections.retain(|registered| {
                        !registered.client.is_same_connection(&connection.client)
                    });
                    if state.baseline.as_ref().is_some_and(|baseline| {
                        baseline.client.is_same_connection(&connection.client)
                    }) {
                        state.baseline = None;
                    }
                }
                self.health.notify_waiters();
                self.record_pool_change();
                outcome
            }
            Reclaim::Pending { error } => {
                {
                    // Held only to publish the failed transition where admission reads the pool.
                    let _state = self.state.lock().await;
                    connection.mark_failed();
                }
                self.health.notify_waiters();
                self.record_pool_change();
                Err(error)
            }
        }
    }

    /// Publishes one pool membership change to shrink watchers.
    ///
    /// Shrink waits are the only consumers: admission never waits on this notification, so a released
    /// permit or a cancelled demand can never stall a caller behind a saturated connection.
    fn record_pool_change(&self) {
        self.capacity.notify_waiters();
    }

    /// Watches one published connection's real end.
    ///
    /// The watcher ends with the endpoint, so its owner can be joined instead of waiting for a signal
    /// a torn-down pool no longer produces.
    fn spawn_loss_watcher(&self, connection: Arc<PhysicalConnection>) {
        let endpoint = self.self_ref.clone();
        let closing = self.closing.clone();
        let watcher = async move {
            tokio::select! {
                biased;
                () = closing.cancelled() => return,
                () = connection.client.wait_disconnected() => {}
            }
            if let Some(endpoint) = endpoint.upgrade() {
                endpoint.handle_loss(connection).await;
            }
        };
        self.spawn_owner(watcher.boxed());
    }

    async fn handle_loss(&self, connection: Arc<PhysicalConnection>) {
        {
            let mut state = self.state.lock().await;
            connection.mark_failed();
            if state
                .baseline
                .as_ref()
                .is_some_and(|baseline| baseline.client.is_same_connection(&connection.client))
            {
                state.baseline = None;
            }
        }
        if let Err(error) = self.teardown(&connection, "lost connection").await {
            tracing::warn!(
                alias = %self.alias,
                generation = connection.generation,
                %error,
                "lost SSH connection was not fully reclaimed"
            );
        }
    }

    /// Watches one non-baseline connection so it is reclaimed once its responsibilities end.
    ///
    /// Every wait also observes the endpoint close and the connection's own terminal state: a business
    /// consumer that never drops its handle must not pin this connection forever.
    fn spawn_retire_watcher(&self, connection: Arc<PhysicalConnection>) {
        let endpoint = self.self_ref.clone();
        let closing = self.closing.clone();
        let watcher = async move {
            loop {
                tokio::select! {
                    biased;
                    () = closing.cancelled() => return,
                    () = connection.client.wait_disconnected() => return,
                    () = connection.client.wait_idle() => {}
                }
                let Some(endpoint) = endpoint.upgrade() else {
                    return;
                };
                let notified = endpoint.capacity.notified();
                tokio::pin!(notified);
                notified.as_mut().enable();
                if endpoint.begin_retirement(&connection).await {
                    break;
                }
                if endpoint.is_sealed().await || !endpoint.is_registered(&connection).await {
                    // A sealed endpoint owns the remaining teardown of every connection.
                    return;
                }
                tokio::select! {
                    biased;
                    () = closing.cancelled() => return,
                    () = connection.client.wait_disconnected() => return,
                    () = notified => {}
                }
            }
            // Retirement is final for new admissions: wait for the remaining responsibilities.
            tokio::select! {
                biased;
                () = closing.cancelled() => return,
                () = connection.client.wait_disconnected() => return,
                () = connection.client.wait_idle() => {}
            }
            if let Some(endpoint) = endpoint.upgrade() {
                endpoint.finish_retirement(&connection).await;
            }
        };
        self.spawn_owner(watcher.boxed());
    }

    /// Moves one idle non-baseline connection into retirement under the pool's serialized state.
    async fn begin_retirement(&self, connection: &Arc<PhysicalConnection>) -> bool {
        let state = self.state.lock().await;
        if state.sealed {
            return false;
        }
        if state
            .baseline
            .as_ref()
            .is_some_and(|baseline| baseline.client.is_same_connection(&connection.client))
        {
            // The baseline stays warm for the next operation.
            return false;
        }
        let sibling_healthy = state
            .connections
            .iter()
            .any(|registered| !Arc::ptr_eq(registered, connection) && registered.is_available());
        if !sibling_healthy {
            // Keep the last healthy connection until a replacement appears.
            return false;
        }
        connection.begin_retirement()
    }

    async fn finish_retirement(&self, connection: &Arc<PhysicalConnection>) {
        if let Err(error) = self.teardown(connection, "retired connection").await {
            tracing::warn!(
                alias = %self.alias,
                generation = connection.generation,
                %error,
                "retired SSH connection was not fully reclaimed"
            );
        }
    }
}

/// Runs the endpoint's single supervisor: it owns every owner task and joins each one as it ends.
///
/// The supervisor never takes the pool's growth or state lock, so it cannot deadlock against the
/// admission path it is observing; unresolved cleanup obligations are archived on the endpoint.
async fn run_supervisor(
    endpoint: Weak<Endpoint>,
    resources: Arc<ResourceSet>,
    owners_closed: Arc<AtomicBool>,
    mut inbox: mpsc::UnboundedReceiver<OwnerFuture>,
    closing: CancellationToken,
) {
    let mut tasks: JoinSet<()> = JoinSet::new();
    loop {
        // Finish only when the endpoint sealed its owner list, nothing is in flight and the inbox is
        // empty; a dropped endpoint closes the inbox instead, which is the second exit path below.
        if closing.is_cancelled()
            && owners_closed.load(Ordering::Acquire)
            && tasks.is_empty()
            && inbox.is_empty()
        {
            break;
        }
        tokio::select! {
            biased;
            incoming = inbox.recv() => match incoming {
                Some(future) => {
                    tasks.spawn(future);
                }
                None => break,
            },
            joined = tasks.join_next(), if !tasks.is_empty() => {
                if let Some(joined) = joined {
                    record_owner(&endpoint, joined).await;
                }
            }
        }
    }
    // The endpoint owns these tasks: nothing may outlive it.
    while let Some(joined) = tasks.join_next().await {
        record_owner(&endpoint, joined).await;
    }
    // Anything adopted while no pool was reachable is still real physical ownership. Keep releasing it
    // here: this is a cleanup obligation, so the supervisor does not end while it still owns resources.
    loop {
        let mut failures = resources.reclaim_connections("abandoned endpoint").await;
        failures.extend(resources.reclaim_startups("abandoned endpoint").await);
        for note in &failures.notes {
            tracing::warn!(note, "endpoint resource is still owned");
        }
        if let Some(first) = &failures.first {
            tracing::warn!(%first, "endpoint resource cause");
        }
        if resources.is_empty() {
            return;
        }
        tokio::time::sleep(STARTUP_RETRY).await;
    }
}

/// Records one joined owner task; only real unresolved responsibilities are kept.
async fn record_owner(endpoint: &Weak<Endpoint>, joined: Result<(), tokio::task::JoinError>) {
    let Some(endpoint) = endpoint.upgrade() else {
        return;
    };
    // An owner that ended normally has already adopted whatever it still owns; only an abnormal end
    // can leave a responsibility that no resource set holds.
    if let Err(join_error) = joined {
        endpoint.record_unresolved(RemoteClientError::task("endpoint owner", join_error));
    }
}

/// Creates one connection and publishes or reclaims it, independent of any caller's lifetime.
///
/// The attempt owns the connection from the first cancellable await onwards: a cancelled waiter never
/// drops a started SSH process, and a sealed endpoint reclaims what this attempt created.
async fn run_connector(
    endpoint: Weak<Endpoint>,
    resources: Arc<ResourceSet>,
    grow: GrowFn,
) -> Result<(), RemoteClientError> {
    let connection = match grow().await {
        Ok(connection) => connection,
        // A startup failure that confirmed its release is the whole story. One that still owns an SSH
        // child, transport or stderr task hands that real ownership to the endpoint (or, without a
        // pool, to the supervisor's resource set), which keeps retrying the release.
        Err(ConnectFailure::Clean(error)) => return Err(error),
        Err(ConnectFailure::Pending { error, cleanup }) => {
            match endpoint.upgrade() {
                Some(endpoint) => endpoint.adopt_startup_cleanup(*cleanup),
                // No pool owns it any more: the supervisor's set keeps the real ownership, so the
                // cleanup continues after this task ends.
                None => {
                    resources.adopt_startup(*cleanup);
                }
            }
            return Err(error);
        }
    };
    // The guard owns the connection until the pool accepts it, so a cancelled or panicking owner can
    // never drop a started transport.
    let mut pending = PendingConnection::new(resources, connection);
    let Some(endpoint) = endpoint.upgrade() else {
        // No pool owns it any more: the guard adopts it into the resource set on drop and the
        // supervisor reclaims it after draining.
        return Err(RemoteClientError::ManagerClosing);
    };
    let result = endpoint.install(pending.connection()).await;
    // The pool owns it now, either published or retained as failed for a retry.
    pending.disarm();
    result
}

/// Bound on the single diagnostic one connector attempt may leave in the log.
const MAX_ATTEMPT_DIAGNOSTIC_CHARS: usize = 512;

/// Whether an attempt ended because admission was sealed or its wait was cancelled.
///
/// The decision follows the typed cause only: a `Context` is unwrapped along its source, so a real
/// cleanup failure wrapped by a closing attempt is never mistaken for a cancellation.
fn is_cancellation(error: &RemoteClientError) -> bool {
    let mut cause = error;
    loop {
        match cause {
            RemoteClientError::ManagerClosing | RemoteClientError::Cancelled => return true,
            RemoteClientError::Context { source, .. } => cause = source.as_ref(),
            _ => return false,
        }
    }
}

/// Records how one connector attempt ended, whether or not a caller still waits for it.
///
/// This owner observes every attempt to its end, so exactly one bounded record is written here and
/// nothing is accumulated: a later healthy shutdown never inherits an earlier attempt's failure. Only
/// an expected admission-seal or cancellation end is debug; every other typed cause stays a warning
/// whatever the endpoint's closing state is, with its own truncated detail.
fn record_attempt_end(instance: u64, alias: &str, generation: u64, error: &RemoteClientError) {
    if is_cancellation(error) {
        tracing::debug!(
            instance,
            alias,
            generation,
            "connector owner observed a cancelled attempt end"
        );
        return;
    }
    let detail: String = error
        .to_string()
        .chars()
        .take(MAX_ATTEMPT_DIAGNOSTIC_CHARS)
        .collect();
    tracing::warn!(
        instance,
        alias,
        generation,
        detail = %detail,
        "connector owner observed attempt failure"
    );
}

/// Whether a new connection would mix execution environments inside one endpoint pool.
///
/// The helper build and the capability set are part of the execution environment: one pool must never
/// mix builds or a partially capable helper into the same logical workspace. Capability order carries
/// no meaning, so it is compared as a set.
fn hello_mismatch(existing: &RemoteHello, incoming: &RemoteHello) -> bool {
    existing.protocol_version != incoming.protocol_version
        || existing.helper_version != incoming.helper_version
        || existing.os != incoming.os
        || existing.architecture != incoming.architecture
        || existing.shell.dialect != incoming.shell.dialect
        || existing.shell.path != incoming.shell.path
        || capability_set(existing) != capability_set(incoming)
}

/// Sorted, de-duplicated capability names of one hello.
fn capability_set(hello: &RemoteHello) -> Vec<String> {
    let mut capabilities = hello
        .capabilities
        .iter()
        .map(|capability| format!("{capability:?}"))
        .collect::<Vec<_>>();
    capabilities.sort_unstable();
    capabilities.dedup();
    capabilities
}
