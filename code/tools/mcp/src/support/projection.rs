use std::sync::Arc;

use base64::{Engine, engine::general_purpose::STANDARD};
use pl_tool_media_support::{
    ImageOutputLimits, MAX_SOURCE_BYTES, Media, MediaHost, MediaKind, PreparedImage, prepare_image,
};
use rmcp::model::{CallToolResult, ContentBlock, ResourceContents};
use serde_json::Value;

use crate::support::{Content, McpError, McpOutput, ResultKind};

pub async fn project_content<H: MediaHost>(
    result: &CallToolResult,
    host: &H,
    limits: Option<ImageOutputLimits>,
) -> Result<McpOutput<H::Projection>, McpError<H::Projection>> {
    let mut value = serde_json::to_value(result).map_err(McpError::new)?;
    let saved = value
        .get_mut("content")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| McpError::invalid("MCP result lacks content array"))?;
    if saved.len() != result.content.len() {
        return Err(McpError::invalid(
            "MCP content serialization changed result cardinality",
        ));
    }
    let image_count = result
        .content
        .iter()
        .filter(|content| matches!(content, ContentBlock::Image(_)))
        .count();
    if limits
        .as_ref()
        .and_then(|limits| limits.max_count)
        .is_some_and(|maximum| image_count > maximum as usize)
    {
        return Err(McpError::invalid(
            "MCP image count exceeds the prepared model limit",
        ));
    }
    let mut total_image_bytes = 0_u64;
    let mut context = Vec::new();
    for (content, saved) in result.content.iter().zip(saved.iter_mut()) {
        let media = match content {
            ContentBlock::Text(text) => {
                context.push(Content::Text(text.text.clone()));
                None
            }
            ContentBlock::Image(image) => Some((
                MediaKind::Image,
                image.data.as_str(),
                image.mime_type.as_str(),
                "data",
            )),
            ContentBlock::Audio(audio) => Some((
                MediaKind::Audio,
                audio.data.as_str(),
                audio.mime_type.as_str(),
                "data",
            )),
            ContentBlock::Resource(resource) => match &resource.resource {
                ResourceContents::TextResourceContents { text, .. } => {
                    context.push(Content::Text(text.clone()));
                    None
                }
                ResourceContents::BlobResourceContents {
                    blob, mime_type, ..
                } => Some((
                    MediaKind::Blob,
                    blob.as_str(),
                    mime_type.as_deref().unwrap_or("application/octet-stream"),
                    "blob",
                )),
                _ => {
                    return Err(McpError::invalid(
                        "unsupported embedded MCP resource kind; original result retained",
                    ));
                }
            },
            ContentBlock::ResourceLink(_) => {
                context.push(Content::Text(
                    serde_json::to_string(saved).map_err(McpError::new)?,
                ));
                None
            }
            _ => {
                return Err(McpError::invalid(
                    "unsupported MCP content kind; original result retained",
                ));
            }
        };
        if let Some((kind, encoded, media_type, field)) = media {
            let bytes: Arc<[u8]> = STANDARD.decode(encoded).map_err(McpError::new)?.into();
            let model_image = match (kind, &limits) {
                (MediaKind::Image, Some(limits)) => {
                    if bytes.len() > MAX_SOURCE_BYTES {
                        return Err(McpError::invalid(
                            "MCP source image exceeds the decode limit",
                        ));
                    }
                    let image = prepare_image(
                        "mcp",
                        bytes.clone(),
                        Some(media_type.to_owned()),
                        limits.clone(),
                    )
                    .await
                    .map_err(McpError::new)?;
                    total_image_bytes = total_image_bytes
                        .checked_add(image.bytes.len() as u64)
                        .ok_or_else(|| McpError::invalid("MCP image byte count overflow"))?;
                    if limits
                        .max_total_bytes
                        .is_some_and(|maximum| total_image_bytes > maximum)
                    {
                        return Err(McpError::invalid(
                            "MCP images exceed the prepared model total byte limit",
                        ));
                    }
                    Some(PreparedImage {
                        bytes: image.bytes.into(),
                        media_type: image.media_type,
                    })
                }
                _ => None,
            };
            let retained = host
                .retain(Media {
                    kind,
                    model_image,
                    bytes,
                    media_type: media_type.to_owned(),
                })
                .await
                .map_err(McpError::new)?;
            let object = if field == "blob" {
                saved.get_mut("resource")
            } else {
                Some(saved)
            }
            .and_then(Value::as_object_mut)
            .ok_or_else(|| McpError::invalid("MCP binary content envelope changed"))?;
            object.remove(field);
            object.insert(
                "retainedResource".into(),
                serde_json::to_value(retained.reference).map_err(McpError::new)?,
            );
            context.push(Content::Media(retained.projection));
        }
    }
    if let Some(structured) = &result.structured_content {
        let encoded = serde_json::to_string(structured).map_err(McpError::new)?;
        if !context
            .iter()
            .any(|content| matches!(content, Content::Text(text) if text == &encoded))
        {
            context.push(Content::Text(encoded));
        }
    }
    bound_text(&mut context);
    Ok(McpOutput {
        protocol: value,
        content: context,
        kind: ResultKind::Tool,
    })
}

pub fn bound_text<P>(context: &mut Vec<Content<P>>) {
    let mut remaining = 12 * 1024;
    let mut omitted = 0_usize;
    for content in context.iter_mut() {
        if let Content::Text(text) = content {
            let bounded = pl_output::bounded_text(text, remaining, 0);
            remaining = remaining.saturating_sub(bounded.text.len());
            omitted = omitted.saturating_add(bounded.bytes_omitted);
            *text = bounded.text;
        }
    }
    if omitted != 0 {
        context.push(Content::Text(format!(
            "[MCP preview omitted {omitted} bytes of text; the complete result is retained in tool history.]"
        )));
    }
}

pub async fn project_resource<H: MediaHost>(
    mut value: Value,
    host: &H,
    limits: Option<ImageOutputLimits>,
) -> Result<McpOutput<H::Projection>, McpError<H::Projection>> {
    let projected = async {
        let parsed: rmcp::model::ReadResourceResult =
            serde_json::from_value(value.clone()).map_err(McpError::new)?;
        let result = CallToolResult::success(
            parsed
                .contents
                .into_iter()
                .map(ContentBlock::resource)
                .collect(),
        );
        let projected = project_content(&result, host, limits).await?;
        let contents = projected
            .protocol
            .get("content")
            .and_then(Value::as_array)
            .ok_or_else(|| McpError::invalid("projected MCP resources lack content"))?
            .iter()
            .map(|content| {
                content
                    .get("resource")
                    .cloned()
                    .ok_or_else(|| McpError::invalid("projected MCP resource envelope changed"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok::<_, McpError<H::Projection>>((contents, projected.content))
    }
    .await;
    match projected {
        Ok((contents, content)) => {
            value
                .as_object_mut()
                .ok_or_else(|| McpError::invalid("MCP resource result is not an object"))?
                .insert("contents".into(), Value::Array(contents));
            Ok(McpOutput {
                protocol: value,
                content,
                kind: ResultKind::Resources,
            })
        }
        Err(error) => Err(error.with_unarchived(value, ResultKind::Resources)),
    }
}
