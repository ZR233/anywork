//! One Thread-local image generation executor over a frozen provider backend and media host.
use super::{
    IMAGE_GENERATION_RECEIPT_FORMAT, IMAGE_GENERATION_RECEIPT_VERSION, TOOL_IMAGE_GENERATION,
};
use crate::media::{PreparedToolImage, ToolMedia, ToolMediaHost, ToolMediaKind, image_limits};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};
use pl_model::provider::images::{ImageGenerationBackground, ImageGenerationRequest, ImagesClient};
use std::sync::Arc;

/// Longest prompt accepted after trimming; the provider never receives a longer request.
const MAX_PROMPT_CHARS: usize = 8_000;

const DESCRIPTION: &str = "Generate one image from a text prompt with the provider's image \
service. The generated image is archived as a thread attachment; describe the result in text \
instead of embedding or repeating the image inline.";

/// Fixed model-visible note appended after the archived media projection.
const ARCHIVED_NOTE: &str = "The generated image is archived as a thread attachment. Do not \
embed or restate the image in your reply.";

/// Request parameters for one image generation call.
#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImageGenerationInput {
    /// Image description sent to the provider verbatim after trimming surrounding whitespace.
    pub prompt: String,
    /// Request a transparent background; omitted means the provider default (opaque).
    #[serde(default)]
    pub transparent_background: bool,
}

/// Tool-owned receipt binding the archived bytes to the request that produced them.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImageGenerationReceipt {
    /// Provider instance that served the request.
    pub provider_id: String,
    /// Image model slug selected from the online directory observation.
    pub model: String,
    /// Trimmed prompt actually sent to the provider.
    pub prompt: String,
    /// Whether a transparent background was requested.
    pub transparent_background: bool,
    /// Media type detected from the returned bytes.
    pub media_type: String,
    /// Raw bytes archived under the shared resource host.
    pub original: pl_core::context::ResourceReference,
    /// Provider-supplied rewritten prompt, when the provider returns one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revised_prompt: Option<String>,
    /// Width of the model-visible variant, absent when the prepared model accepts no image input.
    pub model_width: Option<u32>,
    /// Height of the model-visible variant, absent when the prepared model accepts no image input.
    pub model_height: Option<u32>,
}

/// A Thread-local generator sharing only its immutable HTTP client configuration.
#[derive(Debug)]
pub struct ThreadImageGenerationTool<H> {
    client: ImagesClient,
    model: String,
    provider_id: String,
    media: Arc<H>,
}

impl<H: ToolMediaHost> ThreadImageGenerationTool<H> {
    /// Binds the frozen provider backend, its selected model and the Thread media host.
    pub fn new(client: ImagesClient, model: String, provider_id: String, media: Arc<H>) -> Self {
        Self {
            client,
            model,
            provider_id,
            media,
        }
    }

    /// Stable declaration, independent of conversation state and observed results.
    pub fn declaration() -> pl_protocol::ToolSpec {
        pl_protocol::ToolSpec::function(
            TOOL_IMAGE_GENERATION,
            DESCRIPTION,
            schemars::schema_for!(ImageGenerationInput).to_value(),
        )
    }

    /// Transfers an executor that coexists with other foreground calls and grants no control.
    ///
    /// # Errors
    /// Returns invalid registry identity errors.
    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        Ok(
            Registration::new(TOOL_IMAGE_GENERATION.into(), declaration, self)?
                .foreground_coexisting(),
        )
    }
}

impl<H: ToolMediaHost> Tool for ThreadImageGenerationTool<H> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(failure("unsupported image generation argument encoding"));
        }
        let input: ImageGenerationInput =
            serde_json::from_str(input.content()).map_err(ToolError::new)?;
        let prompt = input.prompt.trim().to_owned();
        if prompt.is_empty() {
            return Err(failure("image generation prompt must not be empty"));
        }
        if prompt.chars().count() > MAX_PROMPT_CHARS {
            return Err(failure("image generation prompt exceeds 8000 characters"));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let generated = self
            .client
            .generate(ImageGenerationRequest {
                model: self.model.clone(),
                prompt: prompt.clone(),
                background: if input.transparent_background {
                    ImageGenerationBackground::Transparent
                } else {
                    ImageGenerationBackground::Opaque
                },
            })
            .await
            .map_err(|error| failure(&format!("image generation failed: {error}")))?;
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let bytes: Arc<[u8]> = generated.bytes.into();
        // The model projection follows the prepared model's advertised image input bounds; a
        // model without image input still receives the archived resource, never a failure.
        let (model_image, model_dimensions) = match image_limits(context.model_projection.as_ref())?
            .filter(|limits| limits.max_count != Some(0))
        {
            Some(limits) => {
                let total_limit = limits.max_total_bytes;
                let original = bytes.clone();
                let normalized = tokio::task::spawn_blocking(move || {
                    crate::image::normalize_tool_image(
                        TOOL_IMAGE_GENERATION,
                        original.to_vec(),
                        None,
                        &limits,
                    )
                    .map_err(ToolError::new)
                })
                .await
                .map_err(ToolError::new)??;
                if total_limit.is_some_and(|limit| normalized.bytes.len() as u64 > limit) {
                    return Err(failure(
                        "generated image exceeds the prepared total-byte limit",
                    ));
                }
                (
                    Some(PreparedToolImage {
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
            .retain(ToolMedia {
                kind: ToolMediaKind::Image,
                bytes: bytes.clone(),
                media_type: generated.media_type.into(),
                model_image,
            })
            .await?;
        retained.reference.verify(&bytes).map_err(ToolError::new)?;
        let payload = OpaquePayload::new(
            IMAGE_GENERATION_RECEIPT_FORMAT,
            IMAGE_GENERATION_RECEIPT_VERSION,
            serde_json::to_string(&ImageGenerationReceipt {
                provider_id: self.provider_id.clone(),
                model: self.model.clone(),
                prompt,
                transparent_background: input.transparent_background,
                media_type: generated.media_type.into(),
                original: retained.reference,
                revised_prompt: generated.revised_prompt,
                model_width: model_dimensions.map(|dimensions| dimensions.0),
                model_height: model_dimensions.map(|dimensions| dimensions.1),
            })
            .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        let mut context = retained.context;
        context.push(ContextContent::Text {
            text: Arc::from(ARCHIVED_NOTE),
        });
        Ok(ToolOutput::new(payload, context))
    }
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_IMAGE_GENERATION, message))
}
