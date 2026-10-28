use std::collections::{BTreeMap, BTreeSet, HashMap};

use pl_protocol::{PureError, Result};
use serde::{Deserialize, Serialize};

use super::{AccountId, AccountTemplateId, ModelCatalogId, builtin_model_catalog};
use crate::model::ModelInfo;
use crate::protocol::{
    ApplyPatchToolType, ConnectionMode, ImageGenerationCapabilities, ProtocolEndpoint,
    ProtocolServiceCapabilities, StandaloneWebSearchDialect, ToolWirePolicy,
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
    /// 用户启用意图的投影；禁用成员仍留在目录里，只是不能被选为执行模型。
    ///
    /// 它不改写 [`Self::type_support`]：类型资格与启用意图是两个独立事实。
    pub enabled: bool,
}

/// 一个 account 当前可用的图像生成服务。
///
/// `models` 只来自该 account 的有效目录成员（在线、手工或内置来源），不用模型名推断补齐。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageGenerationService {
    /// 声明的服务能力（方言、前缀与首选序）。
    pub capabilities: ImageGenerationCapabilities,
    /// 命中所声明前缀的模型 slug，按字典序去重；可为空。
    pub models: Vec<String>,
}

impl AccountModelEntry {
    pub fn new(model: ModelInfo, origin: AccountModelOrigin) -> Self {
        Self {
            context: model.resolve_context(None),
            model,
            origin,
            enabled: true,
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
    /// 显式设置的计费类别；`None` 表示未显式配置，由 [`Self::billing_kind`] 按明确模板与
    /// canonical endpoint 推导。
    ///
    /// 分开保存「用户显式意图」与「模板推导」：修改 endpoint 时只有推导值会变化，用户显式
    /// 选择的类别必须保留。`subscription` 不证明订阅有效、额度充足或实际零费用。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub billing_kind: Option<pl_protocol::BillingKind>,
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
    /// 精确 model_id 的显式启用覆盖；缺项按当前目录自动决定，撤下成员仍保留意图。
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    model_enabled_overrides: BTreeMap<String, bool>,
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
            billing_kind: None,
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
            model_enabled_overrides: BTreeMap::new(),
            resolved_catalog: None,
        }
    }

    /// 记录创建该实例所使用的内置 template。
    ///
    /// 模板本身不写入计费类别：推导只在读取时按 canonical endpoint 判定（见
    /// [`Self::billing_kind`]），因此用同一个模板配非 canonical 地址不会被记成订阅或按量
    /// 计价。
    pub fn with_template(mut self, template: AccountTemplateId) -> Self {
        self.template = Some(template);
        self.capabilities = AccountCapabilitySelection::TemplateDefaults;
        self
    }

    /// 解析 template 默认值或实例显式覆盖后的服务能力。
    ///
    /// 这是服务能力的唯一解析入口：声明不一致在此处失败，调用方不会拿到无效声明。
    pub fn service_capabilities(&self) -> Result<ProtocolServiceCapabilities> {
        let capabilities = self.resolve_service_capabilities()?;
        validate_image_generation_declaration(capabilities.image_generation.as_ref())?;
        Ok(capabilities)
    }

    fn resolve_service_capabilities(&self) -> Result<ProtocolServiceCapabilities> {
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

    /// 返回该 account 的图像生成服务及其可用模型；未声明能力时返回 `None`。
    ///
    /// 候选只来自当前选择资格目录（类型合格且启用）中命中声明前缀的模型，来源不限；
    /// 目录为空时返回空名单，由调用方按不可用处理，不能凭模型名或配置补造名单。
    ///
    /// # Errors
    /// 服务能力或目录声明不一致时返回配置定义错误。
    pub fn image_generation_service(&self) -> Result<Option<ImageGenerationService>> {
        let Some(capabilities) = self.service_capabilities()?.image_generation else {
            return Ok(None);
        };
        let models = self
            .selectable_catalog(None)?
            .into_iter()
            .map(|entry| entry.model.model_id)
            .filter(|slug| {
                capabilities
                    .model_prefixes
                    .iter()
                    .any(|prefix| slug.starts_with(prefix.as_str()))
            })
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        Ok(Some(ImageGenerationService {
            capabilities,
            models,
        }))
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

    /// 管理目录查询；保留全部绑定内置定义，合并当前在线与手工成员。
    ///
    /// 类型筛选消费已合并的定义，不用于发现阶段或改变供应商成员。启用意图在每次读取时
    /// 从 desired 配置投影，因此已解析目录缓存不会把禁用成员漏成可用。
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
            .map(|mut entry| {
                let automatic = entry.origin != AccountModelOrigin::Bundled
                    || self.model_catalog_overlay.is_none();
                entry.enabled = self
                    .model_enabled_overrides
                    .get(&entry.model.model_id)
                    .copied()
                    .unwrap_or(automatic);
                entry
            })
            .filter(|entry| {
                model_type.is_none_or(|kind| entry.type_support(kind).exclusions.is_empty())
            })
            .collect())
    }

    /// 会话、固定 Profile 与自动子代理共用的选择资格入口。
    ///
    /// 先应用模型自身的类型资格（文本输入输出、上下文与预算），再排除用户禁用的成员；
    /// 启用、价格或评价不能绕过类型资格。管理页仍用 [`Self::effective_catalog`] 读取完整
    /// 目录，自动分发的凭据、连接与任务能力追加过滤由调用方完成。
    pub fn selectable_catalog(
        &self,
        model_type: Option<crate::model::ModelType>,
    ) -> Result<Vec<AccountModelEntry>> {
        Ok(self
            .effective_catalog(model_type)?
            .into_iter()
            .filter(|entry| entry.enabled)
            .collect())
    }

    /// 切换一个目录成员的启用状态。
    ///
    /// 这是模型启用的唯一 mutation：只改该精确 `model_id` 的显式意图，保留成员来源、
    /// 连接覆盖、压缩阈值覆盖、凭据与其他模型；把在线成员切换为启用不会把它转成手工成员。
    /// 已禁用的成员被目录撤下后覆盖仍保留，重新出现时继续生效。
    ///
    /// # Errors
    /// `model_id` 不是当前有效目录成员时返回类型化配置错误，且状态零修改。
    pub fn set_model_enabled(&mut self, model_id: &str, enabled: bool) -> Result<()> {
        if !self
            .effective_catalog(None)?
            .iter()
            .any(|entry| entry.model.model_id == model_id)
        {
            return Err(PureError::ConfigError(format!("unknown model: {model_id}")));
        }
        self.model_enabled_overrides
            .insert(model_id.to_string(), enabled);
        Ok(())
    }

    /// 返回当前保存的显式启用覆盖；缺项表示自动。
    ///
    /// 调用方据此投影管理页开关与配置保存，不需要第二份自动分发白名单。
    pub fn model_enabled_overrides(&self) -> &BTreeMap<String, bool> {
        &self.model_enabled_overrides
    }

    /// 由明确模板与 canonical endpoint 推导的计费类别。
    ///
    /// 只有模板自身的 canonical endpoint 才预置类别；改过地址、未知模板或自定义账号返回
    /// [`pl_protocol::BillingKind::Unknown`]。推导只描述计量方式，不证明订阅有效或额度充足。
    /// 显式设置值不参与推导，见 [`Self::billing_kind`]。
    ///
    /// # Errors
    /// 引用未知模板时返回配置定义错误。
    pub fn inferred_billing_kind(&self) -> Result<pl_protocol::BillingKind> {
        let Some(template_id) = self.template_id() else {
            return Ok(pl_protocol::BillingKind::Unknown);
        };
        let template = super::builtin_account_catalog()?
            .templates
            .into_iter()
            .find(|template| &template.id == template_id)
            .ok_or_else(|| {
                PureError::ConfigError(format!("unknown account template: {template_id}"))
            })?;
        if self.base_url.trim_end_matches('/') != template.account.base_url.trim_end_matches('/') {
            return Ok(pl_protocol::BillingKind::Unknown);
        }
        Ok(template_billing_kind(template_id))
    }

    /// 生效的计费类别：显式设置优先，否则按明确模板与 canonical endpoint 推导。
    ///
    /// 这是唯一供投影与查询消费的取值入口。显式值与推导值不一致不是错误：它表示用户选择了
    /// 与模板默认不同的计量方式（例如自建代理），修改 endpoint 时不得静默覆盖显式值。
    ///
    /// # Errors
    /// 引用未知模板时返回配置定义错误。
    pub fn billing_kind(&self) -> Result<pl_protocol::BillingKind> {
        match self.billing_kind {
            Some(kind) => Ok(kind),
            None => self.inferred_billing_kind(),
        }
    }

    /// 按本账号绑定的精确内置目录查找只读选模资料。
    ///
    /// 资料只按「目录 + model_id」精确命中，并要求该 model_id 仍是当前有效目录成员：显式
    /// （自定义）目录没有内置资料，手工覆盖同 ID 的成员由用户定义语义而不附内置资料，
    /// 内置成员即使默认关闭仍可读取资料。资料不是能力声明，也不进入 runtime 载荷。
    ///
    /// # Errors
    /// 读取当前有效目录失败时返回配置错误，不把失败伪装成「没有资料」。
    pub fn model_selection_guide(
        &self,
        model_id: &str,
    ) -> Result<Option<&'static crate::model::ModelSelectionGuide>> {
        let catalog = match &self.catalog {
            AccountModelCatalogConfig::Bundled { catalog, .. } => catalog,
            AccountModelCatalogConfig::Explicit { .. } => return Ok(None),
        };
        let Some(entry) = self
            .effective_catalog(None)?
            .into_iter()
            .find(|entry| entry.model.model_id == model_id)
        else {
            return Ok(None);
        };
        if entry.origin == AccountModelOrigin::Manual {
            return Ok(None);
        }
        Ok(crate::model::bundled_selection_guide(
            catalog.as_str(),
            model_id,
        ))
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
        let mut entries = local.clone();
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
            let is_manual =
                declared.is_some_and(|entry| entry.origin == AccountModelOrigin::Manual);
            let mut model = declared
                .filter(|entry| entry.origin == AccountModelOrigin::Manual)
                .map(|entry| entry.model.clone())
                .unwrap_or_else(|| observed.clone());
            if !is_manual {
                model.display_name = crate::model::observation::resolve_display_name(
                    observed,
                    declared.map(|entry| &entry.model),
                );
            }
            if !matches!(observed.pricing, crate::model::ModelPricing::Unknown) {
                model.pricing = observed.pricing.clone();
            }
            if matches!(model.pricing, crate::model::ModelPricing::Unknown) {
                model.pricing = local
                    .get(&model.model_id)
                    .map(|entry| entry.model.pricing.clone())
                    .unwrap_or_default();
            }
            let origin = if is_manual {
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

    /// Publish a complete successful online inventory; absent bundled members default to disabled.
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
        // 手工成员被删除后，移除对应的显式启用覆盖。
        self.model_enabled_overrides.remove(model_id);
        self.resolved_catalog = None;
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
        for model_id in self.model_enabled_overrides.keys() {
            if model_id.trim().is_empty() {
                return Err(PureError::ConfigError(format!(
                    "account {account_id} contains an empty model enablement override"
                )));
            }
            // 在线目录撤下的成员保留启用覆盖属于合法 desired 状态，不视为配置损坏。
            if !model_ids.contains(model_id.as_str())
                && (strict_availability || self.discovery_profile()?.is_none())
            {
                return Err(PureError::ConfigError(format!(
                    "account {account_id} model enablement override references unknown model: {model_id}"
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

/// 模板默认计费类别。
///
/// 只有订阅制模板预置 `subscription`，品牌 API 模板是 `metered`，自定义兼容入口保持未知。
fn template_billing_kind(template: &AccountTemplateId) -> pl_protocol::BillingKind {
    match template.as_str() {
        "zhipu-coding-plan" | "mimo-token-plan" => pl_protocol::BillingKind::Subscription,
        "openai-compatible" => pl_protocol::BillingKind::Unknown,
        _ => pl_protocol::BillingKind::Metered,
    }
}

/// 校验图像生成能力声明。
///
/// 声明只描述 endpoint 的外部服务能力：前缀必须非空且不含空串，首选序的每个 slug 必须
/// 命中某个声明前缀。生图模型是否真实存在由当前目录候选决定，不在这里补齐或拒绝。
fn validate_image_generation_declaration(
    declaration: Option<&ImageGenerationCapabilities>,
) -> Result<()> {
    let Some(declaration) = declaration else {
        return Ok(());
    };
    if declaration.model_prefixes.is_empty() {
        return Err(PureError::ConfigError(
            "account image generation declaration requires at least one model prefix".into(),
        ));
    }
    for prefix in &declaration.model_prefixes {
        if prefix.trim().is_empty() {
            return Err(PureError::ConfigError(
                "account image generation declaration contains an empty model prefix".into(),
            ));
        }
    }
    for slug in &declaration.preferred_models {
        if !declaration
            .model_prefixes
            .iter()
            .any(|prefix| slug.starts_with(prefix.as_str()))
        {
            return Err(PureError::ConfigError(format!(
                "account image generation preferred model does not match a declared prefix: {slug}"
            )));
        }
    }
    Ok(())
}
