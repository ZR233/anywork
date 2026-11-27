use super::storage_fault_tests::{
    Fixture, live_projection, ready, test_thread, ticket, visible_input_ticket,
};
use super::*;
use crate::history::{HistoryDemand, HistoryEventsQuery};
use pl_core::thread::{ToolDeliveryTarget, history_sink::HistorySink};
use sea_orm::{ConnectionTrait, Database};

#[tokio::test]
async fn tool_result_current_production_recovery_upgrades_legacy_bytes_once() -> Result<()> {
    use crate::studio::thread_factory::recovery::load_current_for_recovery;
    use pl_core::thread::current::{CURRENT_SCHEMA_VERSION, RuntimeEpoch, ThreadCurrent};

    let directory = tempfile::tempdir()?;
    let store = StudioStore::open(directory.path().join("data/studio.sqlite")).await?;
    let thread = test_thread("legacy-current-recovery");
    super::storage_fault_tests::register_test_thread(&store, &thread).await?;
    let session = store.registered_session_paths(&thread.id)?;
    let mut legacy =
        serde_json::to_value(ThreadCurrent::new(thread.id.clone(), RuntimeEpoch::new()))?;
    legacy["schemaVersion"] = 1.into();
    legacy["snapshotRevision"] = 19.into();
    let original = serde_json::to_vec_pretty(&legacy)?;
    std::fs::create_dir_all(session.root())?;
    std::fs::write(session.current_file(), &original)?;
    assert!(
        store
            .state_for(&thread.workspace_id, &thread.id)?
            .load_current()
            .await
            .is_err()
    );

    let recovered = load_current_for_recovery(&store, &thread)
        .await?
        .context("missing legacy Current")?;
    assert_eq!(recovered.schema_version, CURRENT_SCHEMA_VERSION);
    assert_eq!(recovered.snapshot_revision, 19);
    assert_eq!(
        std::fs::read(
            session
                .root()
                .join("migration-backups/current-tool-result-v1/current.original.json")
        )?,
        original
    );
    let published = std::fs::read(session.current_file())?;
    assert!(load_current_for_recovery(&store, &thread).await?.is_some());
    assert_eq!(std::fs::read(session.current_file())?, published);
    assert!(!session.history_database().exists());
    Ok(())
}

#[tokio::test]
async fn tool_result_remains_queryable_after_current_releases_delivery() -> Result<()> {
    assert_saved_tool_payload_is_queryable(ToolDeliveryTarget::CallResult, None).await
}

#[tokio::test]
async fn tool_result_background_remains_queryable_after_release() -> Result<()> {
    assert_saved_tool_payload_is_queryable(
        ToolDeliveryTarget::Inbox {
            message_id: "task-result:1".into(),
        },
        None,
    )
    .await
}

#[tokio::test]
async fn tool_result_cancellation_cause_survives_current_and_history_cold_read() -> Result<()> {
    assert_saved_tool_payload_is_queryable(
        ToolDeliveryTarget::CallResult,
        Some("original operation failed before cancellation"),
    )
    .await
}

#[tokio::test]
async fn tool_result_lookup_ends_on_projection_failure_and_writer_close() -> Result<()> {
    for (id, failure) in [
        (
            "receipt-projection-failed",
            Some("controlled projection failure"),
        ),
        ("receipt-writer-stopped", None),
    ] {
        let fixture = Fixture::new(id).await?;
        let channel = &fixture.sink.0.channel;
        fixture.sink.admit(id, ticket(id, 1))?;
        let read = fixture.sink.read_saved_tool_task(id, "task:missing");
        tokio::pin!(read);
        wait_for_receipt_cut(&fixture.sink, read.as_mut(), 1).await?;
        if let Some(message) = failure {
            channel.fail_projection(1, message.to_owned());
        } else {
            channel.stop_and_join_for_deletion().await?;
        }
        let error = tokio::time::timeout(Duration::from_secs(5), read)
            .await?
            .expect_err("lookup must report the durability failure");
        let diagnostic = error.to_string();
        if let Some(message) = failure {
            assert!(diagnostic.contains(message), "{error}");
            channel.stop_and_join_for_deletion().await?;
        } else {
            // The writer can publish its exit before the lookup observes the stop token.
            assert!(
                diagnostic.contains("history stopped before becoming durable through 1")
                    || (diagnostic.contains("history did not become durable through 1")
                        && diagnostic.contains("history writer unavailable")),
                "{error}"
            );
        }
        history_store(&fixture.sink.0).await?.close().await?;
    }
    Ok(())
}

async fn wait_for_receipt_cut(
    sink: &ThreadStorageSink,
    mut read: std::pin::Pin<&mut impl Future<Output: std::fmt::Debug>>,
    cut: u64,
) -> Result<()> {
    tokio::time::timeout(
        Duration::from_secs(5),
        std::future::poll_fn(|cx| {
            use std::task::Poll;
            if let Poll::Ready(outcome) = read.as_mut().poll(cx) {
                panic!("lookup settled before its admitted prefix was processed: {outcome:?}");
            }
            // Observe the flush request on the lookup's own wakeups, with projection paused.
            if lock_progress(&sink.0).flush_target == cut {
                Poll::Ready(())
            } else {
                Poll::Pending
            }
        }),
    )
    .await?;
    Ok(())
}

async fn assert_saved_tool_payload_is_queryable(
    target: ToolDeliveryTarget,
    cancellation_message: Option<&str>,
) -> Result<()> {
    use pl_core::{
        context::{AgentMessageKind, ContextContent, OpaquePayload},
        model::ModelToolCall,
        thread::{
            ToolDelivery, ToolOutcome,
            inbox::{InboxRecord, ThreadMessage},
            task::{TaskAcknowledgement, TaskRecord, TaskStatus},
        },
        tool::{ToolFailureKind, ToolOutput, opaque::ToolError},
    };

    let mut fixture = Fixture::new("retained-tool-result").await?;
    let id = fixture.sink.0.thread.id.clone();
    let data = serde_json::json!({
        "output": "完整原始结果🧭".repeat(2048),
        "modelOutputBytes": 128,
        "error": null,
        "nestedCallIds": [],
    });
    let content = vec![ContextContent::Text {
        text: "short presentation".into(),
    }];
    let details = cancellation_message.map(|_| serde_json::json!({"archive": ["author receipt"]}));
    let cancelled = cancellation_message.is_some();
    let (status, outcome, delivered_context) = if cancelled {
        (TaskStatus::Cancelled, ToolOutcome::Cancelled, Vec::new())
    } else {
        (
            TaskStatus::Succeeded,
            ToolOutcome::Succeeded,
            content.clone(),
        )
    };
    let task = TaskRecord {
        id: "task:original-tool".into(),
        call_id: "original-tool".into(),
        tool_id: "exec".into(),
        turn_id: "original-turn".into(),
        parent_call_id: None,
        invocation: Some(ModelToolCall {
            call_id: "original-tool".into(),
            tool_id: "exec".into(),
            arguments: OpaquePayload::new("application/json", 1, "{}")?,
            rejection: None,
            presentation_contract: None,
        }),
        revision: 2,
        status,
        cancel_requested: cancelled,
        acknowledgement: matches!(target, ToolDeliveryTarget::Inbox { .. }).then(|| {
            TaskAcknowledgement {
                record_id: "task-receipt:0".into(),
                context_revision: 1,
            }
        }),
        started_sequence: Some(1),
    };
    let mut output = ToolOutput::from_data(data.clone(), content.clone());
    if let Some(details) = &details {
        output = output.with_details(details.clone());
    }
    let cancellation_cause = cancellation_message.map(|message| {
        Arc::new(ToolError::operation(
            std::io::Error::other(message),
            output.clone(),
        ))
    });
    let delivery = ToolDelivery {
        target,
        call_id: task.call_id.clone(),
        tool_id: task.tool_id.clone(),
        output,
        delivered_context: delivered_context.clone(),
        outcome,
        cancellation_cause,
    };
    let assert_delivery = |saved: &ToolDelivery| -> Result<()> {
        assert_eq!(saved.call_id, task.call_id);
        assert_eq!(saved.tool_id, task.tool_id);
        assert_eq!(saved.output.data(), Some(&data));
        assert_eq!(saved.output.details(), details.as_ref());
        assert_eq!(saved.output.content(), content);
        assert_eq!(saved.delivered_context, delivered_context);
        match cancellation_message {
            Some(message) => {
                assert!(matches!(saved.outcome, ToolOutcome::Cancelled));
                let cause = saved
                    .cancellation_cause
                    .as_deref()
                    .context("missing cancellation cause")?;
                assert_eq!(cause.kind(), ToolFailureKind::Operation);
                assert_eq!(cause.to_string(), message);
            }
            None => {
                assert!(matches!(saved.outcome, ToolOutcome::Succeeded));
                assert!(saved.cancellation_cause.is_none());
            }
        }
        Ok(())
    };
    let mut write = ticket(&id, 1);
    let export = Arc::make_mut(&mut write);
    let effect = Arc::make_mut(&mut export.effect);
    if let ToolDeliveryTarget::Inbox { message_id } = &delivery.target {
        let inbox = Arc::from([InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                id: message_id.clone(),
                source_id: task.id.clone(),
                kind: AgentMessageKind::Report,
                payload: OpaquePayload::new(
                    "pl.core.tool-result-reference",
                    1,
                    task.call_id.as_str(),
                )?,
                context: delivery.delivered_context.clone(),
            },
        }]);
        export.state.inbox = Arc::clone(&inbox);
        effect.inbox = inbox;
    }
    export.state.terminal_tasks = Arc::from([task.clone()]);
    let deliveries = Arc::from([delivery]);
    export.state.deliveries = Arc::clone(&deliveries);
    effect.tasks = Arc::from([task.clone()]);
    effect.deliveries = Arc::clone(&deliveries);
    let history = history_store(&fixture.sink.0).await?;
    let channel = Arc::clone(&fixture.sink.0.channel);
    // Leave the live projection paused after the channel takes ownership of the original.
    fixture.sink.admit(&id, write)?;
    let status = channel.subscribe().borrow().clone();
    assert_eq!(status.admitted_sequence, 1);
    assert_eq!(status.committed_sequence, 0);
    assert_eq!(channel.handoff_ticket(), 0);
    assert!(
        crate::studio::storage::tool_task::read(&history.reader(), &task.id)
            .await?
            .is_none()
    );
    assert!(
        fixture
            .sink
            .read_saved_tool_task("foreign-thread", &task.id)
            .await
            .is_err()
    );

    let lookup_sink = fixture.sink.clone();
    let live = lookup_sink.read_saved_tool_task(&id, &task.id);
    tokio::pin!(live);
    // The HistoryReader runs SQLite work in a separate task. Admit the later effect while
    // the first lookup is pending, before it can request a durability barrier.
    assert!(futures::poll!(live.as_mut()).is_pending());
    assert_eq!(lock_progress(&lookup_sink.0).flush_target, 0);
    fixture.sink.admit(&id, ticket(&id, 2))?;
    wait_for_receipt_cut(&lookup_sink, live.as_mut(), 1).await?;
    let original = channel
        .next_unprojected()
        .context("missing admitted original")?;
    fixture.project(&original)?;
    let live_result = tokio::time::timeout(Duration::from_secs(10), live)
        .await??
        .context("admitted original was lost before commit")?;
    assert_eq!(live_result.task, task);
    let status = channel.subscribe().borrow().clone();
    assert_eq!(status.admitted_sequence, 2);
    assert_eq!(status.committed_sequence, 1);
    let later = channel.next_unprojected().context("missing later effect")?;
    fixture.project(&later)?;
    fixture.finish(2).await?;
    history.close().await?;
    drop(history);

    let mut current = pl_core::thread::current::ThreadCurrent::new(
        id.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    current.state.tasks.insert(task.id.clone(), task.clone());
    let paths = fixture.store.registered_session_paths(&id)?;
    let current_file =
        crate::studio::storage::current_file::CurrentFile::new(paths.root().to_owned(), id.clone());
    if cancelled {
        current.state.deliveries = deliveries;
        current_file.save(current).await?;
        current = current_file
            .load()
            .await?
            .context("missing persisted Current")?;
        let [pending] = current.state.deliveries.as_ref() else {
            panic!("expected one pending Current delivery");
        };
        assert_delivery(pending)?;
        current.state.deliveries = Arc::from([]);
    }
    current_file.save(current).await?;
    assert!(
        current_file
            .load()
            .await?
            .unwrap()
            .state
            .deliveries
            .is_empty()
    );

    let reader = crate::history::HistoryStore::open_reader(
        paths.history_database(),
        &id,
        crate::history::HistoryLimits::default(),
    )
    .await?;
    let saved = crate::studio::storage::tool_task::read(&reader, &task.id)
        .await?
        .context("completed task must be read from its original History fact")?;
    assert_eq!(saved.task, task);
    assert_eq!(
        crate::studio::storage::tool_task::read(&reader, &task.call_id)
            .await?
            .unwrap()
            .task,
        task
    );
    assert_delivery(&saved.delivery.context("complete original tool delivery")?)?;
    assert!(
        crate::studio::storage::tool_task::read(&reader, "task:unknown")
            .await?
            .is_none()
    );
    reader.close().await;
    Ok(())
}

fn sqlite_literal(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

#[tokio::test]
async fn resume_feedback_uses_operation_sources_and_immutable_original_receipts() -> Result<()> {
    use pl_core::thread::{ContinuationDisposition, ContinuationOperation, ResumeRequest};
    let id = "resume-history";
    let mut fixture = Fixture::new(id).await?;
    let mut operation = ContinuationOperation {
        request: ResumeRequest {
            operation_id: "resume-once".into(),
            expected_continuation_token: "original-token".into(),
            request_digest: Some("original-route".into()),
        },
        acceptance_epoch: pl_core::thread::current::RuntimeEpoch::new(),
        execution_id: "reserved-execution".into(),
        turn_id: "reserved-turn".into(),
        accepted_revision: 1,
        disposition: ContinuationDisposition::Scheduled,
    };
    for (sequence, disposition) in [
        (1, ContinuationDisposition::Scheduled),
        (2, ContinuationDisposition::Effective),
    ] {
        operation.disposition = disposition;
        let mut export = (*ticket(id, sequence)).clone();
        export
            .state
            .continuation_operations
            .push_back(operation.clone());
        Arc::make_mut(&mut export.effect).continuations = Arc::from([operation.clone()]);
        Arc::make_mut(&mut export.effect).committed_at = sequence as i64;
        fixture.handoff(&Arc::new(export)).await?;
    }
    fixture.finish(2).await?;
    let reader = fixture.store.history(id).await?.reader();
    let page = reader
        .events_page(
            HistoryEventsQuery::AllEvents,
            None,
            None,
            HistoryDemand {
                max_rows: 32,
                max_bytes: 64 * 1024,
            },
        )
        .await?;
    let mut events: Vec<_> = page
        .entries
        .into_iter()
        .filter(|event| matches!(&event.source, Some(crate::HistorySource::Operation { operation_id }) if operation_id == "resume-once"))
        .collect();
    events.sort_by_key(|event| event.seq);
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].kind, crate::HistoryEventKind::SourceStarted);
    assert_eq!(events[1].kind, crate::HistoryEventKind::SourceEnded);
    for (event, expected) in events.iter().zip([
        ContinuationDisposition::Scheduled,
        ContinuationDisposition::Effective,
    ]) {
        assert_eq!(event.entity_id.as_deref(), Some("resume-once"));
        assert_eq!(event.turn_id.as_deref(), Some("reserved-turn"));
        let detail = reader
            .read_event(
                event.event_id.clone(),
                HistoryDemand {
                    max_rows: 1,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        let bytes =
            crate::history::read_event_body_bytes(&reader, &detail, "payload", Some(64 * 1024))
                .await?
                .context("immutable resume payload")?;
        let payload: pl_core::context::OpaquePayload = serde_json::from_slice(&bytes)?;
        assert_eq!(payload.format(), "pl.core.resume-operation");
        let saved: ContinuationOperation = serde_json::from_str(payload.content())?;
        assert_eq!(saved.request, operation.request);
        assert_eq!(saved.acceptance_epoch, operation.acceptance_epoch);
        assert_eq!(saved.execution_id, operation.execution_id);
        assert_eq!(saved.accepted_revision, 1);
        assert_eq!(saved.disposition, expected);
    }
    reader.close().await;
    Ok(())
}

fn normalized_event_body(bytes: &[u8]) -> Option<serde_json::Value> {
    fn strip_admission_ids(value: &mut serde_json::Value) {
        match value {
            serde_json::Value::Array(values) => {
                for value in values {
                    strip_admission_ids(value);
                }
            }
            serde_json::Value::Object(values) => {
                values.remove("bodyId");
                for value in values.values_mut() {
                    strip_admission_ids(value);
                }
            }
            serde_json::Value::Null
            | serde_json::Value::Bool(_)
            | serde_json::Value::Number(_)
            | serde_json::Value::String(_) => {}
        }
    }

    let mut value = serde_json::from_slice(bytes).ok()?;
    strip_admission_ids(&mut value);
    Some(value)
}

#[tokio::test]
async fn rejecting_one_prepared_event_exposes_no_prefix_of_its_effect() -> Result<()> {
    let mut fixture = Fixture::new("whole-effect-admission").await?;
    let channel = fixture.sink.0.channel.clone();
    let lease = channel.step_lock.lock().await;
    let write = visible_input_ticket("whole-effect-admission", 1, "input")?;
    fixture
        .sink
        .admit(&fixture.sink.0.thread.id, write.clone())?;
    let prepared = fixture.projection.prepare_committed(
        &fixture.sink.0.thread,
        &write.effect,
        &write.state,
    )?;
    let mut rejected = (*prepared).clone();
    let mut events = rejected.history_events.to_vec();
    let first = events.first_mut().context("input completion")?;
    // Basic run/source candidates are valid. A later atomic candidate is rejected.
    first.event_id.clear();
    rejected.history_events = Arc::from(events);
    assert!(channel.prepare(Arc::new(rejected)));
    channel.request_flush(1);
    let selected = ready(fixture.select(Instant::now()));
    let history = history_store(&fixture.sink.0).await?;
    let reader = history.reader();
    assert_eq!(reader.capture_position().await?.1, 0);

    assert!(batch::persist(&fixture.sink.0, &selected).await.is_err());
    assert_eq!(
        reader.capture_position().await?.1,
        0,
        "a rejected effect leaked its run/source prefix"
    );
    assert_eq!(
        channel.subscribe().borrow().queued_records,
        1,
        "rejection discarded the reliable effect"
    );
    reader.close().await;
    drop(lease);
    channel.stop_and_join_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn queue_retention_is_charged_once_and_released_only_after_flush() -> Result<()> {
    let mut fixture = Fixture::new("queue-retention").await?;
    let id = fixture.sink.0.thread.id.clone();
    let process = fixture.sink.0.channel.process_bytes.clone();
    let baseline = process.load(Ordering::Acquire);
    let write = visible_input_ticket(&id, 1, "queue-input")?;
    fixture.sink.admit(&id, write.clone())?;
    let admitted = process.load(Ordering::Acquire);
    let status = fixture.sink.0.channel.subscribe().borrow().clone();
    assert_eq!(status.queued_records, 1);
    assert!(status.queued_bytes > 0);
    assert!(admitted > baseline);

    let prepared = fixture.handoff(&write).await?;
    assert!(prepared.retained_bytes() > 0);
    let handed_off = process.load(Ordering::Acquire);
    assert!(
        handed_off <= admitted,
        "projection handoff must transfer, not add, the reliable charge"
    );
    assert_eq!(
        fixture.sink.0.channel.subscribe().borrow().queued_records,
        1,
        "the original admission remains queued until the database commit"
    );

    fixture.finish(1).await?;
    let resident_index = fixture.sink.0.channel.order_index.retained_bytes();
    assert_eq!(process.load(Ordering::Acquire), baseline + resident_index);
    assert_eq!(
        fixture.sink.0.channel.subscribe().borrow().queued_records,
        0
    );
    assert_eq!(
        fixture.sink.0.channel.subscribe().borrow().queued_bytes,
        resident_index,
    );
    Ok(())
}

#[tokio::test]
async fn reprojecting_an_unchanged_effect_keeps_semantics_before_admission() -> Result<()> {
    let mut fixture = Fixture::new("stable-payload").await?;
    let write = visible_input_ticket("stable-payload", 9, "stable-input")?;
    let first = fixture.projection.prepare_committed(
        &fixture.sink.0.thread,
        &write.effect,
        &write.state,
    )?;
    let second = fixture.projection.prepare_committed(
        &fixture.sink.0.thread,
        &write.effect,
        &write.state,
    )?;
    assert_eq!(first.history_events.len(), second.history_events.len());
    for (first, second) in first
        .history_events
        .iter()
        .zip(second.history_events.iter())
    {
        // Body UUIDs are minted at admission. Fresh projection passes must retain the same
        // event semantics, while the SQL retry regression below protects the frozen identity.
        assert_eq!(first.event_id, second.event_id);
        assert_eq!(first.kind, second.kind);
        assert_eq!(first.timeline_role, second.timeline_role);
        assert_eq!(first.entity_id, second.entity_id);
        assert_eq!(first.payload_schema, second.payload_schema);
        match (
            normalized_event_body(first.payload_json.as_bytes()),
            normalized_event_body(second.payload_json.as_bytes()),
        ) {
            (Some(first_json), Some(second_json)) => assert_eq!(first_json, second_json),
            _ => assert_eq!(first.payload_json, second.payload_json),
        }
        assert_eq!(first.bodies.len(), second.bodies.len());
        for (first, second) in first.bodies.iter().zip(second.bodies.iter()) {
            assert_eq!(first.body_key, second.body_key);
            assert_eq!(first.role, second.role);
            match (
                normalized_event_body(&first.bytes),
                normalized_event_body(&second.bytes),
            ) {
                (Some(first), Some(second)) => assert_eq!(first, second),
                _ => assert_eq!(first.bytes, second.bytes),
            }
        }
    }
    fixture.sink.0.channel.stop_and_join_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn stopped_statistics_consumer_does_not_block_writer_shutdown() -> Result<()> {
    let fixture = Fixture::new("statistics-gap").await?;
    let calls_before = fixture.store.calls().metrics();
    let materials_before = fixture.store.calls().subscribe_materials().borrow().clone();
    fixture.store.calls().stop_best_effort();
    submit_accounting(
        &fixture.sink.0,
        super::super::calls::SessionUsageProjection {
            root_thread_id: "statistics-gap".into(),
            thread_id: "statistics-gap".into(),
            revision: 1,
            has_unpriced_usage: false,
            has_incomplete_usage: false,
            purpose_costs: Vec::new(),
        },
    );
    assert!(lock_progress(&fixture.sink.0).pending_accounting.is_some());
    tokio::time::timeout(
        Duration::from_secs(5),
        fixture.sink.0.channel.stop_and_join(),
    )
    .await??;
    assert!(lock_progress(&fixture.sink.0).pending_accounting.is_none());
    assert!(fixture.store.calls().statistics_gap());
    assert_eq!(fixture.sink.0.channel.subscribe().borrow().fault, None);
    let mut expected_metrics = calls_before;
    expected_metrics.statistics_gap = true;
    assert_eq!(fixture.store.calls().metrics(), expected_metrics);
    let mut expected_materials = materials_before;
    expected_materials.statistics_gap = true;
    expected_materials.versions.status += 1;
    assert_eq!(
        *fixture.store.calls().subscribe_materials().borrow(),
        expected_materials
    );
    fixture
        .store
        .thread_persistence()
        .report_calls(fixture.store.calls());
    assert!(
        fixture
            .store
            .thread_persistence()
            .queue_snapshot()
            .statistics_gap
    );
    Ok(())
}

#[tokio::test]
async fn sql_failure_rolls_back_and_retries_the_same_frozen_events_and_bodies() -> Result<()> {
    let id = "batch-atomic-retry";
    let mut fixture = Fixture::new(id).await?;
    let first = visible_input_ticket(id, 1, "input-1")?;
    fixture.handoff(&first).await?;
    fixture.sink.0.channel.await_handoff_durable(id, 1).await?;

    let path = fixture
        .store
        .session_paths("project-test", id)?
        .history_database();
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    let second = visible_input_ticket(id, 2, "input-2")?;
    let third = visible_input_ticket(id, 3, "input-3")?;
    let prepared_second = fixture.handoff(&second).await?;
    let prepared_third = fixture.handoff(&third).await?;
    let rejected_event = prepared_third.history_events[0].event_id.clone();
    db.execute_unprepared(&format!(
        "CREATE TRIGGER reject_third_effect BEFORE INSERT ON history_events \
         WHEN NEW.event_id = {} BEGIN \
         SELECT RAISE(ABORT, 'reject third batch member'); END",
        sqlite_literal(&rejected_event)
    ))
    .await?;

    let channel = fixture.sink.0.channel.clone();
    let mut status = channel.subscribe();
    channel.request_flush(3);
    while status.borrow_and_update().fault.is_none() {
        status.changed().await?;
    }
    let generation = status.borrow().fault_generation;
    assert!(
        fixture
            .store
            .history(id)
            .await?
            .status()
            .write_error
            .is_some()
    );

    let gate = channel.step_lock.lock().await;
    let fourth = ticket(id, 4);
    fixture.sink.admit(id, fourth.clone())?;
    let retried = ready(fixture.select(Instant::now()));
    assert_eq!(
        retried.len(),
        2,
        "new queued work cannot alter the failed transaction"
    );
    assert!(Arc::ptr_eq(&retried[0].prepared, &prepared_second));
    assert!(Arc::ptr_eq(&retried[1].prepared, &prepared_third));

    let originals: Vec<_> = [&prepared_second, &prepared_third]
        .into_iter()
        .flat_map(|prepared| prepared.history_events.iter())
        .map(|event| {
            let event_id = event.event_id.clone();
            let payload_json = event.payload_json.clone();
            let body_id = event.bodies.first().map(|body| body.body_id.clone());
            (event_id, payload_json, body_id)
        })
        .collect();
    db.execute_unprepared("DROP TRIGGER reject_third_effect")
        .await?;
    drop(gate);
    fixture
        .store
        .thread_persistence()
        .retry_history(id, generation)
        .await?;
    while status.borrow_and_update().error.is_some() {
        status.changed().await?;
    }
    assert_eq!(lock_progress(&fixture.sink.0).durable, 3);

    let reader = fixture.store.history(id).await?.reader();
    for (event_id, payload_json, _body_id) in originals {
        let event = reader
            .read_event(
                event_id,
                HistoryDemand {
                    max_rows: 1,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        assert_eq!(
            event.payload_json, payload_json,
            "retry must commit the accepted immutable payload"
        );
    }
    fixture.handoff(&fourth).await?;
    fixture.finish(4).await?;
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn settlement_acknowledges_the_original_sqlite_effect_and_body() -> Result<()> {
    use futures::FutureExt;
    use pl_core::context::OpaquePayload;
    use pl_core::model::ModelSubAttemptSettlement;

    let id = "model-settlement-write";
    let mut fixture = Fixture::new(id).await?;
    fixture
        .handoff(&visible_input_ticket(id, 1, "input")?)
        .await?;
    let channel = &fixture.sink.0.channel;
    channel.await_handoff_durable(id, 1).await?;
    let path = fixture
        .store
        .session_paths("project-test", id)?
        .history_database();
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::ReadWrite,
            |options| options,
        )
        .await?,
    )
    .await
    .context("open the initialized History database for fault injection")?;
    db.execute_unprepared("CREATE TRIGGER reject_settlement BEFORE INSERT ON history_events \
        WHEN NEW.event_id LIKE 'usage:%' BEGIN SELECT RAISE(ABORT, 'controlled settlement failure'); END").await?;

    let receipt = serde_json::json!({
        "turnId": "turn", "attemptId": "a", "logicalRequestId": "a", "generation": 0,
        "retry": 0, "message": "upstream unavailable",
        "billing": {
            "inferenceId": "sub-attempt:1:a:0", "accountId": "account", "modelId": "model",
            "purpose": "turn", "recordedAt": 1,
            "attempt": { "logicalRequestId": "a", "coreAttemptId": "a", "generation": 0,
                "stage": "stream", "outcome": "failed", "usageIsTerminal": false },
            "accounting": { "usage": { "inputTokens": 17, "outputTokens": 7, "cacheReadTokens": 0,
                "totalTokens": 24 }, "pricing": { "kind": "disabled" } }
        }
    });
    let payload = OpaquePayload::new("pl.model.sub-attempt-settlement", 2, receipt.to_string())?;
    let mut export = ticket(id, 2);
    Arc::make_mut(&mut Arc::make_mut(&mut export).effect).model_sub_attempt_settlements =
        Arc::from([ModelSubAttemptSettlement {
            turn_id: Some("turn".into()),
            attempt_id: "a".into(),
            generation: 0,
            payload: payload.clone(),
        }]);
    let sink = fixture.sink.clone();
    fixture.sink.admit(id, export.clone())?;
    let wait = sink.confirm_model_settlement(id, 2);
    tokio::pin!(wait);
    assert!(
        wait.as_mut().now_or_never().is_none(),
        "RAM admission cannot confirm SQLite persistence"
    );
    let accounting = crate::studio::thread_projection::PreparedAccounting::shared(&export.effect)?;
    let prepared = fixture.handoff(&export).await?;
    assert!(Arc::ptr_eq(&accounting, &prepared.accounting));
    let failure = tokio::time::timeout(Duration::from_secs(5), &mut wait)
        .await?
        .expect_err("SQLite rejected the settlement");
    assert!(
        failure
            .to_string()
            .contains("controlled settlement failure"),
        "unexpected SQLite fault: {failure}"
    );
    let generation = sink.0.channel.subscribe().borrow().fault_generation;
    assert_eq!(sink.pressure(id).durable_sequence, 1);
    db.execute_unprepared("DROP TRIGGER reject_settlement")
        .await?;
    let mut status = sink.0.channel.subscribe();
    fixture
        .store
        .thread_persistence()
        .retry_history(id, generation)
        .await?;
    tokio::time::timeout(Duration::from_secs(5), async {
        while status.borrow_and_update().error.is_some() {
            status.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    let history = fixture.store.history(id).await?.reader();
    tokio::time::timeout(Duration::from_secs(5), sink.confirm_model_settlement(id, 2)).await??;
    let event_id = "usage:settlement:sub-attempt:1:a:0".to_owned();
    let event = history
        .read_event(
            event_id,
            HistoryDemand {
                max_rows: 1,
                max_bytes: 64 * 1024,
            },
        )
        .await?;
    assert_eq!(event.turn_id.as_deref(), Some("turn"));
    let body = crate::history::read_event_body_bytes(&history, &event, "modelSettlement", None)
        .await?
        .expect("original receipt body");
    assert_eq!(serde_json::from_slice::<OpaquePayload>(&body)?, payload);
    let mut second = receipt;
    second["attemptId"] = serde_json::json!("title");
    second["logicalRequestId"] = serde_json::json!("title");
    second["billing"]["inferenceId"] = serde_json::json!("sub-attempt:5:title:0");
    second["billing"]["purpose"] = serde_json::json!("title");
    second["billing"]["attempt"]["logicalRequestId"] = serde_json::json!("title");
    second["billing"]["attempt"]["coreAttemptId"] = serde_json::json!("title");
    second["billing"]["attempt"]["outcome"] = serde_json::json!("succeeded");
    second["billing"]["attempt"]["usageIsTerminal"] = serde_json::json!(true);
    second["billing"]["accounting"]["pricing"] = serde_json::json!({
        "kind": "estimated", "cost": {"currency": "CNY", "amount": 0.25}
    });
    let auxiliary_payload =
        OpaquePayload::new("pl.model.sub-attempt-settlement", 2, second.to_string())?;
    let mut export = ticket(id, 3);
    Arc::make_mut(&mut Arc::make_mut(&mut export).effect).model_sub_attempt_settlements =
        Arc::from([ModelSubAttemptSettlement {
            turn_id: Some("turn".into()),
            attempt_id: "title".into(),
            generation: 0,
            payload: auxiliary_payload.clone(),
        }]);
    let prepared = fixture.handoff(&export).await?;
    assert!(prepared.accounting.facts[0].auxiliary);
    tokio::time::timeout(Duration::from_secs(5), sink.confirm_model_settlement(id, 3)).await??;
    let aux_event = history
        .read_event(
            "usage:settlement:sub-attempt:5:title:0".into(),
            HistoryDemand {
                max_rows: 1,
                max_bytes: 64 * 1024,
            },
        )
        .await?;
    let aux_body =
        crate::history::read_event_body_bytes(&history, &aux_event, "modelSettlement", None)
            .await?
            .expect("original auxiliary receipt body");
    assert_eq!(
        serde_json::from_slice::<OpaquePayload>(&aux_body)?,
        auxiliary_payload
    );
    let accounting = history.accounting(None).await?.unwrap();
    assert_eq!(accounting.inference_count, 2);
    assert_eq!(accounting.total_tokens, 48);
    assert!(accounting.has_incomplete_usage);
    assert!(accounting.cache_usage.has_incomplete_usage);
    let costs = history
        .costs_page(
            None,
            None,
            HistoryDemand {
                max_rows: 2,
                max_bytes: 65536,
            },
        )
        .await?;
    assert_eq!(costs.entries.len(), 1);
    let crate::history::HistoryBusinessRowHead::Cost(cost) = &costs.entries[0].head else {
        panic!("expected title cost");
    };
    assert_eq!(cost.purpose.as_deref(), Some("title"));
    assert_eq!(cost.cost_total, 0.25);
    fixture.finish(3).await?;
    db.close().await?;
    Ok(())
}

fn auxiliary_title_payload(
    attempt: &str,
    turn: Option<&str>,
    message: &str,
) -> Result<pl_core::context::OpaquePayload> {
    let receipt = serde_json::json!({
        "turnId": turn, "attemptId": attempt, "logicalRequestId": attempt, "generation": 0,
        "retry": 0, "message": message,
        "billing": {
            "inferenceId": format!("sub-attempt:{}:{attempt}:0", attempt.len()), "accountId": "account",
            "purpose": "title", "recordedAt": 1,
            "attempt": { "logicalRequestId": attempt, "coreAttemptId": attempt, "generation": 0,
                "stage": "stream", "outcome": "failed", "usageIsTerminal": false },
            "accounting": { "usage": { "inputTokens": 17, "outputTokens": 7, "cacheReadTokens": 0,
                "totalTokens": 24 }, "pricing": { "kind": "estimated", "cost": { "currency": "USD", "amount": 0.25 } } }
        }
    });
    Ok(pl_core::context::OpaquePayload::new(
        "pl.model.sub-attempt-settlement",
        2,
        receipt.to_string(),
    )?)
}

#[tokio::test]
async fn repeated_auxiliary_settlement_is_confirmed_once_and_conflicting_body_is_rejected()
-> Result<()> {
    use pl_core::{
        context::OpaquePayload,
        model::{ModelMemberError, ModelSubAttemptSettlement},
        thread::{ThreadHandle, extensions::ExtensionMutation, history_sink::HistorySinkHandle},
    };
    let id = "duplicate-auxiliary-settlement";
    let fixture = Fixture::new(id).await?;
    let sink = fixture.sink.clone();
    let owner = ThreadHandle::start_current(id.into(), None)?;
    owner
        .attach_history(HistorySinkHandle::new(sink.clone()))
        .await?;
    let port = owner.begin_auxiliary_model_call(None).await?;
    let payload = auxiliary_title_payload(port.attempt_id(), port.turn_id(), "supplier failure")?;
    let conflicting =
        auxiliary_title_payload(port.attempt_id(), port.turn_id(), "different failure")?;
    let original = ModelSubAttemptSettlement {
        attempt_id: port.attempt_id().into(),
        turn_id: port.turn_id().map(str::to_owned),
        generation: 0,
        payload: payload.clone(),
    };
    let start = owner.snapshot().commit_sequence;
    let deliveries = tokio::spawn({
        let port = port.clone();
        async move { tokio::join!(port.settle(0, payload.clone()), port.settle(0, payload)) }
    });
    let mut states = owner.subscribe();
    let sequence = tokio::time::timeout(Duration::from_secs(10), async {
        while let Some(snapshot) = states.next().await {
            if snapshot.usage_summary.totals.inference_count == 1 {
                return Some(snapshot.commit_sequence);
            }
        }
        None
    })
    .await?
    .context("the owner must fold on admission")?;
    assert_eq!(sequence, start + 1);
    assert_eq!(owner.snapshot().usage_summary.totals.total_tokens, 24);
    assert!(sink.pressure(id).durable_sequence < sequence);
    assert!(!deliveries.is_finished());
    assert!(matches!(
        port.settle(0, conflicting.clone()).await,
        Err(ModelMemberError::SettlementConflict)
    ));
    let projector =
        super::storage_fault_tests::spawn_live_projection_for_thread(fixture.store.clone(), id);
    let (first, second) = tokio::time::timeout(Duration::from_secs(10), deliveries).await??;
    first?;
    second?;
    assert_eq!(owner.snapshot().commit_sequence, sequence);
    assert_eq!(sink.pressure(id).durable_sequence, sequence);
    let history = fixture.store.history(id).await?.reader();
    assert_eq!(history.accounting(None).await?.unwrap().inference_count, 1);
    let demand = HistoryDemand {
        max_rows: 1,
        max_bytes: 64 * 1024,
    };
    let event = history
        .read_event(
            format!(
                "usage:settlement:{}",
                pl_model::runtime::model_sub_attempt_id(port.attempt_id(), 0)
            ),
            demand,
        )
        .await?;
    assert_eq!(
        event.turn_id, None,
        "a title started outside a Turn has no History Turn link"
    );
    let source = &owner.snapshot().usage_summary.diagnostics.recent_gaps[0].source;
    assert_eq!(source.turn_id, None);
    let costs = history.costs_page(None, None, demand).await?;
    let crate::history::HistoryBusinessRowHead::Cost(cost) = &costs.entries[0].head else {
        panic!("expected title cost");
    };
    assert_eq!(cost.cost_total, 0.25);
    let detail = history
        .read_event(
            format!("usage_cost:{}:{}", event.event_id, cost.row_key()?),
            demand,
        )
        .await?;
    assert_eq!(detail.turn_id, None);
    drop(port);
    owner
        .confirm_saved_model_settlement(original.clone())
        .await?;
    let mut changed = original.clone();
    changed.payload = conflicting;
    assert!(matches!(
        owner.confirm_saved_model_settlement(changed.clone()).await,
        Err(ModelMemberError::SettlementConflict)
    ));
    let mut missing = original.clone();
    missing.generation = 1;
    assert!(matches!(
        owner.confirm_saved_model_settlement(missing.clone()).await,
        Err(ModelMemberError::SettlementExpired)
    ));
    assert_eq!(owner.snapshot().commit_sequence, sequence);
    owner
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: "unrelated".into(),
            expected_revision: None,
            payload: OpaquePayload::text("later effect"),
        }])
        .await?;
    let next = owner.snapshot().commit_sequence;
    assert_eq!(next, sequence + 1);
    tokio::time::timeout(
        Duration::from_secs(5),
        sink.confirm_model_settlement(id, next),
    )
    .await??;
    assert_eq!(history.accounting(None).await?.unwrap().inference_count, 1);
    history.close().await;
    owner.close().await?;
    let saved_current = owner
        .capture_current(tokio_util::sync::CancellationToken::new())
        .await?;
    fixture.finish(owner.snapshot().commit_sequence).await?;
    projector.await?;

    let new_sink = ThreadStorageSink::new(fixture.store.clone(), test_thread(id)).await?;
    let reopened = ThreadHandle::restore_current(saved_current, None)?;
    reopened
        .attach_history(HistorySinkHandle::new(new_sink.clone()))
        .await?;
    assert_eq!(reopened.snapshot().usage_summary.totals.total_tokens, 24);
    let before = reopened.snapshot().commit_sequence;
    reopened.confirm_saved_model_settlement(original).await?;
    assert!(matches!(
        reopened.confirm_saved_model_settlement(changed).await,
        Err(ModelMemberError::SettlementConflict)
    ));
    assert!(matches!(
        reopened.confirm_saved_model_settlement(missing).await,
        Err(ModelMemberError::SettlementExpired)
    ));
    assert_eq!(reopened.snapshot().commit_sequence, before);
    let new_call = reopened.begin_auxiliary_model_call(None).await?;
    let payload = auxiliary_title_payload(
        new_call.attempt_id(),
        new_call.turn_id(),
        "new call after cold reopen",
    )?;
    let reprojector =
        super::storage_fault_tests::spawn_live_projection_for_thread(fixture.store.clone(), id);
    tokio::time::timeout(Duration::from_secs(5), new_call.settle(0, payload)).await??;
    assert_eq!(reopened.snapshot().usage_summary.totals.total_tokens, 48);
    assert_eq!(
        fixture
            .store
            .history(id)
            .await?
            .reader()
            .accounting(None)
            .await?
            .unwrap()
            .inference_count,
        2
    );
    drop(new_call);
    reopened.close().await?;
    new_sink
        .0
        .channel
        .await_handoff_durable(id, reopened.snapshot().commit_sequence)
        .await?;
    new_sink.0.channel.stop_and_join().await?;
    reprojector.await?;
    Ok(())
}

#[tokio::test]
async fn cold_current_upgrades_assistant_pairing_before_the_next_loopback_request() -> Result<()> {
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
        model::{ModelFactory, ModelRequest, ModelToolDeclaration, ToolCallMode},
        thread::{
            UsageCost,
            current::{RuntimeEpoch, ThreadCurrent},
        },
    };
    use pl_model::{
        completion::ToolSpec,
        model::{ModelDefinition, ModelTransportProfile},
        runtime::ThreadModel,
    };
    use pl_provider_fixture::{
        FixtureServer, Protocol, RealtimeToolCall, Reply, Step, responses_text,
        responses_tool_calls,
    };
    use serde_json::{Value, json};

    let provider = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            "First request",
            0,
            Reply::Sse(responses_tool_calls(
                "original-response",
                "model",
                &[RealtimeToolCall {
                    item_id: "fc_fixture",
                    call_id: "call_legacy",
                    name: "lookup",
                    arguments: r#"{"q":1}"#.into(),
                }],
            )),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "Continue v5",
            1,
            Reply::Sse(responses_text("done v5", "next-5", "model")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "Continue v6",
            2,
            Reply::Sse(responses_text("done v6", "next-6", "model")),
        ),
    ])
    .await?;
    let mut model = ModelDefinition::compatible("model");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let runtime = pl_model::runtime::new_with_account_id(
        "migration-fixture",
        pl_model_openai::endpoint::endpoint(Some(provider.base_url())),
        model,
    )?;
    let model = ModelFactory::new(ThreadModel::new(runtime, None).with_in_memory_settlement());
    let tools = Arc::from([ModelToolDeclaration {
        tool_id: "lookup".into(),
        declaration: pl_model::runtime::thread_tool_declaration(&ToolSpec::Function {
            name: "lookup".into(),
            description: "Look up a fixture".into(),
            input_schema: json!({"type":"object","properties":{"q":{"type":"integer"}},"required":["q"]}),
            allowed_callers: Vec::new(),
            output_schema: None,
        })?,
        presentation_contract: None,
    }]);
    let user = |id: &str, turn: &str, text: &str| ContextRecord {
        id: id.into(),
        turn_id: Some(turn.into()),
        source: ContextSource::User,
        content: vec![ContextContent::Text { text: text.into() }],
        tool_calls: Vec::new(),
        tool_data: Default::default(),
    };
    let request = |attempt: &str, turn: &str, context: ContextSnapshot| ModelRequest {
        thread_id: "migration-fixture".into(),
        turn_id: turn.into(),
        attempt_id: attempt.into(),
        context,
        tools: Arc::clone(&tools),
        tool_call_mode: ToolCallMode::Sequential,
        solo_tool_ids: Default::default(),
        committed_private_context: None,
        resources: None,
        cancellation: Default::default(),
        members: None,
        progress: None,
    };
    let mut session = model.open_session().await?;
    let source = session
        .prepare(request(
            "source",
            "original-turn",
            ContextSnapshot {
                revision: 1,
                records: Arc::from([user("original-input", "original-turn", "First request")]),
            },
        ))
        .await?
        .execute()
        .await?;
    assert_eq!(source.tool_calls.len(), 1);
    let canonical = source.tool_calls[0].call_id.clone();
    assert_ne!(canonical, "call_legacy");
    session.close().await?;

    let directory = tempfile::tempdir()?;
    let store = StudioStore::open(directory.path().join("data/studio.sqlite")).await?;
    for version in [5, 6] {
        let thread = test_thread(&format!("assistant-source-v{version}"));
        super::storage_fault_tests::register_test_thread(&store, &thread).await?;
        let paths = store.session_paths("project-test", &thread.id)?;
        tokio::fs::create_dir_all(paths.root()).await?;
        let mut calls = source.tool_calls.clone();
        let mut content = source.content.clone();
        for item in &mut content {
            if let ContextContent::Opaque { payload } = item {
                let mut frame: Value = serde_json::from_str(payload.content())?;
                frame["settlementRelayed"] = json!(true);
                if version == 5 {
                    frame.as_object_mut().unwrap().remove("sourceAttemptId");
                    frame.as_object_mut().unwrap().remove("callBindings");
                    frame["bindings"][0]["callId"] = json!("call_legacy");
                    calls[0].call_id = "call_legacy".into();
                }
                *payload = OpaquePayload::new(payload.format(), version, frame.to_string())?;
            }
        }
        let mut saved = ThreadCurrent::new(thread.id.clone(), RuntimeEpoch::new());
        saved.state.context = ContextSnapshot {
            revision: 3,
            records: Arc::from([
                user("original-input", "original-turn", "First request"),
                ContextRecord {
                    id: "source:output".into(),
                    turn_id: Some("original-turn".into()),
                    source: ContextSource::Assistant,
                    content,
                    tool_calls: calls.clone(),
                    tool_data: Default::default(),
                },
                ContextRecord {
                    id: "original-result".into(),
                    turn_id: Some("original-turn".into()),
                    source: ContextSource::ToolResult {
                        call_id: calls[0].call_id.clone(),
                        tool_id: "lookup".into(),
                    },
                    content: vec![ContextContent::Text {
                        text: "original tool result".into(),
                    }],
                    tool_calls: Vec::new(),
                    tool_data: Default::default(),
                },
            ]),
        };
        saved.state.usage_summary.totals.inference_count = 4;
        saved
            .state
            .usage_summary
            .pricing
            .estimated_costs
            .push(UsageCost {
                currency: "USD".into(),
                amount: 0.25,
            });
        let bytes = serde_json::to_vec(&saved)?;
        tokio::fs::write(paths.current_file(), &bytes).await?;
        let loaded =
            crate::studio::thread_factory::recovery::load_current_for_recovery(&store, &thread)
                .await?
                .context("saved current")?;
        assert!(!paths.history_database().try_exists()?);
        assert_eq!(tokio::fs::read(paths.current_file()).await?, bytes);
        assert_eq!(loaded.state.usage_summary.totals.inference_count, 4);
        assert_eq!(
            loaded.state.usage_summary.pricing.estimated_costs[0].amount,
            0.25
        );
        let mut records = loaded.state.context.records.to_vec();
        assert_eq!(records[1].tool_calls[0].call_id, canonical);
        assert!(
            matches!(&records[2].source, ContextSource::ToolResult { call_id, .. } if call_id == &canonical)
        );
        records.push(user(
            "next-input",
            "next-turn",
            &format!("Continue v{version}"),
        ));
        let mut session = model.open_session().await?;
        session
            .prepare(request(
                "next",
                "next-turn",
                ContextSnapshot {
                    revision: 4,
                    records: records.into(),
                },
            ))
            .await?
            .execute()
            .await?;
        session.close().await?;

        let before = provider.recorded().len();
        Arc::make_mut(&mut saved.state.context.records)[1].id = "missing-provenance".into();
        let unknown = serde_json::to_vec(&saved)?;
        tokio::fs::write(paths.current_file(), &unknown).await?;
        assert!(
            crate::studio::thread_factory::recovery::load_current_for_recovery(&store, &thread)
                .await
                .is_err()
        );
        assert_eq!(tokio::fs::read(paths.current_file()).await?, unknown);
        let records = Arc::make_mut(&mut saved.state.context.records);
        records[1].id = "source:output".into();
        records[1].tool_calls[0].arguments =
            OpaquePayload::new("application/json", 1, r#"{"q":2}"#)?;
        let conflict = serde_json::to_vec(&saved)?;
        tokio::fs::write(paths.current_file(), &conflict).await?;
        assert!(
            crate::studio::thread_factory::recovery::load_current_for_recovery(&store, &thread)
                .await
                .is_err()
        );
        assert_eq!(tokio::fs::read(paths.current_file()).await?, conflict);
        assert_eq!(provider.recorded().len(), before);
    }
    let sent = provider.finish().await?;
    assert_eq!(sent.len(), 3);
    for request in &sent[1..] {
        let input = request.body["input"]
            .as_array()
            .context("Responses input")?;
        assert!(
            input
                .iter()
                .any(|item| item["type"] == "function_call" && item["call_id"] == "call_legacy")
        );
        assert!(
            input
                .iter()
                .any(|item| item["type"] == "function_call_output"
                    && item["call_id"] == "call_legacy"
                    && item["output"]
                        == serde_json::json!([
                            {"type":"input_text", "text":"original tool result"}
                        ]))
        );
    }
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn manual_compaction_settles_over_http_and_sqlite_without_a_turn() -> Result<()> {
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSource},
        model::ModelFactory,
        thread::{
            ContextReplacementReason, ReplaceContext, ThreadHandle,
            context_preparation::{
                ContextPreparation, ContextPreparationHook, ContextPreparationRequest,
                ContextPreparer,
            },
            history_sink::HistorySinkHandle,
        },
    };
    use pl_model::{
        model::{ModelDefinition, ModelPricing, ModelTransportProfile, TokenPriceTier},
        runtime::{ThreadCompactionOptions, ThreadCompactionStrategy, ThreadModel},
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};

    const INSTRUCTIONS: &str = "Compress the conversation";
    const REQUIREMENT: &str = "Summarize the committed history";
    const ATTEMPT: &str = "manual-compaction-request";

    #[derive(Debug)]
    struct ManualCompactor(ThreadModel);
    impl ContextPreparationHook for ManualCompactor {
        async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
            let members = request
                .enter_model_compacting(ATTEMPT.into())
                .await
                .unwrap();
            let mut model = request.model;
            model.attempt_id = ATTEMPT.into();
            model.members = Some(members);
            let result = self
                .0
                .compact(
                    model,
                    ThreadCompactionOptions {
                        strategy: ThreadCompactionStrategy::TextSummary,
                        instructions: INSTRUCTIONS.into(),
                        requirement: REQUIREMENT.into(),
                        summary_prefix: "Summary".into(),
                        max_output_tokens: Some(64),
                    },
                )
                .await;
            match result {
                Ok(result) => ContextPreparation::Prepared {
                    excluded_tool_ids: Vec::new(),
                    inputs: Default::default(),
                    instruction_binding: None,
                    rejected_mutations: Vec::new(),
                    replacement: Some(result.replacement),
                    facts: request.current_facts.to_vec(),
                    mutations: Vec::new(),
                },
                Err(error) => ContextPreparation::Failed {
                    error,
                    mutations: Vec::new(),
                },
            }
        }
    }

    let mut events = responses_text("Compressed history", "manual-result", "manual-model");
    events.last_mut().unwrap()["response"]["usage"] = serde_json::json!({
        "input_tokens": 11, "output_tokens": 7, "total_tokens": 18,
        "input_tokens_details": {"cached_tokens": 0},
    });
    let provider = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        format!("{INSTRUCTIONS}\n\n{REQUIREMENT}"),
        0,
        Reply::Sse(events),
    )])
    .await?;
    let mut model = ModelDefinition::compatible("manual-model");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.extra.pricing = ModelPricing::published(
        "USD",
        vec![TokenPriceTier::flat(2.0, 8.0, Some(1.0), None)],
        "https://example.test/prices",
    );
    let runtime = pl_model::runtime::new_with_account_id(
        "manual",
        pl_model_openai::endpoint::endpoint(Some(provider.base_url())),
        model,
    )?;
    let model = ThreadModel::new(runtime, None);
    let id = "manual-compaction-without-turn";
    let fixture = Fixture::new(id).await?;
    let session = ModelFactory::new(model.clone()).open_session().await?;
    let owner = ThreadHandle::start_current(id.into(), Some(session))?;
    owner
        .attach_history(HistorySinkHandle::new(fixture.sink.clone()))
        .await?;
    owner
        .set_context_preparation(Some(ContextPreparer::new(ManualCompactor(model))))
        .await?;
    let base = owner
        .replace_context(ReplaceContext {
            expected_revision: 0,
            reason: ContextReplacementReason::Rebuild,
            records: vec![ContextRecord {
                id: "history".into(),
                turn_id: None,
                source: ContextSource::Runtime {
                    source_id: "seed".into(),
                },
                content: vec![ContextContent::Text {
                    text: "Committed history for manual compaction".into(),
                }],
                tool_calls: Vec::new(),
                tool_data: Default::default(),
            }],
        })
        .await?;
    let projector =
        super::storage_fault_tests::spawn_live_projection_for_thread(fixture.store.clone(), id);
    let compacted = tokio::time::timeout(
        Duration::from_secs(10),
        owner.compact_context(base.revision, Default::default()),
    )
    .await?
    .with_context(|| format!("manual compaction fixture: {:?}", provider.recorded()))?;
    assert!(compacted.revision > base.revision);
    assert!(owner.snapshot().turns.is_empty());
    assert_eq!(owner.snapshot().usage_summary.totals.inference_count, 1);
    assert_eq!(owner.snapshot().usage_summary.totals.total_tokens, 18);
    let history = fixture.store.history(id).await?.reader();
    let demand = HistoryDemand {
        max_rows: 1,
        max_bytes: 64 * 1024,
    };
    let event_id = format!(
        "usage:settlement:{}",
        pl_model::runtime::model_sub_attempt_id(ATTEMPT, 0)
    );
    let event = history.read_event(event_id.clone(), demand).await?;
    assert_eq!(event.turn_id, None);
    let costs = history.costs_page(None, None, demand).await?;
    let crate::history::HistoryBusinessRowHead::Cost(cost) = &costs.entries[0].head else {
        panic!("expected compaction cost");
    };
    assert_eq!(cost.purpose.as_deref(), Some("compaction"));
    let event = history
        .read_event(format!("usage_cost:{event_id}:{}", cost.row_key()?), demand)
        .await?;
    assert_eq!(event.turn_id, None);
    history.close().await;
    assert_eq!(provider.finish().await?.len(), 1);
    owner.close().await?;
    fixture.finish(owner.snapshot().commit_sequence).await?;
    projector.await?;
    Ok(())
}

#[tokio::test]
async fn preserving_close_waits_for_the_registered_auxiliary_call_and_its_sqlite_save() -> Result<()>
{
    use pl_core::{
        model::ModelMemberError,
        thread::{ThreadHandle, ThreadLifecycle, history_sink::HistorySinkHandle},
    };
    use sea_orm::{SqliteTransactionMode, TransactionOptions, TransactionTrait};
    use tokio::time::timeout;
    let deadline = Duration::from_secs(10);
    let id = "auxiliary-preserve-close";
    let mut fixture = Fixture::new(id).await?;
    let sink = fixture.sink.clone();
    let path = fixture
        .store
        .session_paths("project-test", id)?
        .history_database();
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::ReadWrite,
            |options| options,
        )
        .await?,
    )
    .await?;
    let write_lock = db
        .begin_with_options(TransactionOptions {
            sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
            ..Default::default()
        })
        .await?;
    let owner = ThreadHandle::start_current(id.into(), None)?;
    owner
        .attach_history(HistorySinkHandle::new(sink.clone()))
        .await?;
    let port = owner.begin_auxiliary_model_call(None).await?;
    let expected = auxiliary_title_payload(
        port.attempt_id(),
        port.turn_id(),
        "supplier failure during shutdown",
    )?;
    let event_id = format!(
        "usage:settlement:sub-attempt:{}:{}:0",
        port.attempt_id().len(),
        port.attempt_id()
    );
    let mut states = owner.subscribe();
    let mut close = std::pin::pin!(owner.close());
    assert!(futures::poll!(&mut close).is_pending());
    timeout(deadline, async {
        while let Some(snapshot) = states.next().await {
            if snapshot.lifecycle == ThreadLifecycle::Closing {
                return Ok(());
            }
        }
        anyhow::bail!("owner closed while holding an active model call")
    })
    .await??;
    assert!(matches!(
        owner.begin_auxiliary_model_call(None).await,
        Err(ModelMemberError::Closed)
    ));
    let delivery = tokio::spawn({
        let expected = expected.clone();
        async move { port.settle(0, expected).await }
    });
    let sequence = timeout(deadline, async {
        while let Some(snapshot) = states.next().await {
            if snapshot.usage_summary.totals.inference_count == 1 {
                return Some(snapshot.commit_sequence);
            }
        }
        None
    })
    .await?
    .context("closing owner must retain the incurred receipt")?;
    while let Some(export) = sink.0.channel.next_unprojected() {
        fixture.handoff(&export).await?;
    }
    assert_eq!(owner.snapshot().lifecycle, ThreadLifecycle::Closing);
    assert_eq!(owner.snapshot().usage_summary.totals.total_tokens, 24);
    assert!(!delivery.is_finished());
    assert!(sink.pressure(id).durable_sequence < sequence);
    assert!(futures::poll!(&mut close).is_pending());
    write_lock.rollback().await?;
    let (delivery, closed) = timeout(deadline, async { tokio::join!(delivery, close) }).await?;
    delivery??;
    closed?;
    assert!(owner.snapshot().commit_sequence > sequence);
    while let Some(export) = sink.0.channel.next_unprojected() {
        fixture.handoff(&export).await?;
    }
    let history = fixture.store.history(id).await?;
    assert_eq!(
        history.read_saved_model_settlement(&event_id).await?,
        Some(expected)
    );
    assert_eq!(
        history
            .reader()
            .accounting(None)
            .await?
            .unwrap()
            .inference_count,
        1
    );
    fixture.finish(owner.snapshot().commit_sequence).await?;
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn deleting_thread_cancels_a_model_settlement_wait_without_committing_it() -> Result<()> {
    use pl_core::{
        model::ModelMemberError,
        thread::{ThreadHandle, ThreadLifecycle, history_sink::HistorySinkHandle},
    };
    let deadline = Duration::from_secs(10);
    let id = "auxiliary-delete-with-pending-settlement";
    let fixture = Fixture::new(id).await?;
    let sink = &fixture.sink;
    let owner = ThreadHandle::start_current(id.into(), None)?;
    owner
        .attach_history(HistorySinkHandle::new(sink.clone()))
        .await?;
    let port = owner.begin_auxiliary_model_call(None).await?;
    let payload = auxiliary_title_payload(
        port.attempt_id(),
        port.turn_id(),
        "incurred before deletion",
    )?;
    let event_id = format!(
        "usage:settlement:{}",
        pl_model::runtime::model_sub_attempt_id(port.attempt_id(), 0)
    );
    let mut states = owner.subscribe();
    let delivery = tokio::spawn(async move { port.settle(0, payload).await });
    let sequence = tokio::time::timeout(deadline, async {
        while let Some(state) = states.next().await {
            if state.usage_summary.totals.inference_count == 1 {
                return Some(state.commit_sequence);
            }
        }
        None
    })
    .await?
    .context("the original owner must accept the settlement before deletion")?;
    assert!(sink.pressure(id).durable_sequence < sequence);
    assert!(!delivery.is_finished());

    tokio::time::timeout(deadline, owner.close_for_deletion()).await??;
    assert!(matches!(delivery.await?, Err(ModelMemberError::Closed)));
    assert_eq!(owner.snapshot().lifecycle, ThreadLifecycle::Closed);
    assert_eq!(owner.snapshot().commit_sequence, sequence);
    sink.0.channel.stop_and_join_for_deletion().await?;
    assert_eq!(
        fixture
            .store
            .history(id)
            .await?
            .read_saved_model_settlement(&event_id)
            .await?,
        None
    );
    Ok(())
}

#[tokio::test]
async fn stopped_writer_joins_workers_and_history_reopens_with_a_new_owner() -> Result<()> {
    let id = "retirement-writer-join";
    let mut fixture = Fixture::new(id).await?;
    let channel = fixture.sink.0.channel.clone();
    let write = ticket(id, 1);
    fixture.handoff(&write).await?;
    channel.await_handoff_durable(id, 1).await?;

    let (release, released) = tokio::sync::oneshot::channel();
    channel.workers.lock().await.push(tokio::spawn(async move {
        let _ = released.await;
    }));
    let waiter_channel = channel.clone();
    let waiter = tokio::spawn(async move { waiter_channel.stop_and_join().await });
    channel.stopping.cancelled().await;
    waiter.abort();
    assert!(waiter.await.unwrap_err().is_cancelled());
    assert!(
        !channel.workers.lock().await.is_empty(),
        "cancelled waits cannot lose join ownership"
    );
    release
        .send(())
        .map_err(|_| anyhow::anyhow!("controlled worker lost its owner"))?;
    tokio::time::timeout(Duration::from_secs(5), channel.stop_and_join()).await??;
    assert!(channel.workers.lock().await.is_empty());
    assert!(
        fixture.sink.admit(id, ticket(id, 2)).is_err(),
        "old sinks cannot resume writing"
    );

    let store = fixture.store.clone();
    let reopened = ThreadStorageSink::new(store.clone(), test_thread(id)).await?;
    assert!(!Arc::ptr_eq(&channel, &reopened.0.channel));
    let mut projection = live_projection(&reopened).await?;
    let next = ticket(id, 1);
    reopened.admit(id, next.clone())?;
    let prepared = projection.prepare_committed(&reopened.0.thread, &next.effect, &next.state)?;
    reopened.0.channel.prepare(prepared);
    reopened.0.channel.await_handoff_durable(id, 1).await?;
    let page = store
        .history(id)
        .await?
        .reader()
        .events_page(
            HistoryEventsQuery::AllEvents,
            None,
            None,
            HistoryDemand {
                max_rows: 64,
                max_bytes: 1024 * 1024,
            },
        )
        .await?;
    assert!(page.entries.len() >= 2);
    reopened.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn worker_join_failure_remains_a_failure_after_retry() -> Result<()> {
    let fixture = Fixture::new("retirement-worker-failure").await?;
    let channel = fixture.sink.0.channel.clone();
    channel.workers.lock().await.push(tokio::spawn(async {
        panic!("controlled storage worker failure");
    }));
    assert!(channel.stop_and_join().await.is_err());
    assert!(channel.workers.lock().await.is_empty());
    assert!(
        channel.stop_and_join().await.is_err(),
        "retry cannot erase an observed worker failure"
    );
    Ok(())
}
