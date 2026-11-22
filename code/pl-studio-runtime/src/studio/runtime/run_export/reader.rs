//! Read-only HistoryReader exporter for canonical originals, lifecycle facts, and opaque bodies.
//!
//! Every original is selected by its fixed History cut and original-event index. Inline (`<= 16 KiB`)
//! and chunked BLOB bodies are exported to content-addressed files without involving Core Session or
//! a second timeline projection.

use std::collections::HashSet;

use crate::{ChatClassFilter, ChatContentRole, ChatScope};
use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};

use crate::history::{
    HistoryBodyPage, HistoryBodyRole, HistoryDemand, HistoryEventBodyRef, HistoryEventMeta,
    HistoryEventRecord, HistoryEventsQuery, HistoryReader, decode_event_envelope,
};

use super::types::{
    CONTENT_EXPORT_CHUNK_BYTES, ChatItemHeaderExportV3, EventSourceV3, ExportedBlobV3,
    ExportedContentV3, ExportedHistoryEventHeaderV3,
};
use super::writer::{BlobChunkWriter, ContentBlobSink};

const EXPORT_PAGE_ROWS: u32 = 128;
const EXPORT_PAGE_BYTES: u32 = 1024 * 1024;

fn demand() -> HistoryDemand {
    HistoryDemand {
        max_rows: EXPORT_PAGE_ROWS,
        max_bytes: EXPORT_PAGE_BYTES,
    }
}

/// One typed canonical completion ready for `EventBodyV3::Completion`.
pub struct ExportedCompletionRecord {
    pub source: EventSourceV3,
    pub header: ChatItemHeaderExportV3,
    pub header_payload_fingerprint: String,
    pub atom: HistoryEventMeta,
    pub payload: ExportedBlobV3,
    pub contents_manifest: ExportedBlobV3,
}

/// One bounded ascending original-event window through a captured History position.
pub struct HistoryExportPage {
    pub through: u64,
    pub next_pivot: u64,
    pub has_more: bool,
    pub records: Vec<ExportedCompletionRecord>,
}

/// Reads originals newer than `after_history_seq`, without reconstructing completion appendSeq.
///
/// The caller retains `(through, pivot)` while `has_more`. The indexed window is ascending, so every
/// returned page preserves History order without rescanning older rows.
pub async fn export_history_originals_window<S: ContentBlobSink>(
    history: &HistoryReader,
    through: u64,
    pivot: u64,
    sink: &mut S,
) -> Result<HistoryExportPage> {
    let (through, entries, has_more) = history
        .events_window(
            HistoryEventsQuery::Originals {
                scope: ChatScope {
                    query_class: ChatClassFilter::All {},
                    parent_id: None,
                },
            },
            Some(through),
            Some(pivot),
            true,
            demand(),
        )
        .await?;
    let next_pivot = entries.last().map(|detail| detail.seq).unwrap_or(pivot);
    let mut records = Vec::with_capacity(entries.len());
    for detail in entries {
        records.push(export_single_original(history, detail, sink).await?);
    }
    Ok(HistoryExportPage {
        through,
        next_pivot,
        has_more,
        records,
    })
}

async fn export_single_original<S: ContentBlobSink>(
    history: &HistoryReader,
    detail: HistoryEventRecord,
    sink: &mut S,
) -> Result<ExportedCompletionRecord> {
    ensure!(
        detail.original.is_some(),
        "History event {} is not a canonical original",
        detail.event_id
    );
    let envelope = decode_event_envelope(&detail)
        .with_context(|| format!("decode EventPayloadEnvelope for {}", detail.event_id))?;
    let atom = envelope.meta.clone();

    let payload = write_static_blob(
        sink,
        detail.payload_json.as_bytes(),
        Some("application/json".into()),
        "utf-8".into(),
    )
    .await?;

    let contents_manifest =
        stream_body_manifest(history, &detail.event_id, &envelope.bodies, sink).await?;

    let header = ChatItemHeaderExportV3::from_history(&detail);
    let header_payload_fingerprint =
        original_fingerprint(&header.event, &payload, &contents_manifest)?;
    let source = EventSourceV3 {
        history_event_id: Some(detail.event_id.clone()),
        history_event_seq: Some(detail.seq),
        turn_id: detail.turn_id.clone(),
        attempt_id: detail.attempt_id.clone(),
        tool_call_id: detail.call_id.clone(),
        ..EventSourceV3::default()
    };
    Ok(ExportedCompletionRecord {
        source,
        header,
        header_payload_fingerprint,
        atom,
        payload,
        contents_manifest,
    })
}

async fn stream_body_manifest<S: ContentBlobSink>(
    history: &HistoryReader,
    event_id: &str,
    declared_bodies: &[crate::history::HistoryBodyManifestEntry],
    sink: &mut S,
) -> Result<ExportedBlobV3> {
    let mut writer = sink.begin_blob().await?;
    let mut exported_body_ids = HashSet::new();

    for entry in declared_bodies {
        let history_role = HistoryBodyRole::from_string(entry.role.clone());
        let role = content_role_from_parts(&history_role, &entry.key);
        let (native_ref, blob) = if let Some(text) = &entry.inline_text {
            ensure!(
                text.len() as u64 == entry.byte_length,
                "inline body {} declared {} bytes but decoded to {}",
                entry.key,
                entry.byte_length,
                text.len()
            );
            let blob = write_static_blob(
                sink,
                text.as_bytes(),
                entry.media_type.clone(),
                "utf-8".into(),
            )
            .await?;
            (None, blob)
        } else if let Some(reference) = &entry.reference {
            exported_body_ids.insert(reference.body_id.clone());
            let blob = read_body_bytes(
                history,
                reference,
                sink,
                false,
                false,
                entry.media_type.clone(),
            )
            .await?
            .1;
            (Some(reference.clone()), blob)
        } else if entry.byte_length == 0 {
            let blob =
                write_static_blob(sink, &[], entry.media_type.clone(), "utf-8".into()).await?;
            (None, blob)
        } else {
            anyhow::bail!(
                "body entry {} for event {} has neither inlineText nor reference",
                entry.key,
                event_id
            );
        };
        let line = serde_json::to_vec(&ExportedContentV3 {
            body_key: entry.key.clone(),
            native_ref,
            role,
            history_role,
            path: blob.path,
            byte_length: blob.byte_length,
            sha256: blob.sha256,
            media_type: blob.media_type,
            encoding: blob.encoding,
        })?;
        writer.write_chunk(&line).await?;
        writer.write_chunk(b"\n").await?;
    }

    let mut cursor = None;
    let mut last_ordinal = None;
    loop {
        let page = history
            .list_bodies(event_id.to_owned(), cursor.clone(), demand())
            .await?;
        let HistoryBodyPage {
            owner_event_id,
            entries,
            next,
        } = page;
        ensure!(
            owner_event_id == event_id,
            "History body directory belonged to another event"
        );
        for body in entries {
            ensure!(
                last_ordinal.is_none_or(|ordinal| body.ordinal > ordinal),
                "History body ordinals did not advance"
            );
            last_ordinal = Some(body.ordinal);
            if exported_body_ids.contains(&body.reference.body_id) {
                continue;
            }
            let role = content_role_from_parts(&body.role, &body.body_key);
            let blob = read_body_bytes(
                history,
                &body.reference,
                sink,
                false,
                false,
                body.media_type.clone(),
            )
            .await?
            .1;
            let line = serde_json::to_vec(&ExportedContentV3 {
                body_key: body.body_key,
                native_ref: Some(body.reference),
                role,
                history_role: body.role,
                path: blob.path,
                byte_length: blob.byte_length,
                sha256: blob.sha256,
                media_type: blob.media_type,
                encoding: blob.encoding,
            })?;
            writer.write_chunk(&line).await?;
            writer.write_chunk(b"\n").await?;
        }
        let Some(next) = next else {
            break;
        };
        ensure!(
            cursor.as_deref() != Some(next.as_str()),
            "History body directory cursor did not advance"
        );
        cursor = Some(next);
    }
    writer
        .finish(Some("application/x-ndjson".into()), "utf-8".into())
        .await
}

fn content_role_from_parts(
    history_role: &HistoryBodyRole,
    body_key: &str,
) -> Option<ChatContentRole> {
    match history_role {
        HistoryBodyRole::ReasoningSummary => Some(ChatContentRole::ReasoningSummary),
        HistoryBodyRole::ToolArguments => Some(ChatContentRole::ToolArguments),
        HistoryBodyRole::ToolOutput => Some(ChatContentRole::ToolOutput),
        HistoryBodyRole::Body => content_role_from_key(body_key),
        _ => None,
    }
}

fn content_role_from_key(key: &str) -> Option<ChatContentRole> {
    let key = key.rsplit(':').next().unwrap_or(key);
    if key == "body"
        || key.starts_with("part.outputText.")
        || key.starts_with("part.reasoningText.")
    {
        Some(ChatContentRole::Body)
    } else if key.starts_with("part.summaryText.") {
        Some(ChatContentRole::ReasoningSummary)
    } else if key == "tool.arguments" {
        Some(ChatContentRole::ToolArguments)
    } else if key == "tool.result" {
        Some(ChatContentRole::ToolOutput)
    } else {
        None
    }
}

async fn write_static_blob<S: ContentBlobSink>(
    sink: &mut S,
    bytes: &[u8],
    media_type: Option<String>,
    encoding: String,
) -> Result<ExportedBlobV3> {
    let mut writer = sink.begin_blob().await?;
    for chunk in bytes.chunks(CONTENT_EXPORT_CHUNK_BYTES as usize) {
        writer.write_chunk(chunk).await?;
    }
    writer.finish(media_type, encoding).await
}

fn original_fingerprint(
    header: &ExportedHistoryEventHeaderV3,
    payload: &ExportedBlobV3,
    contents_manifest: &ExportedBlobV3,
) -> Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(serde_json::to_vec(header)?);
    hasher.update(payload.sha256.as_bytes());
    hasher.update(contents_manifest.sha256.as_bytes());
    Ok(hex::encode(hasher.finalize()))
}

async fn read_body_bytes<S: ContentBlobSink>(
    history: &HistoryReader,
    reference: &HistoryEventBodyRef,
    sink: &mut S,
    is_payload: bool,
    collect: bool,
    explicit_media_type: Option<String>,
) -> Result<(Option<Vec<u8>>, ExportedBlobV3)> {
    let mut offset = 0_u64;
    let mut bytes = collect.then(Vec::new);
    let mut writer = sink.begin_blob().await?;
    let mut utf8 = Utf8StreamValidator::default();
    let mut first_non_ws = None;
    while offset < reference.byte_length {
        let max_bytes =
            (reference.byte_length - offset).min(u64::from(CONTENT_EXPORT_CHUNK_BYTES)) as u32;
        let window = history
            .read_body(reference.clone(), offset, max_bytes)
            .await?;
        ensure!(
            window.offset == offset
                && !window.bytes.is_empty()
                && window.bytes.len() <= max_bytes as usize
                && window.total_length == reference.byte_length,
            "History body range did not advance within its declared length"
        );
        if first_non_ws.is_none() {
            first_non_ws = window
                .bytes
                .iter()
                .copied()
                .find(|byte| !byte.is_ascii_whitespace());
        }
        utf8.push(&window.bytes);
        writer.write_chunk(&window.bytes).await?;
        if let Some(bytes) = &mut bytes {
            bytes.extend_from_slice(&window.bytes);
        }
        offset = offset
            .checked_add(window.bytes.len() as u64)
            .context("History body offset overflow")?;
    }
    let encoding = utf8.finish().to_string();
    let media_type = explicit_media_type.or_else(|| {
        (is_payload && encoding == "utf-8" && matches!(first_non_ws, Some(b'{') | Some(b'[')))
            .then(|| "application/json".to_string())
    });
    let blob = writer.finish(media_type, encoding).await?;
    Ok((bytes, blob))
}

/// Incremental UTF-8 validator across arbitrary History body window splits.
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
            Err(error) if error.error_len().is_some() => self.valid = false,
            Err(error) => {
                let remainder = &slice[error.valid_up_to()..];
                if remainder.len() <= 3 {
                    self.pending[..remainder.len()].copy_from_slice(remainder);
                    self.pending_len = remainder.len();
                } else {
                    self.valid = false;
                }
            }
        }
    }

    fn finish(self) -> &'static str {
        if !self.initialized || (self.valid && self.pending_len == 0) {
            "utf-8"
        } else {
            "binary"
        }
    }
}
