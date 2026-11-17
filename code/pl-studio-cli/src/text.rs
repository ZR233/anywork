use anyhow::{Context, Result, ensure};
use pl_protocol::{ChatAtomKind, ThreadTextChannel, Turn};
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::history::{
    HEAD_MAX_BYTES, HISTORY_PROTOCOL_VERSION, HistoryBodyEntry, HistoryBodyPage, HistoryBodyRole,
    HistoryDemand, HistoryEntityHead, HistoryEntityState, HistoryEventBodyRef, HistoryEventsQuery,
    HistoryReader, HistoryRowHead,
};

const READ_ROWS: u32 = 128;
const READ_BYTES: u32 = 1024 * 1024;

fn demand() -> HistoryDemand {
    HistoryDemand {
        max_rows: READ_ROWS,
        max_bytes: READ_BYTES,
    }
}

/// Reads the canonical Final text from immutable History, in History order.
pub(super) async fn final_text(runtime: &StudioRuntime, turn: &Turn) -> Result<String> {
    let reader = runtime
        .open_history_reader(&turn.thread_id, HISTORY_PROTOCOL_VERSION)
        .await?;
    let result = async {
        let (_, through) = reader.capture_position().await?;
        let mut parts = Vec::new();
        let mut pivot = None;
        loop {
            let (_, details, has_more) = reader
                .events_window(
                    HistoryEventsQuery::Turn {
                        turn_id: turn.id.clone(),
                    },
                    Some(through),
                    pivot,
                    true,
                    demand(),
                )
                .await?;
            let Some(last_seq) = details.last().map(|detail| detail.header.seq) else {
                break;
            };
            for detail in details {
                if detail.header.original.is_none() {
                    continue;
                }
                let head = history_head(&reader, &detail).await?;
                if head.kind != ChatAtomKind::Text
                    || head.text_channel != Some(ThreadTextChannel::Final)
                    || !matches!(head.state, HistoryEntityState::KnownTerminal { .. })
                {
                    continue;
                }
                let body = final_body(&reader, &detail.header.event_id).await?;
                let text = match body {
                    Some(reference) => String::from_utf8(read_bytes(&reader, &reference).await?)
                        .context("canonical Final is not UTF-8")?,
                    None if head.content_present == Some(false) => String::new(),
                    None => anyhow::bail!("canonical Final omitted its body"),
                };
                parts.push((detail.header.seq, text));
            }
            if !has_more {
                break;
            }
            pivot = Some(last_seq);
        }
        parts.sort_by_key(|(seq, _)| *seq);
        Ok(parts
            .into_iter()
            .map(|(_, text)| text)
            .collect::<Vec<_>>()
            .join("\n"))
    }
    .await;
    let closed = reader.close().await;
    match (result, closed) {
        (Ok(text), Ok(())) => Ok(text),
        (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(error),
        (Err(error), Err(close)) => {
            Err(error.context(format!("HistoryReader close also failed: {close}")))
        }
    }
}

async fn history_head(
    reader: &HistoryReader,
    detail: &pl_studio_runtime::history::HistoryEventDetail,
) -> Result<HistoryEntityHead> {
    if let Some(HistoryRowHead::Single(head) | HistoryRowHead::Member(head)) = &detail.head {
        return Ok(head.clone());
    }
    let metadata = body_entry(reader, &detail.header.event_id, |body| {
        body.role == HistoryBodyRole::CanonicalMetadata
    })
    .await?
    .context("canonical original omitted typed HistoryEntityHead")?;
    ensure!(
        metadata.reference.byte_length <= HEAD_MAX_BYTES as u64,
        "canonical History head exceeds {HEAD_MAX_BYTES} bytes"
    );
    serde_json::from_slice(&read_bytes(reader, &metadata.reference).await?)
        .context("canonical metadata is not HistoryEntityHead")
}

async fn final_body(reader: &HistoryReader, event_id: &str) -> Result<Option<HistoryEventBodyRef>> {
    Ok(body_entry(reader, event_id, |body| {
        body.role == HistoryBodyRole::Body
            && (body.body_key == "body"
                || body.body_key == "legacy-content:body"
                || body.body_key.ends_with(":body"))
    })
    .await?
    .map(|body| body.reference))
}

async fn body_entry(
    reader: &HistoryReader,
    event_id: &str,
    predicate: impl Fn(&HistoryBodyEntry) -> bool,
) -> Result<Option<HistoryBodyEntry>> {
    let mut cursor = None;
    let mut found = None;
    loop {
        let page = reader
            .list_bodies(event_id.into(), cursor.clone(), demand())
            .await?;
        let HistoryBodyPage {
            owner_event_id,
            entries,
            next,
        } = page;
        ensure!(owner_event_id == event_id, "History body owner mismatch");
        for entry in entries {
            if predicate(&entry) {
                ensure!(found.is_none(), "duplicate selected History body");
                found = Some(entry);
            }
        }
        let Some(next) = next else {
            return Ok(found);
        };
        ensure!(
            cursor.as_deref() != Some(next.as_str()),
            "History body cursor did not advance"
        );
        cursor = Some(next);
    }
}

async fn read_bytes(reader: &HistoryReader, reference: &HistoryEventBodyRef) -> Result<Vec<u8>> {
    let mut bytes = Vec::with_capacity(usize::try_from(reference.byte_length)?);
    while (bytes.len() as u64) < reference.byte_length {
        let offset = bytes.len() as u64;
        let max_bytes = (reference.byte_length - offset)
            .min(u64::from(pl_protocol::CONTENT_WINDOW_MAX_BYTES)) as u32;
        let window = reader
            .read_body(reference.clone(), offset, max_bytes)
            .await?;
        ensure!(
            window.offset == offset
                && !window.bytes.is_empty()
                && window.bytes.len() <= max_bytes as usize
                && window.total_length == reference.byte_length,
            "History body range did not advance"
        );
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}
