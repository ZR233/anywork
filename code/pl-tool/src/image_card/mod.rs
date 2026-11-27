//! Read-only decoder for historical image cards. No executable legacy tool remains.
use pl_core::{context::ResourceReference, tool::opaque::ToolError};
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
/// Rejects malformed content and invalid references.
pub fn saved_image_card_receipt(
    details: Option<&serde_json::Value>,
) -> Result<Option<ImageCardReceipt>, ToolError> {
    let Some(value) = details.and_then(|details| details.get("imageCard")) else {
        return Ok(None);
    };
    let receipt: ImageCardReceipt =
        serde_json::from_value(value.clone()).map_err(ToolError::new)?;
    receipt.image.validate().map_err(ToolError::new)?;
    Ok(Some(receipt))
}
