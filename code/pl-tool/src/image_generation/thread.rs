//! Selected ImagesClient capability and historical generation receipts for Anywork.
use super::{IMAGE_GENERATION_RECEIPT_FORMAT, IMAGE_GENERATION_RECEIPT_VERSION};
use crate::media::{DomainMediaHost, ToolMediaHost, domain_error, image_limits};
use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_model::protocol::images::{ImageGenerationBackground, ImageGenerationRequest, ImagesClient};
pub use pl_tool_media::generate_image::Input as ImageGenerationInput;
use std::sync::Arc;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImageGenerationReceipt {
    pub account_id: String,
    pub model: String,
    pub prompt: String,
    pub transparent_background: bool,
    pub media_type: String,
    pub original: pl_core::context::ResourceReference,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revised_prompt: Option<String>,
    pub model_width: Option<u32>,
    pub model_height: Option<u32>,
}

#[derive(Debug, Clone)]
struct SelectedGenerator {
    client: Arc<ImagesClient>,
    model: String,
}

impl pl_tool_media::generate_image::ImageGenerator for SelectedGenerator {
    type Error = pl_model::protocol::images::ImagesError;

    async fn generate(
        &self,
        prompt: String,
        transparent: bool,
    ) -> Result<pl_tool_media::generate_image::GeneratedImage, Self::Error> {
        let image = self
            .client
            .generate(ImageGenerationRequest {
                model: self.model.clone(),
                prompt,
                background: if transparent {
                    ImageGenerationBackground::Transparent
                } else {
                    ImageGenerationBackground::Opaque
                },
            })
            .await?;
        Ok(pl_tool_media::generate_image::GeneratedImage {
            bytes: image.bytes.into(),
            media_type: image.media_type.into(),
            revised_prompt: image.revised_prompt,
        })
    }
}

#[derive(Debug)]
pub struct ThreadImageGenerationTool<H> {
    generator: SelectedGenerator,
    account_id: String,
    media: Arc<H>,
}

impl<H: ToolMediaHost> ThreadImageGenerationTool<H> {
    pub fn new(client: ImagesClient, model: String, account_id: String, media: Arc<H>) -> Self {
        Self {
            generator: SelectedGenerator {
                client: Arc::new(client),
                model,
            },
            account_id,
            media,
        }
    }

    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::ToolDefinition::json(
            pl_tool_media::generate_image::NAME,
            pl_tool_media::generate_image::DESCRIPTION,
            pl_agent_tool::typed::input_schema_for::<ImageGenerationInput>(),
        )
        .expect("static tool definition")
    }
}

impl<H: ToolMediaHost> TypedTool for ThreadImageGenerationTool<H> {
    const NAME: &'static str = pl_tool_media::generate_image::NAME;
    const DESCRIPTION: &'static str = pl_tool_media::generate_image::DESCRIPTION;
    type Args = ImageGenerationInput;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let context = pl_tool_media_support::ImageContext {
            limits: image_limits(context.model_projection.as_ref())?,
            cancellation: context.cancellation,
        };
        let tool = pl_tool_media::generate_image::GenerateImage::new(
            self.generator.clone(),
            Arc::new(DomainMediaHost(self.media.clone())),
        );
        let output = tool
            .execute(input, context)
            .await
            .map_err(generation_error)?;
        let payload = OpaquePayload::new(
            IMAGE_GENERATION_RECEIPT_FORMAT,
            IMAGE_GENERATION_RECEIPT_VERSION,
            serde_json::to_string(&ImageGenerationReceipt {
                account_id: self.account_id.clone(),
                model: self.generator.model.clone(),
                prompt: output.prompt,
                transparent_background: output.transparent_background,
                media_type: output.media_type,
                original: output.retained.reference,
                revised_prompt: output.revised_prompt,
                model_width: output.model_dimensions.map(|dimensions| dimensions.0),
                model_height: output.model_dimensions.map(|dimensions| dimensions.1),
            })
            .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        let mut context = output.retained.projection;
        context.push(ContextContent::Text {
            text: pl_tool_media::generate_image::ARCHIVED_NOTE.into(),
        });
        Ok(ToolOutput::new(payload, context))
    }
}

fn generation_error(error: pl_tool_media::generate_image::GenerationError) -> ToolError {
    use base64::{Engine, engine::general_purpose::STANDARD};
    let source = domain_error(error.source);
    let Some(image) = error.observed else {
        return source;
    };
    let payload = OpaquePayload::new(
        "pl.tool.image-generation-unarchived",
        1,
        serde_json::json!({
            "mediaType": image.media_type, "data": STANDARD.encode(&image.bytes),
            "revisedPrompt": image.revised_prompt,
        })
        .to_string(),
    )
    .expect("static image generation observation format");
    source.with_output(ToolOutput::new(payload, vec![ContextContent::Text {
        text: "Generated image was received but could not be archived; the service was not called again.".into(),
    }]))
}
