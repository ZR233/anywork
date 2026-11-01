//! Lossless persistence codec for a complete immutable record, not a preview DTO.

use super::super::frozen::{ChatItem, ChatItemParts};
use super::*;
use anyhow::ensure;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StoredRecord {
    item_id: String,
    turn_id: Option<String>,
    append_seq: u64,
    source_effect_seq: Option<u64>,
    sealed_at: Option<i64>,
    meta: Vec<u8>,
    fields: Vec<StoredField>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StoredField {
    identity: FieldIdentity,
    text: String,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum FieldIdentity {
    Body,
    OutputText(u32),
    ReasoningText(u32),
    SummaryText(u32),
    Host(String),
}

impl From<&ChatField> for FieldIdentity {
    fn from(field: &ChatField) -> Self {
        match field {
            ChatField::Body => Self::Body,
            ChatField::Part(PresentationPart::OutputText(index)) => Self::OutputText(*index),
            ChatField::Part(PresentationPart::ReasoningText(index)) => Self::ReasoningText(*index),
            ChatField::Part(PresentationPart::SummaryText(index)) => Self::SummaryText(*index),
            ChatField::Host(key) => Self::Host(key.to_string()),
        }
    }
}

impl From<FieldIdentity> for ChatField {
    fn from(field: FieldIdentity) -> Self {
        match field {
            FieldIdentity::Body => Self::Body,
            FieldIdentity::OutputText(index) => Self::Part(PresentationPart::OutputText(index)),
            FieldIdentity::ReasoningText(index) => {
                Self::Part(PresentationPart::ReasoningText(index))
            }
            FieldIdentity::SummaryText(index) => Self::Part(PresentationPart::SummaryText(index)),
            FieldIdentity::Host(key) => Self::host(key),
        }
    }
}

fn validate(item: &ChatItem) -> Result<()> {
    ensure!(
        !item.item_id.is_empty(),
        "completion record identity is empty"
    );
    ensure!(
        item.append_seq > 0 && item.append_seq <= i64::MAX as u64,
        "completion append sequence is outside the durable range"
    );
    ensure!(
        item.source_effect_seq
            .is_none_or(|sequence| sequence > 0 && sequence <= i64::MAX as u64),
        "completion source effect is outside the durable range"
    );
    ensure!(
        item.turn_id.as_ref().is_none_or(|id| !id.is_empty()),
        "completion turn identity is empty"
    );
    ensure!(
        item.is_complete(),
        "cannot persist an omitted completion preview"
    );
    TimelineMeta::for_item(item)?;
    Ok(())
}

pub(crate) fn encode_record(item: &ChatItem) -> Result<String> {
    validate(item)?;
    let stored = StoredRecord {
        item_id: item.item_id.clone(),
        turn_id: item.turn_id.clone(),
        append_seq: item.append_seq,
        source_effect_seq: item.source_effect_seq,
        sealed_at: item.sealed_at,
        meta: item.meta.to_vec(),
        fields: item
            .fields
            .iter()
            .map(|(field, preview)| StoredField {
                identity: FieldIdentity::from(field),
                text: preview.block.text(),
            })
            .collect(),
    };
    Ok(serde_json::to_string(&stored)?)
}

pub(crate) fn decode_record(payload: &str) -> Result<ChatItem> {
    let stored: StoredRecord = serde_json::from_str(payload)?;
    let mut fields = BTreeMap::new();
    for field in stored.fields {
        ensure!(
            fields
                .insert(
                    ChatField::from(field.identity),
                    ContentBlock::from_text(&field.text)
                )
                .is_none(),
            "completion record contains a duplicate field"
        );
    }
    let item = ChatItem::complete(ChatItemParts {
        item_id: stored.item_id,
        turn_id: stored.turn_id,
        append_seq: stored.append_seq,
        source_effect_seq: stored.source_effect_seq,
        sealed_at: stored.sealed_at,
        fields,
        meta: Arc::from(stored.meta),
    });
    validate(&item)?;
    Ok(item)
}
