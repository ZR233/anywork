use anyhow::{Context, Result};

use super::super::StudioRuntime;
use super::super::background_task::{self, BackgroundTask};
use super::super::lsp_state::health;

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn refresh_thread_lsp_states(&self) -> Result<()> {
        let _refresh = self.external_runtimes.lsp_state.thread_refresh().await;
        let bindings = self.thread_factory.binding_snapshots();
        let known_ids = bindings
            .keys()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>();
        for (thread_id, binding) in bindings {
            let lease = binding.lsp_lease.as_ref();
            let endpoint =
                super::super::lsp_state::execution_endpoint(binding.project.ssh_alias.as_deref());
            let root = lease.map(|lease| lease.workspace_root().to_path_buf());
            let captured_binding_id = binding.lsp_binding_id.clone();
            let should_read = captured_binding_id.is_some()
                && !binding.target_invalidated
                && !binding.lifetime.cancellation.is_cancelled()
                && lease.is_some_and(|lease| !lease.is_closed());
            let servers = if should_read {
                let registry = self.external_runtimes.lsp.execution_scope(&endpoint);
                let snapshots = registry
                    .snapshots_for_workspace(root.as_ref().expect("lease root").as_path())
                    .await;
                let observed_at = crate::studio::ids::unix_seconds();
                snapshots
                    .iter()
                    .map(|server| crate::StudioLspServer {
                        state: super::super::lsp_state::lsp_server_state(server, observed_at),
                        id: server.id.clone(),
                        configuration_path: server.configuration_path.clone(),
                        phase: super::super::lsp_state::lsp_lifecycle_phase(server.phase).into(),
                        display_name: server.display_name.clone(),
                        extensions: server.extensions.clone(),
                        language_ids: server.language_ids.clone(),
                    })
                    .collect()
            } else {
                Vec::new()
            };
            #[cfg(test)]
            self.external_runtimes
                .lsp_state
                .pause_after_thread_snapshot_for_test(&servers)
                .await;
            let _commit = self.external_runtimes.lsp_state.thread_commit().await;
            let expected = crate::studio::thread_factory::LspProjectionBinding {
                incarnation: &binding.incarnation,
                binding_id: captured_binding_id.as_deref(),
                endpoint: Some(endpoint.as_str()),
                root: root.as_deref(),
            };
            let published_thread_id = thread_id.clone();
            let published_binding_id = captured_binding_id.clone();
            self.thread_factory
                .commit_lsp_projection(&thread_id, Some(expected), |valid| {
                    self.external_runtimes.lsp_state.commit_thread(
                        published_thread_id,
                        valid.then(|| published_binding_id.expect("valid binding has ID")),
                        if valid { servers } else { Vec::new() },
                    )
                });
        }
        for thread_id in self.external_runtimes.lsp_state.thread_ids() {
            if !known_ids.contains(&thread_id) {
                let _commit = self.external_runtimes.lsp_state.thread_commit().await;
                let published_thread_id = thread_id.clone();
                self.thread_factory
                    .commit_lsp_projection(&thread_id, None, |valid| {
                        if !valid {
                            self.external_runtimes.lsp_state.commit_thread(
                                published_thread_id,
                                None,
                                Vec::new(),
                            );
                        }
                    });
            }
        }
        Ok(())
    }

    pub(in crate::studio::runtime) fn check_thread_read_access(
        &self,
        thread: &pl_protocol::Thread,
    ) -> Result<()> {
        self.recovery.ensure_thread_read_access(thread)
    }

    pub(in crate::studio::runtime) fn check_thread_execution_access(
        &self,
        thread: &pl_protocol::Thread,
    ) -> Result<()> {
        self.recovery.ensure_thread_execution_access(thread)
    }

    pub(in crate::studio::runtime) async fn verify_thread_execution_preparation(
        &self,
        thread: &pl_protocol::Thread,
        snapshot: Option<&pl_core::thread::ThreadSnapshot>,
    ) -> Result<()> {
        // Resource validation can retain a cold checkpoint while composing local/SSH IO.
        // Keep that state out of both the live preflight and the ancestry loop's future.
        let result = Box::pin(self.thread_factory.verify_execution_workspace(
            thread,
            snapshot,
            crate::studio::thread_factory::ExecutionWorkspaceCheck::Prepare,
        ))
        .await;
        let state = self
            .recovery
            .apply_execution_workspace_check(thread, result.as_ref().err());
        self.agent_facility
            .product_events
            .emit_recovery_state(state);
        result
    }

    /// 订阅 pin：guard 存活期间该线程不参与 LRU 淘汰，Drop 时自动解除。
    ///
    /// bridge 订阅 producer task 持有该 guard——订阅取消/流关闭即解除 pin。
    pub fn pin_thread(&self, thread_id: &str) -> ThreadResidencyPin {
        self.residency.pin(thread_id);
        ThreadResidencyPin {
            runtime: self.clone(),
            thread_id: thread_id.to_string(),
        }
    }

    pub(in crate::studio::runtime) async fn read_protocol_thread(
        &self,
        thread_id: &str,
    ) -> Result<pl_protocol::Thread> {
        if let Some(thread) = self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)?
        {
            return Ok(thread);
        }
        // 冷数据回源：未驻留 Thread 的目录元数据只从 `catalog.toml` 读取。
        let Some(record) = self.store.read_thread(thread_id).await? else {
            // An unknown Thread is an API-visible rejection: answering it as an internal failure
            // would hide a deleted or foreign identity behind a redacted 500.
            return Err(anyhow::Error::new(
                pl_protocol::studio::StudioError::not_found("session"),
            ));
        };
        Ok(pl_protocol::Thread::from(record))
    }

    pub(super) async fn start_lsp_state_watcher(&self) {
        let mut watcher = self.external_runtimes.lsp_state_watcher.lock().await;
        if watcher.as_ref().is_some_and(|handle| !handle.is_finished()) {
            return;
        }
        let runtime = self.clone();
        let mut updates = self.external_runtimes.lsp.subscribe();
        let binding_updates = self.thread_factory.lsp_binding_updates();
        // Threads can prepare services without navigating through project activation.
        // Establish the initial published cut before forwarding background lifecycle changes.
        {
            let _command = self.external_runtimes.lsp_state.command().await;
            let initial = health(&self.external_runtimes.lsp).await;
            if let Err(error) = self
                .external_runtimes
                .lsp_state
                .begin(pl_protocol::StateOperation::Activate)
                .await
            {
                tracing::warn!(%error, "failed to begin LSP observed state");
            } else if let Err(error) = self.external_runtimes.lsp_state.ready(initial, false).await
            {
                tracing::warn!(%error, "failed to publish initial LSP observed state");
            }
        }
        if let Err(error) = self.refresh_thread_lsp_states().await {
            tracing::warn!(%error, "failed to publish initial Thread LSP states");
        }
        *watcher = Some(BackgroundTask::new(tokio::spawn(async move {
            let binding_updates = binding_updates.notified_owned();
            tokio::pin!(binding_updates);
            loop {
                tokio::select! {
                    event = updates.recv() => match event {
                        Ok(()) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                    },
                    _ = &mut binding_updates => {
                        binding_updates.set(runtime.thread_factory.lsp_binding_updates().notified_owned());
                    }
                }
                let health = health(&runtime.external_runtimes.lsp).await;
                if let Err(error) = runtime.external_runtimes.lsp_state.refresh(health).await {
                    tracing::warn!(%error, "failed to refresh LSP observed state");
                }
                if let Err(error) = runtime.refresh_thread_lsp_states().await {
                    tracing::warn!(%error, "failed to refresh Thread LSP states");
                }
            }
        })));
    }

    pub(super) async fn stop_lsp_state_watcher(&self) -> Result<()> {
        background_task::stop(&self.external_runtimes.lsp_state_watcher)
            .await
            .context("failed to join LSP state watcher")
    }

    /// 淘汰超出 LRU 容量且已保存的空闲驻留 actor；未保存时保留内存。
    pub(in crate::studio::runtime) async fn enforce_residency_limit(&self) {
        let candidates = self.residency.over_capacity().await;
        if candidates.is_empty() {
            return;
        }
        for thread_id in candidates {
            if self.residency.is_pinned(&thread_id)
                || self.agent_facility.worktrees.get(&thread_id).is_some_and(|lease| lease.state != crate::studio::agent_host::worktree_lease::WorktreeLeaseState::Cleaned) {
                continue;
            }
            // Eviction retains the full resource/storage close state. Keep that state out of
            // activation's ancestry future without detaching this caller's cancellation or join.
            let Some(session) = self.session_of(&thread_id) else {
                continue;
            };
            match Box::pin(session.evict_idle(&thread_id)).await {
                Ok(true) => {
                    self.residency.remove(&thread_id).await;
                }
                Ok(false) => self.residency.touch(&thread_id).await,
                Err(error) => {
                    tracing::warn!(%thread_id, %error, "idle Thread eviction failed; owner retained")
                }
            }
        }
    }

    /// 显式修复缺失的 Thread actor，并恢复其 durable mailbox/wake。
    pub async fn repair_thread_runtime(&self, thread_id: &str) -> Result<()> {
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        let _ = self.ensure_thread_owner(thread_id).await?;
        Ok(())
    }

    pub(super) async fn shutdown_agent_framework(&self) -> Result<()> {
        // Shutdown already owns lifecycle admission; an accepted archive/cleanup releases it only after
        // its full operation and terminal commit conclude. Join the retained task before storage stops.
        let lifecycle = background_task::finish(&self.thread_lifecycle_task).await;
        self.thread_lifecycle_task.lock().await.take();
        lifecycle.context("failed to join Thread lifecycle operation")?;
        let thread_failures = self.sessions.join_closes().await;
        if !thread_failures.is_empty() {
            return Err(ThreadCloseFailures(thread_failures).into());
        }
        self.thread_observations.finish().await?;
        Ok(())
    }

    /// 排空 agent framework 的 write-behind 队列并停止 writer。
    pub(super) async fn flush_persistence(&self) -> Result<()> {
        self.store.thread_persistence().wait_for_drain().await?;
        let repository = self.agent_facility.persistence.lock().await.clone();
        if let Some(repository) = repository {
            repository
                .flush()
                .await
                .map_err(|error| anyhow::anyhow!(error.to_string()))?;
            repository
                .shutdown()
                .await
                .map_err(|error| anyhow::anyhow!(error.to_string()))?;
            self.agent_facility.persistence.lock().await.take();
        }
        // Call statistics are a lossy projection; they never hold up authoritative history.
        self.store.calls().stop_best_effort();
        self.model_performance.close().await?;
        Ok(())
    }

    /// 当前尚未落库的 pending commit 数量（关机进度用）。
    pub async fn pending_persistence_commits(&self) -> usize {
        let repository = self.agent_facility.persistence.lock().await.clone();
        repository.map_or(0, |repository| repository.pending_commit_count())
            + usize::try_from(self.store.thread_persistence().snapshot().pending_commits)
                .unwrap_or(usize::MAX)
    }
}

/// 订阅驻留 pin guard：Drop 时解除 pin。
pub struct ThreadResidencyPin {
    runtime: StudioRuntime,
    thread_id: String,
}

impl Drop for ThreadResidencyPin {
    fn drop(&mut self) {
        self.runtime.residency.unpin(&self.thread_id);
    }
}

#[derive(Debug)]
struct ThreadCloseFailures(
    Vec<(
        String,
        std::sync::Arc<crate::thread_assembler::ThreadAssemblyError>,
    )>,
);
impl std::fmt::Display for ThreadCloseFailures {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("Thread shutdown failures")?;
        for (id, error) in &self.0 {
            write!(formatter, "; {id}: {error}")?;
        }
        Ok(())
    }
}
impl std::error::Error for ThreadCloseFailures {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.0
            .first()
            .map(|(_, error)| error as &(dyn std::error::Error + 'static))
    }
}
