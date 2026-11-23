//! 模型家族预设，封装同 provider 模型共享的元数据。
//!
//! 参见 design/06-model.md 6.9 节。同 provider 的模型共享 capabilities、
//! truncation_policy、effort 参数声明和 base body。具体模型实例通过差异字段
//! （model_id、display_name、context_window 等）从 family 派生，避免在
//! `default_models` 中为每个模型重复构造完整 `ModelDefinition`。

use crate::model::capabilities::ModelCapabilities;
use crate::model::info::{ModelDefinition, ModelRequestProfile, ModelTransportProfile};
use crate::model::parameter::ModelParameter;
use crate::model::pricing::ModelPricing;
/// 同一 provider 内共享元数据的模型家族预设。
///
/// 封装同 provider 模型共享的 capabilities、truncation_policy、parameters、
/// request_profile 等。具体模型实例通过 [`instantiate`](Self::instantiate)
/// 用差异字段派生。
#[derive(Debug, Clone)]
pub struct ModelFamily {
    pub capabilities: ModelCapabilities,
    pub base: super::CodexModel,
    /// 共享的可调参数声明（如 effort）。
    pub parameters: Vec<ModelParameter>,
    pub transport: ModelTransportProfile,
    /// 共享的请求 profile（含 base body，如 DeepSeek 的 `thinking.type = enabled`）。
    pub request_profile: ModelRequestProfile,
}

/// 家族内单个具体模型的差异字段，[`ModelFamily::instantiate`] 的输入。
#[derive(Debug, Clone)]
pub struct ModelInstanceSpec {
    pub model_id: &'static str,
    pub display_name: &'static str,
    pub description: &'static str,
    pub context_window: u64,
    pub max_context_window: u64,
    pub max_output_tokens: Option<u64>,
    pub pricing: ModelPricing,
}

impl ModelFamily {
    /// Add document input supported by this Responses endpoint. Codex's text/image
    /// modalities describe the model, while this profile describes its file service.
    pub fn with_responses_files(
        mut self,
        media_types: &[&str],
        order: super::MediaSendOrder,
    ) -> Self {
        let mut file = super::ModelInputCapability::media(
            super::ModelModality::File,
            vec![
                super::ModelInputSource::Local,
                super::ModelInputSource::RemoteUrl,
            ],
        );
        file.limits.media_types = media_types.iter().copied().map(str::to_owned).collect();
        self.capabilities.input.push(file);
        self.request_profile.media.push(super::media_profile(
            super::ModelModality::File,
            super::MediaWireFormat::ResponsesInputFile,
            order,
        ));
        self
    }

    /// 用差异字段实例化一个具体 `ModelDefinition`。
    pub fn instantiate(&self, spec: ModelInstanceSpec) -> ModelDefinition {
        let ModelInstanceSpec {
            model_id,
            display_name,
            description,
            context_window,
            max_context_window,
            max_output_tokens,
            pricing,
        } = spec;
        let mut model = ModelDefinition {
            observation: None,
            base: crate::model::CodexModel {
                slug: model_id.to_string(),
                display_name: display_name.to_string(),
                description: Some(description.to_string()),
                context_window: Some(context_window),
                max_context_window: Some(max_context_window),
                ..self.base.clone()
            },
            extra: crate::model::ModelExtras {
                default_temperature: None,
                max_output_tokens,
                pricing,
                parameters: Vec::new(),
                effort_label: None,
                effort_wire: Default::default(),
                binding: super::info::ModelBinding {
                    transport: self.transport.clone(),
                    request: self.request_profile.clone(),
                },
                capabilities: self.capabilities.clone(),
            },
        };
        model.set_parameters(self.parameters.clone());
        model
    }
}
