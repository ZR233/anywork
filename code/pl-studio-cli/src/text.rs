use anyhow::{Context, Result, ensure};
use pl_studio_runtime::history::{
    HISTORY_PROTOCOL_VERSION, HistoryBodyRole, HistoryDemand, HistoryEntityState,
    HistoryEventsQuery, decode_event_envelope, stream_body_reference,
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
                if detail.original.is_none() || detail.payload_schema != "anywork.event/1" {
                    continue;
                }
                let envelope = decode_event_envelope(detail)?;
                let head = &envelope.meta;
                if head.entity_kind != ChatAtomKind::Text
                    || head.text_channel != Some(ThreadTextChannel::Final)
                    || !matches!(head.state, HistoryEntityState::KnownTerminal { .. })
                {
                    continue;
                }
                let mut found = Vec::new();
                for (index, body) in envelope.bodies.iter().enumerate() {
                    if body.role != HistoryBodyRole::Body.as_str() {
                        continue;
                    }
                    let text = if let Some(inline) = &body.inline_text {
                        inline.clone()
                    } else if let Some(reference) = &body.reference {
                        String::from_utf8(stream_body_reference(&reader, reference).await?)
                            .context("canonical Final is not UTF-8")?
                    } else if body.byte_length == 0 {
                        String::new()
                    } else {
                        anyhow::bail!("canonical Final body omitted inlineText and reference");
                    };
                    found.push((index as u64, text));
                }
                if found.is_empty() && head.content_present != Some(false) {
                    anyhow::bail!("canonical Final omitted its body");
                }
                for (ordinal, text) in found {
                    parts.push((detail.seq, ordinal, text));
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
