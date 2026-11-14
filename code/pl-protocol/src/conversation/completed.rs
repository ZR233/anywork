//! Immutable completion envelopes and their read indexes. Native classification
//! belongs to the producer; consumers never infer it from payload or ordinal.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{ChatAtom, ChatAtomLifecycle, ChatScope};
use crate::studio::{StudioError, StudioErrorCode};

pub const COMPLETED_READ_INDEX_VERSION: u32 = 2;
pub const COMPLETED_HISTORY_VERSION: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CompletedEntry {
    pub record_id: String,
    pub completion_seq: u64,
    pub atom: ChatAtom,
}

/// 仅用于导出旧格式中未被现有业务事实覆盖的原始字节，不是新的完成记录。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LegacyExecutionEvidence {
    pub evidence_id: String,
    pub record_id: String,
    pub revision: u64,
    pub kind: String,
    pub source_schema: u32,
    pub source_table: String,
    pub source_row: serde_json::Value,
    pub byte_length: u64,
    pub raw_digest: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LegacyExecutionEvidencePage {
    pub entries: Vec<LegacyExecutionEvidence>,
    pub continuation: Option<String>,
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
        let scope_valid = scope.is_valid();
        let placement_valid = match self.placement {
            ChatPlacement::Set | ChatPlacement::Prepend => self.from_seq.is_none(),
            ChatPlacement::Append => {
                self.before.is_none() && self.from_seq.is_some_and(|from| from < self.through_seq)
            }
        };
        let mut previous = self.from_seq.unwrap_or(0);
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
            ordered
                && identity_valid
                && entry.atom.source_state.is_none()
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
    use crate::ChatClassFilter;

    #[test]
    fn original_record_scope_requires_explicit_class_and_rejects_legacy_shapes() {
        for value in [
            serde_json::json!({}),
            serde_json::json!({"kind":"main"}),
            serde_json::json!({"queryClass":{"kind":"all","value":"conversation"}}),
            serde_json::json!({"queryClass":{"kind":"class"}}),
        ] {
            assert!(serde_json::from_value::<ChatScope>(value).is_err());
        }
        let all: ChatScope =
            serde_json::from_value(serde_json::json!({"queryClass":{"kind":"all"}})).unwrap();
        assert_eq!(all.query_class, ChatClassFilter::All {});
        assert!(all.query_class().is_none());
        let scoped = ChatScope::conversation(Some("4:turnone".into()));
        assert_eq!(
            serde_json::from_value::<ChatScope>(serde_json::to_value(&scoped).unwrap()).unwrap(),
            scoped
        );
        assert!(
            !ChatScope {
                query_class: ChatClassFilter::Class {
                    value: String::new()
                },
                parent_id: None
            }
            .is_valid()
        );
    }

    #[test]
    fn filtered_append_may_advance_over_gaps_but_never_repeat_a_prefix() {
        let scope = ChatScope::conversation(None);
        let mut batch = ChatBatch {
            placement: ChatPlacement::Append,
            entries: vec![],
            before: None,
            from_seq: Some(8),
            through_seq: 11,
        };
        assert!(batch.validate_for(&scope).is_ok());
        batch.from_seq = Some(11);
        assert!(batch.validate_for(&scope).is_err());
        batch.from_seq = Some(8);
        batch.before = Some("older".into());
        assert!(batch.validate_for(&scope).is_err());
    }
}
