use anyhow::Result;
use pl_lsp::runtime::{LspRuntimeRegistry, LspServerSnapshot};
use std::{future::Future, path::Path};

use super::super::StudioRuntime;
use super::super::observation_lifecycle::{ObservationStartError, ObserverTask, RuntimeObserver};
use super::state::{LspOperation, execution_endpoint, health, project_servers};

#[derive(Clone)]
pub(in crate::studio::runtime) struct LspObservationServices {
    registry: pl_lsp::runtime::LspRuntimeRegistry,
    state: super::state::LspStateRuntime,
    threads: crate::studio::thread_factory::StudioThreadFactory,
}

/// Read port for per-workspace snapshots captured before the binding qualification.
/// The watcher owns the qualification and the eventual product commit.
pub(in crate::studio::runtime) trait WorkspaceLspSnapshots:
    Send + Sync + 'static
{
    fn read(
        &self,
        endpoint: &str,
        root: &Path,
    ) -> impl Future<Output = Vec<LspServerSnapshot>> + Send;
}

impl WorkspaceLspSnapshots for LspRuntimeRegistry {
    async fn read(&self, endpoint: &str, root: &Path) -> Vec<LspServerSnapshot> {
        self.execution_scope(endpoint)
            .snapshots_for_workspace(root)
            .await
    }
}

impl LspObservationServices {
    pub(in crate::studio::runtime) async fn refresh_thread_states(
        &self,
        source: &impl WorkspaceLspSnapshots,
    ) {
        let _refresh = self.state.thread_refresh().await;
        let bindings = self.threads.binding_snapshots();
        let known_ids = bindings
            .keys()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>();
        for (thread_id, binding) in bindings {
            let lease = binding.lsp_lease.as_ref();
            let endpoint = execution_endpoint(binding.project.ssh_alias.as_deref());
            let root = lease.map(|lease| lease.workspace_root().to_path_buf());
            let captured_binding_id = binding.lsp_binding_id.as_deref();
            let should_read = captured_binding_id.is_some()
                && !binding.lifetime.target_invalidated()
                && !binding.lifetime.cancellation.is_cancelled()
                && lease.is_some_and(|lease| !lease.is_closed());
            let servers = if should_read {
                let snapshots = source
                    .read(&endpoint, root.as_deref().expect("lease root"))
                    .await;
                let previous = self.state.read_thread(&thread_id);
                project_servers(snapshots, &previous.servers)
            } else {
                Vec::new()
            };
            let expected = crate::studio::thread_factory::LspProjectionBinding {
                incarnation: &binding.incarnation,
                binding_id: captured_binding_id,
                endpoint: Some(endpoint.as_str()),
                root: root.as_deref(),
            };
            self.threads
                .commit_lsp_projection(&thread_id, Some(expected), |valid| {
                    self.state.commit_thread(
                        &thread_id,
                        captured_binding_id.filter(|_| valid).map(str::to_owned),
                        if valid { servers } else { Vec::new() },
                    )
                });
        }
        for thread_id in self.state.thread_ids() {
            if !known_ids.contains(&thread_id) {
                self.threads
                    .commit_lsp_projection(&thread_id, None, |valid| {
                        if !valid {
                            self.state.commit_thread(&thread_id, None, Vec::new());
                        }
                    });
            }
        }
    }

    pub(in crate::studio::runtime) async fn create_observer(
        self,
        cancellation: pl_lifecycle::CancellationToken,
        source: impl WorkspaceLspSnapshots,
    ) -> Result<ObserverTask, super::super::observation_lifecycle::ObservationCleanupError> {
        let mut updates = self.registry.subscribe();
        let binding_source = self.threads.lsp_binding_updates();
        // 先建立通知，再做初始读取；初始化期间的变化留给第一轮循环。
        let mut binding_updates = Box::pin(binding_source.clone().notified_owned());
        binding_updates.as_mut().enable();
        {
            let _command = self.state.command().await;
            let initial = health(&self.registry, None).await;
            if let Err(error) = self.state.begin(LspOperation::Activate).await {
                tracing::warn!(%error, "failed to begin LSP observed state");
            } else if let Err(error) = self.state.ready(initial, false).await {
                tracing::warn!(%error, "failed to publish initial LSP observed state");
            }
        }
        self.refresh_thread_states(&source).await;
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
                {
                    let _command = self.state.command().await;
                    let previous = self.state.read().await;
                    let health = health(&self.registry, previous.state.value()).await;
                    if let Err(error) = self.state.refresh(health).await {
                        tracing::warn!(%error, "failed to refresh LSP observed state");
                    }
                }
                // 取消仅在下一次通知等待生效，不丢弃这一轮的绑定检查与提交。
                self.refresh_thread_states(&source).await;
            }
        });
        Ok(ObserverTask::new(cancellation, task))
    }
}

impl StudioRuntime {
    pub(in crate::studio::runtime) fn lsp_observation_services(&self) -> LspObservationServices {
        LspObservationServices {
            registry: self.external_runtimes.lsp.clone(),
            state: self.external_runtimes.lsp_state.clone(),
            threads: self.thread_factory.clone(),
        }
    }

    pub(in crate::studio::runtime) async fn refresh_thread_lsp_states(&self) {
        let services = self.lsp_observation_services();
        services.refresh_thread_states(&services.registry).await
    }

    pub(in crate::studio::runtime) async fn start_lsp_state_watcher(&self) -> Result<()> {
        let services = self.lsp_observation_services();
        let source = services.registry.clone();
        self.observations
            .start(RuntimeObserver::Lsp, move |cancellation| {
                services.create_observer(cancellation, source)
            })
            .await
            .map(|_| ())
            .map_err(|error| ObservationStartError(error).into())
    }
}
