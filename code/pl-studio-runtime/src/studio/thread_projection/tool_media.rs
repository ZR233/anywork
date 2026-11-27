//! Archived tool media shared by the Timeline projection and safe attachment reads.
//!
//! Both consumers decode the same persisted facts: a displayable attachment is always a
//! variant a tool actually archived, and a read is authorized only by a reference this Thread
//! itself persisted. Both sides scan every committed delivery and reject contradictory facts
//! instead of trusting the first match. Neither side guesses sizes, trusts client paths, or
//! scans a second registry.
//!
//! 展示工具回执是本模块唯一不依赖模型图片输入能力的附件来源：它只引用本 Thread 已归档的
//! 图片，因此没有图片输入能力的 prepared 模型同样能在时间线上展示该图片
//! （见 design/06 §6.13）。
use super::ProjectionError;
use crate::resource_store::FileResourceStore;
use crate::{AttachmentModality, ThreadAttachment};
use anyhow::Context;
use pl_core::{
    context::{ContextContent, ResourceReader, ResourceReference},
    thread::ToolDelivery,
    tool::opaque::ToolError,
};
use tokio_util::sync::CancellationToken;

/// One archived media variant referenced by a persisted tool delivery.
#[derive(Debug, Clone)]
struct ArchivedToolMedia {
    reference: ResourceReference,
    modality: AttachmentModality,
    filename: Option<String>,
}

impl ArchivedToolMedia {
    fn into_attachment(self) -> ThreadAttachment {
        ThreadAttachment {
            id: self.reference.id().to_owned(),
            modality: self.modality,
            media_type: self.reference.media_type().to_owned(),
            filename: self.filename,
            // The versioned `view_image` receipt has no binding to a specific archived variant,
            // so no dimension is ever reported from it; unknown sizes stay unknown.
            width: None,
            height: None,
            byte_size: self.reference.byte_len(),
        }
    }
}

/// Exact retained resource references from the established producer decoder.
pub(crate) fn resource_references(
    delivery: &ToolDelivery,
) -> Result<Vec<ResourceReference>, ProjectionError> {
    let mut references: Vec<_> = archived_media(delivery)?
        .into_iter()
        .map(|media| media.reference)
        .collect();
    // The original may contain media that was not delivered after cancellation or budget
    // selection. Retaining it does not make it a model-visible attachment.
    for content in delivery.output.content() {
        match content {
            ContextContent::Resource { reference } => references.push(reference.clone()),
            ContextContent::Media { payload } => {
                if let Some(attachment) = pl_model::runtime::decode_attachment(payload)? {
                    references.push(attachment.reference);
                }
            }
            ContextContent::Text { .. } | ContextContent::Opaque { .. } => {}
        }
    }
    references.extend(
        pl_tool::exec::saved_command_resources(delivery.output.details())
            .map_err(ProjectionError::ToolMedia)?,
    );
    Ok(references)
}

/// Wraps a rejected persisted-media fact as a projection failure.
fn rejected(message: &str) -> ProjectionError {
    ProjectionError::ToolMedia(ToolError::new(std::io::Error::other(message.to_owned())))
}

/// Decodes the media actually delivered by one tool call.
///
/// Attachment identity, media type and byte length always come from the model-owned projection's
/// archived reference. A `view_image` receipt only supplies the display filename, and only when
/// it describes exactly one archived image attachment: a receipt that claims several attachments
/// or a non-image modality is contradictory and rejected. The receipt never contributes a
/// dimension because it does not bind to a specific archived variant.
///
/// An image card receipt contributes the archived image it displays, because the card never
/// delivers image bytes and therefore never repeats the attachment projection. A card that names
/// an already delivered attachment is not duplicated; one that names the same identity with a
/// different reference or modality contradicts the delivered fact and is rejected.
fn archived_media(delivery: &ToolDelivery) -> Result<Vec<ArchivedToolMedia>, ProjectionError> {
    if let Some(receipt) =
        pl_tool::file_display::saved_file_display_receipt(delivery.output.details())
            .map_err(ProjectionError::ToolMedia)?
    {
        // Preserve every selected entry, even when several entries share one resource.
        return Ok(receipt
            .files
            .into_iter()
            .filter_map(|file| match file {
                pl_tool::file_display::FileDisplayResult::Ready {
                    resource,
                    filename,
                    modality,
                    ..
                } => Some(ArchivedToolMedia {
                    reference: resource,
                    filename: Some(filename),
                    modality,
                }),
                pl_tool::file_display::FileDisplayResult::Deferred { .. }
                | pl_tool::file_display::FileDisplayResult::NetworkImage { .. }
                | pl_tool::file_display::FileDisplayResult::Failed { .. } => None,
            })
            .collect());
    }
    let receipt = pl_tool::image::saved_view_image_receipt(delivery.output.details())
        .map_err(ProjectionError::ToolMedia)?;
    let mut attachments = Vec::new();
    for content in super::tools::delivery_context(delivery) {
        let ContextContent::Media { payload } = content else {
            continue;
        };
        if let Some(attachment) = pl_model::runtime::decode_attachment(payload)? {
            attachments.push(attachment);
        }
    }
    let filename = match (receipt.as_ref(), attachments.as_slice()) {
        (Some(_), []) => None,
        (Some(receipt), [attachment]) if attachment.modality == AttachmentModality::Image => {
            Some(receipt.path.clone())
        }
        (Some(_), [_]) => {
            return Err(rejected(
                "view_image receipt describes a non-image model attachment",
            ));
        }
        (Some(_), _) => {
            return Err(rejected(
                "view_image receipt cannot describe multiple model attachments",
            ));
        }
        (None, _) => None,
    };
    let mut media: Vec<ArchivedToolMedia> = attachments
        .into_iter()
        .map(|attachment| ArchivedToolMedia {
            reference: attachment.reference,
            modality: attachment.modality,
            filename: filename.clone(),
        })
        .collect();
    if let Some(card) = pl_tool::image_card::saved_image_card_receipt(delivery.output.details())
        .map_err(ProjectionError::ToolMedia)?
    {
        match media
            .iter()
            .position(|existing| existing.reference.id() == card.image.id())
        {
            Some(index)
                if media[index].reference == card.image
                    && media[index].modality == AttachmentModality::Image => {}
            Some(_) => {
                return Err(rejected(
                    "image card receipt conflicts with the archived attachment",
                ));
            }
            None => media.push(ArchivedToolMedia {
                reference: card.image,
                modality: AttachmentModality::Image,
                filename: None,
            }),
        }
    }
    Ok(media)
}

/// Typed attachments for one terminal tool delivery, in delivered order.
///
/// # Errors
/// Rejects a corrupt model attachment projection or an undecodable tool receipt.
pub(crate) fn delivery_attachments(
    delivery: &ToolDelivery,
) -> Result<Vec<ThreadAttachment>, ProjectionError> {
    Ok(archived_media(delivery)?
        .into_iter()
        .map(ArchivedToolMedia::into_attachment)
        .collect())
}

/// Returns the archived reference this Thread persisted for `attachment_id`.
///
/// Only a reference recorded inside the Thread's own committed delivery context authorizes a
/// read: a resource id prefix, a digest, or Thread accessibility alone never does. Every
/// delivery is scanned so an id reused with a different reference or modality is rejected
/// instead of resolving to whichever fact appeared first.
///
/// # Errors
/// Rejects a corrupt persisted media projection or a contradictory archived fact for one id.
fn persisted_reference(
    deliveries: &[ToolDelivery],
    attachment_id: &str,
) -> Result<Option<ResourceReference>, ProjectionError> {
    let mut resolved: Option<(ResourceReference, AttachmentModality)> = None;
    let mut modality_conflict = false;
    for delivery in deliveries {
        for media in archived_media(delivery)? {
            if media.reference.id() != attachment_id {
                continue;
            }
            match &resolved {
                None => resolved = Some((media.reference, media.modality)),
                Some((reference, modality)) => {
                    if reference != &media.reference {
                        return Err(rejected("archived resource facts conflict"));
                    }
                    modality_conflict |= modality != &media.modality;
                }
            }
        }
    }
    if modality_conflict {
        return Err(rejected(
            "conflicting archived tool media share one attachment id",
        ));
    }
    Ok(resolved.map(|(reference, _)| reference))
}

/// Reads archived bytes only after proving this Thread itself persisted the reference.
///
/// A resource id prefix, digest, or Thread accessibility never authorizes a read; an unknown,
/// unreferenced, corrupt, or missing resource fails instead of re-reading a workspace path.
///
/// # Errors
/// Returns `None` without resident proof. Rejects corrupt media facts and unavailable or
/// integrity-failing bytes.
pub(crate) async fn read_persisted_media(
    store: &FileResourceStore,
    deliveries: &[ToolDelivery],
    attachment_id: &str,
) -> anyhow::Result<Option<Vec<u8>>> {
    let Some(reference) = persisted_reference(deliveries, attachment_id)? else {
        return Ok(None);
    };
    let bytes = store
        .read(reference, CancellationToken::new())
        .await
        .with_context(|| format!("archived tool media {attachment_id} is unavailable"))?;
    Ok(Some(bytes.to_vec()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::{thread::ToolOutcome, tool::ToolOutput};
    use std::{io::Cursor, sync::Arc};

    #[tokio::test]
    async fn undelivered_media_is_retained_without_becoming_a_visible_attachment()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let store = FileResourceStore::new(directory.path().to_path_buf());
        let mut encoded = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(1, 1).write_to(&mut encoded, image::ImageFormat::Png)?;
        let reference = store
            .retain_bytes(Arc::from(encoded.into_inner()), "image/png")
            .await?;
        let media =
            pl_model::runtime::attachment_content(reference.clone(), AttachmentModality::Image)?;
        let delivery = ToolDelivery {
            target: Default::default(),
            call_id: "cancelled-media".into(),
            tool_id: "media-author".into(),
            output: ToolOutput::new(pl_agent_tool::ToolResult::new(
                pl_agent_tool::ToolData::Absent,
                vec![media.clone()],
            )),
            delivered_context: vec![],
            outcome: ToolOutcome::Cancelled,
            cancellation_cause: None,
        };
        assert_eq!(resource_references(&delivery)?, vec![reference]);
        assert!(delivery_attachments(&delivery)?.is_empty());

        let ContextContent::Media { payload } = media else {
            unreachable!()
        };
        let opaque = ToolDelivery {
            output: ToolOutput::new(pl_agent_tool::ToolResult::new(
                pl_agent_tool::ToolData::Absent,
                vec![ContextContent::Opaque { payload }],
            )),
            ..delivery
        };
        assert!(resource_references(&opaque)?.is_empty());
        assert!(delivery_attachments(&opaque)?.is_empty());
        Ok(())
    }
}
