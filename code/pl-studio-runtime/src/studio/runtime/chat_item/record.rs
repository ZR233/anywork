//! Lossless persistence codec for a complete immutable record, not a preview DTO.

use super::*;
use anyhow::ensure;
use pl_core::chat::{ChatItem, ChatItemParts};
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

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{ThreadContentLifecycle, ThreadTextChannel};

    fn record() -> Result<ChatItem> {
        let draft = completion_draft(
            &ThreadItem::new(
                "record".into(),
                "thread".into(),
                String::new(),
                99,
                17,
                10,
                20,
                ThreadItemState::Text(ThreadTextItem::new(
                    ThreadTextChannel::User,
                    "完整正文\n🦀".into(),
                    Vec::new(),
                    ThreadContentLifecycle::completed(20),
                )),
            ),
            8,
        )?;
        Ok(ChatItem::complete(ChatItemParts {
            item_id: draft.item_id,
            turn_id: draft.turn_id,
            append_seq: 3,
            source_effect_seq: draft.source_effect_seq,
            sealed_at: draft.sealed_at,
            fields: draft.fields,
            meta: draft.meta,
        }))
    }

    #[test]
    fn completion_codec_preserves_identity_and_every_field_without_execution_metadata() -> Result<()>
    {
        let mut original = record()?;
        for field in [
            ChatField::Part(PresentationPart::OutputText(7)),
            ChatField::Part(PresentationPart::SummaryText(2)),
            ChatField::Part(PresentationPart::ReasoningText(4)),
            ChatField::host("body"),
        ] {
            original.fields.insert(
                field,
                pl_core::chat::ChatFieldPreview::complete(ContentBlock::from_text("字段🦀")),
            );
        }
        let encoded = encode_record(&original)?;
        assert_eq!(decode_record(&encoded)?, original);
        let meta: serde_json::Value = serde_json::from_slice(&original.meta)?;
        assert!(meta.get("revision").is_none());
        assert!(meta.get("ordinal").is_none());
        assert_eq!(original.turn_id, None);
        Ok(())
    }

    #[test]
    fn completion_codec_rejects_duplicate_fields_and_omitted_bodies() -> Result<()> {
        let mut original = record()?;
        let mut encoded: serde_json::Value = serde_json::from_str(&encode_record(&original)?)?;
        let fields = encoded["fields"].as_array_mut().unwrap();
        fields.push(fields[0].clone());
        assert!(decode_record(&encoded.to_string()).is_err());
        original
            .fields
            .get_mut(&ChatField::Body)
            .unwrap()
            .total_bytes += 1;
        assert!(encode_record(&original).is_err());
        Ok(())
    }
}
