//! Hybrid 16 KiB body packing and unified read helpers for Schema 26 events.

use std::sync::Arc;

use serde::{Deserialize, Serialize};

use super::{
    BODY_CHUNK_BYTES, HistoryBody, HistoryBodyManifestEntry, HistoryBodyRole,
    HistoryBusinessRowHead, HistoryError, HistoryEvent, HistoryEventBodyRef, HistoryEventMeta,
    HistoryEventRecord, HistoryReader, INLINE_BODY_MAX_BYTES, INLINE_EVENT_MAX_BYTES, Result,
};

#[derive(Debug, Clone)]
pub struct PendingBody {
    pub key: String,
    pub role: HistoryBodyRole,
    pub media_type: Option<String>,
    pub bytes: Arc<[u8]>,
}

impl PendingBody {
    pub fn new(
        key: impl Into<String>,
        role: HistoryBodyRole,
        media_type: Option<String>,
        bytes: impl Into<Arc<[u8]>>,
    ) -> Self {
        Self {
            key: key.into(),
            role,
            media_type,
            bytes: bytes.into(),
        }
    }
}

/// Packs event bodies using the 16 KiB hybrid contract:
/// - Valid UTF-8 text/JSON with `len <= 16 KiB` and per-event inline sum `<= 16 KiB`
///   (excluding `Attachment`) is stored as `"inlineText"` in `payload_json.bodies[]`.
/// - Larger bodies, budget overflow, or binary/attachment payloads go to `history_bodies`
///   + `history_body_chunks` and record a `HistoryEventBodyRef`.
pub fn pack_bodies(
    event: &mut HistoryEvent,
    pending: Vec<PendingBody>,
    database_id: &str,
) -> Result<Vec<HistoryBodyManifestEntry>> {
    if database_id.is_empty() && !pending.is_empty() {
        return Err(HistoryError::InvalidEvent(
            "history database identity is required when packing bodies".into(),
        ));
    }
    let mut inline_used: usize = 0;
    let mut manifest = Vec::with_capacity(pending.len());
    for item in pending {
        let byte_length = item.bytes.len() as u64;
        let can_inline = item.role != HistoryBodyRole::Attachment
            && item.bytes.len() <= INLINE_BODY_MAX_BYTES
            && inline_used
                .checked_add(item.bytes.len())
                .is_some_and(|total| total <= INLINE_EVENT_MAX_BYTES);
        if can_inline && let Ok(text) = std::str::from_utf8(&item.bytes) {
            inline_used += item.bytes.len();
            manifest.push(HistoryBodyManifestEntry {
                key: item.key,
                role: item.role.as_str().to_owned(),
                byte_length,
                media_type: item.media_type,
                inline_text: Some(text.to_owned()),
                reference: None,
            });
            continue;
        }
        let mut body = HistoryBody::new(item.key.clone(), item.role.clone(), item.bytes);
        body.media_type = item.media_type.clone();
        let reference = HistoryEventBodyRef {
            database_id: database_id.to_owned(),
            owner_event_id: event.event_id.clone(),
            body_key: item.key.clone(),
            body_id: body.body_id.clone(),
            byte_start: 0,
            byte_length,
        };
        manifest.push(HistoryBodyManifestEntry {
            key: item.key,
            role: item.role.as_str().to_owned(),
            byte_length,
            media_type: item.media_type,
            inline_text: None,
            reference: Some(reference),
        });
        event.bodies.push(body);
    }
    Ok(manifest)
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EventPayloadEnvelope {
    pub contract: String,
    #[serde(rename = "type")]
    pub item_type: String,
    pub meta: HistoryEventMeta,
    pub data: serde_json::Value,
    #[serde(default)]
    pub bodies: Vec<HistoryBodyManifestEntry>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_order: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub captured_at: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BusinessEnvelope<T> {
    pub head: T,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub bodies: Vec<HistoryBodyManifestEntry>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BusinessFactEnvelope {
    #[serde(rename = "type")]
    pub fact_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub bodies: Vec<HistoryBodyManifestEntry>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AnyBodiesContainer {
    #[serde(default)]
    bodies: Vec<HistoryBodyManifestEntry>,
}

pub fn decode_event_envelope(record: &HistoryEventRecord) -> Result<EventPayloadEnvelope> {
    if record.payload_schema != "anywork.event/1" {
        return Err(HistoryError::Integrity(format!(
            "unsupported event payload schema {}",
            record.payload_schema
        )));
    }
    Ok(serde_json::from_str(&record.payload_json)?)
}

pub(crate) fn decode_business_head_from_record(
    record: &HistoryEventRecord,
) -> Result<HistoryBusinessRowHead> {
    let scope = record
        .row_scope
        .ok_or_else(|| HistoryError::Integrity("business record has no row_scope".into()))?;
    let expected_schema = match scope {
        super::HistoryBusinessRowScope::Turn => "anywork.turn/1",
        super::HistoryBusinessRowScope::Source => "anywork.source/1",
        super::HistoryBusinessRowScope::Cost => "anywork.cost/1",
        super::HistoryBusinessRowScope::Accounting => "anywork.accounting/1",
    };
    if record.payload_schema != expected_schema {
        return Err(HistoryError::Integrity(format!(
            "business row payload_schema {} does not match {expected_schema}",
            record.payload_schema
        )));
    }
    decode_business_head_raw(scope, &record.payload_json)
}

pub(crate) fn decode_business_head_raw(
    scope: super::HistoryBusinessRowScope,
    payload_json: &str,
) -> Result<HistoryBusinessRowHead> {
    match scope {
        super::HistoryBusinessRowScope::Turn => {
            let envelope: BusinessEnvelope<super::HistoryTurnHead> =
                serde_json::from_str(payload_json)?;
            Ok(HistoryBusinessRowHead::Turn(envelope.head))
        }
        super::HistoryBusinessRowScope::Source => {
            let envelope: BusinessEnvelope<super::HistorySourceHead> =
                serde_json::from_str(payload_json)?;
            Ok(HistoryBusinessRowHead::Source(envelope.head))
        }
        super::HistoryBusinessRowScope::Cost => {
            let envelope: BusinessEnvelope<super::HistoryCostHead> =
                serde_json::from_str(payload_json)?;
            Ok(HistoryBusinessRowHead::Cost(envelope.head))
        }
        super::HistoryBusinessRowScope::Accounting => {
            let envelope: BusinessEnvelope<super::HistoryAccountingHead> =
                serde_json::from_str(payload_json)?;
            Ok(HistoryBusinessRowHead::Accounting(envelope.head))
        }
    }
}

/// Reads an event's named body transparently from either inline UTF-8 text in `payload_json.bodies[]`
/// (zero extra SQLite reads) or 64 KiB BLOB chunks in `history_bodies`.
pub async fn read_event_body_bytes(
    reader: &HistoryReader,
    event: &HistoryEventRecord,
    body_key: &str,
    max_bytes: Option<usize>,
) -> Result<Option<Vec<u8>>> {
    if let Ok(container) = serde_json::from_str::<AnyBodiesContainer>(&event.payload_json)
        && let Some(entry) = container
            .bodies
            .into_iter()
            .find(|item| item.key == body_key)
    {
        if let Some(inline) = entry.inline_text {
            let bytes = inline.into_bytes();
            if bytes.len() as u64 != entry.byte_length {
                return Err(HistoryError::Integrity(format!(
                    "inline body {} declared {} bytes but decoded to {}",
                    body_key,
                    entry.byte_length,
                    bytes.len()
                )));
            }
            enforce_max(bytes.len(), max_bytes)?;
            return Ok(Some(bytes));
        }
        if let Some(reference) = entry.reference {
            enforce_max_u64(reference.byte_length, max_bytes)?;
            return stream_body_reference(reader, &reference).await.map(Some);
        }
        if entry.byte_length == 0 {
            return Ok(Some(Vec::new()));
        }
        return Err(HistoryError::Integrity(format!(
            "body entry {body_key} has neither inlineText nor reference"
        )));
    }
    Ok(None)
}

pub async fn stream_body_reference(
    reader: &HistoryReader,
    reference: &HistoryEventBodyRef,
) -> Result<Vec<u8>> {
    let total = usize::try_from(reference.byte_length)
        .map_err(|_| HistoryError::Integrity("history body exceeds addressable memory".into()))?;
    let mut bytes = Vec::with_capacity(total);
    let mut offset = 0u64;
    while offset < reference.byte_length {
        let remaining = (reference.byte_length - offset).min(BODY_CHUNK_BYTES as u64) as u32;
        let window = reader
            .read_body(reference.clone(), offset, remaining)
            .await?;
        if window.bytes.is_empty() || window.total_length != reference.byte_length {
            return Err(HistoryError::Integrity(format!(
                "history body {} did not advance cleanly",
                reference.body_id
            )));
        }
        offset = offset
            .checked_add(window.bytes.len() as u64)
            .ok_or_else(|| HistoryError::Integrity("history body offset overflow".into()))?;
        bytes.extend_from_slice(&window.bytes);
    }
    if bytes.len() != total {
        return Err(HistoryError::Integrity(format!(
            "history body {} truncated",
            reference.body_id
        )));
    }
    Ok(bytes)
}

fn enforce_max(len: usize, max_bytes: Option<usize>) -> Result<()> {
    if let Some(limit) = max_bytes
        && len > limit
    {
        return Err(HistoryError::Integrity(format!(
            "history body {len} bytes exceeds budget {limit}"
        )));
    }
    Ok(())
}

fn enforce_max_u64(len: u64, max_bytes: Option<usize>) -> Result<()> {
    if let Some(limit) = max_bytes
        && len > limit as u64
    {
        return Err(HistoryError::Integrity(format!(
            "history body {len} bytes exceeds budget {limit}"
        )));
    }
    Ok(())
}
