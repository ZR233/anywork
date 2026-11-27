use super::storage_fault_tests::{register_test_thread, test_thread, ticket, visible_input_ticket};
use super::*;
use pl_core::thread::history_sink::HistorySink;
use pl_core::{
    context::{ContextRecord, ContextSource},
    thread::{
        journal::ContextChange,
        task::{TaskAcknowledgement, TaskRecord, TaskStatus},
    },
};

#[test]
fn fresh_background_ack_reserves_identity_without_claiming_completion() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process, 0);
    let call_id = "background-call";
    let task = TaskRecord {
        id: format!("task:{call_id}"),
        parent_call_id: None,
        invocation: None,
        call_id: call_id.into(),
        tool_id: "exec".into(),
        turn_id: "turn".into(),
        revision: 2,
        status: TaskStatus::Running,
        cancel_requested: false,
        acknowledgement: Some(TaskAcknowledgement {
            record_id: "receipt".into(),
            context_revision: 4,
        }),
        started_sequence: Some(1),
    };
    let receipt = ContextRecord {
        id: "receipt".into(),
        turn_id: Some("turn".into()),
        source: ContextSource::ToolResult {
            call_id: call_id.into(),
            tool_id: "exec".into(),
        },
        content: vec![pl_core::context::ContextContent::Text {
            text: "accepted".into(),
        }],
        tool_calls: Vec::new(),
        tool_data: Default::default(),
    };
    let effect = pl_core::thread::ThreadEffectBatch {
        thread_id: "thread".into(),
        sequence: 2,
        committed_at: 2,
        context: Some(ContextChange::Append {
            revision: 4,
            records: Arc::from([receipt]),
        }),
        tasks: Arc::from([task]),
        ..Default::default()
    };
    index.reserve_boundaries(&effect, 0)?;
    let background = crate::studio::thread_projection::order::tool_background_started_id(call_id);
    assert!(index.assigned(&background).is_some());
    assert!(
        !index.is_sealed(&background),
        "an ACK receipt does not claim a terminal completion"
    );
    Ok(())
}

#[test]
fn execution_index_retires_sources_and_charges_pending_until_real_confirmation() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process.clone(), 0);
    let observed = index.reserve_observed("attempt-one", "observed")?;
    assert_eq!(observed, 1);
    let reserved_bytes = index.retained_bytes();
    assert!(reserved_bytes > "observed".len() as u64);
    assert_eq!(process.load(Ordering::Acquire), reserved_bytes);
    index.retain::<()>(&Default::default(), Vec::new());
    let active_bytes = index.retained_bytes();
    assert!(active_bytes > 0 && active_bytes < reserved_bytes);
    assert_eq!(
        index.assigned("observed"),
        Some(observed),
        "an older checkpoint cannot retire a source the projection has not reached"
    );
    index.finish_source("attempt-one");
    let identities = BTreeMap::from([("observed".to_owned(), 5_u64)]);
    index.retain(&identities, Vec::new());
    assert!(
        index.retained_bytes() > 0 && index.retained_bytes() < active_bytes,
        "retained facts own the identity after source and change keys are released"
    );
    assert_eq!(index.assigned("observed"), Some(observed));
    index.retain::<()>(&Default::default(), vec!["observed".into()]);
    assert_eq!(
        index.retained_bytes(),
        0,
        "unmaterialized retired source needs no save"
    );
    let order = index.reserve_observed("attempt-two", "completed")?;
    assert_eq!(
        order, 2,
        "retiring a source cannot rewind the scalar ceiling"
    );
    let item = crate::ExecutionItem::new(
        "completed".into(),
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Borrowed("thread"),
            turn_id: std::borrow::Cow::Borrowed("turn"),
            ordinal: order,
            revision: 9,
            created_at: 10,
            updated_at: 20,
        },
        crate::ExecutionShape::Raw(crate::ThreadRawItem::stored(Vec::new(), "done", 20)),
    );
    index.materialize_execution_batch([ExecutionMaterialization::from_item(&item)], 7)?;
    index.mark_completion("completed", true);
    index.finish_source("attempt-two");
    index.retain::<()>(&Default::default(), Vec::new());
    assert!(index.pending("completed"));
    assert!(index.is_sealed("completed"));
    assert!(index.is_terminal("completed"));
    index.confirm_saved(6);
    assert!(
        index.retained_bytes() > 0,
        "an earlier save cannot release this pending fact"
    );
    index.confirm_saved(7);
    assert_eq!(index.retained_bytes(), 0);
    Ok(())
}

#[test]
fn execution_index_budget_rejects_without_allocating_or_rewinding() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process.clone(), 0);
    let first = index.allocate("first", None, None)?;
    let second = index.allocate("second", None, None)?;
    assert_eq!((first, second), (1, 2));
    let retained = index.retained_bytes();
    process.store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
    let rejected = index.allocate("third", None, None).unwrap_err();
    assert!(
        rejected
            .to_string()
            .contains("process execution identity budget is full")
    );
    assert_eq!(index.retained_bytes(), retained);
    assert_eq!(index.assigned("third"), None);
    process.store(retained, Ordering::Release);
    assert_eq!(index.allocate("third", None, None)?, 3);
    Ok(())
}

#[test]
fn execution_index_materialize_budget_rejection_leaves_no_partial_identity_or_stamp() -> Result<()>
{
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process.clone(), 0);
    let first = index.reserve_observed("attempt", "observed")?;
    assert_eq!(first, 1);
    let retained = index.retained_bytes();
    let large = crate::ExecutionItem::new(
        "observed".into(),
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Borrowed("thread"),
            turn_id: std::borrow::Cow::Borrowed("turn"),
            ordinal: first,
            revision: 9,
            created_at: 10,
            updated_at: 20,
        },
        crate::ExecutionShape::Raw(crate::ThreadRawItem::stored(Vec::new(), "done", 20)),
    );
    process.store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
    let rejected = index
        .materialize_execution_batch([ExecutionMaterialization::from_item(&large)], u64::MAX)
        .unwrap_err();
    assert!(
        rejected
            .to_string()
            .contains("process execution identity budget is full")
    );
    assert_eq!(index.retained_bytes(), retained);
    assert_eq!(index.assigned("observed"), Some(first));
    process.store(retained, Ordering::Release);
    Ok(())
}

#[tokio::test]
async fn operation_output_reservation_returns_to_baseline_across_rounds() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "operation-budget";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store, test_thread(id)).await?;
    let channel = &sink.0.channel;
    let baseline = channel.process_bytes.load(Ordering::Acquire);
    for index in 0..32 {
        assert_eq!(
            channel.reserve_operation_output(&format!("idle-{index}"), 16 * 1024 * 1024,),
            Some(16 * 1024 * 1024)
        );
    }
    assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
    for index in 0..32 {
        channel.release_operation_output(&format!("idle-{index}"));
    }
    for round in 0..4_u64 {
        let operation = format!("task:call-{round}");
        assert_eq!(
            channel.reserve_operation_output(&operation, 4096),
            Some(4096)
        );
        assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
        channel.charge_operation_output(&operation, 1024)?;
        channel.charge_operation_output(&operation, 2048)?;
        assert!(channel.charge_operation_output(&operation, 4097).is_err());
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            baseline + 2048
        );
        channel.release_operation_output(&operation);
        channel.release_operation_output(&operation);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            baseline,
            "a finished call releases all accepted bytes exactly once"
        );
    }
    channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn rejected_terminal_transfer_retains_the_source_without_partial_charge() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "terminal-transfer-budget";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store, test_thread(id)).await?;
    let channel = &sink.0.channel;
    let lease = channel.step_lock.lock().await;
    sink.admit(id, visible_input_ticket(id, 1, "input")?)?;
    let source = PendingProjectionRetention {
        sequence: 1,
        prepared_bytes: 200,
    };
    channel.set_projection_retention(ProjectionRetention {
        resident_bytes: 100,
        pending: Some(source),
    })?;
    let transfer = ProjectionTransfer {
        source,
        after: ProjectionRetention {
            resident_bytes: 100,
            pending: Some(PendingProjectionRetention {
                sequence: 1,
                prepared_bytes: 120,
            }),
        },
    };
    let pressure_before = sink.pressure(id);
    let process_before = channel.process_bytes.load(Ordering::Acquire);
    channel
        .process_bytes
        .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
    assert!(channel.retain_terminal_bytes(1, transfer).is_err());
    assert_eq!(lock_progress(&sink.0).projection_pending, Some(source));
    assert_eq!(channel.retained_delivery_bytes(), 0);
    assert_eq!(sink.pressure(id).thread_bytes, pressure_before.thread_bytes);
    assert_eq!(
        channel.process_bytes.load(Ordering::Acquire),
        MAX_HISTORY_PROCESS_BYTES
    );
    channel
        .process_bytes
        .store(process_before, Ordering::Release);
    channel.release_projection_retention();
    drop(lease);
    channel.stop_and_join_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn full_process_budget_rejects_the_continuous_ticket_without_appending_it() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "admission-backpressure";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store, test_thread(id)).await?;
    let channel = &sink.0.channel;
    let lease = channel.step_lock.lock().await;
    channel
        .process_bytes
        .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
    let error = sink
        .admit(id, ticket(id, 1))
        .expect_err("full reliable budget is admission backpressure");
    assert!(
        error
            .source
            .is::<pl_core::thread::cold::StorageAdmissionBackpressure>()
    );
    let status = channel.subscribe().borrow().clone();
    assert_eq!(status.admitted_sequence, 0);
    assert_eq!(status.queued_records, 0);
    assert!(status.fault.is_none() && status.error.is_none());
    assert!(channel.next_unprojected().is_none());
    channel.process_bytes.store(0, Ordering::Release);
    drop(lease);
    channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn fault_generation_rejects_a_retry_for_the_previous_failure() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "fault-generation";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store, test_thread(id)).await?;
    let channel = &sink.0.channel;
    record_error(
        &sink.0,
        crate::HistoryFault::WriteFailed,
        FaultTarget::NextWrite,
        "first failure".into(),
        &["redacted_error"],
    );
    let first = channel.subscribe().borrow().fault_generation;
    record_error(
        &sink.0,
        crate::HistoryFault::WriteFailed,
        FaultTarget::NextWrite,
        "newer failure".into(),
        &["redacted_error"],
    );
    let second = channel.subscribe().borrow().fault_generation;
    assert!(second > first);
    assert!(channel.retry(first).is_err());
    assert_eq!(
        channel.subscribe().borrow().fault_generation,
        second,
        "a stale acknowledgement cannot resume the newer failure"
    );
    channel.stop_and_join_for_deletion().await?;
    Ok(())
}
