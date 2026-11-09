//! Shared exact-byte media retention and frozen model projection for tools.
pub use pl_core::context::{ContextContent, ResourceReference};
use pl_core::{context::OpaquePayload, tool::opaque::ToolError};
pub use pl_tool_media_support::{
    ImageOutputLimits, Media as ToolMedia, MediaKind as ToolMediaKind,
    PreparedImage as PreparedToolImage,
};
use std::sync::Arc;

/// Durable material and the actual model-visible media projection selected by the host.
#[derive(Debug)]
pub struct RetainedToolMedia {
    pub reference: ResourceReference,
    pub context: Vec<ContextContent>,
}

/// The host supplies persistent resources and model-owned projection as one preparation port.
pub trait ToolMediaHost: Send + Sync + std::fmt::Debug + 'static {
    /// Returns only after bytes are retained. Failure must not imply a remote call was undone.
    fn retain(
        &self,
        media: ToolMedia,
    ) -> impl std::future::Future<Output = Result<RetainedToolMedia, ToolError>> + Send;
}

/// Product resource and delivery adaptation; neither representation enters independent tools.
pub(crate) struct DomainMediaHost<H>(pub(crate) Arc<H>);

impl<H: ToolMediaHost> pl_tool_media_support::MediaHost for DomainMediaHost<H> {
    type Reference = ResourceReference;
    type Projection = Vec<ContextContent>;
    type Error = ToolError;

    async fn retain(
        &self,
        media: ToolMedia,
    ) -> Result<pl_tool_media_support::Retained<Self::Reference, Self::Projection>, ToolError> {
        let bytes = media.bytes.clone();
        let retained = self.0.retain(media).await?;
        retained.reference.verify(&bytes).map_err(ToolError::new)?;
        Ok(pl_tool_media_support::Retained {
            reference: retained.reference,
            projection: retained.context,
        })
    }
}

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
struct DomainSource(#[source] Box<dyn std::error::Error + Send + Sync>);

pub(crate) fn domain_error(source: Box<dyn std::error::Error + Send + Sync>) -> ToolError {
    match source.downcast::<ToolError>() {
        Ok(error) => *error,
        Err(source) => ToolError::new(DomainSource(source)),
    }
}

pub(crate) fn image_limits(
    projection: Option<&OpaquePayload>,
) -> Result<Option<crate::image::ImageOutputLimits>, ToolError> {
    let Some(projection) = projection else {
        return Ok(None);
    };
    if projection.format() != pl_protocol::tool_projection::FORMAT
        || projection.version() != pl_protocol::tool_projection::VERSION
    {
        return Err(pl_core::tool::opaque::ToolError::new(
            std::io::Error::other("unknown model tool projection format"),
        ));
    }
    let projection: pl_protocol::tool_projection::ToolProjection =
        serde_json::from_str(projection.content()).map_err(ToolError::new)?;
    Ok(projection
        .image
        .map(|image| crate::image::ImageOutputLimits {
            max_count: image.max_count,
            max_bytes: image.max_bytes,
            max_total_bytes: image.max_total_bytes,
            max_width: image.max_width,
            max_height: image.max_height,
            media_types: image.media_types,
        }))
}
