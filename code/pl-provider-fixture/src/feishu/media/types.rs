//! Public resource controls and bounded, content-free observations.

use serde::{Deserialize, Serialize};

/// Conservative decimal 30 MB upload/resource limit. Not an image API limit.
pub const MAX_FILE_BYTES: usize = 30_000_000;
pub const MAX_RESOURCE_COUNT: usize = 64;
pub const MAX_RETAINED_BYTES: usize = 120_000_000;
pub const MAX_MEDIA_REQUESTS: usize = 512;
pub const MAX_MEDIA_IN_FLIGHT: usize = 4;
pub const MAX_SCRIPT_STEPS: usize = 64;

/// Official upload `file_type`. The fixture does not inspect or transcode codecs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FileType {
    Opus,
    Mp4,
    Pdf,
    Doc,
    Xls,
    Ppt,
    Stream,
}

impl FileType {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "opus" => Some(Self::Opus),
            "mp4" => Some(Self::Mp4),
            "pdf" => Some(Self::Pdf),
            "doc" => Some(Self::Doc),
            "xls" => Some(Self::Xls),
            "ppt" => Some(Self::Ppt),
            "stream" => Some(Self::Stream),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ResourceKind {
    Image,
    File,
    Audio,
    Media,
}

impl ResourceKind {
    pub(crate) fn download_type(self) -> ResourceDownloadType {
        match self {
            Self::Image => ResourceDownloadType::Image,
            Self::File | Self::Audio | Self::Media => ResourceDownloadType::File,
        }
    }
}

/// Official resource-download query, not the inbound message kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ResourceDownloadType {
    Image,
    File,
}

/// Owned synthetic bytes bound to exactly this inbound message/key.
/// Registration never creates a product event, trust entry, or thread.
#[derive(Clone)]
pub struct SyntheticResource {
    pub message_id: String,
    pub file_key: String,
    pub kind: ResourceKind,
    pub file_name: String,
    pub mime_type: String,
    pub bytes: Vec<u8>,
}

impl std::fmt::Debug for SyntheticResource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SyntheticResource")
            .field("message_id", &self.message_id)
            .field("file_key", &self.file_key)
            .field("kind", &self.kind)
            .field("file_name", &self.file_name)
            .field("mime_type", &self.mime_type)
            .field("byte_len", &self.bytes.len())
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum ResourceOrigin {
    Synthetic {
        message_id: String,
    },
    Upload {
        file_type: FileType,
        duration: Option<u64>,
    },
}

/// No file bytes or bearer credentials are retained in evidence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceSummary {
    pub file_key: String,
    pub kind: ResourceKind,
    pub file_name: String,
    pub mime_type: String,
    pub byte_len: usize,
    pub sha256: String,
    pub origin: ResourceOrigin,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum UploadDisposition {
    Succeed,
    Reject {
        code: i32,
        msg: String,
    },
    /// Valid bytes are stored, then a broken response body loses the file key.
    AcceptThenDrop,
    /// Wait before storing; explicit release succeeds, shutdown stores nothing.
    Hang,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum ResourceDownloadDisposition {
    Succeed,
    Reject {
        code: i32,
        msg: String,
    },
    /// Prepare no response bytes and terminate the response body with an error.
    AcceptThenDrop,
    Hang,
    /// Prepare at most this prefix, then fail the stream (not a valid full file).
    Disconnect {
        after_bytes: usize,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UploadOutcome {
    Receiving,
    Invalid,
    Waiting,
    Rejected,
    Stored,
    StoredResponseDropped,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadObservation {
    /// Index into the peer's ordered RecordedCall list (zero based).
    pub call_index: usize,
    pub file_type: Option<FileType>,
    pub file_name: Option<String>,
    pub byte_len: Option<usize>,
    pub sha256: Option<String>,
    pub file_key: Option<String>,
    pub disposition: Option<UploadDisposition>,
    pub outcome: UploadOutcome,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ResourceDownloadOutcome {
    Invalid,
    Waiting,
    Rejected,
    /// Bytes prepared by the peer, not proof the client received them.
    ResponsePrepared,
    ResponseInterrupted,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceDownloadObservation {
    pub call_index: usize,
    pub message_id: String,
    pub file_key: String,
    pub resource_type: Option<ResourceDownloadType>,
    pub resource: Option<ResourceSummary>,
    pub disposition: Option<ResourceDownloadDisposition>,
    pub outcome: ResourceDownloadOutcome,
    /// Planned body prefix; a transport failure does not prove delivery.
    pub prepared_bytes: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaStatus {
    pub resources: usize,
    pub retained_bytes: usize,
    pub requests: usize,
    pub in_flight: usize,
    pub request_budget_exhausted: bool,
}
