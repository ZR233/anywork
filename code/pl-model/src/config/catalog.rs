use std::collections::{BTreeMap, BTreeSet};

use pl_protocol::{
    ACCOUNT_CATALOG_SCHEMA_VERSION, AccountCatalogSnapshot, AccountServiceCapabilitiesDescriptor,
    AccountTemplateDescriptor, ConnectionModeDescriptor, CredentialDescriptorDto,
    ModelCapabilitiesDto, ModelCatalogDescriptor, ModelInputCapabilityDto, ModelInputSourceDto,
    ModelModalityDto, ModelReasoningDescriptor, ModelTransportDescriptor, PureError, Result,
    WebSearchServiceCapabilitiesDescriptor,
};

use super::{AccountConfig, AccountTemplateId, ModelCatalogId, ModelDescriptor};
use super::{AccountModelEntry, AccountModelOrigin};
use crate::model::{
    ModelInfo, ModelModality, bundled_model_definition, default_models, mimo_default_model_ids,
    zhipu_default_model_ids, zhipu_responses_default_model_ids, zhipu_responses_models,
};
use crate::protocol::{
    ConnectionMode, ProtocolEndpoint, ProtocolServiceCapabilities, WireApi,
    wire_transport_profile_revision,
};

const MIMO_API_BASE_URL: &str = "https://api.xiaomimimo.com/v1";
const MIMO_TOKEN_PLAN_BASE_URL: &str = "https://token-plan-cn.xiaomimimo.com/v1";

/// 目录声明的在线探测能力；未声明时该 catalog 保持静态或显式语义。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelCatalogDiscovery {
    pub transport: crate::model::ModelTransportProfile,
}

/// 一组由 PL 维护且对产品只读的模型定义。
#[derive(Debug, Clone, PartialEq)]
pub struct ModelCatalog {
    pub id: ModelCatalogId,
    pub models: Vec<ModelInfo>,
    pub discovery: Option<ModelCatalogDiscovery>,
}

/// 可由宿主直接实例化的内置 Account 预设。
#[derive(Debug, Clone, PartialEq)]
pub struct AccountTemplate {
    pub id: AccountTemplateId,
    pub display_name: String,
    pub description: Option<String>,
    pub account: AccountConfig,
    pub credential_label: String,
    pub credential_env: Option<String>,
    pub model_catalog: ModelCatalogId,
    pub suggested_model_id: String,
    pub icon_key: Option<String>,
    pub service_capabilities: ProtocolServiceCapabilities,
}

/// PL 内置 Account 与模型目录注册表。
#[derive(Debug, Clone, PartialEq)]
pub struct AccountCatalogRegistry {
    pub templates: Vec<AccountTemplate>,
    pub model_catalogs: BTreeMap<ModelCatalogId, ModelCatalog>,
}

impl AccountCatalogRegistry {
    /// 构造当前二进制内置的完整目录。
    pub fn builtin() -> Result<Self> {
        let openai = bundled_model_definition("openai")?;
        let deepseek = bundled_model_definition("deepseek")?;
        let xai = bundled_model_definition("xai")?;
        let model_catalogs = [
            ModelCatalog {
                id: ModelCatalogId::new("openai")?,
                models: openai.models,
                discovery: Some(ModelCatalogDiscovery {
                    transport: crate::model::ModelTransportProfile::responses_websocket(),
                }),
            },
            ModelCatalog {
                id: ModelCatalogId::new("deepseek")?,
                models: deepseek.models,
                discovery: Some(ModelCatalogDiscovery {
                    transport: crate::model::ModelTransportProfile::responses_http(),
                }),
            },
            ModelCatalog {
                id: ModelCatalogId::new("xai")?,
                models: xai.models,
                discovery: Some(ModelCatalogDiscovery {
                    transport: crate::model::ModelTransportProfile::responses_http(),
                }),
            },
            model_catalog("zhipu", zhipu_default_model_ids())?,
            zhipu_responses_catalog(),
            mimo_catalog()?,
            model_catalog("openai-compatible", &[])?,
        ]
        .into_iter()
        .map(|catalog| (catalog.id.clone(), catalog))
        .collect();

        let mut templates = vec![
            template(
                "openai",
                ProtocolEndpoint::openai(None),
                &openai.suggested_model,
                "openai",
                "OPENAI_API_KEY",
                "OpenAI models served through the Responses API.",
                "openai",
            ),
            template(
                "deepseek",
                ProtocolEndpoint::deepseek(None),
                &deepseek.suggested_model,
                "deepseek",
                "DEEPSEEK_API_KEY",
                "DeepSeek reasoning and coding models.",
                "deepseek",
            ),
            template(
                "xai",
                ProtocolEndpoint::xai(None),
                &xai.suggested_model,
                "xai",
                "XAI_API_KEY",
                "xAI Grok models served through the Responses API.",
                "xai",
            ),
            template(
                "zhipu",
                ProtocolEndpoint::zhipu(None),
                "glm-5.3",
                "zhipu",
                "ZAI_API_KEY",
                "Zhipu BigModel API.",
                "zhipu",
            ),
            template(
                "zhipu-coding-plan",
                ProtocolEndpoint::zhipu_coding_plan(None),
                "glm-5.3",
                "zhipu-responses",
                "ZAI_API_KEY",
                "Zhipu Coding Plan Responses API.",
                "zhipu",
            ),
            template(
                "mimo-api",
                ProtocolEndpoint::compatible("MiMo API", MIMO_API_BASE_URL)
                    .with_protocol(crate::protocol::ProtocolKind::MiMo),
                "mimo-v2.5-pro",
                "mimo",
                "MIMO_API_KEY",
                "Xiaomi MiMo public API.",
                "mimo",
            ),
            template(
                "mimo-token-plan",
                ProtocolEndpoint::compatible("MiMo Token Plan", MIMO_TOKEN_PLAN_BASE_URL)
                    .with_protocol(crate::protocol::ProtocolKind::MiMo),
                "mimo-v2.5-pro",
                "mimo",
                "MIMO_TOKEN_PLAN_API_KEY",
                "Xiaomi MiMo Token Plan endpoint.",
                "mimo",
            ),
        ];

        let mut compatible = template(
            "openai-compatible",
            ProtocolEndpoint::compatible("OpenAI API 兼容", "http://localhost:11434/v1"),
            "",
            "openai-compatible",
            "",
            "Connect a custom Chat Completions or Responses model.",
            "openai",
        );
        compatible.credential_label = "API Key (optional)".to_owned();
        compatible.credential_env = None;
        // openai-compatible 是自定义供应商入口，不属于任何品牌：
        // 不携带 icon_key，UI 对这类供应商回退到名称首字母。
        compatible.icon_key = None;
        compatible.account.bearer_token_env = None;
        compatible.account.catalog = super::AccountModelCatalogConfig::Explicit {
            models: Vec::new(),
            connection_overrides: BTreeMap::new(),
            auto_compact_overrides: BTreeMap::new(),
        };
        templates.push(compatible);

        Ok(Self {
            templates,
            model_catalogs,
        })
    }

    /// 校验 template、catalog、transport 与 suggested model 的引用完整性。
    pub fn validate(&self) -> Result<()> {
        let mut template_ids = BTreeSet::new();
        for template in &self.templates {
            if !template_ids.insert(template.id.as_str()) {
                return Err(PureError::ConfigError(format!(
                    "duplicate account template: {}",
                    template.id
                )));
            }
            let catalog = self
                .model_catalogs
                .get(&template.model_catalog)
                .ok_or_else(|| {
                    PureError::ConfigError(format!(
                        "account template {} references missing catalog: {}",
                        template.id, template.model_catalog
                    ))
                })?;
            for model in &catalog.models {
                model
                    .binding
                    .transport
                    .validate(&model.model_id)
                    .map_err(|error| PureError::ConfigError(error.to_string()))?;
            }
            if !template.suggested_model_id.is_empty()
                && !catalog
                    .models
                    .iter()
                    .any(|model| model.model_id == template.suggested_model_id)
            {
                return Err(PureError::ConfigError(format!(
                    "account template {} references missing suggested model: {}",
                    template.id, template.suggested_model_id
                )));
            }
        }
        // 选模资料属于同一份内置目录：它必须命中真实成员并满足长度/来源上限，
        // 否则是打包缺陷而不是用户配置问题。
        let mut guides = BTreeSet::new();
        for bundled in crate::model::bundled_selection_guides() {
            bundled
                .guide
                .validate()
                .map_err(|error| PureError::ConfigError(error.to_string()))?;
            for catalog_id in bundled.catalogs {
                let catalog = self
                    .model_catalogs
                    .keys()
                    .find(|id| id.as_str() == *catalog_id)
                    .ok_or_else(|| {
                        PureError::ConfigError(format!(
                            "selection guide references unknown model catalog: {catalog_id}"
                        ))
                    })?;
                if !self.model_catalogs.get(catalog).is_some_and(|catalog| {
                    catalog
                        .models
                        .iter()
                        .any(|model| model.model_id == bundled.model_id)
                }) {
                    return Err(PureError::ConfigError(format!(
                        "selection guide references unknown model: {catalog_id}/{}",
                        bundled.model_id
                    )));
                }
                if !guides.insert((*catalog_id, bundled.model_id)) {
                    return Err(PureError::ConfigError(format!(
                        "duplicate selection guide for {catalog_id}/{}",
                        bundled.model_id
                    )));
                }
            }
        }
        Ok(())
    }

    /// 查找一个内置模型目录。
    pub fn model_catalog(&self, id: &ModelCatalogId) -> Option<&ModelCatalog> {
        self.model_catalogs.get(id)
    }

    /// 生成供 Web 与 Flutter 共用的无 secret 快照。
    pub fn snapshot(&self) -> Result<AccountCatalogSnapshot> {
        self.validate()?;
        let templates = self
            .templates
            .iter()
            .map(|template| {
                let catalog = self.model_catalog(&template.model_catalog).ok_or_else(|| {
                    PureError::ConfigError(format!(
                        "account template {} references missing catalog: {}",
                        template.id, template.model_catalog
                    ))
                })?;
                account_template_descriptor(template, catalog)
            })
            .collect::<Result<Vec<_>>>()?;
        let model_catalogs = self
            .model_catalogs
            .iter()
            .map(|(id, catalog)| {
                (
                    id.to_string(),
                    ModelCatalogDescriptor {
                        id: id.to_string(),
                        models: catalog
                            .models
                            .iter()
                            .map(|model| {
                                model_descriptor(&AccountModelEntry::new(
                                    model.clone(),
                                    AccountModelOrigin::Bundled,
                                ))
                            })
                            .collect(),
                    },
                )
            })
            .collect();
        let mut snapshot = AccountCatalogSnapshot {
            schema_version: ACCOUNT_CATALOG_SCHEMA_VERSION,
            revision: String::new(),
            templates,
            model_catalogs,
        };
        let mut canonical = serde_json::to_vec(&snapshot)
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
        for catalog in self.model_catalogs.values() {
            for model in &catalog.models {
                for mode in &model.binding.transport.supported_connection_modes {
                    canonical.push(0);
                    canonical.extend_from_slice(
                        wire_transport_profile_revision(model.binding.transport.protocol, *mode)
                            .as_bytes(),
                    );
                }
            }
        }
        snapshot.revision = stable_revision(&canonical);
        Ok(snapshot)
    }
}

/// 返回当前 PL 内置 Account 目录。
pub fn builtin_account_catalog() -> Result<AccountCatalogRegistry> {
    AccountCatalogRegistry::builtin()
}

/// 返回一个内置模型目录的副本。
pub fn builtin_model_catalog(id: &ModelCatalogId) -> Result<ModelCatalog> {
    AccountCatalogRegistry::builtin()?
        .model_catalog(id)
        .cloned()
        .ok_or_else(|| PureError::ConfigError(format!("unknown model catalog: {id}")))
}

fn model_catalog(id: &str, model_ids: &[&str]) -> Result<ModelCatalog> {
    let models = default_models()?
        .into_iter()
        .filter(|model| model_ids.contains(&model.model_id.as_str()))
        .collect();
    Ok(ModelCatalog {
        id: ModelCatalogId::new(id).expect("static model catalog id is valid"),
        models,
        discovery: None,
    })
}

fn mimo_catalog() -> Result<ModelCatalog> {
    let mut catalog = model_catalog("mimo", mimo_default_model_ids())?;
    catalog.discovery = Some(ModelCatalogDiscovery {
        transport: crate::model::ModelTransportProfile::chat_completions_http(),
    });
    Ok(catalog)
}

/// Coding Plan 的 Responses 目录与通用 Chat 目录共用模型 model_id，因此独立构造而不是按 model_id 过滤。
fn zhipu_responses_catalog() -> ModelCatalog {
    let model_ids = zhipu_responses_default_model_ids();
    let models = zhipu_responses_models()
        .into_iter()
        .filter(|model| model_ids.contains(&model.model_id.as_str()))
        .collect();
    ModelCatalog {
        id: ModelCatalogId::new("zhipu-responses").expect("static model catalog id is valid"),
        models,
        discovery: None,
    }
}

fn template(
    id: &str,
    info: ProtocolEndpoint,
    suggested_model_id: &str,
    catalog: &str,
    credential_env: &str,
    description: &str,
    icon_key: &str,
) -> AccountTemplate {
    let service_capabilities = info.service_capabilities.clone();
    let display_name = info.name.clone();
    let model_catalog = ModelCatalogId::new(catalog).expect("static model catalog id is valid");
    let template_id = AccountTemplateId::new(id).expect("static account template id is valid");
    let mut account = AccountConfig::from_bundled_catalog(info, model_catalog.clone(), Vec::new())
        .with_template(template_id.clone());
    account.bearer_token_env = Some(credential_env.to_string());
    AccountTemplate {
        id: template_id.clone(),
        display_name,
        description: Some(description.to_string()),
        account,
        credential_label: "API Key".to_string(),
        credential_env: Some(credential_env.to_string()),
        model_catalog,
        suggested_model_id: suggested_model_id.to_string(),
        icon_key: Some(icon_key.to_string()),
        service_capabilities,
    }
}

fn account_template_descriptor(
    template: &AccountTemplate,
    catalog: &ModelCatalog,
) -> Result<AccountTemplateDescriptor> {
    Ok(AccountTemplateDescriptor {
        id: template.id.to_string(),
        display_name: template.display_name.clone(),
        description: template.description.clone(),
        base_url: template.account.base_url.clone(),
        credential: CredentialDescriptorDto {
            label: template.credential_label.clone(),
            env_var: template.credential_env.clone(),
        },
        model_catalog_id: template.model_catalog.to_string(),
        protocol: template.account.protocol.as_str().to_string(),
        default_billing_kind: template.account.billing_kind()?,
        supports_model_discovery: catalog.discovery.is_some(),
        supports_usage_query: None,
        suggested_model_id: template.suggested_model_id.clone(),
        icon_key: template.icon_key.clone(),
        service_capabilities: account_service_capabilities_descriptor(
            &template.service_capabilities,
        ),
    })
}

/// 将运行时服务能力投影为无凭证公共 DTO。
pub fn account_service_capabilities_descriptor(
    capabilities: &ProtocolServiceCapabilities,
) -> AccountServiceCapabilitiesDescriptor {
    AccountServiceCapabilitiesDescriptor {
        web_search: WebSearchServiceCapabilitiesDescriptor {
            hosted_responses: capabilities.web_search.hosted_responses,
            hosted_dialect: capabilities.web_search.hosted_dialect.as_str().to_string(),
            standalone: capabilities
                .web_search
                .standalone
                .map(|dialect| dialect.as_str().to_string()),
        },
        prompt_cache_dialect: capabilities.prompt_cache.dialect.as_str().to_string(),
        responses_programmatic_tool_calling: capabilities.responses_tools.programmatic_tool_calling,
    }
}

fn connection_mode_descriptor(mode: ConnectionMode) -> ConnectionModeDescriptor {
    ConnectionModeDescriptor {
        id: connection_mode_label(mode).to_string(),
        display_name: match mode {
            ConnectionMode::WebSocket => "WebSocket".to_string(),
            ConnectionMode::Http => "HTTP".to_string(),
        },
    }
}

fn connection_mode_label(mode: ConnectionMode) -> &'static str {
    match mode {
        ConnectionMode::WebSocket => "web_socket",
        ConnectionMode::Http => "http",
    }
}

/// Project a model into a secret-free display DTO shared by catalog and Settings snapshots.
///
/// This projection must not be used to resolve routes or write configuration: it omits
/// runtime binding details. Unknown budgets and pricing remain `None`.
pub fn model_descriptor(entry: &AccountModelEntry) -> ModelDescriptor {
    let model = &entry.model;
    let capabilities = &model.capabilities;
    let reasoning = model
        .effort_parameter()
        .map(|parameter| ModelReasoningDescriptor {
            parameter: parameter.name.clone(),
            label: parameter
                .label
                .clone()
                .unwrap_or_else(|| "Reasoning effort".to_string()),
            default: parameter.default_candidate(None),
            candidates: parameter.candidates.clone(),
        });
    let pricing = model.pricing.catalog_pricing();
    ModelDescriptor {
        model_id: model.model_id.clone(),
        type_support: vec![entry.type_support(crate::model::ModelType::Text)],
        origin: match entry.origin {
            AccountModelOrigin::Bundled => pl_protocol::ModelOriginDto::Bundled,
            AccountModelOrigin::Online => pl_protocol::ModelOriginDto::Online,
            AccountModelOrigin::Manual => pl_protocol::ModelOriginDto::Manual,
        },
        enabled: entry.enabled,
        display_name: model.display_name.clone(),
        description: model.description.clone(),
        context_window: model.context_window,
        max_context_window: model.max_context_window,
        context: entry.context.clone(),
        max_output_tokens: model.max_output_tokens,
        transport: ModelTransportDescriptor {
            protocol: protocol_label(model.binding.transport.protocol).to_string(),
            connection_modes: model
                .binding
                .transport
                .supported_connection_modes
                .iter()
                .copied()
                .map(connection_mode_descriptor)
                .collect(),
            default_connection_mode: connection_mode_label(
                model.binding.transport.default_connection_mode,
            )
            .to_string(),
        },
        capabilities: ModelCapabilitiesDto {
            input: capabilities.input.iter().map(Into::into).collect(),
            output: capabilities
                .output
                .iter()
                .copied()
                .map(modality_descriptor)
                .collect(),
            streaming: capabilities.streaming,
            temperature: capabilities.temperature,
            reasoning: capabilities.reasoning,
            web_search: capabilities.web_search,
            function_calling: capabilities.tools.function_calling,
            parallel_tool_calls: capabilities.tools.parallel_tool_calls,
            custom_tools: capabilities.tools.custom_tools,
            freeform_tools: capabilities.tools.freeform_tools,
            instruction_snapshot_overrides: capabilities.instruction_snapshot_overrides,
            native_context_family: capabilities.native_context_family.clone(),
        },
        reasoning,
        pricing,
    }
}

fn protocol_label(protocol: WireApi) -> &'static str {
    match protocol {
        WireApi::Responses => "responses",
        WireApi::ChatCompletions => "chat_completions",
    }
}

/// 把内置只读选模资料投影为跨产品 wire。
///
/// 投影只做字段搬运：长度上限、来源与测量条件在 [`crate::model::ModelSelectionGuide::validate`]
/// 中校验，调用方不得静默截断简介或伪造分数。
pub fn selection_guide_descriptor(
    guide: &crate::model::ModelSelectionGuide,
) -> pl_protocol::ModelSelectionGuideDto {
    pl_protocol::ModelSelectionGuideDto {
        summary: guide.summary.to_string(),
        task_suitability: guide.task_suitability.to_vec(),
        limitations: guide
            .limitations
            .iter()
            .map(|limitation| (*limitation).to_string())
            .collect(),
        sources: guide
            .sources
            .iter()
            .map(|source| pl_protocol::ModelSelectionSourceDto {
                kind: match source.kind {
                    crate::model::ModelSelectionSourceKind::Official => {
                        pl_protocol::ModelSelectionSourceKindDto::Official
                    }
                    crate::model::ModelSelectionSourceKind::Benchmark => {
                        pl_protocol::ModelSelectionSourceKindDto::Benchmark
                    }
                    crate::model::ModelSelectionSourceKind::Community => {
                        pl_protocol::ModelSelectionSourceKindDto::Community
                    }
                },
                url: source.url.to_string(),
                verified_at: source.verified_at,
                measurement: source.measurement.as_ref().map(|measurement| {
                    pl_protocol::ModelSelectionMeasurementDto {
                        model: measurement.model.to_string(),
                        effort: measurement.effort.map(ToString::to_string),
                        metric: measurement.metric.to_string(),
                        metric_version: measurement.metric_version.map(ToString::to_string),
                        score: measurement.score,
                    }
                }),
            })
            .collect(),
    }
}

fn modality_descriptor(modality: ModelModality) -> ModelModalityDto {
    match modality {
        ModelModality::Text => ModelModalityDto::Text,
        ModelModality::Image => ModelModalityDto::Image,
        ModelModality::Audio => ModelModalityDto::Audio,
        ModelModality::Video => ModelModalityDto::Video,
        ModelModality::File => ModelModalityDto::File,
    }
}

fn input_source_descriptor(source: crate::model::ModelInputSource) -> ModelInputSourceDto {
    match source {
        crate::model::ModelInputSource::Local => ModelInputSourceDto::Local,
        crate::model::ModelInputSource::RemoteUrl => ModelInputSourceDto::RemoteUrl,
    }
}

fn stable_revision(bytes: &[u8]) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

impl From<&crate::model::ModelInputCapability> for ModelInputCapabilityDto {
    fn from(capability: &crate::model::ModelInputCapability) -> Self {
        Self {
            modality: modality_descriptor(capability.modality),
            sources: capability
                .sources
                .iter()
                .copied()
                .map(input_source_descriptor)
                .collect(),
            max_count: capability.limits.max_count,
            max_bytes: capability.limits.max_bytes,
            max_total_bytes: capability.limits.max_total_bytes,
            max_width: capability.limits.max_width,
            max_height: capability.limits.max_height,
            media_types: capability.limits.media_types.clone(),
        }
    }
}
