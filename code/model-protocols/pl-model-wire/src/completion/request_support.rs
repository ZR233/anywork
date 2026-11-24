//! Shared request validation, media planning, body merging and tool-history helpers
//! reused across wire codecs.

use std::collections::{BTreeMap, HashMap, VecDeque};

use pl_protocol::{PureError, Result};
use serde::Serialize;
use serde_json::{Map, Value};

use crate::completion::{
    AttachmentModality, AttachmentRepresentation, CompletionRequest, ContentPart, Message,
    MessageContent, MessageRole, ModelContextItem, ReasoningConfig, ResolvedAttachment,
    ToolCallCaller, ToolCallKind, ToolMediaContext,
};
use crate::model::info::{MediaMixPolicy, MediaRepresentation, MediaWireFormat, ModelDefinition};

fn protocol_error(message: impl Into<String>) -> PureError {
    PureError::LlmError(format!("request protocol error: {}", message.into()))
}

pub fn sent_model_from_wire_body(body: &Map<String, Value>) -> Result<String> {
    match body.get("model") {
        Some(Value::String(model)) if !model.trim().is_empty() => Ok(model.clone()),
        Some(Value::String(_)) => Err(protocol_error("final request body model must not be blank")),
        Some(_) => Err(protocol_error("final request body model must be a string")),
        None => Err(protocol_error("final request body model is required")),
    }
}

pub fn messages_after_last_compaction(input: &[ModelContextItem]) -> Vec<Message> {
    let start = input
        .iter()
        .rposition(ModelContextItem::is_compaction)
        .map_or(0, |index| index + 1);
    input[start..]
        .iter()
        .filter_map(ModelContextItem::as_message)
        .cloned()
        .collect()
}

pub fn to_object_map<T: Serialize>(value: &T) -> Result<Map<String, Value>> {
    let serialized = serde_json::to_value(value)?;
    match serialized {
        Value::Object(map) => Ok(map),
        _ => Err(protocol_error(
            "typed request body must serialize to a JSON object",
        )),
    }
}

pub fn finalize_body(
    body: &mut Map<String, Value>,
    model: &ModelDefinition,
    reasoning: &Option<ReasoningConfig>,
) {
    merge_base_body(body, &model.extra.binding.request.body);
    apply_parameters(body, model, reasoning);
}

pub fn merge_base_body(target: &mut Map<String, Value>, source: &Map<String, Value>) {
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

pub fn apply_parameters(
    body: &mut Map<String, Value>,
    model: &ModelDefinition,
    reasoning: &Option<ReasoningConfig>,
) {
    for parameter in model.parameters() {
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

pub fn validate_tool_history(messages: &[Message]) -> Result<()> {
    let mut expected_outputs = VecDeque::new();

    for message in messages {
        match message.role {
            MessageRole::Assistant => {
                for tool_call in message.tool_calls.iter().flatten() {
                    expected_outputs.push_back(ExpectedToolOutput {
                        item_id: tool_call.item_id.clone(),
                        call_id: tool_call.call_id.clone(),
                        kind: tool_call.kind,
                    });
                }
            }
            MessageRole::Tool => {
                let Some(tool_result) = message.tool_result.as_ref() else {
                    return Err(protocol_error(
                        "tool result message missing typed tool_result record",
                    ));
                };
                let Some(expected) = expected_outputs.pop_front() else {
                    return Err(protocol_error(
                        "tool result has no preceding assistant tool call",
                    ));
                };
                if tool_result.item_id != expected.item_id {
                    return Err(protocol_error(format!(
                        "tool result item_id {} does not match assistant tool call item_id {}",
                        tool_result.item_id, expected.item_id
                    )));
                }
                if tool_result.call_id != expected.call_id {
                    return Err(protocol_error(format!(
                        "tool result call_id {} does not match assistant tool call call_id {}",
                        tool_result.call_id, expected.call_id
                    )));
                }
                if tool_result.kind != expected.kind {
                    return Err(protocol_error(format!(
                        "tool result kind {} does not match assistant tool call kind {}",
                        tool_result.kind.as_str(),
                        expected.kind.as_str()
                    )));
                }
            }
            MessageRole::System | MessageRole::User => {}
        }
    }

    if let Some(expected) = expected_outputs.front() {
        return Err(protocol_error(format!(
            "assistant tool call {} is missing tool output",
            expected.item_id
        )));
    }

    Ok(())
}

pub fn tool_callers_by_result_position(
    items: &[ModelContextItem],
) -> BTreeMap<usize, ToolCallCaller> {
    let mut calls = VecDeque::new();
    let mut results = BTreeMap::new();
    for (position, item) in items.iter().enumerate() {
        let Some(message) = item.as_message() else {
            continue;
        };
        match message.role {
            MessageRole::Assistant => calls.extend(
                message
                    .tool_calls
                    .iter()
                    .flatten()
                    .map(|call| call.caller.clone()),
            ),
            MessageRole::Tool => {
                if let Some(Some(caller)) = calls.pop_front() {
                    results.insert(position, caller);
                }
            }
            MessageRole::System | MessageRole::User => {}
        }
    }
    results
}

pub fn record_arguments_text(arguments: &Value) -> String {
    match arguments {
        Value::String(raw) => raw.clone(),
        value => serde_json::to_string(value).unwrap_or_default(),
    }
}

pub fn record_custom_input(arguments: &Value) -> String {
    arguments.as_str().unwrap_or_default().to_string()
}

struct ExpectedToolOutput {
    item_id: String,
    call_id: String,
    kind: ToolCallKind,
}

pub fn message_content_text(content: &MessageContent) -> String {
    content.text_value()
}

#[derive(Debug, Default)]
pub struct MediaRepresentationPlan {
    representations: HashMap<AttachmentModality, MediaRepresentation>,
    wires: HashMap<AttachmentModality, MediaWireFormat>,
}

impl MediaRepresentationPlan {
    pub fn for_request(request: &CompletionRequest, model: &ModelDefinition) -> Result<Self> {
        let mut attachment_ids = HashMap::<AttachmentModality, Vec<String>>::new();
        let mut seen = HashMap::<String, AttachmentModality>::new();

        for item in &request.input {
            let tool_media;
            let content = match item {
                ModelContextItem::Message { message }
                | ModelContextItem::ToolResult { message, .. } => &message.content,
                ModelContextItem::ToolMedia { items } => {
                    tool_media = tool_media_content(items);
                    &tool_media
                }
                ModelContextItem::Compaction { .. } | ModelContextItem::Native { .. } => {
                    continue;
                }
            };
            for part in &content.parts {
                let ContentPart::Attachment {
                    attachment_id,
                    modality,
                    ..
                } = part
                else {
                    continue;
                };
                if let Some(existing) = seen.insert(attachment_id.clone(), *modality) {
                    if existing != *modality {
                        return Err(protocol_error(format!(
                            "model={} attachment modality conflict for attachment {attachment_id}",
                            model.base.slug
                        )));
                    }
                    continue;
                }
                attachment_ids
                    .entry(*modality)
                    .or_default()
                    .push(attachment_id.clone());
            }
        }

        if model.extra.binding.request.media_mix_policy == MediaMixPolicy::SingleModality
            && attachment_ids.len() > 1
        {
            return Err(protocol_error(format!(
                "model={} rejects mixed media modalities",
                model.base.slug
            )));
        }

        let mut representations = HashMap::new();
        let mut wires = HashMap::new();
        for (modality, ids) in attachment_ids {
            let media = ids
                .iter()
                .map(|attachment_id| prepared_content(request, attachment_id, modality, model))
                .collect::<Result<Vec<_>>>()?;
            let profile = model
                .extra
                .binding
                .request
                .media_profile(model_modality(modality))
                .ok_or_else(|| {
                    protocol_error(format!(
                        "model={} modality={} count={} has no media request profile",
                        model.base.slug,
                        modality_label(modality),
                        media.len()
                    ))
                })?;
            let candidates = if media
                .iter()
                .all(|item| item.sources.iter().all(is_snapshot_source))
            {
                &profile.replay
            } else {
                &profile.first_send
            };
            let representation = candidates
                .iter()
                .copied()
                .find(|candidate| {
                    media
                        .iter()
                        .all(|item| has_representation(item, *candidate))
                })
                .ok_or_else(|| {
                    protocol_error(format!(
                        "model={} modality={} count={} has no common media representation",
                        model.base.slug,
                        modality_label(modality),
                        media.len()
                    ))
                })?;
            tracing::info!(
                model = %model.base.slug,
                modality = modality_label(modality),
                representation = representation_label(representation),
                count = media.len(),
                "planned media request representation"
            );
            representations.insert(modality, representation);
            wires.insert(modality, profile.wire);
        }

        Ok(Self {
            representations,
            wires,
        })
    }

    pub fn representation(&self, modality: AttachmentModality) -> Result<MediaRepresentation> {
        self.representations.get(&modality).copied().ok_or_else(|| {
            protocol_error(format!(
                "modality={} was not planned before serialization",
                modality_label(modality)
            ))
        })
    }

    pub fn wire(&self, modality: AttachmentModality) -> Result<MediaWireFormat> {
        self.wires.get(&modality).copied().ok_or_else(|| {
            protocol_error(format!(
                "modality={} has no planned provider wire mapping",
                modality_label(modality)
            ))
        })
    }
}

pub fn media_file_id<'a>(
    id: &str,
    media: &'a [ResolvedAttachment],
    plan: &MediaRepresentationPlan,
) -> Option<&'a str> {
    let media = media.iter().find(|part| part.attachment_id == id)?;
    if plan.representation(media.modality).ok()? != MediaRepresentation::ProviderFile {
        return None;
    }
    media.sources.iter().find_map(|source| match source {
        AttachmentRepresentation::ProviderFile { file_id } => Some(file_id.as_str()),
        _ => None,
    })
}

pub fn tool_media_content(items: &[ToolMediaContext]) -> MessageContent {
    let mut parts = Vec::with_capacity(items.len().saturating_mul(2));
    for item in items {
        parts.push(ContentPart::Text {
            text: format!(
                "Image from view_image call {}: {}",
                item.call_id, item.label
            ),
        });
        parts.push(ContentPart::Attachment {
            attachment_id: item.attachment.id.clone(),
            modality: item.attachment.modality,
            media_type: item.attachment.media_type.clone(),
            filename: item.attachment.filename.clone(),
        });
    }
    MessageContent::new(parts)
}

pub fn media_url(
    attachment_id: &str,
    media_type: &str,
    modality: AttachmentModality,
    prepared_content: &[ResolvedAttachment],
    plan: &MediaRepresentationPlan,
) -> Result<String> {
    let media = find_prepared(attachment_id, modality, prepared_content)?;
    let representation = plan.representation(modality)?;
    let source = find_source(media, representation, attachment_id)?;
    match source {
        AttachmentRepresentation::DataUrl { base64 } => {
            let actual_media_type = if media_type.is_empty() {
                media.media_type.as_str()
            } else {
                media_type
            };
            Ok(format!("data:{actual_media_type};base64,{base64}"))
        }
        AttachmentRepresentation::RemoteUrl { url } => Ok(url.clone()),
        AttachmentRepresentation::ProviderFile { .. } => Err(protocol_error(
            "provider file cannot be serialized as a URL content part",
        )),
    }
}

pub fn media_inline_data(
    attachment_id: &str,
    media_type: &str,
    modality: AttachmentModality,
    prepared_content: &[ResolvedAttachment],
    plan: &MediaRepresentationPlan,
) -> Result<(String, String)> {
    let media = find_prepared(attachment_id, modality, prepared_content)?;
    let representation = plan.representation(modality)?;
    let source = find_source(media, representation, attachment_id)?;
    match source {
        AttachmentRepresentation::DataUrl { base64 } => {
            let actual_media_type = if media_type.is_empty() {
                media.media_type.as_str()
            } else {
                media_type
            };
            Ok((actual_media_type.to_owned(), base64.clone()))
        }
        AttachmentRepresentation::RemoteUrl { .. }
        | AttachmentRepresentation::ProviderFile { .. } => Err(protocol_error(
            "inline media requires DataUrl representation",
        )),
    }
}

fn find_prepared<'a>(
    attachment_id: &str,
    modality: AttachmentModality,
    prepared_content: &'a [ResolvedAttachment],
) -> Result<&'a ResolvedAttachment> {
    let media = prepared_content
        .iter()
        .find(|media| media.attachment_id == attachment_id)
        .ok_or_else(|| {
            protocol_error(format!(
                "attachment {attachment_id} was not prepared before model request"
            ))
        })?;
    if media.modality != modality {
        return Err(protocol_error(format!(
            "attachment {attachment_id} prepared modality does not match message content"
        )));
    }
    Ok(media)
}

fn find_source<'a>(
    media: &'a ResolvedAttachment,
    representation: MediaRepresentation,
    attachment_id: &str,
) -> Result<&'a AttachmentRepresentation> {
    media
        .sources
        .iter()
        .find(|source| source_matches(source, representation))
        .ok_or_else(|| {
            protocol_error(format!(
                "attachment {attachment_id} is missing its planned media representation"
            ))
        })
}

fn prepared_content<'a>(
    request: &'a CompletionRequest,
    attachment_id: &str,
    modality: AttachmentModality,
    model: &ModelDefinition,
) -> Result<&'a ResolvedAttachment> {
    let matching = request
        .prepared_content
        .iter()
        .filter(|media| media.attachment_id == attachment_id)
        .collect::<Vec<_>>();
    let [media] = matching.as_slice() else {
        return Err(protocol_error(format!(
            "model={} modality={} attachment {attachment_id} must have exactly one prepared payload",
            model.base.slug,
            modality_label(modality)
        )));
    };
    if media.modality != modality {
        return Err(protocol_error(format!(
            "model={} attachment {attachment_id} prepared modality does not match message content",
            model.base.slug
        )));
    }
    Ok(media)
}

fn has_representation(media: &ResolvedAttachment, representation: MediaRepresentation) -> bool {
    media
        .sources
        .iter()
        .any(|source| source_matches(source, representation))
}

fn source_matches(source: &AttachmentRepresentation, representation: MediaRepresentation) -> bool {
    matches!(
        (source, representation),
        (
            AttachmentRepresentation::RemoteUrl { .. },
            MediaRepresentation::RemoteUrl
        ) | (
            AttachmentRepresentation::ProviderFile { .. },
            MediaRepresentation::ProviderFile
        ) | (
            AttachmentRepresentation::DataUrl { .. },
            MediaRepresentation::DataUrl
        )
    )
}

fn is_snapshot_source(source: &AttachmentRepresentation) -> bool {
    matches!(source, AttachmentRepresentation::DataUrl { .. })
}

fn model_modality(modality: AttachmentModality) -> crate::model::ModelModality {
    match modality {
        AttachmentModality::Image => crate::model::ModelModality::Image,
        AttachmentModality::Video => crate::model::ModelModality::Video,
        AttachmentModality::File => crate::model::ModelModality::File,
    }
}

fn modality_label(modality: AttachmentModality) -> &'static str {
    match modality {
        AttachmentModality::Image => "image",
        AttachmentModality::Video => "video",
        AttachmentModality::File => "file",
    }
}

fn representation_label(representation: MediaRepresentation) -> &'static str {
    match representation {
        MediaRepresentation::RemoteUrl => "remoteUrl",
        MediaRepresentation::ProviderFile => "providerFile",
        MediaRepresentation::DataUrl => "dataUrl",
    }
}
