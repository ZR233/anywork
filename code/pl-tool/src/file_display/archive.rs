//! Frozen context proves membership; original committed tool facts enrich that proof.
use super::{
    FileDisplayOrigin, FileDisplayResult, ResourceReference, failure, saved_file_display_receipt,
};
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    tool::opaque::{CallContext, ToolError},
};
use pl_protocol::AttachmentModality;

pub(super) async fn archived_file(
    context: &CallContext,
    id: &str,
) -> Result<FileDisplayResult, ToolError> {
    let mut fallback = None;
    for record in context.context.records.iter().rev() {
        // A committed receipt is looked up only by an actual call in this frozen Thread context.
        // This also covers old show_image, whose context was just a short text note.
        if let (ContextSource::ToolResult { call_id, .. }, Some(tasks)) =
            (&record.source, &context.tasks)
        {
            // Core's task key is derived from its call identity. `result` includes the
            // terminal ledger/effect window, unlike `list`, which only lists resident tasks.
            let delivery = match tasks.result(&format!("task:{call_id}")) {
                Ok(delivery) => delivery,
                Err(
                    pl_core::thread::ThreadError::InvalidOutput
                    | pl_core::thread::ThreadError::TaskNotFound { .. },
                ) => tasks
                    .durable(call_id)
                    .await
                    .map_err(ToolError::new)?
                    .and_then(|fact| fact.delivery),
                Err(error) => return Err(ToolError::new(error)),
            };
            if let Some(delivery) = delivery
                && let Some(file) = receipt_file(delivery.output.payload(), id)?
            {
                return Ok(file);
            }
        }
        for content in record.content.iter().rev() {
            match content {
                ContextContent::Resource { reference } if reference.id() == id => {
                    fallback = Some(from_reference(reference.clone()));
                }
                ContextContent::Opaque { payload } => {
                    if let Some(file) = receipt_file(payload, id)? {
                        return Ok(file);
                    }
                    if let Some(attachment) =
                        pl_model::runtime::decode_attachment(payload).map_err(ToolError::new)?
                        && attachment.reference.id() == id
                    {
                        let mut file = from_reference(attachment.reference);
                        if let FileDisplayResult::Ready { modality, .. } = &mut file {
                            *modality = attachment.modality;
                        }
                        fallback = Some(file);
                    }
                }
                _ => {}
            }
        }
    }
    fallback.ok_or_else(|| failure("attachment id is not archived in this Thread's frozen context"))
}

fn receipt_file(payload: &OpaquePayload, id: &str) -> Result<Option<FileDisplayResult>, ToolError> {
    if let Some(receipt) = saved_file_display_receipt(payload)? {
        return Ok(receipt.files.into_iter().find(
            |file| matches!(file, FileDisplayResult::Ready { resource, .. } if resource.id() == id),
        ));
    }
    if let Some(receipt) = crate::image::saved_view_image_receipt(payload)?
        && receipt.original.id() == id
    {
        return Ok(Some(FileDisplayResult::Ready {
            resource: receipt.original,
            filename: super::thread::filename(&receipt.path),
            modality: AttachmentModality::Image,
            // Old paths were caller-supplied and are not verified local locators.
            origin: FileDisplayOrigin::Archive,
        }));
    }
    if let Some(receipt) = crate::image_card::saved_image_card_receipt(payload)?
        && receipt.image.id() == id
    {
        return Ok(Some(from_reference(receipt.image)));
    }
    Ok(None)
}

fn from_reference(resource: ResourceReference) -> FileDisplayResult {
    let modality = if resource.media_type().starts_with("image/") {
        AttachmentModality::Image
    } else if resource.media_type().starts_with("video/") {
        AttachmentModality::Video
    } else {
        AttachmentModality::File
    };
    let filename = match resource.media_type() {
        "image/png" => "image.png",
        "image/jpeg" => "image.jpg",
        "image/gif" => "image.gif",
        "image/webp" => "image.webp",
        "application/pdf" => "file.pdf",
        _ => "file",
    }
    .to_owned();
    FileDisplayResult::Ready {
        resource,
        filename,
        modality,
        origin: FileDisplayOrigin::Archive,
    }
}
