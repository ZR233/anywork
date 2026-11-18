//! Frozen schema-24 page budgeting for legacy migration fixtures.
use super::schema::v24_presentation_types::{ChatBatch, ChatPlacement, CompletedEntry};
use crate::*;
use anyhow::{Result, ensure};
use pl_core::chat as core;

pub(crate) struct JsonBudget {
    pub database_id: String,
    deferred_only: bool,
    fixed: usize,
    manifest_item: Option<String>,
}
impl JsonBudget {
    pub(crate) fn new(database_id: String, continuation: String) -> Self {
        let batch = ChatBatch {
            placement: ChatPlacement::Prepend,
            entries: Vec::new(),
            before: Some(continuation),
            from_seq: None,
            through_seq: i64::MAX as u64,
        };
        Self {
            database_id,
            deferred_only: false,
            fixed: serde_json::to_vec(&batch).map_or(usize::MAX, |bytes| bytes.len()),
            manifest_item: None,
        }
    }
    pub(crate) fn headers_only(mut self) -> Self {
        self.deferred_only = true;
        self
    }
}
impl core::ChatBudget for JsonBudget {
    fn allow_inline(&self, _header: &core::ChatItemHeader) -> bool {
        !self.deferred_only
    }
    fn fixed_bytes(&self) -> usize {
        self.fixed
    }
    fn item_bytes(&self, header: &core::ChatItemHeader, mode: core::PayloadMode) -> usize {
        let payload = match mode {
            core::PayloadMode::Inline => PayloadData::Inline { bytes: Vec::new() },
            core::PayloadMode::Deferred => PayloadData::Deferred {
                reference: ContentRef {
                    database_id: self.database_id.clone(),
                    target: ContentTarget::ItemPayload {
                        item_id: header.item_id.clone(),
                    },
                },
                byte_length: header.byte_length,
            },
        };
        let base = completed_entry(header, payload)
            .and_then(|entry| Ok(serde_json::to_vec(&entry)?))
            .map_or(usize::MAX, |bytes| bytes.len().saturating_add(1));
        if mode == core::PayloadMode::Inline {
            base.saturating_add(
                usize::try_from(header.byte_length)
                    .unwrap_or(usize::MAX)
                    .saturating_mul(4),
            )
        } else {
            base
        }
    }
    fn manifest_bytes(&self, descriptor: &core::ContentDescriptor) -> usize {
        manifest_entry(
            &self.database_id,
            self.manifest_item.as_deref().unwrap_or("item"),
            descriptor.clone(),
        )
        .and_then(|entry| Ok(serde_json::to_vec(&entry)?.len().saturating_add(1)))
        .unwrap_or(usize::MAX)
    }
}
pub(crate) fn completed_entry(
    header: &core::ChatItemHeader,
    payload: PayloadData,
) -> Result<CompletedEntry> {
    let mut atom: ChatAtom = serde_json::from_slice(&header.metadata)?;
    ensure!(
        atom.completion_item_id
            .as_deref()
            .is_none_or(|id| id == header.item_id)
            && atom
                .completion_seq
                .is_none_or(|seq| seq == header.append_seq)
            && atom.payload.is_none()
            && atom.source_state.is_none()
            && matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
        core::ChatError::Conflict("completion metadata differs from its frozen header".into())
    );
    atom.completion_item_id = Some(header.item_id.clone());
    atom.completion_seq = Some(header.append_seq);
    atom.payload = Some(payload);
    Ok(CompletedEntry {
        record_id: header.item_id.clone(),
        completion_seq: header.append_seq,
        atom,
    })
}
fn manifest_entry(
    database: &str,
    item_id: &str,
    descriptor: core::ContentDescriptor,
) -> Result<ContentManifestEntry> {
    Ok(ContentManifestEntry {
        key: descriptor.key.key.clone(),
        payload: serde_json::to_vec(
            &serde_json::json!({"byteLength":descriptor.byte_length,"generation":descriptor.generation,"mediaType":descriptor.media_type}),
        )?,
        reference: ContentRef {
            database_id: database.into(),
            target: ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: item_id.into(),
                },
                key: descriptor.key.key,
            },
        },
    })
}
