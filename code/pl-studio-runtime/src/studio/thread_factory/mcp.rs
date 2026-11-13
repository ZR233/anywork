//! Per-Thread `McpRuntime` ownership, `ThreadMcpStateSnapshot` projection, and lifecycle management.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::Result;
use pl_protocol::{McpScope, ThreadMcpLifecycleKind, ThreadMcpServerState, ThreadMcpStateSnapshot};
use pl_tool::command::ExecutorCommandBackend;
use pl_tool::mcp::{
    McpAvailabilityKind, McpAvailabilitySnapshot, McpResetScope, McpRuntime, McpRuntimeHandle,
    McpTurnLease,
};
use pl_tool::remote::SshWorkspaceBinding;
use pl_tool::workspace::ToolWorkspace;
use tokio::sync::broadcast::error::RecvError;
use tokio_util::sync::CancellationToken;

use super::StudioThreadFactory;
use super::errors::resource_error;
use super::mcp_refresh_tool::{McpToolCatalogStatus, ThreadMcpRefreshReceipt};
use super::thread_tools::CatalogPreparation;
use super::tool_bindings::ThreadToolLifetime;
use crate::config::ResolvedThreadMcpServer;
use crate::config::mcp_resource::ResolvedThreadMcpSnapshot;
use crate::studio::{ProductEventBus, WorkspaceRecord};
use crate::thread_assembler::ThreadAssemblyError;

pub(super) struct ThreadMcpPreparation<'a> {
    pub thread_id: &'a str,
    pub lifetime: &'a Arc<ThreadToolLifetime>,
    pub project: &'a WorkspaceRecord,
    pub workspace: &'a ToolWorkspace,
    pub remote: Option<&'a SshWorkspaceBinding>,
    pub preparation: &'a CatalogPreparation,
    pub cancellation: &'a CancellationToken,
}

type McpCloseResult = Result<(), Arc<ThreadAssemblyError>>;
type McpCloseCompletion =
    futures::future::Shared<futures::future::BoxFuture<'static, McpCloseResult>>;

pub(crate) struct ThreadMcpOwner {
    pub(super) thread_id: String,
    pub(super) lifetime: Arc<ThreadToolLifetime>,
    pub(super) scope: McpScope,
    pub(super) workspace_root: PathBuf,
    remote_commands: Mutex<Option<Arc<ExecutorCommandBackend>>>,
    pub(super) runtime: McpRuntimeHandle,
    servers: Mutex<BTreeMap<String, ResolvedThreadMcpServer>>,
    settings_revision: Mutex<u64>,
    state: Mutex<ThreadMcpStateSnapshot>,
    pub(super) command_lock: Arc<tokio::sync::Mutex<()>>,
    watcher: Mutex<Option<tokio::task::JoinHandle<()>>>,
    preparation: Mutex<Option<McpCloseCompletion>>,
    projection_ready: AtomicBool,
    projection_revision: AtomicU64,
    reconcile_requested: tokio::sync::Notify,
    shutdown: Mutex<Option<McpCloseCompletion>>,
}

impl ThreadMcpOwner {
    pub(crate) fn cancel_producers(&self) {
        self.lifetime.cancel();
    }

    fn new(
        thread_id: String,
        lifetime: Arc<ThreadToolLifetime>,
        scope: McpScope,
        workspace_root: PathBuf,
        remote_commands: Option<Arc<ExecutorCommandBackend>>,
        runtime: McpRuntimeHandle,
        servers: BTreeMap<String, ResolvedThreadMcpServer>,
    ) -> Arc<Self> {
        let initial_state = ThreadMcpStateSnapshot {
            thread_id: thread_id.clone(),
            scope: scope.clone(),
            generation: 1,
            servers: servers
                .values()
                .map(|entry| server_state_from_availability(entry, None, None))
                .collect(),
        };
        Arc::new(Self {
            thread_id,
            lifetime,
            scope,
            workspace_root,
            remote_commands: Mutex::new(remote_commands),
            runtime,
            servers: Mutex::new(servers),
            settings_revision: Mutex::new(0),
            state: Mutex::new(initial_state),
            command_lock: Arc::new(tokio::sync::Mutex::new(())),
            watcher: Mutex::new(None),
            preparation: Mutex::new(None),
            projection_ready: AtomicBool::new(true),
            projection_revision: AtomicU64::new(0),
            reconcile_requested: tokio::sync::Notify::new(),
            shutdown: Mutex::new(None),
        })
    }

    fn start_watcher(self: &Arc<Self>, factory: StudioThreadFactory) {
        let mut updates = self.runtime.subscribe();
        let owner = Arc::downgrade(self);
        let handle = tokio::spawn(async move {
            loop {
                let Some(owner) = owner.upgrade() else {
                    break;
                };
                tokio::select! {
                    biased;
                    () = owner.lifetime.cancellation.cancelled() => break,
                    () = owner.reconcile_requested.notified() => {
                        let result = tokio::select! {
                            biased;
                            () = owner.lifetime.cancellation.cancelled() => break,
                            result = async {
                                let _command = owner.command_lock.lock().await;
                                factory.ensure_current_mcp_owner(&owner)?;
                                factory.reconcile_mcp_owner(&owner).await
                            } => result,
                        };
                        if result.is_err() {
                            // Configuration/transport details may contain secrets.
                            tracing::warn!(thread_id = %owner.thread_id, "failed to reconcile Thread MCP configuration");
                        }
                    },
                    update = updates.recv() => match update {
                        Ok(()) | Err(RecvError::Lagged(_)) => {
                            owner.update_snapshot(&factory.services.product_events, true).await;
                        },
                        Err(RecvError::Closed) => break,
                    },
                }
            }
        });
        *self
            .watcher
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(handle);
    }

    fn start_close(self: &Arc<Self>, events: &ProductEventBus) -> McpCloseCompletion {
        use futures::FutureExt;
        self.lifetime.cancel();
        {
            let mut slot = self
                .shutdown
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(current) = slot.as_ref()
                && !matches!(current.peek(), Some(Err(_)))
            {
                current.clone()
            } else {
                let owner = self.clone();
                let events = events.clone();
                let task = tokio::spawn(async move {
                    let _command = owner.command_lock.lock().await;
                    let watcher = owner
                        .watcher
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .take();
                    if let Some(watcher) = watcher {
                        watcher.abort();
                        if let Err(source) = watcher.await
                            && !source.is_cancelled()
                        {
                            return Err(Arc::new(ThreadAssemblyError::Resource {
                                operation: "join MCP watcher",
                                source: Box::new(source),
                            }));
                        }
                    }
                    owner.publish_shutting_down(&events);
                    // Shutdown is the worker's cancellation-and-join boundary. A reconcile
                    // waiter must not be joined first: it can still be awaiting that worker.
                    let stopped =
                        owner.runtime.shutdown().await.map_err(|source| {
                            Arc::new(resource_error("shutdown member MCP", source))
                        });
                    let prepared = owner.finish_preparation().await;
                    stopped?;
                    prepared?;
                    owner.publish_closed(&events);
                    Ok(())
                });
                let completion = async move {
                    task.await.unwrap_or_else(|source| {
                        Err(Arc::new(ThreadAssemblyError::Resource {
                            operation: "join member MCP shutdown",
                            source: Box::new(source),
                        }))
                    })
                }
                .boxed()
                .shared();
                *slot = Some(completion.clone());
                completion
            }
        }
    }

    async fn close(self: &Arc<Self>, events: &ProductEventBus) -> McpCloseResult {
        self.start_close(events).await
    }

    fn remote_commands(&self) -> Option<Arc<ExecutorCommandBackend>> {
        self.remote_commands
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn update_resolved(
        &self,
        servers: BTreeMap<String, ResolvedThreadMcpServer>,
        remote: Option<Arc<ExecutorCommandBackend>>,
    ) {
        *self
            .remote_commands
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = remote;
        self.set_servers(servers);
    }

    fn set_servers(&self, servers: BTreeMap<String, ResolvedThreadMcpServer>) {
        *self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = servers;
    }

    fn matches_servers(&self, servers: &BTreeMap<String, ResolvedThreadMcpServer>) -> bool {
        let _state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.projection_ready.load(Ordering::Acquire)
            && *self
                .servers
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                == *servers
    }

    fn pause_projection(&self) {
        let _state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.projection_ready.store(false, Ordering::Release);
        self.projection_revision.fetch_add(1, Ordering::AcqRel);
    }

    fn resume_projection(&self) {
        let _state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.projection_ready.store(true, Ordering::Release);
    }

    async fn finish_preparation(&self) -> McpCloseResult {
        let completion = self
            .preparation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        match completion {
            Some(completion) => completion.await,
            None => Ok(()),
        }
    }

    fn preparation_error(&self) -> Result<(), ThreadAssemblyError> {
        use futures::FutureExt;
        let slot = self
            .preparation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(Err(error)) = slot
            .as_ref()
            .and_then(|completion| completion.clone().now_or_never())
        {
            return Err(resource_error(
                "prepare background Thread MCP servers",
                error,
            ));
        }
        Ok(())
    }

    // Called under command_lock, after the previous producer reached its terminal result.
    // The task deliberately does not hold command_lock while the worker prepares a generation:
    // same-config input/step refreshes must keep using the already ready lease.
    fn start_preparation(
        self: &Arc<Self>,
        servers: BTreeMap<String, pl_tool::mcp::config::EffectiveMcpServerConfig>,
        authorization: Option<pl_core::tool::opaque::ToolAuthorization>,
        events: ProductEventBus,
    ) {
        use futures::FutureExt;
        let owner = self.clone();
        let task = tokio::spawn(async move {
            let result = if let Some(authorization) = &authorization {
                if !authorization.is_active() {
                    return Ok(());
                }
                owner
                    .runtime
                    .reconcile_authorized(servers, authorization.clone())
                    .await
            } else {
                owner.runtime.reconcile(servers).await
            };
            if owner.lifetime.cancellation.is_cancelled() {
                // The close owner awaits runtime.shutdown separately and checks its result.
                return Ok(());
            }
            match result {
                Ok(()) => {
                    owner.refresh_snapshot(&events).await;
                    Ok(())
                }
                Err(error) => {
                    if let Some(auth) = &authorization
                        && !auth.is_active()
                    {
                        return Ok(());
                    }
                    if error.to_string().contains("authorization was revoked") {
                        return Ok(());
                    }
                    // No endpoint, environment, credential, or unredacted connector error.
                    tracing::error!(thread_id = %owner.thread_id, "background Thread MCP preparation failed");
                    Err(Arc::new(resource_error(
                        "prepare background Thread MCP servers",
                        error,
                    )))
                }
            }
        });
        let completion = async move {
            task.await.unwrap_or_else(|source| {
                Err(Arc::new(resource_error(
                    "join background Thread MCP preparation",
                    source,
                )))
            })
        }
        .boxed()
        .shared();
        *self
            .preparation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(completion);
    }

    async fn prepare_required(
        self: &Arc<Self>,
        resolved: BTreeMap<String, ResolvedThreadMcpServer>,
        authorization: Option<pl_core::tool::opaque::ToolAuthorization>,
        remote: Option<Arc<ExecutorCommandBackend>>,
        events: &ProductEventBus,
        cancellation: &CancellationToken,
    ) -> Result<McpTurnLease, ThreadAssemblyError> {
        let _command = tokio::select! {
            biased;
            () = self.lifetime.cancellation.cancelled() => return Err(ThreadAssemblyError::Closed),
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Cancelled.into()),
            guard = self.command_lock.lock() => guard,
        };
        // A refresh may have queued behind the initial required gate. Recheck after acquiring
        // the lock so it cannot turn into a second waiter for the optional background batch.
        if self.matches_servers(&resolved) {
            self.preparation_error()?;
            return self
                .runtime
                .acquire_turn_lease()
                .await
                .map_err(|error| resource_error("acquire current Thread MCP lease", error));
        }
        self.pause_projection();
        // Existing worker APIs intentionally retain an accepted reconcile even if its waiter
        // disappears. Join that producer before publishing/reconciling a changed desired set.
        tokio::select! {
            biased;
            () = self.lifetime.cancellation.cancelled() => return Err(ThreadAssemblyError::Closed),
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Cancelled.into()),
            result = self.finish_preparation() => result.map_err(|error| resource_error("finish previous Thread MCP preparation", error))?,
        }
        self.update_resolved(resolved.clone(), remote);
        self.publish_connecting(None, events);
        let required: BTreeMap<_, _> = resolved
            .iter()
            .filter(|(_, entry)| entry.server.config.enabled && entry.server.config.required)
            .map(|(id, entry)| (id.clone(), entry.server.clone()))
            .collect();
        let prepared = tokio::select! {
            biased;
            () = self.lifetime.cancellation.cancelled() => return Err(ThreadAssemblyError::Closed),
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Cancelled.into()),
            result = async {
                if let Some(auth) = &authorization {
                    self.runtime.reconcile_authorized(required.clone(), auth.clone()).await
                } else {
                    self.runtime.reconcile(required.clone()).await
                }
            } => result,
        };
        prepared.map_err(|error| resource_error("prepare required Thread MCP servers", error))?;
        let availability = self.runtime.snapshots().await;
        self.resume_projection();
        self.refresh_snapshot(events).await;
        for id in required.keys() {
            if !availability
                .get(id)
                .is_some_and(|state| state.availability_kind == McpAvailabilityKind::Available)
            {
                self.pause_projection();
                return Err(resource_error(
                    "prepare required Thread MCP servers",
                    anyhow::anyhow!("required MCP server '{id}' is unavailable"),
                ));
            }
        }
        let lease = self
            .runtime
            .acquire_turn_lease()
            .await
            .map_err(|error| resource_error("acquire required Thread MCP lease", error))?;
        let effective = resolved
            .into_iter()
            .map(|(id, entry)| (id, entry.server))
            .collect();
        if effective != required {
            self.start_preparation(effective, authorization, events.clone());
        }
        Ok(lease)
    }

    fn mark_settings_revision(&self, revision: u64) {
        *self
            .settings_revision
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = revision;
    }

    fn request_settings_reconcile(&self, revision: u64) {
        if *self
            .settings_revision
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            != revision
        {
            self.reconcile_requested.notify_one();
        }
    }

    fn read_snapshot(&self) -> ThreadMcpStateSnapshot {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn publish_connecting(&self, server_id: Option<&str>, product_events: &ProductEventBus) {
        let servers = self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let previous = self.read_snapshot();
        let next_servers: Vec<ThreadMcpServerState> = servers
            .values()
            .map(|entry| {
                if server_id.is_some_and(|id| entry.id != id)
                    && let Some(previous) =
                        previous.servers.iter().find(|server| server.id == entry.id)
                {
                    return previous.clone();
                }
                let override_connecting = match server_id {
                    Some(id) => entry.id == id,
                    None => entry.server.config.enabled,
                };
                server_state_from_availability(
                    entry,
                    None,
                    override_connecting.then_some(ThreadMcpLifecycleKind::Connecting),
                )
            })
            .collect();
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.generation = guard.generation.saturating_add(1);
        guard.servers = next_servers;
        let snapshot = guard.clone();
        drop(guard);
        product_events.emit_thread_mcp_state(snapshot);
    }

    fn publish_shutting_down(&self, product_events: &ProductEventBus) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for server in &mut guard.servers {
            server.lifecycle = ThreadMcpLifecycleKind::ShuttingDown;
        }
        guard.generation = guard.generation.saturating_add(1);
        let snapshot = guard.clone();
        drop(guard);
        product_events.emit_thread_mcp_state(snapshot);
    }

    fn publish_closed(&self, product_events: &ProductEventBus) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.servers.clear();
        guard.generation = guard.generation.saturating_add(1);
        let snapshot = guard.clone();
        drop(guard);
        product_events.emit_thread_mcp_state(snapshot);
    }

    fn publish_reconnect_failure(&self, server_id: Option<&str>, product_events: &ProductEventBus) {
        let servers = self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.generation = guard.generation.saturating_add(1);
        guard.servers = servers
            .values()
            .map(|entry| {
                if server_id.is_some_and(|id| entry.id != id)
                    && let Some(previous) =
                        guard.servers.iter().find(|server| server.id == entry.id)
                {
                    return previous.clone();
                }
                server_state_from_availability(
                    entry,
                    None,
                    Some(ThreadMcpLifecycleKind::Unavailable),
                )
            })
            .collect();
        let snapshot = guard.clone();
        drop(guard);
        product_events.emit_thread_mcp_state(snapshot);
    }

    async fn refresh_snapshot(&self, product_events: &ProductEventBus) {
        self.update_snapshot(product_events, false).await;
    }

    async fn update_snapshot(&self, product_events: &ProductEventBus, runtime_changed: bool) {
        let revision = self.projection_revision.load(Ordering::Acquire);
        if !self.projection_ready.load(Ordering::Acquire)
            || self.lifetime.cancellation.is_cancelled()
        {
            return;
        }
        let availabilities = self.runtime.snapshots().await;
        let servers = self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let next_servers: Vec<ThreadMcpServerState> = servers
            .values()
            .map(|entry| {
                let availability = availabilities.get(&entry.id);
                server_state_from_availability(entry, availability, None)
            })
            .collect();
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if revision != self.projection_revision.load(Ordering::Acquire)
            || !self.projection_ready.load(Ordering::Acquire)
            || self.lifetime.cancellation.is_cancelled()
        {
            return;
        }
        // A definition/schema change can keep both tool count and availability unchanged.
        // Still wake the original hot-catalog installer for a published runtime update.
        if runtime_changed || guard.servers != next_servers {
            guard.generation = guard.generation.saturating_add(1);
            guard.servers = next_servers;
            let snapshot = guard.clone();
            drop(guard);
            // ProductEventBus only enqueues broadcasts. Serialize that enqueue with
            // pause_projection, not just the snapshot mutation.
            let revision = self.projection_revision.load(Ordering::Acquire);
            if revision == self.projection_revision.load(Ordering::Acquire)
                && self.projection_ready.load(Ordering::Acquire)
                && !self.lifetime.cancellation.is_cancelled()
            {
                product_events.emit_thread_mcp_state(snapshot);
            }
        }
    }
}

fn server_state_from_availability(
    entry: &ResolvedThreadMcpServer,
    availability: Option<&McpAvailabilitySnapshot>,
    override_lifecycle: Option<ThreadMcpLifecycleKind>,
) -> ThreadMcpServerState {
    let lifecycle = override_lifecycle.unwrap_or(match availability {
        Some(snapshot) => match snapshot.availability_kind {
            McpAvailabilityKind::Checking => ThreadMcpLifecycleKind::Connecting,
            McpAvailabilityKind::Available => ThreadMcpLifecycleKind::Available,
            McpAvailabilityKind::Unavailable
            | McpAvailabilityKind::Disabled
            | McpAvailabilityKind::MissingCredential => ThreadMcpLifecycleKind::Unavailable,
        },
        None if !entry.server.config.enabled
            || entry.server.status_kind
                == pl_tool::mcp::config::McpServerStatusKind::MissingCredential =>
        {
            ThreadMcpLifecycleKind::Unavailable
        }
        None => ThreadMcpLifecycleKind::Connecting,
    });
    ThreadMcpServerState {
        id: entry.id.clone(),
        effective_source: entry.effective_source,
        execution_location: entry.execution_location.clone(),
        transport: entry.server.config.transport.as_str().to_owned(),
        endpoint_summary: entry.server.config.endpoint_summary(),
        built_in: entry.built_in,
        lifecycle,
        tool_count: availability.and_then(|snapshot| snapshot.tool_count),
        message: availability.and_then(|snapshot| snapshot.availability_message.clone()),
        last_checked_at: availability.and_then(|snapshot| snapshot.last_checked_at),
    }
}

impl StudioThreadFactory {
    pub(super) async fn prepare_thread_mcp(
        &self,
        request: ThreadMcpPreparation<'_>,
    ) -> Result<McpTurnLease, ThreadAssemblyError> {
        let ThreadMcpPreparation {
            thread_id,
            lifetime,
            project,
            workspace,
            remote,
            preparation,
            cancellation,
        } = request;
        let settings_revision = self
            .services
            .config_runtime
            .read()
            .map_err(|error| resource_error("read MCP settings revision", error))?
            .revision;
        let scope = match &project.ssh_alias {
            Some(alias) => McpScope::Ssh {
                ssh_alias: alias.clone(),
            },
            None => McpScope::Host,
        };
        let remote_commands = remote.map(|host| Arc::new(host.commands().clone()));
        let resolved = self
            .services
            .config_runtime
            .resolve_thread_mcp_snapshot(
                &scope,
                workspace.root(),
                self.services.store.paths().home(),
                remote_commands.clone(),
            )
            .map_err(|error| resource_error("resolve Thread MCP servers", error))?;
        match preparation {
            CatalogPreparation::Initial => {
                self.shutdown_thread_mcp(thread_id)
                    .await
                    .map_err(|error| resource_error("close previous member MCP", error))?;
                let runtime = McpRuntime::new(self.services.mcp_connector.clone());
                let owner = ThreadMcpOwner::new(
                    thread_id.to_owned(),
                    lifetime.clone(),
                    scope,
                    workspace.root().to_path_buf(),
                    remote_commands.clone(),
                    runtime.handle(),
                    resolved.servers.clone(),
                );
                owner.pause_projection();
                owner.mark_settings_revision(settings_revision);
                owner.start_watcher(self.clone());
                let initial_snapshot = owner.read_snapshot();
                *self
                    .resource_scope(thread_id)
                    .ok_or(ThreadAssemblyError::Closed)?
                    .mcp
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(owner.clone());
                self.services
                    .product_events
                    .emit_thread_mcp_state(initial_snapshot);

                match owner
                    .prepare_required(
                        resolved.servers,
                        Some(resolved.authorization.clone()),
                        remote_commands,
                        &self.services.product_events,
                        cancellation,
                    )
                    .await
                {
                    Ok(lease) => {
                        self.ensure_mcp_authorization(&owner, &resolved.authorization)
                            .map_err(|error| {
                                resource_error("check Thread MCP authorization", error)
                            })?;
                        Ok(lease)
                    }
                    Err(setup) => {
                        if let Err(cleanup) = self.shutdown_thread_mcp(thread_id).await {
                            return Err(ThreadAssemblyError::Cleanup {
                                id: thread_id.into(),
                                setup: Box::new(setup),
                                cleanup: Box::new(resource_error(
                                    "close failed member MCP",
                                    cleanup,
                                )),
                            });
                        }
                        Err(setup)
                    }
                }
            }
            CatalogPreparation::Refresh { .. } => {
                let existing = self.mcp_owner(thread_id);
                let owner = match existing {
                    Some(owner) => {
                        owner.request_settings_reconcile(settings_revision);
                        // Desired inputs are adopted under command_lock in prepare_required.
                        // Updating them here can make an in-flight reconnect mistake the
                        // old worker generation for the newly committed configuration.
                        owner
                    }
                    None => {
                        let runtime = McpRuntime::new(self.services.mcp_connector.clone());
                        let owner = ThreadMcpOwner::new(
                            thread_id.to_owned(),
                            lifetime.clone(),
                            scope,
                            workspace.root().to_path_buf(),
                            remote_commands.clone(),
                            runtime.handle(),
                            resolved.servers.clone(),
                        );
                        owner.pause_projection();
                        owner.mark_settings_revision(settings_revision);
                        owner.start_watcher(self.clone());
                        let initial_snapshot = owner.read_snapshot();
                        *self
                            .resource_scope(thread_id)
                            .ok_or(ThreadAssemblyError::Closed)?
                            .mcp
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner) =
                            Some(owner.clone());
                        self.services
                            .product_events
                            .emit_thread_mcp_state(initial_snapshot);
                        owner
                    }
                };
                if owner.lifetime.cancellation.is_cancelled() || cancellation.is_cancelled() {
                    return Err(pl_core::thread::ThreadError::Cancelled.into());
                }
                if owner.matches_servers(&resolved.servers) {
                    owner.preparation_error()?;
                    let lease = self
                        .acquire_mcp_owner_lease(&owner)
                        .await
                        .map_err(|error| {
                            resource_error("acquire refreshed Thread MCP lease", error)
                        })?;
                    tracing::debug!(target: "thread_preparation", thread_id,
                        stage = "mcp_current_lease", tools = lease.tools().len(), "completed");
                    return Ok(lease);
                }
                match owner
                    .prepare_required(
                        resolved.servers,
                        Some(resolved.authorization.clone()),
                        remote_commands,
                        &self.services.product_events,
                        cancellation,
                    )
                    .await
                {
                    Ok(lease) => {
                        self.ensure_mcp_authorization(&owner, &resolved.authorization)
                            .map_err(|error| {
                                resource_error("check Thread MCP authorization", error)
                            })?;
                        Ok(lease)
                    }
                    Err(error) => Err(error),
                }
            }
        }
    }

    pub(crate) async fn read_thread_mcp(&self, thread_id: &str) -> Result<ThreadMcpStateSnapshot> {
        if let Some(owner) = self.mcp_owner(thread_id) {
            return Ok(owner.read_snapshot());
        }
        let thread = self.thread_record(thread_id).await?;
        let project = self.project_record(&thread.workspace_id).await?;
        let scope = match project.ssh_alias {
            Some(ssh_alias) => McpScope::Ssh { ssh_alias },
            None => McpScope::Host,
        };
        Ok(ThreadMcpStateSnapshot {
            thread_id: thread_id.to_owned(),
            scope,
            generation: 0,
            servers: Vec::new(),
        })
    }

    pub async fn reconnect_thread_mcp(
        &self,
        thread_id: &str,
        server_id: Option<&str>,
    ) -> Result<ThreadMcpStateSnapshot> {
        let owner = self.mcp_owner(thread_id).ok_or_else(|| {
            pl_protocol::studio::StudioError::invalid_argument(format!(
                "Thread '{thread_id}' is not active"
            ))
        })?;
        let (_, _, state) = self
            .reconnect_mcp_for_owner(&owner, server_id, CancellationToken::new())
            .await?;
        Ok(state)
    }

    /// Both UI and model reconnect use this physical owner and the same command boundary.
    pub(super) async fn reconnect_mcp_for_owner(
        &self,
        owner: &Arc<ThreadMcpOwner>,
        server_id: Option<&str>,
        cancellation: CancellationToken,
    ) -> Result<(u64, u64, ThreadMcpStateSnapshot)> {
        tokio::select! {
            biased;
            () = cancellation.cancelled() => {
                // The worker still owns any command already accepted. Let the existing
                // owner reconcile its eventual result; never replay a tool invocation.
                owner.reconcile_requested.notify_one();
                anyhow::bail!("MCP reconnect was cancelled")
            },
            () = owner.lifetime.cancellation.cancelled() => anyhow::bail!("MCP owner is closing"),
            result = async {
                let _command = owner.command_lock.lock().await;
                self.ensure_current_mcp_owner(owner)?;
                // Reject before fencing projection, joining preparation, or sending a reset.
                let resolved = self.resolve_mcp_owner_snapshot(owner)?;
                if let Some(target_id) = server_id {
                    let target = resolved.servers.get(target_id).ok_or_else(|| {
                        pl_protocol::studio::StudioError::invalid_argument(format!(
                            "MCP server '{target_id}' is not enabled in Thread '{}'",
                            owner.thread_id
                        ))
                    })?;
                    anyhow::ensure!(
                        target.server.status_kind != pl_tool::mcp::config::McpServerStatusKind::MissingCredential,
                        "MCP server '{target_id}' is missing credentials"
                    );
                }
                self.ensure_mcp_authorization(owner, &resolved.authorization)?;
                let configuration_changed = !owner.matches_servers(&resolved.servers);
                owner.pause_projection();
                owner.finish_preparation().await
                    .map_err(|error| resource_error("finish MCP preparation before reconnect", error))?;
                self.ensure_mcp_authorization(owner, &resolved.authorization)?;
                owner.set_servers(resolved.servers.clone());
                owner.publish_connecting(server_id, &self.services.product_events);
                let effective_servers = resolved.servers
                    .iter()
                    .map(|(id, entry)| (id.clone(), entry.server.clone()))
                    .collect();
                let reset_scope = match server_id {
                    Some(id) => McpResetScope::Server { server_id: id.to_owned() },
                    None => McpResetScope::All,
                };
                let reset = owner.runtime.reset_authorized(
                    reset_scope, effective_servers, resolved.authorization.clone()
                ).await;
                self.ensure_mcp_authorization(owner, &resolved.authorization)?;
                if let Err(source) = reset {
                    // A failed candidate must never be presented as a successful new session,
                    // even if the old generation is retained by the runtime for cleanup.
                    owner.publish_reconnect_failure(server_id, &self.services.product_events);
                    if !configuration_changed {
                        // The worker already stopped target admission in the retained
                        // generation. This terminal projection lets later model steps keep
                        // its remaining tools without preparing optional servers again.
                        owner.resume_projection();
                    }
                    return Err(anyhow::Error::new(source)
                        .context("MCP reconnect failed; the target remains unavailable"));
                }
                owner.resume_projection();
                owner.update_snapshot(&self.services.product_events, true).await;
                let lease = self.acquire_mcp_owner_lease(owner).await?;
                self.ensure_mcp_authorization(owner, &resolved.authorization)?;
                Ok((resolved.catalog_revision, lease.generation().0, owner.read_snapshot()))
            } => result,
        }
    }

    pub(crate) async fn reconcile_open_threads_for_scopes(&self, scopes: &[McpScope]) {
        let include_all = scopes.iter().any(|scope| matches!(scope, McpScope::Host));
        let owners = self
            .resource_scopes()
            .iter()
            .filter_map(|scope| {
                scope
                    .mcp
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone()
            })
            .filter(|owner| include_all || scopes.contains(&owner.scope))
            .collect::<Vec<_>>();
        for owner in owners {
            // Coalesced, owner-managed work: saving configuration never waits on another
            // Thread's command lock, handshake or tools/list.
            owner.reconcile_requested.notify_one();
        }
    }

    fn ensure_current_mcp_owner(&self, owner: &Arc<ThreadMcpOwner>) -> Result<()> {
        anyhow::ensure!(
            !owner.lifetime.cancellation.is_cancelled()
                && self
                    .mcp_owner(&owner.thread_id)
                    .is_some_and(|current| Arc::ptr_eq(&current, owner)),
            "MCP owner is no longer active"
        );
        Ok(())
    }

    fn ensure_mcp_authorization(
        &self,
        owner: &Arc<ThreadMcpOwner>,
        authorization: &pl_core::tool::opaque::ToolAuthorization,
    ) -> Result<()> {
        self.ensure_current_mcp_owner(owner)?;
        if !authorization.is_active() {
            owner.reconcile_requested.notify_one();
            anyhow::bail!("MCP configuration changed; the refresh was superseded");
        }
        Ok(())
    }

    async fn acquire_mcp_owner_lease(&self, owner: &Arc<ThreadMcpOwner>) -> Result<McpTurnLease> {
        self.ensure_current_mcp_owner(owner)?;
        let lease = match owner.runtime.acquire_turn_lease().await {
            Ok(lease) => lease,
            Err(error) => {
                self.ensure_current_mcp_owner(owner)?;
                owner.reconcile_requested.notify_one();
                return Err(error.into());
            }
        };
        self.ensure_mcp_authorization(owner, &lease.authorization())?;
        Ok(lease)
    }

    fn resolve_mcp_owner_snapshot(
        &self,
        owner: &Arc<ThreadMcpOwner>,
    ) -> Result<ResolvedThreadMcpSnapshot> {
        self.services
            .config_runtime
            .resolve_thread_mcp_snapshot(
                &owner.scope,
                &owner.workspace_root,
                self.services.store.paths().home(),
                owner.remote_commands(),
            )
            .map_err(|_| anyhow::anyhow!("failed to resolve Thread MCP configuration"))
    }

    /// The caller holds command_lock and owns cancellation/closing selection.
    async fn apply_mcp_snapshot(
        &self,
        owner: &Arc<ThreadMcpOwner>,
        resolved: &ResolvedThreadMcpSnapshot,
        reset: Option<McpResetScope>,
    ) -> Result<()> {
        self.ensure_mcp_authorization(owner, &resolved.authorization)?;
        owner.pause_projection();
        tokio::select! {
            biased;
            () = owner.lifetime.cancellation.cancelled() => anyhow::bail!("member MCP is closing"),
            result = owner.finish_preparation() => result.map_err(|error| resource_error("finish previous Thread MCP preparation", error))?,
        }
        owner.set_servers(resolved.servers.clone());
        let effective = resolved
            .servers
            .iter()
            .map(|(id, entry)| (id.clone(), entry.server.clone()))
            .collect();
        let result = if let Some(reset) = reset {
            let target = match &reset {
                McpResetScope::Server { server_id } => Some(server_id.as_str()),
                McpResetScope::All => None,
            };
            owner.publish_connecting(target, &self.services.product_events);
            owner
                .runtime
                .reset_authorized(reset, effective, resolved.authorization.clone())
                .await
        } else {
            owner
                .runtime
                .reconcile_authorized(effective, resolved.authorization.clone())
                .await
        };
        // Check even when the lower layer rejected publication: supersession schedules the
        // existing owner, but never silently retries or turns an old result into success.
        self.ensure_mcp_authorization(owner, &resolved.authorization)?;
        result?;
        owner.resume_projection();
        owner.refresh_snapshot(&self.services.product_events).await;
        self.ensure_mcp_authorization(owner, &resolved.authorization)
    }

    /// The caller holds command_lock and owns cancellation/closing selection.
    async fn reconcile_mcp_owner(
        &self,
        owner: &Arc<ThreadMcpOwner>,
    ) -> Result<ResolvedThreadMcpSnapshot> {
        let settings_revision = self
            .services
            .config_runtime
            .read()
            .map_err(|_| anyhow::anyhow!("failed to read MCP settings revision"))?
            .revision;
        let resolved = self.resolve_mcp_owner_snapshot(owner)?;
        self.apply_mcp_snapshot(owner, &resolved, None).await?;
        owner.mark_settings_revision(settings_revision);
        Ok(resolved)
    }

    pub(super) async fn refresh_mcp_for_owner(
        &self,
        owner: &Arc<ThreadMcpOwner>,
        cancellation: CancellationToken,
    ) -> Result<ThreadMcpRefreshReceipt> {
        tokio::select! {
            biased;
            () = cancellation.cancelled() => anyhow::bail!("MCP refresh was cancelled"),
            () = owner.lifetime.cancellation.cancelled() => anyhow::bail!("MCP owner is closing"),
            result = async {
                let _command = owner.command_lock.lock().await;
                self.ensure_current_mcp_owner(owner)?;
                let (_, changed) = self.services.config_runtime
                    .reload_thread_mcp_catalog(&owner.scope)
                    .map_err(|_| anyhow::anyhow!("failed to reload Thread MCP configuration"))?;
                for snapshot in changed {
                    self.services.product_events.emit_mcp_catalog(snapshot);
                }
                let resolved = self.reconcile_mcp_owner(owner).await?;
                let discovery = owner.runtime.refresh_tools().await;
                self.ensure_mcp_authorization(owner, &resolved.authorization)?;
                let discovery = discovery?;
                // Even an unchanged discovery must actually schedule the promised catalog
                // observation. This is the product observation revision, not a new MCP
                // runtime generation, and targets only this owner.
                owner.update_snapshot(&self.services.product_events, true).await;
                self.ensure_mcp_authorization(owner, &resolved.authorization)?;
                // The runtime and state events wake the existing hot-catalog installer.
                // No claim is made about installation in the calling Turn's frozen catalog.
                Ok(ThreadMcpRefreshReceipt {
                    scope: owner.scope.clone(),
                    catalog_revision: resolved.catalog_revision,
                    discovery,
                    state: owner.read_snapshot(),
                    tool_catalog: McpToolCatalogStatus::RefreshScheduled,
                })
            } => result,
        }
    }

    pub(super) fn mcp_owner(&self, id: &str) -> Option<Arc<ThreadMcpOwner>> {
        self.resource_scope(id)?
            .mcp
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn request_member_mcp_shutdown(&self) {
        for scope in self.resource_scopes() {
            let owner = scope
                .mcp
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone();
            if let Some(owner) = owner {
                // The original owner retains the shared completion. Starting its owned task
                // early ensures synchronous caller progress while multiple members close.
                drop(owner.start_close(&self.services.product_events));
            }
        }
    }

    pub(crate) async fn shutdown_scope_mcp(
        &self,
        scope: &Arc<crate::session::NativeResources>,
    ) -> Result<()> {
        let owner = scope
            .mcp
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(owner) = owner {
            #[cfg(test)]
            if scope
                .s2_mcp_close_failure
                .lock()
                .unwrap()
                .as_ref()
                .is_some_and(|flag| flag.load(std::sync::atomic::Ordering::SeqCst))
            {
                return Err(std::io::Error::other("injected failed preparation MCP close").into());
            }
            owner
                .close(&self.services.product_events)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "close member MCP",
                    source: Box::new(source),
                })?;
            let mut slot = scope
                .mcp
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if slot
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(current, &owner))
            {
                slot.take();
            }
        }
        Ok(())
    }

    pub(crate) async fn shutdown_thread_mcp(&self, id: &str) -> Result<()> {
        if let Some(scope) = self.resource_scope(id) {
            self.shutdown_scope_mcp(&scope).await?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod refresh_tests {
    //! Narrow owner/lifecycle proofs complement the real model/Thread integration test.
    use super::*;
    use crate::session::NativeResources;
    use crate::studio::{StudioStore, storage_fault_test_support::close_factory};
    use std::time::Duration;

    fn owner(
        factory: &StudioThreadFactory,
        resources: &Arc<NativeResources>,
        id: &str,
        scope: McpScope,
        root: &std::path::Path,
    ) -> Result<Arc<ThreadMcpOwner>> {
        factory.bind_resource_scope(id, resources)?;
        let connector = factory.services.mcp_connector.clone();
        let runtime = McpRuntime::new(connector);
        let owner = ThreadMcpOwner::new(
            id.into(),
            Arc::new(ThreadToolLifetime::default()),
            scope,
            root.into(),
            None,
            runtime.handle(),
            BTreeMap::new(),
        );
        *resources.mcp.lock().unwrap() = Some(owner.clone());
        Ok(owner)
    }

    #[tokio::test]
    async fn refresh_rejects_replaced_owner_and_cancellation_releases_command_lock() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let fixture = close_factory(&store)?;
        let factory = &fixture.factory;
        let resources = Arc::new(NativeResources::default());
        let old = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
        let current = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
        assert!(
            factory
                .refresh_mcp_for_owner(&old, CancellationToken::new())
                .await
                .is_err()
        );
        assert!(current.runtime.snapshots().await.is_empty());

        let command = current.command_lock.lock().await;
        tokio::time::timeout(
            Duration::from_secs(2),
            factory.reconcile_open_threads_for_scopes(&[McpScope::Host]),
        )
        .await?;
        let cancellation = CancellationToken::new();
        let refresh = factory.refresh_mcp_for_owner(&current, cancellation.clone());
        tokio::pin!(refresh);
        assert!(futures::poll!(&mut refresh).is_pending());
        cancellation.cancel();
        assert!(
            tokio::time::timeout(Duration::from_secs(2), &mut refresh)
                .await?
                .is_err()
        );
        drop(command);

        fixture.config.create_mcp_document(&pl_protocol::CreateMcpDocumentRequest {
        scope: McpScope::Host,
        id: "slow".into(),
        raw_toml: "schema_version = 1\nid = 'slow'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = ['-c', 'import time; time.sleep(60)']\nstartup_timeout_secs = 30\n".into(),
    })?;
        // Refresh now owns the lock while its accepted runtime command is pending.
        // Closing must cancel it before trying to acquire that same lock.
        let refresh = factory.refresh_mcp_for_owner(&current, CancellationToken::new());
        tokio::pin!(refresh);
        assert!(futures::poll!(&mut refresh).is_pending());
        assert!(current.command_lock.try_lock().is_err());
        let closing = current.close(&fixture.events);
        tokio::pin!(closing);
        assert!(futures::poll!(&mut closing).is_pending());
        assert!(
            tokio::time::timeout(Duration::from_secs(2), &mut refresh)
                .await?
                .is_err()
        );
        tokio::time::timeout(Duration::from_secs(2), closing).await??;
        assert!(
            factory
                .refresh_mcp_for_owner(&current, CancellationToken::new())
                .await
                .is_err()
        );
        old.close(&fixture.events).await?;
        Ok(())
    }

    #[tokio::test]
    async fn ssh_refresh_reloads_host_inheritance_without_commanding_unrelated_owners() -> Result<()>
    {
        use crate::config::ConfigPaths;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let fixture = close_factory(&store)?;
        let factory = &fixture.factory;
        let ssh_scope = McpScope::Ssh {
            ssh_alias: "selected".into(),
        };
        let other_scope = McpScope::Ssh {
            ssh_alias: "other".into(),
        };
        let ssh_resources = Arc::new(NativeResources::default());
        let host_resources = Arc::new(NativeResources::default());
        let other_resources = Arc::new(NativeResources::default());
        let ssh = owner(
            factory,
            &ssh_resources,
            "ssh",
            ssh_scope.clone(),
            temp.path(),
        )?;
        let host = owner(
            factory,
            &host_resources,
            "host",
            McpScope::Host,
            temp.path(),
        )?;
        let other = owner(
            factory,
            &other_resources,
            "other",
            other_scope.clone(),
            temp.path(),
        )?;
        let before = fixture.config.mcp_catalog_snapshot(&ssh_scope)?;
        let other_before = fixture.config.mcp_catalog_snapshot(&other_scope)?;
        let host_state = host.read_snapshot();
        let other_state = other.read_snapshot();
        let paths = ConfigPaths::from_config_dir(store.paths().home().join("isolated-test-config"));
        std::fs::create_dir_all(paths.mcp_host_dir())?;
        let peer = temp.path().join("peer.py");
        std::fs::write(&peer, mcp_stdio::STDIO_MCP_SCRIPT)?;
        // Host-inherited servers execute on Host even for SSH owners. No invented SSH
        // transport is necessary to prove actual connection/discovery and scope isolation.
        std::fs::write(
            paths.mcp_host_dir().join("shared.toml"),
            format!(
                "schema_version = 1\nid = 'shared'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 5\n[env]\nMCP_NO_RESOURCES = '1'\n",
                serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?
            ),
        )?;
        let receipt = factory
            .refresh_mcp_for_owner(&ssh, CancellationToken::new())
            .await?;
        assert!(receipt.catalog_revision > before.revision);
        assert!(
            receipt
                .state
                .servers
                .iter()
                .any(|server| server.id == "shared"
                    && server.lifecycle == ThreadMcpLifecycleKind::Available
                    && server.tool_count == Some(1)),
            "actual state: {:?}",
            receipt.state
        );
        assert!(
            receipt
                .discovery
                .servers
                .iter()
                .any(|server| server.server_id == "shared"
                    && server.status == pl_tool::mcp::McpToolRefreshStatus::Unchanged)
        );
        let selected = fixture.config.mcp_catalog_snapshot(&ssh_scope)?;
        assert!(
            selected
                .entries
                .iter()
                .any(|entry| entry.id == "shared" && entry.inherited_from_host)
        );
        assert!(
            fixture
                .config
                .mcp_catalog_snapshot(&McpScope::Host)?
                .entries
                .iter()
                .any(|entry| entry.id == "shared")
        );
        // No all-scope reload, no Host runtime notification, no activation of another owner.
        assert_eq!(
            fixture.config.mcp_catalog_snapshot(&other_scope)?,
            other_before
        );
        assert_eq!(host.read_snapshot(), host_state);
        assert_eq!(other.read_snapshot(), other_state);

        let reconnected = factory.reconnect_thread_mcp("ssh", Some("shared")).await?;
        assert!(
            reconnected
                .servers
                .iter()
                .any(|server| server.id == "shared"
                    && server.lifecycle == ThreadMcpLifecycleKind::Available)
        );

        // Settings publications (including account/credential edits) are a different source:
        // unlike the scope-only tool refresh above, they must still schedule reconciliation.
        let settings = fixture.config.read()?;
        host.mark_settings_revision(settings.revision);
        let mut updates = host.runtime.subscribe();
        host.start_watcher(factory.clone());
        let settings = fixture
            .config
            .replace(settings.revision, settings.canonical_config().clone())?;
        host.request_settings_reconcile(settings.revision);
        tokio::time::timeout(Duration::from_secs(5), async {
            updates.recv().await?;
            let _command = host.command_lock.lock().await;
            anyhow::ensure!(
                host.read_snapshot()
                    .servers
                    .iter()
                    .any(|server| server.id == "shared"
                        && server.lifecycle == ThreadMcpLifecycleKind::Available)
            );
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        ssh.close(&fixture.events).await?;
        host.close(&fixture.events).await?;
        other.close(&fixture.events).await?;
        Ok(())
    }

    mod barrier_tests {
        //! Configuration-commit/discovery interleaving with an actual stdio peer and Thread.
        use super::{binding_host, mcp_stdio, owner};
        use crate::session::NativeResources;
        use crate::studio::{StudioStore, storage_fault_test_support::close_factory};
        use pl_agent_tool::Tool;
        use pl_core::{
            model::DynModelSession,
            thread::{ThreadError, ThreadHandle},
            tool::opaque::ToolError,
        };
        use pl_protocol::{
            CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpScope, UpdateMcpDocumentRequest,
        };
        use pl_tool::{
            binding::{ToolCallPolicy, prepare_registration},
            mcp::thread::ThreadMcpTool,
            media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
        };
        use std::{sync::Arc, time::Duration};
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio_util::sync::CancellationToken;

        #[derive(Debug)]
        struct NoMedia;
        impl ToolMediaHost for NoMedia {
            async fn retain(&self, _: ToolMedia) -> Result<RetainedToolMedia, ToolError> {
                Err(ToolError::new(std::io::Error::other(
                    "the barrier peer returns text only",
                )))
            }
        }

        #[tokio::test]
        async fn committed_delete_must_not_be_regranted_by_late_refresh() -> anyhow::Result<()> {
            revoked_refresh(false, false).await
        }

        #[tokio::test]
        async fn committed_disable_must_not_be_regranted_by_late_refresh() -> anyhow::Result<()> {
            revoked_refresh(true, false).await
        }

        #[tokio::test]
        async fn committed_delete_must_not_be_regranted_by_late_reconnect() -> anyhow::Result<()> {
            revoked_refresh(false, true).await
        }

        #[tokio::test]
        async fn committed_disable_must_not_be_regranted_by_late_reconnect() -> anyhow::Result<()> {
            revoked_refresh(true, true).await
        }

        async fn revoked_refresh(disable: bool, reconnect: bool) -> anyhow::Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let fixture = close_factory(&store)?;
            let factory = fixture.factory.clone();
            let resources = Arc::new(NativeResources::default());
            let owner = owner(&factory, &resources, "barrier", McpScope::Host, temp.path())?;
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
            let flag = temp.path().join("block-list");
            let log = temp.path().join("requests.jsonl");
            let peer = temp.path().join("peer.py");
            // Extend the shared peer only with a transport barrier, not with refresh semantics.
            let script = mcp_stdio::STDIO_MCP_SCRIPT
        .replace("import json, os, signal, sys, time", "import json, os, signal, socket, sys, time")
        .replace(
            "    elif method == \"tools/list\":",
            "    elif method == \"tools/list\":\n\
             \x20       late_discovery = os.path.exists(os.environ['MCP_LIST_FLAG'])\n\
             \x20       if late_discovery:\n\
             \x20           with socket.create_connection(('127.0.0.1', int(os.environ['MCP_LIST_PORT']))) as barrier:\n\
             \x20               barrier.sendall(b'1')\n\
             \x20               barrier.recv(1)",
        )
        .replace(
            "        schema = {\"type\": \"object\", \"properties\": {}}",
            "        schema = {\"type\": \"object\", \"properties\": {}}\n\
             \x20       schema['description'] = 'late candidate' if late_discovery else 'initial'",
        );
            std::fs::write(&peer, script)?;
            let raw = format!(
                "schema_version = 1\nid = 'barrier'\nkind = 'server'\nenabled = true\n\
         transport = 'stdio'\ncommand = 'python3'\nargs = {}\n\
         startup_timeout_secs = 10\n[env]\nMCP_NO_RESOURCES = '1'\n\
         MCP_LIST_PORT = '{}'\nMCP_LIST_FLAG = {}\nMCP_REQUEST_LOG = {}\n",
                serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?,
                listener.local_addr()?.port(),
                serde_json::to_string(&flag.display().to_string())?,
                serde_json::to_string(&log.display().to_string())?,
            );
            let mut running_refresh = None;
            let mut thread: Option<ThreadHandle> = None;
            let result = tokio::time::timeout(Duration::from_secs(30), async {
        let (created, _) = fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
            scope: McpScope::Host, id: "barrier".into(), raw_toml: raw.clone(),
        })?;
        {
            let _command = owner.command_lock.lock().await;
            factory.reconcile_mcp_owner(&owner).await?;
        }
        // Keep a legitimately captured original lease for the delayed-installation proof.
        let initial = owner.runtime.acquire_turn_lease().await?;
        anyhow::ensure!(initial.tools().len() == 1, "actual initial state: {:?}", owner.read_snapshot());
        let original_authorization = initial.authorization();
        anyhow::ensure!(original_authorization.is_active());
        owner.start_watcher(factory.clone());
        std::fs::write(&flag, "block explicit tools/list")?;
        running_refresh = Some({
            let factory = factory.clone();
            let owner = owner.clone();
            tokio::spawn(async move {
                if reconnect {
                    factory.reconnect_mcp_for_owner(&owner, Some("barrier"), CancellationToken::new())
                        .await.map(|(revision, _, _)| revision)
                } else {
                    factory.refresh_mcp_for_owner(&owner, CancellationToken::new())
                        .await.map(|receipt| receipt.catalog_revision)
                }
            })
        });
        let (mut barrier, _) = listener.accept().await?;
        let mut entered = [0];
        barrier.read_exact(&mut entered).await?;
        anyhow::ensure!(entered == [b'1']);
        let before_discovery = owner.runtime.health_snapshot().await?.generation;

        // Queue directory preparation before the configuration watcher, as in the original
        // counterexample. A revoked runtime must reject this acquisition, not return empty success.
        let preparation = async {
            let command = owner.command_lock.lock().await;
            let lease = owner.runtime.acquire_turn_lease().await;
            (command, lease)
        };
        tokio::pin!(preparation);
        anyhow::ensure!(futures::poll!(&mut preparation).is_pending(),
            "directory preparation did not queue behind the refresh");
        let document = created.document.clone().unwrap();
        let (committed, scopes) = if disable {
            fixture.config.update_mcp_document(&UpdateMcpDocumentRequest {
                document: document.clone(), expected_revision: created.revision,
                raw_toml: raw.replace("enabled = true", "enabled = false"),
            })?
        } else {
            fixture.config.delete_mcp_document(&DeleteMcpDocumentRequest {
                document: document.clone(), expected_revision: created.revision,
            })?
        };
        // Revocation is synchronous with the actual configuration commit, before notification.
        anyhow::ensure!(!original_authorization.is_active(), "commit did not revoke the captured lease");
        factory.reconcile_open_threads_for_scopes(&scopes).await;
        std::fs::remove_file(&flag)?;
        barrier.write_all(b"1").await?;
        drop(barrier);
        let refresh_result = running_refresh.as_mut().unwrap().await?;
        running_refresh.take();
        let (command, late_acquisition) = preparation.await;
        anyhow::ensure!(owner.runtime.health_snapshot().await?.generation == before_discovery,
            "revoked discovery published a new runtime generation");
        anyhow::ensure!(late_acquisition.is_err(), "a revoked current generation was exposed as a fresh lease");
        drop(command);
        let superseded = match refresh_result {
            Ok(revision) => anyhow::bail!("stale MCP command succeeded with catalogRevision={}, current={}",
                revision, committed.snapshot.revision),
            Err(error) => error,
        };
        anyhow::ensure!(superseded.to_string().contains("superseded"), "unexpected refresh refusal: {superseded}");

        // Observe corrective publication through runtime events; no sleep or timer-based polling.
        let mut updates = owner.runtime.subscribe();
        loop {
            if let Ok(lease) = owner.runtime.acquire_turn_lease().await
                && lease.authorization().is_active()
                && lease.tools().is_empty()
            {
                break;
            }
            updates.recv().await?;
        }
        let current = factory.refresh_mcp_for_owner(&owner, CancellationToken::new()).await?;
        anyhow::ensure!(current.catalog_revision == committed.snapshot.revision,
            "stable refresh did not report the new configuration revision");
        anyhow::ensure!(
            current.state.servers.iter().all(|server| server.id != "barrier")
                && current.discovery.servers.iter().all(|server| server.server_id != "barrier")
        );

        // Even after current empty publication, the original retained lease cannot be installed.
        // Use the real Thread registration boundary, not a direct equality comparison alone.
        let descriptor = initial.tools().first().unwrap().clone();
        let tool = ThreadMcpTool::new(initial, &descriptor.exposed_name, Arc::new(NoMedia))?;
        let prepared = prepare_registration(&descriptor.exposed_name, tool.definition(), ToolCallPolicy::DirectOnly)?;
        thread = Some(ThreadHandle::start(owner.thread_id.clone(), DynModelSession::new(binding_host::Calls {
            calls: [(descriptor.exposed_name.clone(), "{}".into())].into(), requests: Default::default(),
        }))?);
        let current_thread = thread.as_ref().unwrap();
        let registration = current_thread.register_tools_if_extensions(
            current_thread.snapshot().extension_sequence, vec![tool.registration(prepared)]).await;
        if registration.is_ok() {
            // If registration regresses, actually try the new invocation and retain the
            // peer-call assertion below; an authorization comparison alone is insufficient.
            current_thread.reveal_tools(vec![descriptor.exposed_name]).await?;
            let _outcome = current_thread.run_turn(binding_host::turn("late-call")).await;
        }
        anyhow::ensure!(matches!(registration, Err(ThreadError::ToolPermissionRevoked)),
            "late registration was not rejected for revoked authority: {registration:?}");

        // Re-enabling/deleting-and-recreating issues a valid new authority and remains usable.
        let (restored, scopes) = if disable {
            fixture.config.update_mcp_document(&UpdateMcpDocumentRequest {
                document, expected_revision: committed.revision, raw_toml: raw.clone(),
            })?
        } else {
            fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
                scope: McpScope::Host, id: "barrier".into(), raw_toml: raw.clone(),
            })?
        };
        factory.reconcile_open_threads_for_scopes(&scopes).await;
        let restored_receipt = factory.refresh_mcp_for_owner(&owner, CancellationToken::new()).await?;
        anyhow::ensure!(restored_receipt.catalog_revision == restored.snapshot.revision);
        let recovered = owner.runtime.acquire_turn_lease().await?;
        anyhow::ensure!(recovered.authorization().is_active() && recovered.tools().len() == 1);
        anyhow::ensure!(!original_authorization.is_active(), "restoration revived the old authority");
        eprintln!("barrier evidence: reconnect={reconnect}, disable={disable}, superseded=true, committedRevision={}, stableReceiptRevision={}, revokedLeaseRejected=true, lateRegistrationRejected=true, restoredRevision={}",
            committed.snapshot.revision, current.catalog_revision, restored_receipt.catalog_revision);
        Ok::<_, anyhow::Error>(())
    }).await.map_err(anyhow::Error::from).and_then(std::convert::identity);

            // Always join the refresh and close the Thread/runtime, including early refusal, timeout,
            // assertion failure and transport errors. Dropping the body also drops its barrier socket.
            owner.cancel_producers();
            let refresh_cleanup = if let Some(refresh) = running_refresh.take() {
                refresh.await.map(|_| ()).map_err(anyhow::Error::from)
            } else {
                Ok(())
            };
            let thread_cleanup = if let Some(thread) = thread {
                thread.close().await.map_err(anyhow::Error::from)
            } else {
                Ok(())
            };
            let owner_cleanup = owner
                .close(&fixture.events)
                .await
                .map_err(anyhow::Error::from);
            let calls = match std::fs::read_to_string(log) {
                Ok(log) => log
                    .lines()
                    .map(serde_json::from_str::<serde_json::Value>)
                    .collect::<Result<Vec<_>, _>>()?
                    .into_iter()
                    .filter(|request| request["method"] == "tools/call")
                    .count(),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => 0,
                Err(error) => return Err(error.into()),
            };
            eprintln!("barrier external evidence: disable={disable}, newPeerCalls={calls}");
            anyhow::ensure!(
                calls == 0,
                "revoked configuration accepted {calls} new external calls"
            );
            if let Err(error) = result {
                return Err(error.context(format!("cleanup: refresh={refresh_cleanup:?}, thread={thread_cleanup:?}, owner={owner_cleanup:?}")));
            }
            refresh_cleanup?;
            thread_cleanup?;
            owner_cleanup?;
            Ok(())
        }
    }

    use crate::test_fixture_binding_host as binding_host;

    use crate::test_fixture_mcp_stdio as mcp_stdio;

    mod reconnect_tests {
        //! Physical-owner, cancellation and sibling-isolation proofs for the Studio command.
        use super::{binding_host, mcp_stdio, owner};
        use crate::session::NativeResources;
        use crate::studio::{StudioStore, storage_fault_test_support::close_factory};
        use anyhow::Context;
        use pl_core::{
            context::{ContextContent, ContextSource},
            model::DynModelSession,
            thread::ThreadHandle,
            tool::opaque::Registration,
        };
        use pl_protocol::{CreateMcpDocumentRequest, McpScope};
        use std::{sync::Arc, time::Duration};
        use tokio_util::sync::CancellationToken;

        fn gated_initialize(port: u16) -> String {
            mcp_stdio::STDIO_MCP_SCRIPT
        .replace(
            "import json, os, signal, sys, time",
            "import json, os, signal, socket, sys, time",
        )
        .replace(
            "    elif method == \"initialize\":",
            &format!("    elif method == \"initialize\":\n        with socket.create_connection(('127.0.0.1', {port})) as gate:\n            gate.sendall(b'1')\n            gate.recv(1)"),
        )
        }

        async fn call_registration(
            id: &str,
            tool_id: &str,
            registration: Registration,
            raw: &str,
        ) -> anyhow::Result<String> {
            let thread = ThreadHandle::start(
                id.into(),
                DynModelSession::new(binding_host::Calls {
                    calls: [(tool_id.into(), raw.into())].into(),
                    requests: Default::default(),
                }),
            )?;
            let result = async {
                thread.register_tools(vec![registration]).await?;
                thread.reveal_tools(vec![tool_id.into()]).await?;
                thread
                    .run_turn(binding_host::turn("reconnect-proof"))
                    .await?;
                let snapshot = thread.snapshot();
                Ok(snapshot
                    .context
                    .records
                    .iter()
                    .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
                    .flat_map(|record| &record.content)
                    .filter_map(|part| match part {
                        ContextContent::Text { text } => Some(text.as_ref()),
                        _ => None,
                    })
                    .collect::<Vec<_>>()
                    .join("\n"))
            }
            .await;
            thread.close().await?;
            result
        }

        #[tokio::test]
        async fn reconnect_binding_rejects_wrong_thread_replaced_and_expired_physical_owner()
        -> anyhow::Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let fixture = close_factory(&store)?;
            let factory = &fixture.factory;
            let resources = Arc::new(NativeResources::default());
            let old = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
            let registration =
                super::super::super::mcp_reconnect_tool::registration(factory.clone(), &old)?;
            let output = call_registration(
                "wrong-id",
                "reconnect_mcp",
                registration,
                r#"{"serverId":"fixture"}"#,
            )
            .await?;
            anyhow::ensure!(output.contains("different Thread"), "{output}");
            let frozen =
                super::super::super::mcp_reconnect_tool::registration(factory.clone(), &old)?;
            let current = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
            let output = call_registration(
                "same-id",
                "reconnect_mcp",
                frozen,
                r#"{"serverId":"fixture"}"#,
            )
            .await?;
            anyhow::ensure!(output.contains("no longer active"), "{output}");
            anyhow::ensure!(current.runtime.snapshots().await.is_empty());
            let expired =
                super::super::super::mcp_reconnect_tool::registration(factory.clone(), &old)?;
            old.close(&fixture.events).await?;
            drop(old);
            let output = call_registration(
                "same-id",
                "reconnect_mcp",
                expired,
                r#"{"serverId":"fixture"}"#,
            )
            .await?;
            anyhow::ensure!(output.contains("no longer active"), "{output}");
            current.close(&fixture.events).await?;
            Ok(())
        }

        #[tokio::test]
        async fn reconnect_cancellation_and_close_release_the_original_owner_command_boundary()
        -> anyhow::Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let fixture = close_factory(&store)?;
            let factory = &fixture.factory;
            let resources = Arc::new(NativeResources::default());
            let current = owner(factory, &resources, "cancel", McpScope::Host, temp.path())?;
            let result = async {
    let command = current.command_lock.lock().await;
    let cancellation = CancellationToken::new();
    let reconnect =
        factory.reconnect_mcp_for_owner(&current, Some("fixture"), cancellation.clone());
    tokio::pin!(reconnect);
    assert!(futures::poll!(&mut reconnect).is_pending());
    cancellation.cancel();
    let error = tokio::time::timeout(Duration::from_secs(2), &mut reconnect)
        .await?
        .unwrap_err();
    anyhow::ensure!(error.to_string().contains("cancelled"));
    drop(command);
    anyhow::ensure!(current.command_lock.try_lock().is_ok());

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let peer = temp.path().join("slow.py");
    // Signal actual initialize admission, then block; no sleeps infer runtime acceptance.
    std::fs::write(&peer, gated_initialize(listener.local_addr()?.port()))?;
    fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
        scope: McpScope::Host,
        id: "slow".into(),
        raw_toml: format!("schema_version = 1\nid = 'slow'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 30\n",
            serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?),
    })?;
    let reconnect =
        factory.reconnect_mcp_for_owner(&current, Some("slow"), CancellationToken::new());
    tokio::pin!(reconnect);
    let accepted = tokio::select! {
        result = &mut reconnect => anyhow::bail!("reconnect ended before initialize: {result:?}"),
        accepted = tokio::time::timeout(Duration::from_secs(5), listener.accept()) =>
            accepted.context("close proof: initialize gate never entered")??,
    };
    let closing = current.close(&fixture.events);
    tokio::pin!(closing);
    assert!(futures::poll!(&mut closing).is_pending());
    let error = tokio::time::timeout(Duration::from_secs(2), &mut reconnect)
        .await.context("close proof: reconnect did not observe owner close")?
        .unwrap_err();
    anyhow::ensure!(error.to_string().contains("closing"));
    tokio::time::timeout(Duration::from_secs(5), closing).await.context("close proof: owner did not join reset")??;
    drop(accepted);
    anyhow::ensure!(current.command_lock.try_lock().is_ok());
    anyhow::ensure!(
        factory
            .reconnect_mcp_for_owner(&current, Some("slow"), CancellationToken::new())
            .await
            .is_err()
    );
    Ok::<_, anyhow::Error>(())
    }.await;
            let closed = current.close(&fixture.events).await;
            result?;
            closed?;
            Ok(())
        }

        #[tokio::test]
        async fn failed_reconnect_preserves_current_lease_during_same_configuration_preparation()
        -> anyhow::Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let fixture = close_factory(&store)?;
            let factory = &fixture.factory;
            let peer = temp.path().join("peer.py");
            std::fs::write(&peer, mcp_stdio::STDIO_MCP_SCRIPT)?;
            for id in ["fixture", "unrelated"] {
                fixture
                    .config
                    .create_mcp_document(&CreateMcpDocumentRequest {
                        scope: McpScope::Host,
                        id: id.into(),
                        raw_toml: format!(
                            "schema_version = 1\nid = '{id}'\nkind = 'server'\nenabled = true\n\
                 transport = 'stdio'\ncommand = 'python3'\nargs = {}\n\
                 startup_timeout_secs = 5\n[env]\nSPECIAL_ENV = '{id}'\nMCP_NO_RESOURCES = '1'\n",
                            serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?,
                        ),
                    })?;
            }
            let resources = Arc::new(NativeResources::default());
            let current = owner(
                factory,
                &resources,
                "failed-reset",
                McpScope::Host,
                temp.path(),
            )?;
            let result = async {
                factory
                    .refresh_mcp_for_owner(&current, CancellationToken::new())
                    .await?;
                let before = current.runtime.acquire_turn_lease().await?;
                let sibling_tools: Vec<_> = before
                    .tools()
                    .iter()
                    .filter(|tool| tool.server_id == "unrelated")
                    .cloned()
                    .collect();
                anyhow::ensure!(!sibling_tools.is_empty());
                // Only a new process sees this failure; the sibling's established session stays live.
                std::fs::write(&peer, "import sys\nsys.exit(1)\n")?;
                let error = factory
                    .reconnect_mcp_for_owner(&current, Some("fixture"), CancellationToken::new())
                    .await
                    .expect_err("replacement handshake must fail");
                anyhow::ensure!(error.to_string().contains("remains unavailable"));
                let resolved = factory.resolve_mcp_owner_snapshot(&current)?;
                // This is the preparation performed for the next actual model step. Unchanged
                // configuration must reuse the current lease without starting optional peers again.
                let next = current
                    .prepare_required(
                        resolved.servers,
                        Some(resolved.authorization),
                        None,
                        &fixture.events,
                        &CancellationToken::new(),
                    )
                    .await?;
                anyhow::ensure!(
                    next.generation() == before.generation(),
                    "same-configuration preparation started a new generation after failed reconnect"
                );
                anyhow::ensure!(
                    next.tools() == sibling_tools,
                    "failed target was re-exposed or an unrelated session was removed"
                );
                let snapshot = current.read_snapshot();
                anyhow::ensure!(
                    snapshot.servers.iter().any(|server| server.id == "fixture"
                        && server.lifecycle == pl_protocol::ThreadMcpLifecycleKind::Unavailable),
                    "next model preparation changed the failed target state: {snapshot:?}"
                );
                anyhow::ensure!(
                    snapshot
                        .servers
                        .iter()
                        .any(|server| server.id == "unrelated"
                            && server.lifecycle == pl_protocol::ThreadMcpLifecycleKind::Available)
                );
                Ok::<_, anyhow::Error>(())
            }
            .await;
            let closed = current.close(&fixture.events).await;
            result?;
            closed?;
            Ok(())
        }

        #[tokio::test]
        async fn cancelled_accepted_reconnect_recovers_projection_and_preserves_sibling_sessions()
        -> anyhow::Result<()> {
            use pl_agent_tool::Tool;
            use pl_tool::{
                binding::{ToolCallPolicy, prepare_registration},
                mcp::thread::ThreadMcpTool,
                media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
            };
            #[derive(Debug)]
            struct NoMedia;
            impl ToolMediaHost for NoMedia {
                async fn retain(
                    &self,
                    _: ToolMedia,
                ) -> Result<RetainedToolMedia, pl_core::tool::opaque::ToolError> {
                    unreachable!("the peer only returns text")
                }
            }
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let fixture = close_factory(&store)?;
            let factory = &fixture.factory;
            let peer = temp.path().join("peer.py");
            let log = temp.path().join("requests.jsonl");
            std::fs::write(&peer, mcp_stdio::STDIO_MCP_SCRIPT)?;
            for id in ["fixture", "unrelated"] {
                fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
            scope: McpScope::Host, id: id.into(),
            raw_toml: format!("schema_version = 1\nid = '{id}'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 5\n[env]\nSPECIAL_ENV = '{id}'\nMCP_SCHEMA_TAG = '{id}'\nMCP_NO_RESOURCES = '1'\nMCP_REQUEST_LOG = {}\n",
                serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?,
                serde_json::to_string(&log.display().to_string())?),
        })?;
            }
            let a_resources = Arc::new(NativeResources::default());
            let b_resources = Arc::new(NativeResources::default());
            let a = owner(factory, &a_resources, "a", McpScope::Host, temp.path())?;
            let b = owner(factory, &b_resources, "b", McpScope::Host, temp.path())?;
            let result =
        async {
            factory
                .refresh_mcp_for_owner(&a, CancellationToken::new())
                .await?;
            factory
                .refresh_mcp_for_owner(&b, CancellationToken::new())
                .await?;
            let b_before = b.runtime.acquire_turn_lease().await?.generation();
            let b_state = b.read_snapshot();
            let a_before = a.runtime.acquire_turn_lease().await?.generation();
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
            std::fs::write(&peer, gated_initialize(listener.local_addr()?.port()))?;
            a.start_watcher(factory.clone());
            let mut projection = fixture.events.subscribe_topic_signal(
                &crate::StudioProductTopic::ThreadMcp { thread_id: "a".into() });
            let cancellation = CancellationToken::new();
            let reconnect = factory.reconnect_mcp_for_owner(&a, Some("fixture"), cancellation.clone());
            tokio::pin!(reconnect);
            let (mut gate, _) = tokio::select! {
                result = &mut reconnect => anyhow::bail!("reset ended before initialize: {result:?}"),
                accepted = tokio::time::timeout(Duration::from_secs(5), listener.accept()) =>
                    accepted.context("cancel proof: initialize gate never entered")??,
            };
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            let mut entered = [0];
            gate.read_exact(&mut entered).await?;
            anyhow::ensure!(entered == *b"1", "initialize gate was not entered");
            cancellation.cancel();
            let error = tokio::time::timeout(Duration::from_secs(2), &mut reconnect).await
                .context("cancel proof: caller cancellation did not return")?.unwrap_err();
            anyhow::ensure!(error.to_string().contains("cancelled"), "{error}");
            // Only the existing watcher may finish the reset and restore projection. No
            // explicit refresh, manual resume_projection or replacement reconnect is allowed.
            gate.write_all(b"1").await?;
            drop(gate);
            tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    let snapshot = a.read_snapshot();
                    if a.projection_ready.load(std::sync::atomic::Ordering::Acquire)
                        && ["fixture", "unrelated"].iter().all(|id| snapshot.servers.iter()
                            .any(|server| server.id == *id
                                && server.lifecycle == pl_protocol::ThreadMcpLifecycleKind::Available))
                        && a.runtime.acquire_turn_lease().await?.generation() > a_before
                    {
                        break;
                    }
                    projection.changed().await?;
                }
                Ok::<_, anyhow::Error>(())
            }).await.with_context(|| format!("cancel proof: original watcher did not restore projection; ready={}, state={:?}, requests={}",
                a.projection_ready.load(std::sync::atomic::Ordering::Acquire), a.read_snapshot(),
                std::fs::read_to_string(&log).unwrap_or_default()))??;
            anyhow::ensure!(a.command_lock.try_lock().is_ok(), "background reconcile retained command lock");
            anyhow::ensure!(b.runtime.acquire_turn_lease().await?.generation() == b_before);
            anyhow::ensure!(b.read_snapshot() == b_state);
            for calling in [&a, &b] {
            let lease = calling.runtime.acquire_turn_lease().await?;
            let descriptor = lease
                .tools()
                .iter()
                .find(|tool| tool.server_id == "fixture")
                .ok_or_else(|| anyhow::anyhow!("sibling lost fixture tool"))?
                .clone();
            let tool = ThreadMcpTool::new(lease, &descriptor.exposed_name, Arc::new(NoMedia))?;
            let prepared = prepare_registration(
                &descriptor.exposed_name,
                tool.definition(),
                ToolCallPolicy::DirectOnly,
            )?;
            let output = call_registration(
                &calling.thread_id,
                &descriptor.exposed_name,
                tool.registration(prepared),
                "{}",
            )
            .await?;
            anyhow::ensure!(output.contains("fixture"), "{output}");
            if Arc::ptr_eq(calling, &a) {
                a.close(&fixture.events).await?;
            }
            }
            let requests = std::fs::read_to_string(&log)?
                .lines()
                .map(serde_json::from_str::<serde_json::Value>)
                .collect::<Result<Vec<_>, _>>()?;
            anyhow::ensure!(
                requests
                    .iter()
                    .filter(
                        |request| request["method"] == "initialize" && request["tag"] == "fixture"
                    )
                    .count()
                    == 3
            );
            anyhow::ensure!(
                requests
                    .iter()
                    .filter(|request| request["method"] == "initialize"
                        && request["tag"] == "unrelated")
                    .count()
                    == 2,
                "targeted reconnect restarted an unrelated server"
            );
            anyhow::ensure!(requests.iter().filter(|request| request["method"] == "tools/call").count() == 2,
                "cancellation replayed a business call");
            Ok::<_, anyhow::Error>(())
        }
        .await;
            let a_close = a.close(&fixture.events).await;
            let b_close = b.close(&fixture.events).await;
            result?;
            a_close?;
            b_close?;
            Ok(())
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::studio::{StudioStore, agent_host::ThreadWriteBehindWriter};
    use pl_protocol::{McpEffectiveSource, McpExecutionLocation};
    use pl_tool::mcp::McpConnector;
    use pl_tool::mcp::config::{
        EffectiveMcpServerConfig, McpExecutionContext, McpServerConfig, McpServerMutationPolicy,
        McpServerSourceKind, McpServerStatusKind, McpServerTransport,
    };

    pub(crate) fn sample_resolved_server(id: &str, url: &str) -> ResolvedThreadMcpServer {
        let config = McpServerConfig {
            enabled: true,
            required: false,
            transport: McpServerTransport::StreamableHttp,
            startup_mode: Default::default(),
            command: None,
            args: Vec::new(),
            env: BTreeMap::new(),
            cwd: None,
            url: Some(url.to_owned()),
            bearer_token_env_var: None,
            headers: BTreeMap::new(),
            startup_timeout_secs: Some(1),
            tool_timeout_secs: Some(1),
            enabled_tools: None,
            disabled_tools: Vec::new(),
        };
        ResolvedThreadMcpServer {
            id: id.to_owned(),
            effective_source: McpEffectiveSource::HostServer,
            execution_location: McpExecutionLocation::HostRemoteStreamableHttp,
            built_in: false,
            server: EffectiveMcpServerConfig {
                id: id.to_owned(),
                config,
                source_kind: McpServerSourceKind::User,
                source_label: "User".to_owned(),
                source_detail: None,
                status_kind: McpServerStatusKind::Enabled,
                status_message: None,
                mutation_policy: McpServerMutationPolicy::UserEditable,
                bearer_token: None,
                tool_effect: None,
                execution_context: McpExecutionContext::Host,
            },
        }
    }

    // Called from lifecycle's tests so the trigger is the actual early native fence, not
    // request_member_mcp_shutdown or execute_shutdown invoked directly by the fixture.
    pub(crate) async fn exercise_member_mcp_exit_fence(
        runtime: &crate::studio::StudioRuntime,
        factory: &StudioThreadFactory,
        session: &crate::session::SessionRuntime,
        root: &std::path::Path,
        fail_watcher: bool,
    ) -> Result<()> {
        use super::super::tool_bindings::ToolBinding;
        use crate::StudioProductEventKind;
        use crate::session::session_close_tests::{ProbeStore, member_with_probe};
        use crate::studio::agent_host::worktree_lease::WorkspaceEndpoint;
        use pl_provider_fixture::{FixtureServer, MCP_KEY, MCP_PATH};

        let peer = FixtureServer::start(Vec::new()).await?;
        let mcp = McpRuntime::new(McpConnector::default());
        let mut server = sample_resolved_server(
            "early-close",
            &format!("http://{}{MCP_PATH}", peer.address()),
        );
        server.server.bearer_token = Some(MCP_KEY.to_owned());
        let servers = BTreeMap::from([(server.id.clone(), server)]);
        let lifetime = Arc::new(ThreadToolLifetime::default());
        let owner = ThreadMcpOwner::new(
            "early-close-member".into(),
            lifetime.clone(),
            McpScope::Host,
            root.to_owned(),
            None,
            mcp.handle(),
            servers.clone(),
        );
        owner
            .runtime
            .reconcile(
                servers
                    .into_iter()
                    .map(|(id, entry)| (id, entry.server))
                    .collect(),
            )
            .await?;
        owner
            .refresh_snapshot(&factory.services.product_events)
            .await;
        assert_eq!(
            owner.read_snapshot().servers[0].lifecycle,
            ThreadMcpLifecycleKind::Available
        );
        assert_eq!(
            owner.runtime.acquire_turn_lease().await?.server_ids(),
            &["early-close"]
        );

        let (store, mut flush_entered) = ProbeStore::open(true);
        member_with_probe(session, &owner.thread_id, None, Some(&store), root).await?;
        let member = session
            .observed_thread(&owner.thread_id)
            .expect("assembled member");
        let scope = session.native_resources(&member)?;
        let incarnation = Arc::new(());
        let usage = factory
            .services
            .worktrees
            .reserve_workspace(&owner.thread_id, WorkspaceEndpoint::Local)?;
        *scope.binding.lock().unwrap() = Some(ToolBinding {
            assignment: None,
            workspace_usage: usage.clone(),
            lifetime: lifetime.clone(),
            incarnation: incarnation.clone(),
            target_invalidated: false,
            catalog: None,
            initial_skill_prompt: String::new(),
            policy_key: String::new(),
            permission_mode: crate::approval::PermissionMode::default(),
            policies: BTreeMap::new(),
            project: WorkspaceRecord {
                id: "early-close-project".into(),
                kind: pl_protocol::studio::WorkspaceKind::Project,
                name: "early-close-project".into(),
                path: root.to_string_lossy().into_owned(),
                ssh_alias: None,
                updated_at: 0,
            },
            workspace: ToolWorkspace::new(pl_tool::workspace::AgentWorkspace::local(root)),
            commands: None,
            remote: None,
            ssh_profile: None,
            lsp_lease: None,
            lsp_binding_id: None,
        });
        *scope.mcp.lock().unwrap() = Some(owner.clone());
        factory.bind_resource_scope(&owner.thread_id, &scope)?;
        if fail_watcher {
            let (entered, failed) = tokio::sync::oneshot::channel();
            *owner.watcher.lock().unwrap() = Some(tokio::spawn(async move {
                entered.send(()).unwrap();
                panic!("member MCP watcher regression failure");
            }));
            failed.await?;
        } else {
            owner.start_watcher(factory.clone());
        }

        // Hold the original terminal ColdStore flush, not a parallel close model.
        // The command gate lets us release the early MCP task only after save is blocked.
        let command_gate = owner.command_lock.lock().await;
        let mut events = factory.services.product_events.subscribe_internal();
        assert!(runtime.fence_exit_admission().await.is_empty());
        assert!(lifetime.cancellation.is_cancelled());
        let first = owner
            .shutdown
            .lock()
            .unwrap()
            .clone()
            .expect("fence starts owned stop");
        assert!(runtime.fence_exit_admission().await.is_empty());
        assert!(first.ptr_eq(owner.shutdown.lock().unwrap().as_ref().unwrap()));
        let mut final_close = Box::pin(session.close_session());
        assert!(futures::poll!(&mut final_close).is_pending());
        tokio::select! {
            report = &mut final_close => panic!("Session escaped before terminal flush: {report:?}"),
            entered = flush_entered.wait_for(|entered| *entered) => { entered?; }
        }
        drop(command_gate);

        if fail_watcher {
            // The real JoinError is retained by the original owner; an early broadcast is
            // not allowed to fabricate a successful close or silently remove the binding.
            store.gate.add_permits(1);
            let report = final_close.await;
            assert_eq!(report.len(), 1, "{report:?}");
            assert_eq!(report[0].0, owner.thread_id);
            assert!(format!("{:?}", report[0].1).contains("member MCP watcher regression failure"));
            let retained = first.peek().expect("final join records the real result");
            assert!(
                retained
                    .as_ref()
                    .unwrap_err()
                    .to_string()
                    .contains("join MCP watcher")
            );
            assert!(owner.runtime.health_snapshot().await.is_ok());
            assert!(Arc::ptr_eq(
                scope.mcp.lock().unwrap().as_ref().unwrap(),
                &owner
            ));
            assert!(scope.binding.lock().unwrap().is_some());
            assert!(session.observed_thread(&owner.thread_id).is_some());
            assert_eq!(session.phase(), crate::session::SessionPhase::Closing);
            // Explicit retry after the error has been observed uses the retained owner.
            store.gate.add_permits(1);
            let report = session.close_session().await;
            assert!(report.is_empty(), "{report:?}");
            assert!(!first.ptr_eq(owner.shutdown.lock().unwrap().as_ref().unwrap()));
        } else {
            // No completion future is polled here. Only the dropped early request can
            // advance the actual connector/service shutdown and publish its successful ACK.
            loop {
                if let StudioProductEventKind::ThreadMcpStateChanged(snapshot) =
                    events.recv().await?.kind
                    && snapshot.thread_id == owner.thread_id
                    && snapshot.servers.is_empty()
                {
                    break;
                }
            }
            assert!(owner.runtime.health_snapshot().await.is_err());
            assert!(
                first.peek().is_none(),
                "early task runs without a join waiter"
            );
            assert!(futures::poll!(&mut final_close).is_pending());
            assert!(Arc::ptr_eq(
                scope.mcp.lock().unwrap().as_ref().unwrap(),
                &owner
            ));
            assert!(Arc::ptr_eq(
                &scope.binding.lock().unwrap().as_ref().unwrap().incarnation,
                &incarnation,
            ));
            assert!(scope.has_obligations());
            assert_eq!(session.phase(), crate::session::SessionPhase::Closing);
            assert!(Arc::ptr_eq(&session.native_resources(&member)?, &scope));
            assert_eq!(store.flushes.load(std::sync::atomic::Ordering::SeqCst), 1);
            assert_eq!(
                factory.services.worktrees.usage_owner(&usage)?,
                owner.thread_id
            );
            let closed_generation = owner.read_snapshot().generation;
            assert!(runtime.fence_exit_admission().await.is_empty());
            assert!(first.ptr_eq(owner.shutdown.lock().unwrap().as_ref().unwrap()));
            store.gate.add_permits(1);
            let report = final_close.await;
            assert!(report.is_empty(), "{report:?}");
            assert!(session.close_session().await.is_empty());
            assert_eq!(owner.read_snapshot().generation, closed_generation);
            assert!(matches!(first.peek(), Some(Ok(()))));
        }
        assert!(scope.mcp.lock().unwrap().is_none());
        assert!(scope.binding.lock().unwrap().is_none());
        assert!(!scope.has_obligations());
        assert_eq!(session.phase(), crate::session::SessionPhase::Closed);
        assert!(session.observed_thread(&owner.thread_id).is_none());
        assert!(owner.runtime.health_snapshot().await.is_err());
        peer.finish().await?;
        Ok(())
    }

    #[tokio::test]
    async fn thread_mcp_owners_are_isolated_per_thread_and_emit_connecting_and_shutdown_states()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let events = ProductEventBus::new(store, writer);
        events.initialize_directories().await?;

        let connector = McpConnector::default();
        let runtime_a = McpRuntime::new(connector.clone());
        let runtime_b = McpRuntime::new(connector);

        let mut servers_a = BTreeMap::new();
        servers_a.insert(
            "srv_a".to_owned(),
            sample_resolved_server("srv_a", "http://127.0.0.1:9/mcp"),
        );
        let mut servers_b = BTreeMap::new();
        servers_b.insert(
            "srv_b".to_owned(),
            sample_resolved_server("srv_b", "http://127.0.0.1:9/mcp"),
        );

        let owner_a = ThreadMcpOwner::new(
            "thread-a".to_owned(),
            Arc::new(ThreadToolLifetime::default()),
            McpScope::Host,
            temp.path().to_path_buf(),
            None,
            runtime_a.handle(),
            servers_a.clone(),
        );
        let owner_b = ThreadMcpOwner::new(
            "thread-b".to_owned(),
            Arc::new(ThreadToolLifetime::default()),
            McpScope::Host,
            temp.path().to_path_buf(),
            None,
            runtime_b.handle(),
            servers_b.clone(),
        );

        // Initial snapshot starts in `Connecting` state.
        let snap_a0 = owner_a.read_snapshot();
        assert_eq!(snap_a0.generation, 1);
        assert_eq!(
            snap_a0.servers[0].lifecycle,
            ThreadMcpLifecycleKind::Connecting
        );

        // Reconcile both runtimes independently.
        owner_a
            .runtime
            .reconcile(
                servers_a
                    .iter()
                    .map(|(k, v)| (k.clone(), v.server.clone()))
                    .collect(),
            )
            .await?;
        owner_a.refresh_snapshot(&events).await;

        owner_b
            .runtime
            .reconcile(
                servers_b
                    .iter()
                    .map(|(k, v)| (k.clone(), v.server.clone()))
                    .collect(),
            )
            .await?;
        owner_b.refresh_snapshot(&events).await;

        let snap_a1 = owner_a.read_snapshot();
        assert_eq!(
            snap_a1.servers[0].lifecycle,
            ThreadMcpLifecycleKind::Unavailable
        );
        let snap_b1 = owner_b.read_snapshot();
        assert_eq!(
            snap_b1.servers[0].lifecycle,
            ThreadMcpLifecycleKind::Unavailable
        );

        // Reconnecting `srv_a` on `thread-a` transitions `srv_a` to `Connecting` without touching `thread-b`.
        owner_a.publish_connecting(Some("srv_a"), &events);
        assert_eq!(
            owner_a.read_snapshot().servers[0].lifecycle,
            ThreadMcpLifecycleKind::Connecting
        );
        assert_eq!(owner_b.read_snapshot().generation, snap_b1.generation);

        // Closing `thread-a` transitions `thread-a` through `ShuttingDown` -> `servers: []` while `thread-b` stays intact.
        owner_a.publish_shutting_down(&events);
        assert_eq!(
            owner_a.read_snapshot().servers[0].lifecycle,
            ThreadMcpLifecycleKind::ShuttingDown
        );
        owner_a.runtime.shutdown().await?;
        owner_a.publish_closed(&events);
        assert!(owner_a.read_snapshot().servers.is_empty());

        // `thread-b` is still alive and independent.
        assert_eq!(owner_b.read_snapshot().servers.len(), 1);
        owner_b.runtime.shutdown().await?;
        Ok(())
    }
}
