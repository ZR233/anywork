use std::collections::BTreeMap;

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Serialize};

use super::{AccountConfig, AccountId, AccountModelKey, AgentRoleId};
use crate::model::ModelInfo;
use crate::protocol::{ConnectionMode, ProtocolEndpoint};

/// 模型推理强度的产品无关字符串值。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(transparent)]
pub struct ReasoningEffort(String);

impl ReasoningEffort {
    /// 创建推理强度值；最终有效性由具体模型参数目录校验。
    pub fn new(effort: impl Into<String>) -> Self {
        Self(effort.into())
    }

    /// 返回配置文本。
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }

    /// 是否明确禁用推理。
    pub fn is_none(&self) -> bool {
        self.as_str() == "none"
    }
}

/// 动态 agent 角色到 account/model 的唯一路由。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ModelRouteConfig {
    pub account_id: AccountId,
    pub model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<ReasoningEffort>,
}

impl ModelRouteConfig {
    /// 返回该选择对应的稳定目录身份。
    pub fn key(&self) -> Result<AccountModelKey> {
        AccountModelKey::new(self.account_id.as_str(), self.model_id.clone())
    }
}

/// 可嵌入任意产品配置文档的模型配置。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct AgentModelConfig {
    pub accounts: BTreeMap<AccountId, AccountConfig>,
    pub routes: BTreeMap<AgentRoleId, ModelRouteConfig>,
}

/// An observation can make an intact desired route unavailable without corrupting config.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelRouteAvailability {
    Available,
    ModelUnavailable {
        account_id: AccountId,
        model_id: String,
    },
    TypeUnsupported {
        account_id: AccountId,
        model_id: String,
        exclusions: Vec<crate::model::ModelTypeExclusion>,
    },
    EffortUnavailable {
        account_id: AccountId,
        model_id: String,
    },
    ConnectionUnavailable {
        account_id: AccountId,
        model_id: String,
        connection_mode: ConnectionMode,
    },
}

/// 完成引用校验后可直接创建模型 account 的角色路由。
#[derive(Debug, Clone)]
pub struct ResolvedModelRoute {
    pub pricing_mode: pl_protocol::PricingMode,
    pub role: AgentRoleId,
    pub account_id: AccountId,
    pub endpoint: ProtocolEndpoint,
    pub model: ModelInfo,
    pub context: pl_protocol::ModelContextResolution,
    pub effort: Option<ReasoningEffort>,
}

impl ResolvedModelRoute {
    /// 返回该已解析路由的稳定目录身份。
    pub fn key(&self) -> AccountModelKey {
        AccountModelKey {
            account_id: self.account_id.as_str().to_owned(),
            model_id: self.model.model_id.clone(),
        }
    }

    /// Interprets this route's reasoning choice once for model request preparation.
    pub fn reasoning_config(&self) -> Option<crate::completion::ReasoningConfig> {
        self.effort
            .as_ref()
            .map(|effort| crate::completion::ReasoningConfig {
                effort: Some(effort.as_str().to_owned()),
                summary: Some(if effort.is_none() {
                    crate::completion::ReasoningSummary::Disabled
                } else {
                    crate::completion::ReasoningSummary::Enabled
                }),
            })
    }
}

impl AgentModelConfig {
    /// Check declaration integrity without discarding persisted choices removed by an endpoint.
    /// Malformed accounts, profiles, duplicate declarations, missing accounts and empty routes
    /// still fail. Call `route_availability` separately; edits must use strict `validate`.
    pub fn validate_declarations(&self) -> Result<()> {
        if self.accounts.is_empty() {
            return Err(PureError::ConfigError(
                "at least one account is required".into(),
            ));
        }
        for (id, account) in &self.accounts {
            account.validate_declarations(id)?;
        }
        for route in self.routes.values() {
            self.route_availability(route)?;
        }
        Ok(())
    }

    /// Typed availability, not English error-message matching. This is not edit authorization.
    /// # Errors
    /// Structural/account errors remain fatal, rather than becoming model unavailability.
    pub fn route_availability(&self, route: &ModelRouteConfig) -> Result<ModelRouteAvailability> {
        if route.model_id.trim().is_empty() {
            return Err(PureError::ConfigError("model route has empty model".into()));
        }
        let account = self.accounts.get(&route.account_id).ok_or_else(|| {
            PureError::ConfigError(format!(
                "model route references missing account: {}",
                route.account_id
            ))
        })?;
        account.validate_declarations(&route.account_id)?;
        let models = account.effective_catalog(None)?;
        let Some(model) = models
            .iter()
            .find(|entry| entry.model.model_id == route.model_id)
        else {
            if account.discovery_profile()?.is_none() {
                return Err(PureError::ConfigError(format!(
                    "model route references missing model: {}",
                    route.model_id
                )));
            }
            return Ok(ModelRouteAvailability::ModelUnavailable {
                account_id: route.account_id.clone(),
                model_id: route.model_id.clone(),
            });
        };
        let support = model.type_support(crate::model::ModelType::Text);
        if !support.exclusions.is_empty() {
            return Ok(ModelRouteAvailability::TypeUnsupported {
                account_id: route.account_id.clone(),
                model_id: route.model_id.clone(),
                exclusions: support.exclusions,
            });
        }
        let model = &model.model;
        if let Some(connection_mode) = account.connection_overrides().get(&route.model_id)
            && !model
                .binding
                .transport
                .supported_connection_modes
                .contains(connection_mode)
        {
            // Declaration validation already rejects unsupported manual/Explicit choices.
            return Ok(ModelRouteAvailability::ConnectionUnavailable {
                account_id: route.account_id.clone(),
                model_id: route.model_id.clone(),
                connection_mode: *connection_mode,
            });
        }
        let candidates = model.supported_efforts();
        let valid = match &route.effort {
            None => candidates.is_empty(),
            Some(effort) => candidates.iter().any(|c| c == effort.as_str()),
        };
        if !valid {
            // Local selections stay strict unless a shared online declaration withdrew
            // their candidates. Keep that saved route explicitly unavailable.
            let observed_candidates = model.observation.as_ref().is_some_and(|observation| {
                observation
                    .fields
                    .contains_key(&crate::model::ModelMetadataField::Parameters)
                    || observation
                        .fields
                        .contains_key(&crate::model::ModelMetadataField::Reasoning)
            });
            if !observed_candidates
                && (account.discovery_profile()?.is_none()
                    || account
                        .editable_models()
                        .iter()
                        .any(|manual| manual.model_id == route.model_id))
            {
                return Err(PureError::ConfigError(
                    "model route has invalid effort selection".into(),
                ));
            }
            return Ok(ModelRouteAvailability::EffortUnavailable {
                account_id: route.account_id.clone(),
                model_id: route.model_id.clone(),
            });
        }
        Ok(ModelRouteAvailability::Available)
    }

    /// 校验所有 account 与动态角色路由引用。
    pub fn validate(&self) -> Result<()> {
        if self.accounts.is_empty() {
            return Err(PureError::ConfigError(
                "at least one account is required".to_string(),
            ));
        }
        for (account_id, account) in &self.accounts {
            account.validate(account_id)?;
        }
        for role in self.routes.keys() {
            self.resolve(role)?;
        }
        Ok(())
    }

    /// 解析一个动态角色，并返回选中的 account、模型和推理强度。
    pub fn resolve(&self, role: &AgentRoleId) -> Result<ResolvedModelRoute> {
        let route = self.routes.get(role).ok_or_else(|| {
            PureError::ConfigError(format!("missing model route for role: {role}"))
        })?;
        self.resolve_route(role.clone(), route)
    }

    /// 解析调用方持有的 route selector，并以给定角色标识装配运行时路由。
    pub fn resolve_route(
        &self,
        role: AgentRoleId,
        route: &ModelRouteConfig,
    ) -> Result<ResolvedModelRoute> {
        if route.model_id.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "role {role} has empty model"
            )));
        }
        let account = self.accounts.get(&route.account_id).ok_or_else(|| {
            PureError::ConfigError(format!(
                "role {role} references missing account: {}",
                route.account_id
            ))
        })?;
        let models = account.effective_catalog(None)?;
        let model = models
            .iter()
            .find(|entry| entry.model.model_id == route.model_id)
            .cloned()
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "role {role} references missing model: {}.{}",
                    route.account_id, route.model_id
                ))
            })?;
        let context = model.context.clone();
        let support = model.type_support(crate::model::ModelType::Text);
        if !support.exclusions.is_empty() {
            return Err(PureError::ConfigError(format!(
                "model {}.{} is unavailable: {:?}",
                route.account_id, route.model_id, support.exclusions
            )));
        }
        let model = model.model;
        if let Some(connection_mode) = account.connection_overrides().get(&route.model_id)
            && !model
                .binding
                .transport
                .supported_connection_modes
                .contains(connection_mode)
        {
            // effective_models may preserve a withdrawn remote override for display only.
            // Never silently bind an actual request to the declaration's default instead.
            return Err(PureError::ConfigError(format!(
                "role {role} uses unsupported connection mode {connection_mode:?} for model {}.{}",
                route.account_id, route.model_id
            )));
        }
        let candidates = model.supported_efforts();
        match (&route.effort, candidates.is_empty()) {
            (Some(_), true) => {
                return Err(PureError::ConfigError(format!(
                    "role {role} sets effort for model without an effort parameter: {}.{}",
                    route.account_id, route.model_id
                )));
            }
            (None, false) => {
                return Err(PureError::ConfigError(format!(
                    "role {role} must select an effort for model {}.{}",
                    route.account_id, route.model_id
                )));
            }
            (Some(effort), false)
                if !candidates
                    .iter()
                    .any(|candidate| candidate == effort.as_str()) =>
            {
                return Err(PureError::ConfigError(format!(
                    "role {role} uses unsupported effort '{}' for model {}.{}",
                    effort.as_str(),
                    route.account_id,
                    route.model_id
                )));
            }
            _ => {}
        }
        Ok(ResolvedModelRoute {
            pricing_mode: account.pricing_mode,
            role,
            account_id: route.account_id.clone(),
            endpoint: account.to_endpoint()?,
            context,
            model,
            effort: route.effort.clone(),
        })
    }
}
