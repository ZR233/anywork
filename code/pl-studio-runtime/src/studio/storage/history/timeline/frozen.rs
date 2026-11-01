//! Frozen schema-11 record representation. Not a normal runtime/chat API.
use pl_core::{chat::PresentationPart, model::ContentBlock};
use std::{collections::BTreeMap, sync::Arc};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum ChatField {
    Body,
    Part(PresentationPart),
    Host(Arc<str>),
}
impl ChatField {
    pub(crate) fn host(key: impl Into<Arc<str>>) -> Self {
        Self::Host(key.into())
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Field {
    pub block: Arc<ContentBlock>,
    pub total_bytes: u64,
}
impl Field {
    pub(crate) fn is_complete(&self) -> bool {
        self.total_bytes == self.block.len() as u64
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ChatItem {
    pub item_id: String,
    pub turn_id: Option<String>,
    pub append_seq: u64,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
    pub fields: BTreeMap<ChatField, Field>,
    pub meta: Arc<[u8]>,
}
pub(crate) struct ChatItemParts {
    pub item_id: String,
    pub turn_id: Option<String>,
    pub append_seq: u64,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
    pub fields: BTreeMap<ChatField, Arc<ContentBlock>>,
    pub meta: Arc<[u8]>,
}
pub(crate) struct ChatDraft {
    pub item_id: String,
    pub turn_id: Option<String>,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
    pub fields: BTreeMap<ChatField, Arc<ContentBlock>>,
    pub meta: Arc<[u8]>,
}
impl ChatItem {
    pub(crate) fn complete(parts: ChatItemParts) -> Self {
        Self {
            item_id: parts.item_id,
            turn_id: parts.turn_id,
            append_seq: parts.append_seq,
            source_effect_seq: parts.source_effect_seq,
            sealed_at: parts.sealed_at,
            fields: parts
                .fields
                .into_iter()
                .map(|(key, block)| {
                    (
                        key,
                        Field {
                            total_bytes: block.len() as u64,
                            block,
                        },
                    )
                })
                .collect(),
            meta: parts.meta,
        }
    }
    pub(crate) fn is_complete(&self) -> bool {
        self.fields.values().all(Field::is_complete)
    }
}
