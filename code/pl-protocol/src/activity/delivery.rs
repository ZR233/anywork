//! Current activity content transport. Begin/chunks/commit also carry large snapshots without
//! requiring the consumer to withhold transport credit until the final frame.

use serde::{Deserialize, Serialize};

use super::{ThreadActivity, ThreadActivityToolState};

/// Text bytes in one content frame; metadata has its own enclosing frame budget.
pub const ACTIVITY_TEXT_FRAME_BYTES: usize = 64 * 1024;
/// Enclosing metadata budget calibrated to the documented 128k-token / 2,000-member
/// streaming workload; text chunks remain independently bounded at 64 KiB.
pub const ACTIVITY_FRAME_BYTES: usize = 320 * 1024;

/// Stable region identity. Its type, rather than an ID convention or localized label, determines
/// where the SDK applies text.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ActivityTextRegion {
    Reasoning { item_id: String },
    Response { item_id: String },
    ToolArguments { call_id: String },
    ToolOutput { call_id: String, part_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityPartMetadata {
    pub item_id: String,
    pub complete: bool,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityToolMetadata {
    pub call_id: String,
    pub task_id: Option<String>,
    pub name: String,
    pub state: ThreadActivityToolState,
    pub started_at: Option<i64>,
    pub source_order: Option<u64>,
    /// None means unavailable, not an empty body.
    pub arguments_bytes: Option<u64>,
    pub output_bytes: Option<u64>,
    /// Canonical part order, including observed empty parts. None output has no parts.
    pub output_parts: Vec<ActivityToolOutputMetadata>,
    pub wait: Option<crate::ThreadWaitPresentation>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityToolOutputMetadata {
    pub part_id: String,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ActivityTextOperation {
    Append {
        region: ActivityTextRegion,
        text: String,
    },
    Replace {
        region: ActivityTextRegion,
        text: String,
    },
    Remove {
        region: ActivityTextRegion,
    },
}

/// One staged current-state change, independent of the completed-history cursor.
///
/// `base_revision == None` establishes a snapshot; otherwise generation and base must exactly match
/// the repository's committed current state. Each text chunk is accepted into bounded staging and
/// may release its transport credit immediately. Only Commit publishes the prepared current state.
/// Cancellation, a reset or an invalid frame discards the incomplete staging.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ActivityContentFrame {
    Begin {
        generation: String,
        base_revision: Option<u64>,
        revision: u64,
        activity: Option<Box<ThreadActivity>>,
        reasoning: Vec<ActivityPartMetadata>,
        response: Vec<ActivityPartMetadata>,
        tools: Vec<ActivityToolMetadata>,
        /// Expected final text bytes. Admission also charges metadata and staging structure.
        total_bytes: u64,
    },
    Text {
        generation: String,
        revision: u64,
        operations: Vec<ActivityTextOperation>,
    },
    Commit {
        generation: String,
        revision: u64,
    },
}
