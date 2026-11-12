//! MCP runtime worker:generation 生命周期编排、lease 发布与命令循环。
//!
//! 按域拆分:`reconcile` 承载 generation 准备与连接,`server` 承载 server/generation
//! 运行态结构,`tools` 承载工具定义过滤与超时解析,`dispatch` 承载工具调用与资源
//! 查询分发,`redaction` 承载 host 错误脱敏;本页保留 `RuntimeWorker` 命令循环、
//! generation 激活/回收与 lease 发布。

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::Arc;

use futures::future::BoxFuture;
use futures::stream::FuturesUnordered;
use futures::{FutureExt, StreamExt};
use pl_protocol::{McpAvailabilityDescriptor, McpHealthSnapshot, PureError, Result};
use rmcp::model::Tool;
use tokio::sync::{broadcast, mpsc};

use super::{LeaseSnapshot, McpGeneration, McpResetScope, RuntimeCommand, ShutdownCompletion};
use crate::mcp::config::EffectiveMcpServerConfig;
use crate::mcp::health::{McpAvailabilityKind, McpAvailabilitySnapshot};
use crate::mcp::{McpConnector, McpServerToolRefresh, McpToolRefreshReport, McpToolRefreshStatus};

mod dispatch;
mod reconcile;
mod redaction;
mod server;
#[cfg(test)]
mod tests;
mod tools;

use reconcile::{
    ActivePreparation, PendingMutation, PendingReconcile, await_preparation,
    cancel_and_collect_reconciles, prepare_generation,
};
use server::{
    RuntimeGeneration, assign_tool_descriptors, reset_failed, server_fingerprint, unique_sessions,
};
use tokio_util::sync::CancellationToken;
use tools::{configured_startup_timeout, filter_tool_definitions};

pub(super) async fn run(
    connector: McpConnector,
    receiver: mpsc::UnboundedReceiver<RuntimeCommand>,
    commands: mpsc::UnboundedSender<RuntimeCommand>,
    updates: broadcast::Sender<()>,
    shutdown_completion: ShutdownCompletion,
) {
    RuntimeWorker::new(connector, receiver, commands, updates, shutdown_completion)
        .run()
        .await;
}

struct RuntimeWorker {
    connector: McpConnector,
    receiver: mpsc::UnboundedReceiver<RuntimeCommand>,
    commands: mpsc::UnboundedSender<RuntimeCommand>,
    updates: broadcast::Sender<()>,
    generations: BTreeMap<McpGeneration, RuntimeGeneration>,
    current: McpGeneration,
    next_generation: u64,
    shutting_down: bool,
    /// Single-owned closing completion shared with every runtime handle.
    shutdown_completion: ShutdownCompletion,
    requests: FuturesUnordered<BoxFuture<'static, McpGeneration>>,
    /// Retired/unpublished owners stay here until close confirms exit or returns
    /// them for retry. Cleanup must never suspend request deadlines or admission.
    cleanups: FuturesUnordered<BoxFuture<'static, Vec<RuntimeGeneration>>>,
}

struct ActiveToolRefresh {
    future: BoxFuture<'static, ToolRefreshCandidate>,
}

/// The worker owns discovery even if the requesting future is dropped. No new sessions
/// are created here, and shutdown drops the discovery future before closing its session.
struct ExplicitToolRefresh {
    remaining: VecDeque<String>,
    servers: Vec<McpServerToolRefresh>,
    reply: tokio::sync::oneshot::Sender<Result<McpToolRefreshReport>>,
}

struct ToolRefreshCandidate {
    observed_generation: McpGeneration,
    server_id: String,
    session: Arc<crate::mcp::ConnectedMcp>,
    definitions: std::result::Result<Vec<Tool>, String>,
}

async fn await_tool_refresh(refresh: &mut Option<ActiveToolRefresh>) -> ToolRefreshCandidate {
    refresh
        .as_mut()
        .expect("guarded MCP tool refresh must exist")
        .future
        .as_mut()
        .await
}

impl RuntimeWorker {
    fn new(
        connector: McpConnector,
        receiver: mpsc::UnboundedReceiver<RuntimeCommand>,
        commands: mpsc::UnboundedSender<RuntimeCommand>,
        updates: broadcast::Sender<()>,
        shutdown_completion: ShutdownCompletion,
    ) -> Self {
        let current = McpGeneration(0);
        Self {
            connector,
            receiver,
            commands,
            updates,
            generations: [(current, RuntimeGeneration::empty(current))]
                .into_iter()
                .collect(),
            current,
            next_generation: 1,
            shutting_down: false,
            shutdown_completion,
            requests: FuturesUnordered::new(),
            cleanups: FuturesUnordered::new(),
        }
    }

    async fn run(mut self) {
        let mut pending = VecDeque::new();
        let mut preparation = None;
        let mut pending_tool_refreshes = BTreeSet::new();
        let mut tool_refresh = None;
        let mut explicit_refresh: Option<ExplicitToolRefresh> = None;
        loop {
            if !self.shutting_down && preparation.is_none() && tool_refresh.is_none() {
                if explicit_refresh.is_none() {
                    match pending.pop_front() {
                        Some(PendingMutation::Reconcile(mut request)) => {
                            if request.config_authority.is_none() {
                                request.config_authority =
                                    self.current_generation().config_authority.clone();
                            }
                            if request
                                .config_authority
                                .as_ref()
                                .is_some_and(|authority| !authority.is_active())
                            {
                                let _ = request.reply.send(Err(expired_authority_error()));
                                continue;
                            }
                            // Compare against the configuration at this serial queue position,
                            // not the older generation that was current when it was enqueued.
                            // Equal policy identities can still have independent revocation flags.
                            if request.reset_scope.is_none()
                                && match (
                                    request.config_authority.as_ref(),
                                    self.current_generation().config_authority.as_ref(),
                                ) {
                                    (None, None) => true,
                                    (Some(requested), Some(current)) => {
                                        requested.same_instance(current)
                                    }
                                    _ => false,
                                }
                                && self.current_generation().authorization.is_active()
                                && self.configuration_matches(&request.servers)
                            {
                                let _ = request.reply.send(Ok(()));
                                continue;
                            }
                            preparation = Some(self.start_preparation(request));
                        }
                        Some(PendingMutation::RefreshTools(reply)) => {
                            if let Err(error) = self.current_generation().ensure_active() {
                                let _ = reply.send(Err(error));
                                continue;
                            }
                            explicit_refresh = Some(ExplicitToolRefresh {
                                remaining: self
                                    .current_generation()
                                    .servers
                                    .keys()
                                    .cloned()
                                    .collect(),
                                servers: Vec::new(),
                                reply,
                            });
                        }
                        None => {}
                    }
                }
                if let Some(explicit) = explicit_refresh.as_mut() {
                    while let Some(server_id) = explicit.remaining.pop_front() {
                        if let Some(refresh) = self.start_tool_refresh(server_id.clone()) {
                            tool_refresh = Some(refresh);
                            break;
                        }
                        explicit.servers.push(self.skipped_tool_refresh(server_id));
                    }
                    if tool_refresh.is_none() {
                        let explicit = explicit_refresh.take().expect("completed explicit refresh");
                        let _ = explicit.reply.send(Ok(McpToolRefreshReport {
                            generation: self.current.0,
                            servers: explicit.servers,
                        }));
                        // More mutations may already be queued; do not wait for another command.
                        continue;
                    }
                } else if preparation.is_none()
                    && let Some(server_id) = pending_tool_refreshes.pop_first()
                {
                    tool_refresh = self.start_tool_refresh(server_id);
                    if tool_refresh.is_none() {
                        continue;
                    }
                }
            }
            tokio::select! {
                Some(generation) = self.requests.next(), if !self.requests.is_empty() => {
                    self.release_lease(generation);
                }
                Some(owners) = self.cleanups.next(), if !self.cleanups.is_empty() => {
                    self.restore_cleanup_owners(owners);
                }
                generation = await_preparation(&mut preparation), if preparation.is_some() => {
                    let active = preparation
                        .take()
                        .expect("completed MCP preparation must exist");
                    let result = if let Err(error) = generation.ensure_active() {
                        self.close_unpublished_generation(generation);
                        Err(error)
                    } else if active.reset_scope.as_ref().is_some_and(|scope| {
                        reset_failed(scope, &generation)
                    }) {
                        self.close_unpublished_generation(generation);
                        Err(PureError::ToolExecutionFailed {
                            tool: "mcp".to_string(),
                            error: "MCP reset candidate failed; current generation was preserved".to_string(),
                        })
                    } else {
                        self.activate_generation(generation)
                    };
                    let _ = active.reply.send(result);
                }
                candidate = await_tool_refresh(&mut tool_refresh), if tool_refresh.is_some() => {
                    tool_refresh = None;
                    if !self.shutting_down {
                        let result = self.apply_tool_refresh(candidate, &mut pending_tool_refreshes).await;
                        if let Some(explicit) = explicit_refresh.as_mut() {
                            explicit.servers.push(result);
                        }
                    }
                }
                command = self.receiver.recv() => {
                    let Some(command) = command else {
                        drop(tool_refresh.take());
                        if let Some(explicit) = explicit_refresh.take() {
                            let _ = explicit.reply.send(Err(shutting_down_error()));
                        }
                        let (unpublished, ()) = tokio::join!(
                            cancel_and_collect_reconciles(preparation.take(), &mut pending),
                            self.drain_owned_work(),
                        );
                        if let Some(mut unpublished) = unpublished
                        {
                            unpublished.retired = true;
                            self.generations.insert(unpublished.id, unpublished);
                        }
                        break;
                    };
                    match command {
                RuntimeCommand::Reconcile {
                    servers,
                    reply,
                } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    pending.push_back(PendingMutation::Reconcile(PendingReconcile {
                        servers,
                        config_authority: self.current_generation().config_authority.clone(),
                        reset_scope: None,
                        reply,
                    }));
                }
                RuntimeCommand::Reset {
                    servers,
                    scope,
                    reply,
                } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    pending.push_back(PendingMutation::Reconcile(PendingReconcile {
                        servers,
                        config_authority: self.current_generation().config_authority.clone(),
                        reset_scope: Some(scope),
                        reply,
                    }));
                }
                RuntimeCommand::ReconcileAuthorized { servers, authorization, reply } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    pending.push_back(PendingMutation::Reconcile(PendingReconcile {
                        servers,
                        config_authority: Some(authorization),
                        reset_scope: None,
                        reply,
                    }));
                }
                RuntimeCommand::ResetAuthorized { servers, scope, authorization, reply } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    pending.push_back(PendingMutation::Reconcile(PendingReconcile {
                        servers,
                        config_authority: Some(authorization),
                        reset_scope: Some(scope),
                        reply,
                    }));
                }
                RuntimeCommand::RefreshTools { reply } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    pending.push_back(PendingMutation::RefreshTools(reply));
                }
                RuntimeCommand::AcquireLease { reply } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    // Preparation is independent of a Thread's admission. A later
                    // generation update refreshes its tool directory when ready.
                    let _ = reply.send(self.acquire_lease());
                }
                RuntimeCommand::ReleaseLease { generation } => {
                    self.release_lease(generation);
                }
                RuntimeCommand::Snapshots { reply } => {
                    let _ = reply.send(self.snapshots());
                }
                RuntimeCommand::HealthSnapshot { reply } => {
                    let _ = reply.send(self.health_snapshot());
                }
                RuntimeCommand::AvailableServerNames { reply } => {
                    let _ = reply.send(self.available_server_names());
                }
                RuntimeCommand::CallTool {
                    generation,
                    server_id,
                    raw_name,
                    arguments,
                    reply,
                } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    if reply.is_closed() {
                        continue;
                    }
                    self.spawn_tool_call(generation, server_id, raw_name, arguments, reply);
                }
                RuntimeCommand::ResourceQuery {
                    generation,
                    server_id,
                    operation,
                    reply,
                } => {
                    if self.shutting_down {
                        let _ = reply.send(Err(shutting_down_error()));
                        continue;
                    }
                    if reply.is_closed() {
                        continue;
                    }
                    self.spawn_resource_query(generation, server_id, operation, reply);
                }
                RuntimeCommand::MarkUnavailable {
                    identity,
                    server_id,
                    error,
                } => self.mark_unavailable(&identity, &server_id, error),
                RuntimeCommand::ConnectionEvent { server_id, identity, event } => {
                    match event {
                        crate::mcp::connector::ConnectionEvent::Closed => {
                            self.mark_unavailable(&identity, &server_id, "MCP connection ended".into());
                        }
                        crate::mcp::connector::ConnectionEvent::ToolListChanged => {
                            if !self.shutting_down && self.current_generation().servers.get(&server_id)
                                .and_then(|server| server.session.as_ref())
                                .is_some_and(|session| Arc::ptr_eq(&session.identity, &identity)) {
                                pending_tool_refreshes.insert(server_id);
                            }
                        }
                    }
                }
                RuntimeCommand::Shutdown { reply } => {
                    self.shutting_down = true;
                    tool_refresh = None;
                    if let Some(explicit) = explicit_refresh.take() {
                        let _ = explicit.reply.send(Err(shutting_down_error()));
                    }
                    pending_tool_refreshes.clear();
                    let (unpublished, ()) = tokio::join!(
                        cancel_and_collect_reconciles(preparation.take(), &mut pending),
                        self.drain_owned_work(),
                    );
                    if let Some(mut unpublished) = unpublished
                    {
                        unpublished.retired = true;
                        self.generations.insert(unpublished.id, unpublished);
                    }
                    let result = self.shutdown().await;
                    if result.is_ok() {
                        self.shutdown_completion.record(Ok(())).await;
                        let _ = reply.send(Ok(()));
                        return;
                    }
                    // Retain the worker and its unconfirmed session owners so a subsequent
                    // `shutdown()` joins the same in-flight `ConnectedMcp::close()` tasks.
                    let _ = reply.send(result);
                }
                    }
                }
            }
        }
        let result = self.shutdown().await;
        let recorded = match &result {
            Ok(()) => Ok(()),
            Err(error) => Err(error.to_string()),
        };
        self.shutdown_completion.record(recorded).await;
    }

    fn start_preparation(&mut self, request: PendingReconcile) -> ActivePreparation {
        if let Some(scope) = &request.reset_scope {
            // A reset replaces the target's session state, not just its current catalog.
            // Stop admission through every old frozen lease, without revoking siblings
            // or interrupting requests already captured by `requests`.
            for generation in self.generations.values_mut() {
                for (server_id, server) in &mut generation.servers {
                    if matches!(scope, McpResetScope::All)
                        || matches!(scope, McpResetScope::Server { server_id: target } if target == server_id)
                    {
                        server.availability = McpAvailabilityKind::Unavailable;
                        server.message = Some("MCP session reset is in progress".into());
                    }
                }
            }
            self.emit_update();
        }
        let generation_id = McpGeneration(self.next_generation);
        self.next_generation += 1;
        let mut reusable = self.current_generation().servers.clone();
        match request.reset_scope.as_ref() {
            Some(McpResetScope::Server { server_id }) => {
                reusable.remove(server_id);
            }
            Some(McpResetScope::All) => reusable.clear(),
            None => {}
        }
        let cancel = CancellationToken::new();
        let future = prepare_generation(
            self.connector.clone(),
            generation_id,
            request.servers,
            request.config_authority,
            reusable,
            cancel.clone(),
        );
        ActivePreparation {
            future: future.boxed(),
            cancel,
            reply: request.reply,
            reset_scope: request.reset_scope,
        }
    }

    fn start_tool_refresh(&self, server_id: String) -> Option<ActiveToolRefresh> {
        self.current_generation().ensure_active().ok()?;
        let generation = self.current;
        let server = self.current_generation().servers.get(&server_id)?;
        if server.availability != McpAvailabilityKind::Available {
            return None;
        }
        let session = server.session.clone()?;
        let timeout = configured_startup_timeout(server.config.startup_timeout_secs);
        let config = server.config.clone();
        let redactor = server.redactor.clone();
        let commands = self.commands.clone();
        Some(ActiveToolRefresh {
            future: async move {
                let definitions =
                    match tokio::time::timeout(timeout, session.discover_tools()).await {
                        Ok(Ok(tools)) => Ok(filter_tool_definitions(tools, &config)),
                        Ok(Err(error)) => {
                            let message = redactor.redact(error.to_string());
                            if crate::mcp::connector::is_connection_failure(&error) {
                                let _ = commands.send(RuntimeCommand::MarkUnavailable {
                                    identity: session.identity.clone(),
                                    server_id: server_id.clone(),
                                    error: message.clone(),
                                });
                            }
                            Err(message)
                        }
                        Err(_) => Err(format!(
                            "MCP tool refresh timed out after {} seconds",
                            timeout.as_secs()
                        )),
                    };
                ToolRefreshCandidate {
                    observed_generation: generation,
                    server_id,
                    session,
                    definitions,
                }
            }
            .boxed(),
        })
    }

    async fn apply_tool_refresh(
        &mut self,
        candidate: ToolRefreshCandidate,
        pending: &mut BTreeSet<String>,
    ) -> McpServerToolRefresh {
        if self.current_generation().ensure_active().is_err() {
            return McpServerToolRefresh {
                server_id: candidate.server_id,
                status: McpToolRefreshStatus::Failed,
                tool_count: None,
                message: Some(expired_authority_error().to_string()),
            };
        }
        if candidate.observed_generation != self.current {
            if self
                .current_generation()
                .servers
                .contains_key(&candidate.server_id)
            {
                pending.insert(candidate.server_id.clone());
            }
            return self.skipped_tool_refresh(candidate.server_id);
        }
        let Some(current_server) = self.current_generation().servers.get(&candidate.server_id)
        else {
            return self.skipped_tool_refresh(candidate.server_id);
        };
        if current_server.availability != McpAvailabilityKind::Available
            || current_server
                .session
                .as_ref()
                .is_none_or(|session| !Arc::ptr_eq(session, &candidate.session))
        {
            return self.skipped_tool_refresh(candidate.server_id);
        }
        let tool_count = current_server.definitions.len();
        let definitions = match candidate.definitions {
            Ok(definitions) => definitions,
            Err(error) => {
                tracing::warn!(
                    server_id = %candidate.server_id,
                    %error,
                    "MCP tool refresh failed; preserving the current generation"
                );
                return McpServerToolRefresh {
                    server_id: candidate.server_id,
                    status: McpToolRefreshStatus::Failed,
                    tool_count: Some(tool_count),
                    message: Some(error),
                };
            }
        };
        if current_server.definitions == definitions {
            return McpServerToolRefresh {
                server_id: candidate.server_id,
                status: McpToolRefreshStatus::Unchanged,
                tool_count: Some(tool_count),
                message: None,
            };
        }
        let tool_count = definitions.len();
        let generation_id = McpGeneration(self.next_generation);
        self.next_generation += 1;
        let mut next = RuntimeGeneration::empty(generation_id);
        next.config_authority = self.current_generation().config_authority.clone();
        next.servers = self.current_generation().servers.clone();
        let Some(server) = next.servers.get_mut(&candidate.server_id) else {
            return self.skipped_tool_refresh(candidate.server_id);
        };
        server.message = Some(format!("Available with {} tools", definitions.len()));
        server.last_checked_at = Some(crate::unix_seconds());
        server.definitions = definitions;
        assign_tool_descriptors(&mut next.servers);
        if let Err(error) = self.activate_generation(next) {
            return McpServerToolRefresh {
                server_id: candidate.server_id,
                status: McpToolRefreshStatus::Failed,
                tool_count: None,
                message: Some(error.to_string()),
            };
        }
        McpServerToolRefresh {
            server_id: candidate.server_id,
            status: McpToolRefreshStatus::Updated,
            tool_count: Some(tool_count),
            message: None,
        }
    }

    fn skipped_tool_refresh(&self, server_id: String) -> McpServerToolRefresh {
        // Do not echo configuration/credential diagnostics into the explicit response.
        let message = match self.current_generation().servers.get(&server_id) {
            _ if self.current_generation().ensure_active().is_err() => {
                "MCP configuration authorization was revoked"
            }
            None => "MCP server is no longer configured",
            Some(server) => match server.availability {
                McpAvailabilityKind::Checking => "MCP server is still connecting",
                McpAvailabilityKind::Disabled => "MCP server is disabled",
                McpAvailabilityKind::MissingCredential => "MCP server has missing credentials",
                McpAvailabilityKind::Unavailable => "MCP server is unavailable",
                McpAvailabilityKind::Available => {
                    "MCP server connection changed during tool refresh"
                }
            },
        };
        McpServerToolRefresh {
            server_id,
            status: McpToolRefreshStatus::Skipped,
            tool_count: None,
            message: Some(message.to_string()),
        }
    }

    fn configuration_matches(&self, servers: &BTreeMap<String, EffectiveMcpServerConfig>) -> bool {
        let current = self.current_generation();
        current.servers.len() == servers.len()
            && servers.iter().all(|(server_id, config)| {
                current.servers.get(server_id).is_some_and(|server| {
                    server.fingerprint == server_fingerprint(config)
                        && server.matches_config(config)
                })
            })
    }

    fn activate_generation(&mut self, mut next: RuntimeGeneration) -> Result<()> {
        if let Err(error) = next.ensure_active() {
            self.close_unpublished_generation(next);
            return Err(error);
        }
        self.propagate_pending_session_failures(&mut next);
        next.freeze_authorization(self.current_generation());
        if let Some(previous) = self.generations.get_mut(&self.current) {
            previous.retired = true;
        }
        self.current = next.id;
        self.generations.insert(next.id, next);
        self.cleanup_retired();
        self.emit_update();
        Ok(())
    }

    fn close_unpublished_generation(&mut self, mut generation: RuntimeGeneration) {
        let current_sessions = self
            .current_generation()
            .servers
            .values()
            .filter_map(|server| server.session.as_ref())
            .map(|session| Arc::as_ptr(session) as usize)
            .collect::<BTreeSet<_>>();
        let sessions = unique_sessions(generation.servers.clone())
            .into_iter()
            .filter(|session| !current_sessions.contains(&(Arc::as_ptr(session) as usize)))
            .collect::<Vec<_>>();
        generation.retired = true;
        self.schedule_cleanup(vec![generation], sessions);
    }

    fn propagate_pending_session_failures(&self, next: &mut RuntimeGeneration) {
        for pending in next.servers.values_mut() {
            let Some(session) = pending.session.as_ref() else {
                continue;
            };
            if session.has_ended() {
                pending.availability = McpAvailabilityKind::Unavailable;
                pending.message = Some("MCP connection ended".into());
                continue;
            }
            let failed = self.generations.values().find_map(|generation| {
                generation.servers.values().find(|active| {
                    active.availability == McpAvailabilityKind::Unavailable
                        && active
                            .session
                            .as_ref()
                            .is_some_and(|active| Arc::ptr_eq(active, session))
                })
            });
            if let Some(failed) = failed {
                pending.availability = McpAvailabilityKind::Unavailable;
                pending.message = failed.message.clone();
                pending.last_checked_at = failed.last_checked_at;
            }
        }
    }

    fn acquire_lease(&mut self) -> Result<LeaseSnapshot> {
        let generation = self.generations.get_mut(&self.current).ok_or_else(|| {
            PureError::ToolExecutionFailed {
                tool: "mcp".to_string(),
                error: "MCP current generation is unavailable".to_string(),
            }
        })?;
        generation.ensure_active()?;
        generation.leases += 1;
        let tools = generation
            .servers
            .values()
            .filter(|server| server.availability == McpAvailabilityKind::Available)
            .flat_map(|server| server.tools.clone())
            .collect();
        let server_ids = generation
            .servers
            .values()
            .filter(|server| server.availability == McpAvailabilityKind::Available)
            .map(|server| server.descriptor.id.clone())
            .collect();
        let resource_server_ids = generation
            .servers
            .values()
            .filter(|server| {
                server.availability == McpAvailabilityKind::Available && server.supports_resources
            })
            .map(|server| server.descriptor.id.clone())
            .collect();
        Ok(LeaseSnapshot {
            generation: generation.id,
            authorization: generation.authorization.clone(),
            tools,
            server_ids,
            resource_server_ids,
        })
    }

    fn release_lease(&mut self, generation: McpGeneration) {
        if let Some(state) = self.generations.get_mut(&generation) {
            state.leases = state.leases.saturating_sub(1);
        }
        self.cleanup_retired();
    }

    fn snapshots(&self) -> BTreeMap<String, McpAvailabilitySnapshot> {
        self.current_generation()
            .servers
            .iter()
            .map(|(server_id, server)| {
                (
                    server_id.clone(),
                    McpAvailabilitySnapshot {
                        server_id: server_id.clone(),
                        availability_kind: server.availability,
                        availability_message: server.message.clone(),
                        last_checked_at: server.last_checked_at,
                        tool_count: (server.availability == McpAvailabilityKind::Available)
                            .then_some(server.tools.len()),
                    },
                )
            })
            .collect()
    }

    fn health_snapshot(&self) -> McpHealthSnapshot {
        let generation = self.current_generation();
        McpHealthSnapshot {
            generation: generation.id.0,
            servers: generation
                .servers
                .values()
                .map(|server| McpAvailabilityDescriptor {
                    server: server.descriptor.clone(),
                    availability: server.availability.as_str().to_string(),
                    message: server.message.clone(),
                    last_checked_at: server.last_checked_at,
                    tool_count: (server.availability == McpAvailabilityKind::Available)
                        .then_some(server.tools.len()),
                })
                .collect(),
        }
    }

    fn available_server_names(&self) -> Vec<String> {
        self.current_generation()
            .servers
            .values()
            .filter(|server| server.availability == McpAvailabilityKind::Available)
            .map(|server| server.descriptor.id.clone())
            .collect()
    }

    fn cleanup_retired(&mut self) {
        let retired = self
            .generations
            .iter()
            .filter(|(_, generation)| generation.retired && generation.leases == 0)
            .map(|(id, _)| *id)
            .collect::<Vec<_>>();
        let owners = retired
            .into_iter()
            .filter_map(|id| self.generations.remove(&id))
            .collect::<Vec<_>>();
        let mut candidates = BTreeMap::new();
        for generation in &owners {
            for session in generation
                .servers
                .values()
                .filter_map(|server| server.session.as_ref())
            {
                candidates
                    .entry(Arc::as_ptr(session) as usize)
                    .or_insert_with(|| session.clone());
            }
        }
        let sessions = candidates
            .into_values()
            .filter(|session| {
                // Account for the retained retry owners as well as this unique candidate.
                // Other generations and already accepted requests keep shared sessions alive.
                let local_references = owners
                    .iter()
                    .flat_map(|generation| generation.servers.values())
                    .filter(|server| {
                        server
                            .session
                            .as_ref()
                            .is_some_and(|owned| Arc::ptr_eq(owned, session))
                    })
                    .count()
                    + 1;
                Arc::strong_count(session) == local_references
            })
            .collect::<Vec<_>>();
        self.schedule_cleanup(owners, sessions);
    }

    fn schedule_cleanup(
        &mut self,
        mut owners: Vec<RuntimeGeneration>,
        sessions: Vec<Arc<crate::mcp::ConnectedMcp>>,
    ) {
        let closing = sessions
            .iter()
            .map(|session| Arc::as_ptr(session) as usize)
            .collect::<BTreeSet<_>>();
        // Shared sessions remain owned by live generations. Do not keep extra references
        // in an unrelated cleanup future that could mask their final retirement.
        for owner in &mut owners {
            owner.servers.retain(|_, server| {
                server
                    .session
                    .as_ref()
                    .is_some_and(|session| closing.contains(&(Arc::as_ptr(session) as usize)))
            });
        }
        owners.retain(|owner| !owner.servers.is_empty());
        if owners.is_empty() {
            return;
        }
        self.cleanups.push(
            async move {
                let outcomes =
                    futures::future::join_all(sessions.iter().map(|session| session.close())).await;
                let failed = sessions
                    .iter()
                    .zip(outcomes)
                    .filter_map(|(session, outcome)| {
                        outcome.err().map(|_| Arc::as_ptr(session) as usize)
                    })
                    .collect::<BTreeSet<_>>();
                for owner in &mut owners {
                    owner.servers.retain(|_, server| {
                        server.session.as_ref().is_some_and(|session| {
                            failed.contains(&(Arc::as_ptr(session) as usize))
                        })
                    });
                }
                owners.retain(|owner| !owner.servers.is_empty());
                owners
            }
            .boxed(),
        );
    }

    fn restore_cleanup_owners(&mut self, owners: Vec<RuntimeGeneration>) {
        for owner in owners {
            self.generations.insert(owner.id, owner);
        }
    }

    async fn drain_owned_work(&mut self) {
        while !self.requests.is_empty() || !self.cleanups.is_empty() {
            tokio::select! {
                Some(generation) = self.requests.next(), if !self.requests.is_empty() => {
                    if let Some(state) = self.generations.get_mut(&generation) {
                        state.leases = state.leases.saturating_sub(1);
                    }
                }
                Some(owners) = self.cleanups.next(), if !self.cleanups.is_empty() => {
                    self.restore_cleanup_owners(owners);
                }
            }
        }
    }

    /// 关闭全部 generation 的 session 并确认整树回收。
    ///
    /// 独立 session 的关闭并发发出，任一 hang 不会阻止其它 session 收到 cancel；只有
    /// 确认回收的 session 才从 generation 中移除，未确认的 owner 由 `ConnectedMcp`
    /// 自有的 close task 保留到任务结束或进程终止。返回 typed `Result`，失败带明确
    /// server id，让 runtime 能定位到具体未回收的 server 而不是泛化的 "mcp"。
    async fn shutdown(&mut self) -> Result<()> {
        // Accepted work owns its original generation even if the caller dropped its
        // receiver. Let the actual result or SDK deadline settle before closing I/O.
        self.drain_owned_work().await;
        let sessions = {
            let mut seen = BTreeSet::new();
            let mut sessions = Vec::new();
            for generation in self.generations.values() {
                for (server_id, server) in &generation.servers {
                    if let Some(session) = &server.session
                        && seen.insert(Arc::as_ptr(session) as usize)
                    {
                        sessions.push((
                            server_id.clone(),
                            session.clone(),
                            server.redactor.clone(),
                        ));
                    }
                }
            }
            sessions
        };
        let results =
            futures::future::join_all(sessions.iter().map(|(server_id, session, redactor)| {
                let server_id = server_id.clone();
                let session = session.clone();
                let redactor = redactor.clone();
                async move {
                    let outcome = session
                        .close()
                        .await
                        .map_err(|error| redactor.redact(error.to_string()));
                    (server_id, session, outcome)
                }
            }))
            .await;
        // Only drop the owner of a session whose process tree was confirmed reclaimed. An
        // unconfirmed owner stays in its generation so it is never cleared (and dropped)
        // while the tree may still be alive; it is retained until the worker — and its
        // `ConnectedMcp` close task — actually ends.
        let mut reclaimed = BTreeSet::new();
        let mut failures = Vec::new();
        for (server_id, session, outcome) in results {
            match outcome {
                Ok(()) => {
                    reclaimed.insert(Arc::as_ptr(&session) as usize);
                }
                Err(error) => failures.push(format!(
                    "MCP server '{server_id}' did not confirm process-tree reclamation: {error}"
                )),
            }
        }
        if !reclaimed.is_empty() {
            for generation in self.generations.values_mut() {
                for server in generation.servers.values_mut() {
                    if server
                        .session
                        .as_ref()
                        .is_some_and(|session| reclaimed.contains(&(Arc::as_ptr(session) as usize)))
                    {
                        server.session = None;
                    }
                }
            }
        }
        self.emit_update();
        if failures.is_empty() {
            Ok(())
        } else {
            Err(PureError::ToolExecutionFailed {
                tool: "mcp".to_string(),
                error: failures.join("; "),
            })
        }
    }

    fn current_generation(&self) -> &RuntimeGeneration {
        self.generations
            .get(&self.current)
            .expect("MCP current generation must exist")
    }

    fn emit_update(&self) {
        let _ = self.updates.send(());
    }
}

fn shutting_down_error() -> PureError {
    PureError::ToolExecutionFailed {
        tool: "mcp".to_string(),
        error: "MCP runtime is shutting down".to_string(),
    }
}

pub(super) fn expired_authority_error() -> PureError {
    PureError::ToolExecutionFailed {
        tool: "mcp".to_string(),
        error: "MCP configuration authorization was revoked".to_string(),
    }
}
