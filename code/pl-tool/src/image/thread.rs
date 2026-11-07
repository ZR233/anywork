//! Workspace images delivered through immutable resources, without product attachment state.
use super::{MAX_SOURCE_BYTES, TOOL_VIEW_IMAGE, ViewImageInput, normalize_tool_image};
use crate::{
    media::{PreparedToolImage, ToolMedia, ToolMediaHost, ToolMediaKind, image_limits},
    workspace_file::{
        WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileStatRequest,
    },
};
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use std::sync::Arc;

/// Versioned receipt format emitted for one archived `view_image` result.
pub const VIEW_IMAGE_RECEIPT_FORMAT: &str = "pl.tool.image";
/// Receipt layout version; changes require an explicit decoder update.
pub const VIEW_IMAGE_RECEIPT_VERSION: u32 = 1;

/// Tool-owned receipt binding the frozen source path to the resource it archived.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ViewImageReceipt {
    /// Caller-supplied workspace path, retained verbatim for display only.
    pub path: String,
    /// Raw source bytes that were archived alongside the model projection.
    pub original: pl_core::context::ResourceReference,
    /// Width of the exact model-visible variant recorded by this receipt.
    pub model_width: u32,
    /// Height of the exact model-visible variant recorded by this receipt.
    pub model_height: u32,
}

/// Decodes the tool-owned receipt, or returns `None` for another producer's payload.
///
/// Owning the format means every version of it must be understood: a payload that claims
/// `VIEW_IMAGE_RECEIPT_FORMAT` but an unknown version is rejected instead of being silently
/// skipped, so an unreadable receipt never degrades into a guessed projection.
///
/// # Errors
/// Rejects an unsupported receipt version, a zero model dimension, malformed receipt content,
/// or invalid retained reference metadata.
pub fn saved_view_image_receipt(
    payload: &OpaquePayload,
) -> Result<Option<ViewImageReceipt>, ToolError> {
    if payload.format() != VIEW_IMAGE_RECEIPT_FORMAT {
        return Ok(None);
    }
    if payload.version() != VIEW_IMAGE_RECEIPT_VERSION {
        return Err(ToolError::new(std::io::Error::other(format!(
            "unsupported {VIEW_IMAGE_RECEIPT_FORMAT} receipt version {}",
            payload.version()
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

/// A Thread-local reader over its configured backend and persistent resource host.
#[derive(Debug)]
pub struct ThreadViewImageTool<B, H> {
    backend: Arc<B>,
    media: Arc<H>,
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> ThreadViewImageTool<B, H> {
    /// Binds physical reads and durable media to the same Thread installation.
    pub fn new(backend: Arc<B>, media: Arc<H>) -> Self {
        Self { backend, media }
    }
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> pl_agent_tool::typed::TypedTool
    for ThreadViewImageTool<B, H>
{
    const NAME: &'static str = THREAD_VIEW_IMAGE_TOOL_NAME;
    const DESCRIPTION: &'static str = THREAD_VIEW_IMAGE_TOOL_DESCRIPTION;
    type Args = ViewImageInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let limits = image_limits(context.model_projection.as_ref())?
            .filter(|limits| limits.max_count != Some(0))
            .ok_or_else(|| failure("prepared model does not support image input"))?;
        if context.cancellation.is_cancelled() {
            return Err(failure("image read cancelled"));
        }
        let granted = self.backend.for_grant(&context.grant);
        let backend = granted.as_ref().unwrap_or(self.backend.as_ref());
        let stat = backend
            .stat(WorkspaceFileStatRequest {
                path: input.path.clone(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)?;
        if !stat.is_file {
            return Err(failure("image source is not a regular file"));
        }
        let bytes: Arc<[u8]> = backend
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: input.path.clone(),
                cwd: None,
                max_bytes: MAX_SOURCE_BYTES,
            })
            .await
            .map_err(ToolError::new)?
            .into();
        if bytes.len() > MAX_SOURCE_BYTES {
            return Err(failure("image source exceeds the byte limit"));
        }
        if context.cancellation.is_cancelled() {
            return Err(failure("image read cancelled"));
        }
        let original = bytes.clone();
        let total_limit = limits.max_total_bytes;
        let (source_type, normalized) = tokio::task::spawn_blocking(move || {
            let format = image::guess_format(&original).map_err(ToolError::new)?;
            let source_type =
                super::media_type(format).ok_or_else(|| failure("unsupported image header"))?;
            let normalized =
                normalize_tool_image(TOOL_VIEW_IMAGE, original.to_vec(), None, &limits)
                    .map_err(ToolError::new)?;
            Ok::<_, ToolError>((source_type, normalized))
        })
        .await
        .map_err(ToolError::new)??;
        if total_limit.is_some_and(|limit| normalized.bytes.len() as u64 > limit) {
            return Err(failure("image exceeds the prepared total-byte limit"));
        }
        if context.cancellation.is_cancelled() {
            return Err(failure("image preparation cancelled"));
        }
        let dimensions = (normalized.width, normalized.height);
        let retained = self
            .media
            .retain(ToolMedia {
                kind: ToolMediaKind::Image,
                bytes: bytes.clone(),
                media_type: source_type.into(),
                model_image: Some(PreparedToolImage {
                    bytes: normalized.bytes.into(),
                    media_type: normalized.media_type,
                }),
            })
            .await?;
        retained.reference.verify(&bytes).map_err(ToolError::new)?;
        let payload = OpaquePayload::new(
            VIEW_IMAGE_RECEIPT_FORMAT,
            VIEW_IMAGE_RECEIPT_VERSION,
            serde_json::to_string(&ViewImageReceipt {
                path: input.path,
                original: retained.reference,
                model_width: dimensions.0,
                model_height: dimensions.1,
            })
            .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(payload, retained.context))
    }
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_VIEW_IMAGE, message))
}

pub fn thread_view_image_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        THREAD_VIEW_IMAGE_TOOL_NAME,
        THREAD_VIEW_IMAGE_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<ViewImageInput>(),
    )
    .expect("static tool definition")
}

const THREAD_VIEW_IMAGE_TOOL_NAME: &str = crate::image::TOOL_VIEW_IMAGE;
const THREAD_VIEW_IMAGE_TOOL_DESCRIPTION: &str = "Open a local or SSH workspace image so you can inspect screenshots and other image files. Pass its path in the current workspace; SSH paths must be workspace-relative POSIX paths. The image is retained for model context and history replay. Requires image input support from the current model.";
