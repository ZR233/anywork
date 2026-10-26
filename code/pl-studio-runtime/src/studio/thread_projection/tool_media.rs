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
use pl_core::{
    context::{ContextContent, ResourceReference},
    thread::ToolDelivery,
    tool::opaque::ToolError,
};
use pl_protocol::{AttachmentModality, ThreadAttachment};

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
    let receipt = pl_tool::image::saved_view_image_receipt(delivery.output.payload())
        .map_err(ProjectionError::ToolMedia)?;
    let mut attachments = Vec::new();
    for content in &delivery.delivered_context {
        let ContextContent::Opaque { payload } = content else {
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
    if let Some(card) = pl_tool::image_card::saved_image_card_receipt(delivery.output.payload())
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
pub(crate) fn persisted_reference(
    deliveries: &[ToolDelivery],
    attachment_id: &str,
) -> Result<Option<ResourceReference>, ProjectionError> {
    let mut resolved: Option<(ResourceReference, AttachmentModality)> = None;
    for delivery in deliveries {
        for media in archived_media(delivery)? {
            if media.reference.id() != attachment_id {
                continue;
            }
            match &resolved {
                None => resolved = Some((media.reference, media.modality)),
                Some((reference, modality)) => {
                    if reference != &media.reference || modality != &media.modality {
                        return Err(rejected(
                            "conflicting archived tool media share one attachment id",
                        ));
                    }
                }
            }
        }
    }
    Ok(resolved.map(|(reference, _)| reference))
}
