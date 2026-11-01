//! Fixed-cut baselines, bounded scoped replay and cancellation-safe single-consumer delivery.
#[path = "support/timeline.rs"]
mod support;

use std::sync::Arc;

use futures::FutureExt as _;
use pl_core::chat::*;
use support::*;

async fn subscribe(session: &Session, items: usize) -> ChatTail {
    session
        .subscribe_tail(query(), demand(items), Arc::new(Budget::default()))
        .await
        .unwrap()
}

async fn batch(tail: &mut ChatTail) -> ChatCompletedBatch {
    let ChatTailUpdate::Batch(batch) = tail.next().await.unwrap() else {
        panic!("open tail")
    };
    batch
}

fn assert_parked(tail: &mut ChatTail) {
    assert!(tail.next().now_or_never().is_none());
}

#[tokio::test]
async fn a_first_subscription_registers_before_baseline_and_covers_a_publish_during_capture() {
    let stored = Stored::with([record(1, "durable")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored);
    history.page_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let subscribing = {
        let session = session.clone();
        tokio::spawn(async move { subscribe(&session, 10).await })
    };
    gate.entered().await;
    assert!(session.has_subscribers());
    session
        .publish_batch(vec![draft("during", "during capture")])
        .await
        .unwrap();
    gate.release();
    let mut tail = subscribing.await.unwrap();
    let baseline = tail.initial().unwrap();
    assert_eq!(baseline.through_seq, 1);
    assert_eq!(sequences(&baseline.items), [1]);
    let next = batch(&mut tail).await;
    assert_eq!((next.from_seq, next.through_seq), (1, 2));
    assert_eq!(next.items[0].header.item_id, "during");
    assert_parked(&mut tail);
}

#[tokio::test]
async fn more_than_one_window_of_pending_completions_keeps_the_oldest_prefix() {
    for durable_count in [0, 7] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("run-1"));
        let mut tail = subscribe(&session, 23).await;
        tail.initial().unwrap();
        let records = session
            .publish_batch(
                (1..=150)
                    .map(|i| draft(&format!("pending-{i}"), "body"))
                    .collect(),
            )
            .await
            .unwrap();
        for record in records.iter().take(durable_count) {
            stored.insert((**record).clone());
        }
        session.confirm_durable(durable_count as u64).unwrap();
        let mut delivered = Vec::new();
        while delivered.len() < 150 {
            let next = batch(&mut tail).await;
            assert_eq!(next.from_seq, delivered.len() as u64);
            assert!(next.items.len() <= 23);
            delivered.extend(sequences(&next.items));
        }
        assert_eq!(delivered, (1..=150).collect::<Vec<_>>());
        assert_parked(&mut tail);
    }
}

#[tokio::test]
async fn a_cold_history_seeds_the_wake_head_and_parks_after_catch_up() {
    for after in [None, Some(0), Some(2)] {
        let session = Session::new(
            Stored::with((1..=5).map(|seq| record(seq, "body"))),
            epoch("run-1"),
        );
        let mut tail = match after {
            None => subscribe(&session, 10).await,
            Some(seq) => session
                .subscribe_after(
                    ChatCompletionCursor::new(epoch("run-1"), seq),
                    None,
                    demand(10),
                    Arc::new(Budget::default()),
                )
                .await
                .unwrap(),
        };
        let baseline = tail.initial().unwrap();
        assert_eq!(baseline.through_seq, after.unwrap_or(5));
        if let Some(after) = after {
            let next = batch(&mut tail).await;
            assert_eq!((next.from_seq, next.through_seq), (after, 5));
            assert_eq!(next.items[0].header.append_seq, after + 1);
        }
        assert_parked(&mut tail);
    }
}

#[tokio::test]
async fn a_baseline_does_not_mix_new_pending_across_a_committed_capture_gap() {
    let stored = Stored::with([record(1, "old")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let subscribing = {
        let session = session.clone();
        tokio::spawn(async move { subscribe(&session, 10).await })
    };
    gate.entered().await;
    publish_and_commit(&session, &stored, vec![draft("two", "2")]).await;
    session
        .publish_batch(vec![draft("three", "3")])
        .await
        .unwrap();
    gate.release();
    let mut tail = subscribing.await.unwrap();
    let baseline = tail.initial().unwrap();
    assert_eq!(baseline.through_seq, 1);
    assert_eq!(sequences(&baseline.items), [1]);
    assert_eq!(sequences(&batch(&mut tail).await.items), [2, 3]);
}

#[tokio::test]
async fn a_gap_in_unfiltered_stored_sequences_is_rejected_without_advancing() {
    let session = Session::new(
        Stored::with([record(1, "one"), record(3, "three")]),
        epoch("run-1"),
    );
    let mut tail = session
        .subscribe_after(
            ChatCompletionCursor::new(epoch("run-1"), 0),
            None,
            demand(10),
            Arc::new(Budget::default()),
        )
        .await
        .unwrap();
    tail.initial().unwrap();
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
}

#[tokio::test]
async fn an_empty_unfiltered_stored_range_below_known_head_is_a_gap_not_a_wait() {
    let stored = Stored::with([record(1, "one")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_after(
            ChatCompletionCursor::new(epoch("run-1"), 0),
            None,
            demand(10),
            Arc::new(Budget::default()),
        )
        .await
        .unwrap();
    tail.initial().unwrap();
    stored.remove(1);
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
}

#[tokio::test]
async fn the_first_frame_is_handed_over_once_and_next_requires_it() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let mut tail = subscribe(&session, 10).await;
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
    tail.initial().unwrap();
    assert!(matches!(tail.initial(), Err(ChatError::Conflict(_))));
}

#[tokio::test]
async fn batches_deliver_completions_from_the_delivered_position_and_ack_does_not_repeat() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    publish_and_commit(
        &session,
        &stored,
        vec![draft("a", "1"), draft("b", "2"), draft("c", "3")],
    )
    .await;
    let mut tail = subscribe(&session, 10).await;
    assert_eq!(tail.initial().unwrap().through_seq, 3);
    let records = session
        .publish_batch(vec![draft("d", "4"), draft("e", "5"), draft("f", "6")])
        .await
        .unwrap();
    let next = batch(&mut tail).await;
    assert_eq!((next.from_seq, next.through_seq), (3, 6));
    assert_eq!(sequences(&next.items), [4, 5, 6]);
    for record in records.iter() {
        stored.insert((**record).clone());
    }
    session.confirm_durable(6).unwrap();
    assert_parked(&mut tail);
}

#[tokio::test]
async fn a_lagging_subscription_is_refilled_from_storage_without_skipping_to_head() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = subscribe(&session, 100).await;
    assert!(tail.initial().unwrap().items.is_empty());
    publish_and_commit(
        &session,
        &stored,
        (1..=150)
            .map(|seq| draft(&format!("item-{seq}"), "row"))
            .collect(),
    )
    .await;
    let first = batch(&mut tail).await;
    assert_eq!((first.from_seq, first.through_seq), (0, 100));
    let second = batch(&mut tail).await;
    assert_eq!((second.from_seq, second.through_seq), (100, 150));
    assert_eq!(
        [sequences(&first.items), sequences(&second.items)].concat(),
        (1..=150).collect::<Vec<_>>()
    );
    assert_eq!(stored.reads.afters.lock().unwrap().len(), 2);
    assert!(
        stored
            .reads
            .afters
            .lock()
            .unwrap()
            .iter()
            .all(|request| request.demand.max_items == 100)
    );
    assert_parked(&mut tail);
}

#[tokio::test]
async fn a_byte_truncated_deferred_batch_continues_where_it_stopped() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail(
            query(),
            ReadDemand::new(12, 500),
            Arc::new(Budget::default()),
        )
        .await
        .unwrap();
    tail.initial().unwrap();
    session
        .publish_batch(
            (1..=12)
                .map(|seq| draft(&format!("item-{seq}"), &"x".repeat(300 * 1024)))
                .collect(),
        )
        .await
        .unwrap();
    let mut delivered = Vec::new();
    let mut through = 0;
    while delivered.len() < 12 {
        let next = batch(&mut tail).await;
        assert_eq!(next.from_seq, through);
        assert!(next.items.len() < 12);
        assert!(
            next.items
                .iter()
                .all(|item| matches!(item.payload, PayloadData::Deferred { .. }))
        );
        through = next.through_seq;
        delivered.extend(sequences(&next.items));
    }
    assert_eq!(delivered, (1..=12).collect::<Vec<_>>());
    assert_eq!(through, 12);
    assert_parked(&mut tail);
}

#[tokio::test]
async fn a_cancelled_next_during_io_retains_the_original_delivery_cut_and_pending_arcs() {
    let stored = Stored::with([record(1, "one")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.after_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("two", "two")])
        .await
        .unwrap();
    let mut tail = session
        .subscribe_after(
            ChatCompletionCursor::new(epoch("run-1"), 0),
            None,
            demand(10),
            Arc::new(Budget::default()),
        )
        .await
        .unwrap();
    tail.initial().unwrap();
    {
        let mut next = Box::pin(tail.next());
        tokio::select! { () = gate.entered() => {}, result = &mut next => panic!("unexpected completion: {result:?}") }
    }
    stored.insert((*records[0]).clone());
    session.confirm_durable(2).unwrap();
    session
        .publish_batch(vec![draft("three", "three")])
        .await
        .unwrap();
    gate.release();
    let next = batch(&mut tail).await;
    assert_eq!((next.from_seq, next.through_seq), (0, 3));
    assert_eq!(sequences(&next.items), [1, 2, 3]);
    assert_parked(&mut tail);
}

#[tokio::test]
async fn closing_the_subscription_cancels_demand_and_further_reads() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = subscribe(&session, 10).await;
    tail.initial().unwrap();
    assert!(session.has_subscribers());
    assert_parked(&mut tail);
    tail.close();
    assert!(!session.has_subscribers());
    assert!(matches!(tail.next().await, Err(ChatError::Cancelled)));
    assert!(matches!(tail.initial(), Err(ChatError::Cancelled)));
    publish_and_commit(&session, &stored, vec![draft("a", "1")]).await;
    assert_eq!(
        session
            .page(latest(10), &Budget::default())
            .await
            .unwrap()
            .items
            .len(),
        1
    );
}

#[tokio::test]
async fn a_resumed_subscription_refills_from_its_own_position_without_skipping() {
    let stored = Stored::with((1..=150).map(|seq| record(seq, "row")));
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_after(
            ChatCompletionCursor::new(epoch("run-1"), 20),
            None,
            demand(100),
            Arc::new(Budget::default()),
        )
        .await
        .unwrap();
    let baseline = tail.initial().unwrap();
    assert!(baseline.items.is_empty());
    assert!(baseline.before.is_none());
    assert_eq!(baseline.through_seq, 20);
    let first = batch(&mut tail).await;
    let second = batch(&mut tail).await;
    assert_eq!((first.from_seq, first.through_seq), (20, 120));
    assert_eq!((second.from_seq, second.through_seq), (120, 150));
    assert_eq!(
        [sequences(&first.items), sequences(&second.items)].concat(),
        (21..=150).collect::<Vec<_>>()
    );
    assert!(
        stored.reads.pages.lock().unwrap().is_empty(),
        "resume never substitutes latest()"
    );
    assert_parked(&mut tail);
}

#[tokio::test]
async fn a_resumed_subscription_at_head_delivers_only_new_completions() {
    let session = Session::new(
        Stored::with((1..=3).map(|seq| record(seq, "row"))),
        epoch("run-1"),
    );
    let mut tail = session
        .subscribe_after(
            ChatCompletionCursor::new(epoch("run-1"), 3),
            None,
            demand(10),
            Arc::new(Budget::default()),
        )
        .await
        .unwrap();
    tail.initial().unwrap();
    assert_parked(&mut tail);
    session
        .publish_batch(vec![draft("four", "4"), draft("five", "5")])
        .await
        .unwrap();
    let next = batch(&mut tail).await;
    assert_eq!((next.from_seq, next.through_seq), (3, 5));
    assert_eq!(sequences(&next.items), [4, 5]);
}

#[tokio::test]
async fn a_resume_position_beyond_head_is_rejected() {
    let session = Session::new(Stored::with([record(1, "one")]), epoch("run-1"));
    assert!(matches!(
        session
            .subscribe_after(
                ChatCompletionCursor::new(epoch("run-1"), 99),
                None,
                demand(10),
                Arc::new(Budget::default())
            )
            .await,
        Err(ChatError::InvalidArgument(_))
    ));
    assert!(!session.has_subscribers());
}

#[tokio::test]
async fn a_resume_from_another_epoch_is_rejected() {
    let session = Session::new(Stored::with([record(1, "one")]), epoch("run-2"));
    assert!(matches!(
        session
            .subscribe_after(
                ChatCompletionCursor::new(epoch("run-1"), 1),
                None,
                demand(10),
                Arc::new(Budget::default())
            )
            .await,
        Err(ChatError::EpochMismatch { .. })
    ));
}

#[tokio::test]
async fn scope_gaps_advance_private_cut_without_empty_append_or_mixing_other_scopes() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = subscribe(&session, 10).await;
    tail.initial().unwrap();
    let mut hidden = draft("hidden", "activity");
    hidden.query_class = "activity".into();
    publish_and_commit(&session, &stored, vec![hidden.clone()]).await;
    assert_parked(&mut tail);
    hidden.item_id = "hidden-2".into();
    session
        .publish_batch(vec![draft("main", "visible"), hidden])
        .await
        .unwrap();
    let next = batch(&mut tail).await;
    assert_eq!((next.from_seq, next.through_seq), (1, 3));
    assert_eq!(sequences(&next.items), [2]);
    assert_parked(&mut tail);
}

#[tokio::test]
async fn replay_captures_pending_before_history_io_and_never_chases_the_head_after_clear() {
    let stored = Stored::with([record(1, "one")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.after_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("two", "two")])
        .await
        .unwrap();
    let replay = {
        let session = session.clone();
        tokio::spawn(async move {
            session
                .completed_after(
                    ChatCompletionCursor::new(epoch("run-1"), 0),
                    None,
                    Some(2),
                    demand(10),
                    &Budget::default(),
                )
                .await
        })
    };
    gate.entered().await;
    stored.insert((*records[0]).clone());
    session.confirm_durable(2).unwrap();
    session
        .publish_batch(vec![draft("three", "three")])
        .await
        .unwrap();
    gate.release();
    let next = replay.await.unwrap().unwrap();
    assert_eq!((next.from_seq, next.through_seq), (0, 2));
    assert_eq!(sequences(&next.items), [1, 2]);
    assert_eq!(stored.reads.afters.lock().unwrap()[0].ceiling, 1);
    let PayloadData::Inline(bytes) = &next.items[1].payload else {
        panic!("inline")
    };
    assert!(Arc::ptr_eq(bytes, &records[0].payload));
}
