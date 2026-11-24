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

/// Parsed single page of an online model catalog response.
#[derive(Debug, Clone, Default)]
pub struct ParsedCatalogPage {
    pub records: Vec<Record>,
    pub next_page_token: Option<String>,
}

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
    pub codex: Option<CodexModel>,
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

/// 解析一份成功名单：先由该厂商 typed parser 提取声明，再复用账号内合成与校验。
pub fn models(
    records: Vec<Record>,
    discovery: &crate::config::ModelCatalogDiscovery,
    dialect: DiscoveryPolicy,
    previous: Option<&[ModelDefinition]>,
    defaults: &[ModelDefinition],
) -> Result<Vec<ModelDefinition>, ModelCatalogQueryError> {
    let mut metadata = defaults
        .iter()
        .map(|model| (model.base.slug.clone(), model.clone()))
        .collect::<HashMap<_, _>>();
    for model in previous.into_iter().flatten() {
        let enriched = metadata.get(&model.base.slug).and_then(|current| {
            enrich_unknown_model_fallback(model, current, &discovery.transport, dialect)
        });
        metadata.insert(
            model.base.slug.clone(),
            enriched.unwrap_or_else(|| model.clone()),
        );
    }
    let mut positions = HashMap::new();
    let mut result = Vec::new();
    for record in records {
        let id = record.id.clone();
        let model = normalize(record, discovery, dialect, &metadata)?;
        metadata.insert(model.base.slug.clone(), model.clone());
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
    metadata: &HashMap<String, ModelDefinition>,
) -> Result<ModelDefinition, ModelCatalogQueryError> {
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
    let pricing = record
        .pricing
        .take()
        .filter(|p| *p != ModelPricing::Unknown);
    let declared_price = pricing.is_some();
    if let Some(pricing) = pricing {
        model.extra.pricing = pricing;
    } else if model
        .observation
        .as_ref()
        .and_then(|o| o.price_order)
        .is_none()
    {
        model.extra.pricing = ModelPricing::Unknown;
    }
    if let Some(value) = record.display_name.take() {
        model.base.display_name = value;
    }
    if let Some(value) = record.description.take() {
        model.base.description = value;
    }
    // 在线预算只覆盖它实际声明的字段；缺失的配对字段按观测事实单侧收敛，
    // 不凭空补成固定预算。同时声明两者时仍由 validate 要求自身一致。
    match (
        record.context_window.flatten(),
        record.max_context_window.flatten(),
    ) {
        (Some(current), Some(max)) => {
            model.base.context_window = Some(current);
            model.base.max_context_window = Some(max);
        }
        (Some(current), None) => {
            model.base.context_window = Some(current);
            if model
                .base
                .max_context_window
                .is_some_and(|max| max < current)
            {
                // 观测到的窗口是更新的服务端事实，抬升过时的继承上限。
                model.base.max_context_window = Some(current);
            }
        }
        (None, Some(max)) => {
            // 在线只声明更小的上限：继承的当前窗口收敛到该上限，
            // 不能因内置当前窗口更大而拒绝名单或继续使用旧容量。
            model.base.max_context_window = Some(max);
            if model
                .base
                .context_window
                .is_some_and(|current| current > max)
            {
                model.base.context_window = Some(max);
            }
        }
        (None, None) => {}
    }
    if let Some(value) = record.max_output_tokens.flatten() {
        model.extra.max_output_tokens = Some(value);
    }
    if let Some(value) = record.auto_compact_token_limit.flatten() {
        model.base.auto_compact_token_limit = Some(value);
    }
    if let Some(value) = record.default_temperature.flatten() {
        model.extra.default_temperature = Some(value);
    }
    let explicit_binding = record.binding.is_some();
    if let Some(value) = record.binding.take() {
        // Discovery may declare transport/media, not override endpoint credentials or inject
        // product instructions.
        if value.request.api_model.is_some()
            || !value.request.headers.is_empty()
            || !value.request.body.is_empty()
            || !valid_discovery_transport(&value.transport, &discovery.transport)
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        model.extra.binding = value;
        // Canonicalize ordering, never restore a connection candidate the API withdrew.
        model.extra.binding.transport.supported_connection_modes = discovery
            .transport
            .supported_connection_modes
            .iter()
            .copied()
            .filter(|mode| {
                model
                    .extra
                    .binding
                    .transport
                    .supported_connection_modes
                    .contains(mode)
            })
            .collect();
    }
    let explicit_reasoning = record
        .supports_reasoning
        .or_else(|| record.capabilities.as_ref().and_then(|c| c.reasoning));
    apply_capabilities(&mut record, &mut model, dialect, explicit_binding);
    let effort_policy = if record
        .codex
        .as_ref()
        .is_some_and(|base| base.supported_reasoning_levels.is_some())
    {
        DiscoveryPolicy {
            responses_effort: discovery.transport.protocol == crate::protocol::WireApi::Responses,
            ..dialect
        }
    } else {
        dialect
    };
    record
        .reasoning
        .apply(&mut model, effort_policy, explicit_reasoning)?;
    record.service_tiers.apply(&mut model)?;
    if record.thinking_base_body {
        model.extra.binding.request.body.remove("thinking");
        if !model.supported_efforts().is_empty() {
            model
                .extra
                .binding
                .request
                .body
                .insert("thinking".into(), serde_json::json!({"type":"enabled"}));
        }
    }
    if clear_context {
        model.base.context_window = None;
    }
    if clear_max_context {
        model.base.max_context_window = None;
    }
    if clear_compact {
        model.base.auto_compact_token_limit = None;
    }
    if clear_output {
        model.extra.max_output_tokens = None;
    }
    if clear_temperature {
        model.extra.default_temperature = None;
    }
    if let Some(codex) = record.codex {
        if let Some(levels) = codex.supported_reasoning_levels {
            if levels.is_empty() {
                model
                    .base
                    .default_reasoning_level
                    .clone_from(&codex.default_reasoning_level);
            }
            model.base.supported_reasoning_levels = Some(levels);
        }
        model.base.fields.extend(codex.fields);
        if codex.model_messages != Default::default() {
            model.base.model_messages = codex.model_messages;
        }
        if codex.truncation_policy != Default::default() {
            model.base.truncation_policy = codex.truncation_policy;
        }
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

/// Apply only explicitly declared model capabilities using the same rules for online
/// records and sparse manual edits. Account authorization remains a separate concern.
pub fn apply_capabilities(
    record: &mut Record,
    model: &mut ModelDefinition,
    dialect: DiscoveryPolicy,
    explicit_binding: bool,
) {
    let supplied_media_profile = record
        .capabilities
        .as_ref()
        .is_some_and(|c| c.input.is_some());
    if let Some(capabilities) = record.capabilities.take() {
        if let Some(value) = capabilities.input {
            model.extra.capabilities.input = value;
        }
        if let Some(value) = capabilities.output {
            model.extra.capabilities.output = value;
        }
        if let Some(value) = capabilities.streaming {
            model.extra.capabilities.streaming = value;
        }
        if let Some(value) = capabilities.temperature {
            model.extra.capabilities.temperature = value;
        }
        if let Some(value) = capabilities.reasoning {
            model.extra.capabilities.reasoning = value;
        }
        if let Some(value) = capabilities.web_search {
            model.extra.capabilities.web_search = value;
        }
        if let Some(tools) = capabilities.tools {
            if let Some(value) = tools.function_calling {
                model.extra.capabilities.tools.function_calling = value;
            }
            if let Some(value) = tools.parallel_tool_calls {
                model.base.supports_parallel_tool_calls = Some(value);
            }
            if let Some(value) = tools.custom_tools {
                model.extra.capabilities.tools.custom_tools = value;
            }
            if let Some(value) = tools.freeform_tools {
                model.extra.capabilities.tools.freeform_tools = value;
            }
            if let Some(value) = tools.programmatic_tool_calling {
                model.extra.capabilities.tools.programmatic_tool_calling = value;
            }
        }
    }
    if let Some(value) = record.supports_parallel_tool_calls {
        model.base.supports_parallel_tool_calls = Some(value);
    }
    if let Some(value) = record.supports_function_calling {
        model.extra.capabilities.tools.function_calling = value;
    }
    if let Some(value) = record.supports_temperature {
        model.extra.capabilities.temperature = value;
    }
    if let Some(value) = record.supports_streaming {
        model.extra.capabilities.streaming = value;
    }
    if let Some(value) = record.supports_reasoning {
        model.extra.capabilities.reasoning = value;
    }
    // 缺省模态只由本厂商 parser 给出（当前仅 OpenAI/Codex），且只用于未知模型。
    if let Some(modalities) = record.input_modalities.take() {
        // Model modalities describe the inputs a model reasons over. A separately
        // declared document decoder can supply text to a text-capable model.
        let file = model
            .extra
            .capabilities
            .input
            .iter()
            .find(|c| c.modality == ModelModality::File)
            .cloned();
        let mut inputs = input_capabilities(modalities);
        if !supplied_media_profile
            && let Some(file) = file
            && inputs.iter().any(|c| c.modality == ModelModality::Text)
            && !inputs.iter().any(|c| c.modality == ModelModality::File)
        {
            inputs.push(file);
        }
        if !supplied_media_profile {
            model.extra.capabilities.input = inputs;
        }
        if !explicit_binding {
            let media = &mut model.extra.binding.request.media;
            media.retain(|p| model.extra.capabilities.supports_input_modality(p.modality));
            if model
                .extra
                .capabilities
                .supports_input_modality(ModelModality::Image)
                && !media.iter().any(|p| p.modality == ModelModality::Image)
            {
                media.extend(default_image_media(&model.extra.binding.transport, dialect));
            }
            if model
                .extra
                .capabilities
                .supports_input_modality(ModelModality::File)
                && !media.iter().any(|p| p.modality == ModelModality::File)
            {
                match model.extra.binding.transport.protocol {
                    crate::protocol::WireApi::Responses => media.push(media_profile(
                        ModelModality::File,
                        MediaWireFormat::ResponsesInputFile,
                        dialect.media_send_order,
                    )),
                    crate::protocol::WireApi::GeminiGenerateContent => {
                        media.push(ModelMediaInputProfile {
                            modality: ModelModality::File,
                            wire: MediaWireFormat::GeminiInlineFile,
                            first_send: vec![MediaRepresentation::DataUrl],
                            replay: vec![MediaRepresentation::DataUrl],
                        });
                    }
                    crate::protocol::WireApi::ChatCompletions => {}
                }
            }
        }
    } else if supplied_media_profile && !explicit_binding {
        // A complete capability declaration needs its corresponding explicit binding; never
        // invent a video/file codec.
        let metadata = &mut model.extra;
        metadata.binding.request.media.retain(|profile| {
            metadata
                .capabilities
                .supports_input_modality(profile.modality)
        });
    }
    if let Some(value) = record.output_modalities.take() {
        model.extra.capabilities.output = value;
    }
}

fn minimal(
    model_id: &str,
    transport: &crate::model::ModelTransportProfile,
    dialect: DiscoveryPolicy,
) -> ModelDefinition {
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
        crate::protocol::WireApi::GeminiGenerateContent => ModelRequestProfile {
            media: minimal_media(transport, dialect, &modalities),
            ..ModelRequestProfile::gemini()
        },
    };
    ModelDefinition {
        observation: None,
        base: crate::model::CodexModel {
            slug: model_id.into(),
            display_name: model_id.into(),
            description: None,
            context_window: None,
            max_context_window: None,
            auto_compact_token_limit: None,
            truncation_policy: TruncationPolicy::default(),
            model_messages: crate::model::ModelMessages {
                instructions_template: String::new(),
                ..Default::default()
            },
            ..Default::default()
        },
        extra: crate::model::ModelExtras {
            default_temperature: None,
            max_output_tokens: None,
            pricing: ModelPricing::Unknown,
            parameters: Vec::new(),
            effort_label: None,
            effort_wire: Default::default(),
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
        },
    }
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
    default_media_profiles(transport, dialect, modalities)
}

fn default_media_profiles(
    transport: &crate::model::ModelTransportProfile,
    dialect: DiscoveryPolicy,
    modalities: &[ModelModality],
) -> Vec<ModelMediaInputProfile> {
    let mut profiles = if modalities.contains(&ModelModality::Image) {
        default_image_media(transport, dialect)
    } else {
        Vec::new()
    };
    if transport.protocol == crate::protocol::WireApi::GeminiGenerateContent
        && modalities.contains(&ModelModality::File)
    {
        profiles.push(ModelMediaInputProfile {
            modality: ModelModality::File,
            wire: MediaWireFormat::GeminiInlineFile,
            first_send: vec![MediaRepresentation::DataUrl],
            replay: vec![MediaRepresentation::DataUrl],
        });
    }
    profiles
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
        crate::protocol::WireApi::GeminiGenerateContent => MediaWireFormat::GeminiInlineImage,
    };
    image_media_profiles(wire, dialect.media_send_order)
}

/// Presentation fields on a same-ID skeleton do not declare capabilities or budgets.
pub fn enrich_unknown_model_fallback(
    model: &ModelDefinition,
    current: &ModelDefinition,
    transport: &crate::model::ModelTransportProfile,
    policy: DiscoveryPolicy,
) -> Option<ModelDefinition> {
    if model
        .observation
        .as_ref()
        .is_some_and(|o| !o.fields.is_empty())
    {
        return None;
    }
    let mut skeleton = minimal(&model.base.slug, transport, policy);
    skeleton
        .base
        .display_name
        .clone_from(&model.base.display_name);
    skeleton
        .base
        .description
        .clone_from(&model.base.description);
    skeleton.observation.clone_from(&model.observation);
    let uses_current_default = *model == skeleton;
    if !uses_current_default {
        // Only the complete historical skeleton is eligible for same-ID metadata
        // enrichment; richer explicit declarations keep their existing precedence.
        skeleton.extra.capabilities.input = vec![ModelInputCapability::text()];
        skeleton.extra.binding.request.media.clear();
        if *model != skeleton {
            return None;
        }
    }
    let mut enriched = current.clone();
    if uses_current_default {
        enriched
            .extra
            .capabilities
            .input
            .clone_from(&model.extra.capabilities.input);
        enriched
            .extra
            .binding
            .request
            .media
            .clone_from(&model.extra.binding.request.media);
    }
    if model.base.display_name != model.base.slug {
        enriched
            .base
            .display_name
            .clone_from(&model.base.display_name);
    }
    if model.base.description.is_some() {
        enriched
            .base
            .description
            .clone_from(&model.base.description);
    }
    Some(enriched)
}
