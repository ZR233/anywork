use crate::completion::{
    AttachmentModality, ContentPart, MessageContent, MessageRole, ResponsesContextItem,
    ToolCallCaller, ToolCallKind, ToolCallRecord, ToolCallerMode, ToolSpec,
};
use pl_protocol::Result;
use serde::Serialize;
use serde_json::{Value, json};

use crate::completion::{CompletionRequest, ReasoningConfig, ReasoningSummary};
use crate::model::info::MediaWireFormat;
use crate::protocol::InstructionWireRole;

use super::body::ToolFormatBody;
use super::protocol_error;
use pl_model_wire::completion::request_support::{
    MediaRepresentationPlan, media_file_id, media_url, message_content_text, record_arguments_text,
    record_custom_input, tool_callers_by_result_position, tool_media_content,
};
use pl_model_wire::completion::tool_schema::{
    HOSTED_OUTPUT_SCHEMA_DIALECT, HostedOutputSchemaResources,
};

const DATA_UNAVAILABLE: &str = "tool_data_unavailable";

fn hosted_result_schema<'a>(
    name: &str,
    allowed_callers: &[ToolCallerMode],
    schema: Option<&'a Value>,
    resources: &mut HostedOutputSchemaResources<'a>,
) -> Result<Option<Value>> {
    if !allowed_callers.contains(&ToolCallerMode::Programmatic) {
        return Ok(None);
    }
    let schema = schema.and_then(Value::as_object).ok_or_else(|| {
        protocol_error(format!(
            "programmatic tool {name} requires a declared output schema document"
        ))
    })?;
    let data_schema = resources
        .embed(name, schema)
        .map_err(|error| protocol_error(format!("tool {name}: {error}")))?;
    Ok(Some(json!({
        "$schema": HOSTED_OUTPUT_SCHEMA_DIALECT,
        "type": "object",
        "properties": {
            "data": data_schema,
            "error": {
                "type": "object",
                "description": "The invocation or its history did not provide a program value.",
                "properties": {
                    "code": {"type": "string", "enum": [DATA_UNAVAILABLE]},
                    "message": {"type": "string"}
                },
                "required": ["code", "message"],
                "additionalProperties": false
            }
        },
        "oneOf": [{"required": ["data"]}, {"required": ["error"]}],
        "additionalProperties": false
    })))
}

fn hosted_result(data: Option<&Value>, content: &MessageContent) -> String {
    match data {
        Some(data) => json!({"data": data}),
        None => json!({"error": {
            "code": DATA_UNAVAILABLE,
            "message": message_content_text(content)
        }}),
    }
    .to_string()
}

/// 回放 provider 原生 Responses 上下文项时的输入投影。
///
/// 原生上下文类别（reasoning、web_search_call、program 等）的输出项携带 `status` 等仅用于
/// output 生命周期的字段；严格兼容的 Responses 网关会把它当未知输入参数拒绝
/// （`unknown_parameter: input[*].status`）。回放这类 item 时去掉 `status`，保留 `id`、
/// `encrypted_content`、`action`、`results` 与所有未知厂商字段。message、function_call 等
/// 由 typed 路径重建的 item 不属于原生上下文类别，保持既有回放语义。
fn replay_native_item(value: serde_json::Value) -> serde_json::Value {
    if ResponsesContextItem::from_wire(value.clone()).is_none() {
        return value;
    }
    let mut value = value;
    if let Some(object) = value.as_object_mut() {
        object.remove("status");
    }
    value
}

#[derive(Debug, Clone, Serialize)]
pub(super) struct ResponsesRequestBody {
    model: String,
    input: Vec<ResponsesInputItem>,
    stream: bool,
    tool_choice: String,
    parallel_tool_calls: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    tools: Option<Vec<ResponsesTool>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    store: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt_cache_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    reasoning: Option<ResponsesReasoning>,
}

impl ResponsesRequestBody {
    pub(super) fn from_request(
        request: &CompletionRequest,
        model: &crate::model::ModelDefinition,
        prompt_cache_key: Option<&str>,
        instruction_role: InstructionWireRole,
        chatgpt: bool,
    ) -> Result<Self> {
        let mut input = Vec::new();
        if let Some(system_prompt) = &request.system_prompt
            && !system_prompt.content().is_empty()
        {
            input.push(ResponsesInputItem::message(
                responses_role(MessageRole::System, instruction_role),
                vec![ResponsesContent::InputText {
                    text: system_prompt.content().to_owned(),
                }],
            ));
        }
        if chatgpt
            && request
                .tools
                .iter()
                .any(|tool| matches!(tool, ToolSpec::Function { .. } | ToolSpec::Custom { .. }))
        {
            input.push(ResponsesInputItem::typed(
                ResponsesTypedInputItem::AdditionalTools {
                    role: ResponsesRole::Developer,
                    tools: ResponsesTool::project_all(request.tools.iter().filter(|tool| {
                        matches!(tool, ToolSpec::Function { .. } | ToolSpec::Custom { .. })
                    }))?,
                },
            ));
        }
        let media_plan = MediaRepresentationPlan::for_request(request, model)?;
        let tool_callers = tool_callers_by_result_position(&request.input);

        let mut replay_end = 0;
        let mut replay_spans = request.replay_spans.iter().peekable();
        for (position, item) in request.input.iter().enumerate() {
            if position < replay_end {
                continue;
            }
            if replay_spans
                .peek()
                .is_some_and(|span| span.start == position)
            {
                let span = replay_spans
                    .next()
                    .ok_or_else(|| protocol_error("replay span disappeared"))?;
                for value in span.output.iter().cloned() {
                    input.push(ResponsesInputItem::replay(value, chatgpt)?);
                }
                replay_end = span.start + span.semantic.len();
                continue;
            }
            if let crate::completion::ModelContextItem::ToolMedia { items } = item {
                let content = tool_media_content(items);
                input.push(ResponsesInputItem::message(
                    ResponsesRole::User,
                    responses_content_for_message(
                        &content,
                        MessageRole::User,
                        &request.prepared_content,
                        &media_plan,
                    )?,
                ));
                continue;
            }
            let msg = match item {
                crate::completion::ModelContextItem::Message { message }
                | crate::completion::ModelContextItem::ToolResult { message, .. } => message,
                crate::completion::ModelContextItem::Compaction { encrypted_content } => {
                    input.push(ResponsesInputItem::typed(
                        ResponsesTypedInputItem::Compaction {
                            encrypted_content: encrypted_content.clone(),
                        },
                    ));
                    continue;
                }
                crate::completion::ModelContextItem::Native { payload } => {
                    let item = crate::completion::ResponsesContextItem::from_payload(payload)?;
                    input.push(ResponsesInputItem::replay(item.value, chatgpt)?);
                    continue;
                }
                crate::completion::ModelContextItem::ToolMedia { .. } => unreachable!(),
            };
            match msg.role {
                MessageRole::Assistant if msg.tool_calls.is_some() => {
                    let text = message_content_text(&msg.content);
                    if !text.is_empty() {
                        input.push(ResponsesInputItem::message(
                            ResponsesRole::Assistant,
                            vec![ResponsesContent::OutputText { text }],
                        ));
                    }
                    if let Some(tool_calls) = msg.tool_calls.as_ref() {
                        input.extend(tool_calls.iter().map(ResponsesInputItem::from));
                    }
                }
                MessageRole::Tool => {
                    let record = msg.tool_result.as_ref().ok_or_else(|| {
                        protocol_error("tool result message missing typed tool_result record")
                    })?;
                    let caller = tool_callers.get(&position).cloned();
                    let output = match &caller {
                        Some(ToolCallCaller::Program { .. }) => {
                            if msg
                                .content
                                .parts
                                .iter()
                                .any(|part| matches!(part, ContentPart::Attachment { .. }))
                            {
                                return Err(protocol_error(
                                    "programmatic tool result media requires separate tool media context",
                                ));
                            }
                            ResponsesToolOutput::Text(hosted_result(
                                record.data.as_ref(),
                                &msg.content,
                            ))
                        }
                        // Schema declarations constrain string outputs. Content arrays preserve the
                        // author's ordinary result even when its declaration changes on replay.
                        None => ResponsesToolOutput::Content(responses_content_for_message(
                            &msg.content,
                            MessageRole::Tool,
                            &request.prepared_content,
                            &media_plan,
                        )?),
                    };
                    match record.kind {
                        ToolCallKind::Function => {
                            input.push(ResponsesInputItem::typed(
                                ResponsesTypedInputItem::FunctionCallOutput {
                                    call_id: record.call_id.clone(),
                                    output,
                                    caller,
                                },
                            ));
                        }
                        ToolCallKind::Custom => {
                            input.push(ResponsesInputItem::typed(
                                ResponsesTypedInputItem::CustomToolCallOutput {
                                    call_id: record.call_id.clone(),
                                    output,
                                    caller,
                                },
                            ));
                        }
                    }
                }
                MessageRole::System | MessageRole::User | MessageRole::Assistant => {
                    input.push(ResponsesInputItem::message(
                        responses_role(msg.role, instruction_role),
                        responses_content_for_message(
                            &msg.content,
                            msg.role,
                            &request.prepared_content,
                            &media_plan,
                        )?,
                    ));
                }
            }
        }

        let tools = ResponsesTool::project_all(
            request
                .tools
                .iter()
                .filter(|tool| !chatgpt || matches!(tool, ToolSpec::WebSearch { .. })),
        )?;
        let tools = (!tools.is_empty()).then_some(tools);

        Ok(Self {
            model: model
                .extra
                .binding
                .request
                .api_model
                .clone()
                .unwrap_or_else(|| model.base.slug.clone()),
            input,
            stream: true,
            tool_choice: request.tool_choice.clone(),
            parallel_tool_calls: request.parallel_tool_calls,
            tools,
            temperature: request.temperature,
            store: false,
            prompt_cache_key: prompt_cache_key.map(ToString::to_string),
            reasoning: request.reasoning.as_ref().map(ResponsesReasoning::from),
        })
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
enum ResponsesInputItem {
    Typed(ResponsesTypedInputItem),
    Native(serde_json::Value),
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ResponsesTypedInputItem {
    AdditionalTools {
        role: ResponsesRole,
        tools: Vec<ResponsesTool>,
    },
    Message {
        role: ResponsesRole,
        content: Vec<ResponsesContent>,
    },
    FunctionCall {
        #[serde(skip_serializing_if = "Option::is_none")]
        id: Option<String>,
        name: String,
        arguments: String,
        call_id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        caller: Option<crate::completion::ToolCallCaller>,
    },
    FunctionCallOutput {
        call_id: String,
        output: ResponsesToolOutput,
        #[serde(skip_serializing_if = "Option::is_none")]
        caller: Option<crate::completion::ToolCallCaller>,
    },
    CustomToolCall {
        #[serde(skip_serializing_if = "Option::is_none")]
        id: Option<String>,
        name: String,
        input: String,
        call_id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        caller: Option<crate::completion::ToolCallCaller>,
    },
    CustomToolCallOutput {
        call_id: String,
        output: ResponsesToolOutput,
        #[serde(skip_serializing_if = "Option::is_none")]
        caller: Option<crate::completion::ToolCallCaller>,
    },
    Compaction {
        encrypted_content: String,
    },
}

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
enum ResponsesToolOutput {
    Text(String),
    Content(Vec<ResponsesContent>),
}

impl ResponsesInputItem {
    fn typed(item: ResponsesTypedInputItem) -> Self {
        Self::Typed(item)
    }

    fn replay(value: serde_json::Value, chatgpt: bool) -> Result<Self> {
        if chatgpt {
            super::chatgpt::validate_history_item(&value)?;
            Ok(Self::Native(value))
        } else {
            Ok(Self::Native(replay_native_item(value)))
        }
    }

    fn message(role: ResponsesRole, content: Vec<ResponsesContent>) -> Self {
        Self::typed(ResponsesTypedInputItem::Message { role, content })
    }
}

impl From<&ToolCallRecord> for ResponsesInputItem {
    fn from(record: &ToolCallRecord) -> Self {
        let caller = record.caller.clone();
        match record.kind {
            ToolCallKind::Function => Self::typed(ResponsesTypedInputItem::FunctionCall {
                id: None,
                name: record.name.clone(),
                arguments: record_arguments_text(&record.arguments),
                call_id: record.call_id.clone(),
                caller,
            }),
            ToolCallKind::Custom => Self::typed(ResponsesTypedInputItem::CustomToolCall {
                id: None,
                name: record.name.clone(),
                input: record_custom_input(&record.arguments),
                call_id: record.call_id.clone(),
                caller,
            }),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "lowercase")]
enum ResponsesRole {
    Developer,
    System,
    User,
    Assistant,
    Tool,
}

fn responses_role(role: MessageRole, instruction_role: InstructionWireRole) -> ResponsesRole {
    match role {
        MessageRole::System => match instruction_role {
            InstructionWireRole::Developer => ResponsesRole::Developer,
            InstructionWireRole::System => ResponsesRole::System,
        },
        MessageRole::User => ResponsesRole::User,
        MessageRole::Assistant => ResponsesRole::Assistant,
        MessageRole::Tool => ResponsesRole::Tool,
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ResponsesContent {
    InputText {
        text: String,
    },
    InputImage {
        #[serde(skip_serializing_if = "Option::is_none")]
        detail: Option<&'static str>,
        #[serde(flatten)]
        source: ImageReference,
    },
    InputFile {
        #[serde(flatten)]
        source: FileReference,
    },
    OutputText {
        text: String,
    },
}

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
enum ImageReference {
    Url { image_url: String },
    File { file_id: String },
}

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
enum FileReference {
    Data { filename: String, file_data: String },
    Url { file_url: String },
    File { file_id: String },
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ResponsesTool {
    Function {
        name: String,
        description: String,
        parameters: serde_json::Value,
        strict: bool,
        #[serde(skip_serializing_if = "Vec::is_empty")]
        allowed_callers: Vec<crate::completion::ToolCallerMode>,
        #[serde(skip_serializing_if = "Option::is_none")]
        output_schema: Option<serde_json::Value>,
    },
    Custom {
        name: String,
        description: String,
        format: ToolFormatBody,
        #[serde(skip_serializing_if = "Vec::is_empty")]
        allowed_callers: Vec<crate::completion::ToolCallerMode>,
        #[serde(skip_serializing_if = "Option::is_none")]
        output_schema: Option<serde_json::Value>,
    },
    ProgrammaticToolCalling,
    #[serde(rename = "web_search")]
    BareWebSearch,
    WebSearch {
        external_web_access: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        indexed_web_access: Option<bool>,
        #[serde(skip_serializing_if = "Option::is_none")]
        filters: Option<crate::completion::WebSearchFilters>,
        #[serde(skip_serializing_if = "Option::is_none")]
        user_location: Option<crate::completion::WebSearchUserLocation>,
        #[serde(skip_serializing_if = "Option::is_none")]
        search_context_size: Option<crate::completion::WebSearchContextSize>,
        #[serde(skip_serializing_if = "Option::is_none")]
        search_content_types: Option<Vec<String>>,
    },
}

impl ResponsesTool {
    fn project_all<'a>(tools: impl Iterator<Item = &'a ToolSpec>) -> Result<Vec<Self>> {
        let mut resources = HostedOutputSchemaResources::default();
        tools
            .map(|tool| Self::project(tool, &mut resources))
            .collect()
    }

    fn project<'a>(
        tool: &'a ToolSpec,
        resources: &mut HostedOutputSchemaResources<'a>,
    ) -> Result<Self> {
        Ok(match tool {
            ToolSpec::Function {
                name,
                description,
                input_schema,
                allowed_callers,
                output_schema,
            } => Self::Function {
                name: name.clone(),
                description: description.clone(),
                parameters: input_schema.clone(),
                // Preserve optional and role-specific arguments; Responses otherwise
                // attempts strict normalization, which can make these schemas unsatisfiable.
                strict: false,
                allowed_callers: allowed_callers.clone(),
                output_schema: hosted_result_schema(
                    name,
                    allowed_callers,
                    output_schema.as_ref(),
                    resources,
                )?,
            },
            ToolSpec::Custom {
                name,
                description,
                format,
                allowed_callers,
                output_schema,
            } => Self::Custom {
                name: name.clone(),
                description: description.clone(),
                format: ToolFormatBody::from(format),
                allowed_callers: allowed_callers.clone(),
                output_schema: hosted_result_schema(
                    name,
                    allowed_callers,
                    output_schema.as_ref(),
                    resources,
                )?,
            },
            ToolSpec::ProgrammaticToolCalling => Self::ProgrammaticToolCalling,
            ToolSpec::WebSearch { options } => match options {
                crate::completion::HostedWebSearchOptions::Bare => Self::BareWebSearch,
                crate::completion::HostedWebSearchOptions::OpenAi {
                    external_web_access,
                    indexed_web_access,
                    filters,
                    user_location,
                    search_context_size,
                    search_content_types,
                } => Self::WebSearch {
                    external_web_access: *external_web_access,
                    indexed_web_access: *indexed_web_access,
                    filters: filters.clone(),
                    user_location: user_location.clone(),
                    search_context_size: *search_context_size,
                    search_content_types: search_content_types.clone(),
                },
            },
        })
    }
}

#[derive(Debug, Clone, Serialize)]
struct ResponsesReasoning {
    #[serde(skip_serializing_if = "Option::is_none")]
    summary: Option<ResponsesReasoningSummary>,
}

impl From<&ReasoningConfig> for ResponsesReasoning {
    fn from(reasoning: &ReasoningConfig) -> Self {
        Self {
            summary: reasoning
                .summary
                .and_then(ResponsesReasoningSummary::from_summary),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "lowercase")]
enum ResponsesReasoningSummary {
    Auto,
}

impl ResponsesReasoningSummary {
    fn from_summary(summary: ReasoningSummary) -> Option<Self> {
        match summary {
            ReasoningSummary::Auto | ReasoningSummary::Enabled => Some(Self::Auto),
            ReasoningSummary::Disabled => None,
        }
    }
}

fn responses_content_for_message(
    content: &MessageContent,
    role: MessageRole,
    prepared_content: &[crate::completion::ResolvedAttachment],
    media_plan: &MediaRepresentationPlan,
) -> Result<Vec<ResponsesContent>> {
    let mut response_content = Vec::new();
    for part in &content.parts {
        match part {
            ContentPart::Text { text } => {
                if role == MessageRole::Assistant {
                    response_content.push(ResponsesContent::OutputText { text: text.clone() });
                } else {
                    response_content.push(ResponsesContent::InputText { text: text.clone() });
                }
            }
            ContentPart::Attachment {
                attachment_id,
                modality,
                media_type,
                filename,
            } => match modality {
                AttachmentModality::Image => {
                    if media_plan.wire(*modality)? != MediaWireFormat::ResponsesInputImage {
                        return Err(protocol_error(
                            "Chat media wire cannot be serialized by Responses",
                        ));
                    }
                    let source = if let Some(file_id) =
                        media_file_id(attachment_id, prepared_content, media_plan)
                    {
                        ImageReference::File {
                            file_id: file_id.to_owned(),
                        }
                    } else {
                        ImageReference::Url {
                            image_url: media_url(
                                attachment_id,
                                media_type,
                                *modality,
                                prepared_content,
                                media_plan,
                            )?,
                        }
                    };
                    response_content.push(ResponsesContent::InputImage {
                        detail: (role == MessageRole::Tool).then_some("auto"),
                        source,
                    });
                }
                AttachmentModality::File => {
                    if media_plan.wire(*modality)? != MediaWireFormat::ResponsesInputFile {
                        return Err(protocol_error(
                            "Chat file wire cannot be serialized by Responses",
                        ));
                    }
                    let source = if let Some(file_id) =
                        media_file_id(attachment_id, prepared_content, media_plan)
                    {
                        FileReference::File {
                            file_id: file_id.to_owned(),
                        }
                    } else {
                        let value = media_url(
                            attachment_id,
                            media_type,
                            *modality,
                            prepared_content,
                            media_plan,
                        )?;
                        if value.starts_with("data:") {
                            let fallback = match media_type.as_str() {
                                "application/pdf" => "attachment.pdf",
                                "text/plain" => "attachment.txt",
                                _ => "attachment",
                            };
                            FileReference::Data {
                                filename: filename.clone().unwrap_or_else(|| fallback.into()),
                                file_data: value,
                            }
                        } else {
                            FileReference::Url { file_url: value }
                        }
                    };
                    response_content.push(ResponsesContent::InputFile { source });
                }
                AttachmentModality::Video => {
                    return Err(protocol_error(format!(
                        "Responses does not support {:?} attachments",
                        modality
                    )));
                }
            },
        }
    }
    Ok(response_content)
}
