use super::super::{self as config, AgentProfilesSnapshot};
use super::{
    ConfigRuntime, ConfigRuntimeError, ConfigRuntimeResult, ConfigRuntimeSnapshot,
    ResolvedAgentProfile, config_runtime_poisoned,
};
use crate::{PureError, studio::unix_seconds};

impl ConfigRuntime {
    /// 从已发布缓存取得启用 Profile 的执行视图；不扫描文件。
    #[cfg(test)]
    pub(crate) fn agent_profiles(&self) -> ConfigRuntimeResult<config::AgentProfileCatalog> {
        Ok(self
            .profiles
            .read()
            .catalog
            .executable(crate::DelegationMode::Profile)?)
    }

    /// 读取已发布的 Agent Profiles 资源快照（完整配置与诊断）；纯缓存读取。
    pub fn agent_profiles_snapshot(&self) -> ConfigRuntimeResult<AgentProfilesSnapshot> {
        Ok(self.profiles.read())
    }

    /// 订阅 Agent Profiles 资源变更唤醒；值为最新 revision。
    pub fn subscribe_agent_profiles(&self) -> tokio::sync::watch::Receiver<u64> {
        self.profiles.subscribe()
    }

    /// Resolves an enabled Profile and its model from the same published snapshot.
    #[cfg(test)]
    pub(super) fn resolve_agent_profile(
        &self,
        profile_id: &str,
    ) -> ConfigRuntimeResult<ResolvedAgentProfile> {
        self.resolve_delegated_profile(profile_id, crate::DelegationMode::Profile, None)
    }

    /// Resolves role and model together, before allocating workspaces or provider resources.
    pub(crate) fn resolve_acp_child_profile(
        &self,
        profile_id: &str,
    ) -> ConfigRuntimeResult<(crate::AgentProfile, config::AcpServiceDefinition)> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        ensure_dispatchable_profile_id(profile_id)?;
        let profile = self
            .profiles
            .read()
            .catalog
            .enabled_for_dispatch()?
            .profiles
            .into_iter()
            .find(|profile| profile.enabled && profile.definition.definition_id == profile_id)
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "Agent Profile is missing or disabled: {profile_id}"
                ))
            })?;
        let crate::AgentBinding::Acp(binding) = &profile.binding else {
            return Err(PureError::ConfigError("ACP Profile binding changed".into()).into());
        };
        let definitions = self.read_acp_definitions();
        let entry = definitions
            .definitions
            .get(&binding.account_id)
            .ok_or_else(|| {
                PureError::ConfigError(format!("unknown ACP account `{}`", binding.account_id))
            })?;
        let definition =
            self.resolve_acp_definition(&binding.account_id, entry.connection_revision)?;
        Ok((profile, definition))
    }

    /// Resolves role and model together, before allocating workspaces or provider resources.
    pub fn resolve_delegated_profile(
        &self,
        profile_id: &str,
        mode: crate::DelegationMode,
        selection: Option<crate::NewThreadModelRoute>,
    ) -> ConfigRuntimeResult<ResolvedAgentProfile> {
        // Configuration commands also adopt the Profile cache before releasing this lock.
        // This pure resolution cannot combine a new config with the previous role catalog.
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        ensure_dispatchable_profile_id(profile_id)?;
        let snapshot = self.read()?;
        // Resolve the actual frozen/selected route below rather than replacing its diagnostic
        // with a generic "missing Profile" from the model-visible availability filter.
        let catalog = self.profiles.read().catalog.enabled_for_dispatch()?;
        let mut profile = catalog
            .profiles
            .into_iter()
            .find(|profile| profile.definition.definition_id == profile_id && profile.enabled)
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "Agent Profile is missing or disabled: {profile_id}"
                ))
            })?;
        if matches!(&profile.binding, crate::AgentBinding::Acp(_)) {
            return Err(PureError::ConfigError(
                "ACP Profile requires ACP business preparation".into(),
            )
            .into());
        }
        match (mode, selection) {
            (crate::DelegationMode::Profile, None) => {}
            (crate::DelegationMode::Profile, Some(_)) => {
                return Err(PureError::ConfigError(
                    "fixed Profile delegation forbids modelSelection".into(),
                )
                .into());
            }
            (crate::DelegationMode::Automatic, None) => {
                return Err(PureError::ConfigError(
                    "automatic delegation requires modelSelection".into(),
                )
                .into());
            }
            (crate::DelegationMode::Automatic, Some(selection)) => {
                let crate::AgentBinding::Native(native) = &mut profile.binding else {
                    unreachable!("ACP rejected before Native selection");
                };
                native.route = Some(selection);
                let mut identity = profile.freeze_native()?;
                identity.content_hash.clear();
                profile.definition.content_hash = crate::canonical_content_hash(
                    &serde_json::to_vec(&identity).map_err(PureError::from)?,
                );
            }
        }
        let route =
            crate::studio::delegation::resolve_current_child_route(&snapshot.config, &profile)?;
        Ok(ResolvedAgentProfile {
            config: snapshot.config,
            revision: snapshot.revision,
            definition: profile.definition.clone(),
            binding: profile.binding.clone(),
            profile: profile.freeze_native()?,
            route,
        })
    }

    /// 原子创建或替换一个用户 Agent Profile 文件。
    pub fn save_user_agent_profile(
        &self,
        expected_revision: Option<&str>,
        profile_id: &str,
        profile: &config::UserAgentProfile,
    ) -> ConfigRuntimeResult<(ConfigRuntimeSnapshot, bool)> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let current = self.read()?;
        let actual =
            config::agent_profile::current_profile_revision(self.store.paths(), profile_id)?;
        if expected_revision != actual.as_deref() {
            return Err(ConfigRuntimeError::ProfileConflict(profile_id.into()));
        }
        let changed = config::save_user_agent_profile(
            self.store.paths(),
            profile_id,
            profile,
            &current.config,
            &current.acp,
        )?;
        let next = ConfigRuntimeSnapshot {
            revision: current.revision.saturating_add(1),
            updated_at: unix_seconds(),
            config: current.config,
            acp: current.acp,
            canonical_config: current.canonical_config,
            usage_query_revisions: current.usage_query_revisions,
        };
        self.state
            .write()
            .map_err(|_| config_runtime_poisoned())?
            .snapshot = next.clone();
        // 配置命令采用一次新的目录扫描；资源未变化时不提升 revision、不通知观察者。
        // scan 不持有 state 写锁（与 `update` / `reload_from_disk` 一致）。
        self.profiles
            .adopt_scan(self.store.paths(), &next.config, &next.acp);
        // 同一 command 边界内同步通知身份 owner，随后才释放 command 锁。
        self.notify_settings_committed(&next);
        Ok((next, changed))
    }
}

fn ensure_dispatchable_profile_id(id: &str) -> ConfigRuntimeResult<()> {
    if id == config::ROOT_AGENT_ROUTE_KEY {
        return Err(PureError::ConfigError(
            "planner is reserved for the main agent; this child role is retired and cannot resume"
                .into(),
        )
        .into());
    }
    if crate::agent::definition::is_root_definition_id(id) {
        return Err(PureError::ConfigError(format!(
            "root Agent definition `{id}` cannot be dispatched as a child agent"
        ))
        .into());
    }
    Ok(())
}
