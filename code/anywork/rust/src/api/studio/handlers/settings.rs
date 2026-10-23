use crate::api::studio::bridge_runtime::{active_bridge, installed_bridge};
use crate::api::studio::convert::commands::settings_command_reply;
use crate::api::studio::convert::settings::{
    account_settings_request, bridge_deepseek_web_search_settings, bridge_settings_snapshot,
    bridge_web_search_settings,
};
use crate::api::studio::types::{
    AccountSettingsInput, BridgeAccountCatalogSnapshot, BridgeBillingKind,
    BridgeDeepSeekWebSearchSettingsDto, BridgeError, BridgeSettingsCommandReply,
    BridgeSettingsStateResponse, BridgeWebSearchSettingsDto, RemoveAccountInput,
    SettingsFieldInput,
};
// ── Settings ──

pub fn load_account_catalog() -> Result<BridgeAccountCatalogSnapshot, BridgeError> {
    Ok(installed_bridge()?.studio.load_account_catalog()?.into())
}

pub async fn read_web_search_settings() -> Result<BridgeWebSearchSettingsDto, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_web_search_settings(
        bridge.studio.read_settings()?.config.settings.web_search,
    ))
}

pub async fn read_deepseek_web_search_settings()
-> Result<BridgeDeepSeekWebSearchSettingsDto, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_deepseek_web_search_settings(
        bridge
            .studio
            .read_settings()?
            .config
            .settings
            .deepseek_web_search,
    ))
}

/// Applies one typed settings field/resource mutation. Sibling values are
/// resolved by the runtime from its canonical desired configuration.
pub async fn apply_settings_field(
    operation_id: String,
    expected_settings_revision: u64,
    input: SettingsFieldInput,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(
        bridge
            .studio
            .apply_settings_field(pl_protocol::studio::UpdateSettingsFieldRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                update: input.into(),
            })
            .await?,
    ))
}

pub async fn read_settings_state() -> Result<BridgeSettingsStateResponse, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_settings_snapshot(bridge.studio.read_settings()?))
}

pub async fn remove_account_model(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    model_id: String,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(bridge.studio.remove_account_model(
        pl_protocol::studio::RemoveAccountModelRequest {
            operation_id,
            expected_revision: expected_settings_revision,
            account_id,
            model_id,
        },
    )?))
}

/// Changes only the unified enabled field of one exact catalog member.
pub async fn set_account_model_enabled(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    model_id: String,
    enabled: bool,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    Ok(settings_command_reply(
        active_bridge().await?.studio.set_account_model_enabled(
            pl_protocol::studio::SetAccountModelEnabledRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                account_id,
                model_id,
                enabled,
            },
        )?,
    ))
}

/// `None` explicitly clears the override; explicit Unknown is a distinct intent.
pub async fn set_account_billing_kind(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    billing_kind: Option<BridgeBillingKind>,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let billing_kind = match billing_kind {
        Some(kind) => pl_protocol::studio::BillingKindIntent::set(kind.into()),
        None => pl_protocol::studio::BillingKindIntent::clear(),
    };
    Ok(settings_command_reply(
        active_bridge().await?.studio.set_account_billing_kind(
            pl_protocol::studio::SetAccountBillingKindRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                account_id,
                billing_kind,
            },
        )?,
    ))
}

pub async fn reload_settings_from_disk(
    expected_settings_revision: u64,
) -> Result<BridgeSettingsStateResponse, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_settings_snapshot(
        bridge
            .studio
            .reload_settings(expected_settings_revision)
            .await?,
    ))
}

pub async fn save_runtime_permission_mode(
    operation_id: String,
    expected_settings_revision: u64,
    mode: String,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(
        bridge.studio.save_permission_settings(
            pl_protocol::studio::UpdatePermissionSettingsRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                mode,
            },
        )?,
    ))
}

pub async fn save_account(
    operation_id: String,
    expected_settings_revision: u64,
    input: AccountSettingsInput,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(
        bridge
            .studio
            .save_account(account_settings_request(
                operation_id,
                expected_settings_revision,
                input,
            ))
            .await?,
    ))
}

pub async fn set_default_account(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(bridge.studio.set_default_account(
        pl_protocol::studio::SetDefaultAccountRequest {
            operation_id,
            expected_revision: expected_settings_revision,
            account_id,
        },
    )?))
}

pub async fn remove_account(
    operation_id: String,
    expected_settings_revision: u64,
    account_id: String,
    input: RemoveAccountInput,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(
        bridge
            .studio
            .remove_account(pl_protocol::studio::RemoveAccountRequest {
                operation_id,
                expected_revision: expected_settings_revision,
                account_id,
                replacement_account_id: input.replacement_account_id,
            })
            .await?,
    ))
}
