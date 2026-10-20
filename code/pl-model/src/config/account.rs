use std::collections::{BTreeMap, BTreeSet, HashMap};

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Serialize};

use super::{AccountId, AccountTemplateId, ModelCatalogId, builtin_model_catalog};
use crate::model::ModelInfo;
use crate::protocol::{
    ApplyPatchToolType, ConnectionMode, ProtocolEndpoint, ProtocolServiceCapabilities,
    StandaloneWebSearchDialect, ToolWirePolicy,
};

/// Account 模型目录来源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum AccountModelCatalogConfig {
    /// 引用 PL 内置只读目录；显式模型可补充成员或覆盖同 ID 的本地定义。
    Bundled {
        catalog: ModelCatalogId,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        additional_models: Vec<ModelInfo>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        connection_overrides: BTreeMap<String, ConnectionMode>,
        /// 按模型 model_id 索引的上下文压缩阈值用户覆盖；缺省表示使用模型默认值。
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        auto_compact_overrides: BTreeMap<String, u64>,
    },
    /// 完全由产品配置提供的模型目录。
    Explicit {
        models: Vec<ModelInfo>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        connection_overrides: BTreeMap<String, ConnectionMode>,
        /// 按模型 model_id 索引的上下文压缩阈值用户覆盖；缺省表示使用模型默认值。
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        auto_compact_overrides: BTreeMap<String, u64>,
    },
}

/// Account 服务能力的配置来源。
///
/// template 实例通常继承 registry 默认能力；显式配置可覆盖任意兼容 endpoint。
///
/// 当前 wire 值只有 `source = "template_defaults"`；旧 `preset_defaults` 只在配置
/// 22→23 迁移边界转换，正常读取不接受。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum AccountCapabilitySelection {
    #[default]
    TemplateDefaults,
    Explicit(ProtocolServiceCapabilities),
}

/// 有效目录成员的来源。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccountModelOrigin {
    Bundled,
    Online,
    Manual,
}

/// 唯一有效目录中的一条成员，携带来源供投影与 GUI 区分。
#[derive(Debug, Clone, PartialEq)]
pub struct AccountModelEntry {
    pub model: ModelInfo,
    pub origin: AccountModelOrigin,
    pub context: pl_protocol::ModelContextResolution,
}

impl AccountModelEntry {
    pub fn new(model: ModelInfo, origin: AccountModelOrigin) -> Self {
        Self {
            context: model.resolve_context(None),
            model,
            origin,
        }
    }

    pub fn type_support(
        &self,
        model_type: crate::model::ModelType,
    ) -> crate::model::ModelTypeSupport {
        use crate::model::{ModelModality, ModelType, ModelTypeExclusion as Exclusion};
        let mut exclusions = Vec::new();
        match model_type {
            ModelType::Text => {
                if !self
                    .model
                    .capabilities
                    .supports_input_modality(ModelModality::Text)
                {
                    exclusions.push(Exclusion::TextInputUnsupported);
                }
                if !self
                    .model
                    .capabilities
                    .supports_output_modality(ModelModality::Text)
                {
                    exclusions.push(Exclusion::TextOutputUnsupported);
                }
            }
        }
        if let Some(reason) = self.context.unavailable {
            exclusions.push(match reason {
                pl_protocol::ModelContextUnavailable::WindowUnknown => {
                    Exclusion::ContextWindowUnknown
                }
                pl_protocol::ModelContextUnavailable::InvalidParameters => {
                    Exclusion::ContextParametersInvalid
                }
                pl_protocol::ModelContextUnavailable::InputBudgetExhausted => {
                    Exclusion::InputBudgetExhausted
                }
            });
        }
        crate::model::ModelTypeSupport {
            model_type,
            exclusions,
        }
    }
}

/// 可由产品配置文件组合使用的 Account 值对象。
///
/// 具体默认模型不属于 Account；调用方必须通过角色路由选择模型。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AccountConfig {
    #[serde(default)]
    pub protocol: crate::protocol::ProtocolKind,
    #[serde(default)]
    pub pricing_mode: pl_protocol::PricingMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<AccountTemplateId>,
    pub name: String,
    pub base_url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bearer_token: Option<String>,
    /// 可选的凭证环境变量名；显式 token 始终优先。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bearer_token_env: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_headers: Option<HashMap<String, String>>,
    #[serde(default)]
    pub tool_wire_policy: ToolWirePolicy,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    #[serde(default)]
    pub capabilities: AccountCapabilitySelection,
    pub catalog: AccountModelCatalogConfig,
    /// Successful endpoint observation, never persisted as desired user configuration.
    #[serde(skip)]
    model_catalog_overlay: Option<Vec<ModelInfo>>,
    #[serde(skip)]
    resolved_catalog: Option<Vec<AccountModelEntry>>,
}

impl AccountConfig {
    /// 构造内置 DeepSeek account template，不附带任何产品角色默认值。
    pub fn deepseek_template() -> Self {
        Self::from_bundled_catalog(
            ProtocolEndpoint::deepseek(None),
            ModelCatalogId::new("deepseek").expect("static model catalog id is valid"),
            Vec::new(),
        )
        .with_template(
            AccountTemplateId::new("deepseek").expect("static account template id is valid"),
        )
    }

    /// 从 PL 内置模型目录创建 account 配置。
    pub fn from_bundled_catalog(
        info: ProtocolEndpoint,
        catalog: ModelCatalogId,
        additional_models: Vec<ModelInfo>,
    ) -> Self {
        Self::from_parts(
            info,
            AccountModelCatalogConfig::Bundled {
                catalog,
                additional_models,
                connection_overrides: BTreeMap::new(),
                auto_compact_overrides: BTreeMap::new(),
            },
        )
    }

    /// 从完全显式的模型目录创建 account 配置。
    pub fn from_explicit_models(info: ProtocolEndpoint, models: Vec<ModelInfo>) -> Self {
        Self::from_parts(
            info,
            AccountModelCatalogConfig::Explicit {
                models,
                connection_overrides: BTreeMap::new(),
                auto_compact_overrides: BTreeMap::new(),
            },
        )
    }

    fn from_parts(info: ProtocolEndpoint, catalog: AccountModelCatalogConfig) -> Self {
        let service_capabilities = info.service_capabilities.clone();
        Self {
            protocol: info.protocol,
            template: None,
            pricing_mode: pl_protocol::PricingMode::Catalog,
            name: info.name,
            base_url: info.base_url,
            bearer_token: info.bearer_token,
            bearer_token_env: None,
            http_headers: info.http_headers,
            tool_wire_policy: info.tool_wire_policy,
            apply_patch_tool_type: info.apply_patch_tool_type,
            capabilities: AccountCapabilitySelection::Explicit(service_capabilities),
            catalog,
            model_catalog_overlay: None,
            resolved_catalog: None,
        }
    }

    /// 记录创建该实例所使用的内置 template。
    pub fn with_template(mut self, template: AccountTemplateId) -> Self {
        self.pricing_mode = match template.as_str() {
            "zhipu-coding-plan" | "mimo-token-plan" | "openai-compatible" => {
                pl_protocol::PricingMode::Disabled
            }
            _ => pl_protocol::PricingMode::Catalog,
        };
        self.template = Some(template);
        self.capabilities = AccountCapabilitySelection::TemplateDefaults;
        self
    }

    /// 解析 template 默认值或实例显式覆盖后的服务能力。
    pub fn service_capabilities(&self) -> Result<ProtocolServiceCapabilities> {
        match &self.capabilities {
            AccountCapabilitySelection::Explicit(capabilities) => Ok(capabilities.clone()),
            AccountCapabilitySelection::TemplateDefaults => match self.template_id() {
                Some(template_id) => super::builtin_account_catalog()?
                    .templates
                    .into_iter()
                    .find(|template| &template.id == template_id)
                    .map(|template| {
                        let mut capabilities = template.service_capabilities;
                        if self.base_url.trim_end_matches('/')
                            != template.account.base_url.trim_end_matches('/')
                        {
                            capabilities.remote_compaction = false;
                            capabilities.history_instruction_role = Default::default();
                            capabilities.files = Default::default();
                            capabilities.responses_tools = Default::default();
                            capabilities.web_search.hosted_responses = false;
                            capabilities.prompt_cache = Default::default();
                            // 仅撤销 DeepSeek 原生 standalone 搜索：非 canonical DeepSeek endpoint
                            // 必须显式声明该方言。其余 standalone（如 OpenAI `/alpha/search`）
                            // 保留既有继承语义，不因 base_url 覆盖被禁用。
                            if matches!(
                                capabilities.web_search.standalone,
                                Some(StandaloneWebSearchDialect::DeepSeekToolsApi)
                            ) {
                                capabilities.web_search.standalone = None;
                            }
                        }
                        capabilities
                    })
                    .ok_or_else(|| {
                        PureError::ConfigError(format!("unknown account template: {template_id}"))
                    }),
                None => Ok(ProtocolServiceCapabilities::default()),
            },
        }
    }

    /// 返回实例绑定的内置 template；自定义 account 返回 `None`。
    pub fn template_id(&self) -> Option<&AccountTemplateId> {
        self.template.as_ref()
    }

    /// 查询有效模型列表；None 返回全部。类型条件须在全局目录合并后使用。
    /// 远程目录撤下的旧连接 override 保留在配置中，不注入当前声明；展示可继续发布，
    /// 实际请求必须经过 `AgentModelConfig::resolve_route` 的严格连接选择校验。
    pub fn effective_models(
        &self,
        model_type: Option<crate::model::ModelType>,
    ) -> Result<Vec<ModelInfo>> {
        Ok(self
            .effective_catalog(model_type)?
            .into_iter()
            .map(|entry| entry.model)
            .collect())
    }

    /// 有效目录查询；每条成员携带来源，不从默认定义补回在线名单缺失的模型。
    /// 类型筛选消费已合并的定义，不用于发现阶段或改变供应商成员。
    pub fn effective_catalog(
        &self,
        model_type: Option<crate::model::ModelType>,
    ) -> Result<Vec<AccountModelEntry>> {
        let catalog = if let Some(catalog) = &self.resolved_catalog {
            catalog.clone()
        } else {
            apply_connection_overrides(
                self.catalog_membership()?,
                self.connection_overrides(),
                self.discovery_profile()?.is_some(),
                self.editable_models(),
            )?
            .into_iter()
            .map(|mut entry| {
                entry.context = entry.model.resolve_context(
                    self.auto_compact_overrides()
                        .get(&entry.model.model_id)
                        .copied(),
                );
                entry
            })
            .collect()
        };
        Ok(catalog
            .into_iter()
            .filter(|entry| {
                model_type.is_none_or(|kind| entry.type_support(kind).exclusions.is_empty())
            })
            .collect())
    }

    fn catalog_membership(&self) -> Result<Vec<AccountModelEntry>> {
        let (defaults, additional) = match &self.catalog {
            AccountModelCatalogConfig::Bundled {
                catalog,
                additional_models,
                ..
            } => (
                builtin_model_catalog(catalog)?.models,
                additional_models.as_slice(),
            ),
            AccountModelCatalogConfig::Explicit { models, .. } => (Vec::new(), models.as_slice()),
        };
        let mut local = defaults
            .iter()
            .cloned()
            .map(|model| {
                (
                    model.model_id.clone(),
                    AccountModelEntry::new(model, AccountModelOrigin::Bundled),
                )
            })
            .collect::<BTreeMap<_, _>>();
        for model in additional {
            local.insert(
                model.model_id.clone(),
                AccountModelEntry::new(model.clone(), AccountModelOrigin::Manual),
            );
        }
        let Some(overlay) = &self.model_catalog_overlay else {
            return Ok(local.into_values().collect());
        };
        let mut entries = local
            .iter()
            .filter(|(_, entry)| entry.origin == AccountModelOrigin::Manual)
            .map(|(key, entry)| (key.clone(), entry.clone()))
            .collect::<BTreeMap<_, _>>();
        let discovery = self.discovery_profile()?;
        for observed in overlay {
            let declared = local.get(&observed.model_id);
            let enriched = declared.and_then(|entry| {
                discovery.as_ref().and_then(|discovery| {
                    crate::protocol::discovery::enrich_unknown_model_fallback(
                        observed,
                        &entry.model,
                        &discovery.transport,
                        self.protocol,
                    )
                })
            });
            let observed = enriched.as_ref().unwrap_or(observed);
            let mut model = declared
                .filter(|entry| entry.origin == AccountModelOrigin::Manual)
                .map(|entry| entry.model.clone())
                .unwrap_or_else(|| observed.clone());
            if !matches!(observed.pricing, crate::model::ModelPricing::Unknown) {
                model.pricing = observed.pricing.clone();
            }
            if matches!(model.pricing, crate::model::ModelPricing::Unknown) {
                model.pricing = local
                    .get(&model.model_id)
                    .map(|entry| entry.model.pricing.clone())
                    .unwrap_or_default();
            }
            let origin = if declared.is_some_and(|entry| entry.origin == AccountModelOrigin::Manual)
            {
                AccountModelOrigin::Manual
            } else {
                AccountModelOrigin::Online
            };
            entries.insert(
                model.model_id.clone(),
                AccountModelEntry::new(model, origin),
            );
        }
        Ok(entries.into_values().collect())
    }

    /// Publish a complete successful inventory; even an empty inventory replaces defaults.
    /// The host owns query identity/generation checks and durable publication ordering.
    /// # Errors
    /// Explicit/unsupported catalogs or any invalid declaration reject the whole observation.
    pub fn set_model_catalog_overlay(&mut self, models: Vec<ModelInfo>) -> Result<()> {
        let Some(discovery) = self.discovery_profile()? else {
            return Err(PureError::Protocol(
                "model catalog observation is unsupported".into(),
            ));
        };
        crate::model::validate_inventory(&models)
            .map_err(|_| PureError::Protocol("invalid model catalog observation".into()))?;
        if models.iter().any(|model| {
            !crate::protocol::discovery::valid_discovery_transport(
                &model.binding.transport,
                &discovery.transport,
            )
        }) {
            return Err(PureError::Protocol(
                "invalid model catalog observation profile".into(),
            ));
        }
        self.resolved_catalog = None;
        self.model_catalog_overlay = Some(models);
        Ok(())
    }

    pub fn has_model_catalog_overlay(&self) -> bool {
        self.model_catalog_overlay.is_some()
    }

    /// Pure capability check, independent of credential resolution or network availability.
    pub fn discovery_profile(&self) -> Result<Option<super::ModelCatalogDiscovery>> {
        match &self.catalog {
            AccountModelCatalogConfig::Bundled { catalog, .. } => {
                Ok(builtin_model_catalog(catalog)?.discovery)
            }
            AccountModelCatalogConfig::Explicit { .. } => Ok(None),
        }
    }

    /// Clear an old-identity observation when changing an endpoint; the host may then attach
    /// that identity's cache. This does not delete a cache or mutate desired configuration.
    pub fn clear_model_catalog_overlay(&mut self) {
        self.model_catalog_overlay = None;
        self.resolved_catalog = None;
    }

    pub(crate) fn model_observations(&self) -> &[ModelInfo] {
        self.model_catalog_overlay.as_deref().unwrap_or_default()
    }

    pub(crate) fn clear_resolved_catalog(&mut self) {
        self.resolved_catalog = None;
    }
    pub(crate) fn set_resolved_catalog(&mut self, entries: Vec<AccountModelEntry>) {
        self.resolved_catalog = Some(entries);
    }

    /// Structural validation for startup/reconciliation. Missing observed models or withdrawn
    /// connection candidates are not corruption; manual declarations and edits remain strict.
    pub fn validate_declarations(&self, account_id: &AccountId) -> Result<()> {
        self.validate_structure(account_id, false)
    }

    /// 返回按模型 model_id 保存的当前连接方式 override。
    pub fn connection_overrides(&self) -> &BTreeMap<String, ConnectionMode> {
        match &self.catalog {
            AccountModelCatalogConfig::Bundled {
                connection_overrides,
                ..
            }
            | AccountModelCatalogConfig::Explicit {
                connection_overrides,
                ..
            } => connection_overrides,
        }
    }

    /// 返回按模型 model_id 保存的上下文压缩阈值用户覆盖。
    ///
    /// 覆盖值独立于 [`ModelInfo::auto_compact_token_limit`] 默认元信息，缺省表示使用模型默认值。
    pub fn auto_compact_overrides(&self) -> &BTreeMap<String, u64> {
        match &self.catalog {
            AccountModelCatalogConfig::Bundled {
                auto_compact_overrides,
                ..
            }
            | AccountModelCatalogConfig::Explicit {
                auto_compact_overrides,
                ..
            } => auto_compact_overrides,
        }
    }

    /// 返回可由产品编辑的模型列表，不包含 PL 内置只读模型。
    pub fn editable_models(&self) -> &[ModelInfo] {
        match &self.catalog {
            AccountModelCatalogConfig::Bundled {
                additional_models, ..
            } => additional_models,
            AccountModelCatalogConfig::Explicit { models, .. } => models,
        }
    }

    /// 删除一个手动模型（`additional_models` / `Explicit.models`）。
    ///
    /// 同时删除该 model_id 的 connection override 与 auto-compact override。
    /// 非手动条目（在线或内置模型）与不存在的 model_id 返回类型化配置错误，不改变任何状态。
    ///
    /// # Errors
    ///
    /// 仅接受 `Bundled.additional_models` 或 `Explicit.models` 中的精确 model_id。成功时删除该
    /// 手动条目及其 `connection_overrides`、`auto_compact_overrides`，不修改 overlay 与
    /// 角色路由选择。非手动或不存在的 model_id 返回 `PureError::ConfigError`，且状态零修改。
    pub fn remove_manual_model(&mut self, model_id: &str) -> Result<()> {
        if !self
            .editable_models()
            .iter()
            .any(|model| model.model_id == model_id)
        {
            return Err(PureError::ConfigError(format!("unknown model: {model_id}")));
        }
        match &mut self.catalog {
            AccountModelCatalogConfig::Bundled {
                additional_models,
                connection_overrides,
                auto_compact_overrides,
                ..
            } => {
                additional_models.retain(|model| model.model_id != model_id);
                connection_overrides.remove(model_id);
                auto_compact_overrides.remove(model_id);
            }
            AccountModelCatalogConfig::Explicit {
                models,
                connection_overrides,
                auto_compact_overrides,
                ..
            } => {
                models.retain(|model| model.model_id != model_id);
                connection_overrides.remove(model_id);
                auto_compact_overrides.remove(model_id);
            }
        }
        Ok(())
    }

    /// 为 account 实例中的某个模型选择连接方式。
    pub fn set_model_connection_mode(&mut self, model: &str, mode: ConnectionMode) -> Result<()> {
        let catalog = self.catalog_membership()?;
        let selected = catalog
            .iter()
            .find(|candidate| candidate.model.model_id == model)
            .map(|candidate| &candidate.model)
            .ok_or_else(|| PureError::ConfigError(format!("unknown model: {model}")))?;
        if !selected
            .binding
            .transport
            .supported_connection_modes
            .contains(&mode)
        {
            return Err(PureError::ConfigError(format!(
                "model {model} does not support connection mode {mode:?}"
            )));
        }
        if selected.binding.transport.default_connection_mode == mode {
            self.connection_overrides_mut().remove(model);
        } else {
            self.connection_overrides_mut()
                .insert(model.to_string(), mode);
        }
        Ok(())
    }

    fn connection_overrides_mut(&mut self) -> &mut BTreeMap<String, ConnectionMode> {
        match &mut self.catalog {
            AccountModelCatalogConfig::Bundled {
                connection_overrides,
                ..
            }
            | AccountModelCatalogConfig::Explicit {
                connection_overrides,
                ..
            } => connection_overrides,
        }
    }

    /// 保存或清除某模型的上下文压缩阈值用户覆盖。
    ///
    /// `limit` 为 `None` 或等于该模型默认阈值时删除覆盖项（恢复默认）；覆盖值必须为正整数，
    /// 模型必须存在于当前声明目录中。
    pub fn set_model_auto_compact_override(
        &mut self,
        model: &str,
        limit: Option<u64>,
    ) -> Result<()> {
        let catalog = self.effective_catalog(None)?;
        let selected = catalog
            .iter()
            .find(|candidate| candidate.model.model_id == model)
            .map(|candidate| &candidate.model)
            .ok_or_else(|| PureError::ConfigError(format!("unknown model: {model}")))?;
        let restore_default = match limit {
            None => true,
            Some(0) => {
                return Err(PureError::ConfigError(format!(
                    "model {model} auto compact limit must be a positive integer"
                )));
            }
            Some(limit) => Some(limit) == selected.resolve_context(None).auto_compact_limit,
        };
        if restore_default {
            self.auto_compact_overrides_mut().remove(model);
        } else {
            self.auto_compact_overrides_mut().insert(
                model.to_string(),
                limit.expect("positive override is present"),
            );
        }
        let override_limit = self.auto_compact_overrides().get(model).copied();
        if let Some(catalog) = &mut self.resolved_catalog {
            for entry in catalog
                .iter_mut()
                .filter(|entry| entry.model.model_id == model)
            {
                entry.context = entry.model.resolve_context(override_limit);
            }
        }
        Ok(())
    }

    /// Replaces one account's override intent atomically and normalizes model defaults here.
    /// Unobserved discovery members retain only an already saved, unchanged override.
    pub fn replace_model_auto_compact_overrides(
        &mut self,
        overrides: BTreeMap<String, u64>,
    ) -> Result<()> {
        let catalog = self.effective_catalog(None)?;
        let previous = self.auto_compact_overrides().clone();
        let discovery = self.discovery_profile()?.is_some();
        let mut candidate = self.clone();
        candidate.auto_compact_overrides_mut().clear();
        for (model, limit) in overrides {
            if limit == 0 {
                return Err(PureError::ConfigError(
                    "model auto compact limit must be a positive integer".into(),
                ));
            }
            if catalog.iter().any(|entry| entry.model.model_id == model) {
                candidate.set_model_auto_compact_override(&model, Some(limit))?;
            } else if discovery && previous.get(&model) == Some(&limit) {
                candidate.auto_compact_overrides_mut().insert(model, limit);
            } else {
                return Err(PureError::ConfigError(format!("unknown model: {model}")));
            }
        }
        let limits = candidate.auto_compact_overrides().clone();
        if let Some(catalog) = &mut candidate.resolved_catalog {
            for entry in catalog {
                entry.context = entry
                    .model
                    .resolve_context(limits.get(&entry.model.model_id).copied());
            }
        }
        *self = candidate;
        Ok(())
    }

    fn auto_compact_overrides_mut(&mut self) -> &mut BTreeMap<String, u64> {
        match &mut self.catalog {
            AccountModelCatalogConfig::Bundled {
                auto_compact_overrides,
                ..
            }
            | AccountModelCatalogConfig::Explicit {
                auto_compact_overrides,
                ..
            } => auto_compact_overrides,
        }
    }

    /// 解析不包含模型与 transport 事实的 runtime endpoint。
    pub fn to_endpoint(&self) -> Result<ProtocolEndpoint> {
        Ok(ProtocolEndpoint {
            protocol: self.protocol,
            name: self.name.clone(),
            base_url: self.base_url.clone(),
            bearer_token: self.resolved_bearer_token(),
            http_headers: self.http_headers.clone(),
            tool_wire_policy: self.tool_wire_policy,
            apply_patch_tool_type: self.apply_patch_tool_type,
            service_capabilities: self.service_capabilities()?,
        })
    }

    /// 解析运行时凭证；配置中的显式 secret 优先于环境变量。
    pub fn resolved_bearer_token(&self) -> Option<String> {
        self.bearer_token
            .clone()
            .filter(|token| !token.trim().is_empty())
            .or_else(|| {
                self.bearer_token_env
                    .as_deref()
                    .filter(|name| !name.trim().is_empty())
                    .and_then(|name| std::env::var(name).ok())
                    .filter(|token| !token.trim().is_empty())
            })
    }

    pub(super) fn validate(&self, account_id: &AccountId) -> Result<()> {
        self.validate_structure(account_id, true)
    }

    fn validate_structure(&self, account_id: &AccountId, strict_availability: bool) -> Result<()> {
        if self.name.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "account {account_id} has empty name"
            )));
        }
        if self.base_url.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "account {account_id} has empty base_url"
            )));
        }
        self.service_capabilities()?;
        if self
            .bearer_token_env
            .as_deref()
            .is_some_and(|name| name.trim().is_empty())
        {
            return Err(PureError::ConfigError(format!(
                "account {account_id} has empty bearer_token_env"
            )));
        }
        self.validate_template_binding(account_id)?;
        let models = apply_connection_overrides(
            self.catalog_membership()?,
            self.connection_overrides(),
            !strict_availability && self.discovery_profile()?.is_some(),
            self.editable_models(),
        )?
        .into_iter()
        .map(|entry| entry.model)
        .collect::<Vec<_>>();
        if models.is_empty() && (strict_availability || self.model_catalog_overlay.is_none()) {
            return Err(PureError::ConfigError(format!(
                "account {account_id} must define at least one model"
            )));
        }
        let mut model_ids = BTreeSet::new();
        for model in &models {
            model
                .validate()
                .map_err(|error| PureError::ConfigError(error.to_string()))?;
            model
                .validate_media_contract()
                .map_err(|error| PureError::ConfigError(error.to_string()))?;
            if model.model_id.trim().is_empty() {
                return Err(PureError::ConfigError(format!(
                    "account {account_id} contains a model with empty model_id"
                )));
            }
            if !model_ids.insert(model.model_id.as_str()) {
                return Err(PureError::ConfigError(format!(
                    "account {account_id} contains duplicate model: {}",
                    model.model_id
                )));
            }
        }
        for (model_id, limit) in self.auto_compact_overrides() {
            if *limit == 0 {
                return Err(PureError::ConfigError(format!(
                    "account {account_id} model {model_id} auto compact limit must be a positive integer"
                )));
            }
            if !model_ids.contains(model_id.as_str())
                && (strict_availability || self.discovery_profile()?.is_none())
            {
                return Err(PureError::ConfigError(format!(
                    "account {account_id} auto compact override references unknown model: {model_id}"
                )));
            }
        }
        Ok(())
    }

    fn validate_template_binding(&self, account_id: &AccountId) -> Result<()> {
        let Some(template_id) = self.template_id() else {
            return Ok(());
        };
        let template = super::builtin_account_catalog()?
            .templates
            .into_iter()
            .find(|template| &template.id == template_id)
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "account {account_id} references unknown template: {template_id}"
                ))
            })?;
        match &self.catalog {
            AccountModelCatalogConfig::Bundled { catalog, .. }
                if catalog == &template.model_catalog =>
            {
                Ok(())
            }
            AccountModelCatalogConfig::Bundled { catalog, .. } => {
                Err(PureError::ConfigError(format!(
                    "account {account_id} catalog {catalog} does not match template {template_id}"
                )))
            }
            AccountModelCatalogConfig::Explicit { .. } => {
                if matches!(
                    template.account.catalog,
                    AccountModelCatalogConfig::Explicit { .. }
                ) {
                    Ok(())
                } else {
                    Err(PureError::ConfigError(format!(
                        "account {account_id} cannot combine template {template_id} with an explicit catalog"
                    )))
                }
            }
        }
    }
}

fn apply_connection_overrides(
    mut entries: Vec<AccountModelEntry>,
    overrides: &BTreeMap<String, ConnectionMode>,
    allow_unavailable: bool,
    editable_models: &[ModelInfo],
) -> Result<Vec<AccountModelEntry>> {
    for entry in &entries {
        // A user override must never repair an invalid declared transport profile.
        entry
            .model
            .binding
            .transport
            .validate(&entry.model.model_id)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
    }
    for (model_id, mode) in overrides {
        if model_id.trim().is_empty() {
            return Err(PureError::ConfigError(
                "connection override has empty model".into(),
            ));
        }
        let Some(entry) = entries
            .iter_mut()
            .find(|entry| entry.model.model_id == *model_id)
        else {
            if allow_unavailable {
                continue;
            }
            return Err(PureError::ConfigError(format!(
                "connection override references unknown model: {model_id}"
            )));
        };
        if !entry
            .model
            .binding
            .transport
            .supported_connection_modes
            .contains(mode)
        {
            if allow_unavailable
                && !editable_models
                    .iter()
                    .any(|manual| manual.model_id == *model_id)
            {
                // Preserve desired state, but keep the current display profile valid.
                // Route availability/strict resolution must reject this saved selection.
                continue;
            }
            return Err(PureError::ConfigError(format!(
                "model {model_id} does not support connection mode {mode:?}"
            )));
        }
        entry.model.binding.transport.default_connection_mode = *mode;
    }
    Ok(entries)
}
