//! Workspace image reads over a host-authorized byte source and exact-byte media store.
use pl_agent_tool::typed::TypedTool;
use pl_tool_media::{
    ImageContext, MAX_SOURCE_BYTES, Media, MediaHost, MediaKind, PreparedImage, Retained,
    prepare_image,
};
use std::{error::Error, future::Future, marker::PhantomData, sync::Arc};

pub const NAME: &str = "view_image";
pub const DESCRIPTION: &str = "Open a local or SSH workspace image so you can inspect screenshots and other image files. Pass its path in the current workspace; SSH paths must be workspace-relative POSIX paths. The image is retained for model context and history replay. Requires image input support from the current model.";

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Input {
    /// Image path in the current local or SSH workspace. Use a workspace-relative POSIX path for SSH.
    pub path: String,
}

/// A per-call authorized read capability, not a general filesystem backend.
pub trait ImageReader: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    /// Rejects non-regular files and enforces this maximum before allocating the result.
    fn read(
        &self,
        path: String,
        max_bytes: usize,
    ) -> impl Future<Output = Result<Arc<[u8]>, Self::Error>> + Send;
}

pub struct Context<B> {
    pub reader: B,
    pub image: ImageContext,
}

pub struct Output<R, P> {
    pub path: String,
    pub retained: Retained<R, P>,
    pub model_width: u32,
    pub model_height: u32,
}

#[derive(Debug, thiserror::Error)]
#[error("{source}")]
pub struct ViewImageError {
    #[source]
    pub source: Box<dyn Error + Send + Sync>,
}

impl ViewImageError {
    fn new(source: impl Error + Send + Sync + 'static) -> Self {
        Self {
            source: Box::new(source),
        }
    }
    fn invalid(message: &str) -> Self {
        Self::new(std::io::Error::other(message.to_owned()))
    }
}

pub struct ViewImage<B, H> {
    media: Arc<H>,
    reader: PhantomData<fn() -> B>,
}

impl<B: ImageReader, H: MediaHost> ViewImage<B, H> {
    pub fn new(media: Arc<H>) -> Self {
        Self {
            media,
            reader: PhantomData,
        }
    }
}

impl<B: ImageReader, H: MediaHost> TypedTool for ViewImage<B, H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Input;
    type Context = Context<B>;
    type Output = Output<H::Reference, H::Projection>;
    type Error = ViewImageError;

    async fn execute(
        &self,
        input: Input,
        context: Context<B>,
    ) -> Result<Self::Output, Self::Error> {
        let limits = context
            .image
            .limits
            .filter(|limits| limits.max_count != Some(0))
            .ok_or_else(|| {
                ViewImageError::invalid("prepared model does not support image input")
            })?;
        if context.image.cancellation.is_cancelled() {
            return Err(ViewImageError::invalid("image read cancelled"));
        }
        let bytes = context
            .reader
            .read(input.path.clone(), MAX_SOURCE_BYTES)
            .await
            .map_err(ViewImageError::new)?;
        if bytes.len() > MAX_SOURCE_BYTES {
            return Err(ViewImageError::invalid(
                "image source exceeds the byte limit",
            ));
        }
        if context.image.cancellation.is_cancelled() {
            return Err(ViewImageError::invalid("image read cancelled"));
        }
        let format = image::guess_format(&bytes).map_err(ViewImageError::new)?;
        let source_type = pl_tool_media::media_type(format)
            .ok_or_else(|| ViewImageError::invalid("unsupported image header"))?;
        let total_limit = limits.max_total_bytes;
        let normalized = prepare_image(NAME, bytes.clone(), None, limits)
            .await
            .map_err(ViewImageError::new)?;
        if total_limit.is_some_and(|limit| normalized.bytes.len() as u64 > limit) {
            return Err(ViewImageError::invalid(
                "image exceeds the prepared total-byte limit",
            ));
        }
        if context.image.cancellation.is_cancelled() {
            return Err(ViewImageError::invalid("image preparation cancelled"));
        }
        let dimensions = (normalized.width, normalized.height);
        let retained = self
            .media
            .retain(Media {
                kind: MediaKind::Image,
                bytes,
                media_type: source_type.into(),
                model_image: Some(PreparedImage {
                    bytes: normalized.bytes.into(),
                    media_type: normalized.media_type,
                }),
            })
            .await
            .map_err(ViewImageError::new)?;
        Ok(Output {
            path: input.path,
            retained,
            model_width: dimensions.0,
            model_height: dimensions.1,
        })
    }
}
