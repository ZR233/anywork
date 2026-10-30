use std::cmp::Ordering;
use std::collections::BTreeMap;

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Serialize};

use super::{AccountConfig, AccountId, AccountModelKey, AgentRoleId, ImageGenerationService};
use crate::model::ModelInfo;
use crate::protocol::{ConnectionMode, ImageGenerationDialect, ProtocolEndpoint};

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
    /// 成员存在但被用户禁用；禁用是 desired 状态，不是配置损坏。
    ModelDisabled {
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

/// 一次图像生成调用的 account 后端。
#[derive(Debug, Clone, PartialEq)]
pub struct ImageGenerationBackend {
    /// 提供该能力的 account 标识。
    pub account_id: AccountId,
    /// 该 account 解析出的运行时 endpoint，已含凭据与 header。
    pub endpoint: ProtocolEndpoint,
    /// 本次选择的生图模型 slug。
    pub model: String,
    /// 服务能力声明的方言。
    pub dialect: ImageGenerationDialect,
}

/// 图像生成后端选择结果。
///
/// `any_declared` 区分「没有任何 account 声明该能力」与「已声明但当前不可用」，
/// 让上层在不注册工具时不把配置事实误报为运行故障。
#[derive(Debug, Clone, PartialEq)]
pub struct ImageGenerationSelection {
    /// 确定选择的可用后端；没有可用后端时为 `None`。
    pub backend: Option<ImageGenerationBackend>,
    /// 至少一个 account 声明了图像生成能力。
    pub any_declared: bool,
}

impl AgentModelConfig {
    /// 选择确定性的图像生成后端。
    ///
    /// account 按 [`AccountId`] 字典序遍历；未声明能力、目录候选未命中声明前缀或凭据
    /// 不可解析的 account 依次跳过。命中后模型先取声明首选序中第一个存在于候选名单者
    /// （显式 pin），否则按版本择优。选择不按名称推断能力、价格或尺寸支持。
    ///
    /// # Errors
    /// 服务能力、目录声明或端点构造失败时返回配置定义错误。
    pub fn image_generation_backend(&self) -> Result<ImageGenerationSelection> {
        let mut any_declared = false;
        for (account_id, account) in &self.accounts {
            let Some(service) = account.image_generation_service()? else {
                continue;
            };
            any_declared = true;
            if service.models.is_empty()
                || (account.resolved_bearer_token().is_none() && account.chatgpt_session.is_none())
            {
                continue;
            }
            let model = image_generation_model(&service);
            return Ok(ImageGenerationSelection {
                backend: Some(ImageGenerationBackend {
                    account_id: account_id.clone(),
                    endpoint: account.to_endpoint()?,
                    model,
                    dialect: service.capabilities.dialect,
                }),
                any_declared,
            });
        }
        Ok(ImageGenerationSelection {
            backend: None,
            any_declared,
        })
    }

    /// Check declaration integrity without discarding persisted choices removed by an endpoint.
    /// Malformed accounts, profiles, duplicate declarations, missing accounts and empty routes
    /// still fail; unreferenced accounts may have empty model declarations. Saving declarations
    /// is separate from strictly resolving new or changed selections with `resolve_route`.
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
        // 禁用是用户的 desired 意图：声明仍合法，但当前不可用于执行。
        if !model.enabled {
            return Ok(ModelRouteAvailability::ModelDisabled {
                account_id: route.account_id.clone(),
                model_id: route.model_id.clone(),
            });
        }
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
        if !model.enabled {
            return Err(PureError::ConfigError(format!(
                "role {role} uses disabled model {}.{}",
                route.account_id, route.model_id
            )));
        }
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
            pricing_mode: account.billing_kind()?.into(),
            role,
            account_id: route.account_id.clone(),
            endpoint: account.to_endpoint()?,
            context,
            model,
            effort: route.effort.clone(),
        })
    }
}

/// 从已声明的候选名单中选择一次调用使用的生图模型。
///
/// 声明首选序中存在于候选名单的第一个模型胜出（显式 pin）；否则版本择优：命中前缀之后的
/// `N[.M[.P]]` 版本高者优先，同版本优先无变体后缀者，再按 slug 字典序；无法解析版本的候选
/// 排在最后。结果只由候选名单与声明决定，不按名称推断能力。
fn image_generation_model(service: &ImageGenerationService) -> String {
    if let Some(pinned) = service
        .capabilities
        .preferred_models
        .iter()
        .find(|slug| service.models.iter().any(|model| model == *slug))
    {
        return pinned.clone();
    }
    let mut candidates = service.models.iter().collect::<Vec<_>>();
    candidates.sort_by(|left, right| {
        match (
            version_rank(left, &service.capabilities.model_prefixes),
            version_rank(right, &service.capabilities.model_prefixes),
        ) {
            (Some((left_version, left_variant)), Some((right_version, right_variant))) => {
                right_version
                    .cmp(&left_version)
                    .then_with(|| left_variant.cmp(&right_variant))
                    .then_with(|| left.cmp(right))
            }
            (Some(_), None) => Ordering::Less,
            (None, Some(_)) => Ordering::Greater,
            (None, None) => left.cmp(right),
        }
    });
    candidates
        .first()
        .map(|slug| (*slug).clone())
        .expect("candidate models were checked to be non-empty")
}

/// 解析命中前缀之后的 `N[.M[.P]]` 版本，并报告是否带变体后缀。
///
/// 返回 `None` 表示前缀之后没有可解析的版本数字；这类候选在版本择优中排在最后。
fn version_rank(slug: &str, prefixes: &[String]) -> Option<((u32, u32, u32), bool)> {
    // 最长命中前缀优先：重叠前缀不能把版本数字吃掉。
    let prefix = prefixes
        .iter()
        .filter(|prefix| slug.starts_with(prefix.as_str()))
        .max_by_key(|prefix| prefix.len())?;
    let remainder = &slug[prefix.len()..];
    let mut version = [0u32; 3];
    let mut component = 0usize;
    let mut digits = String::new();
    let mut parsed = 0usize;
    for character in remainder.chars() {
        if character.is_ascii_digit() {
            digits.push(character);
            parsed += character.len_utf8();
        } else if character == '.' && !digits.is_empty() && component < 2 {
            version[component] = digits.parse().ok()?;
            component += 1;
            digits.clear();
            parsed += 1;
        } else {
            break;
        }
    }
    if !digits.is_empty() {
        version[component] = digits.parse().ok()?;
        component += 1;
    }
    if component == 0 {
        return None;
    }
    let bare = remainder[parsed..]
        .trim_start_matches(['-', '_', '.'])
        .is_empty();
    Some(((version[0], version[1], version[2]), !bare))
}
