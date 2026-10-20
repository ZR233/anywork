use std::collections::BTreeMap;
use std::collections::BTreeSet;

use crate::{PureError, Result};

use crate::config::{
    AccountId, ModelRouteConfig, ReasoningEffort, STUDIO_CONFIG_SCHEMA_VERSION, StudioConfig,
    StudioRole,
};
use pl_model::config::{
    AccountConfig, AccountModelCatalogConfig, AccountTemplateId, AgentModelConfig,
    builtin_account_catalog,
};
use pl_model::model::ModelInfo;
use pl_model::protocol::ProtocolEndpoint;
use pl_protocol::ThreadModeId;

/// Studio 使用的动态 account template 标识。
///
/// 名称保留“Template”是为了描述 first-run 的用途；候选项完全来自 PL registry，
/// 不再由 Studio 枚举维护。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct AccountTemplateKind(AccountTemplateId);

impl AccountTemplateKind {
    /// # Errors
    /// Returns an error if the bundled catalog cannot be assembled.
    pub fn all() -> Result<Vec<Self>> {
        Ok(builtin_account_catalog()?
            .templates
            .into_iter()
            .map(|template| Self(template.id))
            .collect())
    }

    /// # Errors
    /// Returns catalog assembly errors; an unknown key returns `Ok(None)`.
    pub fn from_key(key: &str) -> Result<Option<Self>> {
        let normalized = key.trim().replace('_', "-");
        Ok(builtin_account_catalog()?
            .templates
            .into_iter()
            .find(|template| template.id.as_str() == normalized)
            .map(|template| Self(template.id)))
    }

    pub fn key(&self) -> &str {
        self.0.as_str()
    }

    pub fn key_prefix(&self) -> &str {
        self.key()
    }

    /// # Errors
    /// Returns an error if the bundled catalog cannot be assembled.
    pub fn display_name(&self) -> Result<String> {
        Ok(self.template()?.display_name)
    }

    pub(crate) fn protocol_endpoint(&self) -> Result<ProtocolEndpoint> {
        self.template()?.account.to_endpoint()
    }

    pub fn default_models(&self) -> Result<Vec<ModelInfo>> {
        self.template()?.account.effective_models(None)
    }

    pub fn default_model_ids(&self) -> Result<Vec<String>> {
        Ok(self
            .default_models()?
            .into_iter()
            .map(|model| model.model_id)
            .collect())
    }

    /// # Errors
    /// Returns an error if the bundled catalog cannot be assembled.
    pub fn account_config(&self) -> Result<AccountConfig> {
        Ok(self.template()?.account)
    }

    fn template(&self) -> Result<pl_model::config::AccountTemplate> {
        Ok(builtin_account_catalog()?
            .templates
            .into_iter()
            .find(|template| template.id == self.0)
            .expect("AccountTemplateKind is created from the builtin registry"))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FirstRunModelDraft {
    pub config: ModelInfo,
}

impl FirstRunModelDraft {
    pub fn from_model_info(config: ModelInfo) -> Self {
        Self { config }
    }

    pub fn custom(model_id: impl Into<String>) -> Self {
        Self {
            config: ModelInfo::compatible(&model_id.into()),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FirstRunAccountDraft {
    pub key: String,
    pub kind: AccountTemplateKind,
    pub name: String,
    pub base_url: Option<String>,
    pub bearer_token: String,
    pub default_model: String,
    pub models: Vec<FirstRunModelDraft>,
}

impl FirstRunAccountDraft {
    /// # Errors
    /// Returns catalog assembly or account endpoint validation errors.
    pub fn from_template(key: impl Into<String>, kind: AccountTemplateKind) -> Result<Self> {
        let endpoint = kind.protocol_endpoint()?;
        let default_model = kind.template()?.suggested_model_id;
        Ok(Self {
            key: key.into(),
            kind,
            name: endpoint.name,
            base_url: Some(endpoint.base_url),
            bearer_token: String::new(),
            default_model,
            models: Vec::new(),
        })
    }

    pub fn all_models(&self) -> Result<Vec<ModelInfo>> {
        let mut models = self.kind.default_models()?;
        models.extend(self.models.iter().map(|model| model.config.clone()));
        Ok(models)
    }

    fn to_account_config(&self) -> Result<AccountConfig> {
        validate_account_key(&self.key)?;
        let bearer_token = self.bearer_token.trim();
        if bearer_token.is_empty() && self.kind.key() != "openai-compatible" {
            return Err(PureError::ConfigError(format!(
                "account {} api key must not be empty",
                self.key
            )));
        }

        let mut account = self.kind.account_config()?;
        account.name = non_empty_trimmed(&self.name, "account name")?;
        account.base_url = trim_optional(self.base_url.as_deref()).ok_or_else(|| {
            let key = &self.key;
            PureError::ConfigError(format!("account {key} base_url must not be empty"))
        })?;
        let default_model = non_empty_trimmed(&self.default_model, "account default_model")?;
        account.bearer_token = (!bearer_token.is_empty()).then(|| bearer_token.to_string());
        match &mut account.catalog {
            AccountModelCatalogConfig::Bundled {
                additional_models, ..
            } => {
                *additional_models = self
                    .models
                    .iter()
                    .map(|model| model.config.clone())
                    .collect();
            }
            AccountModelCatalogConfig::Explicit { models, .. } => {
                *models = self
                    .models
                    .iter()
                    .map(|model| model.config.clone())
                    .collect();
            }
        }

        let models = account.effective_models(None)?;
        validate_models(&self.key, &default_model, &models)?;

        Ok(account)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FirstRunConfigDraft {
    pub default_account: String,
    pub accounts: Vec<FirstRunAccountDraft>,
}

impl FirstRunConfigDraft {
    /// # Errors
    /// Returns catalog assembly or default account validation errors.
    pub fn new_default() -> Result<Self> {
        let kind = AccountTemplateKind::from_key("deepseek")?
            .expect("PL builtin registry contains deepseek template");
        let account = FirstRunAccountDraft::from_template("deepseek", kind)?;
        Ok(Self {
            default_account: account.key.clone(),
            accounts: vec![account],
        })
    }

    pub fn suggest_account_key(&self, kind: &AccountTemplateKind) -> String {
        let prefix = kind.key_prefix();
        if !self.accounts.iter().any(|account| account.key == prefix) {
            return prefix.to_string();
        }

        for index in 2.. {
            let candidate = format!("{prefix}-{index}");
            if !self.accounts.iter().any(|account| account.key == candidate) {
                return candidate;
            }
        }

        unreachable!("unbounded account key suggestion should always return")
    }

    /// # Errors
    /// Returns template errors without adding a partial account draft.
    pub fn add_account(&mut self, kind: AccountTemplateKind) -> Result<&mut FirstRunAccountDraft> {
        let key = self.suggest_account_key(&kind);
        self.accounts
            .push(FirstRunAccountDraft::from_template(key, kind)?);
        Ok(self.accounts.last_mut().expect("account was just pushed"))
    }

    pub fn to_config(&self) -> Result<StudioConfig> {
        if self.accounts.is_empty() {
            return Err(PureError::ConfigError(
                "at least one account is required".to_string(),
            ));
        }

        let default_account_key = non_empty_trimmed(&self.default_account, "default_account")?;
        let mut account_keys = BTreeSet::new();
        let mut accounts = BTreeMap::new();

        for account in &self.accounts {
            if !account_keys.insert(account.key.clone()) {
                return Err(PureError::ConfigError(format!(
                    "duplicate account key: {}",
                    account.key
                )));
            }
            accounts.insert(
                AccountId::new(account.key.clone())?,
                account.to_account_config()?,
            );
        }

        let default_account_id = AccountId::new(default_account_key.clone())?;
        let default_account = accounts.get(&default_account_id).ok_or_else(|| {
            PureError::ConfigError(format!(
                "default account references missing account: {default_account_key}"
            ))
        })?;
        let default_model = self
            .accounts
            .iter()
            .find(|account| account.key == default_account_key)
            .map(|account| account.default_model.trim().to_string())
            .filter(|model| !model.is_empty())
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "default account has no default model: {default_account_key}"
                ))
            })?;
        let default_effort = role_effort(default_account, &default_model)?;
        let route = ModelRouteConfig {
            account_id: default_account_id,
            model_id: default_model,
            effort: default_effort.map(ReasoningEffort::new),
        };

        let config = StudioConfig {
            schema_version: STUDIO_CONFIG_SCHEMA_VERSION,
            models: AgentModelConfig {
                accounts,
                routes: StudioRole::child_roles()
                    .into_iter()
                    .map(|role| (role.id(), route.clone()))
                    .collect(),
            },
            mode_model_routes: BTreeMap::from([
                (ThreadModeId::simple(), route.clone()),
                (ThreadModeId::task(), route),
            ]),
            disabled_system_agents: Default::default(),
            web_search: Default::default(),
            deepseek_web_search: Default::default(),
            runtime: Default::default(),
            instructions: Default::default(),
            skills: Default::default(),
            mcp: Default::default(),
            lsp: Default::default(),
            ui: Default::default(),
        };
        config.validate()?;
        Ok(config)
    }
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

fn validate_account_key(key: &str) -> Result<()> {
    let key = key.trim();
    if key.is_empty() {
        return Err(PureError::ConfigError(
            "account key must not be empty".to_string(),
        ));
    }
    if !key
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_'))
    {
        return Err(PureError::ConfigError(format!(
            "account key contains unsupported characters: {key}"
        )));
    }
    Ok(())
}

fn validate_models(account_key: &str, default_model: &str, models: &[ModelInfo]) -> Result<()> {
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

    let _model = models
        .iter()
        .find(|model| model.model_id == default_model)
        .ok_or_else(|| {
            PureError::ConfigError(format!(
                "account {account_key} default_model is not in models: {default_model}"
            ))
        })?;
    Ok(())
}

fn role_effort(account: &AccountConfig, model_id: &str) -> Result<Option<String>> {
    let models = account.effective_models(None)?;
    let model = models
        .iter()
        .find(|model| model.model_id == model_id)
        .ok_or_else(|| {
            PureError::ConfigError(format!("default model is missing from account: {model_id}"))
        })?;
    Ok(model.default_effort())
}
