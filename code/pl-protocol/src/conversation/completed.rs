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
mod tests {
    use super::*;
    use crate::{ChatAtomKind, ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome, ReadDemand};

    fn entry(seq: u64, start: u64, ordinal: u64) -> CompletedEntry {
        CompletedEntry {
            record_id: format!("record:{seq}"),
            completion_seq: seq,
            run: Some(CompletionRunPosition {
                start_seq: start,
                ordinal,
            }),
            main_presentation: MainPresentation::ForegroundWork,
            atom: ChatAtom {
                id: format!("part:{seq}"),
                completion_item_id: Some(format!("record:{seq}")),
                completion_seq: Some(seq),
                source: ChatSourceId::ForegroundTurn {
                    turn_id: "turn:one".into(),
                },
                source_state: None,
                source_order: None,
                kind: ChatAtomKind::ToolCall,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: None,
                    outcome: ChatTerminalOutcome::Completed,
                },
                turn_id: Some("turn:one".into()),
                attempt_id: None,
                tool: None,
                wait: None,
                text_channel: None,
                started_at: None,
                finished_at: None,
                content_present: None,
                contents: Vec::new(),
                payload: Some(PayloadData::Deferred {
                    reference: crate::ContentRef {
                        database_id: "database".into(),
                        target: crate::ContentTarget::ItemPayload {
                            item_id: format!("record:{seq}"),
                        },
                    },
                    byte_length: 100_000,
                }),
            },
        }
    }

    fn batch(placement: ChatPlacement, entries: Vec<CompletedEntry>) -> ChatBatch {
        ChatBatch {
            placement,
            entries,
            before: None,
            from_seq: (placement == ChatPlacement::Append).then_some(0),
            through_seq: 10,
        }
    }

    #[test]
    fn main_heads_and_live_records_have_distinct_delivery_shapes() {
        let set = batch(ChatPlacement::Set, vec![entry(3, 1, 3), entry(9, 9, 1)]);
        assert!(set.validate_for(&ChatScope::Main).is_ok());
        let records = vec![entry(1, 1, 1), entry(3, 1, 2)];
        assert!(
            batch(ChatPlacement::Set, records.clone())
                .validate_for(&ChatScope::Main)
                .is_err()
        );
        assert!(
            batch(ChatPlacement::Append, records)
                .validate_for(&ChatScope::Main)
                .is_ok()
        );
        let mut hidden = entry(5, 5, 1);
        hidden.main_presentation = MainPresentation::Hidden;
        hidden.run = None;
        let hidden_batch = batch(ChatPlacement::Set, vec![hidden]);
        assert!(hidden_batch.validate_for(&ChatScope::Main).is_err());
        assert!(
            hidden_batch
                .validate_for(&ChatScope::Children {
                    parent_id: "4:turnone".into()
                })
                .is_ok()
        );
    }

    #[test]
    fn collapsed_work_rejects_inline_payload_even_for_one_member() {
        let mut one = entry(1, 1, 1);
        one.atom.payload = Some(PayloadData::Inline {
            bytes: "完整结果".as_bytes().to_vec(),
        });
        let value = batch(ChatPlacement::Set, vec![one.clone()]);
        assert!(value.validate_for(&ChatScope::Main).is_err());
        let scope = ChatScope::Run {
            reference: CompletionRunRef {
                database_id: "database".into(),
                index_version: COMPLETED_READ_INDEX_VERSION,
                start_seq: 1,
            },
        };
        assert!(value.validate_for(&scope).is_ok());
        one.main_presentation = MainPresentation::Single;
        assert!(
            batch(ChatPlacement::Set, vec![one])
                .validate_for(&ChatScope::Main)
                .is_ok()
        );
    }

    #[test]
    fn filtered_append_advances_prefix_without_inserting_a_fake_record() {
        let mut value = batch(ChatPlacement::Append, Vec::new());
        value.from_seq = Some(8);
        assert!(value.validate_for(&ChatScope::Main).is_ok());
        value.through_seq = 8;
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.through_seq = 10;
        value.before = Some("old-page".into());
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.placement = ChatPlacement::Prepend;
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.from_seq = None;
        assert!(value.validate_for(&ChatScope::Main).is_ok());
    }

    #[test]
    fn empty_result_does_not_legalize_an_invalid_run_reference() {
        let value = batch(ChatPlacement::Set, Vec::new());
        for (database_id, index_version, start_seq) in [("", 1, 1), ("db", 0, 1), ("db", 1, 0)] {
            assert!(
                value
                    .validate_for(&ChatScope::Run {
                        reference: CompletionRunRef {
                            database_id: database_id.into(),
                            index_version,
                            start_seq,
                        },
                    })
                    .is_err()
            );
        }
    }

    #[test]
    fn completion_identity_order_and_cut_are_checked_before_delivery() {
        let mut value = batch(ChatPlacement::Append, vec![entry(3, 1, 2)]);
        value.from_seq = Some(3);
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.from_seq = Some(2);
        value.entries[0].atom.completion_seq = Some(4);
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.entries[0].atom.completion_seq = Some(3);
        value.through_seq = 2;
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.through_seq = i64::MAX as u64 + 1;
        assert!(value.validate_for(&ChatScope::Main).is_err());
        value.through_seq = 10;
        value.entries[0].run.as_mut().unwrap().ordinal = u64::MAX;
        assert!(value.validate_for(&ChatScope::Main).is_err());
    }

    #[test]
    fn envelope_budget_is_enforced_at_the_actual_encoded_length() {
        let value = batch(ChatPlacement::Set, vec![entry(1, 1, 1)]);
        let bytes = serde_json::to_vec(&value).unwrap();
        assert_eq!(value.encoded_len().unwrap(), bytes.len());
        assert!(
            ReadDemand {
                max_items: 1,
                max_bytes: bytes.len() as u32,
            }
            .validate(bytes.len())
            .is_ok()
        );
        assert!(
            ReadDemand {
                max_items: 1,
                max_bytes: bytes.len() as u32 - 1,
            }
            .validate(bytes.len())
            .is_err()
        );
    }
}
