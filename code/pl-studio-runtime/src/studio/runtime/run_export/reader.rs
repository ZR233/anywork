//! Read-only core `Session` completion and streaming content exporter.
//!
//! Reads directly from `pl_core::chat::Session` using `query = None` and explicit bounds,
//! retaining the original read-only `Session` across thread retirement without retaining
//! execution owners or changing completion epochs.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context, Result, ensure};
use pl_core::chat::{
    ChatBudget, ChatCompletionCursor, ChatContentKey, ChatError, ChatItemHeader, ChatPageItem,
    ChatQuery, ContentDescriptor, ContentManifestRequest, ContentReadRequest, ContentRef,
    PayloadData, PayloadMode, ReadDemand, Session,
};
use pl_protocol::{ChatContentRole, ContentTarget};
use sha2::{Digest, Sha256};

use super::types::{
    CONTENT_EXPORT_CHUNK_BYTES, ChatItemHeaderExportV1, EventSourceV1, ExportedBlobV1,
    ExportedContentV1,
};
use super::writer::{BlobChunkWriter, ContentBlobSink};

const EXPORT_BATCH_MAX_ITEMS: usize = 256;

/// Bounded `ChatBudget` used solely by the internal completion exporter.
struct ExportChatBudget;

impl ChatBudget for ExportChatBudget {
    fn fixed_bytes(&self) -> usize {
        0
    }

    fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
        let payload = match mode {
            PayloadMode::Inline => header.byte_length as usize,
            PayloadMode::Deferred => 256,
        };
        header
            .metadata
            .len()
            .saturating_add(payload)
            .saturating_add(256)
    }

    fn manifest_bytes(&self, descriptor: &ContentDescriptor) -> usize {
        descriptor.key.owner.as_str().len()
            + descriptor.key.key.len()
            + descriptor.media_type.as_ref().map_or(0, String::len)
            + 64
    }

    fn allow_inline(&self, header: &ChatItemHeader) -> bool {
        header.byte_length <= u64::from(CONTENT_EXPORT_CHUNK_BYTES)
    }
}

/// Decoded and persisted completion payload ready to become an `EventV1::Completion`.
pub struct ExportedCompletionRecord {
    pub epoch: String,
    pub source: EventSourceV1,
    pub header: ChatItemHeaderExportV1,
    pub header_payload_fingerprint: String,
    pub atom: pl_protocol::ChatAtom,
    pub payload: ExportedBlobV1,
    pub contents: Vec<ExportedContentV1>,
}

/// Incremental UTF-8 validator across arbitrary chunk splits (handling multi-byte codepoints).
#[derive(Default)]
struct Utf8StreamValidator {
    pending: [u8; 4],
    pending_len: usize,
    valid: bool,
    initialized: bool,
}

impl Utf8StreamValidator {
    fn push(&mut self, chunk: &[u8]) {
        if !self.initialized {
            self.valid = true;
            self.initialized = true;
        }
        if !self.valid || chunk.is_empty() {
            return;
        }
        let mut slice = chunk;
        // Complete exactly the pending code point. Consuming up to four bytes at once can
        // also consume the next character's lead byte and misclassify valid Chinese text.
        while self.pending_len > 0 {
            let Some((&byte, rest)) = slice.split_first() else {
                return;
            };
            self.pending[self.pending_len] = byte;
            self.pending_len += 1;
            slice = rest;
            match std::str::from_utf8(&self.pending[..self.pending_len]) {
                Ok(_) => self.pending_len = 0,
                Err(error) if error.error_len().is_none() => {}
                Err(_) => {
                    self.valid = false;
                    return;
                }
            }
        }

        if slice.is_empty() {
            return;
        }
        match std::str::from_utf8(slice) {
            Ok(_) => {}
            Err(err) => {
                if err.error_len().is_some() {
                    self.valid = false;
                } else {
                    let rem = &slice[err.valid_up_to()..];
                    if rem.len() <= 3 {
                        self.pending[..rem.len()].copy_from_slice(rem);
                        self.pending_len = rem.len();
                    } else {
                        self.valid = false;
                    }
                }
            }
        }
    }

    fn finish(self) -> &'static str {
        if !self.initialized {
            return "utf-8";
        }
        if self.valid && self.pending_len == 0 {
            "utf-8"
        } else {
            "binary"
        }
    }
}

/// Exports at most one bounded page after `after_seq` up through `ceiling`.
/// The caller writes this page before requesting the next, avoiding a run-sized record buffer.
pub async fn export_completions_range<S: ContentBlobSink>(
    session: &Session,
    database_id: Option<&str>,
    after_seq: u64,
    ceiling: Option<u64>,
    sink: &mut S,
) -> Result<(u64, Vec<ExportedCompletionRecord>)> {
    let target_ceiling = ceiling.unwrap_or_else(|| session.head_seq());
    let mut seq = after_seq;
    let mut records = Vec::new();
    let demand = ReadDemand::new(EXPORT_BATCH_MAX_ITEMS, pl_core::chat::MAX_READ_BYTES);
    let budget = ExportChatBudget;

    if seq < target_ceiling {
        let epoch = session.epoch();
        let cursor = ChatCompletionCursor::new(epoch.clone(), seq);
        let batch = session
            .completed_after(
                cursor,
                None::<ChatQuery>,
                Some(target_ceiling),
                demand,
                &budget,
            )
            .await?;
        let batch_through = batch.through_seq;
        for item in batch.items {
            ensure!(
                seq.checked_add(records.len() as u64 + 1) == Some(item.header.append_seq),
                "missing completion before {}",
                item.header.append_seq
            );
            let record = export_single_item(session, database_id, &budget, item, sink).await?;
            records.push(record);
        }
        ensure!(
            batch_through > seq && batch_through <= target_ceiling,
            "completion export did not advance to its requested cut"
        );
        ensure!(
            batch_through - seq == records.len() as u64,
            "completion range contains missing originals"
        );
        seq = batch_through;
    }

    Ok((seq, records))
}

async fn export_single_item<S: ContentBlobSink>(
    session: &Session,
    database_id: Option<&str>,
    budget: &ExportChatBudget,
    item: ChatPageItem,
    sink: &mut S,
) -> Result<ExportedCompletionRecord> {
    let epoch = session.epoch().as_str().to_string();
    let resolved_db_id = database_id.unwrap_or_default();

    let (exported_payload, proto_payload) = match &item.payload {
        PayloadData::Inline(bytes) => {
            let mut writer = sink.begin_blob().await?;
            writer.write_chunk(bytes).await?;
            let encoding = if std::str::from_utf8(bytes).is_ok() {
                "utf-8"
            } else {
                "binary"
            }
            .to_string();
            let blob = writer
                .finish(infer_payload_media_type(bytes), encoding)
                .await?;
            let proto = pl_protocol::PayloadData::Inline {
                bytes: bytes.to_vec(),
            };
            (blob, proto)
        }
        PayloadData::Deferred {
            item_id,
            byte_length,
        } => {
            let blob = stream_content_to_sink(
                session,
                &ContentRef::ItemPayload(item_id.clone()),
                Some(*byte_length),
                None,
                true,
                sink,
            )
            .await?;
            let proto = pl_protocol::PayloadData::Deferred {
                reference: pl_protocol::ContentRef {
                    database_id: resolved_db_id.to_string(),
                    target: ContentTarget::ItemPayload {
                        item_id: item_id.clone(),
                    },
                },
                byte_length: *byte_length,
            };
            (blob, proto)
        }
    };

    let header_export = ChatItemHeaderExportV1::from_core(&item.header);
    let mut header_fp = Sha256::new();
    header_fp.update(serde_json::to_vec(&header_export)?);
    header_fp.update(item.header.metadata.as_ref());
    header_fp.update(exported_payload.sha256.as_bytes());
    let header_payload_fingerprint = hex::encode(header_fp.finalize());

    let entry =
        crate::studio::runtime::conversation_reader::completed_entry(&item.header, proto_payload)
            .with_context(|| format!("decode completion item {}", item.header.item_id))?;

    let manifests = list_item_manifests(session, &item.header.item_id, budget).await?;
    let mut manifest_by_key: BTreeMap<ChatContentKey, ContentDescriptor> = manifests
        .into_iter()
        .map(|desc| (desc.key.clone(), desc))
        .collect();

    let mut exported_contents = Vec::new();
    let mut seen_keys: BTreeSet<ChatContentKey> = BTreeSet::new();

    for content in &entry.atom.contents {
        let core_ref = to_core_content_ref(&content.reference)?;
        let media_type = match &core_ref {
            ContentRef::Body(key) => {
                seen_keys.insert(key.clone());
                manifest_by_key
                    .get(key)
                    .and_then(|desc| desc.media_type.clone())
            }
            ContentRef::ItemPayload(_) => None,
        };
        let expected_len = match &core_ref {
            ContentRef::Body(key) => manifest_by_key.get(key).map(|desc| desc.byte_length),
            ContentRef::ItemPayload(_) => None,
        };
        let blob =
            stream_content_to_sink(session, &core_ref, expected_len, media_type, false, sink)
                .await
                .with_context(|| {
                    format!(
                        "export content ref {:?} for {}",
                        content.reference, item.header.item_id
                    )
                })?;
        exported_contents.push(ExportedContentV1 {
            native_ref: content.reference.clone(),
            role: Some(content.role),
            path: blob.path,
            byte_length: blob.byte_length,
            sha256: blob.sha256,
            media_type: blob.media_type,
            encoding: blob.encoding,
        });
    }

    // Also include any item-owned bodies reported by list_contents that weren't in atom.contents.
    for (key, desc) in std::mem::take(&mut manifest_by_key) {
        if seen_keys.contains(&key) {
            continue;
        }
        let native_ref = pl_protocol::ContentRef {
            database_id: resolved_db_id.to_string(),
            target: ContentTarget::Body {
                owner: pl_protocol::ContentOwner::Item {
                    item_id: item.header.item_id.clone(),
                },
                key: key.key.clone(),
            },
        };
        let role: Option<ChatContentRole> =
            crate::studio::runtime::chat_item::atom_content_role_by_key(&key.key);
        let core_ref = ContentRef::Body(key);
        let blob = stream_content_to_sink(
            session,
            &core_ref,
            Some(desc.byte_length),
            desc.media_type,
            false,
            sink,
        )
        .await?;
        exported_contents.push(ExportedContentV1 {
            native_ref,
            role,
            path: blob.path,
            byte_length: blob.byte_length,
            sha256: blob.sha256,
            media_type: blob.media_type,
            encoding: blob.encoding,
        });
    }

    let source = EventSourceV1 {
        epoch: Some(epoch.clone()),
        effect_seq: completion_effect_seq(&entry.atom),
        turn_id: entry.atom.turn_id.clone(),
        attempt_id: entry.atom.attempt_id.clone(),
        tool_call_id: entry.atom.tool.as_ref().map(|t| t.call_id.clone()),
        completion_item_id: Some(item.header.item_id),
        completion_seq: Some(item.header.append_seq),
    };

    Ok(ExportedCompletionRecord {
        epoch,
        source,
        header: header_export,
        header_payload_fingerprint,
        atom: entry.atom,
        payload: exported_payload,
        contents: exported_contents,
    })
}

fn completion_effect_seq(atom: &pl_protocol::ChatAtom) -> Option<u64> {
    match &atom.lifecycle {
        pl_protocol::ChatAtomLifecycle::Terminal { ended, started, .. } => {
            ended.or(*started).map(|pos| pos.effect_seq)
        }
        pl_protocol::ChatAtomLifecycle::Active { started, .. } => started.map(|pos| pos.effect_seq),
    }
}

fn to_core_content_ref(reference: &pl_protocol::ContentRef) -> Result<ContentRef> {
    Ok(match &reference.target {
        ContentTarget::ItemPayload { item_id } => ContentRef::ItemPayload(item_id.clone()),
        ContentTarget::Body { owner, key } => ContentRef::Body(ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(owner)?,
            key: key.clone(),
        }),
    })
}

async fn list_item_manifests(
    session: &Session,
    item_id: &str,
    budget: &ExportChatBudget,
) -> Result<Vec<ContentDescriptor>> {
    let mut out = Vec::new();
    let mut after = None;
    let demand = ReadDemand::new(EXPORT_BATCH_MAX_ITEMS, pl_core::chat::MAX_READ_BYTES);
    loop {
        let page = match session
            .list_contents(
                ContentManifestRequest {
                    epoch: session.epoch(),
                    item_id: item_id.to_string(),
                    after: after.clone(),
                    demand,
                },
                budget,
            )
            .await
        {
            Ok(page) => page,
            Err(ChatError::NotFound(_)) => return Ok(out),
            Err(error) => return Err(error.into()),
        };
        out.extend(page.entries);
        match page.next {
            Some(next) => after = Some(next),
            None => break,
        }
    }
    Ok(out)
}

async fn stream_content_to_sink<S: ContentBlobSink>(
    session: &Session,
    reference: &ContentRef,
    expected_len: Option<u64>,
    explicit_media_type: Option<String>,
    is_payload: bool,
    sink: &mut S,
) -> Result<ExportedBlobV1> {
    let mut offset = 0_u64;
    let mut expected_generation = None;
    let mut total_bytes: Option<u64> = expected_len;
    let mut writer = sink.begin_blob().await?;
    let mut utf8 = Utf8StreamValidator::default();
    let mut first_non_ws: Option<u8> = None;

    loop {
        let window = session
            .read_content(ContentReadRequest {
                epoch: session.epoch(),
                reference: reference.clone(),
                offset,
                max_bytes: CONTENT_EXPORT_CHUNK_BYTES as usize,
                generation: expected_generation,
            })
            .await?;
        if let Some(gen_expected) = expected_generation {
            ensure!(
                window.generation == gen_expected,
                "content generation changed mid-export"
            );
        } else {
            expected_generation = Some(window.generation);
        }
        ensure!(
            window.sealed,
            "content became unsealed during completion export"
        );
        if let Some(expected) = total_bytes {
            ensure!(
                window.available_through == expected,
                "content length mismatch during export: expected {expected}, observed {}",
                window.available_through
            );
        } else {
            total_bytes = Some(window.available_through);
        }
        let chunk = window.bytes.as_bytes();
        if first_non_ws.is_none() {
            first_non_ws = chunk
                .iter()
                .copied()
                .find(|byte| !byte.is_ascii_whitespace());
        }
        utf8.push(chunk);
        writer.write_chunk(chunk).await?;
        offset = offset
            .checked_add(chunk.len() as u64)
            .context("content offset overflow during export")?;
        let target_len = total_bytes.unwrap_or(0);
        if offset >= target_len {
            break;
        }
        ensure!(
            !chunk.is_empty(),
            "stalled zero-byte content read before available_through ({offset}/{target_len})"
        );
    }

    let encoding = utf8.finish().to_string();
    let media_type = explicit_media_type.or_else(|| {
        (is_payload && encoding == "utf-8" && matches!(first_non_ws, Some(b'{') | Some(b'[')))
            .then(|| "application/json".to_string())
    });
    writer.finish(media_type, encoding).await
}

fn infer_payload_media_type(bytes: &[u8]) -> Option<String> {
    if std::str::from_utf8(bytes).is_ok()
        && bytes
            .iter()
            .copied()
            .find(|b| !b.is_ascii_whitespace())
            .is_some_and(|b| matches!(b, b'{' | b'['))
    {
        Some("application/json".to_string())
    } else {
        None
    }
}
