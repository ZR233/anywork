use std::collections::BTreeMap;
use std::collections::BTreeSet;

use crate::{PureError, Result};

use crate::config::{AccountId, ModelRouteConfig, ReasoningEffort, StudioConfig};
use crate::first_run::AccountTemplateKind;
use pl_model::config::{
    AccountConfig, AccountModelCatalogConfig, AccountTemplateId, builtin_account_catalog,
};
use pl_model::model::{ModelInfo, ModelTransportProfile};
use pl_model::protocol::{ConnectionMode, ProtocolEndpoint, ProtocolKind, WireApi};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountModelEdit {
    pub model_id: String,
    pub display_name: String,
    pub protocol: WireApi,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountEdit {
    /// 账号稳定标识；编辑按该 ID 定位同一资源，不提供改名路径。
    pub key: String,
    /// 可选的内置账号模板引用；模板是创建默认值与创建协议的唯一来源。
    pub template: Option<AccountTemplateId>,
    /// 明确的厂商协议选择；模板账号由模板决定，自定义账号使用该显式值。
    pub protocol: ProtocolKind,
    pub name: String,
    pub base_url: Option<String>,
    pub bearer_token: Option<String>,
    pub pricing_mode: pl_protocol::PricingMode,
    pub custom_models: Vec<AccountModelEdit>,
    pub model_connection_modes: BTreeMap<String, ConnectionMode>,
    /// 该 account 实例完整的上下文压缩阈值用户覆盖集合；未列出模型使用默认值。
    pub model_auto_compact_limits: BTreeMap<String, u64>,
}

/// # Errors
/// Returns the bundled catalog assembly error without treating it as a missing template.
pub fn account_template_kind(account: &AccountConfig) -> Result<Option<AccountTemplateKind>> {
    account
        .template_id()
        .map(|template| AccountTemplateKind::from_key(template.as_str()))
        .transpose()
        .map(Option::flatten)
}

impl AccountModelEdit {
    fn to_model_info(&self, current: Option<&ModelInfo>) -> Result<ModelInfo> {
        let model_id = non_empty_trimmed(&self.model_id, "model model_id")?;
        let mut model = current
            .filter(|model| model.model_id == model_id)
            .cloned()
            .unwrap_or_else(|| ModelInfo::compatible(&model_id));
        if let Some(current) = current
            && current.model_id == model_id
            && current.display_name
                == trim_optional(Some(&self.display_name)).unwrap_or_else(|| model_id.clone())
            && current.context_window == self.context_window
            && current.max_output_tokens == self.max_output_tokens
            && current.binding.transport.protocol == self.protocol
        {
            return Ok(current.clone());
        }
        model.display_name =
            trim_optional(Some(&self.display_name)).unwrap_or_else(|| model_id.clone());
        if self.context_window == Some(0)
            || self.max_output_tokens == Some(0)
            || self
                .max_output_tokens
                .zip(self.context_window)
                .is_some_and(|(output, window)| output > window)
        {
            return Err(PureError::ConfigError(
                "custom model budgets must be positive and output must fit its context".into(),
            ));
        }
        model.context_window = self.context_window;
        model.max_context_window = self.context_window;
        model.max_output_tokens = self.max_output_tokens;
        model.binding.request.protocol = match self.protocol {
            WireApi::Responses => {
                pl_model::model::ModelProtocolOptions::Responses(Default::default())
            }
            WireApi::ChatCompletions => pl_model::model::ModelProtocolOptions::ChatCompletions(
                pl_model::model::ChatRequestOptions {
                    include_usage: true,
                    ..Default::default()
                },
            ),
        };
        model.binding.transport = ModelTransportProfile {
            protocol: self.protocol,
            supported_connection_modes: vec![ConnectionMode::Http],
            default_connection_mode: ConnectionMode::Http,
        };
        model
            .binding
            .transport
            .validate(&model_id)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
        Ok(model)
    }
}

impl AccountEdit {
    fn account_key(&self) -> Result<String> {
        validate_account_key(&self.key)
    }

    fn to_account_config(&self, current: Option<&AccountConfig>) -> Result<EditedAccount> {
        let account_key = self.account_key()?;
        let name = non_empty_trimmed(&self.name, "account name")?;
        let base_url = trim_optional(self.base_url.as_deref()).ok_or_else(|| {
            PureError::ConfigError("account base_url must not be empty".to_string())
        })?;
        let bearer_token = trim_optional(self.bearer_token.as_deref());
        let current_models = current
            .map(AccountConfig::editable_models)
            .unwrap_or_default();
        let custom_models = self
            .custom_models
            .iter()
            .map(|edit| {
                edit.to_model_info(
                    current_models
                        .iter()
                        .find(|model| model.model_id.trim() == edit.model_id.trim()),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let template = match &self.template {
            Some(template_id) => Some(
                builtin_account_catalog()?
                    .templates
                    .into_iter()
                    .find(|template| &template.id == template_id)
                    .ok_or_else(|| {
                        PureError::ConfigError(format!(
                            "account {account_key} references unknown template: {template_id}"
                        ))
                    })?,
            ),
            None => None,
        };
        // 模板是模板账号创建协议的来源；自定义账号使用显式选择。
        let template_protocol = template.as_ref().map(|template| template.account.protocol);
        let mut config = match &self.template {
            Some(template_id) => {
                let template = template.expect("resolved template for this account edit");
                let mut config = match current {
                    Some(current) => {
                        let mut config = current.clone();
                        if current.template_id() != Some(template_id) {
                            config.template = Some(template_id.clone());
                            config.protocol = template.account.protocol;
                            config.catalog = template.account.catalog;
                            config.capabilities = template.account.capabilities;
                            config.clear_model_catalog_overlay();
                        }
                        config
                    }
                    None => template.account,
                };
                if current.and_then(AccountConfig::template_id) == Some(template_id) {
                    let current = current.expect("matching current template is present");
                    config.bearer_token_env = current.bearer_token_env.clone();
                    config.http_headers = current.http_headers.clone();
                    config.tool_wire_policy = current.tool_wire_policy;
                    config.apply_patch_tool_type = current.apply_patch_tool_type;
                    config.capabilities = current.capabilities.clone();
                }
                match &mut config.catalog {
                    AccountModelCatalogConfig::Bundled {
                        additional_models, ..
                    } => *additional_models = custom_models,
                    AccountModelCatalogConfig::Explicit { models, .. } => *models = custom_models,
                }
                config
            }
            None => {
                let current_custom = current.filter(|account| account.template_id().is_none());
                let info = ProtocolEndpoint {
                    protocol: self.protocol,
                    name: name.clone(),
                    base_url: base_url.clone(),
                    bearer_token: bearer_token.clone(),
                    http_headers: current_custom.and_then(|account| account.http_headers.clone()),
                    tool_wire_policy: current_custom
                        .map(|account| account.tool_wire_policy)
                        .unwrap_or_default(),
                    apply_patch_tool_type: current_custom
                        .and_then(|account| account.apply_patch_tool_type),
                    service_capabilities: current_custom
                        .and_then(|account| account.service_capabilities().ok())
                        .unwrap_or_default(),
                };
                let fresh = AccountConfig::from_explicit_models(info, custom_models);
                let mut config = match current {
                    Some(current) => {
                        let mut config = current.clone();
                        config.template = None;
                        config.protocol = fresh.protocol;
                        config.catalog = fresh.catalog;
                        config.capabilities = fresh.capabilities;
                        config.clear_model_catalog_overlay();
                        config
                    }
                    None => fresh,
                };
                config.bearer_token_env =
                    current_custom.and_then(|account| account.bearer_token_env.clone());
                config
            }
        };
        config.replace_model_auto_compact_overrides(self.model_auto_compact_limits.clone())?;
        match &mut config.catalog {
            AccountModelCatalogConfig::Bundled {
                connection_overrides,
                ..
            }
            | AccountModelCatalogConfig::Explicit {
                connection_overrides,
                ..
            } => {
                *connection_overrides = self.model_connection_modes.clone();
            }
        }
        config.pricing_mode = self.pricing_mode;
        if let Some(protocol) = template_protocol {
            config.protocol = protocol;
        }
        config.name = name;
        config.base_url = base_url;
        config.bearer_token = bearer_token;
        let models = config.effective_models(None)?;
        if config.discovery_profile()?.is_none() {
            validate_models(&account_key, &models)?;
        }

        Ok(EditedAccount {
            id: AccountId::new(account_key)?,
            config,
        })
    }

    /// Applies one account edit while preserving every other settings domain.
    ///
    /// The old aggregate editor rebuilt accounts, mode routes and role routes
    /// from one page snapshot.  That made a stale settings page capable of
    /// reverting an unrelated route.  Single account commands are deliberately
    /// constrained to an existing id or a new id; identity changes have their
    /// own explicit removal/rename workflow and cannot silently rewrite routes.
    pub fn to_single_config(&self, current: &StudioConfig) -> Result<StudioConfig> {
        let account_key = self.account_key()?;
        let account_id = AccountId::new(account_key)?;
        let edited = self.to_account_config(current.models.accounts.get(&account_id))?;
        let mut next = current.clone();
        next.models.accounts.insert(edited.id, edited.config);
        next.validate_declarations()?;
        Ok(next)
    }
}

/// Removes one account.  Route migration is only performed when the caller
/// explicitly supplies a replacement account; an old page snapshot can never
/// cause an implicit route rewrite.
pub fn remove_account(
    current: &StudioConfig,
    account_key: &str,
    replacement_key: Option<&str>,
) -> Result<StudioConfig> {
    if current.models.accounts.len() <= 1 {
        return Err(PureError::ConfigError(
            "at least one account is required".into(),
        ));
    }
    let account_id = AccountId::new(account_key.trim())?;
    if !current.models.accounts.contains_key(&account_id) {
        return Err(PureError::ConfigError(format!(
            "account does not exist: {account_id}"
        )));
    }
    let replacement_id = replacement_key
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(AccountId::new)
        .transpose()?;
    if replacement_id.as_ref() == Some(&account_id) {
        return Err(PureError::ConfigError(
            "account replacement must differ from the removed account".into(),
        ));
    }
    let replacement = replacement_id
        .as_ref()
        .map(|id| {
            current
                .models
                .accounts
                .get(id)
                .ok_or_else(|| PureError::ConfigError(format!("account does not exist: {id}")))
        })
        .transpose()?;
    let mut next = current.clone();
    next.models.accounts.remove(&account_id);

    let migrate_route = |route: &mut ModelRouteConfig| -> Result<()> {
        if route.account_id != account_id {
            return Ok(());
        }
        let replacement_id = replacement_id.as_ref().ok_or_else(|| {
            PureError::ConfigError(format!(
                "account {account_id} is still referenced by a route; specify replacement_account_id"
            ))
        })?;
        let replacement = replacement.expect("validated replacement account");
        let models = replacement.effective_models(None)?;
        let model = models
            .iter()
            .find(|model| model.model_id == route.model_id)
            .or_else(|| models.first())
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "replacement account has no usable models: {replacement_id}"
                ))
            })?;
        let effort = route
            .effort
            .as_ref()
            .filter(|effort| {
                model
                    .supported_efforts()
                    .iter()
                    .any(|value| value == effort.as_str())
            })
            .cloned()
            .or_else(|| model.default_effort().map(ReasoningEffort::new));
        route.account_id = replacement_id.clone();
        route.model_id = model.model_id.clone();
        route.effort = effort;
        Ok(())
    };
    for route in next.models.routes.values_mut() {
        migrate_route(route)?;
    }
    for route in next.mode_model_routes.values_mut() {
        migrate_route(route)?;
    }
    next.validate_declarations()?;
    Ok(next)
}

struct EditedAccount {
    id: AccountId,
    config: AccountConfig,
}

fn non_empty_trimmed(value: &str, name: &str) -> Result<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(PureError::ConfigError(format!("{name} must not be empty")));
    }
    Ok(trimmed.to_string())
}

fn trim_optional(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn validate_account_key(key: &str) -> Result<String> {
    let key = non_empty_trimmed(key, "account key")?;
    if !key
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_'))
    {
        return Err(PureError::ConfigError(format!(
            "account key contains unsupported characters: {key}"
        )));
    }
    Ok(key)
}

/// 只校验模型声明的结构完整性；具体模型选择属于角色/Mode/Thread 路由，
/// 账号不保存第二份默认模型。
fn validate_models(account_key: &str, models: &[ModelInfo]) -> Result<()> {
    let mut model_ids = BTreeSet::new();
    for model in models {
        if model.model_id.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "account {account_key} has a model with empty model_id"
            )));
        }
        if !model_ids.insert(model.model_id.clone()) {
            return Err(PureError::ConfigError(format!(
                "account {account_key} has duplicate model model_id: {}",
                model.model_id
            )));
        }
    }
    Ok(())
}
