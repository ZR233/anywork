//! Immutable delivery originals. Query positions belong to History, never to Current admission.
use crate::history::{
    HistoryDemand, HistoryEventRecord, HistoryEventsQuery, HistoryReader, HistorySource,
    read_event_body_bytes,
};
use anyhow::{Context, Result, ensure};
use pl_core::{context::OpaquePayload, thread::inbox::ThreadMessage};

pub(crate) fn source(thread_id: &str, kind: &str) -> HistorySource {
    HistorySource::Operation {
        operation_id: format!("studio.{kind}:{thread_id}"),
    }
}

fn manifest_byte_length(event: &HistoryEventRecord) -> Option<u64> {
    let value: serde_json::Value = serde_json::from_str(&event.payload_json).ok()?;
    let bodies = value.get("bodies")?.as_array()?;
    let entry = bodies
        .iter()
        .find(|item| item.get("key").and_then(serde_json::Value::as_str) == Some("business_fact"))
        .or_else(|| bodies.first())?;
    entry.get("byteLength").and_then(serde_json::Value::as_u64)
}

async fn decode<T: serde::de::DeserializeOwned>(
    reader: &HistoryReader,
    record: &HistoryEventRecord,
    format: &str,
    max_bytes: usize,
) -> Result<(T, usize)> {
    let bytes = read_event_body_bytes(reader, record, "business_fact", Some(max_bytes))
        .await?
        .context("delivery original has no body")?;
    let len = bytes.len();
    let payload: OpaquePayload = serde_json::from_slice(&bytes)?;
    ensure!(
        payload.format() == format && payload.version() == 1,
        "unsupported delivery producer contract"
    );
    Ok((serde_json::from_str(payload.content())?, len))
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReportIdentity {
    child_id: String,
    commit_sequence: u64,
}

pub(crate) struct Report {
    pub event_seq: u64,
    pub message: ThreadMessage,
}

/// A bounded page of one Thread's actual parent-report producer facts.
pub(crate) async fn reports(
    reader: &HistoryReader,
    thread: &str,
    after: Option<u64>,
    ascending: bool,
    budget: usize,
) -> Result<Vec<Report>> {
    let (_, events, _) = reader
        .events_window(
            HistoryEventsQuery::Source {
                source: source(thread, "parent_report"),
            },
            None,
            after,
            ascending,
            HistoryDemand {
                max_rows: if after.is_none() && !ascending {
                    1
                } else {
                    128
                },
                max_bytes: 64 * 1024,
            },
        )
        .await?;
    let mut page = Vec::new();
    let mut bytes: usize = 0;
    for event in events {
        if let Some(declared) = manifest_byte_length(&event) {
            let size =
                usize::try_from(declared).context("report size exceeds addressable memory")?;
            if bytes.checked_add(size).is_none_or(|total| total > budget) {
                ensure!(
                    !page.is_empty(),
                    "report cannot fit the requested byte budget"
                );
                break;
            }
        }
        let remaining = budget.saturating_sub(bytes);
        let max_read = if page.is_empty() { budget } else { remaining };
        let (message, size): (ThreadMessage, usize) =
            match decode(reader, &event, "pl.studio.parent-report", max_read).await {
                Ok(result) => result,
                Err(_) if !page.is_empty() && bytes.saturating_add(1) > budget => break,
                Err(error) => return Err(error),
            };
        if bytes.checked_add(size).is_none_or(|total| total > budget) {
            ensure!(
                !page.is_empty(),
                "report cannot fit the requested byte budget"
            );
            break;
        }
        ensure!(
            message.payload.format() == "pl.studio.turn-report",
            "parent report has another producer"
        );
        let identity: ReportIdentity = serde_json::from_str(message.payload.content())?;
        ensure!(
            identity.child_id == thread
                && message.id
                    == crate::studio::agent_close::terminal_report_id(
                        thread,
                        identity.commit_sequence
                    ),
            "report producer identity differs"
        );
        bytes += size;
        page.push(Report {
            event_seq: event.seq,
            message,
        });
    }
    Ok(page)
}
