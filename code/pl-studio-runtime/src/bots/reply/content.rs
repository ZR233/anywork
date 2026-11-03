//! Explicit bounded completion coverage and reliable final verification on the original read lease.

use super::projection::{ReplyProjection, gap};
use crate::studio::{ConversationReader, StudioRuntime};
use pl_protocol::{
    ChatAtomKind, ChatAtomLifecycle, ChatContentRole, ChatEntry, ChatSourceId, ContentOwner,
    ContentRange, ContentRef, ContentTarget, PayloadData, ReadDemand, ThreadTextChannel, TurnState,
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
    Final { body: Body, preview: String },
    Terminal(TurnState),
    Interaction(String),
}

impl ReplyItem {
    pub(super) fn preview_bytes(&self) -> usize {
        match &self.kind {
            ReplyItemKind::Final { body, .. } => body.byte_length as usize,
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
    entry: &ChatEntry,
    turn_id: &str,
) -> Result<Option<ReplyItem>, FinalError> {
    let (atom, id, payload) = match entry {
        ChatEntry::Item(item) => {
            if item.is_work_group() {
                return Ok(None);
            }
            if item.position.is_none() {
                return Ok(None);
            }
            let kind = item
                .atom_kind
                .ok_or_else(|| gap("reply item has no domain kind"))?;
            let id = item
                .content_item_id
                .as_deref()
                .filter(|id| !id.is_empty())
                .ok_or_else(|| gap("reply item has no frozen content owner"))?;
            let payload = item
                .payload
                .as_ref()
                .ok_or_else(|| gap("reply item has no payload"))?;
            // Display identity is not the original text/content identity. Final
            // preview retirement follows the frozen text owner, never an ID prefix.
            (
                ReplyMetadata {
                    id: id.to_owned(),
                    source: item.source.clone(),
                    turn_id: item.turn_id.clone(),
                    kind,
                    tool: None,
                    text_channel: item.text_channel,
                    contents: item.contents.clone(),
                },
                id,
                payload,
            )
        }
        ChatEntry::Atom(atom) => {
            if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
                return Ok(None);
            }
            let id = atom
                .completion_item_id
                .as_deref()
                .filter(|id| !id.is_empty())
                .ok_or_else(|| gap("terminal reply atom has no frozen completion identity"))?;
            if atom.completion_seq.is_none_or(|seq| seq == 0) {
                return Err(gap(
                    "terminal reply atom has no completion publication position",
                ));
            }
            let payload = atom
                .payload
                .as_ref()
                .ok_or_else(|| gap("terminal reply atom has no frozen payload"))?;
            (
                ReplyMetadata {
                    id: atom.id.clone(),
                    source: atom.source.clone(),
                    turn_id: atom.turn_id.clone(),
                    kind: atom.kind,
                    tool: atom.tool.clone(),
                    text_channel: atom.text_channel,
                    contents: atom.contents.clone(),
                },
                id,
                payload,
            )
        }
        ChatEntry::Source(source) => {
            if source_identity(&source.source).is_empty() {
                return Err(gap("reply source fact has no identity"));
            }
            return Ok(None);
        }
    };
    if atom.id.is_empty() || source_identity(&atom.source).is_empty() {
        return Err(gap("reply item has no identity"));
    }
    if let ChatSourceId::ForegroundTurn { turn_id } = &atom.source
        && atom.turn_id.as_deref() != Some(turn_id)
    {
        return Err(gap("reply source and Turn identity conflict"));
    }
    if let PayloadData::Deferred { reference, .. } = payload
        && (reference.database_id.is_empty()
            || !matches!(&reference.target, ContentTarget::ItemPayload { item_id } if item_id == id))
    {
        return Err(gap("deferred reply payload identity conflict"));
    }
    // Main also includes work now. Its known domain is sufficient to skip
    // unrelated payloads; Unknown never grants permission to omit a possible Final.
    if !matches!(
        atom.kind,
        ChatAtomKind::Text
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

fn source_identity(source: &ChatSourceId) -> &str {
    match source {
        ChatSourceId::ForegroundTurn { turn_id } => turn_id,
        ChatSourceId::Input { input_id } => input_id,
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
    atoms: usize,
    pages: usize,
    cursors: BTreeSet<String>,
}
impl Coverage {
    pub(super) fn page(&mut self, entries: &[ChatEntry]) -> Result<(), FinalError> {
        self.pages = self.pages.saturating_add(1);
        self.admit(entries)
    }
    pub(super) fn admit(&mut self, entries: &[ChatEntry]) -> Result<(), FinalError> {
        self.inspected = self.inspected.saturating_add(entries.len());
        self.atoms = self.atoms.saturating_add(
            entries
                .iter()
                .filter(|entry| matches!(entry, ChatEntry::Item(_)))
                .count(),
        );
        if self.inspected > MAX_TURN_CONTENT_ITEMS
            || self.atoms > MAX_TURN_CONTENT_ITEMS
            || self.pages > MAX_TURN_CONTENT_ITEMS
        {
            return Err(FinalError::Attention(
                "canonical turn coverage exceeded 16384 facts, atoms or pages".into(),
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
