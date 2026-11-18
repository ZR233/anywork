//! Frozen schema-24 presentation material consumed only by the explicit migration path.

use super::v24_presentation_types::{
    DisplayBlockBody, DisplayContentSource, DisplayMemberHead, DisplayRecord,
};
use crate::{
    ChatAtom, ChatAtomLifecycle, ChatFactPosition, ChatSourceId, ContentRef, ContentTarget,
    PayloadData,
};
use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};

/// Positive creation position, independent of completion and effect sequences.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(try_from = "u64", into = "u64")]
pub(crate) struct BlockOrder(u64);

impl BlockOrder {
    fn new(value: u64) -> Result<Self> {
        ensure!(
            (1..=i64::MAX as u64).contains(&value),
            "invalid display block order"
        );
        Ok(Self(value))
    }

    pub(crate) fn get(self) -> u64 {
        self.0
    }
}

impl TryFrom<u64> for BlockOrder {
    type Error = anyhow::Error;

    fn try_from(value: u64) -> Result<Self> {
        Self::new(value)
    }
}

impl From<BlockOrder> for u64 {
    fn from(value: BlockOrder) -> Self {
        value.get()
    }
}

/// Persisted schema-24 display header, never a member list or body.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct DisplayHeader {
    pub version: u32,
    pub id: String,
    pub source: ChatSourceId,
    pub block_order: BlockOrder,
    pub boundary: Option<ChatFactPosition>,
    pub first_content_at: Option<ChatFactPosition>,
    pub sealed: bool,
    pub unfinished: u64,
    pub next_member: u64,
    pub revision: u64,
    #[serde(skip)]
    pub thinking_summary: Option<String>,
    pub body: DisplayBlockBody,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct DisplayMemberWrite {
    pub block_id: String,
    pub association_key: String,
    pub terminal: bool,
    pub head: DisplayMemberHead,
}

/// Stable association identity embedded by schema-24 migration rows.
// JSON tuple encoding is unambiguous, including the typed source discriminant.
pub(in crate::studio) fn member_key(atom: &ChatAtom) -> Result<String> {
    Ok(serde_json::to_string(&(
        &atom.source,
        &atom.id,
        if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) {
            "background-result"
        } else {
            "foreground-obligation"
        },
    ))?)
}

pub(in crate::studio) fn record(
    atom: ChatAtom,
    start_fact: Option<ChatFactPosition>,
) -> DisplayRecord {
    let end_fact = match atom.lifecycle {
        ChatAtomLifecycle::Terminal { ended, .. } => ended,
        ChatAtomLifecycle::Active { .. } => None,
    };
    let content_source = atom.completion_item_id.as_ref().map_or_else(
        || {
            if matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }) {
                DisplayContentSource::FrozenObservation {
                    captured_at: atom.finished_at,
                    available: true,
                }
            } else {
                DisplayContentSource::CurrentAtom
            }
        },
        |id| DisplayContentSource::CompletedOriginal {
            completion_id: id.clone(),
        },
    );
    DisplayRecord {
        atom,
        start_fact,
        end_fact,
        content_source,
    }
}

pub(in crate::studio) fn lightweight(mut atom: ChatAtom, database: &str) -> ChatAtom {
    if let Some(payload) = &atom.payload {
        let length = match payload {
            PayloadData::Inline { bytes } => bytes.len() as u64,
            PayloadData::Deferred { byte_length, .. } => *byte_length,
        };
        atom.payload = atom
            .completion_item_id
            .as_ref()
            .map(|id| PayloadData::Deferred {
                reference: ContentRef {
                    database_id: database.into(),
                    target: ContentTarget::ItemPayload {
                        item_id: id.clone(),
                    },
                },
                byte_length: length,
            });
    }
    atom
}
