//! runtime 持有的后台转发任务：Agent Profiles 配置 watch 与调用库统计进度 follower。
//!
//! 转发任务有明确 owner（runtime 的 `BackgroundTaskSlot`）：shutdown 先在 `broadcast_cancel`
//! 向该槽广播 abort，再在 `run_shutdown_stages` 的独立资源组以同一首次期限有界 join
//! （`stop_agent_profiles_forwarder`）；失败或超时经 collector 记为该次退出的 issue，令
//! `Clean` 不可达并保留 owner（常驻槽位超时不丢句柄），绝不伪报成功。启动失败路径由
//! `dispose_startup` 停止并等待；失去最后一个 runtime owner 时由 slot Drop abort 收束。
//! 任务不得依赖自身持有的 watch sender 关闭来退出。持久化状态/队列观察由 `initialization`
//! 在 `StartingServices` 复用同一 `persistence_observer` 槽建立，不在此重复启动。

use anyhow::Context;

use super::super::StudioRuntime;
use super::super::background_task::{self, BackgroundTask};

impl StudioRuntime {
    /// 启动 Agent Profiles 配置 watch 转发：配置 owner 发布的命令变更转发为 typed
    /// product 事实。
    ///
    /// 任务只持有 config/bus 的克隆（不持整个 runtime）；slot 内已有存活任务时为
    /// 幂等 no-op，initialize 重入安全。
    pub(super) async fn start_agent_profiles_forwarder(&self) {
        let mut slot = self.profiles_forwarder.lock().await;
        if slot.as_ref().is_some_and(|task| !task.is_finished()) {
            return;
        }
        let bus = self.agent_facility.product_events.clone();
        let config = self.config_runtime.clone();
        let mut updates = config.subscribe_agent_profiles();
        let task = tokio::spawn(async move {
            loop {
                if updates.changed().await.is_err() {
                    break;
                }
                match config.agent_profiles_snapshot() {
                    Ok(snapshot) => {
                        let _ = bus.emit_agent_profiles_state(snapshot.into());
                    }
                    Err(error) => {
                        tracing::warn!(%error, "Agent Profiles snapshot read failed");
                    }
                }
            }
        });
        *slot = Some(BackgroundTask::new(task));
    }

    /// 停止并等待 Agent Profiles 转发；abort 可打断 watch 等待。
    pub(super) async fn stop_agent_profiles_forwarder(&self) -> anyhow::Result<()> {
        background_task::stop(&self.profiles_forwarder)
            .await
            .context("failed to join Agent Profiles forwarder")
    }

    /// 启动调用库统计进度 follower：统计事实的受理 / 落库 / 缺口 watch 驱动同一 owner 的投影发布。
    ///
    /// 任务只持 `ModelPerformanceOwner` 与调用库句柄，不持整个 runtime；slot 内已有存活任务时
    /// 幂等 no-op，initialize 重入安全。订阅后先按当前水位收敛一次，因此启动窗口内已发生的受理
    /// 不会丢失；水位未前进时只推进轻量状态，不与 `initialize_projection` 重复发布。
    pub(super) async fn start_statistics_follower(&self) {
        let mut slot = self.statistics_follower.lock().await;
        if slot.as_ref().is_some_and(|task| !task.is_finished()) {
            return;
        }
        let owner = self.model_performance.clone();
        let task = tokio::spawn(async move {
            owner.follow_statistics_progress().await;
        });
        *slot = Some(BackgroundTask::new(task));
    }

    /// 停止并等待统计进度 follower；abort 可打断 watch 等待。
    pub(super) async fn stop_statistics_follower(&self) -> anyhow::Result<()> {
        background_task::stop(&self.statistics_follower)
            .await
            .context("failed to join statistics progress follower")
    }
}
