//! 厂商 typed 模型列表 envelope 到一份 presence-aware 规范声明的唯一转换。
//!
//! 每家适配只解释自己的 envelope、字段名与价格单位；转换后的 [`Record`] 不再携带
//! 方言分支。账号内合成、预算收敛、媒体契约、参数默认与 validation 只有这一份实现。
pub mod reasoning;

pub use crate::discovery_error::ModelCatalogQueryError;
pub use crate::discovery_policy::valid_discovery_transport;
use crate::model::*;
use reasoning::ReasoningDeclaration;
use serde::Deserialize;
use std::collections::HashMap;

/// Rules for normalizing the typed records returned by a provider's catalog parser.
#[derive(Debug, Clone, Copy)]
pub struct DiscoveryPolicy {
    pub responses_effort: bool,
    pub media_send_order: MediaSendOrder,
    pub unknown_input: &'static [ModelModality],
}

impl DiscoveryPolicy {
    /// Conservative defaults for a compatible endpoint with sparse model declarations.
    pub const COMPATIBLE: Self = Self {
        responses_effort: false,
        media_send_order: MediaSendOrder::RemoteUrlFirst,
        unknown_input: &[ModelModality::Text],
    };
}

/// 各厂商 parser 产出的 presence-aware 规范声明。
#[derive(Debug, Clone, Default)]
pub struct Record {
    pub id: String,
    pub display_name: Option<String>,
    pub description: Option<Option<String>>,
    pub context_window: Option<Option<u64>>,
    pub max_context_window: Option<Option<u64>>,
    pub auto_compact_token_limit: Option<Option<u64>>,
    pub max_output_tokens: Option<Option<u64>>,
    pub default_temperature: Option<Option<f32>>,
    pub input_modalities: Option<Vec<ModelModality>>,
    pub output_modalities: Option<Vec<ModelModality>>,
    pub supports_parallel_tool_calls: Option<bool>,
    pub supports_function_calling: Option<bool>,
    pub supports_temperature: Option<bool>,
    pub supports_streaming: Option<bool>,
    pub supports_reasoning: Option<bool>,
    pub reasoning: ReasoningDeclaration,
    pub service_tiers: crate::service_tiers::ServiceTierDeclaration,
    pub binding: Option<ModelBinding>,
    pub capabilities: Option<Capabilities>,
    /// 该厂商已在响应中声明的 token 价格；`None` 表示本次没有价格声明。
    pub pricing: Option<ModelPricing>,
    /// 未知模型缺省输入模态；由具体厂商 parser 决定，`None` 表示保持未知骨架。
    pub unknown_default_input: Option<Vec<ModelModality>>,
    /// 该厂商在有 effort 候选时要求启用的固定 base body（DeepSeek thinking）。
    pub thinking_base_body: bool,
}

/// Prefer the first readable provider name while retaining presence when every candidate is blank.
pub fn presentation_name(display_name: Option<String>, name: Option<String>) -> Option<String> {
    display_name
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .map(str::to_owned)
        .or_else(|| {
            name.as_deref()
                .filter(|value| !value.trim().is_empty())
                .map(str::to_owned)
        })
        .or(display_name)
        .or(name)
}

impl Record {
    fn declared_fields(&self) -> Vec<ModelMetadataField> {
        use ModelMetadataField::*;
        let mut fields = Vec::new();
        for (present, field) in [
            (self.display_name.is_some(), DisplayName),
            (self.description.is_some(), Description),
            (self.context_window.is_some(), ContextWindow),
            (self.max_context_window.is_some(), MaxContextWindow),
            (
                self.auto_compact_token_limit.is_some(),
                AutoCompactTokenLimit,
            ),
            (self.max_output_tokens.is_some(), MaxOutputTokens),
            (self.default_temperature.is_some(), DefaultTemperature),
            (self.input_modalities.is_some(), Input),
            (self.output_modalities.is_some(), Output),
            (self.supports_streaming.is_some(), Streaming),
            (self.supports_temperature.is_some(), Temperature),
            (self.supports_reasoning.is_some(), Reasoning),
            (self.supports_function_calling.is_some(), FunctionCalling),
            (
                self.supports_parallel_tool_calls.is_some(),
                ParallelToolCalls,
            ),
            (self.reasoning.declares_parameters(), Parameters),
            (self.service_tiers.declared(), ServiceTiers),
        ] {
            if present {
                fields.push(field);
            }
        }
        if let Some(c) = &self.capabilities {
            for (present, field) in [
                (c.input.is_some(), Input),
                (c.output.is_some(), Output),
                (c.streaming.is_some(), Streaming),
                (c.temperature.is_some(), Temperature),
                (c.reasoning.is_some(), Reasoning),
                (c.web_search.is_some(), WebSearch),
            ] {
                if present && !fields.contains(&field) {
                    fields.push(field);
                }
            }
            if let Some(t) = &c.tools {
                for (present, field) in [
                    (t.function_calling.is_some(), FunctionCalling),
                    (t.parallel_tool_calls.is_some(), ParallelToolCalls),
                    (t.custom_tools.is_some(), CustomTools),
                    (t.freeform_tools.is_some(), FreeformTools),
                    (
                        t.programmatic_tool_calling.is_some(),
                        ProgrammaticToolCalling,
                    ),
                ] {
                    if present && !fields.contains(&field) {
                        fields.push(field);
                    }
                }
            }
        }
        // Candidate declarations also define reasoning; an explicit false withdraws inherited effort.
        if self.reasoning.declares_candidates()
            && self.reasoning.supports_effort != Some(false)
            && !fields.contains(&Reasoning)
        {
            fields.push(Reasoning);
        }
        if (self.supports_reasoning == Some(false)
            || self.capabilities.as_ref().and_then(|c| c.reasoning) == Some(false))
            && !fields.contains(&Parameters)
        {
            fields.push(Parameters);
        }
        fields
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Capabilities {
    pub input: Option<Vec<ModelInputCapability>>,
    pub output: Option<Vec<ModelModality>>,
    pub streaming: Option<bool>,
    pub temperature: Option<bool>,
    pub reasoning: Option<bool>,
    pub web_search: Option<bool>,
    pub tools: Option<Tools>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Tools {
    pub function_calling: Option<bool>,
    pub parallel_tool_calls: Option<bool>,
    pub custom_tools: Option<bool>,
    pub freeform_tools: Option<bool>,
    pub programmatic_tool_calling: Option<bool>,
}

/// 用于把显式 `null` 与缺失区分开的 canonical nullable 字段。
pub fn nullable<'de, D, T>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}

pub fn required_id(id: Option<String>) -> Result<String, ModelCatalogQueryError> {
    let id = id.ok_or(ModelCatalogQueryError::Protocol)?;
    if id.trim().is_empty() {
        return Err(ModelCatalogQueryError::Protocol);
    }
    Ok(id)
}

/// 解析一份成功名单：先由该厂商 typed parser 提取声明，再复用账号内合成与校验。
pub fn models(
    records: Vec<Record>,
    discovery: &crate::config::ModelCatalogDiscovery,
    dialect: DiscoveryPolicy,
    previous: Option<&[ModelInfo]>,
    defaults: &[ModelInfo],
) -> Result<Vec<ModelInfo>, ModelCatalogQueryError> {
    let mut metadata = defaults
        .iter()
        .map(|model| (model.model_id.clone(), model.clone()))
        .collect::<HashMap<_, _>>();
    for model in previous.into_iter().flatten() {
        let enriched = metadata.get(&model.model_id).and_then(|current| {
            enrich_unknown_model_fallback(model, current, &discovery.transport, dialect)
        });
        metadata.insert(
            model.model_id.clone(),
            enriched.unwrap_or_else(|| model.clone()),
        );
    }
    let mut positions = HashMap::new();
    let mut result = Vec::new();
    for record in records {
        let id = record.id.clone();
        let model = normalize(record, discovery, dialect, &metadata)?;
        metadata.insert(model.model_id.clone(), model.clone());
        if let Some(&index) = positions.get(&id) {
            result[index] = model;
        } else {
            positions.insert(id, result.len());
            result.push(model);
        }
    }
    validate_inventory(&result).map_err(|_| ModelCatalogQueryError::Protocol)?;
    Ok(result)
}

fn normalize(
    mut record: Record,
    discovery: &crate::config::ModelCatalogDiscovery,
    dialect: DiscoveryPolicy,
    metadata: &HashMap<String, ModelInfo>,
) -> Result<ModelInfo, ModelCatalogQueryError> {
    let model_id = record.id.clone();
    let declarations = record.declared_fields();
    let budgets = [
        (ModelMetadataField::ContextWindow, record.context_window),
        (
            ModelMetadataField::MaxContextWindow,
            record.max_context_window,
        ),
    ];
    let clear_context = record.context_window == Some(None);
    let clear_max_context = record.max_context_window == Some(None);
    let clear_compact = record.auto_compact_token_limit == Some(None);
    let clear_output = record.max_output_tokens == Some(None);
    let clear_temperature = record.default_temperature == Some(None);
    let known = metadata.get(model_id.as_str());
    let mut model = known
        .cloned()
        .unwrap_or_else(|| minimal(&model_id, &discovery.transport, dialect));
    let declared_price = record.pricing.is_some();
    if let Some(pricing) = record.pricing {
        model.pricing = pricing;
    } else if model
        .observation
        .as_ref()
        .and_then(|o| o.price_order)
        .is_none()
    {
        model.pricing = ModelPricing::Unknown;
    }
    if let Some(value) = record.display_name {
        model.display_name = value;
    }
    if let Some(value) = record.description {
        model.description = value;
    }
    // 在线预算只覆盖它实际声明的字段；缺失的配对字段按观测事实单侧收敛，
    // 不凭空补成固定预算。同时声明两者时仍由 validate 要求自身一致。
    match (
        record.context_window.flatten(),
        record.max_context_window.flatten(),
    ) {
        (Some(current), Some(max)) => {
            model.context_window = Some(current);
            model.max_context_window = Some(max);
        }
        (Some(current), None) => {
            model.context_window = Some(current);
            if model.max_context_window.is_some_and(|max| max < current) {
                // 观测到的窗口是更新的服务端事实，抬升过时的继承上限。
                model.max_context_window = Some(current);
            }
        }
        (None, Some(max)) => {
            // 在线只声明更小的上限：继承的当前窗口收敛到该上限，
            // 不能因内置当前窗口更大而拒绝名单或继续使用旧容量。
            model.max_context_window = Some(max);
            if model.context_window.is_some_and(|current| current > max) {
                model.context_window = Some(max);
            }
        }
        (None, None) => {}
    }
    if let Some(value) = record.max_output_tokens.flatten() {
        model.max_output_tokens = Some(value);
    }
    if let Some(value) = record.auto_compact_token_limit.flatten() {
        model.auto_compact_token_limit = Some(value);
    }
    if let Some(value) = record.default_temperature.flatten() {
        model.default_temperature = Some(value);
    }
    let explicit_binding = record.binding.is_some();
    if let Some(value) = record.binding {
        // Discovery may declare transport/media, not override endpoint credentials or inject
        // product instructions.
        if value.request.api_model.is_some()
            || !value.request.headers.is_empty()
            || !value.request.body.is_empty()
            || !valid_discovery_transport(&value.transport, &discovery.transport)
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        model.binding = value;
        // Canonicalize ordering, never restore a connection candidate the API withdrew.
        model.binding.transport.supported_connection_modes = discovery
            .transport
            .supported_connection_modes
            .iter()
            .copied()
            .filter(|mode| {
                model
                    .binding
                    .transport
                    .supported_connection_modes
                    .contains(mode)
            })
            .collect();
    }
    let supplied_media_profile = record
        .capabilities
        .as_ref()
        .is_some_and(|c| c.input.is_some());
    let explicit_reasoning = record
        .supports_reasoning
        .or_else(|| record.capabilities.as_ref().and_then(|c| c.reasoning));
    if let Some(capabilities) = record.capabilities {
        if let Some(value) = capabilities.input {
            model.capabilities.input = value;
        }
        if let Some(value) = capabilities.output {
            model.capabilities.output = value;
        }
        if let Some(value) = capabilities.streaming {
            model.capabilities.streaming = value;
        }
        if let Some(value) = capabilities.temperature {
            model.capabilities.temperature = value;
        }
        if let Some(value) = capabilities.reasoning {
            model.capabilities.reasoning = value;
        }
        if let Some(value) = capabilities.web_search {
            model.capabilities.web_search = value;
        }
        if let Some(tools) = capabilities.tools {
            if let Some(value) = tools.function_calling {
                model.capabilities.tools.function_calling = value;
            }
            if let Some(value) = tools.parallel_tool_calls {
                model.capabilities.tools.parallel_tool_calls = value;
            }
            if let Some(value) = tools.custom_tools {
                model.capabilities.tools.custom_tools = value;
            }
            if let Some(value) = tools.freeform_tools {
                model.capabilities.tools.freeform_tools = value;
            }
            if let Some(value) = tools.programmatic_tool_calling {
                model.capabilities.tools.programmatic_tool_calling = value;
            }
        }
    }
    if let Some(value) = record.supports_parallel_tool_calls {
        model.capabilities.tools.parallel_tool_calls = value;
    }
    if let Some(value) = record.supports_function_calling {
        model.capabilities.tools.function_calling = value;
    }
    if let Some(value) = record.supports_temperature {
        model.capabilities.temperature = value;
    }
    if let Some(value) = record.supports_streaming {
        model.capabilities.streaming = value;
    }
    if let Some(value) = record.supports_reasoning {
        model.capabilities.reasoning = value;
    }
    // 缺省模态只由本厂商 parser 给出（当前仅 OpenAI/Codex），且只用于未知模型。
    let input_modalities = match record.input_modalities.take() {
        Some(modalities) => Some(modalities),
        None if !supplied_media_profile && known.is_none() => record.unknown_default_input.clone(),
        None => None,
    };
    if let Some(modalities) = input_modalities {
        model.capabilities.input = input_capabilities(modalities);
        if !explicit_binding {
            model.binding.request.media = if model
                .capabilities
                .supports_input_modality(ModelModality::Image)
            {
                default_image_media(&discovery.transport, dialect)
            } else {
                Vec::new()
            };
        }
    } else if supplied_media_profile && !explicit_binding {
        // A complete capability declaration needs its corresponding explicit binding; never
        // invent a video/file codec.
        let metadata = &mut model.0;
        metadata.binding.request.media.retain(|profile| {
            metadata
                .capabilities
                .supports_input_modality(profile.modality)
        });
    }
    if let Some(value) = record.output_modalities {
        model.capabilities.output = value;
    }
    record
        .reasoning
        .apply(&mut model, dialect, explicit_reasoning)?;
    record.service_tiers.apply(&mut model)?;
    if record.thinking_base_body {
        model.binding.request.body.remove("thinking");
        if !model.supported_efforts().is_empty() {
            model
                .binding
                .request
                .body
                .insert("thinking".into(), serde_json::json!({"type":"enabled"}));
        }
    }
    if clear_context {
        model.context_window = None;
    }
    if clear_max_context {
        model.max_context_window = None;
    }
    if clear_compact {
        model.auto_compact_token_limit = None;
    }
    if clear_output {
        model.max_output_tokens = None;
    }
    if clear_temperature {
        model.default_temperature = None;
    }
    let observation = model
        .observation
        .get_or_insert_with(ModelObservation::default);
    for (field, value) in budgets {
        if let Some(value) = value {
            observation.budgets.insert(field, value);
        }
    }
    if declared_price {
        observation.price_order = Some(0);
    }
    for field in declarations {
        observation.declare(field);
    }
    model
        .validate()
        .map_err(|_| ModelCatalogQueryError::Protocol)?;
    Ok(model)
}

fn minimal(
    model_id: &str,
    transport: &crate::model::ModelTransportProfile,
    dialect: DiscoveryPolicy,
) -> ModelInfo {
    // Streaming is a discovery default, not a verified provider capability or a promise of
    // tools/embedding support. Modalities come from the vendor's own default policy.
    let modalities = dialect.unknown_input.to_vec();
    let request = match transport.protocol {
        crate::protocol::WireApi::Responses => ModelRequestProfile {
            media: minimal_media(transport, dialect, &modalities),
            ..ModelRequestProfile::responses()
        },
        crate::protocol::WireApi::ChatCompletions => ModelRequestProfile {
            media: minimal_media(transport, dialect, &modalities),
            ..ModelRequestProfile::default()
        },
    };
    ModelInfo(crate::model::ModelMetadata {
        model_id: model_id.into(),
        observation: None,
        display_name: model_id.into(),
        description: None,
        context_window: None,
        max_context_window: None,
        auto_compact_token_limit: None,
        default_temperature: None,
        max_output_tokens: None,
        pricing: ModelPricing::Unknown,
        parameters: Vec::new(),
        binding: ModelBinding {
            transport: transport.clone(),
            request,
        },
        capabilities: ModelCapabilities {
            streaming: true,
            temperature: false,
            reasoning: false,
            web_search: false,
            input: input_capabilities(modalities),
            output: vec![ModelModality::Text],
            tools: ToolCapabilities::default(),
            interleaved: None,
            prompt_cache: Default::default(),
            instruction_snapshot_overrides: false,
            native_context_family: None,
        },
        truncation_policy: TruncationPolicy::default(),
        base_instructions: String::new(),
    })
}

/// effort 候选的 wire 规则：Responses 写 `reasoning.effort`，其余方言写 `reasoning_effort`。
pub fn effort_parameter(candidates: Vec<String>, dialect: DiscoveryPolicy) -> ModelParameter {
    let path = if dialect.responses_effort {
        "reasoning.effort"
    } else {
        "reasoning_effort"
    };
    ModelParameter {
        candidate_display_names: Default::default(),
        default: None,
        name: "effort".into(),
        label: None,
        wire: candidates
            .iter()
            .map(|value| {
                (
                    value.clone(),
                    ParameterWire {
                        set: vec![WireAssignment {
                            path: path.into(),
                            value: serde_json::Value::String(value.clone()),
                        }],
                        remove: Vec::new(),
                    },
                )
            })
            .collect(),
        candidates,
    }
}

fn minimal_media(
    transport: &crate::model::ModelTransportProfile,
    dialect: DiscoveryPolicy,
    modalities: &[ModelModality],
) -> Vec<ModelMediaInputProfile> {
    if modalities.contains(&ModelModality::Image) {
        default_image_media(transport, dialect)
    } else {
        Vec::new()
    }
}

fn input_capabilities(modalities: Vec<ModelModality>) -> Vec<ModelInputCapability> {
    modalities
        .into_iter()
        .map(|modality| match modality {
            ModelModality::Text => ModelInputCapability::text(),
            modality => ModelInputCapability::media(
                modality,
                vec![ModelInputSource::Local, ModelInputSource::RemoteUrl],
            ),
        })
        .collect()
}

fn default_image_media(
    transport: &crate::model::ModelTransportProfile,
    dialect: DiscoveryPolicy,
) -> Vec<ModelMediaInputProfile> {
    let wire = match transport.protocol {
        crate::protocol::WireApi::Responses => MediaWireFormat::ResponsesInputImage,
        crate::protocol::WireApi::ChatCompletions => MediaWireFormat::ChatImageUrl,
    };
    image_media_profiles(wire, dialect.media_send_order)
}

/// Presentation fields on a same-ID skeleton do not declare capabilities or budgets.
pub fn enrich_unknown_model_fallback(
    model: &ModelInfo,
    current: &ModelInfo,
    transport: &crate::model::ModelTransportProfile,
    policy: DiscoveryPolicy,
) -> Option<ModelInfo> {
    if model
        .observation
        .as_ref()
        .is_some_and(|o| !o.fields.is_empty())
    {
        return None;
    }
    let mut skeleton = minimal(&model.model_id, transport, policy);
    skeleton.display_name.clone_from(&model.display_name);
    skeleton.description.clone_from(&model.description);
    skeleton.observation.clone_from(&model.observation);
    let uses_current_default = *model == skeleton;
    if !uses_current_default {
        // Only the complete historical skeleton is eligible for same-ID metadata
        // enrichment; richer explicit declarations keep their existing precedence.
        skeleton.capabilities.input = vec![ModelInputCapability::text()];
        skeleton.binding.request.media.clear();
        if *model != skeleton {
            return None;
        }
    }
    let mut enriched = current.clone();
    if uses_current_default {
        enriched
            .capabilities
            .input
            .clone_from(&model.capabilities.input);
        enriched
            .binding
            .request
            .media
            .clone_from(&model.binding.request.media);
    }
    if model.display_name != model.model_id {
        enriched.display_name.clone_from(&model.display_name);
    }
    if model.description.is_some() {
        enriched.description.clone_from(&model.description);
    }
    Some(enriched)
}
