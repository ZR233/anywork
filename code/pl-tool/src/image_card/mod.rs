//! Read-only decoder for historical image cards. No executable legacy tool remains.
use pl_core::{
    context::{OpaquePayload, ResourceReference},
    tool::opaque::ToolError,
};
/// Versioned receipt format emitted for one displayed image card.
pub const IMAGE_CARD_FORMAT: &str = "pl.tool.image-card";
/// Receipt layout version; changes require an explicit decoder update.
pub const IMAGE_CARD_VERSION: u32 = 1;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImageCardReceipt {
    pub image: ResourceReference,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
}

/// Decodes an old saved card without restoring its execution path.
///
/// # Errors
/// Rejects unsupported versions, malformed content and invalid references.
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
