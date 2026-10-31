//! 发布准入契约：完成顺序、整批原子性、身份幂等与冲突、pending 生命周期。
//!
//! 这些测试针对 [`Session::publish_batch`] 与 [`Session::confirm_durable`] 的完成集合规则：
//! 序号按发布（完成）分配而不是按启动；同身份同载荷幂等且不重复序号，异载荷是类型化冲突，
//! 已持久身份同样按此规则检查；pending 只在连续前缀真实提交后回收，保存确认不发内容事件。

#[path = "support/timeline.rs"]
mod support;

use std::sync::Arc;

use pl_core::chat::{ChatError, Session};
use support::{
    GatedHistory, HistoryGate, Stored, draft, epoch, publish_and_commit, record_identified, visible,
};

#[tokio::test]
async fn a_stale_identity_read_cannot_republish_a_concurrently_committed_record() {
    let stored = Stored::default();
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.captured_item_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let delayed = {
        let session = session.clone();
        tokio::spawn(async move { session.publish_batch(vec![draft("same", "body")]).await })
    };
    gate.entered().await;
    let committed = session
        .publish_batch(vec![draft("same", "body")])
        .await
        .unwrap();
    stored.insert((*committed[0]).clone());
    session.confirm_durable(committed[0].append_seq).unwrap();
    gate.release();
    let repeated = tokio::time::timeout(std::time::Duration::from_secs(2), delayed)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(repeated, committed);
    assert_eq!(session.head_seq(), 1);
    assert_eq!(visible(&session, 10).await.len(), 1);
}

#[tokio::test]
async fn completion_order_follows_publication_not_start() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    // Tool A started first but finishes after B; B's completion is published first and must not be
    // pushed behind a later, earlier-started record.
    let second = session
        .publish_batch(vec![draft("tool-b", "B finished first")])
        .await
        .expect("B's completion is admitted");
    let first = session
        .publish_batch(vec![draft("tool-a", "A finished later")])
        .await
        .expect("A's completion is admitted");
    assert_eq!(second[0].append_seq, 1, "the first publication gets seq 1");
    assert_eq!(first[0].append_seq, 2, "the later completion follows it");
    let page = visible(&session, 10).await;
    let ids: Vec<&str> = page.iter().map(|item| item.item_id.as_str()).collect();
    assert_eq!(ids, ["tool-b", "tool-a"], "order is completion order");
}

#[tokio::test]
async fn a_batch_gets_consecutive_sequences_and_becomes_visible_at_once() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("a", "1"), draft("b", "2"), draft("c", "3")])
        .await
        .expect("the batch is admitted");
    let sequences: Vec<u64> = records.iter().map(|item| item.append_seq).collect();
    assert_eq!(sequences, [1, 2, 3], "one batch, consecutive sequences");
    let page = visible(&session, 10).await;
    assert_eq!(page.len(), 3, "the whole batch is queryable immediately");
}

#[tokio::test]
async fn a_zero_item_batch_publishes_an_empty_frozen_result() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let records = session
        .publish_batch(Vec::new())
        .await
        .expect("an effect may produce zero completions");
    assert!(records.is_empty());
    assert_eq!(session.head_seq(), 0, "no sequence is consumed");
}

#[tokio::test]
async fn republishing_the_same_payload_is_idempotent_without_a_new_sequence() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let first = session
        .publish_batch(vec![draft("x", "sealed body")])
        .await
        .expect("the first publication is admitted");
    // A duplicate inside one batch collapses to one completion.
    let batch = session
        .publish_batch(vec![draft("x", "sealed body"), draft("x", "sealed body")])
        .await
        .expect("an identical republish is idempotent");
    assert_eq!(batch.len(), 1, "intra-batch duplicates collapse");
    // And a later republish returns the very same frozen record, without a second sequence.
    let second = session
        .publish_batch(vec![draft("x", "sealed body")])
        .await
        .expect("an identical republish is idempotent");
    assert_eq!(second[0].append_seq, 1, "the original sequence is reused");
    assert!(
        Arc::ptr_eq(&second[0], &first[0]),
        "the writer receives the same frozen record pending keeps"
    );
    assert_eq!(session.head_seq(), 1, "idempotency consumes no sequence");
    let page = visible(&session, 10).await;
    assert_eq!(page.len(), 1, "the identity appears exactly once");
}

#[tokio::test]
async fn the_same_identity_with_a_different_payload_conflicts_and_publishes_nothing() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    session
        .publish_batch(vec![draft("x", "sealed body")])
        .await
        .expect("the first publication is admitted");
    let error = session
        .publish_batch(vec![draft("x", "a different body")])
        .await
        .expect_err("a different payload at one identity is a contract error");
    assert!(matches!(error, ChatError::Conflict(id) if id == "x"));
    // A conflicting pair inside one batch fails before anything becomes visible.
    let error = session
        .publish_batch(vec![draft("y", "one"), draft("y", "two")])
        .await
        .expect_err("intra-batch divergence fails the whole batch");
    assert!(matches!(error, ChatError::Conflict(id) if id == "y"));
    assert_eq!(
        session.head_seq(),
        1,
        "no sequence is consumed by conflicts"
    );
    let page = visible(&session, 10).await;
    assert_eq!(page.len(), 1, "only the sealed record is visible");
}

#[tokio::test]
async fn a_persisted_identity_republishes_idempotently_by_payload() {
    let stored = Stored::with([record_identified("x", 7, "already durable")]);
    let session = Session::new(stored.clone(), epoch("run-2"));
    let records = session
        .publish_batch(vec![draft("x", "already durable")])
        .await
        .expect("a persisted identity with the same payload is idempotent");
    assert_eq!(records[0].append_seq, 7, "the persisted sequence is reused");
    assert_eq!(session.head_seq(), 7, "no new sequence is allocated");
    assert_eq!(stored.len(), 1, "nothing is written twice");
}

#[tokio::test]
async fn a_persisted_identity_with_a_different_payload_conflicts() {
    let stored = Stored::with([record_identified("x", 7, "already durable")]);
    let session = Session::new(stored, epoch("run-2"));
    let error = session
        .publish_batch(vec![draft("x", "a divergent body")])
        .await
        .expect_err("a divergent payload at a persisted identity is rejected");
    assert!(matches!(error, ChatError::Conflict(id) if id == "x"));
}

#[tokio::test]
async fn an_empty_identity_is_rejected() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let error = session
        .publish_batch(vec![draft("", "body")])
        .await
        .expect_err("an empty identity is not a valid completion");
    assert!(matches!(error, ChatError::InvalidArgument(_)));
    assert_eq!(session.head_seq(), 0);
}

#[tokio::test]
async fn sequence_exhaustion_fails_the_whole_batch_without_partial_publication() {
    let stored = Stored::with([record_identified("max", i64::MAX as u64, "at the ceiling")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let error = session
        .publish_batch(vec![draft("a", "one"), draft("b", "two")])
        .await
        .expect_err("the assignment would leave the signed 64-bit range");
    assert!(matches!(error, ChatError::SeqExhausted));
    assert_eq!(
        session.head_seq(),
        i64::MAX as u64,
        "the head stays at the ceiling"
    );
    let page = visible(&session, 10).await;
    assert_eq!(page.len(), 1, "only the durable ceiling record is visible");
    assert_eq!(page[0].item_id, "max");
}

#[tokio::test]
async fn confirm_durable_reclaims_the_contiguous_prefix_and_keeps_the_rest_queryable() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let batch = session
        .publish_batch(vec![draft("a", "1"), draft("b", "2"), draft("c", "3")])
        .await
        .expect("the batch is admitted");
    // The writer landed a and b, and confirms exactly that prefix.
    stored.insert(batch[0].as_ref().clone());
    stored.insert(batch[1].as_ref().clone());
    session
        .confirm_durable(2)
        .expect("the contiguous prefix is confirmed");
    assert_eq!(session.durable_seq(), 2);
    assert_eq!(
        session.head_seq(),
        3,
        "the unconfirmed tail stays published"
    );
    // A later completion continues after the reclaimed prefix.
    let tail = session
        .publish_batch(vec![draft("d", "4")])
        .await
        .expect("later completions continue the sequence");
    assert_eq!(tail[0].append_seq, 4);
    let page = visible(&session, 10).await;
    let ids: Vec<&str> = page.iter().map(|item| item.item_id.as_str()).collect();
    assert_eq!(ids, ["a", "b", "c", "d"], "nothing is lost by the reclaim");
    // Confirming a lower watermark again changes nothing.
    session
        .confirm_durable(1)
        .expect("a stale prefix is a no-op");
    assert_eq!(session.durable_seq(), 2);
}

#[tokio::test]
async fn confirming_beyond_the_head_is_a_typed_error() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    session
        .publish_batch(vec![draft("a", "1")])
        .await
        .expect("the batch is admitted");
    let error = session
        .confirm_durable(2)
        .expect_err("a confirmation may not name an unpublished sequence");
    assert!(matches!(error, ChatError::InvalidArgument(_)));
    assert_eq!(session.durable_seq(), 0, "the durable prefix did not move");
}

#[tokio::test]
async fn a_durable_acknowledgement_emits_no_content_event() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let mut tail = session
        .subscribe_tail()
        .await
        .expect("baseline is readable");
    let baseline = support::take_initial(&mut tail);
    assert_eq!(baseline.completed_cursor, None, "history starts empty");
    let records = session
        .publish_batch(vec![draft("a", "1")])
        .await
        .expect("the batch is admitted");
    let batch = match tail.next().await.expect("the completion wakes the tail") {
        pl_core::chat::ChatTailUpdate::Batch(batch) => batch,
        other => panic!("expected a completion batch, got {other:?}"),
    };
    assert_eq!(batch.items.len(), 1);
    // The writer lands the record and confirms; the acknowledgement itself must not wake the tail.
    stored.insert(records[0].as_ref().clone());
    session
        .confirm_durable(1)
        .expect("the durable prefix is confirmed");
    let parked = tokio::time::timeout(std::time::Duration::from_millis(50), tail.next()).await;
    assert!(
        parked.is_err(),
        "a save acknowledgement publishes no content event"
    );
    tail.close();
}

#[tokio::test]
async fn a_full_writer_round_trip_keeps_every_fact_visible_exactly_once() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    publish_and_commit(
        &session,
        &stored,
        vec![draft("a", "one"), draft("b", "two")],
    )
    .await;
    publish_and_commit(&session, &stored, vec![draft("c", "three")]).await;
    assert_eq!(session.durable_seq(), 3);
    let page = visible(&session, 10).await;
    let ids: Vec<&str> = page.iter().map(|item| item.item_id.as_str()).collect();
    assert_eq!(ids, ["a", "b", "c"]);
    assert_eq!(stored.len(), 3);
}
