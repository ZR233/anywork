use anyhow::Result;
use pl_protocol::studio::{
    CommandDisposition, CommandEffectPoint, ResourceStamp, SettingsCommandReply,
    StudioCommandReceipt,
};

use super::StudioRuntime;

impl StudioRuntime {
    /// An owner incarnation; clones of this runtime share it, restarts do not.
    pub fn owner_epoch(&self) -> &str {
        &self.owner_epoch
    }

    pub(super) fn validate_operation_id(operation_id: &str) -> Result<()> {
        if operation_id.trim().is_empty() {
            return Err(pl_protocol::studio::StudioError::invalid_argument(
                "operationId is required",
            )
            .into());
        }
        Ok(())
    }

    pub(super) fn resource_stamp(&self, key: impl Into<String>, revision: u64) -> ResourceStamp {
        ResourceStamp {
            resource_key: key.into(),
            owner_epoch: self.owner_epoch.clone(),
            revision,
        }
    }

    pub(super) fn command_receipt(
        &self,
        operation_id: String,
        changed: bool,
        targets: Vec<ResourceStamp>,
        effect: CommandEffectPoint,
        durable: bool,
    ) -> StudioCommandReceipt {
        StudioCommandReceipt {
            operation_id,
            disposition: if changed {
                CommandDisposition::Applied
            } else {
                CommandDisposition::NoChange
            },
            targets,
            effect,
            effective: effect == CommandEffectPoint::Immediate,
            durable,
            requires_identity_observation: false,
        }
    }

    pub(super) fn settings_command_reply(
        &self,
        operation_id: String,
        state: &crate::ConfigRuntimeSnapshot,
        changed: bool,
        effect: CommandEffectPoint,
    ) -> Result<SettingsCommandReply> {
        Ok(SettingsCommandReply {
            snapshot: self.read_settings_response()?,
            // ConfigStore::save has completed its file/credential transaction;
            // this does not claim that existing Threads adopted the settings.
            receipt: self.command_receipt(
                operation_id,
                changed,
                vec![self.resource_stamp("settings", state.revision)],
                effect,
                true,
            ),
        })
    }

    pub(super) fn thread_directory_stamp(
        &self,
        envelope: &crate::StudioProductEventEnvelope,
    ) -> Result<ResourceStamp> {
        let crate::StudioProductEventKind::ThreadDirectoryChanged(delta) = &envelope.kind else {
            anyhow::bail!("Thread directory commit returned another resource");
        };
        Ok(self.resource_stamp("thread-directory", delta.revision))
    }
}
