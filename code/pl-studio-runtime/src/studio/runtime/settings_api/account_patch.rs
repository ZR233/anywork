//! Narrow account editing and model intents share ConfigRuntime's CAS/credential transaction.

use anyhow::Result;
use pl_model::config::{AccountId, AccountModelCatalogConfig, builtin_account_catalog};
use pl_model::protocol::ConnectionMode;
use pl_protocol::PureError;
use pl_protocol::studio::{
    AccountConnectionMode, AccountModelsPatch, AccountTextPatch, AutoCompactIntent,
    CommandEffectPoint, ModelConnectionIntent, PatchAccountRequest,
    SetAccountModelAutoCompactRequest, SetAccountModelConnectionRequest, SettingsCommandReply,
};

use super::super::StudioRuntime;
use super::account_edit::{account_configuration, invalid_settings_argument};

impl StudioRuntime {
    /// Resolves only changed fields inside the settings command lock; no stale whole-card retry.
    pub async fn patch_account(
        &self,
        request: PatchAccountRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let mut changed = false;
        let authentication = request.authentication.clone();
        let account_id = request.account_id.clone();
        let state = self
            .chatgpt_auth
            .with_claim(&authentication, &account_id, |credential| {
                Ok(self.config_runtime.update_with_credential_intents(
                    request.expected_revision,
                    crate::config::credential_commit::CredentialIntents::for_account(
                        &account_id,
                        &authentication,
                    ),
                    |desired, effective| {
                        let id = AccountId::new(request.account_id.trim())?;
                        let account = effective.models.accounts.get(&id).ok_or_else(|| {
                            PureError::ConfigError("account does not exist".into())
                        })?;
                        let template_id = match request.template_id {
                            AccountTextPatch::Keep => {
                                account.template_id().map(ToString::to_string)
                            }
                            AccountTextPatch::Set { value } => Some(value),
                            AccountTextPatch::Restore => None,
                        };
                        let template = template_id
                            .as_deref()
                            .map(|id| {
                                builtin_account_catalog()?
                                    .templates
                                    .into_iter()
                                    .find(|template| template.id.as_str() == id)
                                    .ok_or_else(|| {
                                        PureError::ConfigError("unknown account template".into())
                                    })
                            })
                            .transpose()?;
                        let default = template.as_ref().map(|template| &template.account);
                        let name = text(
                            request.name,
                            &account.name,
                            default.map(|value| value.name.as_str()),
                        )?;
                        let base_url = text(
                            request.base_url,
                            &account.base_url,
                            default.map(|value| value.base_url.as_str()),
                        )?;
                        let protocol = text(
                            request.protocol,
                            account.protocol.as_str(),
                            default.map(|value| value.protocol.as_str()),
                        )?;
                        let custom_models = match request.custom_models {
                            AccountModelsPatch::Keep => account
                                .editable_models()
                                .iter()
                                .map(|model| pl_protocol::studio::AccountModelUpdate {
                                    model_id: model.model_id.clone(),
                                    display_name: model.display_name.clone(),
                                    wire_api: match model.binding.transport.protocol {
                                        pl_model::protocol::WireApi::Responses => "responses",
                                        pl_model::protocol::WireApi::ChatCompletions => {
                                            "chat_completions"
                                        }
                                    }
                                    .to_owned(),
                                    context_window: model.context_window,
                                    max_output_tokens: model.max_output_tokens,
                                })
                                .collect(),
                            AccountModelsPatch::Set { models } => models,
                            AccountModelsPatch::Restore => Vec::new(),
                        };
                        let removed_manual = account
                            .editable_models()
                            .iter()
                            .filter(|model| {
                                !custom_models
                                    .iter()
                                    .any(|candidate| candidate.model_id.trim() == model.model_id)
                            })
                            .map(|model| model.model_id.clone())
                            .collect::<std::collections::BTreeSet<_>>();
                        let input = pl_protocol::studio::AccountSettingsUpdate {
                            authentication: request.authentication,
                            account_id: id.to_string(),
                            template_id,
                            protocol,
                            name,
                            base_url,
                            secret: request.secret,
                            initial_billing_kind: None,
                            custom_models,
                            model_connection_modes: account
                                .connection_overrides()
                                .iter()
                                .filter(|(model_id, _)| !removed_manual.contains(*model_id))
                                .map(|(id, mode)| {
                                    pl_protocol::studio::AccountModelConnectionUpdate {
                                        model_id: id.clone(),
                                        connection_mode: match mode {
                                            ConnectionMode::Http => "http",
                                            ConnectionMode::WebSocket => "web_socket",
                                        }
                                        .to_owned(),
                                    }
                                })
                                .collect(),
                            model_auto_compact_limits: account
                                .auto_compact_overrides()
                                .iter()
                                .filter(|(model_id, _)| !removed_manual.contains(*model_id))
                                .map(|(id, limit)| {
                                    pl_protocol::studio::AccountModelAutoCompactUpdate {
                                        model_id: id.clone(),
                                        limit: *limit,
                                    }
                                })
                                .collect(),
                        };
                        let mut baseline = effective.clone();
                        if let Some(account) = baseline.models.accounts.get_mut(&id) {
                            for model in &removed_manual {
                                account.remove_manual_model(model)?;
                            }
                        }
                        let next = account_configuration(
                            input,
                            &baseline,
                            credential,
                            &self.config_runtime,
                        )
                        .map_err(|error| PureError::ConfigError(error.to_string()))?;
                        let mut canonical_account = next.models.accounts.get(&id).cloned();
                        if let Some(account) = canonical_account.as_mut() {
                            account.clear_model_catalog_overlay();
                        }
                        changed = canonical_account.as_ref() != desired.models.accounts.get(&id);
                        Ok(next)
                    },
                )?)
            })?;
        if matches!(
            authentication,
            pl_protocol::studio::AccountAuthenticationIntent::ApiKey
        ) {
            self.chatgpt_auth.discard_account(&account_id).await?;
        }
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }

    pub fn set_account_model_auto_compact(
        &self,
        request: SetAccountModelAutoCompactRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let id = AccountId::new(&request.account_id)?;
        let mut changed = false;
        let state =
            self.config_runtime.update_with_effective(
                request.expected_revision,
                |desired, effective| {
                    let mut next = desired.clone();
                    let mut account =
                        effective.models.accounts.get(&id).cloned().ok_or_else(|| {
                            PureError::ConfigError("account does not exist".into())
                        })?;
                    let limit = match request.limit {
                        AutoCompactIntent::Set(limit) => Some(limit),
                        AutoCompactIntent::Clear => None,
                    };
                    account.set_model_auto_compact_override(&request.model_id, limit)?;
                    changed = desired.models.accounts.get(&id).is_some_and(|old| {
                        old.auto_compact_overrides() != account.auto_compact_overrides()
                    });
                    next.models.accounts.insert(id.clone(), account);
                    Ok(next)
                },
            )?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }

    pub fn set_account_model_connection(
        &self,
        request: SetAccountModelConnectionRequest,
    ) -> Result<SettingsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let id = AccountId::new(&request.account_id)?;
        if request.model_id.trim().is_empty() {
            return Err(invalid_settings_argument("Model id must not be empty"));
        }
        let mut changed = false;
        let state =
            self.config_runtime.update_with_effective(
                request.expected_revision,
                |desired, effective| {
                    let mut next = desired.clone();
                    let mut account =
                        effective.models.accounts.get(&id).cloned().ok_or_else(|| {
                            PureError::ConfigError("account does not exist".into())
                        })?;
                    match request.connection {
                        ModelConnectionIntent::Set(mode) => account.set_model_connection_mode(
                            &request.model_id,
                            match mode {
                                AccountConnectionMode::Http => ConnectionMode::Http,
                                AccountConnectionMode::WebSocket => ConnectionMode::WebSocket,
                            },
                        )?,
                        ModelConnectionIntent::Clear => {
                            if !account
                                .effective_catalog(None)?
                                .iter()
                                .any(|entry| entry.model.model_id == request.model_id)
                            {
                                return Err(PureError::ConfigError("model does not exist".into()));
                            }
                            match &mut account.catalog {
                                AccountModelCatalogConfig::Bundled {
                                    connection_overrides,
                                    ..
                                }
                                | AccountModelCatalogConfig::Explicit {
                                    connection_overrides,
                                    ..
                                } => {
                                    connection_overrides.remove(&request.model_id);
                                }
                            }
                        }
                    }
                    changed = desired.models.accounts.get(&id).is_some_and(|old| {
                        old.connection_overrides() != account.connection_overrides()
                    });
                    next.models.accounts.insert(id.clone(), account);
                    Ok(next)
                },
            )?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            request.operation_id,
            &state,
            changed,
            CommandEffectPoint::FutureSession,
        )
    }
}

fn text(patch: AccountTextPatch, current: &str, default: Option<&str>) -> crate::Result<String> {
    match patch {
        AccountTextPatch::Keep => Ok(current.to_owned()),
        AccountTextPatch::Set { value } => Ok(value),
        AccountTextPatch::Restore => default.map(str::to_owned).ok_or_else(|| {
            PureError::ConfigError("custom account field has no template default".into())
        }),
    }
}
