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

fn admission_event(id: &str) -> HistoryEvent {
    HistoryEvent::new(
        id,
        HistoryEventKind::RunStarted,
        HistoryTimelineRole::Hidden,
        1,
    )
}

#[tokio::test]
async fn hot_admission_skips_seen_ids_and_never_waits_for_writer_or_flush() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(
        &path,
        "hot-admission",
        HistoryLimits {
            pending_events: 2,
            pending_bytes: 64 * 1024,
        },
    )
    .await?;
    store.accept_batch(&[admission_event("seen")]).await?;
    store.flush().await?;
    store.close().await?;
    let store = HistoryStore::open(
        &path,
        "hot-admission",
        HistoryLimits {
            pending_events: 2,
            pending_bytes: 64 * 1024,
        },
    )
    .await?;
    let paused = store.pause_flush().await;
    let writer_guard = store.admission_guard().await;
    let reads = store.read_query_count();
    let revision = store.memory_admission_revision();
    let mut replay = admission_event("seen");
    replay.payload_json = r#"{"ignoredReplayCandidate":true}"#.into();
    let records = store.accept_new_in_memory(
        &[admission_event("a"), replay.clone(), admission_event("b")],
        revision,
    )?;
    assert_eq!(
        records
            .iter()
            .map(|r| (&*r.event_id, r.seq))
            .collect::<Vec<_>>(),
        [("a", 2), ("b", 3)]
    );
    assert!(
        store
            .accept_new_in_memory(&[replay.clone()], revision)?
            .is_empty()
    );
    assert!(matches!(
        store.accept_new_in_memory(&[admission_event("full")], revision),
        Err(HistoryError::Capacity)
    ));
    assert!(!store.event_exists_in_memory("full"));
    assert_eq!(store.current_head(), 3);
    assert_eq!(store.read_query_count(), reads);
    assert_eq!(store.durable_head(), 1);
    drop(writer_guard);
    assert!(matches!(
        store.accept_batch(&[replay]).await,
        Err(HistoryError::Conflict(_))
    ));
    drop(paused);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn strict_admission_revalidates_ids_added_while_reading_sqlite() -> Result<()> {
    for same_payload in [true, false] {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            directory.path().join("history.sqlite"),
            "strict-race",
            HistoryLimits::default(),
        )
        .await?;
        let old = admission_event("old");
        store.accept_batch(std::slice::from_ref(&old)).await?;
        store.flush().await?;
        let paused = store.pause_flush().await;
        let gate = store.pause_strict_validation();
        let background = store.clone();
        let candidate = admission_event("racing");
        let mut hot = candidate.clone();
        if !same_payload {
            hot.payload_json = r#"{"different":true}"#.into();
        }
        let strict = tokio::spawn(async move {
            background
                .accept_batch(&[old, candidate, admission_event("last")])
                .await
        });
        tokio::time::timeout(std::time::Duration::from_secs(5), gate.arrived.notified()).await?;
        store.accept_new_in_memory(&[hot], store.memory_admission_revision())?;
        gate.resume.notify_one();
        let result = strict.await?;
        if same_payload {
            assert_eq!(result?, [1, 2, 3]);
        } else {
            assert!(matches!(result, Err(HistoryError::Conflict(_))));
            assert_eq!(store.current_head(), 2);
            assert!(!store.event_exists_in_memory("last"));
        }
        drop(paused);
        store.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn stale_usage_preparation_cannot_overwrite_a_newer_accounting_head() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let store = HistoryStore::open(
        directory.path().join("history.sqlite"),
        "usage-race",
        HistoryLimits::default(),
    )
    .await?;
    let paused = store.pause_flush().await;
    // The strict guard captures the revision before potentially asynchronous preparation.
    let guard = store.admission_guard().await;
    let make_usage = |id: &str, total: u64, anchor: bool| -> Result<HistoryEvent> {
        let mut event = HistoryEvent::new(
            id,
            HistoryEventKind::UsageRecorded,
            HistoryTimelineRole::Hidden,
            1,
        );
        event.row_scope = Some(HistoryBusinessRowScope::Accounting);
        event.row_key = Some("accounting:session".into());
        event.is_anchor = anchor;
        event.payload_schema = "anywork.accounting/1".into();
        event.payload_json = serde_json::to_string(&super::body::BusinessEnvelope {
            head: HistoryAccountingHead {
                total_tokens: total,
                inference_count: 1,
                ..Default::default()
            },
            bodies: Vec::new(),
        })?;
        Ok(event)
    };
    store.accept_new_in_memory(
        &[make_usage("hot-usage", 30, true)?],
        store.memory_admission_revision(),
    )?;
    let error = store
        .accept_locked(&guard, &[make_usage("stale-usage", 20, false)?])
        .await
        .expect_err("stale usage must fail");
    assert!(error.is_usage_preparation_changed());
    // A fresh async writer guard must not make an old frozen vector valid.
    let old_revision = guard.usage_revision();
    drop(guard);
    let guard = store.admission_guard().await;
    let error = store
        .accept_locked_at_revision(
            &guard,
            &[make_usage("stale-usage", 20, false)?],
            old_revision,
        )
        .await
        .expect_err("frozen usage must keep its original basis");
    assert!(error.is_usage_preparation_changed());
    assert!(!store.event_exists_in_memory("stale-usage"));
    {
        let known = store.inner.known.lock().unwrap();
        assert_eq!(known.latest_accounting.as_ref().unwrap().total_tokens, 30);
    }
    drop(guard);
    drop(paused);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn hot_admission_capacity_failure_rolls_back_reservations_and_identities() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let a = admission_event("a");
    let bytes = super::validate::event(&a)? as u32;
    let store = HistoryStore::open(
        directory.path().join("history.sqlite"),
        "byte-capacity",
        HistoryLimits {
            pending_events: 8,
            pending_bytes: bytes,
        },
    )
    .await?;
    let paused = store.pause_flush().await;
    assert!(matches!(
        store.accept_new_in_memory(&[a.clone(), admission_event("b")], 0),
        Err(HistoryError::Capacity)
    ));
    assert_eq!(store.current_head(), 0);
    assert_eq!(store.status().retained_events, 0);
    assert_eq!(store.status().retained_bytes, 0);
    assert!(!store.event_exists_in_memory("a"));
    assert!(!store.event_exists_in_memory("b"));
    assert_eq!(store.accept_new_in_memory(&[a], 0)?[0].seq, 1);
    drop(paused);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn strict_admission_revalidates_anchor_and_body_collisions_after_sqlite() -> Result<()> {
    for anchor_collision in [true, false] {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            directory.path().join("history.sqlite"),
            "resource-race",
            HistoryLimits::default(),
        )
        .await?;
        let old = admission_event("old");
        store.accept_batch(std::slice::from_ref(&old)).await?;
        store.flush().await?;
        let mut candidate = admission_event("candidate");
        if anchor_collision {
            candidate.turn_id = Some("turn-1".into());
            candidate.row_scope = Some(HistoryBusinessRowScope::Turn);
            candidate.row_key = Some("turn:turn-1".into());
            candidate.is_anchor = true;
            candidate.payload_schema = "anywork.turn/1".into();
            candidate.payload_json = serde_json::to_string(&super::body::BusinessEnvelope {
                head: HistoryTurnHead {
                    turn_id: "turn-1".into(),
                    input_id: None,
                    run_id: None,
                    state: HistoryTurnState::Running,
                    phase: None,
                    context_disposition: Default::default(),
                    queued_at: None,
                    started_at: None,
                    finished_at: None,
                    updated_at: 1,
                    detail_event_id: None,
                },
                bodies: Vec::new(),
            })?;
        } else {
            let manifest = pack_bodies(
                &mut candidate,
                vec![PendingBody::new(
                    "payload",
                    HistoryBodyRole::CanonicalPayload,
                    Some("text/plain".into()),
                    vec![b'z'; 17_000],
                )],
                store.database_id(),
            )?;
            candidate.payload_json = serde_json::json!({"bodies": manifest}).to_string();
        }
        let mut hot = candidate.clone();
        hot.event_id = "thief".into();
        hot.payload_json = hot.payload_json.replace("candidate", "thief");
        let paused = store.pause_flush().await;
        let gate = store.pause_strict_validation();
        let background = store.clone();
        let strict = tokio::spawn(async move {
            background
                .accept_batch(&[old, candidate, admission_event("last")])
                .await
        });
        tokio::time::timeout(std::time::Duration::from_secs(5), gate.arrived.notified()).await?;
        store.accept_new_in_memory(&[hot], store.memory_admission_revision())?;
        gate.resume.notify_one();
        assert!(matches!(strict.await?, Err(HistoryError::Conflict(_))));
        assert_eq!(store.current_head(), 2);
        assert!(!store.event_exists_in_memory("candidate"));
        assert!(!store.event_exists_in_memory("last"));
        drop(paused);
        store.close().await?;
    }
    Ok(())
}
