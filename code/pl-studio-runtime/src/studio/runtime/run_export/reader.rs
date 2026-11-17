//! Read-only HistoryReader exporter for canonical originals, lifecycle facts, and opaque bodies.
//!
//! Every original is selected by its fixed History cut and original-event index. Payload and body
//! bytes are streamed directly from `HistoryEventBodyRef` in bounded 64 KiB windows. No Core chat
//! Session, completion append sequence, router, or second timeline projection is involved.

use anyhow::{Context, Result, ensure};
use pl_protocol::{ChatClassFilter, ChatContentRole, ChatScope};
use sha2::{Digest, Sha256};

use crate::history::{
    HEAD_MAX_BYTES, HistoryBodyEntry, HistoryBodyPage, HistoryBodyRole, HistoryDemand,
    HistoryEntityHead, HistoryEventBodyRef, HistoryEventDetail, HistoryEventHeader,
    HistoryEventsQuery, HistoryReader, HistoryRowHead,
};

use super::types::{
    CONTENT_EXPORT_CHUNK_BYTES, ChatItemHeaderExportV3, EventSourceV3, ExportedBlobV3,
    ExportedContentV3,
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
    pub atom: HistoryEntityHead,
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
    let next_pivot = entries
        .last()
        .map(|detail| detail.header.seq)
        .unwrap_or(pivot);
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
    detail: HistoryEventDetail,
    sink: &mut S,
) -> Result<ExportedCompletionRecord> {
    ensure!(
        detail.header.original.is_some(),
        "History event {} is not a canonical original",
        detail.header.event_id
    );
    let metadata = find_body_entry(history, &detail.header.event_id, |body| {
        body.role == HistoryBodyRole::CanonicalMetadata
    })
    .await?
    .with_context(|| {
        format!(
            "canonical original {} omitted its HistoryEntityHead metadata",
            detail.header.event_id
        )
    })?;
    ensure!(
        metadata.reference.byte_length <= HEAD_MAX_BYTES as u64,
        "canonical metadata for {} exceeds {HEAD_MAX_BYTES} bytes",
        detail.header.event_id
    );
    let metadata_bytes = read_body_bytes(
        history,
        &metadata.reference,
        sink,
        false,
        true,
        metadata.media_type.clone(),
    )
    .await?
    .0
    .context("canonical metadata was not materialized")?;
    let metadata_head: HistoryEntityHead = serde_json::from_slice(&metadata_bytes)
        .with_context(|| format!("decode HistoryEntityHead for {}", detail.header.event_id))?;
    let payload_ref = detail
        .payload_ref
        .clone()
        .context("canonical History original omitted its opaque payload")?;
    let payload_entry = find_body_entry(history, &detail.header.event_id, |body| {
        body.reference == payload_ref
    })
    .await?
    .context("History payload reference is absent from its body directory")?;
    ensure!(
        payload_entry.role == HistoryBodyRole::CanonicalPayload,
        "History payload body is not typed canonicalPayload"
    );
    let atom = match detail.head {
        Some(HistoryRowHead::Single(head) | HistoryRowHead::Member(head)) => head,
        None => metadata_head.clone(),
        Some(_) => {
            anyhow::bail!(
                "canonical original {} has a non-entity row head",
                detail.header.event_id
            )
        }
    };
    ensure!(
        atom == metadata_head,
        "canonical metadata and indexed History head disagree for {}",
        detail.header.event_id
    );

    let payload = read_body_bytes(
        history,
        &payload_ref,
        sink,
        true,
        false,
        payload_entry.media_type.clone(),
    )
    .await?
    .1;

    let contents_manifest = stream_body_manifest(history, &detail.header.event_id, sink).await?;

    let header = ChatItemHeaderExportV3::from_history(&detail.header);
    let header_payload_fingerprint =
        original_fingerprint(&detail.header, &payload, &contents_manifest)?;
    let source = EventSourceV3 {
        history_event_id: Some(detail.header.event_id.clone()),
        history_event_seq: Some(detail.header.seq),
        turn_id: detail.header.turn_id.clone(),
        attempt_id: detail.header.attempt_id.clone(),
        tool_call_id: detail.header.call_id.clone(),
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

async fn find_body_entry(
    history: &HistoryReader,
    event_id: &str,
    predicate: impl Fn(&HistoryBodyEntry) -> bool,
) -> Result<Option<HistoryBodyEntry>> {
    let mut cursor = None;
    let mut found = None;
    loop {
        let page = history
            .list_bodies(event_id.to_owned(), cursor.clone(), demand())
            .await?;
        let HistoryBodyPage {
            owner_event_id,
            entries: page_entries,
            next,
        } = page;
        ensure!(
            owner_event_id == event_id,
            "History body directory belonged to another event"
        );
        for entry in page_entries {
            if predicate(&entry) {
                ensure!(
                    found.is_none(),
                    "History body directory contains duplicate selected roles"
                );
                found = Some(entry);
            }
        }
        let Some(next) = next else {
            return Ok(found);
        };
        ensure!(
            cursor.as_deref() != Some(next.as_str()),
            "History body directory exceeded its bounded cursor traversal"
        );
        cursor = Some(next);
    }
}

async fn stream_body_manifest<S: ContentBlobSink>(
    history: &HistoryReader,
    event_id: &str,
    sink: &mut S,
) -> Result<ExportedBlobV3> {
    let mut writer = sink.begin_blob().await?;
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
            let role = content_role(&body);
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
                native_ref: body.reference,
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

fn content_role(body: &HistoryBodyEntry) -> Option<ChatContentRole> {
    match &body.role {
        HistoryBodyRole::ReasoningSummary => Some(ChatContentRole::ReasoningSummary),
        HistoryBodyRole::ToolArguments => Some(ChatContentRole::ToolArguments),
        HistoryBodyRole::ToolOutput => Some(ChatContentRole::ToolOutput),
        HistoryBodyRole::Body => content_role_from_key(&body.body_key),
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

fn original_fingerprint(
    header: &HistoryEventHeader,
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
