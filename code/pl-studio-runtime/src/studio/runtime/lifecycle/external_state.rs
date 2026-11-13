use anyhow::Result;

use super::super::StudioRuntime;
use super::super::{AccountUsageStateSnapshot, StudioUpdateStateSnapshot};

impl StudioRuntime {
    /// Desktop startup input, before bootstrap or any update command is admitted.
    pub async fn record_studio_update_installation_failure(&self, message: String) -> Result<()> {
        self.updater.record_installation_failure(message).await
    }

    pub async fn abort_cancelled_studio_update_installation(&self) -> Result<()> {
        self.updater.abort_cancelled_installation().await
    }

    pub async fn abort_studio_update_installation(&self) -> Result<()> {
        self.updater.abort_installation().await
    }

    pub async fn read_account_usage_state(&self) -> AccountUsageStateSnapshot {
        self.account_usage.read().await
    }

    pub async fn check_account_usage(&self, account_id: &str) -> Result<AccountUsageStateSnapshot> {
        self.account_usage.check(account_id).await
    }

    pub async fn read_update_state(&self) -> StudioUpdateStateSnapshot {
        self.updater.read().await
    }

    pub async fn check_studio_update(
        &self,
        cancellation: &pl_studio_update::StudioUpdateCancellation,
    ) -> Result<()> {
        self.updater.check_cancellable(cancellation).await
    }

    /// Retained background scheduler; only process shutdown cancels this token.
    pub async fn run_studio_background_updates(
        &self,
        stop: pl_studio_update::StudioUpdateCancellation,
    ) {
        self.updater.run_automatic(stop).await;
    }

    pub async fn cancel_current_update_preparation(&self) -> Result<()> {
        self.updater.cancel_current().await
    }

    /// 仅在统一退出已确认全部资源安全停止后交接本进程持有的安装包。
    pub async fn launch_studio_update_on_exit(&self) -> Result<Option<String>> {
        anyhow::ensure!(
            self.runtime_snapshot().await?.state.is_stopped(),
            "Studio runtime has not stopped cleanly"
        );
        self.updater.launch_ready_on_exit().await
    }

    pub async fn prepare_studio_update(
        &self,
        expected_revision: u64,
        version: &str,
        cancellation: pl_studio_update::StudioUpdateCancellation,
    ) -> Result<super::super::StudioUpdatePreparationResult> {
        self.updater
            .prepare_selected(expected_revision, version, cancellation)
            .await
    }

    pub async fn read_lsp_state(&self) -> crate::StudioLspStateSnapshot {
        self.external_runtimes.lsp_state.read().await
    }
}
