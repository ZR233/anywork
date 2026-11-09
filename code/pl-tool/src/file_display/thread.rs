use super::{
    FILE_DISPLAY_FORMAT, FILE_DISPLAY_VERSION, FileDisplayOrigin, FileDisplayReceipt,
    FileDisplayResult, ShowFileSource, ShowFilesInput, TOOL_SHOW_FILES, failure,
};
use crate::{
    media::{ToolMedia, ToolMediaHost, ToolMediaKind},
    workspace_file::{
        WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileStatRequest,
    },
};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_protocol::AttachmentModality;
use std::sync::Arc;

const MAX_SOURCE_BYTES: usize = 50 * 1024 * 1024;

#[derive(Debug)]
pub struct ThreadShowFilesTool<B, H> {
    backend: Arc<B>,
    media: Arc<H>,
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> ThreadShowFilesTool<B, H> {
    pub fn new(backend: Arc<B>, media: Arc<H>) -> Self {
        Self { backend, media }
    }

    async fn workspace_file(
        &self,
        path: &str,
        context: &CallContext,
    ) -> Result<FileDisplayResult, ToolError> {
        let granted = self.backend.for_grant(&context.grant);
        let backend = granted.as_ref().unwrap_or(self.backend.as_ref());
        let stat = backend
            .stat(WorkspaceFileStatRequest {
                path: path.into(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)?;
        if !stat.is_file {
            return Err(failure("display source is not a regular file"));
        }
        if stat.len.is_some_and(|len| len > MAX_SOURCE_BYTES as u64) {
            return Err(failure("display source exceeds the 50 MiB limit"));
        }
        // Only the physical backend can identify a source as local. A remote path is never
        // interpreted relative to the host process or transformed into a local locator.
        let origin = match backend
            .local_file_path(WorkspaceFileStatRequest {
                path: path.into(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)?
        {
            Some(path) => FileDisplayOrigin::Local { path },
            None => FileDisplayOrigin::Remote,
        };
        let bytes = backend
            .read_bytes(WorkspaceFileReadBytesRequest {
                // Freeze a validated local target instead of resolving the caller's symlink
                // again and potentially archiving a different file under the old locator.
                path: match &origin {
                    FileDisplayOrigin::Local { path } => path.clone(),
                    _ => path.into(),
                },
                cwd: None,
                max_bytes: MAX_SOURCE_BYTES,
            })
            .await
            .map_err(ToolError::new)?;
        if bytes.len() > MAX_SOURCE_BYTES {
            return Err(failure("display source exceeds the 50 MiB limit"));
        }
        let name = filename(path);
        let image_expected = matches!(
            extension(&name).as_str(),
            "png" | "jpg" | "jpeg" | "gif" | "webp"
        );
        let (bytes, media_type, modality) = tokio::task::spawn_blocking(move || {
            // Preview only formats supported by the existing decoder. Other image formats
            // remain ordinary downloadable files, without claiming that they can be decoded.
            let image_format = image::guess_format(&bytes)
                .ok()
                .filter(|format| crate::image::media_type(*format).is_some());
            let (media_type, modality) = if image_expected || image_format.is_some() {
                let format = image_format.ok_or_else(|| failure("unsupported image header"))?;
                // Header recognition alone must not advertise a corrupt image as previewable.
                image::ImageReader::with_format(std::io::Cursor::new(&bytes), format)
                    .decode()
                    .map_err(ToolError::new)?;
                let media_type = crate::image::media_type(format)
                    .ok_or_else(|| failure("unsupported image format"))?;
                (media_type.to_owned(), AttachmentModality::Image)
            } else {
                file_type(&name)
            };
            Ok::<_, ToolError>((bytes, media_type, modality))
        })
        .await
        .map_err(ToolError::new)??;
        if context.cancellation.is_cancelled() {
            return Err(failure("file display cancelled"));
        }
        let bytes: Arc<[u8]> = bytes.into();
        let retained = self
            .media
            .retain(ToolMedia {
                kind: if modality == AttachmentModality::Image {
                    ToolMediaKind::Image
                } else {
                    ToolMediaKind::Blob
                },
                bytes: bytes.clone(),
                media_type,
                model_image: None,
            })
            .await?;
        retained.reference.verify(&bytes).map_err(ToolError::new)?;
        // Host media context is deliberately ignored: this operation is not model media input.
        Ok(FileDisplayResult::Ready {
            resource: retained.reference,
            filename: filename(path),
            modality,
            origin,
        })
    }
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> pl_agent_tool::typed::TypedTool
    for ThreadShowFilesTool<B, H>
{
    const NAME: &'static str = TOOL_SHOW_FILES;
    const DESCRIPTION: &'static str = super::DESCRIPTION;
    type Args = ShowFilesInput;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    async fn execute(
        &self,
        input: ShowFilesInput,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let caption = input
            .caption
            .as_deref()
            .map(str::trim)
            .filter(|caption| !caption.is_empty())
            .map(str::to_owned);
        if input.files.is_empty() {
            return Err(failure("files must not be empty"));
        }
        if caption
            .as_ref()
            .is_some_and(|caption| caption.chars().count() > 240)
        {
            return Err(failure("caption exceeds 240 characters"));
        }
        if input.files.iter().any(|source| match source {
            ShowFileSource::Workspace { path } => path.trim().is_empty(),
            ShowFileSource::Attachment { attachment_id } => attachment_id.trim().is_empty(),
        }) {
            return Err(failure("file selectors must not be empty"));
        }
        let mut files = Vec::with_capacity(input.files.len());
        for source in input.files {
            if context.cancellation.is_cancelled() {
                return Err(failure("file display cancelled"));
            }
            let (name, result) = match source {
                ShowFileSource::Workspace { path } => {
                    (filename(&path), self.workspace_file(&path, &context).await)
                }
                ShowFileSource::Attachment { attachment_id } => (
                    attachment_id.chars().take(255).collect(),
                    super::archive::archived_file(&context, &attachment_id).await,
                ),
            };
            files.push(match result {
                Ok(file) => file,
                Err(error) => FileDisplayResult::Failed {
                    filename: name,
                    message: error.to_string().chars().take(512).collect(),
                },
            });
        }
        let ready = files
            .iter()
            .filter(|file| matches!(file, FileDisplayResult::Ready { .. }))
            .count();
        let mut model_context = vec![ContextContent::Text {
            text: format!(
                "File display archived: {ready} ready, {} failed.",
                files.len() - ready
            )
            .into(),
        }];
        for file in &files {
            if let FileDisplayResult::Ready { resource, .. } = file {
                model_context.push(ContextContent::Resource {
                    reference: resource.clone(),
                });
            }
        }
        let payload = OpaquePayload::new(
            FILE_DISPLAY_FORMAT,
            FILE_DISPLAY_VERSION,
            serde_json::to_string(&FileDisplayReceipt { caption, files })
                .map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(payload, model_context))
    }
}

pub(super) fn filename(path: &str) -> String {
    path.rsplit(['/', '\\'])
        .find(|part| !part.is_empty())
        .unwrap_or("file")
        .to_owned()
}

fn extension(filename: &str) -> String {
    filename
        .rsplit_once('.')
        .map(|(_, ext)| ext.to_ascii_lowercase())
        .unwrap_or_default()
}

fn file_type(filename: &str) -> (String, AttachmentModality) {
    let (mime, modality) = match extension(filename).as_str() {
        "pdf" => ("application/pdf", AttachmentModality::File),
        "txt" | "log" => ("text/plain", AttachmentModality::File),
        "md" => ("text/markdown", AttachmentModality::File),
        "json" => ("application/json", AttachmentModality::File),
        "csv" => ("text/csv", AttachmentModality::File),
        "mp4" => ("video/mp4", AttachmentModality::Video),
        "webm" => ("video/webm", AttachmentModality::Video),
        "mov" => ("video/quicktime", AttachmentModality::Video),
        _ => ("application/octet-stream", AttachmentModality::File),
    };
    (mime.into(), modality)
}
