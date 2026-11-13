use std::sync::Arc;

use anyhow::Error;
use pl_lsp::runtime::{
    LspActivityKind, LspAvailabilityKind, LspLifecyclePhase, LspRuntimeRegistry, LspServerSnapshot,
};
use pl_protocol::{
    ObservedResource, ObservedResourceCommand, ObservedResourceKind, StateError, StateOperation,
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
pub(super) struct LspStateRuntime {
    command_lock: Arc<Mutex<()>>,
    state: Arc<RwLock<StudioLspStateSnapshot>>,
    events: ProductEventBus,
    thread_states: Arc<
        std::sync::RwLock<
            std::collections::BTreeMap<String, crate::protocol::StudioThreadLspStateSnapshot>,
        >,
    >,
    thread_revision: Arc<std::sync::atomic::AtomicU64>,
    thread_commit_lock: Arc<Mutex<()>>,
    thread_refresh_lock: Arc<Mutex<()>>,
    #[cfg(test)]
    thread_snapshot_pause: Arc<std::sync::Mutex<Option<Arc<ThreadSnapshotPause>>>>,
}

#[cfg(test)]
struct ThreadSnapshotPause {
    server_id: String,
    entered: tokio::sync::watch::Sender<bool>,
    resume: tokio::sync::watch::Receiver<bool>,
}

impl LspStateRuntime {
    pub(super) fn new(events: ProductEventBus) -> Self {
        Self {
            command_lock: Arc::new(Mutex::new(())),
            state: Arc::new(RwLock::new(StudioLspStateSnapshot {
                state: ObservedResource::uninitialized(unix_seconds()),
            })),
            events,
            thread_states: Arc::new(std::sync::RwLock::new(std::collections::BTreeMap::new())),
            thread_revision: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            thread_commit_lock: Arc::new(Mutex::new(())),
            thread_refresh_lock: Arc::new(Mutex::new(())),
            #[cfg(test)]
            thread_snapshot_pause: Arc::new(std::sync::Mutex::new(None)),
        }
    }

    pub(super) async fn command(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.command_lock.lock().await
    }

    pub(super) async fn read(&self) -> StudioLspStateSnapshot {
        self.state.read().await.clone()
    }

    pub(super) async fn begin(&self, operation: StateOperation) -> anyhow::Result<()> {
        let previous = self.read().await;
        let revision = previous.state.revision();
        self.publish(StudioLspStateSnapshot {
            state: previous
                .state
                .decide(ObservedResourceCommand::Begin {
                    expected_revision: revision,
                    operation,
                    operation_id: format!(
                        "lsp-{}-{}",
                        operation_name(operation),
                        revision.saturating_add(1)
                    ),
                    started_at: unix_seconds(),
                })?
                .next_state,
        })
        .await;
        Ok(())
    }

    pub(super) async fn ready(&self, health: StudioLspHealth, checked: bool) -> anyhow::Result<()> {
        let previous = self.read().await;
        let now = unix_seconds();
        self.publish(StudioLspStateSnapshot {
            state: previous
                .state
                .decide(ObservedResourceCommand::Succeed {
                    expected_revision: previous.state.revision(),
                    updated_at: now,
                    last_checked_at: if checked {
                        latest_checked_at(&health).or(Some(now))
                    } else {
                        previous.state.last_checked_at()
                    },
                    value: health,
                })?
                .next_state,
        })
        .await;
        Ok(())
    }

    pub(super) async fn failed(&self, error: &Error) -> anyhow::Result<()> {
        let previous = self.read().await;
        self.publish(StudioLspStateSnapshot {
            state: previous
                .state
                .decide(ObservedResourceCommand::Fail {
                    expected_revision: previous.state.revision(),
                    failed_at: unix_seconds(),
                    error: StateError {
                        code: "lspOperationFailed".to_string(),
                        message: format!("{error:#}"),
                        retryable: true,
                    },
                })?
                .next_state,
        })
        .await;
        Ok(())
    }

    pub(super) async fn refresh(&self, health: StudioLspHealth) -> anyhow::Result<()> {
        let previous = self.read().await;
        if matches!(
            previous.state.kind(),
            ObservedResourceKind::Uninitialized
                | ObservedResourceKind::Loading
                | ObservedResourceKind::Refreshing
                | ObservedResourceKind::Failed
                | ObservedResourceKind::Stopped
        ) || previous.state.value() == Some(&health)
        {
            return Ok(());
        }
        self.publish(StudioLspStateSnapshot {
            state: previous
                .state
                .decide(ObservedResourceCommand::Observe {
                    expected_revision: previous.state.revision(),
                    observed_at: unix_seconds(),
                    last_checked_at: latest_checked_at(&health)
                        .or(previous.state.last_checked_at()),
                    value: health,
                })?
                .next_state,
        })
        .await;
        Ok(())
    }

    pub(super) async fn stopped(&self) -> anyhow::Result<()> {
        let previous = self.read().await;
        self.publish(StudioLspStateSnapshot {
            state: previous
                .state
                .decide(ObservedResourceCommand::Stop {
                    expected_revision: previous.state.revision(),
                    stopped_at: unix_seconds(),
                })?
                .next_state,
        })
        .await;
        Ok(())
    }

    async fn publish(&self, snapshot: StudioLspStateSnapshot) {
        *self.state.write().await = snapshot.clone();
        self.events.emit_lsp_state(snapshot);
    }

    pub(super) async fn read_thread(
        &self,
        thread_id: &str,
    ) -> crate::protocol::StudioThreadLspStateSnapshot {
        let _commit = self.thread_commit_lock.lock().await;
        self.thread_states
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .cloned()
            .unwrap_or_else(|| crate::protocol::StudioThreadLspStateSnapshot {
                thread_id: thread_id.to_owned(),
                revision: self
                    .thread_revision
                    .load(std::sync::atomic::Ordering::Acquire),
                binding_id: None,
                servers: Vec::new(),
            })
    }

    pub(super) fn thread_ids(&self) -> Vec<String> {
        self.thread_states
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .keys()
            .cloned()
            .collect()
    }

    pub(super) async fn thread_refresh(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.thread_refresh_lock.lock().await
    }

    pub(super) async fn thread_commit(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.thread_commit_lock.lock().await
    }

    #[cfg(test)]
    pub(crate) fn pause_thread_snapshot_for_test(
        &self,
        server_id: impl Into<String>,
    ) -> (
        tokio::sync::watch::Receiver<bool>,
        tokio::sync::watch::Sender<bool>,
    ) {
        let (entered, entered_receiver) = tokio::sync::watch::channel(false);
        let (resume, resume_receiver) = tokio::sync::watch::channel(false);
        *self
            .thread_snapshot_pause
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) =
            Some(Arc::new(ThreadSnapshotPause {
                server_id: server_id.into(),
                entered,
                resume: resume_receiver,
            }));
        (entered_receiver, resume)
    }

    #[cfg(test)]
    pub(crate) async fn pause_after_thread_snapshot_for_test(&self, servers: &[StudioLspServer]) {
        let pause = self
            .thread_snapshot_pause
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(pause) = pause
            && servers.iter().any(|server| server.id == pause.server_id)
        {
            pause.entered.send_replace(true);
            let mut resume = pause.resume.clone();
            let _ = resume.wait_for(|released| *released).await;
        }
    }

    /// Caller holds `thread_commit_lock` and the current binding/lifetime qualification.
    pub(super) fn commit_thread(
        &self,
        thread_id: String,
        binding_id: Option<String>,
        servers: Vec<StudioLspServer>,
    ) -> crate::protocol::StudioThreadLspStateSnapshot {
        {
            let states = self
                .thread_states
                .read()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match (&binding_id, states.get(&thread_id)) {
                (Some(binding_id), Some(current))
                    if current.binding_id.as_ref() == Some(binding_id)
                        && current.servers == servers =>
                {
                    return current.clone();
                }
                (None, None) => {
                    return crate::protocol::StudioThreadLspStateSnapshot {
                        thread_id,
                        revision: self
                            .thread_revision
                            .load(std::sync::atomic::Ordering::Acquire),
                        binding_id: None,
                        servers,
                    };
                }
                _ => {}
            }
        }
        let revision = self
            .thread_revision
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel)
            .saturating_add(1);
        let snapshot = crate::protocol::StudioThreadLspStateSnapshot {
            thread_id: thread_id.clone(),
            revision,
            binding_id,
            servers,
        };
        {
            let mut states = self
                .thread_states
                .write()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if snapshot.binding_id.is_some() {
                states.insert(thread_id, snapshot.clone());
            } else {
                states.remove(&thread_id);
            }
            self.events.emit_thread_lsp_state(snapshot.clone());
        }
        snapshot
    }
}

pub(super) async fn health(registry: &LspRuntimeRegistry) -> StudioLspHealth {
    let snapshots = registry.snapshots().await;
    let active_lsp_servers = registry.active_server_names().await;
    let observed_at = unix_seconds();
    StudioLspHealth {
        lsp_servers: snapshots
            .into_iter()
            .map(|server| StudioLspServer {
                state: lsp_server_state(&server, observed_at),
                id: server.id,
                configuration_path: server.configuration_path,
                phase: lsp_lifecycle_phase(server.phase).to_string(),
                display_name: server.display_name,
                extensions: server.extensions,
                language_ids: server.language_ids,
            })
            .collect(),
        active_lsp_servers,
    }
}

pub(super) fn lsp_lifecycle_phase(phase: LspLifecyclePhase) -> &'static str {
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
        .filter_map(|server| match &server.state {
            StudioLspServerState::Available(state) => Some(state.checked_at()),
            StudioLspServerState::Unavailable(state) => Some(state.checked_at()),
            StudioLspServerState::Checking(_) | StudioLspServerState::Disabled(_) => None,
        })
        .max()
}

pub(super) fn lsp_server_state(
    server: &LspServerSnapshot,
    observed_at: i64,
) -> StudioLspServerState {
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

fn operation_name(operation: StateOperation) -> &'static str {
    match operation {
        StateOperation::Initialize => "initialize",
        StateOperation::Activate => "activate",
        StateOperation::Reload => "reload",
        StateOperation::Reconcile => "reconcile",
        StateOperation::Discover => "discover",
        StateOperation::Check => "check",
        StateOperation::Probe => "probe",
        StateOperation::Repair => "repair",
        StateOperation::Reset => "reset",
        StateOperation::Shutdown => "shutdown",
    }
}
