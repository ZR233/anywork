use anyhow::{Context, Result, ensure};
use pl_studio_runtime::history::{
    BODY_CHUNK_BYTES, HEAD_MAX_BYTES, HISTORY_PROTOCOL_VERSION, HistoryBodyEntry, HistoryBodyPage,
    HistoryBodyRole, HistoryDemand, HistoryEntityHead, HistoryEntityState, HistoryEventBodyRef,
    HistoryEventDetail, HistoryEventsQuery, HistoryReader, HistoryRowHead,
};
use pl_studio_runtime::{ChatAtomKind, StudioRuntime, ThreadTextChannel, Turn};

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
        let cut = reader.capture().await?;
        let mut parts = Vec::new();
        let mut cursor = None;
        loop {
            let page = reader
                .events_page(
                    HistoryEventsQuery::Turn {
                        turn_id: turn.id.clone(),
                    },
                    Some(cut.clone()),
                    cursor.clone(),
                    demand(),
                )
                .await?;
            for detail in &page.entries {
                if detail.header.original.is_none() {
                    continue;
                }
                let head = history_head(&reader, detail).await?;
                if head.kind != ChatAtomKind::Text
                    || head.text_channel != Some(ThreadTextChannel::Final)
                    || !matches!(head.state, HistoryEntityState::KnownTerminal { .. })
                {
                    continue;
                }
                let bodies = final_bodies(&reader, &detail.header.event_id).await?;
                if bodies.is_empty() && head.content_present != Some(false) {
                    anyhow::bail!("canonical Final omitted its body");
                }
                for (ordinal, reference) in bodies {
                    let text = String::from_utf8(read_bytes(&reader, &reference).await?)
                        .context("canonical Final is not UTF-8")?;
                    parts.push((detail.header.seq, ordinal, text));
                }
            }
            let Some(next) = page.next else {
                break;
            };
            ensure!(
                cursor.as_deref() != Some(next.as_str()),
                "History event cursor did not advance"
            );
            cursor = Some(next);
        }
        parts.sort_by_key(|(seq, ordinal, _)| (*seq, *ordinal));
        Ok(parts
            .into_iter()
            .map(|(_, _, text)| text)
            .collect::<Vec<_>>()
            .join("\n"))
    }
    .await;
    reader.close().await;
    result
}

async fn history_head(
    reader: &HistoryReader,
    detail: &HistoryEventDetail,
) -> Result<HistoryEntityHead> {
    if let Some(HistoryRowHead::Single(head) | HistoryRowHead::Member(head)) = &detail.head {
        return Ok(head.clone());
    }
    let metadata = body_entries(reader, &detail.header.event_id, |body| {
        body.role == HistoryBodyRole::CanonicalMetadata
    })
    .await?;
    ensure!(
        metadata.len() == 1,
        "canonical original must contain one typed HistoryEntityHead"
    );
    let metadata = &metadata[0];
    ensure!(
        metadata.reference.byte_length <= HEAD_MAX_BYTES as u64,
        "canonical History head exceeds {HEAD_MAX_BYTES} bytes"
    );
    serde_json::from_slice(&read_bytes(reader, &metadata.reference).await?)
        .context("canonical metadata is not HistoryEntityHead")
}

async fn final_bodies(
    reader: &HistoryReader,
    event_id: &str,
) -> Result<Vec<(u64, HistoryEventBodyRef)>> {
    Ok(
        body_entries(reader, event_id, |body| body.role == HistoryBodyRole::Body)
            .await?
            .into_iter()
            .map(|body| (body.ordinal, body.reference))
            .collect(),
    )
}

async fn body_entries(
    reader: &HistoryReader,
    event_id: &str,
    predicate: impl Fn(&HistoryBodyEntry) -> bool,
) -> Result<Vec<HistoryBodyEntry>> {
    let mut cursor = None;
    let mut found = Vec::new();
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
                ensure!(
                    found
                        .iter()
                        .all(|selected: &HistoryBodyEntry| selected.ordinal != entry.ordinal),
                    "duplicate History body ordinal"
                );
                found.push(entry);
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
    let mut bytes = Vec::new();
    while (bytes.len() as u64) < reference.byte_length {
        let offset = bytes.len() as u64;
        let max_bytes = (reference.byte_length - offset).min(BODY_CHUNK_BYTES as u64) as u32;
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
