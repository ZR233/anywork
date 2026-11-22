//! Bounded bot-reply decoding from immutable History originals and current previews.

use super::projection::{ReplyProjection, gap};
use crate::history::{
    EventPayloadEnvelope, HistoryBodyManifestEntry, HistoryBusinessRowHead,
    HistoryBusinessRowScope, HistoryDemand, HistoryEventBodyRef, HistoryEventMeta,
    HistoryEventRecord, HistoryEventsQuery, HistoryReader, HistoryTurnState,
    body::decode_business_head_from_record, decode_event_envelope,
};
use crate::{ChatAtomKind, ChatSourceId, ReadDemand, ThreadTextChannel, TurnState};

pub(super) const MAX_TURN_CONTENT_ITEMS: usize = 16_384;
pub(super) const MAX_TURN_BODY_BYTES: usize = 800_000;
const WINDOW_BYTES: u32 = 32 * 1024;

pub(super) fn demand() -> ReadDemand {
    ReadDemand {
        max_items: 100,
        max_bytes: 256 * 1024,
    }
}

#[derive(Debug, thiserror::Error)]
pub(super) enum FinalError {
    #[error("{0}")]
    Retryable(String),
    #[error("{0}")]
    Attention(String),
}

pub(super) enum FinalText {
    CompleteNoText,
    CompleteText(String),
}

#[derive(Clone)]
pub(super) struct ReplyItem {
    pub(super) member_id: String,
    pub(super) id: String,
    pub(super) kind: ReplyItemKind,
}

#[derive(Clone)]
pub(super) enum ReplyItemKind {
    Final {
        body: Body,
        preview: String,
    },
    Terminal(TurnState),
    Interaction(String),
    Files {
        call_id: String,
        receipt: pl_tool::file_display::FileDisplayReceipt,
        byte_length: usize,
    },
}

impl ReplyItem {
    pub(super) fn preview_bytes(&self) -> usize {
        match &self.kind {
            ReplyItemKind::Final { body, .. } => body.byte_length as usize,
            ReplyItemKind::Files { byte_length, .. } => *byte_length,
            _ => 0,
        }
    }
}

#[derive(Clone)]
pub(super) struct Body {
    key: String,
    pub(super) byte_length: u64,
    inline_text: Option<String>,
    reference: Option<HistoryEventBodyRef>,
}

impl From<HistoryBodyManifestEntry> for Body {
    fn from(entry: HistoryBodyManifestEntry) -> Self {
        Self {
            key: entry.key,
            byte_length: entry.byte_length,
            inline_text: entry.inline_text,
            reference: entry.reference,
        }
    }
}

pub(super) async fn history_turn_items(
    reader: &HistoryReader,
    turn_id: &str,
    cut: crate::history::HistoryCut,
) -> Result<Vec<ReplyItem>, FinalError> {
    let mut cursor = None;
    let mut items = Vec::new();
    loop {
        let page = reader
            .events_page(
                HistoryEventsQuery::Turn {
                    turn_id: turn_id.to_owned(),
                },
                Some(cut.clone()),
                cursor,
                HistoryDemand {
                    max_rows: 128,
                    max_bytes: 1024 * 1024,
                },
            )
            .await
            .map_err(|error| read_failure("reply Turn originals failed", error))?;
        for detail in page.entries {
            if detail.original.is_some()
                && let Some(item) = decode_original(reader, &detail, turn_id).await?
            {
                items.push((detail.seq, item));
                if items.len() > MAX_TURN_CONTENT_ITEMS {
                    return Err(FinalError::Attention(
                        "reply Turn exceeded its completion-record budget".into(),
                    ));
                }
            }
        }
        let Some(next) = page.next else {
            break;
        };
        cursor = Some(next);
    }
    items.sort_by_key(|(seq, _)| *seq);
    let items = items.into_iter().map(|(_, item)| item).collect::<Vec<_>>();
    let bytes = items
        .iter()
        .try_fold(0usize, |bytes, item| {
            bytes.checked_add(item.preview_bytes())
        })
        .ok_or_else(|| gap("reply body size overflow"))?;
    if bytes > MAX_TURN_BODY_BYTES {
        return Err(FinalError::Attention(
            "reply Turn exceeded its body budget".into(),
        ));
    }
    Ok(items)
}

pub(super) async fn history_turn_terminal(
    reader: &HistoryReader,
    turn_id: &str,
    cut: crate::history::HistoryCut,
) -> Result<Option<ReplyItem>, FinalError> {
    let mut cursor = None;
    loop {
        let page = reader
            .events_page(
                HistoryEventsQuery::Turn {
                    turn_id: turn_id.to_owned(),
                },
                Some(cut.clone()),
                cursor,
                HistoryDemand {
                    max_rows: 128,
                    max_bytes: 1024 * 1024,
                },
            )
            .await
            .map_err(|error| read_failure("reply Turn head failed", error))?;
        for entry in page.entries {
            if entry.row_scope != Some(HistoryBusinessRowScope::Turn) {
                continue;
            }
            let HistoryBusinessRowHead::Turn(head) = decode_business_head_from_record(&entry)
                .map_err(|error| gap(&format!("malformed reply Turn head: {error}")))?
            else {
                continue;
            };
            if matches!(
                head.state,
                HistoryTurnState::Completed
                    | HistoryTurnState::Cancelled
                    | HistoryTurnState::Failed
                    | HistoryTurnState::BudgetLimited
            ) {
                let turn = crate::studio::runtime::history_turn(reader, head)
                    .await
                    .map_err(|error| {
                        read_failure("reply immutable Turn detail failed", error)
                    })?;
                if turn.id != turn_id || turn.state.completed_at().is_none() {
                    return Err(gap("reply Turn detail does not prove its terminal outcome"));
                }
                return Ok(Some(ReplyItem {
                    member_id: format!("turn:{turn_id}"),
                    id: entry.event_id,
                    kind: ReplyItemKind::Terminal(turn.state),
                }));
            }
        }
        let Some(next) = page.next else {
            return Ok(None);
        };
        cursor = Some(next);
    }
}

async fn decode_original(
    reader: &HistoryReader,
    detail: &HistoryEventRecord,
    target_turn: &str,
) -> Result<Option<ReplyItem>, FinalError> {
    if detail.payload_schema != "anywork.event/1"
        || detail.timeline_role == crate::history::HistoryTimelineRole::Hidden
    {
        return Ok(None);
    }
    let id = detail
        .entity_id
        .as_deref()
        .filter(|id| !id.is_empty())
        .ok_or_else(|| gap("reply original has no entity identity"))?;
    if detail.turn_id.as_deref() != Some(target_turn) {
        return Ok(None);
    }
    if matches!(&detail.source, Some(ChatSourceId::InboxMessage { .. })) {
        return Ok(None);
    }
    let envelope = decode_event_envelope(detail)
        .map_err(|error| gap(&format!("malformed reply envelope: {error}")))?;
    let head = &envelope.meta;
    if head.entity_kind == ChatAtomKind::ToolCall
        && head
            .tool
            .as_ref()
            .is_none_or(|tool| tool.name != pl_tool::file_display::TOOL_SHOW_FILES)
    {
        return Ok(None);
    }
    if !matches!(
        &head.entity_kind,
        ChatAtomKind::Text
            | ChatAtomKind::ToolCall
            | ChatAtomKind::Interaction
            | ChatAtomKind::Plan
            | ChatAtomKind::TurnReceipt
            | ChatAtomKind::Unknown
    ) {
        return Ok(None);
    }
    decode_envelope(reader, head, detail, id, &envelope, target_turn).await
}

async fn decode_envelope(
    reader: &HistoryReader,
    head: &HistoryEventMeta,
    detail: &HistoryEventRecord,
    id: &str,
    envelope: &EventPayloadEnvelope,
    target: &str,
) -> Result<Option<ReplyItem>, FinalError> {
    if envelope.contract != "anywork.event/1" {
        return Err(gap("unsupported reply envelope contract"));
    }
    if envelope.turn_id.as_deref().or(detail.turn_id.as_deref()) != Some(target) {
        return Ok(None);
    }
    let expected = match &head.entity_kind {
        ChatAtomKind::Text => Some("text"),
        ChatAtomKind::Interaction | ChatAtomKind::ToolCall => Some("tool"),
        ChatAtomKind::Plan => Some("plan"),
        ChatAtomKind::TurnReceipt => Some("turn"),
        ChatAtomKind::Unknown => None,
        _ => return Ok(None),
    };
    if expected.is_some_and(|kind| kind != envelope.item_type) {
        return Err(gap("reply metadata and frozen payload domain conflict"));
    }
    if let Some(tool) = &head.tool
        && (envelope.data["invocation"]["toolCallId"].as_str() != Some(tool.call_id.as_str())
            || envelope.data["invocation"]["name"].as_str() != Some(tool.name.as_str()))
    {
        return Err(gap(
            "reply metadata and frozen payload tool identity conflict",
        ));
    }
    let bodies: Vec<Body> = envelope.bodies.iter().cloned().map(Body::from).collect();
    let kind = match envelope.item_type.as_str() {
        "text" => {
            let channel: ThreadTextChannel = serde_json::from_value(
                envelope
                    .data
                    .get("channel")
                    .cloned()
                    .ok_or_else(|| gap("reply text lacks channel"))?,
            )
            .map_err(|error| gap(&format!("invalid reply text channel: {error}")))?;
            if head.text_channel.as_ref() != Some(&channel) {
                return Err(gap("reply metadata and frozen payload channel conflict"));
            }
            if channel != ThreadTextChannel::Final {
                return Ok(None);
            }
            let body = unique_body(&bodies, "body", detail, id)?;
            let bytes = body.read(reader, true).await?;
            let preview = match String::from_utf8(bytes) {
                Ok(text) => text,
                Err(error) => {
                    return Err(gap(&format!("canonical Final body is not UTF-8: {error}")));
                }
            };
            ReplyItemKind::Final { body, preview }
        }
        "turn" => {
            let state: TurnState = serde_json::from_value(
                envelope
                    .data
                    .get("outcome")
                    .cloned()
                    .ok_or_else(|| gap("reply terminal lacks canonical outcome"))?,
            )
            .map_err(|error| gap(&format!("invalid canonical TurnState: {error}")))?;
            if state.completed_at().is_none() {
                return Err(gap(
                    "completed reply original contains nonterminal TurnState",
                ));
            }
            ReplyItemKind::Terminal(state)
        }
        "tool" => {
            if head.entity_kind == ChatAtomKind::ToolCall
                && envelope.data["invocation"]["presentationContract"].as_str()
                    == Some(pl_tool::file_display::FILE_DISPLAY_PRESENTATION)
                && envelope.data["state"]["kind"].as_str() == Some("succeeded")
            {
                let call_id = envelope.data["invocation"]["toolCallId"]
                    .as_str()
                    .filter(|id| !id.is_empty())
                    .ok_or_else(|| gap("file display lacks frozen tool call identity"))?;
                let body = unique_body(&bodies, "tool.output-artifacts", detail, id)?;
                let bytes = body.read(reader, true).await?;
                let artifacts: Vec<serde_json::Value> = serde_json::from_slice(&bytes)
                    .map_err(|error| gap(&format!("malformed display artifacts: {error}")))?;
                let mut receipt = None;
                for artifact in artifacts {
                    if artifact["kind"].as_str() != Some("opaque") {
                        continue;
                    }
                    let payload: pl_core::context::OpaquePayload =
                        serde_json::from_value(artifact["payload"].clone()).map_err(|error| {
                            gap(&format!("invalid saved display payload: {error}"))
                        })?;
                    if let Some(saved) = pl_tool::file_display::saved_file_display_receipt(&payload)
                        .map_err(|error| gap(&format!("invalid file display receipt: {error}")))?
                        && receipt.replace(saved).is_some()
                    {
                        return Err(gap("file display has multiple saved receipts"));
                    }
                }
                let receipt = receipt.ok_or_else(|| gap("file display has no verified receipt"))?;
                return Ok(Some(ReplyItem {
                    member_id: id.into(),
                    id: id.into(),
                    kind: ReplyItemKind::Files {
                        call_id: call_id.into(),
                        receipt,
                        byte_length: body.byte_length as usize,
                    },
                }));
            }
            let Some(input) = envelope
                .data
                .get("userInput")
                .filter(|value| !value.is_null())
            else {
                if head.entity_kind == ChatAtomKind::Interaction {
                    return Err(gap("reply Interaction original lacks frozen user input"));
                }
                return Ok(None);
            };
            let interaction = input
                .get("interactionId")
                .and_then(serde_json::Value::as_str)
                .ok_or_else(|| gap("reply tool interaction lacks identity"))?;
            ReplyItemKind::Interaction(interaction.into())
        }
        "plan" => {
            let interaction = envelope
                .data
                .get("interactionId")
                .and_then(serde_json::Value::as_str)
                .ok_or_else(|| gap("reply plan interaction lacks identity"))?;
            ReplyItemKind::Interaction(interaction.into())
        }
        _ => return Err(gap("unsupported target reply payload type")),
    };
    Ok(Some(ReplyItem {
        member_id: id.into(),
        id: id.into(),
        kind,
    }))
}

fn unique_body(
    bodies: &[Body],
    key: &str,
    detail: &HistoryEventRecord,
    _id: &str,
) -> Result<Body, FinalError> {
    let mut matching = bodies.iter().filter(|body| body.key == key);
    let body = matching
        .next()
        .cloned()
        .ok_or_else(|| gap("canonical reply body is missing"))?;
    if matching.next().is_some() {
        return Err(gap("canonical reply body has duplicate declarations"));
    }
    body.validate(detail, _id)?;
    Ok(body)
}

impl Body {
    fn validate(&self, detail: &HistoryEventRecord, _item: &str) -> Result<(), FinalError> {
        check_length(self.byte_length)?;
        match (&self.inline_text, &self.reference) {
            (Some(text), None) if text.len() as u64 == self.byte_length => Ok(()),
            (None, Some(reference))
                if reference.owner_event_id == detail.event_id
                    && reference.body_key == self.key
                    && reference.byte_length == self.byte_length
                    && reference.byte_start == 0 =>
            {
                Ok(())
            }
            _ => Err(gap(
                "canonical reply body reference identity or length conflict",
            )),
        }
    }

    async fn read(&self, reader: &HistoryReader, complete: bool) -> Result<Vec<u8>, FinalError> {
        match (&self.inline_text, &self.reference) {
            (Some(text), None) => Ok(text.as_bytes().to_vec()),
            (None, Some(reference)) => read_bytes(reader, reference, complete).await,
            _ => Err(gap("canonical reply body has no unique source")),
        }
    }
}

fn check_length(length: u64) -> Result<(), FinalError> {
    if length > MAX_TURN_BODY_BYTES as u64 {
        return Err(FinalError::Attention(
            "canonical turn content exceeded 800000 UTF-8 bytes".into(),
        ));
    }
    Ok(())
}

async fn read_bytes(
    reader: &HistoryReader,
    reference: &HistoryEventBodyRef,
    complete: bool,
) -> Result<Vec<u8>, FinalError> {
    check_length(reference.byte_length)?;
    let mut bytes = Vec::new();
    loop {
        let offset = bytes.len() as u64;
        let max_bytes = WINDOW_BYTES.min((reference.byte_length - offset).max(1) as u32);
        let window = reader
            .read_body(reference.clone(), offset, max_bytes)
            .await
            .map_err(|error| read_failure("canonical reply history range failed", error))?;
        if window.offset != offset
            || window.total_length != reference.byte_length
            || window.bytes.len() > max_bytes as usize
            || offset + window.bytes.len() as u64 > reference.byte_length
            || window.bytes.is_empty() && offset < reference.byte_length
        {
            return Err(gap(
                "canonical reply history range identity or coverage conflict",
            ));
        }
        bytes.extend(window.bytes);
        if bytes.len() as u64 == reference.byte_length || !complete {
            return Ok(bytes);
        }
    }
}

pub(super) fn collect_complete_turn_text(
    projection: &ReplyProjection,
) -> Result<FinalText, FinalError> {
    let items = projection.completed()?;
    let mut text = String::new();
    for item in items {
        if let ReplyItemKind::Final { body, preview } = &item.kind {
            if preview.len() as u64 != body.byte_length {
                return Err(gap(
                    "canonical Final preview does not cover the complete body",
                ));
            }
            if text.len().saturating_add(preview.len()) > MAX_TURN_BODY_BYTES {
                return Err(FinalError::Attention(
                    "canonical turn content exceeded 800000 UTF-8 bytes".into(),
                ));
            }
            text.push_str(preview);
        }
    }
    if text.trim().is_empty() {
        Ok(FinalText::CompleteNoText)
    } else {
        Ok(FinalText::CompleteText(text))
    }
}

pub(super) fn activity_preview(
    atom: &crate::CurrentAtom,
    body: &crate::CurrentContentPreview,
    turn_id: &str,
) -> Option<String> {
    if atom.turn_id.as_deref() != Some(turn_id)
        || atom.kind != ChatAtomKind::Text
        || atom.text_channel != Some(ThreadTextChannel::Final)
        || !matches!(&atom.lifecycle, crate::ChatAtomLifecycle::Active { .. })
        || body.id != atom.id
        || body.role != crate::CurrentContentRole::Response
    {
        return None;
    }
    Some(body.text.clone())
}

pub(super) fn read_failure(context: &str, error: impl Into<anyhow::Error>) -> FinalError {
    let error = crate::studio_error_from_anyhow(error.into());
    let diagnostic = format!(
        "{context}: {} (correlation id: {})",
        error.code.label(),
        error.correlation_id
    );
    if error.retryable {
        FinalError::Retryable(diagnostic)
    } else {
        FinalError::Attention(diagnostic)
    }
}
