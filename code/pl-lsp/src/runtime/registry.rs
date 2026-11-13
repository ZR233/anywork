//! Workspace-scoped runtime ownership and managed background work.
use super::{
    LspActivityKind, LspAvailabilityKind, LspLifecyclePhase, LspResult, LspRuntimeError,
    LspServerSnapshot, ResolvedLspServer,
};
use crate::catalog::LspUserServerConfig;
use crate::client::LspClient;
use crate::host::LspHostBackend;
use crate::query::{LspDiagnostic, LspQuery, LspQueryResult};
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock, broadcast};
use tokio_util::sync::CancellationToken;

/// A join handle is retained until the task has actually finished, even if a
/// shutdown caller is cancelled while awaiting it.
pub(super) type ManagedTask = Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>;

pub(super) async fn join_task(task: &ManagedTask) -> Result<(), tokio::task::JoinError> {
    let mut guard = task.lock().await;
    let result = match guard.as_mut() {
        Some(task) => task.await,
        None => return Ok(()),
    };
    guard.take();
    result
}

#[derive(Clone)]
pub struct LspRuntimeRegistry {
    pub(super) state: Arc<Mutex<LspRuntimeState>>,
    pub(super) lifecycle: Arc<RwLock<()>>,
    pub(super) updates: broadcast::Sender<()>,
    pub(super) directories: super::lease::DirectoryLeases,
    scopes: std::sync::Weak<std::sync::Mutex<ExecutionScopes>>,
    _scope_owner: Option<Arc<std::sync::Mutex<ExecutionScopes>>>,
    pub(super) is_global: bool,
}

#[derive(Clone, Default)]
struct ExecutionPartition {
    state: Arc<Mutex<LspRuntimeState>>,
    lifecycle: Arc<RwLock<()>>,
    directories: super::lease::DirectoryLeases,
}

#[derive(Default)]
struct ExecutionScopes {
    partitions: BTreeMap<String, ExecutionPartition>,
    closed: bool,
}
impl std::fmt::Debug for LspRuntimeRegistry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LspRuntimeRegistry").finish_non_exhaustive()
    }
}
impl Default for LspRuntimeRegistry {
    fn default() -> Self {
        Self::new()
    }
}
impl LspRuntimeRegistry {
    pub fn new() -> Self {
        let (updates, _) = broadcast::channel(64);
        let scopes = Arc::new(std::sync::Mutex::new(ExecutionScopes::default()));
        Self {
            state: Arc::new(Mutex::new(LspRuntimeState::default())),
            lifecycle: Arc::new(RwLock::new(())),
            updates,
            directories: Default::default(),
            scopes: Arc::downgrade(&scopes),
            _scope_owner: Some(scopes),
            is_global: true,
        }
    }
    /// Stable endpoint view. Partitions retain state, never registry views, so
    /// the global owner and its endpoint views do not form an ownership cycle.
    pub fn execution_scope(&self, endpoint: &str) -> Self {
        let Some(owner) = self.scopes.upgrade() else {
            return Self {
                state: Arc::new(Mutex::new(LspRuntimeState {
                    closed: true,
                    ..Default::default()
                })),
                lifecycle: Default::default(),
                updates: self.updates.clone(),
                directories: Default::default(),
                scopes: self.scopes.clone(),
                _scope_owner: None,
                is_global: false,
            };
        };
        let mut scopes = owner.lock().expect("LSP execution scopes are not poisoned");
        let closed = scopes.closed;
        let partition = scopes
            .partitions
            .entry(endpoint.to_owned())
            .or_insert_with(|| ExecutionPartition {
                state: Arc::new(Mutex::new(LspRuntimeState {
                    closed,
                    ..Default::default()
                })),
                lifecycle: Default::default(),
                directories: Default::default(),
            })
            .clone();
        Self {
            state: partition.state,
            lifecycle: partition.lifecycle,
            directories: partition.directories,
            updates: self.updates.clone(),
            scopes: self.scopes.clone(),
            _scope_owner: None,
            is_global: false,
        }
    }

    pub(super) fn partition_views(&self) -> Vec<Self> {
        let mut current = self.clone();
        current.is_global = false;
        current._scope_owner = None;
        let mut views = vec![current];
        if self.is_global {
            let owner = self
                .scopes
                .upgrade()
                .expect("global LSP registry retains scope ownership");
            let scopes = owner.lock().expect("LSP execution scopes are not poisoned");
            views.extend(scopes.partitions.values().map(|partition| Self {
                state: partition.state.clone(),
                lifecycle: partition.lifecycle.clone(),
                directories: partition.directories.clone(),
                updates: self.updates.clone(),
                scopes: self.scopes.clone(),
                _scope_owner: None,
                is_global: false,
            }));
        }
        views
    }
    pub fn subscribe(&self) -> broadcast::Receiver<()> {
        self.updates.subscribe()
    }
    pub async fn query(&self, query: LspQuery) -> LspResult<LspQueryResult> {
        let root = self.workspace_root_for_query(&query).await?;
        self.query_in_workspace(root, query).await
    }
    pub async fn shutdown(&self) -> LspResult<()> {
        if !self.is_global {
            return self.shutdown_partition().await;
        }
        self.scopes
            .upgrade()
            .expect("global LSP registry retains scope ownership")
            .lock()
            .expect("LSP execution scopes are not poisoned")
            .closed = true;
        let views = self.partition_views();
        let outcomes = futures::future::join_all(views.iter().map(Self::shutdown_partition)).await;
        let failures: Vec<_> = outcomes
            .into_iter()
            .filter_map(Result::err)
            .map(|error| error.to_string())
            .collect();
        if failures.is_empty() {
            Ok(())
        } else {
            Err(LspRuntimeError::Unavailable(failures.join("; ")))
        }
    }

    async fn shutdown_partition(&self) -> LspResult<()> {
        let _guard = self.lifecycle.write().await;
        let roots = {
            let mut state = self.state.lock().await;
            state.closed = true;
            for workspace in state.workspaces.values_mut() {
                workspace.scan_cancel.cancel();
                for server in workspace.servers.values_mut() {
                    server.cancel.cancel();
                    if let Some(client) = &server.client {
                        client.cancel();
                    }
                }
            }
            state.workspaces.keys().cloned().collect::<Vec<_>>()
        };
        let (leased_roots, mut failures) = self.close_directory_users().await;
        // Until callers of the old bare configuration entry points are migrated,
        // global shutdown must also reclaim workspaces without directory users.
        failures.extend(
            futures::future::join_all(
                roots
                    .iter()
                    .filter(|root| !leased_roots.contains(root))
                    .map(|root| self.reclaim_workspace(root)),
            )
            .await
            .into_iter()
            .filter_map(Result::err)
            .map(|error| error.to_string()),
        );
        self.emit_update();
        if failures.is_empty() {
            Ok(())
        } else {
            Err(LspRuntimeError::Unavailable(format!(
                "LSP shutdown failed: {}",
                failures.join("; ")
            )))
        }
    }
    pub(crate) fn emit_update(&self) {
        let _ = self.updates.send(());
    }
}
pub(super) fn workspace_key(root: &std::path::Path) -> PathBuf {
    root.to_path_buf()
}
#[derive(Default)]
pub(super) struct LspRuntimeState {
    pub workspaces: BTreeMap<PathBuf, LspWorkspaceState>,
    pub closed: bool,
}
#[derive(Default)]
pub(super) struct LspWorkspaceState {
    pub tasks: Vec<ManagedTask>,
    pub retired_clients: Vec<Arc<LspClient>>,
    pub configured: bool,
    pub has_scanned: bool,
    pub scan_pending: bool,
    pub servers: BTreeMap<String, LspRuntimeServerState>,
    pub host: Option<Arc<dyn LspHostBackend>>,
    pub defaults: BTreeMap<String, LspUserServerConfig>,
    pub defaults_directory: Option<PathBuf>,
    pub binding_identity: Option<String>,
    pub scan_generation: u64,
    pub member_generation: u64,
    pub scan_cancel: CancellationToken,
    pub errors: Vec<LspServerSnapshot>,
    pub retiring: BTreeMap<String, (ManagedTask, Arc<LspClient>)>,
}
pub(super) struct LspRuntimeServerState {
    pub diagnostics: Arc<Mutex<HashMap<String, Vec<LspDiagnostic>>>>,
    pub resolved: ResolvedLspServer,
    pub fingerprint: String,
    pub configuration_path: Option<String>,
    pub phase: LspLifecyclePhase,
    pub availability_kind: LspAvailabilityKind,
    pub availability_message: Option<String>,
    pub last_checked_at: Option<i64>,
    pub client: Option<Arc<LspClient>>,
    pub generation: u64,
    pub cancel: CancellationToken,
    pub task: Option<ManagedTask>,
}
impl LspRuntimeServerState {
    pub fn healthy(&self) -> bool {
        self.phase == LspLifecyclePhase::Ready
            && self.client.as_ref().is_some_and(|client| client.is_ready())
    }
    pub fn set_phase(&mut self, phase: LspLifecyclePhase, message: Option<String>) {
        self.phase = phase;
        self.availability_kind = match phase {
            LspLifecyclePhase::Ready => LspAvailabilityKind::Available,
            LspLifecyclePhase::Disabled => LspAvailabilityKind::Disabled,
            LspLifecyclePhase::Failed | LspLifecyclePhase::Stopped => {
                LspAvailabilityKind::Unavailable
            }
            _ => LspAvailabilityKind::Checking,
        };
        self.availability_message = message;
        self.last_checked_at = Some(crate::clock::unix_seconds());
    }
    pub fn snapshot(&self, diagnostic_count: usize) -> LspServerSnapshot {
        // Liveness is an atomic read, not a probe or restart.
        let exited = self.phase == LspLifecyclePhase::Ready && !self.healthy();
        LspServerSnapshot {
            id: self.resolved.id.clone(),
            configuration_path: self.configuration_path.clone(),
            phase: if exited {
                LspLifecyclePhase::Failed
            } else {
                self.phase
            },
            display_name: self.resolved.display_name.clone(),
            extensions: self.resolved.extensions.clone(),
            language_ids: self.resolved.language_ids.clone(),
            availability_kind: if exited {
                LspAvailabilityKind::Unavailable
            } else {
                self.availability_kind.clone()
            },
            availability_message: if exited {
                Some("LSP connection closed".into())
            } else {
                self.availability_message.clone()
            },
            last_checked_at: self.last_checked_at,
            diagnostic_count,
            activity_kind: LspActivityKind::Idle,
            activity_title: None,
            activity_message: None,
            activity_percentage: None,
            last_error: None,
            last_error_at: None,
        }
    }
}
