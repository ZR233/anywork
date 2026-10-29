//! 完成批次订阅契约：一致基线、连续补发与单消费者生命周期。
//!
//! 订阅先登记唤醒再捕获基线，因此建基线期间发布的完成事实不丢；补发从实际交付位置继续，落后时
//! 由存储回填而不跳到 head；预算截断的批次停在真实交付的最后一条上；保存确认不唤醒订阅。

#[path = "support/timeline.rs"]
mod support;

use std::{sync::Arc, time::Duration};

use pl_core::chat::{ChatError, ChatTailUpdate, Session, TimelineEpoch};
use support::{
    BoundedReads, GatedHistory, HistoryGate, Stored, draft, epoch, publish_and_commit, take_initial,
};

#[tokio::test]
async fn a_first_subscription_registers_before_the_baseline_and_covers_a_publish_during_capture() {
    let history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    let gated = {
        let mut gated = history;
        gated.page_gate = Some(gate.clone());
        gated
    };
    let session = Session::new(gated, epoch("run-1"));
    let subscribing_session = session.clone();
    let subscribing = tokio::spawn(async move { subscribing_session.subscribe_tail().await });
    gate.entered().await;
    // The completion lands while the baseline's storage read is held open.
    session
        .publish_batch(vec![draft("a", "during the baseline")])
        .await
        .expect("the completion is admitted");
    gate.release();
    let mut tail = subscribing
        .await
        .expect("the subscription finishes")
        .expect("the baseline is readable");
    assert!(session.has_subscribers(), "the open tail declares demand");
    let baseline = take_initial(&mut tail);
    assert!(
        baseline.items.is_empty(),
        "the baseline stays at its captured head"
    );
    assert_eq!(baseline.completed_cursor, None);
    let ChatTailUpdate::Batch(batch) = tail.next().await.unwrap() else {
        panic!("the publication after capture belongs to the next batch");
    };
    assert_eq!(batch.from_seq, 0);
    assert_eq!(batch.through_seq, 1);
    assert_eq!(batch.items[0].item_id, "a");
    // With that publication delivered, the next read parks.
    let parked = tokio::time::timeout(Duration::from_millis(50), tail.next()).await;
    assert!(
        parked.is_err(),
        "no completion is invented after the baseline"
    );
    tail.close();
}

#[tokio::test]
async fn more_than_one_window_of_pending_completions_keeps_the_oldest_prefix() {
    for durable_count in [0, 7] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("run-1"));
        let mut tail = session.subscribe_tail().await.unwrap();
        take_initial(&mut tail);
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
        if durable_count > 0 {
            session.confirm_durable(durable_count as u64).unwrap();
        }
        let mut sequences = Vec::new();
        while sequences.len() < 150 {
            let ChatTailUpdate::Batch(batch) = tail.next().await.unwrap() else {
                panic!("the subscription must remain open");
            };
            assert_eq!(batch.from_seq, sequences.len() as u64);
            sequences.extend(batch.items.iter().map(|item| item.append_seq));
        }
        assert_eq!(sequences, (1..=150).collect::<Vec<u64>>());
    }
}

#[tokio::test]
async fn a_cold_history_seeds_the_wake_head_and_parks_after_catch_up() {
    for after in [None, Some(0), Some(2)] {
        let stored = Stored::with((1..=5).map(|i| support::record(i, "body")));
        let session = Session::new(stored, epoch("run-1"));
        let mut tail = match after {
            None => session.subscribe_tail().await.unwrap(),
            Some(seq) => session
                .subscribe_after(pl_core::chat::ChatCompletionCursor::new(
                    epoch("run-1"),
                    seq,
                ))
                .await
                .unwrap(),
        };
        take_initial(&mut tail);
        if let Some(after) = after {
            let ChatTailUpdate::Batch(batch) = tail.next().await.unwrap() else {
                panic!("cold durable history must catch up immediately");
            };
            assert_eq!(batch.from_seq, after);
            assert_eq!(batch.through_seq, 5);
            assert_eq!(batch.items[0].append_seq, after + 1);
        }
        assert!(
            tokio::time::timeout(Duration::from_millis(20), tail.next())
                .await
                .is_err()
        );
    }
}

#[tokio::test]
async fn a_baseline_does_not_mix_a_new_pending_record_across_a_committed_capture_gap() {
    let stored = Stored::default();
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let subscribing = {
        let session = session.clone();
        tokio::spawn(async move { session.subscribe_tail().await })
    };
    gate.entered().await;
    let first = session
        .publish_batch(vec![draft("one", "1")])
        .await
        .unwrap();
    stored.insert((*first[0]).clone());
    session.confirm_durable(1).unwrap();
    session
        .publish_batch(vec![draft("two", "2")])
        .await
        .unwrap();
    gate.release();
    let mut tail = subscribing.await.unwrap().unwrap();
    let baseline = take_initial(&mut tail);
    assert!(baseline.items.is_empty());
    assert_eq!(baseline.completed_cursor, None);
    let ChatTailUpdate::Batch(batch) = tail.next().await.unwrap() else {
        panic!("both completions must be caught up from the captured head");
    };
    assert_eq!(
        batch
            .items
            .iter()
            .map(|item| item.append_seq)
            .collect::<Vec<_>>(),
        [1, 2]
    );
}

#[tokio::test]
async fn a_gap_in_stored_completion_sequences_is_rejected_without_advancing() {
    let stored = Stored::with([support::record(1, "one"), support::record(3, "three")]);
    let session = Session::new(stored, epoch("run-1"));
    let mut tail = session
        .subscribe_after(pl_core::chat::ChatCompletionCursor::new(epoch("run-1"), 0))
        .await
        .unwrap();
    take_initial(&mut tail);
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
}

#[tokio::test]
async fn an_empty_stored_range_below_a_known_head_is_a_gap_not_a_wait() {
    let stored = Stored::with([support::record(1, "one")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_after(pl_core::chat::ChatCompletionCursor::new(epoch("run-1"), 0))
        .await
        .unwrap();
    take_initial(&mut tail);
    stored.remove(1);
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
    assert!(matches!(tail.next().await, Err(ChatError::Conflict(_))));
}

#[tokio::test]
async fn the_first_frame_is_handed_over_once_and_next_requires_it() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("the baseline is readable");
    let error = tail
        .next()
        .await
        .expect_err("the first frame must be taken before awaiting updates");
    assert!(matches!(error, ChatError::Conflict(_)));
    take_initial(&mut tail);
    let error = tail
        .initial()
        .expect_err("the first frame is a single hand-off");
    assert!(matches!(error, ChatError::Conflict(_)));
}

#[tokio::test]
async fn batches_deliver_consecutive_completions_from_the_delivered_position() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    publish_and_commit(
        &session,
        &stored,
        vec![draft("a", "1"), draft("b", "2"), draft("c", "3")],
    )
    .await;
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("the baseline is readable");
    let baseline = take_initial(&mut tail);
    assert_eq!(baseline.items.len(), 3);
    assert_eq!(baseline.completed_cursor.expect("cursor").append_seq, 3);

    publish_and_commit(
        &session,
        &stored,
        vec![draft("d", "4"), draft("e", "5"), draft("f", "6")],
    )
    .await;
    let batch = match tail.next().await.expect("the batch is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(batch.from_seq, 3, "the batch continues the baseline cursor");
    assert_eq!(batch.through_seq, 6);
    let sequences: Vec<u64> = batch.items.iter().map(|item| item.append_seq).collect();
    assert_eq!(sequences, [4, 5, 6], "the batch is ascending and gap-free");
    // With everything delivered, the next read parks instead of inventing a frame.
    let parked = tokio::time::timeout(Duration::from_millis(50), tail.next()).await;
    assert!(parked.is_err());
    tail.close();
}

#[tokio::test]
async fn a_lagging_subscription_is_refilled_from_storage_without_skipping_to_head() {
    let stored = Stored::default();
    let bounded = BoundedReads::new(stored.clone());
    let session = Session::new(bounded.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("the baseline is readable");
    assert!(take_initial(&mut tail).is_empty(), "history starts empty");

    let drafts: Vec<_> = (1..=150)
        .map(|seq| draft(&format!("item-{seq}"), "row"))
        .collect();
    publish_and_commit(&session, &stored, drafts).await;

    // The delivered position is far below the durable prefix: the refill must come from storage in
    // bounded windows, covering every sequence exactly once instead of jumping to the head.
    let first = match tail.next().await.expect("the first refill is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(first.from_seq, 0);
    assert_eq!(first.items.len(), 100, "the item cap bounds one batch");
    assert_eq!(first.through_seq, 100);
    assert_eq!(first.items.first().expect("non-empty").append_seq, 1);

    let second = match tail.next().await.expect("the second refill is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(second.from_seq, 100, "the second batch continues exactly");
    assert_eq!(second.through_seq, 150);
    assert_eq!(second.items.len(), 50);
    let mut delivered: Vec<u64> = first
        .items
        .iter()
        .chain(second.items.iter())
        .map(|item| item.append_seq)
        .collect();
    delivered.sort_unstable();
    let expected: Vec<u64> = (1..=150).collect();
    assert_eq!(
        delivered, expected,
        "every completion arrives once, none skipped"
    );
    assert!(
        *bounded.largest_after.lock().unwrap() <= 100,
        "the catch-up read stays bounded"
    );
    let parked = tokio::time::timeout(Duration::from_millis(50), tail.next()).await;
    assert!(parked.is_err(), "the refill ends at the head");
    tail.close();
}

#[tokio::test]
async fn a_budget_truncated_batch_continues_where_it_stopped() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("the baseline is readable");
    assert!(take_initial(&mut tail).is_empty());
    let drafts: Vec<_> = (1..=12)
        .map(|seq| draft(&format!("item-{seq}"), &"x".repeat(300 * 1024)))
        .collect();
    session
        .publish_batch(drafts)
        .await
        .expect("the large completions are admitted");

    let first = match tail.next().await.expect("a first batch is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert!(
        first.items.len() < 12,
        "the page budget splits the window before the item cap"
    );
    assert!(
        first.through_seq < 12,
        "through names the last delivered record"
    );

    let mut delivered: Vec<u64> = first.items.iter().map(|item| item.append_seq).collect();
    let mut through = first.through_seq;
    while delivered.len() < 12 {
        let next = match tail.next().await.expect("the continuation is delivered") {
            ChatTailUpdate::Batch(batch) => batch,
            other => panic!("expected a completion batch, got {other:?}"),
        };
        assert_eq!(
            next.from_seq, through,
            "each batch continues the previous one"
        );
        through = next.through_seq;
        delivered.extend(next.items.iter().map(|item| item.append_seq));
    }
    delivered.sort_unstable();
    let expected: Vec<u64> = (1..=12).collect();
    assert_eq!(delivered, expected, "the budget cut loses no completion");
    assert_eq!(through, 12);
    tail.close();
}

#[tokio::test]
async fn a_cancelled_next_future_leaves_the_subscription_usable() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("the baseline is readable");
    take_initial(&mut tail);
    // A caller cancels the parked read; nothing is delivered by the cancelled future.
    let parked = tokio::time::timeout(Duration::from_millis(20), tail.next()).await;
    assert!(parked.is_err(), "there is nothing to deliver yet");
    publish_and_commit(&session, &stored, vec![draft("a", "1")]).await;
    let batch = match tail.next().await.expect("the batch is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(batch.through_seq, 1);
    assert_eq!(batch.items.len(), 1);
    tail.close();
}

#[tokio::test]
async fn closing_the_subscription_cancels_demand_and_further_reads() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("the baseline is readable");
    take_initial(&mut tail);
    assert!(session.has_subscribers());
    tail.close();
    assert!(
        !session.has_subscribers(),
        "a closed tail declares no demand"
    );
    let error = tail
        .next()
        .await
        .expect_err("a closed subscription refuses further reads");
    assert!(matches!(error, ChatError::Cancelled));
    let error = tail
        .initial()
        .expect_err("a closed subscription hands out no first frame");
    assert!(matches!(error, ChatError::Cancelled));
    // Closing one subscription stops neither the producer nor page reads.
    publish_and_commit(&session, &stored, vec![draft("a", "1")]).await;
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest())
        .await
        .expect("pages do not hang on the tail lifecycle");
    assert_eq!(page.items.len(), 1);
}

#[tokio::test]
async fn a_resumed_subscription_refills_from_its_own_position_without_skipping() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let drafts: Vec<_> = (1..=150)
        .map(|seq| draft(&format!("item-{seq}"), "row"))
        .collect();
    publish_and_commit(&session, &stored, drafts).await;
    let after = pl_core::chat::ChatCompletionCursor::new(TimelineEpoch::new("run-1").unwrap(), 20);
    let mut tail = session
        .subscribe_after(after.clone())
        .await
        .expect("the resume is accepted");

    // The first frame is the placeholder echo of the resume position, never the latest page.
    let placeholder = take_initial(&mut tail);
    assert!(
        placeholder.items.is_empty(),
        "no latest page is substituted"
    );
    assert_eq!(placeholder.before, None);
    assert!(!placeholder.has_older);
    assert_eq!(placeholder.completed_cursor, Some(after));
    assert_eq!(placeholder.epoch, epoch("run-1"));

    let first = match tail.next().await.expect("the first refill is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(
        first.from_seq, 20,
        "the refill starts at the resume position"
    );
    assert_eq!(first.items.first().expect("non-empty").append_seq, 21);
    assert_eq!(first.through_seq, 120, "the item cap bounds one batch");
    let second = match tail.next().await.expect("the second refill is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(second.from_seq, 120);
    assert_eq!(
        second.through_seq, 150,
        "the refill ends at the head, not past it"
    );
    let delivered: Vec<u64> = first
        .items
        .iter()
        .chain(second.items.iter())
        .map(|item| item.append_seq)
        .collect();
    let expected: Vec<u64> = (21..=150).collect();
    assert_eq!(delivered, expected, "the refill is complete and gap-free");
    let parked = tokio::time::timeout(Duration::from_millis(50), tail.next()).await;
    assert!(parked.is_err(), "nothing is invented past the head");
    tail.close();
}

#[tokio::test]
async fn a_resumed_subscription_at_the_head_delivers_only_new_completions() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    publish_and_commit(
        &session,
        &stored,
        vec![draft("a", "1"), draft("b", "2"), draft("c", "3")],
    )
    .await;
    let head_cursor =
        pl_core::chat::ChatCompletionCursor::new(TimelineEpoch::new("run-1").unwrap(), 3);
    let mut tail = session
        .subscribe_after(head_cursor)
        .await
        .expect("resuming at the head is legal");
    take_initial(&mut tail);
    // The writer is paused: the new completions stay pending, and the resumed tail still delivers
    // them from its own position instead of waiting for durability.
    session
        .publish_batch(vec![draft("item-4", "4"), draft("item-5", "5")])
        .await
        .expect("the completions are admitted");
    let batch = match tail.next().await.expect("the batch is delivered") {
        ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(batch.from_seq, 3);
    assert_eq!(batch.through_seq, 5);
    assert_eq!(batch.items.len(), 2);
    tail.close();
}

#[tokio::test]
async fn a_resume_position_beyond_the_head_is_rejected() {
    let stored = Stored::with([support::record(1, "one")]);
    let session = Session::new(stored, epoch("run-1"));
    let beyond = pl_core::chat::ChatCompletionCursor::new(TimelineEpoch::new("run-1").unwrap(), 99);
    let error = session
        .subscribe_after(beyond)
        .await
        .expect_err("a position this run never published cannot be resumed");
    assert!(matches!(error, ChatError::InvalidArgument(_)));
}

#[tokio::test]
async fn a_resume_from_another_epoch_is_rejected() {
    let stored = Stored::with([support::record(1, "one")]);
    let session = Session::new(stored, epoch("run-2"));
    let stale = pl_core::chat::ChatCompletionCursor::new(TimelineEpoch::new("run-1").unwrap(), 1);
    let error = session
        .subscribe_after(stale)
        .await
        .expect_err("a cursor from the previous run generation is rejected");
    assert!(matches!(error, ChatError::EpochMismatch { .. }));
}
