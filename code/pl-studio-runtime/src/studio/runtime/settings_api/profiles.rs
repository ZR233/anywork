use anyhow::Result;

use super::super::StudioRuntime;
use super::super::observation_lifecycle::{ObservationStartError, ObserverTask, RuntimeObserver};

impl StudioRuntime {
    pub(crate) fn read_agent_profiles_state(
        &self,
    ) -> Result<crate::StudioAgentProfilesStateSnapshot> {
        Ok(self.config_runtime.agent_profiles_snapshot()?.into())
    }

    /// 原子创建或保存一个用户 Agent Profile TOML。
    pub fn save_user_agent_profile(
        &self,
        operation_id: String,
        expected_revision: Option<&str>,
        profile_id: &str,
        profile: &crate::config::UserAgentProfile,
    ) -> Result<crate::SettingsCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        let (state, changed) =
            self.config_runtime
                .save_user_agent_profile(expected_revision, profile_id, profile)?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &state,
            changed,
            crate::CommandEffectPoint::FutureSession,
        )
    }

    /// 启用或禁用不可编辑、不可删除的系统 Agent Profile。
    pub fn set_system_agent_enabled(
        &self,
        operation_id: String,
        profile_id: &str,
        enabled: bool,
    ) -> Result<crate::SettingsCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        if !crate::config::is_system_profile_id(profile_id)? {
            anyhow::bail!("`{profile_id}` is not a system Agent Profile");
        }
        let profile_id = profile_id.to_string();
        let mut changed = false;
        let state = self
            .config_runtime
            .update_with_effective(None, |config, _| {
                let mut config = config.clone();
                if enabled {
                    changed = config.disabled_system_agents.remove(&profile_id);
                } else {
                    changed = config.disabled_system_agents.insert(profile_id.clone());
                }
                Ok(config)
            })?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &state,
            changed,
            crate::CommandEffectPoint::FutureSession,
        )
    }

    /// 立即重试待落库事实；查询和停止路径不需要调用本命令。
    pub(in crate::studio::runtime) async fn start_agent_profiles_forwarder(
        &self,
    ) -> anyhow::Result<()> {
        let bus = self.agent_facility.product_events.clone();
        let config = self.config_runtime.clone();
        self.observations
            .start(RuntimeObserver::Profiles, move |cancellation| async move {
                let mut updates = config.subscribe_agent_profiles();
                let task_cancel = cancellation.clone();
                let task = tokio::spawn(async move {
                    loop {
                        tokio::select! {
                            biased;
                            _ = task_cancel.cancelled() => break,
                            change = updates.changed() => if change.is_err() { break; },
                        }
                        match config.agent_profiles_snapshot() {
                            Ok(snapshot) => {
                                bus.emit_agent_profiles_state(snapshot.into());
                            }
                            Err(error) => {
                                tracing::warn!(%error, "Agent Profiles snapshot read failed")
                            }
                        }
                    }
                });
                Ok(ObserverTask::new(cancellation, task))
            })
            .await
            .map(|_| ())
            .map_err(|error| ObservationStartError(error).into())
    }
}
