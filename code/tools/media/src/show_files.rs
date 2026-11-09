//! Ordered file display without product history, resources, or model context.
use pl_agent_tool::typed::TypedTool;
use pl_tool_media_support::{CancellationToken, Media, MediaHost, MediaKind};
use std::{error::Error, fmt, future::Future, marker::PhantomData, sync::Arc};

pub const NAME: &str = "show_files";
pub const DESCRIPTION: &str = "Display an ordered selection of workspace files or this Thread's archived attachments to the user. Workspace files are archived exactly (maximum 50 MiB each); partial failures are reported in order. This does not read file contents into model context or require image input support. Use view_image to inspect an image yourself. Optional caption is trimmed and limited to 240 characters.";
pub const MAX_SOURCE_BYTES: usize = 50 * 1024 * 1024;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Input {
    pub files: Vec<Source>,
    pub caption: Option<String>,
}

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum Source {
    Workspace { path: String },
    Attachment { attachment_id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Modality {
    Image,
    Video,
    File,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Origin {
    Local { path: String },
    Remote,
    Archive,
}

#[derive(Debug, serde::Serialize)]
pub struct File<R> {
    pub resource: R,
    pub filename: String,
    pub modality: Modality,
    pub origin: Origin,
}

#[derive(Debug, serde::Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum FileResult<R> {
    Ready(File<R>),
    Failed { filename: String, message: String },
}

#[derive(Debug, serde::Serialize)]
pub struct Output<R> {
    pub caption: Option<String>,
    pub files: Vec<FileResult<R>>,
}

pub struct FileStat {
    pub is_file: bool,
    pub len: Option<u64>,
}

/// A host-frozen, per-call capability. Each operation enforces the same grant.
/// Archived lookup proves membership and returns validated, already retained resources.
pub trait FileSource: Send + Sync + 'static {
    type Reference: Send + Sync + 'static;
    type Error: Error + Send + Sync + 'static;

    fn stat(&self, path: &str) -> impl Future<Output = Result<FileStat, Self::Error>> + Send;
    /// Only a trusted physical backend may return a verified local absolute locator.
    fn local_file_path(
        &self,
        path: &str,
    ) -> impl Future<Output = Result<Option<String>, Self::Error>> + Send;
    /// Rejects over-limit files rather than truncating; paths remain subject to the grant.
    fn read_bytes(
        &self,
        path: &str,
        max_bytes: usize,
    ) -> impl Future<Output = Result<Arc<[u8]>, Self::Error>> + Send;
    fn archived_file(
        &self,
        id: &str,
    ) -> impl Future<Output = Result<File<Self::Reference>, Self::Error>> + Send;
}

pub struct Context<S> {
    pub source: S,
    pub cancellation: CancellationToken,
}

/// Safe diagnostics do not expose a host's private error chain or Debug output.
pub struct DisplayError {
    message: String,
    original: Option<Box<dyn Error + Send + Sync>>,
}

impl DisplayError {
    fn invalid(message: &str) -> Self {
        Self {
            message: message.into(),
            original: None,
        }
    }

    fn caused(source: impl Error + Send + Sync + 'static) -> Self {
        Self {
            message: source.to_string(),
            original: Some(Box::new(source)),
        }
    }

    /// Trusted host recovery, not a public diagnostic/source-chain representation.
    pub fn into_original(self) -> Result<Box<dyn Error + Send + Sync>, Self> {
        match self.original {
            Some(source) => Ok(source),
            None => Err(self),
        }
    }
}

impl fmt::Display for DisplayError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl fmt::Debug for DisplayError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DisplayError")
            .field("message", &self.message)
            .finish_non_exhaustive()
    }
}

impl Error for DisplayError {}

pub struct ShowFiles<S, H> {
    media: Arc<H>,
    source: PhantomData<fn() -> S>,
}

impl<S, H> ShowFiles<S, H> {
    pub fn new(media: Arc<H>) -> Self {
        Self {
            media,
            source: PhantomData,
        }
    }
}

impl<S: FileSource, H: MediaHost<Reference = S::Reference>> ShowFiles<S, H> {
    async fn workspace_file(
        &self,
        path: &str,
        context: &Context<S>,
    ) -> Result<File<S::Reference>, DisplayError> {
        let stat = context
            .source
            .stat(path)
            .await
            .map_err(DisplayError::caused)?;
        if !stat.is_file {
            return Err(DisplayError::invalid(
                "display source is not a regular file",
            ));
        }
        if stat.len.is_some_and(|len| len > MAX_SOURCE_BYTES as u64) {
            return Err(DisplayError::invalid(
                "display source exceeds the 50 MiB limit",
            ));
        }
        let origin = match context
            .source
            .local_file_path(path)
            .await
            .map_err(DisplayError::caused)?
        {
            Some(path) => Origin::Local { path },
            None => Origin::Remote,
        };
        // Freeze a verified local target instead of resolving the caller's symlink again.
        let read_path = match &origin {
            Origin::Local { path } => path.as_str(),
            _ => path,
        };
        let bytes = context
            .source
            .read_bytes(read_path, MAX_SOURCE_BYTES)
            .await
            .map_err(DisplayError::caused)?;
        if bytes.len() > MAX_SOURCE_BYTES {
            return Err(DisplayError::invalid(
                "display source exceeds the 50 MiB limit",
            ));
        }
        let name = filename(path);
        let classification_name = name.clone();
        let (bytes, media_type, modality) = tokio::task::spawn_blocking(move || {
            let image_expected = matches!(
                extension(&classification_name).as_str(),
                "png" | "jpg" | "jpeg" | "gif" | "webp"
            );
            let image_format = image::guess_format(&bytes)
                .ok()
                .filter(|format| pl_tool_media_support::media_type(*format).is_some());
            let (media_type, modality) = if image_expected || image_format.is_some() {
                let format = image_format
                    .ok_or_else(|| DisplayError::invalid("unsupported image header"))?;
                image::ImageReader::with_format(std::io::Cursor::new(&bytes), format)
                    .decode()
                    .map_err(DisplayError::caused)?;
                let media_type = pl_tool_media_support::media_type(format)
                    .ok_or_else(|| DisplayError::invalid("unsupported image format"))?;
                (media_type.to_owned(), Modality::Image)
            } else {
                file_type(&classification_name)
            };
            Ok::<_, DisplayError>((bytes, media_type, modality))
        })
        .await
        .map_err(DisplayError::caused)??;
        if context.cancellation.is_cancelled() {
            return Err(DisplayError::invalid("file display cancelled"));
        }
        let retained = self
            .media
            .retain(Media {
                kind: if modality == Modality::Image {
                    MediaKind::Image
                } else {
                    MediaKind::Blob
                },
                bytes,
                media_type,
                model_image: None,
            })
            .await
            .map_err(DisplayError::caused)?;
        // A display is not model input: deliberately discard the host's model projection.
        Ok(File {
            resource: retained.reference,
            filename: name,
            modality,
            origin,
        })
    }
}

impl<S: FileSource, H: MediaHost<Reference = S::Reference>> TypedTool for ShowFiles<S, H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Input;
    type Context = Context<S>;
    type Output = Output<S::Reference>;
    type Error = DisplayError;

    async fn execute(
        &self,
        input: Input,
        context: Context<S>,
    ) -> Result<Self::Output, DisplayError> {
        let caption = input
            .caption
            .as_deref()
            .map(str::trim)
            .filter(|caption| !caption.is_empty())
            .map(str::to_owned);
        if input.files.is_empty() {
            return Err(DisplayError::invalid("files must not be empty"));
        }
        if caption
            .as_ref()
            .is_some_and(|caption| caption.chars().count() > 240)
        {
            return Err(DisplayError::invalid("caption exceeds 240 characters"));
        }
        if input.files.iter().any(|source| match source {
            Source::Workspace { path } => path.trim().is_empty(),
            Source::Attachment { attachment_id } => attachment_id.trim().is_empty(),
        }) {
            return Err(DisplayError::invalid("file selectors must not be empty"));
        }
        let mut files = Vec::with_capacity(input.files.len());
        for source in input.files {
            if context.cancellation.is_cancelled() {
                return Err(DisplayError::invalid("file display cancelled"));
            }
            let (name, result) = match source {
                Source::Workspace { path } => {
                    (filename(&path), self.workspace_file(&path, &context).await)
                }
                Source::Attachment { attachment_id } => (
                    attachment_id.chars().take(255).collect(),
                    context
                        .source
                        .archived_file(&attachment_id)
                        .await
                        .map_err(DisplayError::caused),
                ),
            };
            files.push(match result {
                Ok(file) => FileResult::Ready(file),
                Err(error) => FileResult::Failed {
                    filename: name,
                    message: error.to_string().chars().take(512).collect(),
                },
            });
        }
        Ok(Output { caption, files })
    }
}

pub fn filename(path: &str) -> String {
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

fn file_type(filename: &str) -> (String, Modality) {
    let (mime, modality) = match extension(filename).as_str() {
        "pdf" => ("application/pdf", Modality::File),
        "txt" | "log" => ("text/plain", Modality::File),
        "md" => ("text/markdown", Modality::File),
        "json" => ("application/json", Modality::File),
        "csv" => ("text/csv", Modality::File),
        "mp4" => ("video/mp4", Modality::Video),
        "webm" => ("video/webm", Modality::Video),
        "mov" => ("video/quicktime", Modality::Video),
        _ => ("application/octet-stream", Modality::File),
    };
    (mime.into(), modality)
}
