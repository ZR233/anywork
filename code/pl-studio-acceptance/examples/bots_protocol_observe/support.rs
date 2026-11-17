//! Bounded typed History/Current observation shared by the bots acceptance cases.
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::{
    ContentRange, CurrentPayloadData, ReadDemand, ThreadTextChannel, Turn, TurnState,
};
use pl_studio_runtime::history::{
    HEAD_MAX_BYTES, HistoryBodyEntry, HistoryBodyPage, HistoryBodyRole, HistoryCut, HistoryDemand,
    HistoryEntityHead, HistoryEntityState, HistoryEventBodyRef, HistoryEventDetail,
    HistoryEventHeader, HistoryEventsPage, HistoryEventsQuery, HistoryGroupPage, HistoryRowHead,
    HistoryTimelinePage, HistoryTurnHead, HistoryTurnState,
};
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeSet, HashSet};
use std::time::Instant;

pub(crate) const HISTORY_DEMAND: HistoryDemand = HistoryDemand {
    max_rows: 100,
    max_bytes: 256 * 1024,
};
pub(crate) const HISTORY_OBSERVATION_BYTES: usize = 4 * 1024 * 1024;
const CURRENT_DEMAND: ReadDemand = ReadDemand {
    max_items: 100,
    max_bytes: 256 * 1024,
};
const CURSOR_PAGE_LIMIT: usize = 256;
const BODY_CHUNK_BYTES: u32 = 64 * 1024;

#[derive(Debug, Clone, Serialize)]
pub(crate) struct HistoryOriginal {
    pub event_id: String,
    pub event: HistoryEventHeader,
    pub head: HistoryEntityHead,
    pub payload: Value,
    pub bodies: Vec<HistoryBodyEntry>,
}

impl HistoryOriginal {
    pub(crate) fn text_body(&self) -> Result<Option<&HistoryBodyEntry>> {
        ensure!(
            self.head.kind == pl_protocol::ChatAtomKind::Text,
            "History entity {} is not typed text",
            self.head.entity_id
        );
        unique_body(&self.bodies, |body| {
            body.role == HistoryBodyRole::Body && is_text_body_key(&body.body_key)
        })
        .with_context(|| format!("History text {}", self.head.entity_id))
    }

    pub(crate) fn tool_output_body(&self) -> Result<Option<&HistoryBodyEntry>> {
        ensure!(
            self.head.kind == pl_protocol::ChatAtomKind::ToolCall,
            "History entity {} is not a tool",
            self.head.entity_id
        );
        unique_body(&self.bodies, is_tool_output_body)
            .with_context(|| format!("History tool output {}", self.head.entity_id))
    }

    pub(crate) fn tool_arguments_body(&self) -> Result<Option<&HistoryBodyEntry>> {
        ensure!(
            self.head.kind == pl_protocol::ChatAtomKind::ToolCall,
            "History entity {} is not a tool",
            self.head.entity_id
        );
        unique_body(&self.bodies, is_tool_arguments_body)
            .with_context(|| format!("History tool arguments {}", self.head.entity_id))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct HistoryMainScan {
    /// Product Main rows are exactly visible top-level Work + Single rows.
    pub rows: usize,
    /// Every visible entity head, including Work members, for independent inventory assertions.
    pub entities: Vec<HistoryEntityHead>,
}

pub(crate) async fn charge_history_page<T: Serialize>(
    page: &T,
    demand: HistoryDemand,
    remaining: &mut usize,
) -> Result<()> {
    let bytes = serde_json::to_vec(page)?.len();
    let max_bytes = usize::try_from(demand.max_bytes).context("History byte demand overflow")?;
    ensure!(
        bytes <= max_bytes,
        "History response exceeded its byte demand"
    );
    charge_history_bytes(bytes, remaining)
}

pub(crate) fn charge_history_bytes(bytes: usize, remaining: &mut usize) -> Result<()> {
    *remaining = remaining
        .checked_sub(bytes)
        .context("History observation exceeded its cumulative 4MiB budget")?;
    Ok(())
}

/// Enumerates Main in product order. Work groups are expanded only to obtain their exact member
/// inventory; they still contribute one Main row each.
pub(crate) async fn scan_main(
    read: &crate::http::HistoryRead,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<HistoryMainScan> {
    tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
        let mut rows = 0usize;
        let mut entities = Vec::new();
        let mut entity_ids = BTreeSet::new();
        let mut cut: Option<HistoryCut> = None;
        let mut cursor = None;
        let mut seen = HashSet::new();
        for page_index in 0..CURSOR_PAGE_LIMIT {
            let page = read
                .timeline_page(cut.clone(), cursor.clone(), HISTORY_DEMAND)
                .await?;
            charge_history_page(&page, HISTORY_DEMAND, remaining)?;
            let HistoryTimelinePage {
                cut: page_cut,
                entries,
                next,
            } = page;
            for entry in entries {
                rows = rows.checked_add(1).context("Main row count overflow")?;
                match entry.head {
                    HistoryRowHead::Single(head) => {
                        if entity_ids.insert(head.entity_id.clone()) {
                            entities.push(head);
                        }
                    }
                    HistoryRowHead::Work(work) => {
                        let mut group_cut = Some(page_cut.clone());
                        let mut group_cursor = None;
                        let mut group_seen = HashSet::new();
                        for group_index in 0..CURSOR_PAGE_LIMIT {
                            let group = read
                                .group_page(
                                    work.group_id.clone(),
                                    group_cut.clone(),
                                    group_cursor.clone(),
                                    HISTORY_DEMAND,
                                )
                                .await?;
                            charge_history_page(&group, HISTORY_DEMAND, remaining)?;
                            let HistoryGroupPage {
                                cut: next_group_cut,
                                group_id,
                                members,
                                next,
                            } = group;
                            ensure!(
                                group_id == work.group_id,
                                "History group response belonged to another Work"
                            );
                            for member in members {
                                let HistoryRowHead::Member(head) = member.head else {
                                    bail!(
                                        "History group {} returned a non-member head",
                                        work.group_id
                                    );
                                };
                                if entity_ids.insert(head.entity_id.clone()) {
                                    entities.push(head);
                                }
                            }
                            let Some(next) = next else {
                                break;
                            };
                            ensure!(
                                group_index + 1 < CURSOR_PAGE_LIMIT
                                    && group_seen.insert(next.clone()),
                                "History group continuation repeated or exceeded its page budget"
                            );
                            group_cut = Some(next_group_cut);
                            group_cursor = Some(next);
                        }
                    }
                    _ => bail!("History Main returned a non-Work/Single head"),
                }
            }
            let Some(next) = next else {
                return Ok(HistoryMainScan { rows, entities });
            };
            ensure!(
                page_index + 1 < CURSOR_PAGE_LIMIT && seen.insert(next.clone()),
                "History Main continuation repeated or exceeded its page budget"
            );
            cut = Some(page_cut);
            cursor = Some(next);
        }
        bail!("History Main exceeded its bounded page budget")
    })
    .await
    .context("History Main observation exceeded its deadline")?
}

/// Reads one canonical original by its typed visible head.
pub(crate) async fn read_original(
    read: &crate::http::HistoryRead,
    head: &HistoryEntityHead,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<HistoryOriginal> {
    let event_id = head
        .detail_event_id
        .as_deref()
        .context("visible History entity omitted its original event")?;
    let detail = read
        .event(event_id, HISTORY_DEMAND)
        .await
        .with_context(|| format!("read History original {event_id}"))?;
    charge_history_page(&detail, HISTORY_DEMAND, remaining)?;
    original_from_event(read, detail, remaining, deadline).await
}

pub(crate) async fn originals_for_turn(
    read: &crate::http::HistoryRead,
    turn_id: &str,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<HistoryOriginal>> {
    tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
        let mut details = Vec::new();
        let mut cut: Option<HistoryCut> = None;
        let mut cursor = None;
        let mut seen = HashSet::new();
        for page_index in 0..CURSOR_PAGE_LIMIT {
            let page = read
                .events_page(
                    HistoryEventsQuery::Turn {
                        turn_id: turn_id.to_owned(),
                    },
                    cut.clone(),
                    cursor.clone(),
                    HISTORY_DEMAND,
                )
                .await?;
            charge_history_page(&page, HISTORY_DEMAND, remaining)?;
            let HistoryEventsPage {
                cut: page_cut,
                entries,
                next,
            } = page;
            details.extend(
                entries
                    .into_iter()
                    .filter(|entry| entry.header.original.is_some()),
            );
            let Some(next) = next else {
                details.sort_by_key(|detail| detail.header.seq);
                let mut originals = Vec::with_capacity(details.len());
                for detail in details {
                    originals.push(original_from_event(read, detail, remaining, deadline).await?);
                }
                return Ok(originals);
            };
            ensure!(
                page_index + 1 < CURSOR_PAGE_LIMIT && seen.insert(next.clone()),
                "Turn originals continuation repeated or exceeded its page budget"
            );
            cut = Some(page_cut);
            cursor = Some(next);
        }
        bail!("Turn originals exceeded the bounded page budget")
    })
    .await
    .context("Turn original observation exceeded its deadline")?
}

pub(crate) async fn originals_for_input(
    read: &crate::http::HistoryRead,
    input_id: &str,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<HistoryOriginal>> {
    originals_for_query(
        read,
        HistoryEventsQuery::Source {
            source: pl_protocol::ChatSourceId::Input {
                input_id: input_id.to_owned(),
            },
        },
        remaining,
        deadline,
    )
    .await
}

async fn originals_for_query(
    read: &crate::http::HistoryRead,
    query: HistoryEventsQuery,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<HistoryOriginal>> {
    tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
        let mut details = Vec::new();
        let mut cut: Option<HistoryCut> = None;
        let mut cursor = None;
        let mut seen = HashSet::new();
        for page_index in 0..CURSOR_PAGE_LIMIT {
            let page = read
                .events_page(query.clone(), cut.clone(), cursor.clone(), HISTORY_DEMAND)
                .await?;
            charge_history_page(&page, HISTORY_DEMAND, remaining)?;
            let HistoryEventsPage {
                cut: page_cut,
                entries,
                next,
            } = page;
            details.extend(
                entries
                    .into_iter()
                    .filter(|entry| entry.header.original.is_some()),
            );
            let Some(next) = next else {
                details.sort_by_key(|detail| detail.header.seq);
                let mut originals = Vec::with_capacity(details.len());
                for detail in details {
                    originals.push(original_from_event(read, detail, remaining, deadline).await?);
                }
                return Ok(originals);
            };
            ensure!(
                page_index + 1 < CURSOR_PAGE_LIMIT && seen.insert(next.clone()),
                "History query continuation repeated or exceeded its page budget"
            );
            cut = Some(page_cut);
            cursor = Some(next);
        }
        bail!("History query exceeded its bounded page budget")
    })
    .await
    .context("History query observation exceeded its deadline")?
}

async fn original_from_event(
    read: &crate::http::HistoryRead,
    detail: HistoryEventDetail,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<HistoryOriginal> {
    ensure!(
        detail.header.original.is_some(),
        "History event {} is not a canonical original",
        detail.header.event_id
    );
    let bodies = read_body_entries(read, &detail.header.event_id, remaining, deadline).await?;
    let metadata_head =
        canonical_head(read, &detail.header.event_id, &bodies, remaining, deadline).await?;
    let head = match detail.head {
        Some(HistoryRowHead::Single(head) | HistoryRowHead::Member(head)) => head,
        None => metadata_head.clone(),
        Some(_) => bail!("canonical original has a non-entity head"),
    };
    ensure!(
        head == metadata_head,
        "canonical metadata and indexed History head disagree"
    );
    let payload_ref = detail
        .payload_ref
        .context("canonical original omitted its opaque payload")?;
    let payload_bytes = read_body_bytes(read, &payload_ref, remaining, deadline).await?;
    let payload = serde_json::from_slice(&payload_bytes)
        .with_context(|| format!("canonical payload {} is not JSON", head.entity_id))?;
    ensure_history_payload_matches(&head, &payload)?;
    Ok(HistoryOriginal {
        event_id: detail.header.event_id.clone(),
        event: detail.header,
        head,
        payload,
        bodies,
    })
}

async fn canonical_head(
    read: &crate::http::HistoryRead,
    event_id: &str,
    bodies: &[HistoryBodyEntry],
    remaining: &mut usize,
    deadline: Instant,
) -> Result<HistoryEntityHead> {
    let entry = unique_body(bodies, |body| {
        body.role == HistoryBodyRole::CanonicalMetadata
    })?
    .with_context(|| format!("canonical original {event_id} omitted its typed head body"))?;
    ensure!(
        entry.reference.byte_length <= HEAD_MAX_BYTES as u64,
        "canonical History head exceeded {HEAD_MAX_BYTES} bytes"
    );
    let bytes = read_body_bytes(read, &entry.reference, remaining, deadline).await?;
    serde_json::from_slice(&bytes)
        .with_context(|| format!("canonical metadata for {event_id} is not HistoryEntityHead"))
}

pub(crate) async fn read_body_entries(
    read: &crate::http::HistoryRead,
    event_id: &str,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<HistoryBodyEntry>> {
    tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
        let mut entries = Vec::new();
        let mut cursor = None;
        let mut seen = HashSet::new();
        for page_index in 0..CURSOR_PAGE_LIMIT {
            let page = read
                .bodies(event_id, cursor.clone(), HISTORY_DEMAND)
                .await?;
            charge_history_page(&page, HISTORY_DEMAND, remaining)?;
            let HistoryBodyPage {
                owner_event_id,
                entries: page_entries,
                next,
            } = page;
            ensure!(
                owner_event_id == event_id,
                "History bodies belonged to another event"
            );
            entries.extend(page_entries);
            let Some(next) = next else {
                return Ok(entries);
            };
            ensure!(
                page_index + 1 < CURSOR_PAGE_LIMIT && seen.insert(next.clone()),
                "History body directory repeated or exceeded its page budget"
            );
            cursor = Some(next);
        }
        bail!("History body directory exceeded its bounded page budget")
    })
    .await
    .context("History body directory observation exceeded its deadline")?
}

pub(crate) async fn read_body_bytes(
    read: &crate::http::HistoryRead,
    reference: &HistoryEventBodyRef,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<u8>> {
    ensure!(
        reference.byte_length <= *remaining as u64,
        "History body exceeds the remaining observation budget"
    );
    let mut bytes = Vec::with_capacity(usize::try_from(reference.byte_length)?);
    while (bytes.len() as u64) < reference.byte_length {
        let offset = bytes.len() as u64;
        let max_bytes = (reference.byte_length - offset).min(BODY_CHUNK_BYTES as u64) as u32;
        let window = tokio::time::timeout_at(
            tokio::time::Instant::from_std(deadline),
            read.body(reference.clone(), offset, max_bytes),
        )
        .await
        .context("History body read exceeded its deadline")??;
        ensure!(
            window.offset == offset
                && !window.bytes.is_empty()
                && window.bytes.len() <= usize::try_from(max_bytes)?
                && window.total_length == reference.byte_length,
            "History body range did not advance within its declared length"
        );
        charge_history_bytes(serde_json::to_vec(&window)?.len(), remaining)?;
        bytes.extend(window.bytes);
    }
    ensure!(
        bytes.len() as u64 == reference.byte_length,
        "History body length mismatch"
    );
    Ok(bytes)
}

pub(crate) async fn body_text(
    read: &crate::http::HistoryRead,
    entry: &HistoryBodyEntry,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<String> {
    let bytes = read_body_bytes(read, &entry.reference, remaining, deadline).await?;
    String::from_utf8(bytes).context("History text body is not UTF-8")
}

pub(crate) async fn turn_head(
    read: &crate::http::HistoryRead,
    turn_id: &str,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<HistoryTurnHead> {
    tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
        let mut cut: Option<HistoryCut> = None;
        let mut cursor = None;
        let mut seen = HashSet::new();
        for page_index in 0..CURSOR_PAGE_LIMIT {
            let page = read
                .events_page(
                    HistoryEventsQuery::Turn {
                        turn_id: turn_id.to_owned(),
                    },
                    cut.clone(),
                    cursor.clone(),
                    HISTORY_DEMAND,
                )
                .await?;
            charge_history_page(&page, HISTORY_DEMAND, remaining)?;
            let HistoryEventsPage {
                cut: page_cut,
                entries,
                next,
            } = page;
            for entry in entries {
                if let Some(HistoryRowHead::Turn(head)) = entry.head
                    && head.turn_id == turn_id
                {
                    return Ok(head);
                }
            }
            let Some(next) = next else {
                break;
            };
            ensure!(
                page_index + 1 < CURSOR_PAGE_LIMIT && seen.insert(next.clone()),
                "History Turn continuation repeated or exceeded its page budget"
            );
            cut = Some(page_cut);
            cursor = Some(next);
        }
        bail!("History has no Turn {turn_id}")
    })
    .await
    .context("History Turn observation exceeded its deadline")?
}

pub(crate) async fn turn_head_for_input(
    read: &crate::http::HistoryRead,
    input_id: &str,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Option<HistoryTurnHead>> {
    tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
        let mut cut: Option<HistoryCut> = None;
        let mut cursor = None;
        let mut seen = HashSet::new();
        for page_index in 0..CURSOR_PAGE_LIMIT {
            let page = read
                .turns_page(cut.clone(), cursor.clone(), HISTORY_DEMAND)
                .await?;
            charge_history_page(&page, HISTORY_DEMAND, remaining)?;
            let HistoryTimelinePage {
                cut: page_cut,
                entries,
                next,
            } = page;
            for entry in entries {
                if let HistoryRowHead::Turn(head) = entry.head
                    && head.input_id.as_deref() == Some(input_id)
                {
                    return Ok(Some(head));
                }
            }
            let Some(next) = next else {
                break;
            };
            ensure!(
                page_index + 1 < CURSOR_PAGE_LIMIT && seen.insert(next.clone()),
                "History input Turn continuation repeated or exceeded its page budget"
            );
            cut = Some(page_cut);
            cursor = Some(next);
        }
        Ok(None)
    })
    .await
    .context("History input Turn observation exceeded its deadline")?
}

pub(crate) async fn turn_detail(
    read: &crate::http::HistoryRead,
    head: &HistoryTurnHead,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Turn> {
    let event_id = head
        .detail_event_id
        .as_deref()
        .with_context(|| format!("History Turn {} omitted its typed detail", head.turn_id))?;
    let detail = read.event(event_id, HISTORY_DEMAND).await?;
    charge_history_page(&detail, HISTORY_DEMAND, remaining)?;
    let payload = detail
        .payload_ref
        .context("History Turn detail omitted its payload")?;
    let bytes = read_body_bytes(read, &payload, remaining, deadline).await?;
    let turn: Turn = serde_json::from_slice(&bytes)
        .with_context(|| format!("History Turn {} detail is not a Turn", head.turn_id))?;
    ensure!(
        turn.id == head.turn_id && history_turn_state(&turn.state) == head.state,
        "History Turn head and immutable detail disagree"
    );
    Ok(turn)
}

pub(crate) async fn assert_completed_turn(
    read: &crate::http::HistoryRead,
    turn_id: &str,
    expected_input_id: Option<&str>,
    require_success: bool,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<()> {
    let head = turn_head(read, turn_id, remaining, deadline).await?;
    if let Some(expected) = expected_input_id {
        ensure!(
            head.input_id.as_deref() == Some(expected),
            "History Turn input identity did not match the expected input"
        );
    }
    if require_success {
        ensure!(
            head.state == HistoryTurnState::Completed,
            "History Turn {turn_id} did not complete successfully: {:?}",
            head.state
        );
    }
    let detail = turn_detail(read, &head, remaining, deadline).await?;
    if let Some(expected) = expected_input_id {
        ensure!(
            detail.input_id.as_deref() == Some(expected),
            "History Turn detail input identity did not match the expected input"
        );
    }
    if require_success {
        ensure!(
            matches!(detail.state, TurnState::Completed(_)),
            "History Turn {turn_id} immutable detail is not Completed"
        );
    }
    Ok(())
}

pub(crate) async fn current_payload_bytes(
    read: &crate::http::CurrentRead,
    payload: &CurrentPayloadData,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<u8>> {
    match payload {
        CurrentPayloadData::Inline { bytes } => Ok(bytes.clone()),
        CurrentPayloadData::Deferred {
            reference,
            byte_length,
        } => current_content_bytes(read, reference, *byte_length, remaining, deadline).await,
    }
}

pub(crate) async fn current_content_bytes(
    read: &crate::http::CurrentRead,
    reference: &pl_protocol::CurrentContentRef,
    length: u64,
    remaining: &mut usize,
    deadline: Instant,
) -> Result<Vec<u8>> {
    ensure!(
        length <= *remaining as u64,
        "Current content exceeds the remaining observation budget"
    );
    let mut bytes = Vec::with_capacity(usize::try_from(length)?);
    let mut generation = None;
    while (bytes.len() as u64) < length {
        let offset = bytes.len() as u64;
        let max_bytes = (length - offset).min(BODY_CHUNK_BYTES as u64) as u32;
        let window = tokio::time::timeout_at(
            tokio::time::Instant::from_std(deadline),
            read.read_body(reference, ContentRange { offset, max_bytes }),
        )
        .await
        .context("Current body read exceeded its deadline")??;
        ensure!(
            window.offset == offset
                && !window.bytes.is_empty()
                && window.bytes.len() <= usize::try_from(max_bytes)?
                && window.available_through == length
                && window.sealed,
            "Current body range did not advance within its declared length"
        );
        charge_history_bytes(serde_json::to_vec(&window)?.len(), remaining)?;
        if let Some(expected) = &generation {
            ensure!(
                &window.generation == expected,
                "Current body generation changed mid-read"
            );
        } else {
            generation = Some(window.generation);
        }
        bytes.extend(window.bytes);
    }
    ensure!(bytes.len() as u64 == length, "Current body length mismatch");
    Ok(bytes)
}

pub(crate) async fn open_current(
    http: &crate::http::StudioHttp,
    thread_id: &str,
) -> Result<crate::http::CurrentRead> {
    http.open_current(thread_id, CURRENT_DEMAND).await
}

pub(crate) fn current_demand() -> ReadDemand {
    CURRENT_DEMAND
}

fn unique_body<'a>(
    bodies: &'a [HistoryBodyEntry],
    predicate: impl Fn(&HistoryBodyEntry) -> bool,
) -> Result<Option<&'a HistoryBodyEntry>> {
    let mut matching = bodies.iter().filter(|body| predicate(body));
    let first = matching.next();
    ensure!(
        matching.next().is_none(),
        "History body directory contains duplicate selected roles"
    );
    Ok(first)
}

fn is_text_body_key(key: &str) -> bool {
    key == "body" || key == "legacy-content:body" || key.ends_with(":body")
}

fn is_tool_output_body(body: &HistoryBodyEntry) -> bool {
    body.role == HistoryBodyRole::ToolOutput
        || body.body_key == "tool.result"
        || body.body_key.ends_with(":tool.result")
}

fn is_tool_arguments_body(body: &HistoryBodyEntry) -> bool {
    body.role == HistoryBodyRole::ToolArguments
        || body.body_key == "tool.arguments"
        || body.body_key.ends_with(":tool.arguments")
}

fn ensure_history_payload_matches(head: &HistoryEntityHead, payload: &Value) -> Result<()> {
    ensure!(
        payload["contract"] == "anywork.chat/1"
            && payload["type"].is_string()
            && payload["data"].is_object(),
        "canonical payload omitted its current contract, type, or data"
    );
    if let Some(turn_id) = payload["turnId"].as_str() {
        ensure!(
            !turn_id.is_empty(),
            "canonical payload has an empty Turn identity"
        );
    }
    if let Some(channel) = head.text_channel {
        ensure!(
            payload["type"] == "text"
                && serde_json::from_value::<ThreadTextChannel>(payload["data"]["channel"].clone())
                    .is_ok_and(|saved| saved == channel),
            "typed History text channel and opaque payload disagree"
        );
    }
    if let Some(tool) = &head.tool {
        ensure!(
            payload["type"] == "tool"
                && payload["data"]["invocation"]["toolCallId"] == tool.call_id
                && payload["data"]["invocation"]["name"] == tool.name,
            "typed History tool identity and opaque payload disagree"
        );
    }
    match &head.state {
        HistoryEntityState::KnownTerminal { outcome } => {
            if head.kind == pl_protocol::ChatAtomKind::TurnReceipt {
                ensure!(
                    payload["type"] == "turn",
                    "terminal History Turn receipt is not a Turn payload"
                );
                let saved: pl_protocol::ChatTerminalOutcome =
                    serde_json::from_value(payload["data"]["outcome"].clone())?;
                ensure!(
                    &saved == outcome,
                    "typed History terminal and opaque payload disagree"
                );
            }
        }
        HistoryEntityState::Unknown | HistoryEntityState::KnownActive { .. } => {
            bail!(
                "canonical History original {} is not a known terminal",
                head.entity_id
            );
        }
    }
    Ok(())
}

pub(crate) fn history_turn_state(state: &TurnState) -> HistoryTurnState {
    match state {
        TurnState::Queued(_) => HistoryTurnState::Queued,
        TurnState::Running(_) => HistoryTurnState::Running,
        TurnState::Completed(_) => HistoryTurnState::Completed,
        TurnState::Cancelled(_) => HistoryTurnState::Cancelled,
        TurnState::Failed(_) => HistoryTurnState::Failed,
        TurnState::BudgetLimited(_) => HistoryTurnState::BudgetLimited,
    }
}
