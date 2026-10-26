//! Profile mutations share the original ConfigRuntime command owner and publication path.
use super::{
    ConfigMutationEvidence, ConfigMutationFailure, ConfigProfileCommandResult, ConfigRuntime,
    ConfigRuntimeError, ConfigRuntimeResult, ConfigRuntimeSnapshot, config_runtime_poisoned,
    ensure_revision,
};
use crate::{PureError, studio::unix_seconds};

#[derive(Debug, thiserror::Error)]
pub(crate) enum ProfileMutationFailure {
    #[error("Profile command was rejected before the possibly replacing writer")]
    Preflight(#[source] ConfigRuntimeError),
    #[error("Profile command's durable outcome is unknown")]
    Commit(#[source] ConfigRuntimeError),
    #[error("Profile file/save succeeded but no usable receipt could be captured")]
    Confirmed(#[source] ConfigRuntimeError),
}
impl From<ProfileMutationFailure> for ConfigRuntimeError {
    fn from(error: ProfileMutationFailure) -> Self {
        match error {
            ProfileMutationFailure::Preflight(error)
            | ProfileMutationFailure::Commit(error)
            | ProfileMutationFailure::Confirmed(error) => error,
        }
    }
}
impl From<ConfigMutationFailure> for ProfileMutationFailure {
    fn from(error: ConfigMutationFailure) -> Self {
        match error {
            ConfigMutationFailure::Preflight(error) => Self::Preflight(error),
            ConfigMutationFailure::Commit(error) => Self::Commit(error),
            ConfigMutationFailure::Confirmed(error) => Self::Confirmed(error),
        }
    }
}
impl ConfigRuntime {
    pub(crate) fn save_user_agent_profile_phased(
        &self,
        expected_revision: u64,
        profile_id: &str,
        profile: &super::super::UserAgentProfile,
    ) -> Result<ConfigProfileCommandResult, ProfileMutationFailure> {
        let command = self
            .command_lock
            .lock()
            .map_err(|_| ProfileMutationFailure::Preflight(config_runtime_poisoned()))?;
        let prepared = (|| -> ConfigRuntimeResult<_> {
            let current = self.read()?;
            ensure_revision(expected_revision, current.revision)?;
            if self
                .state
                .read()
                .map_err(|_| config_runtime_poisoned())?
                .closing
            {
                return Err(PureError::ConfigError("settings owner is closing".into()).into());
            }
            let revision = current
                .revision
                .checked_add(1)
                .ok_or_else(|| PureError::ConfigError("settings revision is exhausted".into()))?;
            let prepared = super::super::agent_profile::prepare_user_agent_profile(
                self.store.paths(),
                profile_id,
                profile,
                &current.config,
            )?;
            Ok((current, revision, prepared))
        })();
        let (current, revision, prepared) = prepared.map_err(ProfileMutationFailure::Preflight)?;
        // The unchanged atomic writer may have replaced the file before returning an error.
        let changed = prepared
            .write()
            .map_err(|error| ProfileMutationFailure::Commit(error.into()))?;
        let next = ConfigRuntimeSnapshot {
            revision,
            updated_at: unix_seconds(),
            config: current.config,
            canonical_config: current.canonical_config,
            usage_query_revisions: current.usage_query_revisions,
        };
        // Profile 提交同样先取得与新 revision 严格相符的不可变 ACP 目录，再在原状态发布边界
        // 采用配置材料；此处不持有配置状态锁。
        let acp_directory = self.observe_settings_commit(&next);
        // Real ConfirmedWithoutUsableReceipt path: write returned success, but this guard failed.
        // We cannot invent a configuration revision/receipt from the prospective `next` value.
        let mut state = self
            .state
            .write()
            .map_err(|_| ProfileMutationFailure::Confirmed(config_runtime_poisoned()))?;
        state.acp_directory = Some(acp_directory);
        state.snapshot = next.clone();
        let publication = self.publish_projection_locked(&mut state);
        let catalog = state.catalog.clone();
        drop(state);
        let adopted = self
            .profiles
            .adopt_scan_captured(self.store.paths(), &next.config);
        let result = ConfigProfileCommandResult {
            configuration: next.clone(),
            catalog: catalog.clone(),
            profiles: adopted.evidence.snapshot.clone(),
            changed,
            _evidence: ConfigMutationEvidence {
                configuration: next,
                catalog,
                captures: publication.configuration_captures.clone(),
                profiles: adopted.evidence.clone(),
            },
        };
        drop(command);
        adopted.notify();
        self.notify_projection(publication);
        Ok(result)
    }

    pub(crate) fn set_system_agent_enabled_phased(
        &self,
        expected_revision: u64,
        profile_id: &str,
        enabled: bool,
    ) -> Result<ConfigProfileCommandResult, ProfileMutationFailure> {
        if !super::super::is_system_profile_id(profile_id)
            .map_err(|error| ProfileMutationFailure::Preflight(error.into()))?
        {
            return Err(ProfileMutationFailure::Preflight(
                PureError::ConfigError("not a system Agent Profile".into()).into(),
            ));
        }
        let command = self
            .command_lock
            .lock()
            .map_err(|_| ProfileMutationFailure::Preflight(config_runtime_poisoned()))?;
        let mut changed = false;
        let current = self.read().map_err(ProfileMutationFailure::Preflight)?;
        ensure_revision(expected_revision, current.revision)
            .map_err(ProfileMutationFailure::Preflight)?;
        current.revision.checked_add(1).ok_or_else(|| {
            ProfileMutationFailure::Preflight(
                PureError::ConfigError("settings revision is exhausted".into()).into(),
            )
        })?;
        let (configuration, publication, adopted) = self
            .update_with_effective_locked(expected_revision, |desired, _| {
                let mut next = desired.clone();
                changed = if enabled {
                    next.disabled_system_agents.remove(profile_id)
                } else {
                    next.disabled_system_agents.insert(profile_id.to_owned())
                };
                Ok(next)
            })
            .map_err(ProfileMutationFailure::from)?;
        let catalog = publication.catalog.clone();
        let profiles = adopted.snapshot.clone();
        let evidence = ConfigMutationEvidence {
            configuration: configuration.clone(),
            catalog: catalog.clone(),
            captures: publication.configuration_captures.clone(),
            profiles: adopted,
        };
        drop(command);
        self.notify_projection(publication);
        Ok(ConfigProfileCommandResult {
            configuration,
            catalog,
            profiles,
            changed,
            _evidence: evidence,
        })
    }
}
