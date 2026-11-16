use pl_protocol::Result;
use serde::Serialize;
use serde_json::{Map, Value};

use crate::completion::{CompletionRequest, ReasoningConfig, ReasoningSummary};
use crate::model::info::ModelInfo;
use crate::model::{ModelProtocolOptions, ParameterWire, ResponsesMaxTokensField};
use crate::protocol::ProtocolKind;
use pl_protocol::ToolFormat;

use super::protocol_error;
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

/// 把强类型请求序列化为 JSON 对象 Map，供 base body 与 parameter wire 注入。
pub(super) fn to_object_map<T: Serialize>(value: &T) -> Result<Map<String, Value>> {
    let serialized = serde_json::to_value(value)?;
    match serialized {
        Value::Object(map) => Ok(map),
        _ => Err(protocol_error(
            "typed request body must serialize to a JSON object",
        )),
    }
}

/// 注入 base body 后应用 parameter wire，完成请求体动态字段组装。
pub(super) fn finalize_body(
    body: &mut Map<String, Value>,
    model: &ModelInfo,
    request: &CompletionRequest,
    native_options: &Map<String, Value>,
    protocol: ProtocolKind,
    chatgpt: bool,
) -> Result<()> {
    if !request.frozen_options {
        merge_base_body(body, &model.binding.request.body);
        apply_parameters(body, model, &request.reasoning);
        merge_base_body(body, native_options);
        return Ok(());
    }

    validate_frozen_options(request, model)?;
    let mut protected = FROZEN_FIELDS
        .iter()
        .copied()
        .filter(|field| *field != "parallel_tool_calls" && !TOKEN_FIELDS.contains(field))
        .collect::<Vec<_>>();
    if !request.options_projection && recovery_touches_input(request, model, native_options) {
        protected.push(input_field(model));
    }
    let expected = values_at(body, &protected);
    let mut defaults = model.binding.request.body.clone();
    for key in OPTION_FIELDS {
        // Omit supplies no typed token field: a declared/native overlay may still supply
        // the real output-token limit. Validate that final value rather than discarding it.
        if !matches!(&model.binding.request.protocol,
            ModelProtocolOptions::Responses(options) if options.max_tokens_field == ResponsesMaxTokensField::Omit)
            || !TOKEN_FIELDS.contains(key)
        {
            defaults.remove(*key);
        }
    }
    // Reuse the declared wire's path semantics, including provider-specific effort fields.
    // Clear all candidate defaults, then write only the saved candidate; never resolve a new default.
    ParameterWire {
        set: Vec::new(),
        remove: effort_paths(model)
            .filter(|path| !protected_path(path, model))
            .map(str::to_owned)
            .collect(),
    }
    .apply_to(&mut defaults);
    for root in effort_paths(model).filter_map(|path| path.split('.').next()) {
        if protected_path(root, model) {
            continue;
        }
        if defaults
            .get(root)
            .is_some_and(|value| value.as_object().is_some_and(Map::is_empty))
        {
            defaults.remove(root);
        }
    }
    merge_base_body(body, &defaults);
    apply_parameters(body, model, &request.reasoning);
    // Native options cannot change the already encoded effort. Other frozen values are
    // compared against the typed baseline only after every overlay, including native options.
    let effort = effort_paths(model)
        .chain(["reasoning.effort", "reasoning_effort"])
        .filter(|path| !protected_path(path, model))
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let expected_effort = values_at(body, &effort);
    merge_base_body(body, native_options);
    if values_at(body, &protected) != expected || values_at(body, &effort) != expected_effort {
        return Err(protocol_error(
            "request overlays change confirmed input or saved recovery options",
        ));
    }
    let parallel = body
        .get("parallel_tool_calls")
        .and_then(Value::as_bool)
        .or_else(|| {
            (body.get("parallel_tool_calls").is_none()
                && protocol == ProtocolKind::OpenAi
                && !chatgpt)
                .then_some(true)
        });
    if request.tool_choice != "none"
        && !request.tools.is_empty()
        && parallel != Some(request.parallel_tool_calls)
    {
        return Err(protocol_error(
            "saved parallel_tool_calls cannot be represented by the final request",
        ));
    }
    validate_token_limit(body, model, request.max_tokens)?;
    validate_recovery_effects(body, model, protocol, chatgpt)?;
    Ok(())
}

const OPTION_FIELDS: &[&str] = &[
    "tools",
    "tool_choice",
    "parallel_tool_calls",
    "temperature",
    "max_tokens",
    "max_output_tokens",
    "max_completion_tokens",
    "reasoning",
    "reasoning_effort",
];
const FROZEN_FIELDS: &[&str] = &[
    "tools",
    "tool_choice",
    "parallel_tool_calls",
    "temperature",
    "max_tokens",
    "max_output_tokens",
    "max_completion_tokens",
    "reasoning.summary",
    "stream",
];
const TOKEN_FIELDS: &[&str] = &["max_tokens", "max_output_tokens", "max_completion_tokens"];

fn validate_token_limit(
    body: &Map<String, Value>,
    model: &ModelInfo,
    saved: Option<u64>,
) -> Result<()> {
    let field = match &model.binding.request.protocol {
        ModelProtocolOptions::Responses(options) => {
            super::responses_max_tokens_key(options.max_tokens_field)
                // With Omit, only the standard Responses output-token field has known semantics;
                // other vendor spellings require an explicit model profile mapping, not inference.
                .unwrap_or("max_output_tokens")
        }
        ModelProtocolOptions::ChatCompletions(options) => match options.max_tokens_field {
            crate::model::MaxTokensField::MaxTokens => "max_tokens",
            crate::model::MaxTokensField::MaxCompletionTokens => "max_completion_tokens",
        },
    };
    if TOKEN_FIELDS
        .iter()
        .any(|key| *key != field && body.contains_key(*key))
        || body.get(field).and_then(Value::as_u64) != saved
        || saved.is_none() && body.contains_key(field)
    {
        return Err(protocol_error(
            "final output-token limit is missing, changed or uses an unconfirmed/conflicting field",
        ));
    }
    Ok(())
}

fn input_field(model: &ModelInfo) -> &'static str {
    match model.binding.request.protocol {
        ModelProtocolOptions::Responses(_) => "input",
        ModelProtocolOptions::ChatCompletions(_) => "messages",
    }
}

fn protected_path(path: &str, model: &ModelInfo) -> bool {
    let root = path.split('.').next().unwrap_or(path);
    root == "model"
        || root == input_field(model)
        || matches!(
            root,
            "store"
                | "background"
                | "conversation"
                | "previous_response_id"
                | "prompt"
                | "instructions"
        )
        || FROZEN_FIELDS.contains(&root)
        || path == "reasoning.summary"
        || path.starts_with("reasoning.summary.")
}

fn value_at<'a>(body: &'a Map<String, Value>, path: &str) -> Option<&'a Value> {
    let mut parts = path.split('.');
    let mut value = body.get(parts.next()?)?;
    for part in parts {
        value = value.get(part)?;
    }
    Some(value)
}

fn values_at(body: &Map<String, Value>, paths: &[&str]) -> Vec<Option<Value>> {
    paths
        .iter()
        .map(|path| value_at(body, path).cloned())
        .collect()
}

pub(crate) fn recovery_touches_input(
    request: &CompletionRequest,
    model: &ModelInfo,
    native: &Map<String, Value>,
) -> bool {
    let field = input_field(model);
    model.binding.request.body.contains_key(field)
        || native.contains_key(field)
        || request
            .reasoning
            .as_ref()
            .and_then(|config| config.effort.as_deref())
            .and_then(|effort| model.effort_parameter()?.wire_for(effort))
            .is_some_and(|wire| {
                wire.set
                    .iter()
                    .map(|assignment| assignment.path.as_str())
                    .chain(wire.remove.iter().map(String::as_str))
                    .any(|path| path.split('.').next() == Some(field))
            })
}

fn effort_paths(model: &ModelInfo) -> impl Iterator<Item = &str> {
    model
        .parameters
        .iter()
        .filter(|parameter| parameter.name == "effort")
        .flat_map(|parameter| parameter.wire.values())
        .flat_map(|wire| {
            wire.set
                .iter()
                .map(|assignment| assignment.path.as_str())
                .chain(wire.remove.iter().map(String::as_str))
        })
}

fn validate_frozen_options(request: &CompletionRequest, model: &ModelInfo) -> Result<()> {
    match &model.binding.request.protocol {
        ModelProtocolOptions::Responses(_) => {}
        ModelProtocolOptions::ChatCompletions(_) => {
            if request.reasoning.as_ref().is_some_and(|config| {
                matches!(
                    config.summary,
                    Some(ReasoningSummary::Auto | ReasoningSummary::Enabled)
                )
            }) {
                return Err(protocol_error(
                    "saved reasoning summary cannot be represented by Chat Completions",
                ));
            }
            if request.tools.is_empty() && !matches!(request.tool_choice.as_str(), "auto" | "none")
            {
                return Err(protocol_error(
                    "saved tool_choice cannot be represented without Chat tools",
                ));
            }
        }
    }
    if let Some(effort) = request
        .reasoning
        .as_ref()
        .and_then(|config| config.effort.as_deref())
    {
        // ModelInfo::validate already proves that wire keys are exactly the candidates and
        // every wire is nonempty. Only the saved selection's presence remains request-specific.
        if model
            .effort_parameter()
            .and_then(|parameter| parameter.wire_for(effort))
            .is_none()
        {
            return Err(protocol_error(
                "saved reasoning effort has no supported parameter wire",
            ));
        }
    }
    Ok(())
}

fn validate_recovery_effects(
    body: &mut Map<String, Value>,
    model: &ModelInfo,
    protocol: ProtocolKind,
    chatgpt: bool,
) -> Result<()> {
    let responses = matches!(
        model.binding.request.protocol,
        ModelProtocolOptions::Responses(_)
    );
    if responses {
        for field in ["conversation", "previous_response_id", "prompt"] {
            if body.get(field).is_some_and(|value| !value.is_null()) {
                return Err(protocol_error(
                    "recovery cannot add server-managed history or prompt references",
                ));
            }
        }
        if effective_bool(body.get("background"), false)? {
            return Err(protocol_error(
                "recovery cannot introduce a retained background response",
            ));
        }
    }
    // The public OpenAI Chat API explicitly supports store=false. For other Chat providers an
    // omitted setting is not proof of either behavior, so preserve their ordinary request rather
    // than require a provider-specific field that may not exist.
    if !responses
        && protocol == ProtocolKind::OpenAi
        && !chatgpt
        && body.get("store").is_none_or(Value::is_null)
    {
        body.insert("store".into(), Value::Bool(false));
    }
    let store = body.get("store");
    if (responses && store != Some(&Value::Bool(false)))
        || (!responses && !matches!(store, None | Some(Value::Null | Value::Bool(false))))
    {
        return Err(protocol_error(
            "recovery cannot introduce an explicit server storage request",
        ));
    }
    Ok(())
}

fn effective_bool(value: Option<&Value>, default: bool) -> Result<bool> {
    match value {
        None | Some(Value::Null) => Ok(default),
        Some(Value::Bool(value)) => Ok(*value),
        Some(_) => Err(protocol_error(
            "request behavior flag must be a boolean or null",
        )),
    }
}

/// 深合并 base body 到请求体：对象字段递归合并，其余字段覆盖。
pub(super) fn merge_base_body(target: &mut Map<String, Value>, source: &Map<String, Value>) {
    for (key, value) in source {
        match (target.get_mut(key), value) {
            (Some(Value::Object(target_inner)), Value::Object(source_inner)) => {
                merge_base_body(target_inner, source_inner);
            }
            _ => {
                target.insert(key.clone(), value.clone());
            }
        }
    }
}

/// 遍历模型声明的可调参数，对用户选中的值应用 wire 写入请求体。
fn apply_parameters(
    body: &mut Map<String, Value>,
    model: &ModelInfo,
    reasoning: &Option<ReasoningConfig>,
) {
    for parameter in &model.parameters {
        let selected = if parameter.name == "effort" {
            reasoning
                .as_ref()
                .and_then(|config| config.effort.as_deref())
        } else {
            None
        };
        if let Some(value) = selected
            && let Some(wire) = parameter.wire_for(value)
        {
            wire.apply_to(body);
        }
    }
}
