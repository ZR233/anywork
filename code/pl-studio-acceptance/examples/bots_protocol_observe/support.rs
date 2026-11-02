//! Shared bounded Chat observation and terminal-atom validation.
use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatBatch, ChatSourceId, ContentRange, ContentRef,
    ContentTarget, PayloadData, ReadDemand, TurnState,
};
use std::time::Instant;

pub(crate) const CHAT_DEMAND: ReadDemand = ReadDemand {
    max_items: 100,
    max_bytes: 256 * 1024,
};
pub(crate) const CHAT_OBSERVATION_BYTES: usize = 4 * 1024 * 1024;

/// Canonical Core `ChatKey::new("turn", id)` encoding for the Children query field.
pub(crate) fn turn_parent_key(turn_id: &str) -> Result<String> {
    ensure!(
        !turn_id.is_empty(),
        "cannot scope Children to an empty Turn identity"
    );
    Ok(format!("{}:turn{turn_id}", "turn".len()))
}

pub(crate) fn charge_chat_batch(batch: &ChatBatch, remaining: &mut usize) -> Result<()> {
    ensure!(
        batch.entries.len() <= CHAT_DEMAND.max_items as usize,
        "Chat exceeded entry demand"
    );
    let bytes = batch.encoded_len()?;
    ensure!(
        bytes <= CHAT_DEMAND.max_bytes as usize,
        "Chat exceeded byte demand"
    );
    charge_chat_bytes(bytes, remaining)
}

pub(crate) fn charge_chat_bytes(bytes: usize, remaining: &mut usize) -> Result<()> {
    *remaining = remaining
        .checked_sub(bytes)
        .context("Chat observation exceeded its cumulative 4MiB budget")?;
    Ok(())
}

pub(crate) async fn payload_bytes(
    read: &crate::http::ChatRead,
    payload: &PayloadData,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<u8>> {
    match payload {
        PayloadData::Inline { bytes } => Ok(bytes.clone()),
        PayloadData::Deferred {
            reference,
            byte_length,
        } => content_bytes(read, reference, *byte_length, remaining, deadline).await,
    }
}

pub(crate) async fn content_bytes(
    read: &crate::http::ChatRead,
    reference: &ContentRef,
    length: u64,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<u8>> {
    ensure!(
        length <= *remaining as u64,
        "Deferred content exceeds remaining observation budget"
    );
    let mut bytes = Vec::new();
    let mut generation = None;
    while (bytes.len() as u64) < length {
        let offset = bytes.len() as u64;
        let max_bytes = (length - offset).min(64 * 1024) as u32;
        let window = tokio::time::timeout_at(
            tokio::time::Instant::from_std(deadline),
            read.read_content(reference, ContentRange { offset, max_bytes }),
        )
        .await
        .context("Chat content read exceeded observation deadline")??;
        ensure!(
            window.offset == offset
                && !window.bytes.is_empty()
                && window.bytes.len() <= max_bytes as usize
                && window.available_through == length,
            "Chat content range did not advance within its declared length"
        );
        charge_chat_bytes(serde_json::to_vec(&window)?.len(), remaining)?;
        if let Some(expected) = &generation {
            ensure!(
                &window.generation == expected,
                "Chat content generation changed mid-read"
            );
        } else {
            generation = Some(window.generation);
        }
        bytes.extend(window.bytes);
    }
    ensure!(
        bytes.len() as u64 == length,
        "Deferred payload length mismatch"
    );
    Ok(bytes)
}

pub(crate) async fn chat_payload(
    read: &crate::http::ChatRead,
    payload: &PayloadData,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<serde_json::Value> {
    let bytes = payload_bytes(read, payload, remaining, deadline).await?;
    let value: serde_json::Value =
        serde_json::from_slice(&bytes).context("invalid Chat payload JSON")?;
    ensure!(
        value["contract"] == "anywork.chat/1"
            && matches!(
                value["type"].as_str(),
                Some(
                    "text"
                        | "thinking"
                        | "tool"
                        | "raw"
                        | "agent"
                        | "turn"
                        | "inference"
                        | "skill"
                        | "file"
                        | "contextCompaction"
                        | "plan"
                )
            )
            && value["data"].is_object()
            && value["bodies"].is_array(),
        "Chat payload omitted its current contract, type, metadata or bodies"
    );
    if value["type"] == "turn" {
        ensure!(
            value["turnId"].as_str().is_some_and(|id| !id.is_empty()),
            "terminal Chat Turn omitted its identity"
        );
        let input = value["data"]
            .get("inputId")
            .context("Chat Turn omitted inputId")?;
        ensure!(
            input.is_null() || input.is_string(),
            "Chat Turn has invalid inputId"
        );
        let state: TurnState = serde_json::from_value(
            value["data"]
                .get("outcome")
                .context("Chat Turn omitted outcome")?
                .clone(),
        )?;
        ensure!(
            matches!(
                state,
                TurnState::Completed(_)
                    | TurnState::Failed(_)
                    | TurnState::Cancelled(_)
                    | TurnState::BudgetLimited(_)
            ),
            "completed Chat contains a nonterminal Turn"
        );
    }
    Ok(value)
}

/// Decode only actual terminal atoms; Source and Active are facts, never results.
pub(crate) async fn completed_atom_payload(
    read: &crate::http::ChatRead,
    atom: &ChatAtom,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Option<serde_json::Value>> {
    match &atom.lifecycle {
        ChatAtomLifecycle::Active { .. } => {
            ensure!(
                atom.payload.is_none()
                    && atom.completion_item_id.is_none()
                    && atom.completion_seq.is_none(),
                "active atom carried terminal payload or completion identity"
            );
            Ok(None)
        }
        ChatAtomLifecycle::Terminal { .. } => {
            let item_id = atom
                .completion_item_id
                .as_deref()
                .filter(|id| !id.is_empty())
                .context("terminal atom omitted completion_item_id")?;
            ensure!(
                atom.completion_seq.is_some(),
                "terminal atom omitted completion_seq"
            );
            let payload_data = atom
                .payload
                .as_ref()
                .context("terminal atom omitted its frozen payload")?;
            if let PayloadData::Deferred { reference, .. } = payload_data {
                ensure!(
                    matches!(
                        &reference.target,
                        ContentTarget::ItemPayload { item_id: payload_id }
                            if payload_id.as_str() == item_id
                    ),
                    "Deferred payload identity did not match completion_item_id"
                );
            }
            let payload = chat_payload(read, payload_data, remaining, deadline).await?;
            if let Some(turn_id) = atom.turn_id.as_deref() {
                ensure!(
                    payload["turnId"].as_str() == Some(turn_id),
                    "terminal atom metadata and payload Turn conflict"
                );
            }
            if let ChatSourceId::ForegroundTurn { turn_id } = &atom.source
                && let Some(atom_turn_id) = atom.turn_id.as_deref()
            {
                ensure!(
                    atom_turn_id == turn_id.as_str(),
                    "atom source and Turn identity conflict"
                );
            }
            let payload_kind = payload["type"].as_str();
            let kind_matches = match atom.kind {
                ChatAtomKind::Input | ChatAtomKind::Text => payload_kind == Some("text"),
                ChatAtomKind::Reasoning => matches!(payload_kind, Some("thinking" | "inference")),
                ChatAtomKind::ToolCall => payload_kind == Some("tool"),
                ChatAtomKind::FileChange => payload_kind == Some("file"),
                ChatAtomKind::Skill => payload_kind == Some("skill"),
                ChatAtomKind::Interaction => {
                    payload_kind == Some("tool")
                        && payload["data"]
                            .get("userInput")
                            .is_some_and(|input| !input.is_null())
                }
                ChatAtomKind::Plan => payload_kind == Some("plan"),
                ChatAtomKind::Compaction => payload_kind == Some("contextCompaction"),
                ChatAtomKind::TurnReceipt => payload_kind == Some("turn"),
                ChatAtomKind::Receipt | ChatAtomKind::Unknown => true,
            };
            ensure!(
                kind_matches,
                "atom kind {:?} conflicts with payload type {payload_kind:?}",
                atom.kind
            );
            if let Some(tool) = &atom.tool {
                ensure!(
                    payload_kind == Some("tool")
                        && payload["data"]["invocation"]["toolCallId"].as_str()
                            == Some(tool.call_id.as_str())
                        && payload["data"]["invocation"]["name"].as_str()
                            == Some(tool.name.as_str()),
                    "atom tool metadata conflicts with frozen payload identity"
                );
            }
            Ok(Some(payload))
        }
    }
}
