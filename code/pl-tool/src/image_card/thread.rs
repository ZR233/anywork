//! One Thread-local display tool selecting an image this Thread already archived.
use super::{IMAGE_CARD_FORMAT, IMAGE_CARD_VERSION, TOOL_SHOW_IMAGE};
use pl_core::{
    context::{ContextContent, ContextRecord, OpaquePayload, ResourceReference},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};
use pl_protocol::AttachmentModality;

/// Longest caption retained after trimming; the card never shows a longer text.
const MAX_CAPTION_CHARS: usize = 240;

const DESCRIPTION: &str = "Display one image this thread already archived as a timeline image \
card. Pass an optional short caption; the image is chosen from archived thread attachments. This \
does not read workspace files, fetch remote URLs or add new image bytes.";

/// Fixed model-visible note describing the delivered card, without image bytes or paths.
const CARD_NOTE: &str = "An image card was added to the timeline.";

/// Request parameters for one image card display.
#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ShowImageInput {
    /// Optional card text, trimmed; an empty text or omission shows no caption (<= 240 chars).
    pub caption: Option<String>,
    /// Optional identity of one archived image; omitted displays the newest archived image.
    pub image_id: Option<String>,
}

/// Tool-owned receipt binding the displayed attachment to its bounded caption.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImageCardReceipt {
    /// Thread-owned archive reference the card displays; the tool adds no second media source.
    pub image: pl_core::context::ResourceReference,
    /// Trimmed display text, absent when the caller supplied none.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
}

/// Decodes the tool-owned receipt, or returns `None` for another producer's payload.
///
/// Owning the format means every version of it must be understood: a payload that claims
/// `IMAGE_CARD_FORMAT` but an unknown version is rejected instead of being silently skipped, so
/// an unreadable card never degrades into a guessed projection.
///
/// # Errors
/// Rejects an unsupported receipt version, malformed receipt content, or invalid retained
/// reference metadata.
pub fn saved_image_card_receipt(
    payload: &OpaquePayload,
) -> Result<Option<ImageCardReceipt>, ToolError> {
    if payload.format() != IMAGE_CARD_FORMAT {
        return Ok(None);
    }
    if payload.version() != IMAGE_CARD_VERSION {
        return Err(ToolError::new(std::io::Error::other(format!(
            "unsupported {IMAGE_CARD_FORMAT} receipt version {}",
            payload.version()
        ))));
    }
    let receipt: ImageCardReceipt =
        serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    receipt.image.validate().map_err(ToolError::new)?;
    Ok(Some(receipt))
}

/// A role-free display tool: it owns no media host, backend or workspace binding.
#[derive(Debug, Default)]
pub struct ThreadShowImageTool;

impl ThreadShowImageTool {
    /// Creates the tool; display input and archived facts come from the executed call alone.
    pub fn new() -> Self {
        Self
    }

    /// Stable declaration, independent of conversation state and observed results.
    pub fn declaration() -> pl_protocol::ToolSpec {
        pl_protocol::ToolSpec::function(
            TOOL_SHOW_IMAGE,
            DESCRIPTION,
            schemars::schema_for!(ShowImageInput).to_value(),
        )
    }

    /// Transfers a local, side-effect-free display that coexists with other foreground calls.
    ///
    /// The call only reads its own frozen context and grants no framework control permission.
    ///
    /// # Errors
    /// Returns invalid registry identity errors.
    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        Ok(Registration::new(TOOL_SHOW_IMAGE.into(), declaration, self)?.foreground_coexisting())
    }
}

impl Tool for ThreadShowImageTool {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(failure("unsupported image card argument encoding"));
        }
        let input: ShowImageInput =
            serde_json::from_str(input.content()).map_err(ToolError::new)?;
        let caption = input
            .caption
            .as_deref()
            .map(str::trim)
            .filter(|caption| !caption.is_empty())
            .map(str::to_owned);
        if caption
            .as_ref()
            .is_some_and(|caption| caption.chars().count() > MAX_CAPTION_CHARS)
        {
            return Err(failure("image card caption exceeds 240 characters"));
        }
        let image_id = input.image_id;
        let image = match archived_image(&context.context.records, image_id.as_deref()) {
            Some(image) => image,
            None if image_id.is_some() => {
                return Err(failure("archived image id not found in this thread"));
            }
            None => return Err(failure("no archived image in this thread")),
        };
        let payload = OpaquePayload::new(
            IMAGE_CARD_FORMAT,
            IMAGE_CARD_VERSION,
            serde_json::to_string(&ImageCardReceipt { image, caption }).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            payload,
            vec![ContextContent::Text {
                text: CARD_NOTE.into(),
            }],
        ))
    }
}

/// Returns the archived image reference the card displays, scanning newest content first.
///
/// An opaque entry contributes only when it decodes as the model attachment projection with an
/// image modality; another producer's opaque payload is skipped instead of failing the call. A
/// resource entry contributes only an `image/*` reference. A requested identity filters out every
/// other archived image, so a stale identity never silently displays a different image.
fn archived_image(records: &[ContextRecord], image_id: Option<&str>) -> Option<ResourceReference> {
    for record in records.iter().rev() {
        for content in record.content.iter().rev() {
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
                ContextContent::Resource { reference } => {
                    if reference.media_type().starts_with("image/") {
                        Some(reference.clone())
                    } else {
                        None
                    }
                }
                ContextContent::Text { .. } => None,
            };
            let Some(reference) = reference else {
                continue;
            };
            if image_id.is_some_and(|image_id| reference.id() != image_id) {
                continue;
            }
            return Some(reference);
        }
    }
    None
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_SHOW_IMAGE, message))
}
