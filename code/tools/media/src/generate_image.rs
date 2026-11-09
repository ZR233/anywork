//! Image generation orchestration over an already selected service; no provider HTTP code.
use pl_agent_tool::typed::TypedTool;
use pl_tool_media_support::{
    ImageContext, Media, MediaHost, MediaKind, PreparedImage, Retained, prepare_image,
};
use std::{error::Error, future::Future, sync::Arc};

pub const NAME: &str = "generate_image";
pub const DESCRIPTION: &str = "Generate one image from a text prompt with the account's image service. The generated image is archived as a thread attachment; describe the result in text instead of embedding or repeating the image inline.";
pub const ARCHIVED_NOTE: &str = "The generated image is archived as a thread attachment. Do not embed or restate the image in your reply.";

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Input {
    /// Image description sent to the account verbatim after trimming surrounding whitespace.
    pub prompt: String,
    /// Request a transparent background; omitted means the account default (opaque).
    #[serde(default)]
    pub transparent_background: bool,
}

#[derive(Debug, Clone)]
pub struct GeneratedImage {
    pub bytes: Arc<[u8]>,
    pub media_type: String,
    pub revised_prompt: Option<String>,
}

pub trait ImageGenerator: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    fn generate(
        &self,
        prompt: String,
        transparent: bool,
    ) -> impl Future<Output = Result<GeneratedImage, Self::Error>> + Send;
}

pub struct Output<R, P> {
    pub prompt: String,
    pub transparent_background: bool,
    pub media_type: String,
    pub retained: Retained<R, P>,
    pub revised_prompt: Option<String>,
    pub model_dimensions: Option<(u32, u32)>,
}

#[derive(Debug, thiserror::Error)]
#[error("{source}")]
pub struct GenerationError {
    #[source]
    pub source: Box<dyn Error + Send + Sync>,
    pub observed: Option<GeneratedImage>,
}

impl GenerationError {
    fn new(source: impl Error + Send + Sync + 'static) -> Self {
        Self {
            source: Box::new(source),
            observed: None,
        }
    }
    fn invalid(message: &str) -> Self {
        Self::new(std::io::Error::other(message.to_owned()))
    }
}

pub struct GenerateImage<G, H> {
    generator: G,
    media: Arc<H>,
}

impl<G: ImageGenerator, H: MediaHost> GenerateImage<G, H> {
    pub fn new(generator: G, media: Arc<H>) -> Self {
        Self { generator, media }
    }
}

impl<G: ImageGenerator, H: MediaHost> TypedTool for GenerateImage<G, H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Input;
    type Context = ImageContext;
    type Output = Output<H::Reference, H::Projection>;
    type Error = GenerationError;

    async fn execute(
        &self,
        input: Input,
        context: ImageContext,
    ) -> Result<Self::Output, Self::Error> {
        let prompt = input.prompt.trim().to_owned();
        if prompt.is_empty() {
            return Err(GenerationError::invalid(
                "image generation prompt must not be empty",
            ));
        }
        if prompt.chars().count() > 8_000 {
            return Err(GenerationError::invalid(
                "image generation prompt exceeds 8000 characters",
            ));
        }
        if context.cancellation.is_cancelled() {
            return Err(GenerationError::invalid(
                "image generation cancelled before dispatch",
            ));
        }
        let generated = self
            .generator
            .generate(prompt.clone(), input.transparent_background)
            .await
            .map_err(GenerationError::new)?;
        // A received image is observed even if cancellation arrived while the provider was working.
        let prepared = async {
            let (model_image, model_dimensions) =
                match context.limits.filter(|limits| limits.max_count != Some(0)) {
                    Some(limits) => {
                        let total_limit = limits.max_total_bytes;
                        let normalized = prepare_image(NAME, generated.bytes.clone(), None, limits)
                            .await
                            .map_err(GenerationError::new)?;
                        if total_limit.is_some_and(|limit| normalized.bytes.len() as u64 > limit) {
                            return Err(GenerationError::invalid(
                                "generated image exceeds the prepared total-byte limit",
                            ));
                        }
                        (
                            Some(PreparedImage {
                                bytes: normalized.bytes.into(),
                                media_type: normalized.media_type,
                            }),
                            Some((normalized.width, normalized.height)),
                        )
                    }
                    None => (None, None),
                };
            let retained = self
                .media
                .retain(Media {
                    kind: MediaKind::Image,
                    bytes: generated.bytes.clone(),
                    media_type: generated.media_type.clone(),
                    model_image,
                })
                .await
                .map_err(GenerationError::new)?;
            Ok((retained, model_dimensions))
        }
        .await;
        let (retained, model_dimensions) = prepared.map_err(|mut error| {
            error.observed = Some(generated.clone());
            error
        })?;
        Ok(Output {
            prompt,
            transparent_background: input.transparent_background,
            media_type: generated.media_type,
            retained,
            revised_prompt: generated.revised_prompt,
            model_dimensions,
        })
    }
}
