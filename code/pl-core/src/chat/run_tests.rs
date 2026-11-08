//! Completion-run invariants; reuse the controlled history/barriers used by the existing readers.
#[path = "../../tests/support/timeline.rs"]
mod support;

use super::*;
use futures::FutureExt as _;
use std::sync::{Arc, atomic::Ordering};
use support::*;

fn hinted(id: &str, hint: ChatReadHint) -> ChatDraft {
    let mut item = draft(id, "原始正文");
    item.read_hint = hint;
    item
}

fn adjacent(source: &str) -> ChatReadHint {
    ChatReadHint::Adjacent {
        key: ChatKey::new("来源域", source).unwrap(),
    }
}

fn select(selection: ChatSelection) -> ChatQuery {
    ChatQuery {
        selection,
        ..query()
    }
}

fn main_request(items: usize) -> ChatPageRequest {
    ChatPageRequest::latest(select(ChatSelection::RunHeads), demand(items))
}

async fn main_page(session: &Session, items: usize) -> ChatPage {
    session
        .page(main_request(items), &Budget::default())
        .await
        .unwrap()
}

fn positions(items: &[Arc<ChatItem>]) -> Vec<Option<(u64, u64)>> {
    items
        .iter()
        .map(|item| item.header.run.map(|run| (run.start_seq, run.ordinal)))
        .collect()
}

#[tokio::test]
async fn hints_use_visible_adjacency_opaque_sources_and_keep_real_parents() {
    let session = Session::new(Stored::default(), epoch("runs"));
    let mut first = hinted("first", adjacent("前台一"));
    first.parent_id = Some(ChatKey::new("turn", "one").unwrap());
    let records = session
        .publish_batch(vec![
            first,
            hinted("diagnostic", ChatReadHint::Hidden),
            hinted("second", adjacent("前台一")),
            hinted("other-source", adjacent("前台二")),
            hinted("text", ChatReadHint::Single),
            hinted("late-first-source", adjacent("前台一")),
            hinted("background-1", adjacent("统一后台域")),
            hinted("background-2", adjacent("统一后台域")),
        ])
        .await
        .unwrap();
    assert_eq!(
        positions(&records),
        [
            Some((1, 1)),
            None,
            Some((1, 2)),
            Some((4, 1)),
            Some((5, 1)),
            Some((6, 1)),
            Some((7, 1)),
            Some((7, 2)),
        ]
    );
    assert_eq!(
        sequences(&main_page(&session, 20).await.items),
        [3, 4, 5, 6, 8]
    );
    assert_eq!(
        visible(&session, 20).await.len(),
        8,
        "Records retains Hidden and parented facts"
    );
    let children = session
        .page(
            ChatPageRequest::latest(
                ChatQuery::new("conversation", records[0].header.parent_id.clone()),
                demand(20),
            ),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert_eq!(sequences(&children.items), [1]);
    assert_eq!(
        ChatDraft::new("generic", "internal", Arc::from([])).read_hint,
        ChatReadHint::Hidden
    );
}

#[tokio::test]
async fn replay_never_becomes_the_tail_and_hint_conflicts_leave_the_entire_batch_private() {
    for durable in [false, true] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("replay"));
        let first = hinted("old", adjacent("one"));
        let records = session
            .publish_batch(vec![first.clone(), hinted("single", ChatReadHint::Single)])
            .await
            .unwrap();
        if durable {
            for item in records.iter() {
                stored.insert((**item).clone());
            }
            session.confirm_durable(2).unwrap();
        }
        let repeated = session
            .publish_batch(vec![first.clone(), first.clone()])
            .await
            .unwrap();
        assert_eq!(repeated[0].header, records[0].header);
        assert_eq!(session.head_seq(), 2);
        let mut conflict = first;
        conflict.read_hint = adjacent("different");
        assert!(matches!(
            session
                .publish_batch(vec![hinted("must-not-appear", adjacent("one")), conflict,])
                .await,
            Err(ChatError::Conflict(_))
        ));
        assert_eq!(session.head_seq(), 2);
        let next = session
            .publish_batch(vec![hinted("next", adjacent("one"))])
            .await
            .unwrap();
        assert_eq!(positions(&next), [Some((3, 1))]);
    }
}

#[tokio::test]
async fn cold_seed_preserves_the_last_visible_run_across_a_hidden_durable_tail() {
    let stored = Stored::default();
    let first = Session::new(stored.clone(), epoch("first"));
    let records = first
        .publish_batch(vec![
            hinted("one", adjacent("来源")),
            hinted("hidden", ChatReadHint::Hidden),
        ])
        .await
        .unwrap();
    for record in records.iter() {
        stored.insert((**record).clone());
    }
    first.confirm_durable(2).unwrap();
    drop(first);
    let cold = Session::new(stored, epoch("second"));
    let records = cold
        .publish_batch(vec![hinted("two", adjacent("来源"))])
        .await
        .unwrap();
    assert_eq!(positions(&records), [Some((1, 2))]);
    assert_eq!((cold.durable_seq(), cold.head_seq()), (2, 3));
}

#[test]
fn allocation_rejects_signed_seq_and_ordinal_overflow_without_mutating_seed() {
    let hint = adjacent("边界");
    for mut seed in [
        ChatPublicationSeed {
            head_seq: i64::MAX as u64,
            last_visible: None,
        },
        ChatPublicationSeed {
            head_seq: 42,
            last_visible: Some(ChatRunSeed {
                seq: 42,
                hint: hint.clone(),
                position: ChatRunPosition {
                    start_seq: 1,
                    ordinal: u64::MAX,
                },
            }),
        },
    ] {
        let before = seed.clone();
        assert!(matches!(seed.advance(&hint), Err(ChatError::SeqExhausted)));
        assert_eq!(seed, before);
    }
    let mut seed = ChatPublicationSeed {
        head_seq: i64::MAX as u64 - 1,
        last_visible: None,
    };
    assert_eq!(
        seed.advance(&ChatReadHint::Single).unwrap(),
        (
            i64::MAX as u64,
            Some(ChatRunPosition {
                start_seq: i64::MAX as u64,
                ordinal: 1
            })
        )
    );
    let invalid = ChatPublicationSeed {
        head_seq: u64::MAX,
        last_visible: None,
    };
    assert!(matches!(invalid.validate(), Err(ChatError::SeqExhausted)));
}

#[tokio::test]
async fn arithmetic_failure_at_the_end_does_not_publish_the_candidate_prefix_or_advance_run() {
    let stored = Stored::with([ChatItem::complete(
        hinted("near-end", ChatReadHint::Single),
        i64::MAX as u64 - 1,
        Some(ChatRunPosition {
            start_seq: i64::MAX as u64 - 1,
            ordinal: 1,
        }),
    )]);
    let session = Session::new(stored, epoch("end"));
    assert!(matches!(
        session
            .publish_batch(vec![
                hinted("candidate", adjacent("one")),
                hinted("overflow", adjacent("one"))
            ])
            .await,
        Err(ChatError::SeqExhausted)
    ));
    assert_eq!(session.head_seq(), i64::MAX as u64 - 1);
    let record = session
        .publish_batch(vec![hinted("last", adjacent("one"))])
        .await
        .unwrap();
    assert_eq!(positions(&record), [Some((i64::MAX as u64, 1))]);
}

#[tokio::test]
async fn cross_durable_run_is_returned_once_and_run_members_remain_individually_readable() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("cross-d"));
    let records = session
        .publish_batch(vec![
            hinted("text", ChatReadHint::Single),
            hinted("a", adjacent("one")),
            hinted("hidden", ChatReadHint::Hidden),
            hinted("b", adjacent("one")),
            hinted("c", adjacent("one")),
        ])
        .await
        .unwrap();
    for record in records.iter().take(4) {
        stored.insert((**record).clone());
    }
    session.confirm_durable(4).unwrap();
    let page = main_page(&session, 20).await;
    assert_eq!(sequences(&page.items), [1, 5]);
    assert_eq!(page.items[1].header.run.unwrap().ordinal, 3);
    let request = stored.reads.pages.lock().unwrap()[0].clone();
    assert_eq!(
        request.ceiling, 1,
        "RAM representative jumps over the durable part of its run"
    );
    let members = session
        .page(
            ChatPageRequest::latest(select(ChatSelection::Run { start_seq: 2 }), demand(20)),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert_eq!(sequences(&members.items), [2, 4, 5]);
    assert!(
        members
            .items
            .iter()
            .all(|item| matches!(item.payload, PayloadData::Inline(_)))
    );
}

#[tokio::test]
async fn a_fixed_main_cursor_keeps_its_original_cut_when_the_same_run_grows() {
    let session = Session::new(Stored::default(), epoch("fixed"));
    session
        .publish_batch(vec![
            hinted("one", ChatReadHint::Single),
            hinted("a", adjacent("one")),
            hinted("b", adjacent("one")),
        ])
        .await
        .unwrap();
    let page = main_page(&session, 1).await;
    let cursor = page.before.unwrap();
    assert_eq!(
        (
            cursor.version,
            cursor.index_version,
            cursor.ceiling,
            cursor.append_seq
        ),
        (2, 1, 3, 2)
    );
    session
        .publish_batch(vec![hinted("c", adjacent("one"))])
        .await
        .unwrap();
    let older = session
        .page(
            ChatPageRequest::before(cursor, demand(1)),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert_eq!(older.ceiling, 3);
    assert_eq!(sequences(&older.items), [1]);
    let latest = main_page(&session, 1).await;
    assert_eq!(sequences(&latest.items), [4]);
    assert_eq!(latest.items[0].header.run.unwrap().ordinal, 3);
}

#[tokio::test]
async fn main_byte_cut_and_final_empty_page_keep_exclusive_run_boundaries() {
    let session = Session::new(Stored::default(), epoch("byte-cut"));
    let records = session
        .publish_batch(vec![
            hinted("a", adjacent("one")),
            hinted("b", adjacent("one")),
        ])
        .await
        .unwrap();
    let budget = Budget::default();
    let bytes = budget.fixed_bytes() + budget.item_bytes(&records[1].header, PayloadMode::Deferred);
    let page = session
        .page(
            ChatPageRequest::latest(select(ChatSelection::RunHeads), ReadDemand::new(1, bytes)),
            &budget,
        )
        .await
        .unwrap();
    assert!(matches!(
        page.items[0].payload,
        PayloadData::Deferred { .. }
    ));
    assert_eq!(page.before.as_ref().unwrap().append_seq, 1);
    let empty = session
        .page(
            ChatPageRequest::before(page.before.unwrap(), demand(1)),
            &budget,
        )
        .await
        .unwrap();
    assert!(empty.items.is_empty());
    assert!(empty.before.is_none());
    assert!(matches!(
        session
            .page(
                ChatPageRequest::latest(
                    select(ChatSelection::RunHeads),
                    ReadDemand::new(1, bytes - 1)
                ),
                &budget
            )
            .await,
        Err(ChatError::InvalidDemand(_))
    ));
}

#[tokio::test]
async fn run_heads_reject_parent_and_cursor_version_scope_or_epoch_changes() {
    let session = Session::new(Stored::default(), epoch("validation"));
    session
        .publish_batch(vec![hinted("a", adjacent("one"))])
        .await
        .unwrap();
    for selection in [ChatSelection::RunHeads, ChatSelection::Run { start_seq: 1 }] {
        let mut query = select(selection);
        query.parent_id = Some(ChatKey::new("call", "one").unwrap());
        assert!(matches!(
            session
                .page(
                    ChatPageRequest::latest(query, demand(1)),
                    &Budget::default()
                )
                .await,
            Err(ChatError::InvalidArgument(_))
        ));
    }
    let cursor = main_page(&session, 1).await.before.unwrap();
    for change in 0..4 {
        let mut invalid = cursor.clone();
        match change {
            0 => invalid.version = 1,
            1 => invalid.index_version = 2,
            2 => invalid.query.selection = ChatSelection::Records,
            _ => invalid.epoch = epoch("retired"),
        }
        let mut request = ChatPageRequest::before(invalid, demand(1));
        request.query = select(ChatSelection::RunHeads);
        assert!(session.page(request, &Budget::default()).await.is_err());
    }
}

#[tokio::test]
async fn main_tail_replays_every_member_and_filtered_completions_advance_through() {
    for durable in [false, true] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("tail"));
        let mut tail = session
            .subscribe_tail(
                select(ChatSelection::RunHeads),
                demand(1),
                Arc::new(Budget::default()),
            )
            .await
            .unwrap();
        tail.initial().unwrap();
        let records = session
            .publish_batch(vec![
                hinted("a", adjacent("one")),
                hinted("hidden", ChatReadHint::Hidden),
                hinted("b", adjacent("one")),
                hinted("c", adjacent("one")),
            ])
            .await
            .unwrap();
        if durable {
            for item in records.iter() {
                stored.insert((**item).clone());
            }
            session.confirm_durable(4).unwrap();
        }
        for (seq, ordinal) in [(1, 1), (3, 2), (4, 3)] {
            let ChatTailUpdate::Batch(batch) = tail.next().await.unwrap() else {
                panic!("batch")
            };
            assert_eq!(sequences(&batch.items), [seq]);
            assert_eq!(batch.through_seq, seq);
            assert_eq!(batch.items[0].header.run.unwrap().ordinal, ordinal);
            assert!(matches!(
                batch.items[0].payload,
                PayloadData::Deferred { .. }
            ));
        }
        assert!(tail.next().now_or_never().is_none());
        assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
        assert!(
            stored
                .reads
                .afters
                .lock()
                .unwrap()
                .iter()
                .all(|request| request.query.as_ref().unwrap().selection == ChatSelection::Records)
        );
    }
}

#[tokio::test]
async fn captured_run_arcs_survive_commit_cleanup_and_a_later_publication() {
    let stored = Stored::default();
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history, epoch("capture"));
    let records = session
        .publish_batch(vec![
            hinted("old", ChatReadHint::Single),
            hinted("a", adjacent("one")),
            hinted("b", adjacent("one")),
        ])
        .await
        .unwrap();
    stored.insert((*records[0]).clone());
    session.confirm_durable(1).unwrap();
    let reading = {
        let session = session.clone();
        tokio::spawn(async move { main_page(&session, 20).await })
    };
    gate.entered().await;
    for record in records.iter().skip(1) {
        stored.insert((**record).clone());
    }
    session.confirm_durable(3).unwrap();
    session
        .publish_batch(vec![hinted("future", adjacent("one"))])
        .await
        .unwrap();
    gate.release();
    let page = reading.await.unwrap();
    assert_eq!(page.ceiling, 3);
    assert_eq!(sequences(&page.items), [1, 3]);
    assert_eq!(stored.reads.pages.lock().unwrap()[0].ceiling, 1);
    gate.release();
    let after_cleanup = main_page(&session, 20).await;
    assert_eq!(sequences(&after_cleanup.items), [1, 4]);
}

#[tokio::test]
async fn durable_confirmation_releases_all_secondary_record_and_content_references_exactly() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("release"));
    let records = session
        .publish_batch(vec![
            with_body(
                hinted("a", adjacent("one")),
                "body",
                ContentData::Bytes(Arc::from(b"owned body".as_slice())),
            ),
            hinted("b", adjacent("one")),
        ])
        .await
        .unwrap();
    let body = records[0].contents.values().next().unwrap().clone();
    let body_key = body.descriptor.key.clone();
    let weak = Arc::downgrade(&records[0]);
    let remaining = Arc::downgrade(&records[1]);
    stored.insert((*records[0]).clone());
    session.confirm_durable(1).unwrap();
    assert_eq!(
        Arc::strong_count(&records[0]),
        1,
        "every index released the first Arc"
    );
    assert_eq!(
        Arc::strong_count(&body),
        2,
        "only the frozen manifest and this reader retain the body"
    );
    assert!(
        session
            .with_timeline(|state| state.pending_content(&body_key))
            .is_none()
    );
    assert!(Arc::strong_count(&records[1]) > 1);
    drop(records);
    assert!(weak.upgrade().is_none());
    assert!(
        remaining.upgrade().is_some(),
        "uncommitted member stays pending"
    );
    assert!(matches!(
        session.confirm_durable(3),
        Err(ChatError::InvalidArgument(_))
    ));
    assert_eq!((session.durable_seq(), session.head_seq()), (1, 2));
    session.confirm_durable(1).unwrap();
}

#[tokio::test]
async fn run_replay_examines_filtered_gaps_and_advances_to_the_fixed_global_ceiling() {
    for durable in [false, true] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("run-replay"));
        let records = session
            .publish_batch(vec![
                hinted("a", adjacent("one")),
                hinted("hidden", ChatReadHint::Hidden),
                hinted("b", adjacent("one")),
                hinted("other", ChatReadHint::Single),
            ])
            .await
            .unwrap();
        if durable {
            for record in records.iter() {
                stored.insert((**record).clone());
            }
            session.confirm_durable(4).unwrap();
        }
        let batch = session
            .completed_after(
                ChatCompletionCursor::new(session.epoch(), 0),
                Some(select(ChatSelection::Run { start_seq: 1 })),
                Some(4),
                demand(20),
                &Budget::default(),
            )
            .await
            .unwrap();
        assert_eq!(sequences(&batch.items), [1, 3]);
        assert_eq!((batch.from_seq, batch.through_seq), (0, 4));
        let empty = session
            .completed_after(
                ChatCompletionCursor::new(session.epoch(), 3),
                Some(select(ChatSelection::Run { start_seq: 1 })),
                Some(4),
                demand(1),
                &Budget::default(),
            )
            .await
            .unwrap();
        assert!(empty.items.is_empty());
        assert_eq!((empty.from_seq, empty.through_seq), (3, 4));
    }
}

#[tokio::test]
async fn collapsed_pending_work_is_bounded_by_requested_runs_for_one_to_100000_members() {
    let mut expected_cost = None;
    for size in [1, 100, 10_000, 100_000] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("scale"));
        let mut drafts = Vec::with_capacity(size + 19);
        for index in 0..19 {
            drafts.push(hinted(&format!("single-{index}"), ChatReadHint::Single));
        }
        for index in 0..size {
            drafts.push(hinted(&format!("work-{index}"), adjacent("one")));
        }
        let records = session.publish_batch(drafts).await.unwrap();
        let budget = Budget::default();
        let page = session.page(main_request(20), &budget).await.unwrap();
        assert_eq!(page.items.len(), 20);
        assert_eq!(
            page.items.last().unwrap().header.run.unwrap().ordinal,
            size as u64
        );
        assert!(matches!(
            page.items.last().unwrap().payload,
            PayloadData::Deferred { .. }
        ));
        assert!(stored.reads.pages.lock().unwrap().is_empty());
        assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
        let cost = budget.visited.lock().unwrap().len();
        assert_eq!(*expected_cost.get_or_insert(cost), cost);
        // A real scoped index must not retain any saved work member or scan it at the next read.
        for record in records.iter() {
            stored.insert((**record).clone());
        }
        session.confirm_durable(session.head_seq()).unwrap();
        assert!(records.iter().all(|record| Arc::strong_count(record) == 1));
    }
}

fn item_request(session: &Session, item_id: &str, ceiling: Option<u64>) -> ChatItemRequest {
    ChatItemRequest {
        epoch: session.epoch(),
        item_id: item_id.into(),
        ceiling,
        demand: demand(1),
    }
}

#[tokio::test]
async fn read_item_pending_hit_and_pending_only_miss_do_no_history_io_or_manifest_clone() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("point-pending"));
    let records = session
        .publish_batch(vec![
            with_body(
                hinted("first", ChatReadHint::Single),
                "body",
                ContentData::Bytes(Arc::from(b"separate body".as_slice())),
            ),
            hinted("future", ChatReadHint::Single),
        ])
        .await
        .unwrap();
    let identity_reads = stored.reads.item.load(Ordering::SeqCst);
    let manifests = Arc::strong_count(&records[0].contents);
    let item = session
        .read_item(item_request(&session, "first", None), &Budget::default())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(item.header, records[0].header);
    let PayloadData::Inline(payload) = &item.payload else {
        panic!("small envelope")
    };
    assert!(Arc::ptr_eq(payload, &records[0].payload));
    assert_eq!(Arc::strong_count(&records[0].contents), manifests);
    assert!(
        session
            .read_item(
                item_request(&session, "future", Some(1)),
                &Budget::default()
            )
            .await
            .unwrap()
            .is_none(),
        "known future pending identity must not fall through to history"
    );
    assert!(
        session
            .read_item(item_request(&session, "missing", None), &Budget::default())
            .await
            .unwrap()
            .is_none()
    );
    assert_eq!(stored.reads.item.load(Ordering::SeqCst), identity_reads);
    assert!(stored.reads.item_envelopes.lock().unwrap().is_empty());
    assert!(stored.reads.pages.lock().unwrap().is_empty());
    assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
    assert!(stored.reads.ranges.lock().unwrap().is_empty());
    let weak = Arc::downgrade(&records[0]);
    for record in records.iter() {
        stored.insert((**record).clone());
    }
    session.confirm_durable(2).unwrap();
    drop(records);
    assert!(
        weak.upgrade().is_none(),
        "envelope does not retain the record/contents owner"
    );
    assert_eq!(
        payload.as_ref(),
        "原始正文".as_bytes(),
        "returned payload survives commit cleanup"
    );
}

#[tokio::test]
async fn read_item_cold_history_reads_only_the_requested_envelope_with_reserved_budget() {
    let stored = Stored::with([ChatItem::complete(
        with_body(
            hinted("durable", ChatReadHint::Single),
            "body",
            ContentData::Bytes(Arc::from(b"not requested".as_slice())),
        ),
        1,
        Some(ChatRunPosition {
            start_seq: 1,
            ordinal: 1,
        }),
    )]);
    let session = Session::new(stored.clone(), epoch("point-cold"));
    let budget = Budget::default();
    let request = item_request(&session, "durable", None);
    let max_bytes = request.demand.max_bytes - budget.fixed_bytes();
    let item = session.read_item(request, &budget).await.unwrap().unwrap();
    assert_eq!((session.head_seq(), session.durable_seq()), (1, 1));
    assert_eq!(
        (item.header.item_id.as_str(), item.header.append_seq),
        ("durable", 1)
    );
    assert!(matches!(item.payload, PayloadData::Inline(_)));
    assert_eq!(
        stored.reads.item_envelopes.lock().unwrap().as_slice(),
        [ChatHistoryItemRequest {
            item_id: "durable".into(),
            ceiling: 1,
            demand: ReadDemand::new(1, max_bytes)
        },]
    );
    assert_eq!(
        stored.reads.item.load(Ordering::SeqCst),
        0,
        "never use publication item()"
    );
    assert_eq!(
        stored.reads.payload_bytes.load(Ordering::SeqCst),
        "原始正文".len()
    );
    assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
    assert!(stored.reads.ranges.lock().unwrap().is_empty());
    assert!(
        session
            .read_item(item_request(&session, "durable", Some(0)), &budget)
            .await
            .unwrap()
            .is_none()
    );
    assert_eq!(stored.reads.item_envelopes.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn read_item_defers_large_payloads_without_loading_contents_in_pending_or_history() {
    for durable in [false, true] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("point-large"));
        let mut large = hinted("large", adjacent("one"));
        large.payload = Arc::from(vec![b'x'; 2 * 1024 * 1024]);
        let records = session
            .publish_batch(vec![with_body(
                large,
                "body",
                ContentData::Bytes(Arc::from(vec![b'y'; 4 * 1024 * 1024])),
            )])
            .await
            .unwrap();
        if durable {
            stored.insert((*records[0]).clone());
            session.confirm_durable(1).unwrap();
        }
        let manifests = Arc::strong_count(&records[0].contents);
        let identity_reads = stored.reads.item.load(Ordering::SeqCst);
        let mut request = item_request(&session, "large", None);
        request.demand = ReadDemand::new(20, 512);
        let item = session
            .read_item(request, &Budget::default())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            item.payload,
            PayloadData::Deferred {
                item_id: "large".into(),
                byte_length: 2 * 1024 * 1024,
            }
        );
        assert_eq!(Arc::strong_count(&records[0].contents), manifests);
        assert_eq!(stored.reads.item.load(Ordering::SeqCst), identity_reads);
        assert_eq!(
            stored.reads.item_envelopes.lock().unwrap().len(),
            usize::from(durable)
        );
        assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
        assert_eq!(stored.reads.manifests.load(Ordering::SeqCst), 0);
        assert!(stored.reads.ranges.lock().unwrap().is_empty());
    }
}

#[tokio::test]
async fn read_item_miss_captures_d_before_new_snapshot_even_when_writer_commits_and_cleans() {
    for explicit_cut in [None, Some(1)] {
        let stored = Stored::with([record_identified("old", 1, "durable prefix")]);
        let gate = Arc::new(HistoryGate::new());
        let mut history = GatedHistory::new(stored.clone());
        history.read_item_gate = Some(gate.clone());
        let session = Session::new(history, epoch("point-cut"));
        let reading = {
            let session = session.clone();
            tokio::spawn(async move {
                session
                    .read_item(
                        item_request(&session, "future", explicit_cut),
                        &Budget::default(),
                    )
                    .await
            })
        };
        gate.entered().await;
        let records = session
            .publish_batch(vec![hinted("future", adjacent("one"))])
            .await
            .unwrap();
        stored.insert((*records[0]).clone());
        session.confirm_durable(2).unwrap();
        gate.release();
        assert!(reading.await.unwrap().unwrap().is_none());
        assert_eq!(
            stored.reads.item_envelopes.lock().unwrap()[0].ceiling,
            1,
            "fresh history snapshot must still honor captured D/H, not latest D"
        );
        gate.release();
        let after_cleanup = session
            .read_item(item_request(&session, "future", None), &Budget::default())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(after_cleanup.header.append_seq, 2);
        assert_eq!(stored.reads.item_envelopes.lock().unwrap()[1].ceiling, 2);
    }
}

#[tokio::test]
async fn read_item_keeps_absence_budget_epoch_and_history_errors_distinct() {
    for durable in [false, true] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("point-errors"));
        let records = session
            .publish_batch(vec![hinted("one", ChatReadHint::Single)])
            .await
            .unwrap();
        if durable {
            stored.insert((*records[0]).clone());
            session.confirm_durable(1).unwrap();
        }
        let budget = Budget::default();
        let missing = session
            .read_item(item_request(&session, "missing", None), &budget)
            .await
            .unwrap();
        assert!(missing.is_none());
        let mut tiny = item_request(&session, "one", None);
        tiny.demand = ReadDemand::new(1, budget.fixed_bytes() + 1);
        assert!(matches!(
            session.read_item(tiny, &budget).await,
            Err(ChatError::InvalidDemand(_))
        ));
        let mut stale = item_request(&session, "one", None);
        stale.epoch = epoch("retired");
        assert!(matches!(
            session.read_item(stale, &budget).await,
            Err(ChatError::EpochMismatch { .. })
        ));
        assert!(matches!(
            session
                .read_item(item_request(&session, "one", Some(2)), &budget)
                .await,
            Err(ChatError::InvalidArgument(_))
        ));
        assert!(matches!(
            session
                .read_item(item_request(&session, "", None), &budget)
                .await,
            Err(ChatError::InvalidArgument(_))
        ));
        if durable {
            stored.fail_read_item.store(true, Ordering::SeqCst);
            assert!(matches!(
                session
                    .read_item(item_request(&session, "one", None), &budget)
                    .await,
                Err(ChatError::History(_))
            ));
            assert!(
                session
                    .read_item(item_request(&session, "one", None), &budget)
                    .await
                    .unwrap()
                    .is_some(),
                "a failed read does not consume the fixed identity"
            );
        }
    }
}

#[tokio::test]
async fn read_item_explicit_detail_can_inline_work_while_header_only_demand_never_fetches_it() {
    for durable in [false, true] {
        let stored = Stored::default();
        let session = Session::new(stored.clone(), epoch("point-payload-policy"));
        let records = session
            .publish_batch(vec![hinted("work", adjacent("one"))])
            .await
            .unwrap();
        if durable {
            stored.insert((*records[0]).clone());
            session.confirm_durable(1).unwrap();
        }
        let budget = Budget::default();
        let detail = session
            .read_item(item_request(&session, "work", None), &budget)
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(detail.payload, PayloadData::Inline(_)));
        stored.reads.payload_bytes.store(0, Ordering::SeqCst);
        let header_only = super::read::RunHeadBudget(&budget);
        let deferred = session
            .read_item(item_request(&session, "work", None), &header_only)
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(deferred.payload, PayloadData::Deferred { .. }));
        assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
    }
}
