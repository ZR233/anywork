//! Immutable completion envelopes and their read indexes. Native classification
//! belongs to the producer; consumers never infer it from payload or ordinal.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{ChatAtom, ChatAtomLifecycle, ChatScope, PayloadData};
use crate::studio::{StudioError, StudioErrorCode};

pub const COMPLETED_READ_INDEX_VERSION: u32 = 1;
pub const COMPLETED_HISTORY_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CompletionRunPosition {
    pub start_seq: u64,
    pub ordinal: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CompletionRunRef {
    pub database_id: String,
    pub index_version: u32,
    pub start_seq: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum MainPresentation {
    Hidden,
    Single,
    ForegroundWork,
    BackgroundResults,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CompletedEntry {
    pub record_id: String,
    pub completion_seq: u64,
    pub run: Option<CompletionRunPosition>,
    pub main_presentation: MainPresentation,
    pub atom: ChatAtom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatPlacement {
    Set,
    Prepend,
    Append,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatBatch {
    pub placement: ChatPlacement,
    pub entries: Vec<CompletedEntry>,
    pub before: Option<String>,
    /// The previously checked prefix, present only on Append.
    pub from_seq: Option<u64>,
    /// The checked global completion prefix, including filtered-out records.
    pub through_seq: u64,
}

impl ChatBatch {
    /// Check the producer's envelope before delivery. Source classification is
    /// not reimplemented here; these are structural and scope invariants only.
    pub fn validate_for(&self, scope: &ChatScope) -> Result<(), StudioError> {
        let scope_valid = match scope {
            ChatScope::Main => true,
            ChatScope::Run { reference } => {
                !reference.database_id.is_empty()
                    && reference.index_version == COMPLETED_READ_INDEX_VERSION
                    && reference.start_seq > 0
                    && reference.start_seq <= i64::MAX as u64
            }
            ChatScope::Children { parent_id } => !parent_id.is_empty(),
        };
        let placement_valid = match self.placement {
            ChatPlacement::Set | ChatPlacement::Prepend => self.from_seq.is_none(),
            ChatPlacement::Append => {
                self.before.is_none() && self.from_seq.is_some_and(|from| from < self.through_seq)
            }
        };
        let mut previous = self.from_seq.unwrap_or(0);
        let mut previous_run = None;
        let entries_valid = self.entries.iter().all(|entry| {
            let seq = entry.completion_seq;
            let ordered = seq > previous && seq <= self.through_seq;
            previous = seq;
            let identity_valid = !entry.record_id.is_empty()
                && entry
                    .atom
                    .completion_item_id
                    .as_ref()
                    .is_none_or(|id| id == &entry.record_id)
                && entry.atom.completion_seq.is_none_or(|value| value == seq);
            let run_valid = match (entry.main_presentation, entry.run) {
                (MainPresentation::Hidden, None) => true,
                (MainPresentation::Single, Some(run)) => run.start_seq == seq && run.ordinal == 1,
                (
                    MainPresentation::ForegroundWork | MainPresentation::BackgroundResults,
                    Some(run),
                ) => {
                    run.start_seq > 0
                        && run.start_seq <= seq
                        && run.ordinal > 0
                        && run.ordinal <= seq - run.start_seq + 1
                }
                _ => false,
            };
            let scope_valid = match scope {
                ChatScope::Main => {
                    let distinct_heads = if self.placement != ChatPlacement::Append {
                        entry.run.is_some_and(|run| {
                            let valid = previous_run.is_none_or(|start| start < run.start_seq);
                            previous_run = Some(run.start_seq);
                            valid
                        })
                    } else {
                        true
                    };
                    let payload_valid = match entry.main_presentation {
                        MainPresentation::Hidden => false,
                        MainPresentation::Single => true,
                        MainPresentation::ForegroundWork | MainPresentation::BackgroundResults => {
                            !matches!(entry.atom.payload, Some(PayloadData::Inline { .. }))
                        }
                    };
                    distinct_heads && payload_valid && entry.run.is_some()
                }
                ChatScope::Run { reference } => {
                    reference.index_version == COMPLETED_READ_INDEX_VERSION
                        && !reference.database_id.is_empty()
                        && entry
                            .run
                            .is_some_and(|run| run.start_seq == reference.start_seq)
                }
                ChatScope::Children { .. } => true,
            };
            ordered
                && identity_valid
                && run_valid
                && scope_valid
                && matches!(entry.atom.lifecycle, ChatAtomLifecycle::Terminal { .. })
        });
        if !scope_valid || !placement_valid || !entries_valid || self.through_seq > i64::MAX as u64
        {
            return Err(StudioError::new(
                StudioErrorCode::Internal,
                "Invalid immutable completion batch",
                false,
            ));
        }
        Ok(())
    }

    pub fn encoded_len(&self) -> Result<usize, serde_json::Error> {
        serde_json::to_vec(self).map(|bytes| bytes.len())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ActivityIdentity {
    ModelPart { atom_id: String },
    ForegroundTool { call_id: String },
    BackgroundTool { call_id: String },
    Other { domain: String, id: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ActivityEntry {
    pub identity: ActivityIdentity,
    pub atom: ChatAtom,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ActivitySnapshot {
    pub revision: u64,
    pub completed_through: u64,
    pub execution_present: bool,
    pub entries: Vec<ActivityEntry>,
}

#[cfg(test)]
mod tests;
