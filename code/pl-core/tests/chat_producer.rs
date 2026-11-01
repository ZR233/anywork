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
    session
        .confirm_durable(committed[0].header.append_seq)
        .unwrap();
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
    assert_eq!(
        second[0].header.append_seq, 1,
        "the first publication gets seq 1"
    );
    assert_eq!(
        first[0].header.append_seq, 2,
        "the later completion follows it"
    );
    let page = visible(&session, 10).await;
    let ids: Vec<&str> = page
        .iter()
        .map(|item| item.header.item_id.as_str())
        .collect();
    assert_eq!(ids, ["tool-b", "tool-a"], "order is completion order");
}

#[tokio::test]
async fn a_batch_gets_consecutive_sequences_and_becomes_visible_at_once() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("a", "1"), draft("b", "2"), draft("c", "3")])
        .await
        .expect("the batch is admitted");
    let sequences: Vec<u64> = records.iter().map(|item| item.header.append_seq).collect();
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
    assert_eq!(
        second[0].header.append_seq, 1,
        "the original sequence is reused"
    );
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
    assert_eq!(
        records[0].header.append_seq, 7,
        "the persisted sequence is reused"
    );
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
    assert_eq!(page[0].header.item_id, "max");
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
    assert_eq!(tail[0].header.append_seq, 4);
    let page = visible(&session, 10).await;
    let ids: Vec<&str> = page
        .iter()
        .map(|item| item.header.item_id.as_str())
        .collect();
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
        .subscribe_tail(
            support::query(),
            support::demand(10),
            Arc::new(support::Budget::default()),
        )
        .await
        .expect("baseline is readable");
    let baseline = tail.initial().unwrap();
    assert_eq!(baseline.through_seq, 0, "history starts empty");
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
    assert!(
        futures::poll!(Box::pin(tail.next())).is_pending(),
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
    let ids: Vec<&str> = page
        .iter()
        .map(|item| item.header.item_id.as_str())
        .collect();
    assert_eq!(ids, ["a", "b", "c"]);
    assert_eq!(stored.len(), 3);
}

#[tokio::test]
async fn a_manifest_conflict_rejects_the_whole_batch_without_partial_index_publication() {
    use pl_core::chat::{ChatContentKey, ChatKey, ContentData};
    let session = Session::new(Stored::default(), epoch("run-1"));
    let key = ChatContentKey {
        owner: ChatKey::new("item", "shared").unwrap(),
        key: "body".into(),
    };
    let make = |id: &str, byte: u8| {
        let mut item = support::with_body(
            draft(id, "opaque"),
            "body",
            ContentData::Bytes(Arc::from([byte])),
        );
        let (_, content) = Arc::make_mut(&mut item.contents).pop_first().unwrap();
        let mut content = (*content).clone();
        content.descriptor.key = key.clone();
        Arc::make_mut(&mut item.contents).insert(key.clone(), Arc::new(content));
        item
    };
    session.publish_batch(vec![make("first", 1)]).await.unwrap();
    assert!(matches!(
        session
            .publish_batch(vec![draft("fresh", "not published"), make("second", 2)])
            .await,
        Err(ChatError::Conflict(_))
    ));
    assert_eq!(session.head_seq(), 1);
    assert_eq!(visible(&session, 10).await.len(), 1);
    assert!(matches!(
        session
            .publish_batch(vec![make("third", 3), make("fourth", 4)])
            .await,
        Err(ChatError::Conflict(_))
    ));
    assert_eq!(session.head_seq(), 1);
}

#[tokio::test]
async fn query_membership_is_part_of_the_frozen_identity_and_typed_keys_do_not_alias() {
    use pl_core::chat::{ChatKey, ContentData};
    let a = ChatKey::new("turn", "same").unwrap();
    let b = ChatKey::new("call", "same").unwrap();
    assert_ne!(a, b);
    assert_eq!(ChatKey::from_encoded(a.as_str().into()).unwrap(), a);
    assert_ne!(
        ChatKey::new("ab", "c").unwrap(),
        ChatKey::new("a", "bc").unwrap()
    );
    let session = Session::new(Stored::default(), epoch("run-1"));
    let frozen = support::with_body(
        draft("x", "payload"),
        "body",
        ContentData::Bytes(Arc::from([1])),
    );
    session.publish_batch(vec![frozen.clone()]).await.unwrap();
    let mut changes = Vec::new();
    let mut changed = frozen.clone();
    changed.query_class = "activity".into();
    changes.push(changed);
    let mut changed = frozen.clone();
    changed.parent_id = Some(a);
    changes.push(changed);
    let mut changed = frozen;
    changed.contents = Arc::default();
    changes.push(changed);
    for changed in changes {
        assert!(matches!(
            session
                .publish_batch(vec![draft("fresh", "fresh"), changed])
                .await,
            Err(ChatError::Conflict(_))
        ));
        assert_eq!(session.head_seq(), 1);
    }
}

#[tokio::test]
async fn an_out_of_range_persistent_seed_never_initializes_or_publishes() {
    let session = Session::new(
        Stored::with([record_identified(
            "invalid",
            i64::MAX as u64 + 1,
            "bad seed",
        )]),
        epoch("run-1"),
    );
    assert!(matches!(
        session.publish_batch(vec![draft("fresh", "fresh")]).await,
        Err(ChatError::SeqExhausted)
    ));
    assert_eq!((session.durable_seq(), session.head_seq()), (0, 0));
}

fn sharing_body(id: &str, data: pl_core::chat::ContentData) -> pl_core::chat::ChatDraft {
    use pl_core::chat::{ChatContentKey, ChatKey};
    let mut item = support::with_body(draft(id, "opaque"), "body", data);
    let (_, content) = Arc::make_mut(&mut item.contents).pop_first().unwrap();
    let mut content = (*content).clone();
    let key = ChatContentKey {
        owner: ChatKey::new("item", "shared").unwrap(),
        key: "body".into(),
    };
    content.descriptor.key = key.clone();
    Arc::make_mut(&mut item.contents).insert(key, Arc::new(content));
    item
}

#[tokio::test]
async fn a_durable_content_conflict_rejects_every_new_item_and_preserves_the_old_body() {
    use pl_core::chat::{ContentData, ContentRef};
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let first = sharing_body("first", ContentData::Bytes(Arc::from([1])));
    let key = first.contents.keys().next().unwrap().clone();
    publish_and_commit(&session, &stored, vec![first]).await;
    // Same key, generation and length, different actual bytes must conflict before publication.
    let byte_conflict = sharing_body("second", ContentData::Bytes(Arc::from([2])));
    let mut generation_conflict = sharing_body("second", ContentData::Bytes(Arc::from([1])));
    let content = Arc::make_mut(&mut generation_conflict.contents)
        .get_mut(&key)
        .unwrap();
    Arc::make_mut(content).descriptor.generation += 1;
    let mut media_conflict = sharing_body("second", ContentData::Bytes(Arc::from([1])));
    let content = Arc::make_mut(&mut media_conflict.contents)
        .get_mut(&key)
        .unwrap();
    Arc::make_mut(content).descriptor.media_type = Some("application/octet-stream".into());
    for second in [byte_conflict, generation_conflict, media_conflict] {
        assert!(matches!(
            session
                .publish_batch(vec![draft("fresh", "must not become visible"), second])
                .await,
            Err(ChatError::Conflict(_))
        ));
        assert_eq!((session.durable_seq(), session.head_seq()), (1, 1));
        let items = visible(&session, 10).await;
        assert_eq!(
            items
                .iter()
                .map(|item| item.header.item_id.as_str())
                .collect::<Vec<_>>(),
            ["first"]
        );
        let old = session
            .read_content(support::content_request(
                ContentRef::Body(key.clone()),
                0,
                1,
            ))
            .await
            .unwrap();
        assert_eq!(old.bytes.as_bytes(), &[1]);
    }
}

#[tokio::test]
async fn publication_revalidates_content_after_a_stale_snapshot_and_concurrent_commit_or_pending_insert()
 {
    use pl_core::chat::{ContentData, ContentRef};
    for commit in [false, true] {
        let stored = Stored::default();
        let gate = Arc::new(HistoryGate::new());
        let mut history = GatedHistory::new(stored.clone());
        history.captured_validation_gate = Some(gate.clone());
        let session = Session::new(history, epoch("run-1"));
        let second = sharing_body("second", ContentData::Bytes(Arc::from([2])));
        let key = second.contents.keys().next().unwrap().clone();
        let delayed = {
            let session = session.clone();
            tokio::spawn(async move {
                session
                    .publish_batch(vec![draft("fresh", "not admitted"), second])
                    .await
            })
        };
        gate.entered().await;
        assert_eq!(
            session.head_seq(),
            0,
            "no partial admission while validation awaits"
        );
        let first = session
            .publish_batch(vec![sharing_body(
                "first",
                ContentData::Bytes(Arc::from([1])),
            )])
            .await
            .unwrap();
        if commit {
            stored.insert((*first[0]).clone());
            session.confirm_durable(1).unwrap();
        }
        gate.release();
        assert!(matches!(
            delayed.await.unwrap(),
            Err(ChatError::Conflict(_))
        ));
        assert_eq!(session.head_seq(), 1);
        assert_eq!(visible(&session, 10).await[0].header.item_id, "first");
        assert_eq!(visible(&session, 10).await.len(), 1);
        assert_eq!(
            stored.reads.validations.lock().unwrap().len(),
            if commit { 3 } else { 2 },
            "a changed D must open a fresh validation snapshot"
        );
        assert_eq!(
            session
                .read_content(support::content_request(ContentRef::Body(key), 0, 1))
                .await
                .unwrap()
                .bytes
                .as_bytes(),
            &[1]
        );
    }
}

#[tokio::test]
async fn byte_equivalent_text_and_binary_owners_are_idempotent_in_pending_durable_and_same_batch() {
    use pl_core::{chat::ContentData, model::ContentBlock};
    let body = "汉📖".repeat(10_000);
    let text = || {
        ContentData::text(ContentBlock::append(
            &ContentBlock::from_text(&body[..35_000]),
            &body[35_000..],
        ))
    };
    let binary = || ContentData::Bytes(Arc::from(body.as_bytes()));
    for first_is_text in [false, true] {
        for commit in [false, true] {
            let stored = Stored::default();
            let session = Session::new(stored.clone(), epoch("run-1"));
            let first = session
                .publish_batch(vec![sharing_body(
                    "first",
                    if first_is_text { text() } else { binary() },
                )])
                .await
                .unwrap();
            if commit {
                // A durable adapter can reconstruct its BLOB as Bytes regardless of the producer.
                let persisted =
                    pl_core::chat::ChatItem::complete(sharing_body("first", binary()), 1);
                stored.insert(persisted);
                session.confirm_durable(1).unwrap();
            }
            let repeat = session
                .publish_batch(vec![
                    sharing_body("first", if first_is_text { binary() } else { text() }),
                    sharing_body("first", ContentData::text(ContentBlock::from_text(&body))),
                ])
                .await
                .unwrap();
            assert_eq!(repeat.len(), 1);
            assert_eq!(repeat[0].header.append_seq, 1);
            if !commit {
                assert!(Arc::ptr_eq(&repeat[0], &first[0]));
            }
            let validations_before = stored.reads.validations.lock().unwrap().len();
            let shared = session
                .publish_batch(vec![
                    sharing_body("second", text()),
                    sharing_body("third", binary()),
                ])
                .await
                .unwrap();
            assert_eq!(
                shared
                    .iter()
                    .map(|item| item.header.append_seq)
                    .collect::<Vec<_>>(),
                [2, 3]
            );
            assert_eq!(
                stored.reads.validations.lock().unwrap().len(),
                validations_before + 1,
                "validate each unique content key once per publication attempt"
            );
        }
    }
}

#[tokio::test]
async fn cancellation_and_storage_failure_during_content_validation_publish_nothing() {
    use pl_core::chat::ContentData;
    use std::sync::atomic::Ordering;
    let stored = Stored::default();
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.captured_validation_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let batch = || {
        vec![
            draft("fresh", "not partial"),
            sharing_body("body-owner", ContentData::Bytes(Arc::from([1]))),
        ]
    };
    let delayed = {
        let session = session.clone();
        let batch = batch();
        tokio::spawn(async move { session.publish_batch(batch).await })
    };
    gate.entered().await;
    delayed.abort();
    assert!(delayed.await.unwrap_err().is_cancelled());
    assert_eq!(session.head_seq(), 0);
    stored.fail_validation.store(true, Ordering::SeqCst);
    assert!(matches!(
        session.publish_batch(batch()).await,
        Err(ChatError::History(_))
    ));
    assert_eq!(session.head_seq(), 0);
    assert!(visible(&session, 10).await.is_empty());
    let records = session.publish_batch(batch()).await.unwrap();
    assert_eq!(
        records
            .iter()
            .map(|record| record.header.append_seq)
            .collect::<Vec<_>>(),
        [1, 2]
    );
}
