//! Exact-byte media capabilities and bounded image preparation, without product resources.
use std::{error::Error, future::Future, sync::Arc};

mod normalize;
pub use normalize::{MAX_SOURCE_BYTES, NormalizedToolImage, media_type, normalize_tool_image};
pub use tokio_util::sync::CancellationToken;

/// Host-frozen image input limits; no provider or product context is required.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImageOutputLimits {
    pub max_count: Option<u32>,
    pub max_bytes: Option<u64>,
    pub max_total_bytes: Option<u64>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub media_types: Vec<String>,
}

#[derive(Debug, Clone, Copy)]
pub enum MediaKind {
    Image,
    Audio,
    Blob,
}

#[derive(Debug)]
pub struct PreparedImage {
    pub bytes: Arc<[u8]>,
    pub media_type: String,
}

/// Original bytes and, when supported, the model-normalized image variant.
#[derive(Debug)]
pub struct Media {
    pub kind: MediaKind,
    pub bytes: Arc<[u8]>,
    pub media_type: String,
    pub model_image: Option<PreparedImage>,
}

/// The host owns the identities and the projection; tools cannot invent product resources.
#[derive(Debug)]
pub struct Retained<R, P> {
    pub reference: R,
    pub projection: P,
}

pub trait MediaHost: Send + Sync + 'static {
    type Reference: serde::Serialize + Send + Sync + 'static;
    type Projection: std::fmt::Debug + Send + Sync + 'static;
    type Error: Error + Send + Sync + 'static;

    /// Retains exact bytes and validates the reference before returning.
    fn retain(
        &self,
        media: Media,
    ) -> impl Future<Output = Result<Retained<Self::Reference, Self::Projection>, Self::Error>> + Send;
}

/// Only the model facts needed by media-producing tools travel with a call.
#[derive(Debug, Clone, Default)]
pub struct ImageContext {
    pub limits: Option<ImageOutputLimits>,
    pub cancellation: CancellationToken,
}

#[derive(Debug, thiserror::Error)]
#[error("{message}")]
pub struct ImageError {
    message: String,
    #[source]
    source: Option<Box<dyn Error + Send + Sync>>,
}

impl ImageError {
    pub fn invalid(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            source: None,
        }
    }

    pub fn caused(message: impl Into<String>, source: impl Error + Send + Sync + 'static) -> Self {
        Self {
            message: message.into(),
            source: Some(Box::new(source)),
        }
    }
}

/// Runs the existing image SDK-based normalization outside the async executor.
pub async fn prepare_image(
    tool: &'static str,
    bytes: Arc<[u8]>,
    declared: Option<String>,
    limits: ImageOutputLimits,
) -> Result<NormalizedToolImage, ImageError> {
    tokio::task::spawn_blocking(move || {
        normalize_tool_image(tool, bytes.to_vec(), declared.as_deref(), &limits)
    })
    .await
    .map_err(|source| ImageError::caused("image preparation task failed", source))?
}
