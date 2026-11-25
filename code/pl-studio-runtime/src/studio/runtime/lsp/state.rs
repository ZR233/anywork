use std::{
    collections::BTreeMap,
    sync::{Arc, PoisonError},
};

use crate::{
    ObservedResource, ObservedResourceCommand, ObservedResourceKind, StateError, StateOperation,
};
use anyhow::Error;
use pl_lsp::runtime::{
    LspActivityKind, LspAvailabilityKind, LspLifecyclePhase, LspRuntimeRegistry, LspServerSnapshot,
};
use tokio::sync::{Mutex, RwLock};

use crate::studio::ids::unix_seconds;
use crate::{
    LspAvailable, LspAvailableActivity, LspBusy, LspChecking, LspDisabled, LspIdle, LspIndexing,
    LspUnavailable, ProductEventBus, StudioLspHealth, StudioLspServer, StudioLspServerState,
    StudioLspStateSnapshot,
};

/// Stable execution endpoint, independent of transport reconnects and worker fd leases.
pub(crate) fn execution_endpoint(ssh_alias: Option<&str>) -> String {
    match ssh_alias {
        Some(alias) => format!("ssh:{alias}"),
        None => "local".to_owned(),
    }
}

/// LSP published state 的唯一 owner。
#[derive(Clone)]
pub(in crate::studio::runtime) struct LspStateRuntime {
    command_lock: Arc<Mutex<()>>,
    state: Arc<RwLock<StudioLspStateSnapshot>>,
    events: ProductEventBus,
    threads: Arc<std::sync::Mutex<ThreadLspStates>>,
    thread_refresh_lock: Arc<Mutex<()>>,
}

#[derive(Default)]
struct ThreadLspStates {
    published: BTreeMap<String, crate::StudioThreadLspStateSnapshot>,
    revision: u64,
}

pub(super) enum LspOperation {
    Activate,
    Probe,
    Reset,
}

impl LspStateRuntime {
    pub(in crate::studio::runtime) fn new(events: ProductEventBus) -> Self {
        Self {
            command_lock: Arc::new(Mutex::new(())),
            state: Arc::new(RwLock::new(StudioLspStateSnapshot {
                state: ObservedResource::uninitialized(unix_seconds()),
            })),
            events,
            threads: Arc::default(),
            thread_refresh_lock: Arc::new(Mutex::new(())),
        }
    }

    pub(super) async fn command(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.command_lock.lock().await
    }

    pub(in crate::studio::runtime) async fn read(&self) -> StudioLspStateSnapshot {
        self.state.read().await.clone()
    }

    pub(super) async fn begin(&self, operation: LspOperation) -> anyhow::Result<()> {
        let (operation, name) = match operation {
            LspOperation::Activate => (StateOperation::Activate, "activate"),
            LspOperation::Probe => (StateOperation::Probe, "probe"),
            LspOperation::Reset => (StateOperation::Reset, "reset"),
        };
        self.transition(|previous| {
            Some(ObservedResourceCommand::Begin {
                expected_revision: previous.revision(),
                operation,
                operation_id: format!("lsp-{name}-{}", previous.revision().saturating_add(1)),
                started_at: unix_seconds(),
            })
        })
        .await
    }

    pub(in crate::studio::runtime) async fn ready(
        &self,
        health: StudioLspHealth,
        checked: bool,
    ) -> anyhow::Result<()> {
        self.transition(|previous| {
            let now = unix_seconds();
            Some(ObservedResourceCommand::Succeed {
                expected_revision: previous.revision(),
                updated_at: now,
                last_checked_at: if checked {
                    latest_checked_at(&health).or(Some(now))
                } else {
                    previous.last_checked_at()
                },
                value: health,
            })
        })
        .await
    }

    pub(in crate::studio::runtime) async fn failed(&self, error: &Error) -> anyhow::Result<()> {
        self.transition(|previous| {
            Some(ObservedResourceCommand::Fail {
                expected_revision: previous.revision(),
                failed_at: unix_seconds(),
                error: StateError {
                    code: "lspOperationFailed".into(),
                    message: format!("{error:#}"),
                    retryable: true,
                },
            })
        })
        .await
    }

    pub(in crate::studio::runtime) async fn refresh(
        &self,
        health: StudioLspHealth,
    ) -> anyhow::Result<()> {
        self.transition(|previous| {
            if !matches!(
                previous.kind(),
                ObservedResourceKind::Ready
                    | ObservedResourceKind::Stale
                    | ObservedResourceKind::Degraded
            ) || previous.value() == Some(&health)
            {
                return None;
            }
            Some(ObservedResourceCommand::Observe {
                expected_revision: previous.revision(),
                observed_at: unix_seconds(),
                last_checked_at: latest_checked_at(&health).or(previous.last_checked_at()),
                value: health,
            })
        })
        .await
    }

    pub(in crate::studio::runtime) async fn stopped(&self) -> anyhow::Result<()> {
        let _command = self.command().await;
        self.transition(|previous| {
            (previous.kind() != ObservedResourceKind::Stopped).then(|| {
                ObservedResourceCommand::Stop {
                    expected_revision: previous.revision(),
                    stopped_at: unix_seconds(),
                }
            })
        })
        .await
    }

    async fn transition(
        &self,
        command: impl FnOnce(
            &ObservedResource<StudioLspHealth>,
        ) -> Option<ObservedResourceCommand<StudioLspHealth>>,
    ) -> anyhow::Result<()> {
        let mut current = self.state.write().await;
        if let Some(command) = command(&current.state) {
            let decision = current.state.decide(command)?;
            if decision.changed {
                current.state = decision.next_state;
                self.events.emit_lsp_state(current.clone());
            }
        }
        Ok(())
    }

    pub(in crate::studio::runtime) fn read_thread(
        &self,
        thread_id: &str,
    ) -> crate::StudioThreadLspStateSnapshot {
        let threads = self.threads.lock().unwrap_or_else(PoisonError::into_inner);
        threads
            .published
            .get(thread_id)
            .cloned()
            .unwrap_or_else(|| crate::StudioThreadLspStateSnapshot {
                thread_id: thread_id.to_owned(),
                revision: threads.revision,
                binding_id: None,
                servers: Vec::new(),
            })
    }

    pub(super) fn thread_ids(&self) -> Vec<String> {
        self.threads
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .published
            .keys()
            .cloned()
            .collect()
    }

    pub(super) async fn thread_refresh(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.thread_refresh_lock.lock().await
    }

    /// Caller holds the current binding/lifetime qualification. Publish under the same lock as reads.
    pub(super) fn commit_thread(
        &self,
        thread_id: &str,
        binding_id: Option<String>,
        servers: Vec<StudioLspServer>,
    ) {
        let mut threads = self.threads.lock().unwrap_or_else(PoisonError::into_inner);
        match threads.published.get(thread_id) {
            Some(current) if current.binding_id == binding_id && current.servers == servers => {
                return;
            }
            None if binding_id.is_none() => return,
            _ => {}
        }
        threads.revision = threads.revision.saturating_add(1);
        let snapshot = crate::StudioThreadLspStateSnapshot {
            thread_id: thread_id.to_owned(),
            revision: threads.revision,
            binding_id,
            servers,
        };
        if snapshot.binding_id.is_some() {
            threads
                .published
                .insert(thread_id.to_owned(), snapshot.clone());
        } else {
            threads.published.remove(thread_id);
        }
        self.events.emit_thread_lsp_state(snapshot);
    }
}

pub(super) async fn health(
    registry: &LspRuntimeRegistry,
    previous: Option<&StudioLspHealth>,
) -> StudioLspHealth {
    let snapshots = registry.snapshots().await;
    let active_lsp_servers = registry.active_server_names().await;
    StudioLspHealth {
        lsp_servers: project_servers(
            snapshots,
            previous.map_or(&[], |health| &health.lsp_servers),
        ),
        active_lsp_servers,
    }
}

pub(super) fn project_servers(
    snapshots: Vec<LspServerSnapshot>,
    previous: &[StudioLspServer],
) -> Vec<StudioLspServer> {
    let observed_at = unix_seconds();
    snapshots
        .into_iter()
        .map(|server| {
            let state = previous
                .iter()
                .filter(|current| {
                    current.id == server.id
                        && current.configuration_path == server.configuration_path
                })
                .find_map(|current| {
                    let at = server_checked_at(&current.state)?;
                    (lsp_server_state(&server, at) == current.state).then(|| current.state.clone())
                })
                .unwrap_or_else(|| lsp_server_state(&server, observed_at));
            StudioLspServer {
                state,
                id: server.id,
                configuration_path: server.configuration_path,
                phase: lsp_lifecycle_phase(server.phase).into(),
                display_name: server.display_name,
                extensions: server.extensions,
                language_ids: server.language_ids,
            }
        })
        .collect()
}

fn server_checked_at(state: &StudioLspServerState) -> Option<i64> {
    match state {
        StudioLspServerState::Available(state) => Some(state.checked_at()),
        StudioLspServerState::Unavailable(state) => Some(state.checked_at()),
        StudioLspServerState::Checking(_) | StudioLspServerState::Disabled(_) => None,
    }
}

fn lsp_lifecycle_phase(phase: LspLifecyclePhase) -> &'static str {
    match phase {
        LspLifecyclePhase::Loading => "loading",
        LspLifecyclePhase::Probing => "probing",
        LspLifecyclePhase::Starting => "starting",
        LspLifecyclePhase::Initializing => "initializing",
        LspLifecyclePhase::Ready => "ready",
        LspLifecyclePhase::Failed => "failed",
        LspLifecyclePhase::Stopped => "stopped",
        LspLifecyclePhase::Disabled => "disabled",
    }
}

fn latest_checked_at(health: &StudioLspHealth) -> Option<i64> {
    health
        .lsp_servers
        .iter()
        .filter_map(|server| server_checked_at(&server.state))
        .max()
}

fn lsp_server_state(server: &LspServerSnapshot, observed_at: i64) -> StudioLspServerState {
    match &server.availability_kind {
        LspAvailabilityKind::Checking => StudioLspServerState::Checking(LspChecking::new(
            server
                .availability_message
                .as_deref()
                .unwrap_or("LSP health check is running"),
        )),
        LspAvailabilityKind::Available => {
            let activity = match server.activity_kind {
                LspActivityKind::Idle => LspAvailableActivity::Idle(LspIdle),
                LspActivityKind::Busy => LspAvailableActivity::Busy(LspBusy::new(
                    server.activity_title.clone(),
                    server.activity_message.clone(),
                    server.activity_percentage,
                )),
                LspActivityKind::Indexing => LspAvailableActivity::Indexing(LspIndexing::new(
                    server.activity_title.clone(),
                    server.activity_message.clone(),
                    server.activity_percentage,
                )),
            };
            StudioLspServerState::Available(LspAvailable::new(
                server.last_checked_at.unwrap_or(observed_at),
                server.diagnostic_count as u64,
                activity,
            ))
        }
        LspAvailabilityKind::Disabled => StudioLspServerState::Disabled(LspDisabled::new(
            server
                .availability_message
                .as_deref()
                .unwrap_or("LSP server is disabled"),
        )),
        LspAvailabilityKind::Unavailable => {
            unavailable_lsp_state(server, observed_at, "lspServerUnavailable")
        }
        LspAvailabilityKind::MissingCommand => {
            unavailable_lsp_state(server, observed_at, "lspCommandMissing")
        }
    }
}

fn unavailable_lsp_state(
    server: &LspServerSnapshot,
    observed_at: i64,
    code: &str,
) -> StudioLspServerState {
    StudioLspServerState::Unavailable(LspUnavailable::new(
        server
            .last_error_at
            .or(server.last_checked_at)
            .unwrap_or(observed_at),
        StateError {
            code: code.to_string(),
            message: server
                .last_error
                .clone()
                .or_else(|| server.availability_message.clone())
                .unwrap_or_else(|| "LSP server is unavailable".to_string()),
            retryable: true,
        },
    ))
}
