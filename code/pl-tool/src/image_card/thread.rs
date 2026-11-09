//! Host-authorized archive candidates and unchanged image-card history receipts.
use super::{IMAGE_CARD_FORMAT, IMAGE_CARD_VERSION};
use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::{ContextContent, ContextRecord, OpaquePayload, ResourceReference},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_protocol::AttachmentModality;
pub use pl_tool_show_image::Input as ShowImageInput;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImageCardReceipt {
    pub image: ResourceReference,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
}

pub fn saved_image_card_receipt(
    payload: &OpaquePayload,
) -> Result<Option<ImageCardReceipt>, ToolError> {
    if payload.format() != IMAGE_CARD_FORMAT {
        return Ok(None);
    }
    if payload.version() != IMAGE_CARD_VERSION {
        return Err(ToolError::new(std::io::Error::other(format!(
            "unsupported {IMAGE_CARD_FORMAT} receipt version {}",
            payload.version(),
        ))));
    }
    let receipt: ImageCardReceipt =
        serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    receipt.image.validate().map_err(ToolError::new)?;
    Ok(Some(receipt))
}

#[derive(Debug, Default)]
pub struct ThreadShowImageTool;
impl ThreadShowImageTool {
    pub fn new() -> Self {
        Self
    }
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::ToolDefinition::json(
            pl_tool_show_image::NAME,
            pl_tool_show_image::DESCRIPTION,
            pl_agent_tool::typed::input_schema_for::<ShowImageInput>(),
        )
        .expect("static tool definition")
    }
}

impl TypedTool for ThreadShowImageTool {
    const NAME: &'static str = pl_tool_show_image::NAME;
    const DESCRIPTION: &'static str = pl_tool_show_image::DESCRIPTION;
    type Args = ShowImageInput;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let candidates = archived_images(&context.context.records);
        let output = pl_tool_show_image::ShowImage::default()
            .execute(input, candidates)
            .await
            .map_err(ToolError::new)?;
        let payload = OpaquePayload::new(
            IMAGE_CARD_FORMAT,
            IMAGE_CARD_VERSION,
            serde_json::to_string(&ImageCardReceipt {
                image: output.image,
                caption: output.caption,
            })
            .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            payload,
            vec![ContextContent::Text {
                text: pl_tool_show_image::CARD_NOTE.into(),
            }],
        ))
    }
}

fn archived_images(
    records: &[ContextRecord],
) -> Vec<pl_tool_show_image::ArchivedImage<ResourceReference>> {
    records
        .iter()
        .rev()
        .flat_map(|record| record.content.iter().rev())
        .filter_map(|content| {
            let reference = match content {
                ContextContent::Opaque { payload } => {
                    match pl_model::runtime::decode_attachment(payload) {
                        Ok(Some(attachment))
                            if attachment.modality == AttachmentModality::Image =>
                        {
                            Some(attachment.reference)
                        }
                        _ => None,
                    }
                }
                ContextContent::Resource { reference }
                    if reference.media_type().starts_with("image/") =>
                {
                    Some(reference.clone())
                }
                _ => None,
            }?;
            Some(pl_tool_show_image::ArchivedImage {
                id: reference.id().to_owned(),
                image: reference,
            })
        })
        .collect()
}
