//! Immutable delivery originals. Query positions belong to History, never to Current admission.
use crate::history::{
    HistoryDemand, HistoryEventDetail, HistoryEventsQuery, HistoryReader, HistorySource,
};
use anyhow::{Context, Result, ensure};
use pl_core::{context::OpaquePayload, thread::inbox::ThreadMessage};

pub(crate) fn source(thread_id: &str, kind: &str) -> HistorySource {
    HistorySource::Operation {
        operation_id: format!("studio.{kind}:{thread_id}"),
    }
}
async fn body(reader: &HistoryReader, detail: &HistoryEventDetail) -> Result<Vec<u8>> {
    let reference = detail
        .payload_ref
        .clone()
        .context("delivery original has no body")?;
    let mut bytes = Vec::new();
    let mut offset = 0;
    while offset < reference.byte_length {
        let window = reader
            .read_body(reference.clone(), offset, 64 * 1024)
            .await?;
        ensure!(
            !window.bytes.is_empty(),
            "delivery original did not advance"
        );
        offset += window.bytes.len() as u64;
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}
async fn decode<T: serde::de::DeserializeOwned>(
    reader: &HistoryReader,
    detail: &HistoryEventDetail,
    format: &str,
) -> Result<T> {
    let payload: OpaquePayload = serde_json::from_slice(&body(reader, detail).await?)?;
    ensure!(
        payload.format() == format && payload.version() == 1,
        "unsupported delivery producer contract"
    );
    Ok(serde_json::from_str(payload.content())?)
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
        let size = event
            .payload_ref
            .as_ref()
            .context("report original body is missing")?
            .byte_length;
        let size = usize::try_from(size).context("report size exceeds addressable memory")?;
        if bytes.checked_add(size).is_none_or(|total| total > budget) {
            ensure!(
                !page.is_empty(),
                "report cannot fit the requested byte budget"
            );
            break;
        }
        let message: ThreadMessage = decode(reader, &event, "pl.studio.parent-report").await?;
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
            event_seq: event.header.seq,
            message,
        });
    }
    Ok(page)
}
