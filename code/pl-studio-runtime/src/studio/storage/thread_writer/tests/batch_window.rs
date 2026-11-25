use super::storage_fault_tests::{Fixture, ready, ticket};
use super::*;
use pl_core::thread::history_sink::HistorySink;

#[tokio::test]
async fn continuous_arrival_keeps_the_original_deadline_and_retry_boundary() -> Result<()> {
    let mut fixture = Fixture::new("batch-deadline").await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let now = Instant::now();
    let first = fixture.handoff(&ticket("batch-deadline", 1)).await?;
    lock_progress(&fixture.sink.0)
        .effects
        .front_mut()
        .unwrap()
        .admitted_at = now;
    assert!(
        matches!(fixture.select(now), batch::Selection::Wait(deadline)
            if deadline == now + Duration::from_millis(20))
    );
    fixture.handoff(&ticket("batch-deadline", 2)).await?;
    assert!(
        matches!(fixture.select(now + Duration::from_millis(19)), batch::Selection::Wait(deadline)
            if deadline == now + Duration::from_millis(20))
    );
    fixture.handoff(&ticket("batch-deadline", 3)).await?;
    let selected = ready(fixture.select(now + Duration::from_millis(20)));
    assert_eq!(
        selected
            .iter()
            .map(|effect| effect.sequence)
            .collect::<Vec<_>>(),
        [1, 2, 3]
    );
    assert!(Arc::ptr_eq(&selected[0].prepared, &first));
    fixture.handoff(&ticket("batch-deadline", 4)).await?;
    let retried = ready(fixture.select(now + Duration::from_secs(1)));
    assert_eq!(
        retried.len(),
        3,
        "later admission must not widen a frozen transaction"
    );
    for (original, retry) in selected.iter().zip(&retried) {
        assert!(Arc::ptr_eq(&original.write, &retry.write));
        assert!(Arc::ptr_eq(&original.prepared, &retry.prepared));
    }
    drop(gate);
    fixture.finish(4).await
}

#[tokio::test]
async fn barriers_pressure_and_prepared_gaps_end_the_window() -> Result<()> {
    for mode in ["flush", "handoff-barrier", "pressure", "queue-full", "gap"] {
        let mut fixture = Fixture::new(&format!("batch-cut-{mode}")).await?;
        let id = fixture.sink.0.thread.id.clone();
        let channel = fixture.sink.0.channel.clone();
        let gate = channel.step_lock.lock().await;
        fixture.handoff(&ticket(&id, 1)).await?;
        let now = lock_progress(&fixture.sink.0)
            .effects
            .front()
            .unwrap()
            .admitted_at;
        assert!(matches!(fixture.select(now), batch::Selection::Wait(_)));
        match mode {
            "flush" => {
                channel.request_flush(1);
            }
            "handoff-barrier" => {
                let barrier = channel.await_handoff_durable(&id, 1);
                tokio::pin!(barrier);
                assert!(futures::poll!(&mut barrier).is_pending());
            }
            "pressure" => lock_progress(&fixture.sink.0).pressure_paused = true,
            "queue-full" => {
                lock_progress(&fixture.sink.0).fault = Some(crate::HistoryFault::QueueFull)
            }
            "gap" => fixture.sink.admit(&id, ticket(&id, 2))?,
            _ => unreachable!(),
        }
        let selected = ready(fixture.select(now));
        assert_eq!(selected.len(), 1, "{mode}");
        drop(gate);
        channel.await_handoff_durable(&id, 1).await?;
        if mode == "gap" {
            assert_eq!(lock_progress(&fixture.sink.0).durable, 1);
            fixture.handoff(&ticket(&id, 2)).await?;
            fixture.finish(2).await?;
        } else {
            fixture.finish(1).await?;
        }
    }
    Ok(())
}

#[tokio::test]
async fn count_and_encoded_byte_limits_cut_a_batch_without_starving_large_effects() -> Result<()> {
    let mut fixture = Fixture::new("batch-count").await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let now = Instant::now();
    for sequence in 1..=64 {
        fixture.handoff(&ticket("batch-count", sequence)).await?;
        if sequence == 63 {
            assert!(matches!(fixture.select(now), batch::Selection::Wait(_)));
        }
    }
    assert_eq!(ready(fixture.select(now)).len(), 64);
    drop(gate);
    fixture.finish(64).await?;

    let mut fixture = Fixture::new("batch-large").await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let mut large = (*ticket("batch-large", 1)).clone();
    let extension = pl_core::thread::extensions::ExtensionRecord {
        revision: 1,
        payload: pl_core::context::OpaquePayload::text("large".repeat(256 * 1024)),
    };
    large
        .state
        .extensions
        .insert("test.large".into(), extension.clone());
    Arc::make_mut(&mut large.effect).extensions =
        Arc::from([pl_core::thread::extensions::ExtensionChange::Put {
            id: "test.large".into(),
            record: extension,
        }]);
    fixture.handoff(&Arc::new(large)).await?;
    let now = lock_progress(&fixture.sink.0)
        .effects
        .front()
        .unwrap()
        .admitted_at;
    assert!(
        lock_progress(&fixture.sink.0)
            .effects
            .front()
            .unwrap()
            .bytes
            > 1024 * 1024
    );
    assert_eq!(ready(fixture.select(now)).len(), 1);
    fixture.handoff(&ticket("batch-large", 2)).await?;
    assert_eq!(ready(fixture.select(now)).len(), 1);
    drop(gate);
    fixture.finish(2).await
}
