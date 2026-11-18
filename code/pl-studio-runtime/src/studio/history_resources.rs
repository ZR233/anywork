//! Exact archived-resource ownership over the History entity index.
use crate::history::{
    HistoryBody, HistoryBodyRole, HistoryDemand, HistoryEvent, HistoryEventKind,
    HistoryEventsQuery, HistoryReader,
};
use anyhow::{Context, Result, ensure};
use pl_core::context::{OpaquePayload, ResourceReader, ResourceReference};

pub(crate) fn observed_event(
    reference: &ResourceReference,
    thread_run: &str,
    call: &str,
    turn: Option<&str>,
    effect: u64,
    at: i64,
) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(
        format!(
            "resource:{thread_run}:{effect}:{}:{call}:{}",
            call.len(),
            reference.id()
        ),
        HistoryEventKind::BusinessChanged,
        at,
    );
    event.header.run_id = Some(thread_run.into());
    event.header.entity_id = Some(reference.id().into());
    event.header.call_id = Some(call.into());
    event.header.turn_id = turn.map(str::to_owned);
    let payload = OpaquePayload::new(
        "pl.studio.retained-tool-resource",
        1,
        serde_json::to_string(reference)?,
    )?;
    let mut body = HistoryBody::new(
        "resource",
        HistoryBodyRole::CanonicalPayload,
        serde_json::to_vec(&payload)?,
    );
    body.media_type = Some("application/json".into());
    event.payload_body_id = Some(body.body_id.clone());
    event.bodies.push(body);
    Ok(event)
}

pub(crate) async fn read(
    reader: &HistoryReader,
    resources: &crate::resource_store::FileResourceStore,
    id: &str,
) -> Result<Vec<u8>> {
    let mut cursor = None;
    let mut reference = None;
    loop {
        let page = reader
            .events_page(
                HistoryEventsQuery::Entity {
                    entity_id: id.into(),
                },
                None,
                cursor,
                HistoryDemand {
                    max_rows: 128,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        for event in page.entries {
            let body = event.payload_ref.context("resource fact has no body")?;
            let mut bytes = Vec::new();
            let mut offset = 0;
            while offset < body.byte_length {
                let window = reader.read_body(body.clone(), offset, 64 * 1024).await?;
                ensure!(
                    !window.bytes.is_empty(),
                    "resource fact body did not advance"
                );
                offset += window.bytes.len() as u64;
                bytes.extend(window.bytes);
            }
            let payload: OpaquePayload = serde_json::from_slice(&bytes)?;
            ensure!(
                payload.format() == "pl.studio.retained-tool-resource" && payload.version() == 1,
                "unsupported resource producer fact"
            );
            let value: ResourceReference = serde_json::from_str(payload.content())?;
            ensure!(value.id() == id, "resource fact identity differs");
            if let Some(old) = &reference {
                ensure!(old == &value, "resource ownership facts conflict");
            } else {
                reference = Some(value);
            }
        }
        let Some(next) = page.next else {
            break;
        };
        cursor = Some(next);
    }
    let reference = reference.context("Thread has no original proof for this archived resource")?;
    Ok(resources
        .read(reference, tokio_util::sync::CancellationToken::new())
        .await?
        .to_vec())
}
