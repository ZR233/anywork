use anyhow::{Context, Result};

use super::super::StudioRuntime;
use super::super::background_task::{self, BackgroundTask};
use super::super::lsp_state::health;

impl StudioRuntime {
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
            .thread_snapshot(thread_id)
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
        *watcher = Some(BackgroundTask::new(tokio::spawn(async move {
            while let Ok(()) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) =
                updates.recv().await
            {
                let health = health(&runtime.external_runtimes.lsp).await;
                if let Err(error) = runtime.external_runtimes.lsp_state.refresh(health).await {
                    tracing::warn!(%error, "failed to refresh LSP observed state");
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
            match self.threads.evict_idle(&thread_id).await {
                Ok(true) => {
                    self.residency.remove(&thread_id).await;
                    self.agent_facility
                        .product_events
                        .evict_thread_entry(&thread_id);
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
        // Accepted draft commands may still initialize/submit on the original Thread/SSH owners.
        // Join them before closing those dependencies, never abort them as observation feeds.
        let command_issues = self.draft_commands.close().await;
        let framework: Result<()> = async {
            // Archive and safe cleanup retain the same lifecycle slot through their real terminal
            // commit, even after the original caller stops waiting. Join before storage stops.
            let archive = background_task::finish(&self.thread_lifecycle_task).await;
            self.thread_lifecycle_task.lock().await.take();
            let archive = archive.err().map(anyhow::Error::new);
            let thread_failures = self.threads.close_all().await;
            // A failed Thread must keep its observation/writer dependency. Do not wait for an
            // observation final state that that owner has not produced yet.
            let observation = if thread_failures.is_empty() {
                self.thread_observations.finish().await.err()
            } else {
                None
            };
            let retained = self.threads.observed_threads();
            let retry_close = archive.is_none()
                && observation.is_none()
                && !thread_failures.is_empty()
                && thread_failures.iter().all(|(id, error)| {
                    retained.iter().any(|(retained, _)| retained == id)
                        && retryable_thread_close(error)
                });
            let threads = thread_failures
                .into_iter()
                .map(|(id, error)| (id, anyhow::Error::new(error)))
                .collect::<Vec<_>>();
            if archive.is_some() || observation.is_some() || !threads.is_empty() {
                Err(FrameworkShutdownFailure {
                    archive,
                    threads,
                    observation,
                    retry_close,
                }
                .into())
            } else {
                Ok(())
            }
        }
        .await;
        if !command_issues.is_empty() {
            return Err(super::super::draft_commands::DraftCommandsCloseFailure {
                issues: command_issues,
                source: framework.err(),
            }
            .into());
        }
        framework
    }

    /// 排空当前 write-behind 工作，保留 writer 接收后续 Thread 关闭产生的可靠写入。
    pub(super) async fn flush_persistence(&self) -> Result<()> {
        self.store
            .thread_persistence()
            .wait_for_drain()
            .await
            .map_err(PersistenceShutdownFailure::Drain)?;
        let repository = self.agent_facility.persistence.lock().await.clone();
        if let Some(repository) = repository {
            repository
                .flush()
                .await
                .map_err(|error| PersistenceShutdownFailure::Flush(anyhow::Error::new(error)))?;
        }
        Ok(())
    }

    /// 只有原生产者全部收束后，最终 persistence 阶段才停止 writer。
    pub(super) async fn shutdown_persistence(&self) -> Result<()> {
        self.flush_persistence().await?;
        // A drained queue only means the admitted facts are durable. The writer task and its two
        // helpers own the same Thread separately, so their real end is waited for here: before the
        // persistence owner is released, and while the global recorder can still take their last
        // report.
        let writers = self.store.thread_persistence().wait_for_writers_end(None).await;
        writers.map_err(PersistenceShutdownFailure::Writers)?;
        let repository = self.agent_facility.persistence.lock().await.clone();
        if let Some(repository) = repository {
            repository
                .shutdown()
                .await
                .map_err(|error| PersistenceShutdownFailure::Shutdown(anyhow::Error::new(error)))?;
            self.agent_facility.persistence.lock().await.take();
        }
        // Call statistics are a lossy projection; they never hold up authoritative history.
        self.store.calls().stop_best_effort();
        // History connections outlive their Thread: their last holder handed them to the coordinator
        // instead of leaving them to an unobservable drop. Sealing takes the same admission boundary
        // the handle construction uses, so after it returns no new holder can appear; every
        // producer, reader and session owner was already joined above. Settling then joins those
        // original connections and keeps every real failure.
        let persistence = self.store.thread_persistence();
        persistence.seal_history().await;
        persistence
            .settle_history()
            .await
            .map_err(|group| PersistenceShutdownFailure::History(anyhow::Error::new(group)))?;
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
pub(super) struct FrameworkShutdownFailure {
    pub(super) archive: Option<anyhow::Error>,
    pub(super) threads: Vec<(String, anyhow::Error)>,
    pub(super) observation: Option<anyhow::Error>,
    pub(super) retry_close: bool,
}

fn retryable_thread_close(error: &crate::thread_assembler::ThreadAssemblyError) -> bool {
    use crate::thread_assembler::ThreadAssemblyError;
    if let ThreadAssemblyError::Resource { source, .. } = error
        && let Some(failure) = source.downcast_ref::<crate::thread_assembler::ThreadCloseFailure>()
    {
        // The assembler retains the exact close phase and its original dependencies. Only that
        // owner's recovery contract (not a generic Resource error) permits another close attempt.
        return failure.can_resume_original() || failure.original_is_complete();
    }
    matches!(
        error,
        ThreadAssemblyError::Preparing(_)
            | ThreadAssemblyError::Descendant(_)
            | ThreadAssemblyError::Thread(pl_core::thread::ThreadError::Tool(_))
            | ThreadAssemblyError::Thread(pl_core::thread::ThreadError::Storage(_))
    )
}

/// A consumed writer shutdown handle is not the same recovery operation as drain/flush.
#[derive(Debug, thiserror::Error)]
pub(super) enum PersistenceShutdownFailure {
    #[error("history drain did not complete")]
    Drain(#[source] anyhow::Error),
    #[error("writer tasks did not end")]
    Writers(#[source] anyhow::Error),
    #[error("write-behind flush did not complete")]
    Flush(#[source] anyhow::Error),
    #[error("write-behind shutdown did not complete")]
    Shutdown(#[source] anyhow::Error),
    #[error("history connections were not closed")]
    History(#[source] anyhow::Error),
}

impl std::fmt::Display for FrameworkShutdownFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("agent framework shutdown retained failed original owners")
    }
}

impl std::error::Error for FrameworkShutdownFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.archive
            .as_ref()
            .or_else(|| self.threads.first().map(|(_, error)| error))
            .or(self.observation.as_ref())
            .map(|error| error.as_ref())
    }
}
