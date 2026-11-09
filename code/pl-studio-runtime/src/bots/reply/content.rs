//! Explicit bounded completion coverage and reliable final verification on the original read lease.

use super::projection::{ReplyProjection, gap};
use crate::studio::{ConversationReader, StudioRuntime};
use pl_protocol::{
    ActivitySnapshot, ChatAtomKind, ChatAtomLifecycle, ChatContentRole, ChatSourceId,
    CompletedEntry, ContentOwner, ContentRange, ContentRef, ContentTarget, PayloadData, ReadDemand,
    ThreadTextChannel, TurnState,
};
use serde::Deserialize;
use std::collections::BTreeSet;

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
    /// Frozen payload/content owner, which may differ from the stable member.
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

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Body {
    key: String,
    pub(super) byte_length: u64,
    inline: Option<Vec<u8>>,
    reference: Option<ContentRef>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Envelope {
    contract: String,
    #[serde(rename = "type")]
    kind: String,
    data: serde_json::Value,
    turn_id: Option<String>,
    bodies: Vec<Body>,
}

/// Decode only the frozen public envelope. Unknown/bad payload is a gap, never
/// permission to silently omit a possible Final. No private checkpoint fallback.
pub(super) async fn decode_entry(
    reader: &ConversationReader,
    entry: &CompletedEntry,
    turn_id: &str,
) -> Result<Option<ReplyItem>, FinalError> {
    let source = &entry.atom;
    let id = entry.record_id.as_str();
    if id.is_empty()
        || entry.completion_seq == 0
        || source.completion_item_id.as_deref() != Some(id)
        || source.completion_seq != Some(entry.completion_seq)
        || !matches!(source.lifecycle, ChatAtomLifecycle::Terminal { .. })
    {
        return Err(gap(
            "reply completion identity or publication position conflict",
        ));
    }
    let payload = source
        .payload
        .as_ref()
        .ok_or_else(|| gap("terminal reply atom has no frozen payload"))?;
    let atom = ReplyMetadata {
        id: source.id.clone(),
        source: source.source.clone(),
        turn_id: source.turn_id.clone(),
        kind: source.kind,
        tool: source.tool.clone(),
        text_channel: source.text_channel,
        contents: source.contents.clone(),
    };
    if atom.id.is_empty() || source_identity(&atom.source).is_empty() {
        return Err(gap("reply item has no identity"));
    }
    if let ChatSourceId::ForegroundTurn { turn_id } = &atom.source
        && atom.turn_id.as_deref() != Some(turn_id)
    {
        return Err(gap("reply source and Turn identity conflict"));
    }
    // A received external message remains input data. Its claimed channel,
    // outcome or payload cannot authorize a bot response or a Turn terminal.
    if matches!(atom.source, ChatSourceId::InboxMessage { .. }) {
        return Ok(None);
    }
    if let PayloadData::Deferred { reference, .. } = payload
        && (reference.database_id.is_empty()
            || !matches!(&reference.target, ContentTarget::ItemPayload { item_id } if item_id == id))
    {
        return Err(gap("deferred reply payload identity conflict"));
    }
    // Metadata only selects candidates; it does not authorize delivery. Avoid
    // fetching arbitrary tool logs (which can be much larger than the reply budget).
    // A candidate still needs its actual frozen output receipt decoded below.
    if atom.kind == ChatAtomKind::ToolCall
        && (atom
            .tool
            .as_ref()
            .is_none_or(|tool| tool.name != pl_tool::file_display::TOOL_SHOW_FILES)
            || atom.turn_id.as_deref() != Some(turn_id)
            || !matches!(&atom.source, ChatSourceId::ForegroundTurn { turn_id: source } if source == turn_id))
    {
        return Ok(None);
    }
    // Main also includes work now. Its known domain is sufficient to skip
    // unrelated payloads; Unknown never grants permission to omit a possible Final.
    if !matches!(
        atom.kind,
        ChatAtomKind::Text
            | ChatAtomKind::ToolCall
            | ChatAtomKind::Interaction
            | ChatAtomKind::Plan
            | ChatAtomKind::TurnReceipt
            | ChatAtomKind::Unknown
    ) {
        return Ok(None);
    }
    let bytes = match payload {
        PayloadData::Inline { bytes } => {
            check_length(bytes.len() as u64)?;
            bytes.clone()
        }
        PayloadData::Deferred {
            reference,
            byte_length,
        } => read_bytes(reader, reference, *byte_length, true).await?,
    };
    decode_envelope(reader, &atom, id, &bytes, turn_id).await
}

/// Read only a bounded actual Final body. Activity carries references, never
/// authorizes commentary by display role, and never proves Turn completion.
pub(super) async fn decode_activity(
    reader: &ConversationReader,
    snapshot: &ActivitySnapshot,
    turn_id: &str,
    index: usize,
) -> Result<Option<(String, String)>, FinalError> {
    let atom = &snapshot.entries[index].atom;
    if atom.turn_id.as_deref() != Some(turn_id)
        || atom.kind != ChatAtomKind::Text
        || atom.text_channel != Some(ThreadTextChannel::Final)
        || !matches!(&atom.source, ChatSourceId::ForegroundTurn { turn_id: source } if source == turn_id)
        || !matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
    {
        return Ok(None);
    }
    let mut bodies = atom
        .contents
        .iter()
        .filter(|content| content.role == ChatContentRole::Body);
    let body = bodies
        .next()
        .ok_or_else(|| gap("active Final has no body reference"))?;
    if bodies.next().is_some() || atom.id.is_empty() {
        return Err(gap("active Final body identity conflict"));
    }
    if !matches!(&body.reference.target,
        ContentTarget::Body { owner: ContentOwner::Item { item_id }, key }
        if item_id == &atom.id && key == "body")
    {
        return Err(gap("active Final content ownership conflict"));
    }
    let window = reader
        .read_content(
            &body.reference,
            ContentRange {
                offset: 0,
                max_bytes: WINDOW_BYTES,
            },
        )
        .await
        .map_err(|error| read_failure("active Final content range failed", error))?;
    check_length(window.available_through)?;
    if window.offset != 0
        || window.bytes.len() > WINDOW_BYTES as usize
        || window.bytes.len() as u64 > window.available_through
        || window.generation.is_empty()
        || window.bytes.is_empty() && window.available_through > 0
    {
        return Err(gap("active Final content range coverage conflict"));
    }
    let text = match String::from_utf8(window.bytes) {
        Ok(text) => text,
        Err(error)
            if error.utf8_error().error_len().is_none()
                && (error.as_bytes().len() as u64) < window.available_through =>
        {
            let through = error.utf8_error().valid_up_to();
            String::from_utf8(error.into_bytes()[..through].to_vec())
                .map_err(|_| gap("invalid active Final UTF-8 prefix"))?
        }
        Err(_) => return Err(gap("invalid active Final UTF-8")),
    };
    Ok(Some((atom.id.clone(), text)))
}

fn source_identity(source: &ChatSourceId) -> &str {
    match source {
        ChatSourceId::ForegroundTurn { turn_id } => turn_id,
        ChatSourceId::Input { input_id } => input_id,
        ChatSourceId::InboxMessage {
            source_id,
            message_id,
        } => {
            if source_id.is_empty() {
                ""
            } else {
                message_id
            }
        }
        ChatSourceId::BackgroundResult { message_id } => message_id,
        ChatSourceId::Operation { operation_id } => operation_id,
        ChatSourceId::Receipt { receipt_id } => receipt_id,
    }
}

struct ReplyMetadata {
    id: String,
    source: ChatSourceId,
    turn_id: Option<String>,
    kind: ChatAtomKind,
    tool: Option<pl_protocol::ChatToolIdentity>,
    text_channel: Option<ThreadTextChannel>,
    contents: Vec<pl_protocol::ChatAtomContent>,
}

async fn decode_envelope(
    reader: &ConversationReader,
    atom: &ReplyMetadata,
    id: &str,
    bytes: &[u8],
    target: &str,
) -> Result<Option<ReplyItem>, FinalError> {
    let envelope: Envelope = serde_json::from_slice(bytes)
        .map_err(|error| gap(&format!("malformed reply envelope: {error}")))?;
    if envelope.contract != "anywork.chat/1" {
        return Err(gap("unsupported reply envelope contract"));
    }
    if envelope.turn_id != atom.turn_id {
        return Err(gap("reply metadata and frozen payload Turn conflict"));
    }
    let expected = match atom.kind {
        ChatAtomKind::Text => Some("text"),
        ChatAtomKind::Interaction => Some("tool"),
        ChatAtomKind::ToolCall => Some("tool"),
        ChatAtomKind::Plan => Some("plan"),
        ChatAtomKind::TurnReceipt => Some("turn"),
        ChatAtomKind::Unknown => None,
        _ => unreachable!("unrelated domain payloads are not decoded"),
    };
    if expected.is_some_and(|kind| kind != envelope.kind) {
        return Err(gap("reply metadata and frozen payload domain conflict"));
    }
    if atom.kind == ChatAtomKind::Unknown
        && !matches!(envelope.kind.as_str(), "text" | "turn" | "tool" | "plan")
    {
        return Err(gap(
            "unknown reply domain cannot prove an unrelated payload",
        ));
    }
    if let Some(tool) = &atom.tool
        && (envelope.data["invocation"]["toolCallId"].as_str() != Some(tool.call_id.as_str())
            || envelope.data["invocation"]["name"].as_str() != Some(tool.name.as_str()))
    {
        return Err(gap(
            "reply metadata and frozen payload tool identity conflict",
        ));
    }
    if envelope.turn_id.as_deref() != Some(target) {
        return Ok(None);
    }
    let kind = match envelope.kind.as_str() {
        "text" => {
            let channel: ThreadTextChannel = serde_json::from_value(
                envelope
                    .data
                    .get("channel")
                    .cloned()
                    .ok_or_else(|| gap("reply text lacks channel"))?,
            )
            .map_err(|error| gap(&format!("invalid reply text channel: {error}")))?;
            if atom.text_channel != Some(channel) {
                return Err(gap("reply metadata and frozen payload channel conflict"));
            }
            if channel != ThreadTextChannel::Final {
                return Ok(None);
            }
            let mut bodies = envelope
                .bodies
                .into_iter()
                .filter(|body| body.key == "body");
            let body = bodies
                .next()
                .ok_or_else(|| gap("canonical Final lacks explicit body manifest"))?;
            if bodies.next().is_some() {
                return Err(gap("canonical Final has duplicate body manifests"));
            }
            body.validate(id)?;
            for content in &atom.contents {
                if content.role == ChatContentRole::Body
                    && (content.reference.database_id.is_empty()
                        || !matches!(&content.reference.target,
                            ContentTarget::Body { owner: ContentOwner::Item { item_id }, key }
                                if item_id == id && key == &body.key)
                        || body
                            .reference
                            .as_ref()
                            .is_some_and(|reference| reference != &content.reference))
                {
                    return Err(gap("reply metadata and frozen body ownership conflict"));
                }
            }
            let preview = body.read(reader, false).await?;
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
                    "completed reply message contains nonterminal TurnState",
                ));
            }
            ReplyItemKind::Terminal(state)
        }
        "tool" => {
            if atom.kind == ChatAtomKind::ToolCall
                && atom
                    .tool
                    .as_ref()
                    .is_some_and(|tool| tool.name == pl_tool::file_display::TOOL_SHOW_FILES)
                && envelope.data["invocation"]["presentationContract"].as_str()
                    == Some(pl_tool::file_display::FILE_DISPLAY_PRESENTATION)
                && envelope.data["state"]["kind"].as_str() == Some("succeeded")
                && matches!(&atom.source, ChatSourceId::ForegroundTurn { turn_id } if turn_id == target)
            {
                let call_id = envelope.data["invocation"]["toolCallId"]
                    .as_str()
                    .filter(|id| !id.is_empty())
                    .ok_or_else(|| gap("file display lacks frozen tool call identity"))?;
                let mut artifacts = envelope
                    .bodies
                    .iter()
                    .filter(|body| body.key == "tool.output-artifacts");
                let body = artifacts
                    .next()
                    .ok_or_else(|| gap("file display lacks reliable output artifacts"))?;
                if artifacts.next().is_some() {
                    return Err(gap("file display has duplicate artifact bodies"));
                }
                body.validate(id)?;
                let bytes = body.read(reader, true).await?;
                let artifacts: Vec<serde_json::Value> = serde_json::from_str(&bytes)
                    .map_err(|error| gap(&format!("malformed display artifacts: {error}")))?;
                let mut receipt = None;
                for artifact in artifacts {
                    // The producer adds this explicit ContextContent wrapper only after
                    // decoding the actual output payload. Bare resources and opaque model
                    // context are not display authorization.
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
                    member_id: atom.id.clone(),
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
                if atom.kind == ChatAtomKind::Interaction {
                    return Err(gap("reply Interaction metadata lacks frozen user input"));
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
        member_id: atom.id.clone(),
        id: id.into(),
        kind,
    }))
}

impl Body {
    fn validate(&self, item: &str) -> Result<(), FinalError> {
        check_length(self.byte_length)?;
        match (&self.inline, &self.reference) {
            (Some(bytes), None) if bytes.len() as u64 == self.byte_length => Ok(()),
            (None, Some(reference))
                if matches!(&reference.target,
                ContentTarget::Body { owner: ContentOwner::Item { item_id }, key } if item_id == item && key == &self.key) =>
            {
                Ok(())
            }
            _ => Err(gap(
                "canonical Final body manifest identity or length conflict",
            )),
        }
    }

    async fn read(
        &self,
        reader: &ConversationReader,
        complete: bool,
    ) -> Result<String, FinalError> {
        let bytes = match (&self.inline, &self.reference) {
            (Some(bytes), None) => bytes.clone(),
            (None, Some(reference)) => {
                read_bytes(reader, reference, self.byte_length, complete).await?
            }
            _ => return Err(gap("canonical Final body manifest has no unique source")),
        };
        match String::from_utf8(bytes) {
            Ok(text) => Ok(text),
            Err(error)
                if !complete
                    && self.reference.is_some()
                    && error.utf8_error().error_len().is_none() =>
            {
                // A byte window may end inside a scalar. Only this incomplete
                // boundary is omitted from the preview; malformed bytes still fail.
                let through = error.utf8_error().valid_up_to();
                String::from_utf8(error.into_bytes()[..through].to_vec())
                    .map_err(|_| gap("invalid canonical Final UTF-8 prefix"))
            }
            Err(error) => Err(gap(&format!("canonical Final body is not UTF-8: {error}"))),
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

/// Bounded ranges are issued before allocating the object. In particular a Deferred
/// ItemPayload exceeding the bot budget is rejected before any full-object read.
async fn read_bytes(
    reader: &ConversationReader,
    reference: &ContentRef,
    length: u64,
    complete: bool,
) -> Result<Vec<u8>, FinalError> {
    check_length(length)?;
    let mut bytes = Vec::new();
    let mut generation = None;
    loop {
        let offset = bytes.len() as u64;
        let max_bytes = WINDOW_BYTES.min((length - offset).max(1) as u32);
        let window = reader
            .read_content(reference, ContentRange { offset, max_bytes })
            .await
            .map_err(|error| read_failure("canonical reply content range failed", error))?;
        if window.offset != offset
            || window.available_through != length
            || !window.sealed
            || window.generation.is_empty()
            || generation
                .as_ref()
                .is_some_and(|old| old != &window.generation)
            || window.bytes.len() > max_bytes as usize
            || offset + window.bytes.len() as u64 > length
            || window.bytes.is_empty() && offset < length
        {
            return Err(gap(
                "canonical reply content range identity, generation or coverage conflict",
            ));
        }
        generation = Some(window.generation);
        bytes.extend(window.bytes);
        if bytes.len() as u64 == length || !complete {
            return Ok(bytes);
        }
    }
}

/// Only completed messages already accepted by this feed are used. Its original
/// page ceiling is not reopened with a cursor from another lease. Append ordering
/// plus recovered prefix covers the exact target; the barrier establishes durable
/// save coverage before any terminal platform action (including failure/cancel).
pub(super) async fn collect_complete_turn_text(
    runtime: &StudioRuntime,
    reader: &ConversationReader,
    projection: &ReplyProjection,
) -> Result<FinalText, FinalError> {
    let items = projection.completed()?;
    runtime
        .synchronize_thread_observation(reader.thread_id())
        .await
        .map_err(|error| read_failure("thread observation barrier failed", error))?;
    // Even all-inline/empty replies must recheck the original read qualification
    // after the barrier; closing/replacing a lease must not authorize a final send.
    reader
        .ensure()
        .map_err(|error| read_failure("canonical terminal read qualification failed", error))?;
    let mut text = String::new();
    for item in items {
        if let ReplyItemKind::Final { body, preview } = &item.kind {
            let value = body.read(reader, true).await?;
            if !value.starts_with(preview) {
                return Err(gap("canonical Final does not cover accepted preview"));
            }
            if text.len().saturating_add(value.len()) > MAX_TURN_BODY_BYTES {
                check_length(MAX_TURN_BODY_BYTES as u64 + 1)?;
            }
            text.push_str(&value);
        }
    }
    if text.trim().is_empty() {
        Ok(FinalText::CompleteNoText)
    } else {
        Ok(FinalText::CompleteText(text))
    }
}

/// Continuations are opaque and local to the original lease. Bound both scanned
/// items and requests, so even advancing empty pages cannot cause an unbounded walk.
#[derive(Default)]
pub(super) struct Coverage {
    inspected: usize,
    pages: usize,
    cursors: BTreeSet<String>,
}
impl Coverage {
    pub(super) fn page(&mut self, entries: &[CompletedEntry]) -> Result<(), FinalError> {
        self.pages = self.pages.saturating_add(1);
        self.admit(entries)
    }
    pub(super) fn admit(&mut self, entries: &[CompletedEntry]) -> Result<(), FinalError> {
        self.inspected = self.inspected.saturating_add(entries.len());
        if self.inspected > MAX_TURN_CONTENT_ITEMS || self.pages > MAX_TURN_CONTENT_ITEMS {
            return Err(FinalError::Attention(
                "canonical turn coverage exceeded 16384 completion records or pages".into(),
            ));
        }
        Ok(())
    }
    pub(super) fn cursor(&mut self, token: &str) -> Result<(), FinalError> {
        if token.is_empty() || !self.cursors.insert(token.to_owned()) {
            return Err(gap("canonical reply cursor did not advance"));
        }
        Ok(())
    }
}

pub(super) fn read_failure(context: &str, error: anyhow::Error) -> FinalError {
    let error = crate::studio_error_from_anyhow(error);
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
