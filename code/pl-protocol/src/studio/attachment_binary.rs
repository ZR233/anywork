//! A producer-less scope over one authorized, pinned original attachment file.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum AttachmentBinaryTarget {
    Draft {
        #[serde(rename = "draftId")]
        draft_id: String,
    },
    Thread {
        #[serde(rename = "threadId")]
        thread_id: String,
        #[serde(rename = "attachmentId")]
        attachment_id: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentBinaryIdentity {
    pub scope_id: String,
    pub runtime_epoch: String,
    pub incarnation: u64,
    pub target: AttachmentBinaryTarget,
}

/// Length comes from the very same open file used by every subsequent block read.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentBinaryOpenReply {
    pub identity: AttachmentBinaryIdentity,
    pub byte_length: i64,
}

/// Temporary caller-owned bytes, not canonical state or a second attachment cache.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttachmentBinaryChunk {
    pub offset: i64,
    pub bytes: Vec<u8>,
    pub next_offset: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OpenDraftBinaryRequest {
    pub draft_id: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OpenThreadBinaryRequest {
    pub thread_id: String,
    pub attachment_id: String,
}
