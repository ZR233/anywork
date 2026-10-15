use crate::api::studio::types::{
    BridgeCommandDisposition, BridgeCommandEffectPoint, BridgeResourceStamp,
    BridgeSettingsCommandReply, BridgeStudioCommandReceipt,
};
use pl_protocol::studio::{
    CommandDisposition, CommandEffectPoint, SettingsCommandReply, StudioCommandReceipt,
};

pub(crate) fn command_receipt(value: StudioCommandReceipt) -> BridgeStudioCommandReceipt {
    BridgeStudioCommandReceipt {
        operation_id: value.operation_id,
        disposition: match value.disposition {
            CommandDisposition::Applied => BridgeCommandDisposition::Applied,
            CommandDisposition::NoChange => BridgeCommandDisposition::NoChange,
        },
        targets: value
            .targets
            .into_iter()
            .map(|target| BridgeResourceStamp {
                resource_key: target.resource_key,
                owner_epoch: target.owner_epoch,
                revision: target.revision,
            })
            .collect(),
        effect: match value.effect {
            CommandEffectPoint::Immediate => BridgeCommandEffectPoint::Immediate,
            CommandEffectPoint::NextTurn => BridgeCommandEffectPoint::NextTurn,
            CommandEffectPoint::FutureSession => BridgeCommandEffectPoint::FutureSession,
        },
        effective: value.effective,
        durable: value.durable,
        requires_identity_observation: value.requires_identity_observation,
    }
}

pub(crate) fn settings_command_reply(value: SettingsCommandReply) -> BridgeSettingsCommandReply {
    BridgeSettingsCommandReply {
        snapshot: super::settings::bridge_settings_snapshot(value.snapshot),
        receipt: command_receipt(value.receipt),
    }
}
