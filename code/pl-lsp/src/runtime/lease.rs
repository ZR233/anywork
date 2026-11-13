//! Directory users and registry-owned, cancellation-safe final reclamation.
use super::registry::{ManagedTask, join_task};
use super::{
    LspAvailabilityKind, LspLifecyclePhase, LspResult, LspRuntimeError, LspRuntimeRegistry,
};
use crate::host::LspHostBackend;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

pub(super) type DirectoryLeases = Arc<Mutex<BTreeMap<PathBuf, Arc<DirectoryLease>>>>;

#[derive(Default)]
pub(super) struct DirectoryLease {
    gate: tokio::sync::Mutex<()>,
    members: Mutex<DirectoryMembers>,
}

#[derive(Default)]
struct DirectoryMembers {
    users: usize,
    closing: bool,
    closed: bool,
    release: Option<ReleaseTask>,
}

#[derive(Clone)]
struct ReleaseTask {
    task: ManagedTask,
    result: Arc<Mutex<Option<Result<(), String>>>>,
}

impl ReleaseTask {
    fn finished(&self) -> bool {
        self.task
            .try_lock()
            .is_ok_and(|task| task.as_ref().is_none_or(|task| task.is_finished()))
    }

    async fn wait(&self) -> LspResult<()> {
        join_task(&self.task)
            .await
            .map_err(|error| LspRuntimeError::Unavailable(error.to_string()))?;
        self.result
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
            .unwrap_or_else(|| Err("LSP directory reclamation did not complete".into()))
            .map_err(LspRuntimeError::Unavailable)
    }
}

struct WorkspaceUser {
    registry: LspRuntimeRegistry,
    root: PathBuf,
    directory: Arc<DirectoryLease>,
    closed: AtomicBool,
    runtime: tokio::runtime::Handle,
}

impl WorkspaceUser {
    fn release(&self) -> Option<ReleaseTask> {
        let mut members = self
            .directory
            .members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if members.closed {
            self.closed.store(true, Ordering::Release);
            return if members.closing {
                Some(start_release(
                    &self.registry,
                    &self.root,
                    &self.directory,
                    &self.runtime,
                    &mut members,
                ))
            } else {
                members.release.clone()
            };
        }
        if !self.closed.swap(true, Ordering::AcqRel) {
            members.users -= 1;
            if members.users != 0 {
                return None;
            }
            members.closing = true;
        } else if !members.closing {
            return None;
        }
        Some(start_release(
            &self.registry,
            &self.root,
            &self.directory,
            &self.runtime,
            &mut members,
        ))
    }
}

impl Drop for WorkspaceUser {
    fn drop(&mut self) {
        self.release();
    }
}

/// One directory user. Clones share that user; closing any clone invalidates all
/// of them. A distinct acquisition is required for each independent Thread.
#[derive(Clone)]
pub struct LspWorkspaceLease(Arc<WorkspaceUser>);

impl std::fmt::Debug for LspWorkspaceLease {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LspWorkspaceLease")
            .field("root", &self.0.root)
            .field("closed", &self.is_closed())
            .finish()
    }
}

impl LspWorkspaceLease {
    pub fn workspace_root(&self) -> &Path {
        &self.0.root
    }

    pub fn is_closed(&self) -> bool {
        self.0.closed.load(Ordering::Acquire)
            || self
                .0
                .directory
                .members
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .closed
    }

    /// Release this user immediately and await final reclamation when it was the
    /// last user. Starting close is synchronous so cancelled callers, synchronous
    /// binding replacement and Drop all leave cleanup owned by the registry.
    /// Repeating close retries an unsuccessful final reclamation.
    pub fn close(&self) -> impl Future<Output = LspResult<()>> + Send + 'static {
        let task = self.0.release();
        self.0.registry.emit_update();
        async move {
            match task {
                Some(task) => task.wait().await,
                None => Ok(()),
            }
        }
    }

    /// Refresh the existing user's execution binding after tool/transport
    /// refresh. This never acquires another directory reference.
    pub async fn refresh_configuration(
        &self,
        host: Option<Arc<dyn LspHostBackend>>,
        defaults_directory: Option<PathBuf>,
    ) -> LspResult<()> {
        let _lifecycle = self.0.registry.lifecycle.read().await;
        let _gate = self.0.directory.gate.lock().await;
        if self.is_closed() {
            return Err(LspRuntimeError::Unavailable(
                "LSP workspace lease is closed".into(),
            ));
        }
        self.0
            .registry
            .bind_workspace(&self.0.root, host, BTreeMap::new(), defaults_directory)
            .await;
        self.0
            .registry
            .refresh_workspace_configuration(&self.0.root)
            .await;
        Ok(())
    }

    /// Wait for the current scan and each member's initialization outcome, not
    /// for their long-running lifetime tasks. Used by explicit short-lived probes.
    pub async fn wait_initialized(&self) -> LspResult<()> {
        let mut updates = self.0.registry.subscribe();
        loop {
            if self.is_closed() {
                return Err(LspRuntimeError::Unavailable(
                    "LSP workspace lease is closed".into(),
                ));
            }
            let state = self.0.registry.state.lock().await;
            let workspace = state.workspaces.get(&self.0.root).ok_or_else(|| {
                LspRuntimeError::Unavailable("LSP workspace is not configured".into())
            })?;
            let finished = workspace.has_scanned
                && !workspace.scan_pending
                && workspace.servers.values().all(|server| {
                    matches!(
                        server.phase,
                        LspLifecyclePhase::Ready
                            | LspLifecyclePhase::Failed
                            | LspLifecyclePhase::Disabled
                            | LspLifecyclePhase::Stopped
                    )
                });
            drop(state);
            if finished {
                return Ok(());
            }
            let _ = updates.recv().await;
        }
    }
}

fn start_release(
    registry: &LspRuntimeRegistry,
    root: &Path,
    directory: &Arc<DirectoryLease>,
    runtime: &tokio::runtime::Handle,
    members: &mut DirectoryMembers,
) -> ReleaseTask {
    if let Some(task) = &members.release
        && !task.finished()
    {
        return task.clone();
    }
    let result = Arc::new(Mutex::new(None));
    let outcome = result.clone();
    let owner = registry.clone();
    let root = root.to_owned();
    let directory = directory.clone();
    let task = runtime.spawn(async move {
        let _gate = directory.gate.lock().await;
        let result = owner.reclaim_workspace(&root).await;
        if result.is_ok() {
            directory
                .members
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .closing = false;
        }
        *outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) =
            Some(result.map_err(|error| error.to_string()));
        owner.emit_update();
    });
    let task = ReleaseTask {
        task: Arc::new(tokio::sync::Mutex::new(Some(task))),
        result,
    };
    members.release = Some(task.clone());
    task
}

impl LspRuntimeRegistry {
    /// Acquire a user in this stable execution endpoint. `root` must be the
    /// execution host's canonical workspace root (not a local alias of SSH paths).
    /// Configuration preparation is managed in the background.
    pub async fn acquire_workspace(
        &self,
        root: impl AsRef<Path>,
        host: Option<Arc<dyn LspHostBackend>>,
        defaults_directory: Option<PathBuf>,
    ) -> LspResult<LspWorkspaceLease> {
        let root = root.as_ref().to_owned();
        let _lifecycle = self.lifecycle.read().await;
        if self.state.lock().await.closed {
            return Err(LspRuntimeError::Unavailable(
                "LSP runtime is stopped".into(),
            ));
        }
        let directory = self
            .directories
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(root.clone())
            .or_default()
            .clone();
        let runtime = tokio::runtime::Handle::current();
        loop {
            let gate = directory.gate.lock().await;
            let pending = {
                let mut members = directory
                    .members
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if members.closing {
                    Some(start_release(
                        self,
                        &root,
                        &directory,
                        &runtime,
                        &mut members,
                    ))
                } else {
                    members.users += 1;
                    None
                }
            };
            if let Some(task) = pending {
                drop(gate);
                task.wait().await?;
                continue;
            }
            // Construct the drop guard before any further await: cancellation
            // during assembly must not strand the newly registered user.
            let lease = LspWorkspaceLease(Arc::new(WorkspaceUser {
                registry: self.clone(),
                root: root.clone(),
                directory: directory.clone(),
                closed: AtomicBool::new(false),
                runtime,
            }));
            // Binding compares the live execution identity, not just the directory
            // path. Equivalent handles preserve healthy servers; a genuinely replaced
            // SSH workspace must not keep using the previous host.
            self.bind_workspace(&root, host, BTreeMap::new(), defaults_directory)
                .await;
            return Ok(lease);
        }
    }

    pub(super) async fn close_directory_users(&self) -> (Vec<PathBuf>, Vec<String>) {
        let runtime = tokio::runtime::Handle::current();
        let (roots, tasks): (Vec<_>, Vec<_>) = self
            .directories
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .map(|(root, directory)| {
                let mut members = directory
                    .members
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                members.closed = true;
                members.closing = true;
                (
                    root.clone(),
                    start_release(self, root, directory, &runtime, &mut members),
                )
            })
            .unzip();
        let failures = futures::future::join_all(tasks.iter().map(ReleaseTask::wait))
            .await
            .into_iter()
            .filter_map(Result::err)
            .map(|error| error.to_string())
            .collect();
        (roots, failures)
    }

    pub(super) async fn reclaim_workspace(&self, root: &Path) -> LspResult<()> {
        let summaries = self.snapshots_for_workspace(root).await;
        let tasks = {
            let mut state = self.state.lock().await;
            let Some(workspace) = state.workspaces.get_mut(root) else {
                return Ok(());
            };
            workspace.configured = false;
            workspace.scan_cancel.cancel();
            for server in workspace.servers.values_mut() {
                server.cancel.cancel();
                if let Some(client) = &server.client {
                    client.cancel();
                }
            }
            workspace.tasks.clone()
        };
        let mut failures: Vec<_> = futures::future::join_all(tasks.iter().map(join_task))
            .await
            .into_iter()
            .filter_map(Result::err)
            .map(|error| error.to_string())
            .collect();
        let clients = {
            let state = self.state.lock().await;
            let workspace = state.workspaces.get(root).expect("owned workspace");
            let mut clients = workspace.retired_clients.clone();
            clients.extend(
                workspace
                    .servers
                    .values()
                    .filter_map(|server| server.client.clone()),
            );
            clients.extend(
                workspace
                    .retiring
                    .values()
                    .map(|(_, client)| client.clone()),
            );
            clients.sort_by_key(|client| Arc::as_ptr(client) as usize);
            clients.dedup_by_key(|client| Arc::as_ptr(client) as usize);
            clients
        };
        failures.extend(
            futures::future::join_all(clients.iter().map(|client| client.shutdown()))
                .await
                .into_iter()
                .filter_map(Result::err)
                .map(|error| error.to_string()),
        );
        if !failures.is_empty() {
            return Err(LspRuntimeError::Unavailable(format!(
                "LSP directory reclamation failed: {}",
                failures.join("; ")
            )));
        }
        let mut state = self.state.lock().await;
        let workspace = state.workspaces.get_mut(root).expect("owned workspace");
        workspace.errors = summaries
            .into_iter()
            .map(|mut snapshot| {
                if snapshot.phase == LspLifecyclePhase::Ready {
                    snapshot.phase = LspLifecyclePhase::Stopped;
                    snapshot.availability_kind = LspAvailabilityKind::Unavailable;
                    snapshot.availability_message =
                        Some("LSP workspace released after successful initialization".into());
                } else if matches!(
                    snapshot.phase,
                    LspLifecyclePhase::Loading
                        | LspLifecyclePhase::Probing
                        | LspLifecyclePhase::Starting
                        | LspLifecyclePhase::Initializing
                ) {
                    snapshot.phase = LspLifecyclePhase::Stopped;
                    snapshot.availability_kind = LspAvailabilityKind::Unavailable;
                    snapshot.availability_message =
                        Some("LSP workspace released during preparation".into());
                }
                snapshot.diagnostic_count = 0;
                snapshot.activity_kind = super::LspActivityKind::Idle;
                snapshot.activity_title = None;
                snapshot.activity_message = None;
                snapshot.activity_percentage = None;
                snapshot
            })
            .collect();
        workspace.servers.clear();
        workspace.tasks.clear();
        workspace.retiring.clear();
        workspace.retired_clients.clear();
        workspace.host = None;
        workspace.binding_identity = None;
        workspace.defaults.clear();
        workspace.defaults_directory = None;
        workspace.has_scanned = false;
        self.emit_update();
        Ok(())
    }
}
