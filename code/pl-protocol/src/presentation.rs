//! Product presentation snapshots, independent of atomic completion sequence.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    ChatAtom, ChatFactPosition, ChatSourceId,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};

pub const PRESENTATION_VERSION: u32 = 6;
pub const TIMELINE_READER_PROTOCOL_VERSION: u32 = 1;

/// A capability-local position, unrelated to persisted block or completion order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct ViewCursor(pub String);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OpenTimeline {
    pub reader_id: String,
    pub presentation_version: u32,
    pub reader_protocol_version: u32,
    pub initial_cursor: ViewCursor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum HistoryPlacement {
    Set,
    Append,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryDelta {
    pub placement: HistoryPlacement,
    pub from_order: Option<u64>,
    pub through_order: u64,
    pub blocks: Vec<DisplayBlock>,
    pub before: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TailSnapshot {
    pub revision: u64,
    pub layout_revision: u64,
    pub ready_frontier: u64,
    pub execution_present: bool,
    pub current_work_id: Option<String>,
    pub blocks: Vec<LiveDisplayBlock>,
    pub older: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum TailUpdate {
    Keep,
    Replace {
        snapshot: TailSnapshot,
    },
    Status {
        base_layout_revision: u64,
        revision: u64,
        current_work_id: Option<String>,
        thinking_summary: Option<String>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ViewUpdate {
    pub presentation_version: u32,
    pub reader_protocol_version: u32,
    pub after: ViewCursor,
    pub next: ViewCursor,
    pub history: HistoryDelta,
    pub tail: TailUpdate,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelinePage {
    pub presentation_version: u32,
    pub database_id: String,
    pub ceiling: u64,
    pub blocks: Vec<DisplayBlock>,
    pub before: Option<String>,
}

pub fn validate_timeline_versions(presentation: u32, reader: u32) -> Result<(), StudioError> {
    if presentation == PRESENTATION_VERSION && reader == TIMELINE_READER_PROTOCOL_VERSION {
        return Ok(());
    }
    Err(StudioError::new(
        StudioErrorCode::Protocol,
        "Unsupported timeline reader protocol",
        false,
    )
    .with_reason(
        StudioErrorReason::ProtocolVersionMismatch,
        serde_json::Value::Null,
    ))
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisplayBlockRef {
    pub database_id: String,
    pub block_id: String,
}

/// The Work block's creation-to-boundary interval, in Unix seconds.
/// Imported snapshots without group-level clock evidence retain unknown timestamps.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkTiming {
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
}

/// Indirection keeps queued heads compact without changing the serialized body.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum DisplayBlockBody {
    Work {
        timing: WorkTiming,
        members: DisplayBlockRef,
    },
    Single {
        record: Box<DisplayRecord>,
        visibility: SingleVisibility,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum SingleVisibility {
    Content,
    FinalEmptyAfterContent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisplayRecord {
    pub atom: ChatAtom,
    pub start_fact: Option<ChatFactPosition>,
    pub end_fact: Option<ChatFactPosition>,
    pub content_source: DisplayContentSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum DisplayContentSource {
    CurrentAtom,
    FrozenObservation {
        captured_at: Option<i64>,
        available: bool,
    },
    CompletedOriginal {
        completion_id: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum DisplayBlockState {
    Open,
    Sealed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisplayBlock {
    pub id: String,
    pub block_order: u64,
    pub body: DisplayBlockBody,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LiveDisplayBlock {
    pub id: String,
    pub block_order: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<ChatSourceId>,
    pub body: DisplayBlockBody,
    pub state: DisplayBlockState,
    pub has_unfinished_members: bool,
    pub thinking_summary: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum DisplayMemberWindow {
    Latest,
    Before { member_order: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisplayMemberHead {
    pub member_key: String,
    pub member_order: u64,
    pub record: DisplayRecord,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisplayMemberPage {
    pub block: DisplayBlockRef,
    pub revision: u64,
    pub sealed: bool,
    pub entries: Vec<DisplayMemberHead>,
    pub before: Option<u64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn work_heads_do_not_reserve_an_inline_single_atom() {
        assert!(
            std::mem::size_of::<DisplayBlockBody>() < std::mem::size_of::<ChatAtom>(),
            "lightweight Work heads must not reserve an inline Single atom"
        );
    }

    #[test]
    fn versions_are_explicit_and_old_clients_are_rejected() {
        assert!(validate_timeline_versions(6, 1).is_ok());
        for (presentation, reader) in [(5, 1), (6, 0), (6, 2)] {
            assert_eq!(
                validate_timeline_versions(presentation, reader)
                    .unwrap_err()
                    .reason(),
                Some("protocolVersionMismatch")
            );
        }
        assert!(
            serde_json::from_value::<OpenTimeline>(serde_json::json!({
                "readerId": "reader", "presentationVersion": 6, "initialCursor": "C0"
            }))
            .is_err()
        );
    }

    #[test]
    fn keep_and_status_cannot_carry_a_second_tail_window() {
        assert!(
            serde_json::from_value::<TailUpdate>(serde_json::json!({
                "kind": "keep", "snapshot": {}
            }))
            .is_err()
        );
        let update = TailUpdate::Status {
            base_layout_revision: 9,
            revision: 10,
            current_work_id: Some("work".into()),
            thinking_summary: Some("标题".into()),
        };
        assert_eq!(
            serde_json::from_slice::<TailUpdate>(&serde_json::to_vec(&update).unwrap()).unwrap(),
            update
        );
    }
}
