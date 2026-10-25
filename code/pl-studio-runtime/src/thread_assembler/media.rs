//! Persistent raw media and model-owned image projection for Thread tools.
use crate::resource_store::{ArchiveOrigin, ThreadResourceStore};
use pl_core::{context::ContextContent, tool::opaque::ToolError};
use pl_tool::media::{RetainedToolMedia, ToolMedia, ToolMediaHost, ToolMediaKind};
use std::sync::Arc;

/// Shared resource host used by Thread tools that archive media bytes.
#[derive(Debug)]
pub(crate) struct MediaHost(pub(crate) ThreadResourceStore);

impl ToolMediaHost for MediaHost {
    async fn retain(
        &self,
        origin: pl_tool::media::ToolResourceOrigin,
        media: ToolMedia,
    ) -> Result<RetainedToolMedia, ToolError> {
        let reference = self
            .0
            .retain_bytes(
                ArchiveOrigin::Tool(origin.clone()),
                media.bytes.clone(),
                media.media_type.clone(),
            )
            .await?;
        let mut context = if let Some(image) = media.model_image {
            let projected = if image.media_type == media.media_type
                && image.bytes.as_ref() == media.bytes.as_ref()
            {
                reference.clone()
            } else {
                self.0
                    .retain_bytes(ArchiveOrigin::Tool(origin), image.bytes, image.media_type)
                    .await?
            };
            vec![
                pl_model::runtime::attachment_content(
                    projected,
                    pl_protocol::AttachmentModality::Image,
                )
                .map_err(ToolError::new)?,
            ]
        } else {
            let mut context = vec![ContextContent::Resource {
                reference: reference.clone(),
            }];
            match media.kind {
                ToolMediaKind::Image => context.push(ContextContent::Text { text: Arc::from("Image retained as a resource; this prepared model does not advertise image input.") }),
                ToolMediaKind::Audio | ToolMediaKind::Blob => {}
            }
            context
        };
        // Always retain the original as an explicit reliable fact as well as any native derivative.
        if !context.iter().any(|part| matches!(part, ContextContent::Resource { reference: existing } if existing == &reference)) {
            context.push(ContextContent::Resource { reference: reference.clone() });
        }
        Ok(RetainedToolMedia { reference, context })
    }
}
