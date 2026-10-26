use super::{convert, types::*};
use crate::api::studio::{
    bridge_runtime::active_bridge,
    convert::commands::settings_command_reply,
    types::{AccountSecretInput, BridgeError, BridgeSettingsCommandReply},
};
use pl_protocol::studio as p;

pub async fn patch_account(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    input: BridgePatchAccountInput,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let secret = match input.secret {
        AccountSecretInput::Preserve => p::AccountSecretUpdate::Preserve,
        AccountSecretInput::Replace { value } => p::AccountSecretUpdate::Replace { value },
        AccountSecretInput::Clear => p::AccountSecretUpdate::Clear,
    };
    let custom_models = match input.custom_models {
        BridgeAccountModelsPatch::Keep => p::AccountModelsPatch::Keep,
        BridgeAccountModelsPatch::Restore => p::AccountModelsPatch::Restore,
        BridgeAccountModelsPatch::Set { models } => p::AccountModelsPatch::Set {
            models: models
                .into_iter()
                .map(|model| p::AccountModelUpdate {
                    model_id: model.model_id,
                    display_name: model.display_name,
                    wire_api: model.wire_api,
                    context_window: model.context_window,
                    max_output_tokens: model.max_output_tokens,
                })
                .collect(),
        },
    };
    Ok(settings_command_reply(
        active_bridge()
            .await?
            .studio
            .patch_account(p::PatchAccountRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                account_id,
                name: text(input.name),
                base_url: text(input.base_url),
                template_id: text(input.template_id),
                protocol: text(input.protocol),
                secret,
                custom_models,
            })
            .await?,
    ))
}

pub async fn set_account_model_auto_compact(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    model_id: String,
    intent: BridgeAutoCompactIntent,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    Ok(settings_command_reply(
        active_bridge()
            .await?
            .studio
            .set_account_model_auto_compact(p::SetAccountModelAutoCompactRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                account_id,
                model_id,
                limit: match intent {
                    BridgeAutoCompactIntent::Set { limit } => p::AutoCompactIntent::Set(limit),
                    BridgeAutoCompactIntent::Clear => p::AutoCompactIntent::Clear,
                },
            })?,
    ))
}

pub async fn set_account_model_connection(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    model_id: String,
    intent: BridgeModelConnectionIntent,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    Ok(settings_command_reply(
        active_bridge().await?.studio.set_account_model_connection(
            p::SetAccountModelConnectionRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                account_id,
                model_id,
                connection: match intent {
                    BridgeModelConnectionIntent::Clear => p::ModelConnectionIntent::Clear,
                    BridgeModelConnectionIntent::Set { mode } => {
                        p::ModelConnectionIntent::Set(match mode {
                            BridgeAccountConnectionMode::Http => p::AccountConnectionMode::Http,
                            BridgeAccountConnectionMode::WebSocket => {
                                p::AccountConnectionMode::WebSocket
                            }
                        })
                    }
                },
            },
        )?,
    ))
}

pub async fn sync_account_models(
    operation_id: String,
    account_id: String,
) -> Result<BridgeSyncAccountModelsReply, BridgeError> {
    let reply = active_bridge()
        .await?
        .studio
        .sync_account_models(p::SyncAccountModelsRequest {
            operation_id,
            account_id,
        })
        .await?;
    Ok(BridgeSyncAccountModelsReply {
        operation_id: reply.operation_id,
        account_id: reply.account_id,
        query_generation: reply.query_generation,
        joined_existing: reply.joined_existing,
    })
}

pub async fn check_account_usage(
    account_id: String,
) -> Result<BridgeAccountDomainFrame, BridgeError> {
    let bridge = active_bridge().await?;
    bridge.studio.check_account_usage(&account_id).await?;
    Ok(convert::frame(bridge.studio.read_account_domain(
        &p::AccountObservationTarget::Usage,
    )?))
}

fn text(value: BridgeAccountTextPatch) -> p::AccountTextPatch {
    match value {
        BridgeAccountTextPatch::Keep => p::AccountTextPatch::Keep,
        BridgeAccountTextPatch::Set { value } => p::AccountTextPatch::Set { value },
        BridgeAccountTextPatch::Restore => p::AccountTextPatch::Restore,
    }
}
