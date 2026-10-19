//! Private provider wire DTOs. Product prompts, shell settings and tool permissions are intentionally absent.
mod reasoning;
use super::ModelCatalogQueryError;
use crate::model::*;
use crate::provider::ProviderAdapterKind;
use reasoning::{Effort, ReasoningDeclaration};
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<Record>>,
    models: Option<Vec<Record>>,
    error: Option<serde::de::IgnoredAny>,
    success: Option<bool>,
}

fn nullable<'de, D, T>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}

enum OnlinePricing {
    Tokens(ModelPricing),
    Other,
}

impl<'de> Deserialize<'de> for OnlinePricing {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        if value
            .get("kind")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|kind| matches!(kind, "rates" | "unknown"))
        {
            serde_json::from_value(value)
                .map(Self::Tokens)
                .map_err(|_| serde::de::Error::custom("invalid token pricing declaration"))
        } else {
            Ok(Self::Other)
        }
    }
}

#[derive(Deserialize)]
struct Record {
    id: Option<String>,
    #[serde(rename = "modelId", alias = "model_id")]
    model_id: Option<String>,
    context_length: Option<u64>,
    pricing: Option<OnlinePricing>,
    prompt_text_token_price: Option<f64>,
    completion_text_token_price: Option<f64>,
    cached_prompt_text_token_price: Option<f64>,
    prompt_text_token_price_long_context: Option<f64>,
    completion_text_token_price_long_context: Option<f64>,
    cached_prompt_text_token_price_long_context: Option<f64>,
    long_context_threshold: Option<u64>,
    slug: Option<String>,
    name: Option<String>,
    display_name: Option<String>,
    #[serde(default, deserialize_with = "nullable")]
    description: Option<Option<String>>,
    #[serde(default, deserialize_with = "nullable")]
    context_window: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    max_context_window: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    auto_compact_token_limit: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    max_output_tokens: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    default_temperature: Option<Option<f32>>,
    input_modalities: Option<Vec<ModelModality>>,
    output_modalities: Option<Vec<ModelModality>>,
    #[serde(flatten)]
    reasoning: ReasoningDeclaration,
    binding: Option<ModelBinding>,
    capabilities: Option<Capabilities>,
    supports_parallel_tool_calls: Option<bool>,
    supports_function_calling: Option<bool>,
    supports_temperature: Option<bool>,
    supports_streaming: Option<bool>,
    supports_reasoning: Option<bool>,
}

impl Record {
    fn declared_fields(&self) -> Vec<ModelMetadataField> {
        use ModelMetadataField::*;
        let mut fields = Vec::new();
        for (present, field) in [
            (
                self.name.is_some() || self.display_name.is_some(),
                DisplayName,
            ),
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
                if present {
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
                    if present {
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
        if self.supports_reasoning == Some(false)
            || self.capabilities.as_ref().and_then(|c| c.reasoning) == Some(false)
        {
            fields.push(Parameters);
        }
        fields
    }

    fn online_pricing(&self) -> Result<Option<ModelPricing>, ModelCatalogQueryError> {
        if [
            self.prompt_text_token_price,
            self.completion_text_token_price,
            self.cached_prompt_text_token_price,
            self.prompt_text_token_price_long_context,
            self.completion_text_token_price_long_context,
            self.cached_prompt_text_token_price_long_context,
        ]
        .into_iter()
        .flatten()
        .any(|price| !price.is_finite() || price < 0.0)
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        let pricing = match &self.pricing {
            Some(OnlinePricing::Tokens(ModelPricing::Unknown)) => None,
            Some(OnlinePricing::Tokens(pricing)) => Some(pricing.clone()),
            _ => match (
                self.prompt_text_token_price,
                self.completion_text_token_price,
            ) {
                (Some(input), Some(output)) => {
                    // xAI documents USD cents per 100 million tokens: divide by 10,000 for USD/Mtok.
                    let mut tiers = vec![TokenPriceTier::flat(
                        input / 10_000.0,
                        output / 10_000.0,
                        self.cached_prompt_text_token_price.map(|p| p / 10_000.0),
                        None,
                    )];
                    if let Some(threshold) = self.long_context_threshold.filter(|v| *v > 0) {
                        tiers[0].input_until = Some(threshold);
                        let mut long = TokenPriceTier::flat(
                            self.prompt_text_token_price_long_context
                                .filter(|v| *v != 0.0)
                                .unwrap_or(input)
                                / 10_000.0,
                            self.completion_text_token_price_long_context
                                .filter(|v| *v != 0.0)
                                .unwrap_or(output)
                                / 10_000.0,
                            self.cached_prompt_text_token_price_long_context
                                .filter(|v| *v != 0.0)
                                .or(self.cached_prompt_text_token_price)
                                .map(|v| v / 10_000.0),
                            None,
                        );
                        long.input_from = threshold;
                        tiers.push(long);
                    }
                    Some(ModelPricing::published_at(
                        "USD",
                        tiers,
                        "provider model catalog",
                        0,
                    ))
                }
                (None, None) => None,
                _ => return Err(ModelCatalogQueryError::Protocol),
            },
        };
        if let Some(value) = &pricing {
            value
                .validate()
                .map_err(|_| ModelCatalogQueryError::Protocol)?;
        }
        Ok(pricing)
    }

    fn identifier(&self) -> Result<&str, ModelCatalogQueryError> {
        if let (Some(a), Some(b)) = (&self.model_id, &self.id)
            && a != b
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        let wire_id = self.model_id.as_deref().or(self.id.as_deref());
        let id = match (wire_id, self.slug.as_deref()) {
            (Some(id), None) | (None, Some(id)) => id,
            (Some(id), Some(slug)) if id == slug => id,
            _ => return Err(ModelCatalogQueryError::Protocol),
        };
        if id.trim().is_empty() {
            return Err(ModelCatalogQueryError::Protocol);
        }
        Ok(id)
    }
}

#[derive(Deserialize)]
struct Capabilities {
    input: Option<Vec<ModelInputCapability>>,
    output: Option<Vec<ModelModality>>,
    streaming: Option<bool>,
    temperature: Option<bool>,
    reasoning: Option<bool>,
    web_search: Option<bool>,
    tools: Option<Tools>,
    reasoning_effort: Option<Vec<String>>,
    #[serde(default, deserialize_with = "nullable")]
    default_reasoning_effort: Option<Option<String>>,
}
#[derive(Deserialize)]
struct Tools {
    function_calling: Option<bool>,
    parallel_tool_calls: Option<bool>,
    custom_tools: Option<bool>,
    freeform_tools: Option<bool>,
    programmatic_tool_calling: Option<bool>,
}

pub(super) fn models(
    bytes: &[u8],
    discovery: &crate::config::ModelCatalogDiscovery,
    adapter: ProviderAdapterKind,
    previous: Option<&[ModelInfo]>,
    defaults: &[ModelInfo],
) -> Result<Vec<ModelInfo>, ModelCatalogQueryError> {
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
    if envelope.error.is_some() || envelope.success == Some(false) {
        return Err(ModelCatalogQueryError::Protocol);
    }
    let records = match (envelope.data, envelope.models) {
        (Some(records), None) | (None, Some(records)) => records,
        _ => return Err(ModelCatalogQueryError::Protocol),
    };
    let mut metadata = defaults
        .iter()
        .map(|model| (model.model_id.clone(), model.clone()))
        .collect::<HashMap<_, _>>();
    for model in previous.into_iter().flatten() {
        let enriched = metadata.get(&model.model_id).and_then(|current| {
            enrich_unknown_model_fallback(model, current, &discovery.transport, adapter)
        });
        metadata.insert(
            model.model_id.clone(),
            enriched.unwrap_or_else(|| model.clone()),
        );
    }
    let mut positions = HashMap::new();
    let mut result = Vec::new();
    for record in records {
        let id = record.identifier()?.to_owned();
        let model = normalize(record, discovery, adapter, &metadata)?;
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
    adapter: ProviderAdapterKind,
    metadata: &HashMap<String, ModelInfo>,
) -> Result<ModelInfo, ModelCatalogQueryError> {
    let model_id = record.identifier()?.to_owned();
    if record.context_window.is_none() {
        record.context_window = record.context_length.map(Some);
    }
    if !record.reasoning.declares_candidates()
        && let Some(capabilities) = &mut record.capabilities
        && let Some(levels) = capabilities.reasoning_effort.take()
    {
        record.reasoning.effort = Some(Effort {
            supported_levels: levels,
            default_level: capabilities.default_reasoning_effort.take(),
        });
    }
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
    let pricing = record.online_pricing()?;
    let known = metadata.get(model_id.as_str());
    let mut model = known
        .cloned()
        .unwrap_or_else(|| minimal(&model_id, &discovery.transport, adapter));
    let declared_price = pricing.is_some();
    if let Some(pricing) = pricing {
        model.pricing = pricing;
    } else if model
        .observation
        .as_ref()
        .and_then(|o| o.price_order)
        .is_none()
    {
        model.pricing = ModelPricing::Unknown;
    }
    if let Some(value) = record.display_name.or(record.name) {
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
        // Discovery may declare transport/media, not override endpoint credentials or inject product instructions.
        if value.request.api_model.is_some()
            || !value.request.headers.is_empty()
            || !value.request.body.is_empty()
            || !super::valid_discovery_transport(&value.transport, &discovery.transport)
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
    // Match Codex: an absent declaration defaults to text + image. An explicit
    // capability list (including an empty one) must never be replaced by this default.
    let input_modalities = record
        .input_modalities
        .or_else(|| (!supplied_media_profile && known.is_none()).then(default_input_modalities));
    if let Some(modalities) = input_modalities {
        model.capabilities.input = input_capabilities(modalities);
        if !explicit_binding {
            model.binding.request.media = if model
                .capabilities
                .supports_input_modality(ModelModality::Image)
            {
                default_image_media(&discovery.transport, adapter)
            } else {
                Vec::new()
            };
        }
    } else if supplied_media_profile && !explicit_binding {
        // A complete capability declaration needs its corresponding explicit binding; never invent a video/file codec.
        model
            .binding
            .request
            .media
            .retain(|p| model.capabilities.supports_input_modality(p.modality));
    }
    if let Some(value) = record.output_modalities {
        model.capabilities.output = value;
    }
    record
        .reasoning
        .apply(&mut model, adapter, explicit_reasoning)?;
    if adapter == ProviderAdapterKind::DeepSeek {
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
    adapter: ProviderAdapterKind,
) -> ModelInfo {
    // Streaming and text/image are discovery defaults, not a verified
    // provider capability or a promise of tools/embedding support.
    let request = match transport.protocol {
        crate::provider::ProviderWireProtocol::Responses => ModelRequestProfile {
            media: default_image_media(transport, adapter),
            ..ModelRequestProfile::responses()
        },
        crate::provider::ProviderWireProtocol::ChatCompletions => ModelRequestProfile {
            media: default_image_media(transport, adapter),
            ..ModelRequestProfile::default()
        },
    };
    ModelInfo {
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
            input: input_capabilities(default_input_modalities()),
            output: vec![ModelModality::Text],
            tools: ToolCapabilities::default(),
            interleaved: None,
            prompt_cache: Default::default(),
            instruction_snapshot_overrides: false,
            native_context_family: None,
        },
        truncation_policy: TruncationPolicy::default(),
        base_instructions: String::new(),
    }
}

fn default_input_modalities() -> Vec<ModelModality> {
    vec![ModelModality::Text, ModelModality::Image]
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
    adapter: ProviderAdapterKind,
) -> Vec<ModelMediaInputProfile> {
    let wire = match transport.protocol {
        crate::provider::ProviderWireProtocol::Responses => MediaWireFormat::ResponsesInputImage,
        crate::provider::ProviderWireProtocol::ChatCompletions => MediaWireFormat::ChatImageUrl,
    };
    image_media_profiles(
        wire,
        if adapter == ProviderAdapterKind::DeepSeek {
            MediaSendOrder::ProviderFileFirst
        } else {
            MediaSendOrder::RemoteUrlFirst
        },
    )
}

/// Presentation fields on a same-ID skeleton do not declare capabilities or budgets.
pub(crate) fn enrich_unknown_model_fallback(
    model: &ModelInfo,
    current: &ModelInfo,
    transport: &crate::model::ModelTransportProfile,
    adapter: ProviderAdapterKind,
) -> Option<ModelInfo> {
    if model
        .observation
        .as_ref()
        .is_some_and(|o| !o.fields.is_empty())
    {
        return None;
    }
    let mut skeleton = minimal(&model.model_id, transport, adapter);
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

fn uses_responses_effort(adapter: ProviderAdapterKind) -> bool {
    matches!(
        adapter,
        ProviderAdapterKind::OpenAi | ProviderAdapterKind::Xai
    )
}

fn effort_parameter(candidates: Vec<String>, adapter: ProviderAdapterKind) -> ModelParameter {
    let path = if uses_responses_effort(adapter) {
        "reasoning.effort"
    } else {
        "reasoning_effort"
    };
    ModelParameter {
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
