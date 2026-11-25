use super::*;
use anyhow::{Context, Result};

#[tokio::test]
async fn history_pages_large_heads_without_duplicate_or_missing_sequences() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let store = HistoryStore::open(
        directory.path().join("history.sqlite"),
        "large-history",
        HistoryLimits {
            pending_events: 64,
            pending_bytes: 1024 * 1024,
        },
    )
    .await?;
    let mut sequence = 0_u64;
    for group in 0..10 {
        let events: Vec<_> = (0..64)
            .map(|offset| {
                sequence += 1;
                let mut event = HistoryEvent::new(
                    format!("event-{group}-{offset}"),
                    crate::history::HistoryEventKind::RunStarted,
                    crate::history::HistoryTimelineRole::Hidden,
                    sequence as i64,
                );
                event.run_id = Some(format!("run-{group}-{offset}"));
                event
            })
            .collect();
        store.accept_batch(&events).await?;
        store.flush().await?;
    }
    assert_eq!(sequence, 640);

    let reader = store.reader();
    let demand = HistoryDemand {
        max_rows: 17,
        max_bytes: 64 * 1024,
    };
    let mut seen = std::collections::BTreeSet::new();
    let mut cursor = None;
    let mut pages = 0;
    loop {
        let page = reader
            .events_page(HistoryEventsQuery::AllEvents, None, cursor, demand)
            .await?;
        assert!(!page.entries.is_empty());
        assert!(
            page.entries.len() <= demand.max_rows as usize,
            "a History page exceeded its row demand"
        );
        pages += 1;
        for entry in page.entries {
            assert!(seen.insert(entry.seq));
        }
        cursor = page.next;
        if cursor.is_none() {
            break;
        }
    }
    assert!(
        pages > 1,
        "the fixture must exercise actual cursor continuation"
    );
    assert_eq!(seen.len(), 640);
    assert_eq!(seen.first().copied(), Some(1));
    assert_eq!(seen.last().copied(), Some(640));
    assert!(cursor.is_none());
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn maximum_history_body_window_reads_the_full_64k_original() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let store = HistoryStore::open(
        directory.path().join("history.sqlite"),
        "large-body",
        HistoryLimits {
            pending_events: 8,
            pending_bytes: 256 * 1024,
        },
    )
    .await?;
    let payload: Vec<u8> = (0..65_536).map(|index| (index % 251) as u8).collect();
    let mut event = HistoryEvent::new(
        "one-large-original",
        crate::history::HistoryEventKind::BackgroundDeliveryRecorded,
        crate::history::HistoryTimelineRole::Hidden,
        1,
    );
    let manifest = crate::history::pack_bodies(
        &mut event,
        vec![crate::history::PendingBody::new(
            "canonical",
            crate::history::HistoryBodyRole::CanonicalPayload,
            Some("application/octet-stream".into()),
            payload.clone(),
        )],
        store.database_id(),
    )?;
    event.payload_schema = "anywork.business/1".into();
    event.payload_json = serde_json::to_string(&serde_json::json!({
        "type": "background_delivery",
        "bodies": manifest,
    }))?;
    store.accept_batch(&[event]).await?;
    store.flush().await?;

    let reader = store.reader();
    let original = reader
        .read_event(
            "one-large-original".into(),
            HistoryDemand {
                max_rows: 1,
                max_bytes: 4096,
            },
        )
        .await?;
    let body =
        crate::history::read_event_body_bytes(&reader, &original, "canonical", Some(64 * 1024))
            .await?
            .context("canonical large body")?;
    assert_eq!(body.len(), 65_536);
    assert_eq!(body, payload);
    reader.close().await;
    store.close().await?;
    Ok(())
}
