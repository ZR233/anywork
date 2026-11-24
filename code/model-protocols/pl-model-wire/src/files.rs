//! Optional upload capability. Each dialect owns its wire contract, not the invocation loop.
use crate::completion::AttachmentInput;
use crate::protocol::ProtocolEndpoint;
use pl_protocol::Result;
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

/// Provider implementation of a single upload attempt.
pub type UploadFile = for<'a> fn(
    FileUploadRequest<'a>,
) -> std::pin::Pin<
    Box<dyn std::future::Future<Output = Result<Option<UploadedFile>>> + Send + 'a>,
>;

/// Registered upload implementation and the revision that isolates its cached file IDs.
#[derive(Debug)]
pub struct FileUploadService {
    pub id: crate::protocol::FileUploadCapability,
    pub cache_revision: &'static str,
    pub upload: UploadFile,
}
