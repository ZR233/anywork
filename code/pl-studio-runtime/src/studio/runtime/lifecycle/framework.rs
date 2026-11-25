use anyhow::{Context, Result};

use super::super::StudioRuntime;
use super::super::background_task;
use super::super::lsp_state::health;
use super::super::observation_lifecycle::{ObservationStartError, ObserverTask, RuntimeObserver};

#[derive(Clone)]
struct LspObservationServices {
    registry: pl_lsp::runtime::LspRuntimeRegistry,
    state: super::super::lsp_state::LspStateRuntime,
    threads: crate::studio::thread_factory::StudioThreadFactory,
}

impl LspObservationServices {
    async fn refresh_thread_states(
        &self,
        #[cfg(test)] probe: &super::super::observation_lifecycle::LspProjectionProbe,
    ) -> Result<()> {
        let _refresh = self.state.thread_refresh().await;
        let bindings = self.threads.binding_snapshots();
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
                && !binding.lifetime.target_invalidated()
                && !binding.lifetime.cancellation.is_cancelled()
                && lease.is_some_and(|lease| !lease.is_closed());
            let servers = if should_read {
                let registry = self.registry.execution_scope(&endpoint);
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
            self.state
                .pause_after_thread_snapshot_for_test(&servers)
                .await;
            let _commit = self.state.thread_commit().await;
            let expected = crate::studio::thread_factory::LspProjectionBinding {
                incarnation: &binding.incarnation,
                binding_id: captured_binding_id.as_deref(),
                endpoint: Some(endpoint.as_str()),
                root: root.as_deref(),
            };
            let published_thread_id = thread_id.clone();
            let published_binding_id = captured_binding_id.clone();
            let _result = self
                .threads
                .commit_lsp_projection(&thread_id, Some(expected), |valid| {
                    self.state.commit_thread(
                        published_thread_id,
                        valid.then(|| published_binding_id.expect("valid binding has ID")),
                        if valid { servers } else { Vec::new() },
                    )
                });
            #[cfg(test)]
            probe.projection_completed(
                &thread_id,
                &binding.incarnation,
                captured_binding_id,
                _result,
            );
        }
        for thread_id in self.state.thread_ids() {
            if !known_ids.contains(&thread_id) {
                let _commit = self.state.thread_commit().await;
                let published_thread_id = thread_id.clone();
                self.threads
                    .commit_lsp_projection(&thread_id, None, |valid| {
                        if !valid {
                            self.state
                                .commit_thread(published_thread_id, None, Vec::new());
                        }
                    });
            }
        }
        Ok(())
    }

    async fn create_observer(
        self,
        cancellation: pl_lifecycle::CancellationToken,
        #[cfg(test)] probe: super::super::observation_lifecycle::LspProjectionProbe,
    ) -> Result<ObserverTask, super::super::observation_lifecycle::ObservationCleanupError> {
        let mut updates = self.registry.subscribe();
        let binding_source = self.threads.lsp_binding_updates();
        // 先建立通知，再做初始读取；初始化期间的变化留给第一轮循环。
        let mut binding_updates = Box::pin(binding_source.clone().notified_owned());
        binding_updates.as_mut().enable();
        {
            let _command = self.state.command().await;
            let initial = health(&self.registry).await;
            if let Err(error) = self.state.begin(crate::StateOperation::Activate).await {
                tracing::warn!(%error, "failed to begin LSP observed state");
            } else if let Err(error) = self.state.ready(initial, false).await {
                tracing::warn!(%error, "failed to publish initial LSP observed state");
            }
        }
        if let Err(error) = self
            .refresh_thread_states(
                #[cfg(test)]
                &probe,
            )
            .await
        {
            tracing::warn!(%error, "failed to publish initial Thread LSP states");
        }
        let task_cancel = cancellation.clone();
        // Opening worker 已拥有全部初始化；数据任务创建后立即交给 adapter，不跨 await 留裸句柄。
        let task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    biased;
                    _ = task_cancel.cancelled() => break,
                    event = updates.recv() => match event {
                        Ok(()) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                    },
                    _ = &mut binding_updates => {
                        binding_updates.set(binding_source.clone().notified_owned());
                        binding_updates.as_mut().enable();
                    }
                }
                let health = health(&self.registry).await;
                if let Err(error) = self.state.refresh(health).await {
                    tracing::warn!(%error, "failed to refresh LSP observed state");
                }
                // 取消仅在下一次通知等待生效，不丢弃这一轮的绑定检查与提交。
                if let Err(error) = self
                    .refresh_thread_states(
                        #[cfg(test)]
                        &probe,
                    )
                    .await
                {
                    tracing::warn!(%error, "failed to refresh Thread LSP states");
                }
            }
        });
        Ok(ObserverTask::new(cancellation, task))
    }
}

impl StudioRuntime {
    fn lsp_observation_services(&self) -> LspObservationServices {
        LspObservationServices {
            registry: self.external_runtimes.lsp.clone(),
            state: self.external_runtimes.lsp_state.clone(),
            threads: self.thread_factory.clone(),
        }
    }

    pub(in crate::studio::runtime) async fn refresh_thread_lsp_states(&self) -> Result<()> {
        self.lsp_observation_services()
            .refresh_thread_states(
                #[cfg(test)]
                &self.observations.lsp_projection_probe(),
            )
            .await
    }

    pub(in crate::studio::runtime) fn check_thread_read_access(
        &self,
        thread: &crate::Thread,
    ) -> Result<()> {
        self.recovery.ensure_thread_read_access(thread)
    }

    pub(in crate::studio::runtime) fn check_thread_execution_access(
        &self,
        thread: &crate::Thread,
    ) -> Result<()> {
        self.recovery.ensure_thread_execution_access(thread)
    }

    pub(in crate::studio::runtime) async fn verify_thread_execution_preparation(
        &self,
        thread: &crate::Thread,
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

    pub(in crate::studio::runtime) async fn read_protocol_thread(
        &self,
        thread_id: &str,
    ) -> Result<crate::Thread> {
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
            return Err(anyhow::Error::new(crate::StudioError::not_found("session")));
        };
        Ok(crate::Thread::from(record))
    }

    pub(super) async fn start_lsp_state_watcher(&self) -> Result<()> {
        let services = self.lsp_observation_services();
        #[cfg(test)]
        let probe = self.observations.lsp_projection_probe();
        self.observations
            .start(RuntimeObserver::Lsp, move |cancellation| {
                services.create_observer(
                    cancellation,
                    #[cfg(test)]
                    probe,
                )
            })
            .await
            .map(|_| ())
            .map_err(|error| ObservationStartError(error).into())
    }

    /// 淘汰超出 LRU 容量且已保存的空闲驻留 actor；未保存时保留内存。
    pub(in crate::studio::runtime) async fn enforce_residency_limit(&self) {
        let candidates = self.residency.over_capacity();
        if candidates.is_empty() {
            return;
        }
        for thread_id in candidates {
            if self.residency.is_pinned(&thread_id)
                || self
                    .agent_facility
                    .worktrees
                    .get(&thread_id)
                    .is_some_and(|lease| {
                        lease.state
                            != crate::studio::worktree::worktree_lease::WorktreeLeaseState::Cleaned
                    })
            {
                continue;
            }
            // Eviction retains the full resource/storage close state. Keep that state out of
            // activation's ancestry future without detaching this caller's cancellation or join.
            let Some(session) = self.session_of(&thread_id) else {
                continue;
            };
            match Box::pin(session.evict_idle(&thread_id)).await {
                Ok(true) => {
                    self.residency.remove(&thread_id);
                }
                Ok(false) => self.residency.touch(&thread_id),
                Err(error) => {
                    tracing::warn!(%thread_id, %error, "idle Thread eviction failed; owner retained")
                }
            }
        }
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
    pub(super) async fn pending_persistence_commits(&self) -> usize {
        let repository = self.agent_facility.persistence.lock().await.clone();
        repository.map_or(0, |repository| repository.pending_commit_count())
            + usize::try_from(self.store.thread_persistence().snapshot().pending_commits)
                .unwrap_or(usize::MAX)
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
