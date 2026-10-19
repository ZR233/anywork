use std::collections::{BTreeMap, BTreeSet, HashMap};

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Serialize};

use super::{ModelCatalogId, ProviderId, ProviderPresetId, builtin_model_catalog};
use crate::model::ModelInfo;
use crate::provider::{
    ApplyPatchToolType, ProviderConnectionMode, ProviderEndpoint, ProviderServiceCapabilities,
    StandaloneWebSearchDialect, ToolWirePolicy,
};

/// Provider 模型目录来源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum ProviderModelCatalogConfig {
    /// 引用 PL 内置只读目录；显式模型可补充成员或覆盖同 ID 的本地定义。
    Bundled {
        catalog: ModelCatalogId,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        additional_models: Vec<ModelInfo>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        connection_overrides: BTreeMap<String, ProviderConnectionMode>,
        /// 按模型 model_id 索引的上下文压缩阈值用户覆盖；缺省表示使用模型默认值。
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        auto_compact_overrides: BTreeMap<String, u64>,
    },
    /// 完全由产品配置提供的模型目录。
    Explicit {
        models: Vec<ModelInfo>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        connection_overrides: BTreeMap<String, ProviderConnectionMode>,
        /// 按模型 model_id 索引的上下文压缩阈值用户覆盖；缺省表示使用模型默认值。
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        auto_compact_overrides: BTreeMap<String, u64>,
    },
}

/// Provider 服务能力的配置来源。
///
/// preset 实例通常继承 registry 默认能力；显式配置可覆盖任意兼容 endpoint。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum ProviderCapabilitySelection {
    #[default]
    PresetDefaults,
    Explicit(ProviderServiceCapabilities),
}

/// 有效目录成员的来源。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderModelOrigin {
    Bundled,
    Online,
    Manual,
}

/// 唯一有效目录中的一条成员，携带来源供投影与 GUI 区分。
#[derive(Debug, Clone, PartialEq)]
pub struct ProviderModelEntry {
    pub model: ModelInfo,
    pub origin: ProviderModelOrigin,
}

/// 可由产品配置文件组合使用的 Provider 值对象。
///
/// 具体默认模型不属于 Provider；调用方必须通过角色路由选择模型。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderConfig {
    #[serde(default)]
    pub adapter: crate::provider::ProviderAdapterKind,
    #[serde(default)]
    pub pricing_mode: pl_protocol::PricingMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preset: Option<ProviderPresetId>,
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
    pub capabilities: ProviderCapabilitySelection,
    pub catalog: ProviderModelCatalogConfig,
    /// Successful endpoint observation, never persisted as desired user configuration.
    #[serde(skip)]
    model_catalog_overlay: Option<Vec<ModelInfo>>,
    #[serde(skip)]
    resolved_catalog: Option<Vec<ProviderModelEntry>>,
}

impl ProviderConfig {
    /// 构造内置 DeepSeek provider preset，不附带任何产品角色默认值。
    pub fn deepseek_preset() -> Self {
        Self::from_bundled_catalog(
            ProviderEndpoint::deepseek(None),
            ModelCatalogId::new("deepseek").expect("static model catalog id is valid"),
            Vec::new(),
        )
        .with_preset(ProviderPresetId::new("deepseek").expect("static provider preset id is valid"))
    }

    /// 从 PL 内置模型目录创建 provider 配置。
    pub fn from_bundled_catalog(
        info: ProviderEndpoint,
        catalog: ModelCatalogId,
        additional_models: Vec<ModelInfo>,
    ) -> Self {
        Self::from_parts(
            info,
            ProviderModelCatalogConfig::Bundled {
                catalog,
                additional_models,
                connection_overrides: BTreeMap::new(),
                auto_compact_overrides: BTreeMap::new(),
            },
        )
    }

    /// 从完全显式的模型目录创建 provider 配置。
    pub fn from_explicit_models(info: ProviderEndpoint, models: Vec<ModelInfo>) -> Self {
        Self::from_parts(
            info,
            ProviderModelCatalogConfig::Explicit {
                models,
                connection_overrides: BTreeMap::new(),
                auto_compact_overrides: BTreeMap::new(),
            },
        )
    }

    fn from_parts(info: ProviderEndpoint, catalog: ProviderModelCatalogConfig) -> Self {
        let service_capabilities = info.service_capabilities.clone();
        Self {
            adapter: info.adapter,
            preset: None,
            pricing_mode: pl_protocol::PricingMode::Catalog,
            name: info.name,
            base_url: info.base_url,
            bearer_token: info.bearer_token,
            bearer_token_env: None,
            http_headers: info.http_headers,
            tool_wire_policy: info.tool_wire_policy,
            apply_patch_tool_type: info.apply_patch_tool_type,
            capabilities: ProviderCapabilitySelection::Explicit(service_capabilities),
            catalog,
            model_catalog_overlay: None,
            resolved_catalog: None,
        }
    }

    /// 记录创建该实例所使用的内置 preset。
    pub fn with_preset(mut self, preset: ProviderPresetId) -> Self {
        self.pricing_mode = match preset.as_str() {
            "zhipu-coding-plan" | "mimo-token-plan" | "openai-compatible" => {
                pl_protocol::PricingMode::Disabled
            }
            _ => pl_protocol::PricingMode::Catalog,
        };
        self.preset = Some(preset);
        self.capabilities = ProviderCapabilitySelection::PresetDefaults;
        self
    }

    /// 解析 preset 默认值或实例显式覆盖后的服务能力。
    pub fn service_capabilities(&self) -> Result<ProviderServiceCapabilities> {
        match &self.capabilities {
            ProviderCapabilitySelection::Explicit(capabilities) => Ok(capabilities.clone()),
            ProviderCapabilitySelection::PresetDefaults => match self.preset_id() {
                Some(preset_id) => super::builtin_provider_catalog()?
                    .presets
                    .into_iter()
                    .find(|preset| &preset.id == preset_id)
                    .map(|preset| {
                        let mut capabilities = preset.service_capabilities;
                        if self.base_url.trim_end_matches('/')
                            != preset.provider.base_url.trim_end_matches('/')
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
                        PureError::ConfigError(format!("unknown provider preset: {preset_id}"))
                    }),
                None => Ok(ProviderServiceCapabilities::default()),
            },
        }
    }

    /// 返回实例绑定的内置 preset；自定义 provider 返回 `None`。
    pub fn preset_id(&self) -> Option<&ProviderPresetId> {
        self.preset.as_ref()
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
    ) -> Result<Vec<ProviderModelEntry>> {
        let catalog = if let Some(catalog) = &self.resolved_catalog {
            catalog.clone()
        } else {
            apply_connection_overrides(
                self.catalog_membership()?,
                self.connection_overrides(),
                self.discovery_profile()?.is_some(),
                self.editable_models(),
            )?
        };
        Ok(catalog
            .into_iter()
            .filter(|entry| model_type.is_none_or(|kind| entry.model.matches_type(kind)))
            .collect())
    }

    fn catalog_membership(&self) -> Result<Vec<ProviderModelEntry>> {
        let (defaults, additional) = match &self.catalog {
            ProviderModelCatalogConfig::Bundled {
                catalog,
                additional_models,
                ..
            } => (
                builtin_model_catalog(catalog)?.models,
                additional_models.as_slice(),
            ),
            ProviderModelCatalogConfig::Explicit { models, .. } => (Vec::new(), models.as_slice()),
        };
        let mut local = defaults
            .iter()
            .cloned()
            .map(|model| {
                (
                    model.model_id.clone(),
                    ProviderModelEntry {
                        model,
                        origin: ProviderModelOrigin::Bundled,
                    },
                )
            })
            .collect::<BTreeMap<_, _>>();
        for model in additional {
            local.insert(
                model.model_id.clone(),
                ProviderModelEntry {
                    model: model.clone(),
                    origin: ProviderModelOrigin::Manual,
                },
            );
        }
        let Some(overlay) = &self.model_catalog_overlay else {
            return Ok(local.into_values().collect());
        };
        let mut entries = local
            .iter()
            .filter(|(_, entry)| entry.origin == ProviderModelOrigin::Manual)
            .map(|(key, entry)| (key.clone(), entry.clone()))
            .collect::<BTreeMap<_, _>>();
        let discovery = self.discovery_profile()?;
        for observed in overlay {
            let declared = local.get(&observed.model_id);
            let enriched = declared.and_then(|entry| {
                discovery.as_ref().and_then(|discovery| {
                    crate::provider::discovery::enrich_unknown_model_fallback(
                        observed,
                        &entry.model,
                        &discovery.transport,
                        self.adapter,
                    )
                })
            });
            let observed = enriched.as_ref().unwrap_or(observed);
            let mut model = declared
                .filter(|entry| entry.origin == ProviderModelOrigin::Manual)
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
            let origin =
                if declared.is_some_and(|entry| entry.origin == ProviderModelOrigin::Manual) {
                    ProviderModelOrigin::Manual
                } else {
                    ProviderModelOrigin::Online
                };
            entries.insert(model.model_id.clone(), ProviderModelEntry { model, origin });
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
            !crate::provider::discovery::valid_discovery_transport(
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
            ProviderModelCatalogConfig::Bundled { catalog, .. } => {
                Ok(builtin_model_catalog(catalog)?.discovery)
            }
            ProviderModelCatalogConfig::Explicit { .. } => Ok(None),
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
    pub(crate) fn set_resolved_catalog(&mut self, entries: Vec<ProviderModelEntry>) {
        self.resolved_catalog = Some(entries);
    }

    /// Structural validation for startup/reconciliation. Missing observed models or withdrawn
    /// connection candidates are not corruption; manual declarations and edits remain strict.
    pub fn validate_declarations(&self, provider_id: &ProviderId) -> Result<()> {
        self.validate_structure(provider_id, false)
    }

    /// 返回按模型 model_id 保存的当前连接方式 override。
    pub fn connection_overrides(&self) -> &BTreeMap<String, ProviderConnectionMode> {
        match &self.catalog {
            ProviderModelCatalogConfig::Bundled {
                connection_overrides,
                ..
            }
            | ProviderModelCatalogConfig::Explicit {
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
            ProviderModelCatalogConfig::Bundled {
                auto_compact_overrides,
                ..
            }
            | ProviderModelCatalogConfig::Explicit {
                auto_compact_overrides,
                ..
            } => auto_compact_overrides,
        }
    }

    /// 解析某模型（含 provider 实例覆盖）的实际生效压缩阈值。
    ///
    /// 生效值取「用户覆盖或模型默认」与上下文 90% 安全上限的较小值；上下文未知返回 `None`。
    pub fn resolved_auto_compact_limit(&self, model: &ModelInfo) -> Option<u64> {
        let override_limit = self.auto_compact_overrides().get(&model.model_id).copied();
        model.resolved_auto_compact_limit_with(override_limit)
    }

    /// 返回可由产品编辑的模型列表，不包含 PL 内置只读模型。
    pub fn editable_models(&self) -> &[ModelInfo] {
        match &self.catalog {
            ProviderModelCatalogConfig::Bundled {
                additional_models, ..
            } => additional_models,
            ProviderModelCatalogConfig::Explicit { models, .. } => models,
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
            ProviderModelCatalogConfig::Bundled {
                additional_models,
                connection_overrides,
                auto_compact_overrides,
                ..
            } => {
                additional_models.retain(|model| model.model_id != model_id);
                connection_overrides.remove(model_id);
                auto_compact_overrides.remove(model_id);
            }
            ProviderModelCatalogConfig::Explicit {
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

    /// 为 provider 实例中的某个模型选择连接方式。
    pub fn set_model_connection_mode(
        &mut self,
        model: &str,
        mode: ProviderConnectionMode,
    ) -> Result<()> {
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

    fn connection_overrides_mut(&mut self) -> &mut BTreeMap<String, ProviderConnectionMode> {
        match &mut self.catalog {
            ProviderModelCatalogConfig::Bundled {
                connection_overrides,
                ..
            }
            | ProviderModelCatalogConfig::Explicit {
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
            Some(limit) => Some(limit) == selected.default_auto_compact_token_limit(),
        };
        if restore_default {
            self.auto_compact_overrides_mut().remove(model);
        } else {
            self.auto_compact_overrides_mut().insert(
                model.to_string(),
                limit.expect("positive override is present"),
            );
        }
        Ok(())
    }

    fn auto_compact_overrides_mut(&mut self) -> &mut BTreeMap<String, u64> {
        match &mut self.catalog {
            ProviderModelCatalogConfig::Bundled {
                auto_compact_overrides,
                ..
            }
            | ProviderModelCatalogConfig::Explicit {
                auto_compact_overrides,
                ..
            } => auto_compact_overrides,
        }
    }

    /// 解析不包含模型与 transport 事实的 runtime endpoint。
    pub fn to_endpoint(&self) -> Result<ProviderEndpoint> {
        Ok(ProviderEndpoint {
            adapter: self.adapter,
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

    pub(super) fn validate(&self, provider_id: &ProviderId) -> Result<()> {
        self.validate_structure(provider_id, true)
    }

    fn validate_structure(
        &self,
        provider_id: &ProviderId,
        strict_availability: bool,
    ) -> Result<()> {
        if self.name.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "provider {provider_id} has empty name"
            )));
        }
        if self.base_url.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "provider {provider_id} has empty base_url"
            )));
        }
        self.service_capabilities()?;
        if self
            .bearer_token_env
            .as_deref()
            .is_some_and(|name| name.trim().is_empty())
        {
            return Err(PureError::ConfigError(format!(
                "provider {provider_id} has empty bearer_token_env"
            )));
        }
        self.validate_preset_binding(provider_id)?;
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
                "provider {provider_id} must define at least one model"
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
                    "provider {provider_id} contains a model with empty model_id"
                )));
            }
            if !model_ids.insert(model.model_id.as_str()) {
                return Err(PureError::ConfigError(format!(
                    "provider {provider_id} contains duplicate model: {}",
                    model.model_id
                )));
            }
        }
        for (model_id, limit) in self.auto_compact_overrides() {
            if *limit == 0 {
                return Err(PureError::ConfigError(format!(
                    "provider {provider_id} model {model_id} auto compact limit must be a positive integer"
                )));
            }
            if !model_ids.contains(model_id.as_str())
                && (strict_availability || self.discovery_profile()?.is_none())
            {
                return Err(PureError::ConfigError(format!(
                    "provider {provider_id} auto compact override references unknown model: {model_id}"
                )));
            }
        }
        Ok(())
    }

    fn validate_preset_binding(&self, provider_id: &ProviderId) -> Result<()> {
        let Some(preset_id) = self.preset_id() else {
            return Ok(());
        };
        let preset = super::builtin_provider_catalog()?
            .presets
            .into_iter()
            .find(|preset| &preset.id == preset_id)
            .ok_or_else(|| {
                PureError::ConfigError(format!(
                    "provider {provider_id} references unknown preset: {preset_id}"
                ))
            })?;
        match &self.catalog {
            ProviderModelCatalogConfig::Bundled { catalog, .. }
                if catalog == &preset.model_catalog =>
            {
                Ok(())
            }
            ProviderModelCatalogConfig::Bundled { catalog, .. } => {
                Err(PureError::ConfigError(format!(
                    "provider {provider_id} catalog {catalog} does not match preset {preset_id}"
                )))
            }
            ProviderModelCatalogConfig::Explicit { .. } => {
                if matches!(
                    preset.provider.catalog,
                    ProviderModelCatalogConfig::Explicit { .. }
                ) {
                    Ok(())
                } else {
                    Err(PureError::ConfigError(format!(
                        "provider {provider_id} cannot combine preset {preset_id} with an explicit catalog"
                    )))
                }
            }
        }
    }
}

fn apply_connection_overrides(
    mut entries: Vec<ProviderModelEntry>,
    overrides: &BTreeMap<String, ProviderConnectionMode>,
    allow_unavailable: bool,
    editable_models: &[ModelInfo],
) -> Result<Vec<ProviderModelEntry>> {
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
