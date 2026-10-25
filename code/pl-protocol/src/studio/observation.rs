//! Identity and cleanup values shared by concrete product and Thread observations.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigProjectionStamp {
    pub settings_revision: u64,
    pub model_catalog_revision: u64,
    pub closing: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum CleanupRecovery {
    AwaitCompletion,
    RetryClose,
    Terminal,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FeedCloseIssue {
    pub diagnostic: StudioShutdownIssue,
    pub recovery: CleanupRecovery,
}

/// Shutdown diagnostics retain their original retryability independently of cleanup capability.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioShutdownIssue {
    pub stage: String,
    pub code: String,
    pub message: String,
    pub retryable: bool,
    pub correlation_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum FeedCloseOutcome {
    Clean,
    Unresolved { issues: Vec<FeedCloseIssue> },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FeedCloseReport {
    pub feed_id: String,
    pub outcome: FeedCloseOutcome,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ReadText {
    Inline { text: String },
    Deferred { field_id: u64, utf8_bytes: u64 },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TextChunk {
    pub field_id: u64,
    pub offset: u64,
    pub text: String,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TypedListRef {
    pub list_id: u64,
    pub total: u64,
}
