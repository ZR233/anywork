//! Product presentation snapshots, independent of atomic completion sequence.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    ChatAtom, ChatPlacement, ContentRef,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};

pub const PRESENTATION_VERSION: u32 = 1;

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
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub duration_ms: Option<u64>,
    pub thinking_summary: Option<String>,
    pub thinking_content: Option<ContentRef>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum DisplayBlockBody {
    Work {
        summary: WorkSummary,
        members: DisplayBlockRef,
    },
    Single {
        atom: ChatAtom,
        completion_id: Option<String>,
    },
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
    pub body: DisplayBlockBody,
    pub closing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LiveDisplayWindow {
    pub revision: u64,
    pub history_through: u64,
    pub execution_present: bool,
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
            live.history_through == self.through_pos
                && live.blocks.iter().all(|block| {
                    let ordered = block.block_order > order;
                    order = block.block_order;
                    ordered && !block.id.is_empty() && identities.insert(block.id.as_str())
                })
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
    pub atom: ChatAtom,
    pub completion_id: Option<String>,
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
            summary: WorkSummary::default(),
            members: DisplayBlockRef {
                database_id: "db".into(),
                block_id: id.into(),
            },
        }
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
                blocks: vec![LiveDisplayBlock {
                    id: "g1".into(),
                    block_order: 1,
                    body: work("g1"),
                    closing: true,
                }],
                older: None,
            }),
        };
        assert!(batch.validate().is_err());
    }
}
