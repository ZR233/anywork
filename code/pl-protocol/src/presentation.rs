//! Product presentation snapshots, independent of atomic completion sequence.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    ChatAtom, ChatFactPosition, ChatPlacement, ChatSourceId, ContentRef,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};

pub const PRESENTATION_VERSION: u32 = 3;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisplayBlockRef {
    pub database_id: String,
    pub block_id: String,
}

/// Incremental counters and evidence-based time; never a collection of members.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkSummary {
    pub total: u64,
    pub terminal: u64,
    pub running: u64,
    pub waiting: u64,
    pub failed: u64,
    pub cancelled: u64,
    pub transferred: u64,
    /// Legacy observations whose state at the boundary cannot be proved.
    pub unavailable: u64,
    /// First member creation's reliable effect time, in Unix seconds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<i64>,
    /// A proven display interval. Long-lived open tails do not use wall elapsed time.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub elapsed_ms: Option<u64>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub duration_ms: Option<u64>,
    pub thinking_summary: Option<String>,
    pub thinking_content: Option<ContentRef>,
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
        summary: Box<WorkSummary>,
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
    pub history_pos: u64,
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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LiveDisplayWindow {
    pub revision: u64,
    pub history_through: u64,
    pub execution_present: bool,
    pub current_work_id: Option<String>,
    pub blocks: Vec<LiveDisplayBlock>,
    pub older: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineBatch {
    pub presentation_version: u32,
    pub placement: ChatPlacement,
    pub blocks: Vec<DisplayBlock>,
    pub before: Option<String>,
    pub from_pos: Option<u64>,
    pub through_pos: u64,
    /// None preserves the remaining live blocks during a split handoff.
    pub live: Option<LiveDisplayWindow>,
}

impl TimelineBatch {
    /// Validate one delivery cut without inferring membership or execution state.
    pub fn validate(&self) -> Result<(), StudioError> {
        if self.presentation_version != PRESENTATION_VERSION {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Unsupported timeline presentation version",
                false,
            )
            .with_reason(
                StudioErrorReason::ProtocolVersionMismatch,
                serde_json::Value::Null,
            ));
        }
        let placement_valid = match self.placement {
            ChatPlacement::Set => self.from_pos.is_none() && self.live.is_some(),
            ChatPlacement::Prepend => self.from_pos.is_none() && self.live.is_none(),
            ChatPlacement::Append => {
                self.before.is_none()
                    && self.from_pos.is_some_and(|from| {
                        from < self.through_pos
                            || (from == self.through_pos
                                && self.blocks.is_empty()
                                && self.live.is_some())
                    })
            }
        };
        let mut previous = self.from_pos.unwrap_or(0);
        let mut identities = std::collections::HashSet::new();
        let blocks_valid = self.blocks.iter().all(|block| {
            let ordered = block.history_pos > previous && block.history_pos <= self.through_pos;
            previous = block.history_pos;
            ordered && !block.id.is_empty() && identities.insert(block.id.as_str())
        });
        let live_valid = self.live.as_ref().is_none_or(|live| {
            let mut order = 0;
            let mut current = live.blocks.iter().filter(|block| {
                block.state == DisplayBlockState::Open
                    && matches!(block.body, DisplayBlockBody::Work { .. })
            });
            let current_id = current.next().map(|block| block.id.as_str());
            live.history_through == self.through_pos
                && live.blocks.iter().all(|block| {
                    let ordered = block.block_order > order;
                    order = block.block_order;
                    ordered && !block.id.is_empty() && identities.insert(block.id.as_str())
                })
                && live.current_work_id.as_deref() == current_id
                && current.next().is_none()
        });
        if !placement_valid || !blocks_valid || !live_valid || self.through_pos > i64::MAX as u64 {
            return Err(StudioError::new(
                StudioErrorCode::InvalidArgument,
                "Invalid timeline delivery cut",
                false,
            ));
        }
        Ok(())
    }
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

    fn work(id: &str) -> DisplayBlockBody {
        DisplayBlockBody::Work {
            summary: Box::default(),
            members: DisplayBlockRef {
                database_id: "db".into(),
                block_id: id.into(),
            },
        }
    }

    #[test]
    fn live_source_round_trips_and_missing_old_evidence_stays_unknown() {
        let mut block = LiveDisplayBlock {
            id: "opaque-block".into(),
            block_order: 1,
            source: None,
            body: work("opaque-block"),
            state: DisplayBlockState::Open,
        };
        let old = serde_json::to_value(&block).unwrap();
        assert!(old.get("source").is_none());
        assert_eq!(
            serde_json::from_value::<LiveDisplayBlock>(old)
                .unwrap()
                .source,
            None
        );
        for source in [
            ChatSourceId::ForegroundTurn {
                turn_id: "original-turn".into(),
            },
            ChatSourceId::Input {
                input_id: "independent-input".into(),
            },
            ChatSourceId::BackgroundResult {
                message_id: "background-result".into(),
            },
        ] {
            block.source = Some(source.clone());
            let wire = serde_json::to_value(&block).unwrap();
            assert_eq!(wire["source"], serde_json::to_value(source).unwrap());
            assert_eq!(
                serde_json::from_value::<LiveDisplayBlock>(wire).unwrap(),
                block
            );
        }
    }

    #[test]
    fn work_creation_and_elapsed_evidence_round_trip_without_backfilling_old_heads() {
        let old = serde_json::to_value(WorkSummary::default()).unwrap();
        assert!(old.get("createdAt").is_none());
        assert!(old.get("elapsedMs").is_none());
        let mut summary: WorkSummary = serde_json::from_value(old).unwrap();
        assert_eq!(summary.created_at, None);
        assert_eq!(summary.elapsed_ms, None);
        summary.created_at = Some(1_700_000_000);
        summary.elapsed_ms = Some(125_000);
        let wire = serde_json::to_value(&summary).unwrap();
        assert_eq!(wire["createdAt"], 1_700_000_000_i64);
        assert_eq!(wire["elapsedMs"], 125_000_u64);
        assert_eq!(
            serde_json::from_value::<WorkSummary>(wire).unwrap(),
            summary
        );
    }

    #[test]
    fn body_indirection_keeps_the_flat_wire_shape() {
        let body = work("work");
        let wire = serde_json::to_value(&body).unwrap();
        assert_eq!(
            wire,
            serde_json::json!({
                "kind": "work",
                "summary": WorkSummary::default(),
                "members": {"databaseId": "db", "blockId": "work"},
            })
        );
        assert_eq!(
            serde_json::from_value::<DisplayBlockBody>(wire).unwrap(),
            body
        );
        assert!(
            std::mem::size_of::<DisplayBlockBody>() < std::mem::size_of::<ChatAtom>(),
            "lightweight Work heads must not reserve an inline Single atom"
        );
    }

    #[test]
    fn split_handoff_and_live_only_keep_distinct_delivery_cuts() {
        let mut batch = TimelineBatch {
            presentation_version: PRESENTATION_VERSION,
            placement: ChatPlacement::Append,
            blocks: vec![DisplayBlock {
                id: "g1".into(),
                history_pos: 1,
                body: work("g1"),
            }],
            before: None,
            from_pos: Some(0),
            through_pos: 1,
            live: None,
        };
        assert!(batch.validate().is_ok());
        batch.blocks.clear();
        batch.from_pos = Some(1);
        assert!(batch.validate().is_err());
        batch.live = Some(LiveDisplayWindow {
            revision: 2,
            history_through: 1,
            execution_present: true,
            current_work_id: None,
            blocks: vec![],
            older: None,
        });
        assert!(batch.validate().is_ok());
        batch.live.as_mut().unwrap().history_through = 2;
        assert!(batch.validate().is_err());
    }

    #[test]
    fn published_identity_cannot_reappear_in_live_same_frame() {
        let batch = TimelineBatch {
            presentation_version: PRESENTATION_VERSION,
            placement: ChatPlacement::Set,
            blocks: vec![DisplayBlock {
                id: "g1".into(),
                history_pos: 1,
                body: work("g1"),
            }],
            before: None,
            from_pos: None,
            through_pos: 1,
            live: Some(LiveDisplayWindow {
                revision: 2,
                history_through: 1,
                execution_present: true,
                current_work_id: None,
                blocks: vec![LiveDisplayBlock {
                    id: "g1".into(),
                    block_order: 1,
                    source: None,
                    body: work("g1"),
                    state: DisplayBlockState::Sealed,
                }],
                older: None,
            }),
        };
        assert!(batch.validate().is_err());
    }

    #[test]
    fn canonical_current_work_requires_one_matching_open_work_and_version_three() {
        let mut batch = TimelineBatch {
            presentation_version: PRESENTATION_VERSION,
            placement: ChatPlacement::Set,
            blocks: vec![],
            before: None,
            from_pos: None,
            through_pos: 0,
            live: Some(LiveDisplayWindow {
                revision: 1,
                history_through: 0,
                execution_present: false,
                current_work_id: Some("tail".into()),
                older: None,
                blocks: vec![LiveDisplayBlock {
                    id: "tail".into(),
                    block_order: 1,
                    source: None,
                    body: work("tail"),
                    state: DisplayBlockState::Open,
                }],
            }),
        };
        assert!(batch.validate().is_ok());
        batch.presentation_version = 2;
        assert!(batch.validate().is_err());
        batch.presentation_version = PRESENTATION_VERSION;
        batch.live.as_mut().unwrap().current_work_id = None;
        assert!(batch.validate().is_err());
        batch.live.as_mut().unwrap().current_work_id = Some("another".into());
        assert!(batch.validate().is_err());
        batch.live.as_mut().unwrap().current_work_id = Some("tail".into());
        batch.live.as_mut().unwrap().blocks[0].state = DisplayBlockState::Sealed;
        assert!(batch.validate().is_err());
        batch.live.as_mut().unwrap().current_work_id = None;
        assert!(batch.validate().is_ok());
    }
}
