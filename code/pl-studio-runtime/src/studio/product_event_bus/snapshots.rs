//! 低频产品状态快照：agent、settings、recovery、MCP、LSP、skills、thread mode
//! catalog、provider usage、model performance、updater 与 persistence 状态的
//! 读取、维护与事件发射。

use tokio::sync::watch;

use crate::{
    PersistenceStateSnapshot, SkillsStateSnapshot, StudioAgentProfilesStateSnapshot,
    StudioLspStateSnapshot, StudioModelCatalogStateSnapshot, StudioPersistenceQueueStateSnapshot,
    StudioProductEventEnvelope, StudioProductEventKind, StudioRecoveryStateSnapshot,
    StudioSessionCostsState, StudioSettingsConfigStateSnapshot, StudioUpdateStateSnapshot,
};
use pl_studio_statistics::StudioModelPerformanceSnapshot;

use super::ProductEventBus;

// Equivalent typed event adapters share expansion; domain deduplication stays at its owner.
macro_rules! snapshot_emitters {
    ($( $(#[$meta:meta])* $name:ident($value:ident: $ty:ty) => $kind:expr; )*) => {
        impl ProductEventBus {
            $($(#[$meta])* pub fn $name(&self, $value: $ty) -> StudioProductEventEnvelope {
                self.emit($kind)
            })*
        }
    };
}

snapshot_emitters! {
    /// 发布配置级 Agent Profiles 资源快照。
    emit_agent_profiles_state(state: StudioAgentProfilesStateSnapshot) =>
        StudioProductEventKind::AgentProfilesStateChanged(Box::new(state));
    emit_lsp_state(state: StudioLspStateSnapshot) => StudioProductEventKind::LspStateChanged(state);
    emit_mcp_catalog(snapshot: crate::McpCatalogSnapshot) => StudioProductEventKind::McpCatalogChanged(snapshot);
    emit_model_catalog_state(state: StudioModelCatalogStateSnapshot) =>
        StudioProductEventKind::ModelCatalogStateChanged(Box::new(state));
    emit_model_performance_state(state: StudioModelPerformanceSnapshot) => StudioProductEventKind::ModelPerformanceStateChanged(state);
    emit_recovery_state(state: crate::ObservedResource<Vec<crate::StudioRecoveryIssue>>) =>
        StudioProductEventKind::RecoveryStateChanged(StudioRecoveryStateSnapshot { state });
    /// 发布一个 root 会话的作用域费用事实；清除（`cost == None`）也是显式事件。
    emit_session_costs(state: StudioSessionCostsState) => StudioProductEventKind::SessionCostsChanged(state);
    emit_settings_config_state(state: StudioSettingsConfigStateSnapshot) =>
        StudioProductEventKind::SettingsConfigStateChanged(Box::new(state));
    emit_skills_state(state: SkillsStateSnapshot) => StudioProductEventKind::SkillsStateChanged(state.into());
    emit_thread_lsp_state(state: crate::protocol::StudioThreadLspStateSnapshot) => StudioProductEventKind::ThreadLspStateChanged(state);
    emit_thread_mcp_state(state: crate::ThreadMcpStateSnapshot) => StudioProductEventKind::ThreadMcpStateChanged(state);
    emit_updater_state(state: StudioUpdateStateSnapshot) => StudioProductEventKind::UpdaterStateChanged(state);
}

impl ProductEventBus {
    /// Mode catalog 只在真实注册/装载变化时发布；同一 revision 重复装载不产生事件。
    pub fn emit_thread_mode_catalog(
        &self,
        state: crate::mode::ThreadModeCatalogSnapshot,
    ) -> Option<StudioProductEventEnvelope> {
        let mut published = self
            .mode_catalog_revision
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.revision == 0 || state.revision <= *published {
            return None;
        }
        *published = state.revision;
        Some(self.emit(StudioProductEventKind::ThreadModeCatalogChanged(state)))
    }

    pub fn persistence_state(&self) -> PersistenceStateSnapshot {
        self.persistence_snapshot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(in crate::studio) fn observe_persistence(
        &self,
        mut state: watch::Receiver<PersistenceStateSnapshot>,
        mut threads: watch::Receiver<
            crate::studio::storage::coordinator::ThreadPersistenceSnapshot,
        >,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> tokio::task::JoinHandle<()> {
        let bus = self.clone();
        bus.update_persistence(state.borrow().clone(), threads.borrow().clone());
        bus.update_persistence_queue();
        // 仅在 scope 已登记的 factory 内调用；正常关闭只取消通知等待，不打断投影。
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    biased;
                    _ = cancellation.cancelled() => break,
                    result = state.changed() => if result.is_err() { break; },
                    result = threads.changed() => if result.is_err() { break; },
                }
                bus.update_persistence(
                    state.borrow_and_update().clone(),
                    threads.borrow_and_update().clone(),
                );
                bus.update_persistence_queue();
            }
        })
    }

    /// 当前已发布的持久化队列快照；纯查询。
    ///
    /// 首帧由构造期 observation 显式建立；读取路径不 emit、不推进 revision。
    pub fn persistence_queue_state(&self) -> StudioPersistenceQueueStateSnapshot {
        self.persistence_queue
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .snapshot
            .clone()
    }

    /// 把协调器的真实队列观测发布为 typed 快照；值未变化时不提升 revision。
    ///
    /// 观测在协调器 watch 唤醒时刷新：队列操作数、字节、在途字节、逐 Thread 水位与
    /// calls writer 进度都来自协调器；calls 侧只在指标真变时回灌，避免自唤醒循环。
    fn update_persistence_queue(&self) {
        let coordinator = self.store.thread_persistence();
        coordinator.refresh_calls_metrics(self.store.calls());
        let queue = coordinator.queue_snapshot();
        self.publish_persistence_queue(queue);
    }

    fn publish_persistence_queue(&self, queue: crate::PersistenceQueueSnapshot) {
        let mut current = self
            .persistence_queue
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if current.published.as_ref() == Some(&queue) {
            return;
        }
        current.revision = current.revision.saturating_add(1);
        current.published = Some(queue.clone());
        current.snapshot = StudioPersistenceQueueStateSnapshot {
            revision: current.revision,
            updated_at: super::unix_seconds(),
            queue,
        };
        let snapshot = current.snapshot.clone();
        self.emit(StudioProductEventKind::PersistenceQueueStateChanged(
            snapshot,
        ));
    }

    fn update_persistence(
        &self,
        mut state: PersistenceStateSnapshot,
        threads: crate::studio::storage::coordinator::ThreadPersistenceSnapshot,
    ) {
        use crate::studio::{BlockedPersistence, FlushingPersistence, PersistenceState};
        let pending = state
            .state
            .pending_commits()
            .saturating_add(threads.pending_commits);
        if let Some(error) = threads.error {
            state.state = PersistenceState::Blocked(BlockedPersistence {
                pending_commits: pending,
                oldest_pending_revision: threads.oldest_pending_revision,
                first_failed_at: super::unix_seconds(),
                error: crate::StateError {
                    code: "threadPersistenceFailed".into(),
                    message: error,
                    retryable: true,
                },
            });
        } else {
            match &mut state.state {
                PersistenceState::Ready(_) if pending > 0 => {
                    state.state = PersistenceState::Flushing(FlushingPersistence {
                        pending_commits: pending,
                        oldest_pending_revision: threads.oldest_pending_revision,
                    })
                }
                PersistenceState::Ready(value) => value.pending_commits = pending,
                PersistenceState::Flushing(value) => value.pending_commits = pending,
                PersistenceState::Degraded(value) => value.pending_commits = pending,
                PersistenceState::Recovering(value) => value.pending_commits = pending,
                PersistenceState::Blocked(value) => value.pending_commits = pending,
            }
        }
        let mut current = self
            .persistence_snapshot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.state == current.state {
            return;
        }
        state.revision = current.revision.saturating_add(1);
        *current = state.clone();
        self.emit(StudioProductEventKind::PersistenceStateChanged(state));
    }
}

#[cfg(test)]
#[path = "snapshots_tests.rs"]
mod tests;
