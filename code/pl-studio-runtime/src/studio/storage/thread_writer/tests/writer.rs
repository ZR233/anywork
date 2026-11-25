use super::storage_fault_tests::{
    Fixture, live_projection, ready, register_test_thread, test_thread, ticket,
    visible_input_ticket,
};
use super::*;
use crate::history::{HistoryDemand, HistoryEventsQuery};
use pl_core::thread::{ToolDeliveryTarget, history_sink::HistorySink};
use sea_orm::{ConnectionTrait, Database};

#[tokio::test]
async fn completed_tool_payload_remains_queryable_after_current_releases_delivery() -> Result<()> {
    assert_saved_tool_payload_is_queryable(ToolDeliveryTarget::CallResult).await
}

#[tokio::test]
async fn background_tool_payload_remains_queryable_after_release() -> Result<()> {
    assert_saved_tool_payload_is_queryable(ToolDeliveryTarget::Inbox {
        message_id: "task-result:1".into(),
    })
    .await
}

async fn assert_saved_tool_payload_is_queryable(target: ToolDeliveryTarget) -> Result<()> {
    use pl_core::{
        context::{AgentMessageKind, ContextContent, OpaquePayload},
        model::ModelToolCall,
        thread::{
            ToolDelivery, ToolOutcome,
            inbox::{InboxRecord, ThreadMessage},
            task::{TaskAcknowledgement, TaskRecord, TaskStatus},
        },
        tool::ToolOutput,
    };

    let mut fixture = Fixture::new("retained-tool-result").await?;
    let id = fixture.sink.0.thread.id.clone();
    let expected = serde_json::json!({
        "output": "完整原始结果🧭".repeat(2048),
        "modelOutputBytes": 128,
        "error": null,
        "nestedCallIds": [],
    })
    .to_string();
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
        status: TaskStatus::Succeeded,
        cancel_requested: false,
        acknowledgement: matches!(target, ToolDeliveryTarget::Inbox { .. }).then(|| {
            TaskAcknowledgement {
                record_id: "task-receipt:0".into(),
                context_revision: 1,
            }
        }),
        started_sequence: Some(1),
    };
    let delivery = ToolDelivery {
        target,
        call_id: task.call_id.clone(),
        tool_id: task.tool_id.clone(),
        output: ToolOutput::new(
            OpaquePayload::new("pl.tool.lua", 1, expected.clone())?,
            vec![ContextContent::Text {
                text: "short presentation".into(),
            }],
        ),
        delivered_context: vec![ContextContent::Text {
            text: "short presentation".into(),
        }],
        outcome: ToolOutcome::Succeeded,
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
                payload: delivery.output.payload().clone(),
                context: delivery.delivered_context.clone(),
            },
        }]);
        export.state.inbox = Arc::clone(&inbox);
        effect.inbox = inbox;
    }
    export.state.terminal_tasks = Arc::from([task.clone()]);
    export.state.deliveries = Arc::from([delivery.clone()]);
    effect.tasks = Arc::from([task.clone()]);
    effect.deliveries = Arc::from([delivery]);
    fixture.handoff(&write).await?;
    fixture.finish(1).await?;

    let mut current = pl_core::thread::current::ThreadCurrent::new(
        id.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    current.state.tasks.insert(task.id.clone(), task.clone());
    let paths = fixture.store.registered_session_paths(&id)?;
    crate::studio::storage::current_file::CurrentFile::new(paths.root().to_owned(), id.clone())
        .save(current)
        .await?;

    let saved = fixture
        .sink
        .read_tool_task(&id, &task.id)
        .await?
        .context("completed task must be read from its original History fact")?;
    assert_eq!(saved.task.id, task.id);
    assert_eq!(saved.task.status, TaskStatus::Succeeded);
    let result = saved.delivery.context("complete original tool delivery")?;
    assert_eq!(result.output.payload().format(), "pl.tool.lua");
    assert_eq!(result.output.payload().content(), expected);
    assert!(
        fixture
            .sink
            .read_tool_task(&id, "task:unknown")
            .await?
            .is_none()
    );
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
