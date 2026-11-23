//! Exact archived-resource ownership over the History entity index.
use crate::history::{
    HistoryBodyRole, HistoryDemand, HistoryEvent, HistoryEventKind, HistoryEventsQuery,
    HistoryReader, HistoryTimelineRole, PendingBody, body::BusinessFactEnvelope, pack_bodies,
    read_event_body_bytes,
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
    database_id: &str,
) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(
        format!(
            "resource:{thread_run}:{effect}:{}:{call}:{}",
            call.len(),
            reference.id()
        ),
        HistoryEventKind::RetainedResourceRecorded,
        HistoryTimelineRole::Hidden,
        at,
    );
    event.run_id = Some(thread_run.into());
    event.entity_id = Some(reference.id().into());
    event.call_id = Some(call.into());
    event.turn_id = turn.map(str::to_owned);
    let payload = OpaquePayload::new(
        "pl.studio.retained-tool-resource",
        1,
        serde_json::to_string(reference)?,
    )?;
    let manifest = pack_bodies(
        &mut event,
        vec![PendingBody::new(
            "resource",
            HistoryBodyRole::CanonicalPayload,
            Some("application/json".into()),
            serde_json::to_vec(&payload)?,
        )],
        database_id,
    )?;
    event.payload_schema = "anywork.business/1".into();
    event.payload_json = serde_json::to_string(&BusinessFactEnvelope {
        fact_type: "retained_resource".into(),
        data: None,
        bodies: manifest,
    })?;
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
            let bytes = read_event_body_bytes(reader, &event, "resource", None)
                .await?
                .context("resource fact has no body")?;
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
