//! Drive the original detector with a monotonic Tokio observation clock and real storage owners.

use super::storage_fault_tests::{
    live_projection, register_test_thread, test_thread, ticket, visible_input_ticket,
};
use super::*;
use pl_core::thread::cold::ColdStore;
use sea_orm::{ConnectionTrait, Database, TransactionTrait};

#[tokio::test]
async fn unprepared_head_stalls_despite_later_admissions_and_notifications() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "projection-watchdog";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let channel = sink.0.channel.clone();
    let lease = channel.step_lock.lock().await;
    channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW);
    assert!(channel.subscribe().borrow().fault.is_none());
    let first = visible_input_ticket(id, 1, "first")?;
    sink.admit(id, first.clone())?;
    let admitted_at = lock_progress(&sink.0).effects.front().unwrap().admitted_at;
    for sequence in 2..=4 {
        sink.admit(
            id,
            visible_input_ticket(id, sequence, &format!("later-{sequence}"))?,
        )?;
        channel.changed.notify_one();
        channel.status.send_modify(|_| {});
        let _ = sink.pressure(id);
        channel.detect_stall_at(admitted_at + Duration::from_secs(59));
        assert!(channel.subscribe().borrow().fault.is_none());
    }
    let retained = sink.pressure(id).thread_bytes;
    channel.detect_stall_at(admitted_at + NO_PROGRESS_WINDOW);
    let failed = channel.subscribe().borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::NoProgress)
    );
    assert_eq!(failed.committed_sequence, 0);
    assert_eq!(failed.queued_records, 4);
    assert_eq!(sink.pressure(id).thread_bytes, retained);
    assert!(sink.flush(id, 1).await.is_err());
    channel.detect_stall_at(admitted_at + NO_PROGRESS_WINDOW * 2);
    assert_eq!(
        channel.subscribe().borrow().fault_generation,
        failed.fault_generation
    );

    let mut projection = live_projection(&sink).await?;
    let mut deferred_head = None;
    for sequence in 1..=4 {
        let write = lock_progress(&sink.0).effects[(sequence - 1) as usize]
            .write
            .clone();
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection
            .publish_prepared(&sink.0.chat, &mut prepared)
            .await?;
        if sequence == 1 {
            deferred_head = Some(prepared);
            continue;
        }
        if sequence == 2 {
            assert!(
                !channel.prepare(prepared.clone()),
                "a prepared tail cannot skip the head"
            );
            assert_eq!(lock_progress(&sink.0).prepared_through(), 0);
            assert!(channel.prepare(deferred_head.take().unwrap()));
        }
        assert!(channel.prepare(prepared));
        assert_eq!(lock_progress(&sink.0).prepared_through(), sequence);
    }
    assert_eq!(channel.subscribe().borrow().fault, failed.fault);
    drop(lease);
    store
        .thread_persistence()
        .retry_history(id, failed.fault_generation)
        .await?;
    sink.flush(id, 4).await?;
    assert_eq!(store.history(id).await?.watermark().await?, 4);
    channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW);
    assert!(channel.subscribe().borrow().fault.is_none());

    // A known projection failure keeps its source and generation even after the stall window.
    let lease = channel.step_lock.lock().await;
    let fifth = visible_input_ticket(id, 5, "explicit-failure")?;
    sink.admit(id, fifth.clone())?;
    channel.fail_projection(5, "controlled projection failure".to_owned());
    let explicit = channel.subscribe().borrow().clone();
    channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW * 2);
    assert_eq!(*channel.subscribe().borrow(), explicit);
    assert!(sink.flush(id, 5).await.is_err());
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &fifth.effect, &fifth.checkpoint.state)
        .await?;
    projection
        .publish_prepared(&sink.0.chat, &mut prepared)
        .await?;
    assert!(channel.prepare(prepared));
    drop(lease);
    store
        .thread_persistence()
        .retry_history(id, explicit.fault_generation)
        .await?;
    sink.flush(id, 5).await?;
    channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn pending_sql_retains_writer_and_obligations_until_the_call_returns() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "sql-watchdog";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let channel = sink.0.channel.clone();
    let lease = channel.step_lock.lock().await;
    let mut projection = live_projection(&sink).await?;
    let write = visible_input_ticket(id, 1, "sql-input")?;
    sink.admit(id, write.clone())?;
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection
        .publish_prepared(&sink.0.chat, &mut prepared)
        .await?;
    assert!(channel.prepare(prepared));
    assert_eq!(
        lock_progress(&sink.0).stage,
        Some(HistoryStage::WriterQueue)
    );
    let retained = sink.pressure(id).thread_bytes;

    let path = store
        .session_paths("project-test", id)?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    let blocker = db.begin().await?;
    blocker
        .execute_unprepared("UPDATE history_meta SET applied_write_seq = applied_write_seq")
        .await?;
    let (entered, pending) = tokio::sync::oneshot::channel();
    *channel.sql_pending.lock().unwrap() = Some(entered);
    channel.request_flush(1);
    drop(lease);
    pending.await?;
    let started = {
        let progress = lock_progress(&sink.0);
        assert_eq!(progress.stage, Some(HistoryStage::SqlCommit));
        assert_eq!(progress.prepared_through(), 1);
        progress.last_progress_at.unwrap()
    };
    channel.detect_stall_at(started + Duration::from_secs(59));
    assert!(channel.subscribe().borrow().fault.is_none());
    channel.detect_stall_at(started + NO_PROGRESS_WINDOW);
    let failed = channel.subscribe().borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::NoProgress)
    );
    assert_eq!(failed.committed_sequence, 0);
    assert_eq!(failed.queued_records, 1);
    assert_eq!(sink.pressure(id).thread_bytes, retained);
    assert!(
        channel.step_lock.try_lock().is_err(),
        "SQL still owns the writer"
    );
    assert!(
        channel
            .workers
            .lock()
            .await
            .iter()
            .any(|worker| !worker.is_finished())
    );
    assert!(sink.flush(id, 1).await.is_err());
    assert_eq!(store.history(id).await?.watermark().await?, 0);

    let mut released = channel.effects_released.subscribe();
    blocker.rollback().await?;
    while *released.borrow_and_update() < 1 {
        released.changed().await?;
    }
    assert_eq!(store.history(id).await?.watermark().await?, 1);
    assert_eq!(channel.subscribe().borrow().fault, failed.fault);
    assert!(!lock_progress(&sink.0).fault_recovered);
    // The real call may finish after the watchdog fired. Its success is not automatic recovery.
    store
        .thread_persistence()
        .retry_history(id, failed.fault_generation)
        .await?;
    sink.flush(id, 1).await?;
    channel.stop_and_join().await?;
    Ok(())
}

#[test]
fn diagnostic_reasons_are_bounded_categories_without_private_source_text() {
    let error = anyhow::Error::new(std::io::Error::new(
        std::io::ErrorKind::PermissionDenied,
        "token=secret private provider response",
    ))
    .context("authorization: secret")
    .context("private request")
    .context("private response")
    .context("private path");
    assert_eq!(safe_error_reasons(&error), vec!["redacted_error"; 4]);
    let io = anyhow::Error::new(std::io::Error::new(
        std::io::ErrorKind::PermissionDenied,
        "token=secret private provider response",
    ));
    assert_eq!(safe_error_reasons(&io), vec!["io_permission_denied"]);
}

#[derive(Clone, Default)]
struct DiagnosticEvents(Arc<Mutex<Vec<BTreeMap<String, String>>>>);

#[derive(Default)]
struct DiagnosticFields(BTreeMap<String, String>);

impl tracing::field::Visit for DiagnosticFields {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        self.0.insert(field.name().to_owned(), format!("{value:?}"));
    }
}

impl tracing::Subscriber for DiagnosticEvents {
    fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
        metadata.target() == "conversation_work"
    }
    fn new_span(&self, _: &tracing::span::Attributes<'_>) -> tracing::span::Id {
        tracing::span::Id::from_u64(1)
    }
    fn record(&self, _: &tracing::span::Id, _: &tracing::span::Record<'_>) {}
    fn record_follows_from(&self, _: &tracing::span::Id, _: &tracing::span::Id) {}
    fn event(&self, event: &tracing::Event<'_>) {
        let mut fields = DiagnosticFields::default();
        event.record(&mut fields);
        self.0.lock().unwrap().push(fields.0);
    }
    fn enter(&self, _: &tracing::span::Id) {}
    fn exit(&self, _: &tracing::span::Id) {}
}

#[test]
fn diagnostic_event_correlates_only_the_head_execution_and_redacts_causes() -> Result<()> {
    use pl_core::thread::{ActiveExecution, ExecutionPhase};

    let capture = DiagnosticEvents::default();
    let channel = HistoryChannel::new(Arc::new(AtomicU64::new(0)));
    let mut progress = Progress::default();
    for (sequence, execution_id) in [(1, "execution-head"), (2, "execution-tail")] {
        let mut write = ticket("diagnostic-thread", sequence);
        write.checkpoint.state.execution = Some(ActiveExecution {
            id: execution_id.to_owned(),
            phase: ExecutionPhase::Running,
            turn_id: None,
        });
        let bytes = serde_json::to_vec(&write.effect)?.len() as u64;
        progress.effects.push_back(QueuedEffect {
            sequence,
            admitted_at: Instant::now(),
            write: Arc::new(write),
            bytes,
            prepared: None,
            prepared_bytes: 0,
        });
        progress.effect_bytes += bytes;
    }
    progress.refresh_head_stage(Instant::now());
    let error = anyhow::Error::new(std::io::Error::new(
        std::io::ErrorKind::PermissionDenied,
        "SYNTHETIC-SECRET-TOKEN private-provider-response",
    ))
    .context("SYNTHETIC-PRIVATE-REQUEST");
    let reasons = safe_error_reasons(&error);
    // No enclosing span: background writers must correlate the event from their own head.
    tracing::subscriber::with_default(capture.clone(), || {
        channel.diagnose(
            &progress,
            Instant::now(),
            "history_store",
            pl_protocol::studio::HistoryFault::WriteFailed,
            &reasons,
        );
        Arc::make_mut(&mut progress.effects.front_mut().unwrap().write)
            .checkpoint
            .state
            .execution = None;
        channel.diagnose(
            &progress,
            Instant::now(),
            "history_store",
            pl_protocol::studio::HistoryFault::WriteFailed,
            &reasons,
        );
    });
    let events = capture.0.lock().unwrap();
    assert_eq!(
        events.len(),
        2,
        "the real diagnostic callsite must emit both events"
    );
    assert_eq!(events[0]["execution_id"], "Some(\"execution-head\")");
    assert_eq!(events[1]["execution_id"], "None");
    for event in events.iter() {
        assert_eq!(event["thread_id"], "Some(\"diagnostic-thread\")");
        assert_eq!(event["effect"], "Some(1)");
        assert_eq!(event["request_id"], "None");
        assert_eq!(event["generation"], "None");
        assert_eq!(event["stage"], "Some(\"projection_prepare\")");
        assert_eq!(event["fault_generation"], "0");
        assert_eq!(
            event["reason_chain"],
            "[\"redacted_error\", \"io_permission_denied\"]"
        );
        let text = format!("{event:?}");
        for private in [
            "SYNTHETIC-SECRET-TOKEN",
            "private-provider-response",
            "SYNTHETIC-PRIVATE-REQUEST",
            "execution-tail",
        ] {
            assert!(!text.contains(private), "diagnostic leaked {private}");
        }
        eprintln!("HISTORY_DIAGNOSTIC {text}");
    }
    Ok(())
}
