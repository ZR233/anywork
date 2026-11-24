use pl_model_wire::completion::{CompletionRequest, ToolFormat};
use pl_model_wire::model::info::ModelDefinition;
use serde::Serialize;
use serde_json::{Map, Value};

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(super) enum ToolFormatBody {
    Text,
    Grammar { syntax: String, definition: String },
}

impl From<&ToolFormat> for ToolFormatBody {
    fn from(format: &ToolFormat) -> Self {
        match format {
            ToolFormat::Text => Self::Text,
            ToolFormat::Grammar { syntax, definition } => Self::Grammar {
                syntax: syntax.clone(),
                definition: definition.clone(),
            },
        }
    }
}

/// 注入 base body 后应用 parameter wire 与 service_tier，完成 OpenAI 请求体动态字段组装。
pub(super) fn finalize_body(
    body: &mut Map<String, Value>,
    model: &ModelDefinition,
    request: &CompletionRequest,
) {
    pl_model_wire::completion::request_support::finalize_body(body, model, &request.reasoning);
    if let Some(tier) = &request.service_tier {
        body.insert("service_tier".into(), Value::String(tier.clone()));
    }
}
