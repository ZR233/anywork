//! Optional upload capability. Each dialect owns its wire contract, not the invocation loop.
use crate::completion::AttachmentInput;
use crate::protocol::ProtocolEndpoint;
use pl_protocol::PureError;
use std::collections::HashMap;

pub struct FileUploadRequest<'a> {
    pub client: &'a reqwest::Client,
    pub endpoint: &'a ProtocolEndpoint,
    pub model_headers: &'a HashMap<String, String>,
    pub input: &'a AttachmentInput,
    pub bytes: &'a [u8],
    pub now: i64,
}

pub struct UploadedFile {
    pub id: String,
    pub expires_at: i64,
}

/// What the upload boundary knows about a failed submission's remote effect.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UploadFailureOutcome {
    /// The request was not submitted, or the endpoint explicitly rejected it.
    Rejected,
    /// A file may have been created; automatic replay could duplicate the upload.
    Unknown,
}

/// A single upload's error and independently observed submission outcome.
#[derive(Debug)]
pub struct FileUploadFailure {
    pub source: PureError,
    pub outcome: UploadFailureOutcome,
}

impl std::fmt::Display for FileUploadFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Display::fmt(&self.source, formatter)
    }
}

impl std::error::Error for FileUploadFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.source)
    }
}

/// Provider implementation of a single upload attempt.
pub type UploadFile = for<'a> fn(
    FileUploadRequest<'a>,
) -> std::pin::Pin<
    Box<
        dyn std::future::Future<Output = Result<Option<UploadedFile>, FileUploadFailure>>
            + Send
            + 'a,
    >,
>;

/// Registered upload implementation and the revision that isolates its cached file IDs.
#[derive(Debug)]
pub struct FileUploadService {
    pub id: crate::protocol::FileUploadCapability,
    pub cache_revision: &'static str,
    pub upload: UploadFile,
}
