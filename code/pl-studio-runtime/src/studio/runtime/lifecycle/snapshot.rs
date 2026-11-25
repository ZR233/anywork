use anyhow::Result;

use crate::studio::{StudioRecoveryIssue, StudioRuntimeSnapshot};

use super::super::StudioRuntime;

impl StudioRuntime {
    pub(crate) fn publish_settings_state(&self) -> Result<()> {
        // 同一个 Settings command 边界内投影：身份撤代已随提交完成，这里只读取一致快照。
        let published =
            self.config_runtime
                .with_consistent_snapshot(|settings, catalog_state| {
                    let acp_accounts = self
                        .acp_accounts
                        .settings_view(settings.revision, &settings.acp)?;
                    Ok::<_, anyhow::Error>((
                        settings.clone(),
                        super::super::settings_api::settings_config_snapshot(
                            settings,
                            acp_accounts,
                        )?,
                        super::super::settings_api::model_catalog_snapshot(
                            settings,
                            catalog_state,
                        )?,
                    ))
                })?;
        let (settings, config, catalog) = published?;
        self.settings_updates.send_if_modified(|current| {
            if settings.revision <= current.revision {
                return false;
            }
            *current = settings;
            true
        });
        self.agent_facility
            .product_events
            .emit_settings_config_state(crate::StudioSettingsConfigStateSnapshot {
                state: crate::ObservedResource::ready(config.revision, config.updated_at, config),
            });
        self.observations
            .model_catalog_publication
            .publish(&self.agent_facility.product_events, catalog);
        for mcp_catalog in self.config_runtime.refresh_mcp_catalogs_for_models()? {
            self.agent_facility
                .product_events
                .emit_mcp_catalog(mcp_catalog);
        }
        Ok(())
    }

    /// 返回当前所有恢复问题的快照。
    ///
    /// 恢复问题由独立的 [`StudioRecoveryRegistry`] 持有，不混入 runtime 快照，
    /// 避免与生命周期转换竞争同一把锁。
    pub fn recovery_issues(&self) -> Vec<StudioRecoveryIssue> {
        self.recovery.snapshot()
    }

    pub async fn runtime_snapshot(&self) -> Result<StudioRuntimeSnapshot> {
        let mut snapshot = self.runtime_state.snapshot();
        snapshot.startup_recovery = self.startup_recovery.clone();
        snapshot.active_turns = self.derive_active_turns().await?;
        Ok(snapshot)
    }
}
