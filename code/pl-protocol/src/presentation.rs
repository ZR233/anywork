//! Product presentation snapshots, independent of atomic completion sequence.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    ChatAtom, ChatFactPosition, ChatPlacement, ChatSourceId,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};

pub const PRESENTATION_VERSION: u32 = 5;

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
    pub has_unfinished_members: bool,
    pub thinking_summary: Option<String>,
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
            timing: WorkTiming::default(),
            members: DisplayBlockRef {
                database_id: "db".into(),
                block_id: id.into(),
            },
        }
    }

    #[test]
    fn work_heads_do_not_reserve_an_inline_single_atom() {
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
                    has_unfinished_members: false,
                    thinking_summary: None,
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
    fn canonical_current_work_requires_one_matching_open_work_and_current_version() {
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
                    has_unfinished_members: false,
                    thinking_summary: None,
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
