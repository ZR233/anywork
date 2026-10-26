//! The old transports and typed Configuration commands share these exact mutation functions.
use anyhow::Result;
use pl_protocol::studio::{
    CommandEffectPoint, RemoveAccountModelRequest, RemoveAccountRequest,
    SetAccountBillingKindRequest, SetAccountModelEnabledRequest, SetDefaultAccountRequest,
    SettingsCommandReply, UpdateAccountRequest, UpdatePermissionSettingsRequest,
    UpdateSettingsFieldRequest,
};

use super::super::StudioRuntime;
use crate::config::ConfigMutationEvidence;

pub(in crate::studio::runtime) enum Followup {
    None,
    Skills,
    Accounts,
}

pub(in crate::studio::runtime) struct SettingsCommit {
    pub(in crate::studio::runtime) evidence: ConfigMutationEvidence,
    pub(in crate::studio::runtime) operation_id: String,
    pub(in crate::studio::runtime) changed: bool,
    pub(in crate::studio::runtime) effect: CommandEffectPoint,
    pub(in crate::studio::runtime) followup: Followup,
}

impl SettingsCommit {
    pub(in crate::studio::runtime) async fn followup(&self, runtime: &StudioRuntime) -> Result<()> {
        runtime.publish_settings_state()?;
        match &self.followup {
            Followup::None => {}
            Followup::Skills => runtime.skills.mark_all_stale().await,
            Followup::Accounts => {
                runtime.apply_account_config().await?;
            }
        }
        Ok(())
    }

    fn legacy(self, runtime: &StudioRuntime) -> Result<SettingsCommandReply> {
        runtime.settings_command_reply(
            self.operation_id,
            &self.evidence.configuration,
            self.changed,
            self.effect,
        )
    }
}

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn configuration_reload_followup(&self) -> Result<()> {
        self.publish_settings_state()?;
        self.skills.mark_all_stale().await;
        let _ = self.apply_account_config().await?;
        Ok(())
    }

    pub async fn apply_settings_field(
        &self,
        request: UpdateSettingsFieldRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_settings_field(request)?;
        commit.followup(self).await?;
        commit.legacy(self)
    }
    pub fn save_permission_settings(
        &self,
        request: UpdatePermissionSettingsRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_permission_settings(request)?;
        self.publish_settings_state()?;
        commit.legacy(self)
    }
    pub async fn save_account(
        &self,
        request: UpdateAccountRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_account(request)?;
        commit.followup(self).await?;
        commit.legacy(self)
    }
    pub fn set_account_model_enabled(
        &self,
        request: SetAccountModelEnabledRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_account_model_enabled(request)?;
        self.publish_settings_state()?;
        commit.legacy(self)
    }
    pub fn set_account_billing_kind(
        &self,
        request: SetAccountBillingKindRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_account_billing_kind(request)?;
        self.publish_settings_state()?;
        commit.legacy(self)
    }
    pub fn set_default_account(
        &self,
        request: SetDefaultAccountRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_default_account(request)?;
        self.publish_settings_state()?;
        commit.legacy(self)
    }
    pub fn remove_account_model(
        &self,
        request: RemoveAccountModelRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_remove_account_model(request)?;
        self.publish_settings_state()?;
        commit.legacy(self)
    }
    pub async fn remove_account(
        &self,
        request: RemoveAccountRequest,
    ) -> Result<SettingsCommandReply> {
        let commit = self.commit_remove_account(request)?;
        commit.followup(self).await?;
        commit.legacy(self)
    }
}
