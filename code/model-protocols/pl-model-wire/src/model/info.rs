use std::collections::{BTreeMap, HashMap};

use serde::Deserialize;
use serde::Serialize;
use serde_json::Map;
use serde_json::Value;

use crate::model::capabilities::{ModelCapabilities, ModelModality};
use crate::model::parameter::ModelParameter;
use crate::model::profile_error::ModelProfileError;
use crate::protocol::{ConnectionMode, WireApi};

/// One model declaration shared by bundled, discovered and manually supplied members.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelDefinition {
    pub base: super::CodexModel,
    #[serde(default, skip_serializing_if = "is_default")]
    pub extra: ModelExtras,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub observation: Option<super::ModelObservation>,
}

/// Runtime bindings and metadata with no corresponding Codex field.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ModelExtras {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_output_tokens: Option<u64>,
    #[serde(skip_serializing_if = "is_default")]
    pub pricing: super::ModelPricing,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub parameters: Vec<ModelParameter>,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub effort_wire: BTreeMap<String, super::ParameterWire>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort_label: Option<String>,
    #[serde(skip_serializing_if = "is_default")]
    pub binding: ModelBinding,
    #[serde(skip_serializing_if = "is_default")]
    pub capabilities: ModelCapabilities,
}

fn is_default<T: Default + PartialEq>(value: &T) -> bool {
    *value == T::default()
}

pub use pl_model_types::model::{TruncationMode, TruncationPolicy};

/// 在线发现但无内置对应、或手动配置的模型，在未显式声明 `auto_compact_token_limit`
/// 时采用的默认自动压缩阈值（256K token）。若上下文已声明，则与上下文 90% 取较小值。
pub const DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT: u64 = 256_000;

/// 未显式声明 `auto_compact_token_limit` 时的默认自动压缩策略。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum AutoCompactDefaultPolicy {
    /// 绑定内置定义的模型（含命中内置 ID 的在线观测）：仅按上下文 90% 推导，上下文未知时保持未启用。
    #[default]
    Bundled,
    /// 无内置对应的在线模型及手动配置模型：未显式声明 `auto_compact_token_limit` 时，
    /// 使用 [`DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT`]（256,000）与上下文 90% 的较小值；上下文未知时取 256,000。
    UnbundledOrManual,
}

/// Adapter binding kept separate from provider-neutral model metadata.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelBinding {
    pub transport: ModelTransportProfile,
    pub request: ModelRequestProfile,
}

impl Default for ModelBinding {
    fn default() -> Self {
        Self {
            transport: Default::default(),
            request: ModelRequestProfile {
                protocol: ModelProtocolOptions::ChatCompletions(ChatRequestOptions {
                    include_usage: true,
                    ..Default::default()
                }),
                ..Default::default()
            },
        }
    }
}

impl ModelBinding {
    /// Changes wire API and its protocol-specific defaults together, preserving same-API options.
    pub fn set_transport(&mut self, transport: ModelTransportProfile) {
        let matches = matches!(
            (&self.request.protocol, transport.protocol),
            (ModelProtocolOptions::Responses(_), WireApi::Responses)
                | (
                    ModelProtocolOptions::ChatCompletions(_),
                    WireApi::ChatCompletions
                )
                | (
                    ModelProtocolOptions::GeminiGenerateContent(_),
                    WireApi::GeminiGenerateContent
                )
        );
        if !matches {
            self.request.protocol = match transport.protocol {
                WireApi::Responses => ModelProtocolOptions::Responses(Default::default()),
                WireApi::ChatCompletions => {
                    ModelProtocolOptions::ChatCompletions(Default::default())
                }
                WireApi::GeminiGenerateContent => {
                    ModelProtocolOptions::GeminiGenerateContent(Default::default())
                }
            };
        }
        self.transport = transport;
    }
}

/// 模型拥有的 API wire 与连接策略。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelTransportProfile {
    pub protocol: WireApi,
    pub supported_connection_modes: Vec<ConnectionMode>,
    pub default_connection_mode: ConnectionMode,
}

impl ModelTransportProfile {
    pub fn responses_websocket() -> Self {
        Self {
            protocol: WireApi::Responses,
            supported_connection_modes: vec![ConnectionMode::WebSocket, ConnectionMode::Http],
            default_connection_mode: ConnectionMode::WebSocket,
        }
    }

    pub fn responses_http() -> Self {
        Self {
            protocol: WireApi::Responses,
            supported_connection_modes: vec![ConnectionMode::Http],
            default_connection_mode: ConnectionMode::Http,
        }
    }

    pub fn chat_completions_http() -> Self {
        Self {
            protocol: WireApi::ChatCompletions,
            supported_connection_modes: vec![ConnectionMode::Http],
            default_connection_mode: ConnectionMode::Http,
        }
    }

    pub fn gemini_http() -> Self {
        Self {
            protocol: WireApi::GeminiGenerateContent,
            supported_connection_modes: vec![ConnectionMode::Http],
            default_connection_mode: ConnectionMode::Http,
        }
    }
}

impl Default for ModelTransportProfile {
    fn default() -> Self {
        Self::chat_completions_http()
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ModelRequestProfile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub api_model: Option<String>,
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub headers: HashMap<String, String>,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub body: Map<String, Value>,
    pub protocol: ModelProtocolOptions,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub media: Vec<ModelMediaInputProfile>,
    #[serde(default, skip_serializing_if = "MediaMixPolicy::is_default")]
    pub media_mix_policy: MediaMixPolicy,
}

impl ModelRequestProfile {
    /// 所有字段均未设置时返回 true（用于字段级合并判断「用户未提供」）。
    pub fn is_empty(&self) -> bool {
        self.api_model.is_none()
            && self.headers.is_empty()
            && self.body.is_empty()
            && self.protocol == ModelProtocolOptions::default()
            && self.media.is_empty()
            && self.media_mix_policy.is_default()
    }

    pub fn media_profile(&self, modality: ModelModality) -> Option<&ModelMediaInputProfile> {
        self.media
            .iter()
            .find(|profile| profile.modality == modality)
    }
}

/// Only options belonging to the selected wire API are representable.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "api", rename_all = "camelCase")]
pub enum ModelProtocolOptions {
    Responses(ResponsesRequestOptions),
    ChatCompletions(ChatRequestOptions),
    GeminiGenerateContent(GeminiRequestOptions),
}
impl Default for ModelProtocolOptions {
    fn default() -> Self {
        Self::ChatCompletions(ChatRequestOptions::default())
    }
}
/// Responses-only request controls.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResponsesRequestOptions {
    pub programmatic_tool_calling: bool,
    pub max_tokens_field: ResponsesMaxTokensField,
}
/// Chat-only request controls. Usage requests are independent of tool streaming.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatRequestOptions {
    pub parallel_tool_calls: bool,
    pub max_tokens_field: MaxTokensField,
    pub include_usage: bool,
    pub tool_stream: bool,
}
/// Gemini native `generateContent` request controls.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GeminiRequestOptions {
    #[serde(default)]
    pub include_thoughts: bool,
    #[serde(default = "default_true")]
    pub use_parameters_json_schema: bool,
}
impl Default for GeminiRequestOptions {
    fn default() -> Self {
        Self {
            include_thoughts: true,
            use_parameters_json_schema: true,
        }
    }
}
const fn default_true() -> bool {
    true
}
impl ModelRequestProfile {
    pub fn responses() -> Self {
        Self {
            protocol: ModelProtocolOptions::Responses(ResponsesRequestOptions::default()),
            ..Self::default()
        }
    }
    pub fn gemini() -> Self {
        Self {
            protocol: ModelProtocolOptions::GeminiGenerateContent(GeminiRequestOptions::default()),
            ..Self::default()
        }
    }
    pub fn supports_programmatic_tool_calling(&self) -> bool {
        matches!(&self.protocol, ModelProtocolOptions::Responses(options) if options.programmatic_tool_calling)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelMediaInputProfile {
    pub modality: ModelModality,
    pub wire: MediaWireFormat,
    pub first_send: Vec<MediaRepresentation>,
    pub replay: Vec<MediaRepresentation>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaWireFormat {
    ChatImageUrl,
    ChatVideoUrl,
    ChatFileUrl,
    ResponsesInputImage,
    ResponsesInputFile,
    GeminiInlineImage,
    GeminiInlineFile,
}

impl MediaWireFormat {
    fn modality(self) -> ModelModality {
        match self {
            Self::ChatImageUrl | Self::ResponsesInputImage | Self::GeminiInlineImage => {
                ModelModality::Image
            }
            Self::ChatVideoUrl => ModelModality::Video,
            Self::ChatFileUrl | Self::ResponsesInputFile | Self::GeminiInlineFile => {
                ModelModality::File
            }
        }
    }

    fn protocol(self) -> WireApi {
        match self {
            Self::ChatImageUrl | Self::ChatVideoUrl | Self::ChatFileUrl => WireApi::ChatCompletions,
            Self::ResponsesInputImage | Self::ResponsesInputFile => WireApi::Responses,
            Self::GeminiInlineImage | Self::GeminiInlineFile => WireApi::GeminiGenerateContent,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaRepresentation {
    RemoteUrl,
    ProviderFile,
    DataUrl,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaMixPolicy {
    #[default]
    Any,
    SingleModality,
}

impl MediaMixPolicy {
    fn is_default(&self) -> bool {
        *self == Self::Any
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MaxTokensField {
    #[default]
    MaxTokens,
    MaxCompletionTokens,
}

impl MaxTokensField {
    pub fn is_default(&self) -> bool {
        *self == Self::MaxTokens
    }
}

/// Controls how a Responses request serializes [`CompletionRequest::max_tokens`](crate::completion::CompletionRequest::max_tokens).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResponsesMaxTokensField {
    #[default]
    Omit,
    MaxOutputTokens,
    MaxTokens,
    MaxCompletionTokens,
}

impl ResponsesMaxTokensField {
    pub fn is_default(&self) -> bool {
        *self == Self::Omit
    }
}

impl ModelDefinition {
    pub fn validate_media_contract(&self) -> Result<(), ModelProfileError> {
        let mut modalities = Vec::new();
        for capability in &self.extra.capabilities.input {
            if modalities.contains(&capability.modality) {
                return Err(ModelProfileError::DuplicateInputModality {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            modalities.push(capability.modality);
            if capability.modality == ModelModality::Text {
                if !capability.sources.is_empty() {
                    return Err(ModelProfileError::TextInputDeclaresMediaSources {
                        model: self.base.slug.clone(),
                    });
                }
                continue;
            }
            let profile = self
                .extra
                .binding
                .request
                .media_profile(capability.modality)
                .ok_or_else(|| ModelProfileError::ModalityWithoutMediaProfile {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                })?;
            if capability.sources.is_empty() {
                return Err(ModelProfileError::ModalityWithoutAdmittedSources {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            if profile.first_send.is_empty() || profile.replay.is_empty() {
                return Err(ModelProfileError::MissingSendOrReplayRepresentations {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            if profile.wire.modality() != profile.modality {
                return Err(ModelProfileError::WireModalityMismatch {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                    wire: profile.wire,
                });
            }
            if profile.wire.protocol() != self.extra.binding.transport.protocol {
                return Err(ModelProfileError::WireProtocolMismatch {
                    model: self.base.slug.clone(),
                    wire: profile.wire,
                    protocol: self.extra.binding.transport.protocol,
                });
            }
            if has_duplicates(&profile.first_send) || has_duplicates(&profile.replay) {
                return Err(ModelProfileError::RepeatedMediaRepresentation {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            if profile.replay.contains(&MediaRepresentation::RemoteUrl) {
                return Err(ModelProfileError::ReplayUsesRemoteUrl {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            if capability
                .sources
                .contains(&crate::model::ModelInputSource::Local)
                && !profile.first_send.iter().any(|representation| {
                    matches!(
                        representation,
                        MediaRepresentation::ProviderFile | MediaRepresentation::DataUrl
                    )
                })
            {
                return Err(ModelProfileError::LocalSourceWithoutDurableRepresentation {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            if profile.first_send.contains(&MediaRepresentation::RemoteUrl)
                && !capability
                    .sources
                    .contains(&crate::model::ModelInputSource::RemoteUrl)
            {
                return Err(ModelProfileError::RemoteUrlStrategyWithoutAdmission {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
            if profile
                .replay
                .iter()
                .all(|representation| *representation == MediaRepresentation::RemoteUrl)
            {
                return Err(ModelProfileError::ReplayNotDurable {
                    model: self.base.slug.clone(),
                    modality: capability.modality,
                });
            }
        }
        let mut profile_modalities = Vec::new();
        for profile in &self.extra.binding.request.media {
            if profile_modalities.contains(&profile.modality) {
                return Err(ModelProfileError::DuplicateMediaProfile {
                    model: self.base.slug.clone(),
                    modality: profile.modality,
                });
            }
            profile_modalities.push(profile.modality);
            if !self
                .extra
                .capabilities
                .supports_input_modality(profile.modality)
            {
                return Err(ModelProfileError::MediaProfileForUndeclaredModality {
                    model: self.base.slug.clone(),
                    modality: profile.modality,
                });
            }
        }
        Ok(())
    }

    /// Validates a complete model binding and its price table before use.
    /// # Errors
    /// Returns the inconsistent transport, media or tariff contract, or a
    /// non-positive default auto-compact token limit.
    pub fn validate(&self) -> Result<(), ModelProfileError> {
        if self.base.auto_compact_token_limit == Some(0) {
            return Err(ModelProfileError::InvalidAutoCompactTokenLimit {
                model: self.base.slug.clone(),
            });
        }
        if self
            .resolve_context(None, AutoCompactDefaultPolicy::Bundled)
            .unavailable
            == Some(crate::model::ModelContextUnavailable::InvalidParameters)
            || self
                .extra
                .default_temperature
                .is_some_and(|t| !t.is_finite() || t < 0.0)
        {
            return Err(ModelProfileError::InvalidBudget {
                model: self.base.slug.clone(),
            });
        }
        let mut names = std::collections::BTreeSet::new();
        for parameter in self.parameters() {
            let mut candidates = std::collections::BTreeSet::new();
            if parameter.name.trim().is_empty()
                || !names.insert(parameter.name.clone())
                || parameter.candidates.is_empty()
                || parameter
                    .default
                    .as_ref()
                    .is_some_and(|value| !parameter.candidates.contains(value))
                || parameter
                    .candidates
                    .iter()
                    .any(|c| c.trim().is_empty() || !candidates.insert(c))
                || parameter.wire.len() != candidates.len()
                || parameter.wire.iter().any(|(candidate, wire)| {
                    !candidates.contains(candidate)
                        || wire.set.is_empty() && wire.remove.is_empty()
                        || wire
                            .set
                            .iter()
                            .map(|s| &s.path)
                            .chain(&wire.remove)
                            .any(|path| path.split('.').any(str::is_empty))
                })
            {
                return Err(ModelProfileError::InvalidParameter {
                    model: self.base.slug.clone(),
                });
            }
        }
        self.extra.binding.transport.validate(&self.base.slug)?;
        if !matches!(
            (
                &self.extra.binding.request.protocol,
                self.extra.binding.transport.protocol
            ),
            (ModelProtocolOptions::Responses(_), WireApi::Responses)
                | (
                    ModelProtocolOptions::ChatCompletions(_),
                    WireApi::ChatCompletions
                )
                | (
                    ModelProtocolOptions::GeminiGenerateContent(_),
                    WireApi::GeminiGenerateContent
                )
        ) {
            return Err(ModelProfileError::ProtocolOptionsMismatch {
                model: self.base.slug.clone(),
                protocol: self.extra.binding.transport.protocol,
            });
        }
        self.extra
            .pricing
            .validate()
            .map_err(|source| ModelProfileError::InvalidPricing {
                model: self.base.slug.clone(),
                source,
            })?;
        self.validate_media_contract()
    }

    /// Resolves the complete context policy. Consumers must reuse the catalog's frozen result.
    pub fn resolve_context(
        &self,
        override_limit: Option<u64>,
        default_policy: AutoCompactDefaultPolicy,
    ) -> crate::model::ModelContextResolution {
        use crate::model::{
            ModelContextAdjustment, ModelContextResolution, ModelContextUnavailable,
        };
        let window = self.base.context_window.or(self.base.max_context_window);
        let invalid = [
            self.base.context_window,
            self.base.max_context_window,
            self.extra.max_output_tokens,
            self.base.auto_compact_token_limit,
            override_limit,
        ]
        .contains(&Some(0))
            || self
                .base
                .context_window
                .zip(self.base.max_context_window)
                .is_some_and(|(current, maximum)| current > maximum);
        let capacity = self.base.max_context_window.or(window);
        let fallback_limit = match default_policy {
            AutoCompactDefaultPolicy::Bundled => None,
            AutoCompactDefaultPolicy::UnbundledOrManual => {
                Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
            }
        };
        let default_ceiling = window.map(ninety_percent);
        let configured_default = self.base.auto_compact_token_limit.or(fallback_limit);
        let default_limit = match (configured_default, default_ceiling) {
            (Some(limit), Some(ceiling)) => Some(limit.min(ceiling)),
            (limit, ceiling) => limit.or(ceiling),
        };
        let requested = override_limit.or(default_limit);
        let maximum = capacity.map(ninety_percent);
        let effective = requested.map(|limit| maximum.map_or(limit, |max| limit.min(max)));
        ModelContextResolution {
            unavailable: invalid.then_some(ModelContextUnavailable::InvalidParameters),
            context_window: capacity,
            auto_compact_limit: effective.filter(|limit| !invalid && *limit > 0),
            adjustment: (effective != requested).then_some(ModelContextAdjustment::SafetyLimit),
        }
    }

    pub fn max_auto_compact_override(&self) -> Option<u64> {
        self.base
            .max_context_window
            .or(self.base.context_window)
            .map(ninety_percent)
    }

    /// A manually entered model starts with unknown capacities.
    pub fn compatible(model_id: &str) -> Self {
        Self {
            observation: None,
            base: super::CodexModel {
                slug: model_id.to_owned(),
                ..Default::default()
            },
            extra: Default::default(),
        }
    }

    /// 返回名为 "effort" 的参数声明，若模型未声明则返回 None。
    pub fn effort_parameter(&self) -> Option<ModelParameter> {
        let levels = self.base.supported_reasoning_levels.as_ref()?;
        if levels.is_empty() {
            return None;
        }
        let path = match self.extra.binding.transport.protocol {
            WireApi::Responses => "reasoning.effort",
            WireApi::ChatCompletions => "reasoning_effort",
            WireApi::GeminiGenerateContent => "generationConfig.thinkingConfig.thinkingLevel",
        };
        let candidates: Vec<_> = levels.iter().map(|level| level.effort.clone()).collect();
        let wire = candidates
            .iter()
            .map(|id| {
                let rule = self.extra.effort_wire.get(id).cloned().unwrap_or_else(|| {
                    super::ParameterWire {
                        set: vec![super::WireAssignment {
                            path: path.into(),
                            value: Value::String(id.clone()),
                        }],
                        remove: Vec::new(),
                    }
                });
                (id.clone(), rule)
            })
            .collect();
        Some(ModelParameter {
            name: "effort".into(),
            label: self.extra.effort_label.clone(),
            default: self.base.default_reasoning_level.clone(),
            candidates,
            wire,
            candidate_display_names: Default::default(),
        })
    }

    pub fn parameters(&self) -> impl Iterator<Item = ModelParameter> + '_ {
        self.effort_parameter()
            .into_iter()
            .chain(self.extra.parameters.iter().cloned())
    }

    /// Split a protocol parameter projection back into Codex reasoning metadata and wire bindings.
    pub fn set_parameters(&mut self, parameters: Vec<ModelParameter>) {
        let old = self.base.supported_reasoning_levels.take();
        self.base.default_reasoning_level = None;
        self.extra.effort_wire.clear();
        self.extra.effort_label = None;
        self.extra.parameters.clear();
        for parameter in parameters {
            if parameter.name != "effort" {
                self.extra.parameters.push(parameter);
                continue;
            }
            self.base.default_reasoning_level = parameter.default;
            self.extra.effort_label = parameter.label;
            self.base.supported_reasoning_levels = Some(
                parameter
                    .candidates
                    .into_iter()
                    .map(|effort| {
                        old.as_ref()
                            .and_then(|levels| levels.iter().find(|level| level.effort == effort))
                            .cloned()
                            .unwrap_or_else(|| super::ReasoningLevel {
                                effort,
                                ..Default::default()
                            })
                    })
                    .collect(),
            );
            let standard = self.effort_parameter().map(|p| p.wire).unwrap_or_default();
            self.extra.effort_wire = parameter
                .wire
                .into_iter()
                .filter(|(candidate, rule)| standard.get(candidate) != Some(rule))
                .collect();
        }
    }

    /// 返回 effort 参数的候选值字符串列表（GUI 下拉渲染用）。
    /// 若模型未声明 effort 参数，返回空 Vec。
    pub fn supported_efforts(&self) -> Vec<String> {
        self.effort_parameter()
            .map(|parameter| parameter.candidates.clone())
            .unwrap_or_default()
    }

    /// 返回模型声明的默认 effort；未声明默认时使用候选首项。
    pub fn default_effort(&self) -> Option<String> {
        self.effort_parameter()
            .and_then(|parameter| parameter.default_candidate(None))
    }
}

fn has_duplicates<T: PartialEq>(values: &[T]) -> bool {
    values
        .iter()
        .enumerate()
        .any(|(index, value)| values[..index].contains(value))
}

fn ninety_percent(tokens: u64) -> u64 {
    (u128::from(tokens) * 9 / 10) as u64
}
