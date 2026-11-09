//! Anywork binding and historical receipts for the independent workspace image reader.
use super::ViewImageInput;
use crate::{
    media::{DomainMediaHost, ToolMediaHost, domain_error, image_limits},
    workspace_file::{
        WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileStatRequest,
    },
};
use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use std::sync::Arc;

pub const VIEW_IMAGE_RECEIPT_FORMAT: &str = "pl.tool.image";
pub const VIEW_IMAGE_RECEIPT_VERSION: u32 = 1;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ViewImageReceipt {
    pub path: String,
    pub original: pl_core::context::ResourceReference,
    pub model_width: u32,
    pub model_height: u32,
}

pub fn saved_view_image_receipt(
    payload: &OpaquePayload,
) -> Result<Option<ViewImageReceipt>, ToolError> {
    if payload.format() != VIEW_IMAGE_RECEIPT_FORMAT {
        return Ok(None);
    }
    if payload.version() != VIEW_IMAGE_RECEIPT_VERSION {
        return Err(ToolError::new(std::io::Error::other(format!(
            "unsupported {VIEW_IMAGE_RECEIPT_FORMAT} receipt version {}",
            payload.version(),
        ))));
    }
    let receipt: ViewImageReceipt =
        serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    receipt.original.validate().map_err(ToolError::new)?;
    if receipt.model_width == 0 || receipt.model_height == 0 {
        return Err(ToolError::new(std::io::Error::other(
            "view_image receipt records a zero model dimension",
        )));
    }
    Ok(Some(receipt))
}

struct AuthorizedImageReader<B>(Arc<B>);
impl<B: WorkspaceFileBackend + 'static> pl_tool_view_image::ImageReader
    for AuthorizedImageReader<B>
{
    type Error = ToolError;

    async fn read(&self, path: String, max_bytes: usize) -> Result<Arc<[u8]>, ToolError> {
        let stat = self
            .0
            .stat(WorkspaceFileStatRequest {
                path: path.clone(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)?;
        if !stat.is_file {
            return Err(ToolError::new(std::io::Error::other(
                "image source is not a regular file",
            )));
        }
        self.0
            .read_bytes(WorkspaceFileReadBytesRequest {
                path,
                cwd: None,
                max_bytes,
            })
            .await
            .map(Into::into)
            .map_err(ToolError::new)
    }
}

#[derive(Debug)]
pub struct ThreadViewImageTool<B, H> {
    backend: Arc<B>,
    media: Arc<H>,
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> ThreadViewImageTool<B, H> {
    pub fn new(backend: Arc<B>, media: Arc<H>) -> Self {
        Self { backend, media }
    }
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> TypedTool for ThreadViewImageTool<B, H> {
    const NAME: &'static str = pl_tool_view_image::NAME;
    const DESCRIPTION: &'static str = pl_tool_view_image::DESCRIPTION;
    type Args = ViewImageInput;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let limits = image_limits(context.model_projection.as_ref())?;
        let reader = AuthorizedImageReader(match self.backend.for_grant(&context.grant) {
            Some(backend) => Arc::new(backend),
            None => self.backend.clone(),
        });
        let tool =
            pl_tool_view_image::ViewImage::new(Arc::new(DomainMediaHost(self.media.clone())));
        let output = tool
            .execute(
                input,
                pl_tool_view_image::Context {
                    reader,
                    image: pl_tool_media_support::ImageContext {
                        limits,
                        cancellation: context.cancellation,
                    },
                },
            )
            .await
            .map_err(|error| domain_error(error.source))?;
        let payload = OpaquePayload::new(
            VIEW_IMAGE_RECEIPT_FORMAT,
            VIEW_IMAGE_RECEIPT_VERSION,
            serde_json::to_string(&ViewImageReceipt {
                path: output.path,
                original: output.retained.reference,
                model_width: output.model_width,
                model_height: output.model_height,
            })
            .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(payload, output.retained.projection))
    }
}

pub fn thread_view_image_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        pl_tool_view_image::NAME,
        pl_tool_view_image::DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<ViewImageInput>(),
    )
    .expect("static tool definition")
}
