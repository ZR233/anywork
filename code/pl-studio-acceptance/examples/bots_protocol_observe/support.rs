//! Shared bounded Chat observation and terminal-atom validation.
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::{
    ChatAtomKind, ChatAtomLifecycle, ChatBatch, ChatScope, ChatSourceId, ContentRange, ContentRef,
    ContentTarget, PayloadData, ReadDemand, TurnState,
};
use std::time::Instant;

pub(crate) const CHAT_DEMAND: ReadDemand = ReadDemand {
    max_items: 100,
    max_bytes: 256 * 1024,
};
pub(crate) const CHAT_OBSERVATION_BYTES: usize = 4 * 1024 * 1024;

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

/// Read an immutable completion's original payload after validating its
/// completion identity. Main work representatives may be Deferred; callers
/// must open their referenced Run to inspect all members.
pub(crate) async fn completed_entry_payload(
    read: &crate::http::ChatRead,
    entry: &pl_protocol::CompletedEntry,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Option<serde_json::Value>> {
    ensure!(
        !entry.record_id.is_empty()
            && entry
                .atom
                .completion_item_id
                .as_ref()
                .is_none_or(|id| id == &entry.record_id)
            && entry
                .atom
                .completion_seq
                .is_none_or(|seq| seq == entry.completion_seq),
        "completed entry identity disagrees with its original atom"
    );
    ensure!(
        matches!(entry.atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
        "completed entry contains a nonterminal atom"
    );
    let payload_data = entry
        .atom
        .payload
        .as_ref()
        .context("completed entry omitted its frozen payload")?;
    if let PayloadData::Deferred { reference, .. } = payload_data {
        ensure!(
            matches!(
                &reference.target,
                ContentTarget::ItemPayload { item_id } if !item_id.is_empty()
            ),
            "Deferred completion payload reference had an invalid item identity"
        );
    }
    let payload = chat_payload(read, payload_data, remaining, deadline).await?;
    if let Some(turn_id) = entry.atom.turn_id.as_deref() {
        ensure!(
            payload["turnId"].as_str() == Some(turn_id),
            "completed atom metadata and original payload Turn conflict"
        );
    }
    if let ChatSourceId::ForegroundTurn { turn_id } = &entry.atom.source {
        ensure!(
            entry.atom.turn_id.as_deref() == Some(turn_id),
            "completed atom source and Turn identity conflict"
        );
    }
    if let ChatSourceId::InboxMessage {
        source_id,
        message_id,
    } = &entry.atom.source
    {
        ensure!(
            !source_id.is_empty() && !message_id.is_empty(),
            "inbox completion omitted its stable source/message identity"
        );
    }
    let payload_kind = payload["type"].as_str();
    let kind_matches = match entry.atom.kind {
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
        ChatAtomKind::Raw => payload_kind == Some("raw"),
        ChatAtomKind::Agent => payload_kind == Some("agent"),
        ChatAtomKind::Inference => payload_kind == Some("inference"),
        ChatAtomKind::Receipt | ChatAtomKind::Unknown => true,
    };
    ensure!(
        kind_matches,
        "atom kind {:?} conflicts with payload type {payload_kind:?}",
        entry.atom.kind
    );
    if let Some(tool) = &entry.atom.tool {
        ensure!(
            payload_kind == Some("tool")
                && payload["data"]["invocation"]["toolCallId"].as_str()
                    == Some(tool.call_id.as_str())
                && payload["data"]["invocation"]["name"].as_str() == Some(tool.name.as_str()),
            "atom tool metadata conflicts with frozen payload identity"
        );
    }
    if let Some(channel) = &entry.atom.text_channel {
        ensure!(
            payload["type"] == "text"
                && payload["data"]["channel"] == serde_json::to_value(channel)?,
            "completed atom channel and original text payload disagree"
        );
    }
    Ok(Some(payload))
}

/// Build a Run reference only from a validated representative's run position
/// and its Deferred completion reference; never infer a run from atom fields.
pub(crate) fn completion_run_ref(
    entry: &pl_protocol::CompletedEntry,
) -> Result<pl_protocol::CompletionRunRef> {
    use pl_protocol::{COMPLETED_READ_INDEX_VERSION, MainPresentation};
    ensure!(
        matches!(
            entry.main_presentation,
            MainPresentation::ForegroundWork | MainPresentation::BackgroundResults
        ),
        "only a Main work representative can identify a completion Run"
    );
    let run = entry
        .run
        .context("Main work representative omitted run position")?;
    ensure!(
        run.start_seq > 0 && run.start_seq <= entry.completion_seq && run.ordinal > 0,
        "Main work representative has an invalid run position"
    );
    let Some(PayloadData::Deferred { reference, .. }) = entry.atom.payload.as_ref() else {
        anyhow::bail!("Main work representative did not carry a Deferred payload reference");
    };
    ensure!(
        !reference.database_id.is_empty()
            && matches!(
                &reference.target,
                ContentTarget::ItemPayload { item_id } if !item_id.is_empty()
            ),
        "Main work representative has an invalid Deferred completion reference"
    );
    Ok(pl_protocol::CompletionRunRef {
        database_id: reference.database_id.clone(),
        index_version: COMPLETED_READ_INDEX_VERSION,
        start_seq: run.start_seq,
    })
}

/// Page every immutable member of one actual Run, preserving bounded demand,
/// deadline, continuation progress, and the caller's cumulative byte budget.
pub(crate) async fn completion_run_entries(
    read: &crate::http::ChatRead,
    representative: &pl_protocol::CompletedEntry,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<(crate::http::ChatRead, Vec<pl_protocol::CompletedEntry>)> {
    let reference = completion_run_ref(representative)?;
    let scope = ChatScope::Run {
        reference: reference.clone(),
    };
    let (run_read, mut page) = tokio::time::timeout_at(
        tokio::time::Instant::from_std(deadline),
        read.open_run(&reference, CHAT_DEMAND),
    )
    .await
    .context("opening completion Run exceeded observation deadline")??;
    let mut entries = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for page_index in 0..256 {
        let has_more = tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
            charge_chat_batch(&page, remaining)?;
            page.validate_for(&scope)?;
            entries.extend(page.entries.iter().cloned());
            if let Some(before) = page.before.take() {
                ensure!(
                    page_index + 1 < 256,
                    "completion Run exceeded bounded page budget"
                );
                ensure!(
                    seen.insert(before.clone()),
                    "completion Run continuation did not advance"
                );
                page = run_read.load_older(&before, CHAT_DEMAND).await?;
            } else {
                return Ok::<bool, anyhow::Error>(false);
            }
            Ok(true)
        })
        .await
        .context("completion Run read exceeded observation deadline")??;
        if !has_more {
            break;
        }
    }
    ensure!(
        page.before.is_none(),
        "completion Run exceeded bounded page budget"
    );
    Ok((run_read, entries))
}

/// Successful Turn receipts are Hidden from Main; inspect the original typed
/// Turn parent scope and require its one real successful completion record.
pub(crate) async fn completed_turn_from_children(
    read: &crate::http::ChatRead,
    turn_id: &str,
    expected_input_id: Option<&str>,
    require_success: bool,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<()> {
    let parent_id = format!("{}:{turn_id}", turn_id.len());
    let scope = ChatScope::conversation(Some(parent_id.clone()));
    let (children_read, mut page) = tokio::time::timeout_at(
        tokio::time::Instant::from_std(deadline),
        read.open_children(&parent_id, CHAT_DEMAND),
    )
    .await
    .context("opening Turn Children exceeded observation deadline")??;
    let mut seen = std::collections::HashSet::new();
    let mut matched = 0usize;
    for page_index in 0..256 {
        charge_chat_batch(&page, remaining)?;
        page.validate_for(&scope)?;
        for entry in &page.entries {
            if entry.atom.kind != ChatAtomKind::TurnReceipt {
                continue;
            }
            let payload = completed_entry_payload(&children_read, entry, remaining, deadline)
                .await?
                .context("Turn Children returned a nonterminal TurnReceipt")?;
            ensure!(
                payload["type"] == "turn" && payload["turnId"].as_str() == Some(turn_id),
                "TurnReceipt atom and original payload identity disagree"
            );
            ensure!(
                matches!(
                    &entry.atom.source,
                    ChatSourceId::ForegroundTurn { turn_id: source_turn }
                        if source_turn == turn_id
                ),
                "TurnReceipt source does not match its typed Children parent"
            );
            let input_id = payload["data"]
                .get("inputId")
                .and_then(serde_json::Value::as_str);
            if let Some(expected) = expected_input_id {
                ensure!(
                    input_id == Some(expected),
                    "TurnReceipt input identity did not match the expected input"
                );
            }
            let state: TurnState = serde_json::from_value(
                payload["data"]
                    .get("outcome")
                    .context("Turn payload omitted outcome")?
                    .clone(),
            )?;
            if require_success {
                ensure!(
                    matches!(state, TurnState::Completed(_)),
                    "Turn {turn_id} did not complete successfully: {state:?}"
                );
            }
            matched += 1;
        }
        let Some(before) = page.before.take() else {
            ensure!(
                matched == 1,
                "Turn {turn_id} Children had {matched} terminal receipts"
            );
            return Ok(());
        };
        ensure!(
            page_index + 1 < 256 && seen.insert(before.clone()),
            "Turn Children exceeded its bounded page budget or repeated a continuation"
        );
        page = children_read.load_older(&before, CHAT_DEMAND).await?;
    }
    bail!("Turn Children exceeded its bounded page budget")
}
