use anyhow::Result;

use super::super::StudioRuntime;
use super::super::{AccountUsageStateSnapshot, StudioUpdateStateSnapshot};

impl StudioRuntime {
    pub async fn read_account_usage_state(&self) -> AccountUsageStateSnapshot {
        self.account_usage.read().await
    }

    pub async fn check_account_usage(&self, account_id: &str) -> Result<AccountUsageStateSnapshot> {
        let id = crate::config::AccountId::new(account_id)?;
        let revision = self
            .config_runtime
            .read()?
            .usage_query_revision(&id)
            .ok_or_else(|| {
                pl_protocol::studio::StudioError::invalid_argument("Provider does not exist")
            })?;
        self.account_usage
            .check_expected(account_id, revision)
            .await
            .map(|material| material.value.clone())
    }

    pub async fn apply_account_config(&self) -> Result<AccountUsageStateSnapshot> {
        self.account_usage.apply_config().await
    }

    pub async fn read_update_state(&self) -> StudioUpdateStateSnapshot {
        self.updater.read().await
    }

    pub async fn check_studio_update(
        &self,
        cancellation: &crate::StudioUpdateCancellation,
    ) -> Result<StudioUpdateStateSnapshot> {
        self.updater
            .check_cancellable(cancellation, crate::studio::new_id("update-check"))
            .await
            .map(|material| material.snapshot().clone())
    }

    /// 桌面后台更新：一次检测和可信准备，不关闭运行时。调用方拥有取消与完成观察。
    pub async fn prepare_studio_update_on_start(
        &self,
        cancellation: crate::StudioUpdateCancellation,
    ) -> Result<()> {
        let state = match self
            .updater
            .check_cancellable(&cancellation, crate::studio::new_id("automatic-update"))
            .await
        {
            Ok(material) => material.snapshot().clone(),
            Err(error)
                if error
                    .downcast_ref::<crate::StudioUpdateError>()
                    .is_some_and(|error| {
                        error.code() == crate::StudioUpdateErrorCode::InstallInProgress
                    }) =>
            {
                // 手动命令已占有更新流程，后台入口没有创建任何待回收资源。
                return Ok(());
            }
            Err(error) => return Err(error),
        };
        if let StudioUpdateStateSnapshot::Available(value) = state {
            let result = self
                .updater
                .prepare(value.update().clone(), cancellation, None)
                .await;
            if let Err(error) = result {
                // The manual owner may claim the available package after the check completed.
                if !error
                    .downcast_ref::<crate::StudioUpdateError>()
                    .is_some_and(|error| {
                        error.code() == crate::StudioUpdateErrorCode::InstallInProgress
                    })
                {
                    return Err(error);
                }
            }
        }
        Ok(())
    }

    /// 仅在统一退出已确认全部资源安全停止后交接本进程持有的安装包。
    pub async fn launch_studio_update_on_exit(
        &self,
        mode: crate::StudioUpdateLaunch,
    ) -> Result<Option<String>> {
        anyhow::ensure!(
            self.runtime_snapshot().await?.state.is_stopped(),
            "Studio runtime has not stopped cleanly"
        );
        self.updater.launch_ready_on_exit(mode).await
    }

    /// Resolves the exact verified update selected by the desktop host.
    pub async fn verified_studio_update(
        &self,
        expected_revision: u64,
        version: &str,
    ) -> Result<crate::StudioUpdate> {
        self.updater
            .verified_update(expected_revision, version)
            .await
    }

    /// 准备可信安装包并等待下载及投影结束，不停止运行时或启动安装器。
    pub async fn prepare_studio_update(
        &self,
        update: crate::StudioUpdate,
        progress: tokio::sync::mpsc::UnboundedSender<StudioUpdateStateSnapshot>,
        cancellation: crate::StudioUpdateCancellation,
    ) -> Result<()> {
        self.updater
            .prepare(update, cancellation, Some(progress))
            .await
            .map(|_| ())
    }

    pub async fn read_lsp_state(&self) -> crate::StudioLspStateSnapshot {
        self.external_runtimes.lsp_state.read().await
    }
}
