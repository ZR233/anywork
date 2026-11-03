//! Per-Thread `McpRuntime` ownership, `ThreadMcpStateSnapshot` projection, and lifecycle management.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use pl_protocol::{McpScope, ThreadMcpLifecycleKind, ThreadMcpServerState, ThreadMcpStateSnapshot};
use pl_tool::mcp::{
    McpAvailabilityKind, McpAvailabilitySnapshot, McpResetScope, McpRuntime, McpRuntimeHandle,
    McpTurnLease,
};
use pl_tool::remote::{RemoteCommandBackend, RemoteWorkspaceHost};
use pl_tool::workspace::ToolWorkspace;
use tokio::sync::broadcast::error::RecvError;
use tokio_util::sync::CancellationToken;

use super::StudioThreadFactory;
use super::errors::resource_error;
use super::thread_tools::CatalogPreparation;
use super::tool_bindings::ThreadToolLifetime;
use crate::config::ResolvedThreadMcpServer;
use crate::studio::{ProductEventBus, WorkspaceRecord};
use crate::thread_assembler::ThreadAssemblyError;

pub(crate) struct ThreadMcpOwner {
    pub(super) thread_id: String,
    pub(super) lifetime: Arc<ThreadToolLifetime>,
    pub(super) scope: McpScope,
    pub(super) workspace_root: PathBuf,
    remote_commands: Mutex<Option<Arc<RemoteCommandBackend>>>,
    pub(super) runtime: McpRuntimeHandle,
    servers: Mutex<BTreeMap<String, ResolvedThreadMcpServer>>,
    state: Mutex<ThreadMcpStateSnapshot>,
    pub(super) command_lock: Arc<tokio::sync::Mutex<()>>,
    watcher: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl ThreadMcpOwner {
    fn new(
        thread_id: String,
        lifetime: Arc<ThreadToolLifetime>,
        scope: McpScope,
        workspace_root: PathBuf,
        remote_commands: Option<Arc<RemoteCommandBackend>>,
        runtime: McpRuntimeHandle,
        servers: BTreeMap<String, ResolvedThreadMcpServer>,
    ) -> Arc<Self> {
        let initial_servers = servers
            .values()
            .map(|entry| server_state_from_availability(entry, None, None))
            .collect();
        let initial_state = ThreadMcpStateSnapshot {
            thread_id: thread_id.clone(),
            scope: scope.clone(),
            generation: 1,
            servers: initial_servers,
        };
        Arc::new(Self {
            thread_id,
            lifetime,
            scope,
            workspace_root,
            remote_commands: Mutex::new(remote_commands),
            runtime,
            servers: Mutex::new(servers),
            state: Mutex::new(initial_state),
            command_lock: Arc::new(tokio::sync::Mutex::new(())),
            watcher: Mutex::new(None),
        })
    }

    fn start_watcher(self: &Arc<Self>, product_events: ProductEventBus) {
        let mut updates = self.runtime.subscribe();
        let owner = Arc::downgrade(self);
        let handle = tokio::spawn(async move {
            while let Ok(()) | Err(RecvError::Lagged(_)) = updates.recv().await {
                let Some(owner) = owner.upgrade() else {
                    break;
                };
                owner.refresh_snapshot(&product_events).await;
            }
        });
        *self
            .watcher
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(handle);
    }

    fn stop_watcher(&self) {
        if let Some(handle) = self
            .watcher
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            handle.abort();
        }
    }

    fn remote_commands(&self) -> Option<Arc<RemoteCommandBackend>> {
        self.remote_commands
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn update_resolved(
        &self,
        servers: BTreeMap<String, ResolvedThreadMcpServer>,
        remote_commands: Option<Arc<RemoteCommandBackend>>,
    ) {
        *self
            .remote_commands
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = remote_commands;
        *self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = servers;
    }

    fn set_servers(&self, servers: BTreeMap<String, ResolvedThreadMcpServer>) {
        *self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = servers;
    }

    pub(super) fn read_snapshot(&self) -> ThreadMcpStateSnapshot {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn publish_connecting(&self, target_server_id: Option<&str>, product_events: &ProductEventBus) {
        let servers = self
            .servers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let previous_by_id: BTreeMap<String, ThreadMcpServerState> = guard
            .servers
            .iter()
            .cloned()
            .map(|entry| (entry.id.clone(), entry))
            .collect();
        let next_servers: Vec<ThreadMcpServerState> = servers
            .values()
            .map(|entry| {
                let mark_connecting =
                    target_server_id.is_none_or(|target| target == entry.id.as_str());
                if mark_connecting {
                    server_state_from_availability(
                        entry,
                        None,
                        Some(ThreadMcpLifecycleKind::Connecting),
                    )
                } else if let Some(prev) = previous_by_id.get(&entry.id) {
                    prev.clone()
                } else {
                    server_state_from_availability(
                        entry,
                        None,
                        Some(ThreadMcpLifecycleKind::Connecting),
                    )
                }
            })
            .collect();
        if guard.servers != next_servers {
            guard.generation = guard.generation.saturating_add(1);
            guard.servers = next_servers;
            let snapshot = guard.clone();
            drop(guard);
            product_events.emit_thread_mcp_state(snapshot);
        }
    }

    fn publish_shutting_down(&self, product_events: &ProductEventBus) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if guard.servers.is_empty() {
            return;
        }
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
        guard.generation = guard.generation.saturating_add(1);
        guard.servers.clear();
        let snapshot = guard.clone();
        drop(guard);
        product_events.emit_thread_mcp_state(snapshot);
    }

    pub(super) async fn refresh_snapshot(&self, product_events: &ProductEventBus) {
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
        if guard.servers != next_servers {
            guard.generation = guard.generation.saturating_add(1);
            guard.servers = next_servers;
            let snapshot = guard.clone();
            drop(guard);
            product_events.emit_thread_mcp_state(snapshot);
        }
    }
}

fn server_state_from_availability(
    entry: &ResolvedThreadMcpServer,
    availability: Option<&McpAvailabilitySnapshot>,
    override_lifecycle: Option<ThreadMcpLifecycleKind>,
) -> ThreadMcpServerState {
    let lifecycle = override_lifecycle.unwrap_or_else(|| match availability {
        Some(snapshot) => match snapshot.availability_kind {
            McpAvailabilityKind::Checking => ThreadMcpLifecycleKind::Connecting,
            McpAvailabilityKind::Available => ThreadMcpLifecycleKind::Available,
            McpAvailabilityKind::Unavailable
            | McpAvailabilityKind::Disabled
            | McpAvailabilityKind::MissingCredential => ThreadMcpLifecycleKind::Unavailable,
        },
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
        thread_id: &str,
        lifetime: &Arc<ThreadToolLifetime>,
        project: &WorkspaceRecord,
        workspace: &ToolWorkspace,
        remote: Option<&RemoteWorkspaceHost>,
        preparation: &CatalogPreparation,
        cancellation: &CancellationToken,
    ) -> Result<McpTurnLease, ThreadAssemblyError> {
        let scope = match &project.ssh_alias {
            Some(alias) => McpScope::Ssh {
                ssh_alias: alias.clone(),
            },
            None => McpScope::Host,
        };
        let remote_commands = remote.map(|host| Arc::new(host.commands.clone()));
        let resolved_servers = self
            .services
            .config_runtime
            .resolve_thread_mcp_configs(
                &scope,
                workspace.root(),
                self.services.store.paths().home(),
                remote_commands.clone(),
            )
            .map_err(|error| resource_error("resolve Thread MCP servers", error))?;
        let effective_servers: BTreeMap<String, _> = resolved_servers
            .iter()
            .map(|(id, entry)| (id.clone(), entry.server.clone()))
            .collect();

        match preparation {
            CatalogPreparation::Initial => {
                let _ = self.shutdown_thread_mcp(thread_id).await;
                let runtime = McpRuntime::new(self.services.mcp_connector.clone());
                let owner = ThreadMcpOwner::new(
                    thread_id.to_owned(),
                    lifetime.clone(),
                    scope,
                    workspace.root().to_path_buf(),
                    remote_commands,
                    runtime.handle(),
                    resolved_servers,
                );
                owner.start_watcher(self.services.product_events.clone());
                let initial_snapshot = owner.read_snapshot();
                self.mcp_owners
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .insert(thread_id.to_owned(), owner.clone());
                self.services
                    .product_events
                    .emit_thread_mcp_state(initial_snapshot);

                let reconcile_result = {
                    let _guard = owner.command_lock.lock().await;
                    tokio::select! {
                        biased;
                        _ = cancellation.cancelled() => Err(ThreadAssemblyError::from(pl_core::thread::ThreadError::Cancelled)),
                        res = owner.runtime.reconcile(effective_servers) => res.map_err(|error| resource_error("reconcile initial Thread MCP servers", error)),
                    }
                };
                if let Err(error) = reconcile_result {
                    let _ = self.shutdown_thread_mcp(thread_id).await;
                    return Err(error);
                }
                owner.refresh_snapshot(&self.services.product_events).await;
                match owner.runtime.acquire_turn_lease().await {
                    Ok(lease) => Ok(lease),
                    Err(error) => {
                        let _ = self.shutdown_thread_mcp(thread_id).await;
                        Err(resource_error("acquire initial Thread MCP lease", error))
                    }
                }
            }
            CatalogPreparation::Refresh { .. } => {
                let existing = self
                    .mcp_owners
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .get(thread_id)
                    .cloned();
                let owner = match existing {
                    Some(owner) => {
                        owner.update_resolved(resolved_servers, remote_commands);
                        owner
                    }
                    None => {
                        let runtime = McpRuntime::new(self.services.mcp_connector.clone());
                        let owner = ThreadMcpOwner::new(
                            thread_id.to_owned(),
                            lifetime.clone(),
                            scope,
                            workspace.root().to_path_buf(),
                            remote_commands,
                            runtime.handle(),
                            resolved_servers,
                        );
                        owner.start_watcher(self.services.product_events.clone());
                        let initial_snapshot = owner.read_snapshot();
                        self.mcp_owners
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .insert(thread_id.to_owned(), owner.clone());
                        self.services
                            .product_events
                            .emit_thread_mcp_state(initial_snapshot);
                        owner
                    }
                };
                {
                    let _guard = owner.command_lock.lock().await;
                    tokio::select! {
                        biased;
                        _ = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Cancelled.into()),
                        res = owner.runtime.reconcile(effective_servers) => res.map_err(|error| resource_error("reconcile refreshed Thread MCP servers", error))?,
                    }
                }
                owner.refresh_snapshot(&self.services.product_events).await;
                owner
                    .runtime
                    .acquire_turn_lease()
                    .await
                    .map_err(|error| resource_error("acquire refreshed Thread MCP lease", error))
            }
        }
    }

    pub(crate) async fn read_thread_mcp(&self, thread_id: &str) -> Result<ThreadMcpStateSnapshot> {
        if let Some(owner) = self
            .mcp_owners
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .cloned()
        {
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

    pub(crate) async fn reconnect_thread_mcp(
        &self,
        thread_id: &str,
        server_id: Option<&str>,
    ) -> Result<ThreadMcpStateSnapshot> {
        let owner = self
            .mcp_owners
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .cloned()
            .ok_or_else(|| {
                pl_protocol::studio::StudioError::invalid_argument(format!(
                    "Thread '{thread_id}' is not currently open"
                ))
            })?;
        let _guard = owner.command_lock.lock().await;
        let resolved_servers = self.services.config_runtime.resolve_thread_mcp_configs(
            &owner.scope,
            &owner.workspace_root,
            self.services.store.paths().home(),
            owner.remote_commands(),
        )?;
        if let Some(target_id) = server_id
            && !resolved_servers.contains_key(target_id)
        {
            return Err(pl_protocol::studio::StudioError::invalid_argument(format!(
                "MCP server '{target_id}' is not enabled in Thread '{thread_id}'"
            ))
            .into());
        }
        owner.set_servers(resolved_servers.clone());
        owner.publish_connecting(server_id, &self.services.product_events);
        let effective_servers = resolved_servers
            .into_iter()
            .map(|(id, entry)| (id, entry.server))
            .collect();
        let reset_scope = match server_id {
            Some(id) => McpResetScope::Server {
                server_id: id.to_owned(),
            },
            None => McpResetScope::All,
        };
        owner.runtime.reset(reset_scope, effective_servers).await?;
        owner.refresh_snapshot(&self.services.product_events).await;
        Ok(owner.read_snapshot())
    }

    pub(crate) async fn reconcile_open_threads_for_scopes(&self, scopes: &[McpScope]) {
        let include_all = scopes.iter().any(|scope| matches!(scope, McpScope::Host));
        let owners: Vec<Arc<ThreadMcpOwner>> = self
            .mcp_owners
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .filter(|owner| include_all || scopes.contains(&owner.scope))
            .cloned()
            .collect();
        for owner in owners {
            let _guard = owner.command_lock.lock().await;
            let resolved_servers = match self.services.config_runtime.resolve_thread_mcp_configs(
                &owner.scope,
                &owner.workspace_root,
                self.services.store.paths().home(),
                owner.remote_commands(),
            ) {
                Ok(servers) => servers,
                Err(error) => {
                    tracing::warn!(
                        thread_id = %owner.thread_id,
                        error = %error,
                        "failed to resolve Thread MCP configs after catalog change"
                    );
                    continue;
                }
            };
            owner.set_servers(resolved_servers.clone());
            let effective_servers = resolved_servers
                .into_iter()
                .map(|(id, entry)| (id, entry.server))
                .collect();
            if let Err(error) = owner.runtime.reconcile(effective_servers).await {
                tracing::warn!(
                    thread_id = %owner.thread_id,
                    error = %error,
                    "failed to reconcile Thread MCP runtime after catalog change"
                );
            }
            owner.refresh_snapshot(&self.services.product_events).await;
        }
    }

    pub(super) fn retire_thread_mcp_if_current(
        &self,
        id: &str,
        lifetime: &Arc<ThreadToolLifetime>,
    ) {
        let removed = {
            let mut guard = self
                .mcp_owners
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if guard
                .get(id)
                .is_some_and(|owner| Arc::ptr_eq(&owner.lifetime, lifetime))
            {
                guard.remove(id)
            } else {
                None
            }
        };
        if let Some(owner) = removed {
            owner.stop_watcher();
            let product_events = self.services.product_events.clone();
            let handle = tokio::spawn(async move {
                owner.publish_shutting_down(&product_events);
                let _ = owner.runtime.shutdown().await;
                owner.publish_closed(&product_events);
            });
            self.retiring_mcp
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .push(handle);
        }
    }

    async fn drain_retiring_mcp(&self) {
        let handles: Vec<tokio::task::JoinHandle<()>> = std::mem::take(
            &mut *self
                .retiring_mcp
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        );
        for handle in handles {
            let _ = handle.await;
        }
    }

    pub(crate) async fn shutdown_thread_mcp(&self, id: &str) -> Result<()> {
        let removed = self
            .mcp_owners
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(id);
        let mut shutdown_res = Ok(());
        if let Some(owner) = removed {
            owner.stop_watcher();
            owner.publish_shutting_down(&self.services.product_events);
            shutdown_res = owner.runtime.shutdown().await.map_err(Into::into);
            owner.publish_closed(&self.services.product_events);
        }
        self.drain_retiring_mcp().await;
        shutdown_res
    }

    pub(crate) async fn shutdown_all_mcp(&self) -> Result<()> {
        let owners: Vec<Arc<ThreadMcpOwner>> = {
            let mut guard = self
                .mcp_owners
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            std::mem::take(&mut *guard).into_values().collect()
        };
        let mut first_error = None;
        for owner in owners {
            owner.stop_watcher();
            owner.publish_shutting_down(&self.services.product_events);
            if let Err(error) = owner.runtime.shutdown().await
                && first_error.is_none()
            {
                first_error = Some(anyhow::Error::from(error));
            }
            owner.publish_closed(&self.services.product_events);
        }
        self.drain_retiring_mcp().await;
        if let Some(error) = first_error {
            return Err(error);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::{StudioStore, agent_host::ThreadWriteBehindWriter};
    use pl_protocol::{McpEffectiveSource, McpExecutionLocation};
    use pl_tool::mcp::McpConnector;
    use pl_tool::mcp::config::{
        EffectiveMcpServerConfig, McpExecutionContext, McpServerConfig, McpServerMutationPolicy,
        McpServerSourceKind, McpServerStatusKind, McpServerTransport,
    };

    fn sample_resolved_server(id: &str, url: &str) -> ResolvedThreadMcpServer {
        let config = McpServerConfig {
            enabled: true,
            transport: McpServerTransport::StreamableHttp,
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
            Arc::new(ThreadToolLifetime {
                gate: Arc::new(tokio::sync::Mutex::new(())),
                cancellation: CancellationToken::new(),
            }),
            McpScope::Host,
            temp.path().to_path_buf(),
            None,
            runtime_a.handle(),
            servers_a.clone(),
        );
        let owner_b = ThreadMcpOwner::new(
            "thread-b".to_owned(),
            Arc::new(ThreadToolLifetime {
                gate: Arc::new(tokio::sync::Mutex::new(())),
                cancellation: CancellationToken::new(),
            }),
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
