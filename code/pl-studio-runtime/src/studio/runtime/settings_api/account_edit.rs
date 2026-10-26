//! Account 设置编辑：把 wire 层的 account/model/role 更新解析为配置编辑对象。

use anyhow::Result;
use pl_model::protocol::{ConnectionMode, WireApi};
use pl_protocol::studio::{
    AccountModelAutoCompactUpdate, AccountModelConnectionUpdate, AccountModelUpdate,
    AccountSecretUpdate, AccountSettingsUpdate, StudioError,
};

use crate::{AccountEdit, AccountModelEdit};
use pl_model::config::AccountTemplateId;
use pl_model::protocol::ProtocolKind;

pub(super) fn account_edit(
    input: AccountSettingsUpdate,
    current: &crate::StudioConfig,
) -> Result<AccountEdit> {
    let template = input
        .template_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(AccountTemplateId::new)
        .transpose()
        .map_err(|_| invalid_settings_argument("Invalid account template id"))?;
    let protocol = input
        .protocol
        .trim()
        .parse::<ProtocolKind>()
        .map_err(|_| invalid_settings_argument("Invalid account protocol"))?;
    let account_id = input.account_id.trim();
    let current_token = current
        .models
        .accounts
        .get(&pl_model::config::AccountId::new(account_id)?)
        .and_then(|account| account.bearer_token.clone());
    let bearer_token = match input.secret {
        AccountSecretUpdate::Preserve => current_token,
        AccountSecretUpdate::Replace { value } => {
            let value = value.trim();
            if value.is_empty() {
                current_token
            } else {
                Some(value.to_string())
            }
        }
        AccountSecretUpdate::Clear => None,
    };
    Ok(AccountEdit {
        key: input.account_id,
        template,
        protocol,
        name: input.name,
        base_url: Some(input.base_url),
        bearer_token,
        initial_billing_kind: input.initial_billing_kind,
        custom_models: input
            .custom_models
            .into_iter()
            .map(account_model_edit)
            .collect::<Result<Vec<_>>>()?,
        model_connection_modes: model_connection_modes(input.model_connection_modes)?,
        model_auto_compact_limits: model_auto_compact_limits(input.model_auto_compact_limits)?,
    })
}

fn account_model_edit(input: AccountModelUpdate) -> Result<AccountModelEdit> {
    Ok(AccountModelEdit {
        model_id: input.model_id,
        display_name: input.display_name,
        protocol: parse_account_protocol(&input.wire_api)?,
        context_window: input.context_window,
        max_output_tokens: input.max_output_tokens,
    })
}

fn model_connection_modes(
    inputs: Vec<AccountModelConnectionUpdate>,
) -> Result<std::collections::BTreeMap<String, ConnectionMode>> {
    let mut modes = std::collections::BTreeMap::new();
    for input in inputs {
        let model_id = input.model_id.trim();
        if model_id.is_empty() {
            return Err(invalid_settings_argument(
                "Model connection model_id must not be empty",
            ));
        }
        if modes
            .insert(
                model_id.to_string(),
                parse_account_connection_mode(&input.connection_mode)?,
            )
            .is_some()
        {
            return Err(invalid_settings_argument("Duplicate model connection mode"));
        }
    }
    Ok(modes)
}

fn model_auto_compact_limits(
    inputs: Vec<AccountModelAutoCompactUpdate>,
) -> Result<std::collections::BTreeMap<String, u64>> {
    let mut limits = std::collections::BTreeMap::new();
    for input in inputs {
        let model_id = input.model_id.trim();
        if model_id.is_empty() {
            return Err(invalid_settings_argument(
                "Model auto compact model_id must not be empty",
            ));
        }
        if input.limit == 0 {
            return Err(invalid_settings_argument(
                "Model auto compact limit must be a positive integer",
            ));
        }
        if limits.insert(model_id.to_string(), input.limit).is_some() {
            return Err(invalid_settings_argument(
                "Duplicate model auto compact limit",
            ));
        }
    }
    Ok(limits)
}

fn parse_account_protocol(value: &str) -> Result<WireApi> {
    match value.trim() {
        "responses" => Ok(WireApi::Responses),
        "chat_completions" => Ok(WireApi::ChatCompletions),
        _ => Err(invalid_settings_argument("Unsupported model wire protocol")),
    }
}

fn parse_account_connection_mode(value: &str) -> Result<ConnectionMode> {
    match value.trim() {
        "web_socket" => Ok(ConnectionMode::WebSocket),
        "http" => Ok(ConnectionMode::Http),
        _ => Err(invalid_settings_argument(
            "Unsupported model connection mode",
        )),
    }
}

pub(super) fn invalid_settings_argument(message: &'static str) -> anyhow::Error {
    anyhow::Error::new(StudioError::invalid_argument(message))
}
