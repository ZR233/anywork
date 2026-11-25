use super::storage_fault_tests::{
    live_projection, register_test_thread, test_thread, visible_input_ticket,
};
use super::*;
use pl_core::thread::history_sink::HistorySink;

#[tokio::test]
async fn unprepared_head_stalls_despite_later_admissions_and_notifications() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "projection-watchdog";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id)).await?;
    let channel = sink.0.channel.clone();
    let lease = channel.step_lock.lock().await;
    channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW);
    assert!(channel.subscribe().borrow().fault.is_none());
    sink.admit(id, visible_input_ticket(id, 1, "first")?)?;
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
    assert_eq!(failed.fault, Some(crate::HistoryFault::NoProgress));
    assert_eq!(failed.committed_sequence, 0);
    assert_eq!(failed.queued_records, 4);
    assert_eq!(sink.pressure(id).thread_bytes, retained);

    let mut projection = live_projection(&sink).await?;
    let mut deferred_head = None;
    for sequence in 1..=4 {
        let write = lock_progress(&sink.0).effects[(sequence - 1) as usize]
            .write
            .clone();
        let prepared = projection.prepare_committed(&sink.0.thread, &write.effect, &write.state)?;
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
    channel.await_handoff_durable(id, 4).await?;
    assert_eq!(channel.subscribe().borrow().committed_sequence, 4);
    channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW);
    assert!(channel.subscribe().borrow().fault.is_none());

    let lease = channel.step_lock.lock().await;
    let fifth = visible_input_ticket(id, 5, "explicit-failure")?;
    sink.admit(id, fifth.clone())?;
    channel.fail_projection(5, "controlled projection failure".to_owned());
    let explicit = channel.subscribe().borrow().clone();
    channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW * 2);
    assert_eq!(*channel.subscribe().borrow(), explicit);
    let prepared = projection.prepare_committed(&sink.0.thread, &fifth.effect, &fifth.state)?;
    assert!(channel.prepare(prepared));
    drop(lease);
    store
        .thread_persistence()
        .retry_history(id, explicit.fault_generation)
        .await?;
    channel.await_handoff_durable(id, 5).await?;
    channel.stop_and_join().await?;
    Ok(())
}
