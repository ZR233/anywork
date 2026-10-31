//! Demand-first, scope-indexed keyset reads with disjoint committed/pending intervals.
#[path = "support/timeline.rs"]
mod support;
use pl_core::chat::*;
use std::sync::{Arc, atomic::Ordering};
use support::*;

#[tokio::test]
async fn pending_full_page_does_no_history_io_and_reuses_payload_arcs() {
    let stored = Stored::with([record(1, "durable")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("a", "a"), draft("b", "b")])
        .await
        .unwrap();
    let page = session.page(latest(2), &Budget::default()).await.unwrap();
    assert_eq!(sequences(&page.items), [2, 3]);
    assert!(page.before.is_some());
    assert!(stored.reads.pages.lock().unwrap().is_empty());
    assert!(stored.reads.afters.lock().unwrap().is_empty());
    if let PayloadData::Inline(bytes) = &page.items[0].payload {
        assert!(Arc::ptr_eq(bytes, &records[0].payload));
    } else {
        panic!("small payload should be inline");
    }
}

#[tokio::test]
async fn an_exact_memory_fill_may_return_one_empty_eof_page_without_cursor_loop() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    session.publish_batch(vec![draft("a", "a")]).await.unwrap();
    let first = session.page(latest(1), &Budget::default()).await.unwrap();
    let eof = session
        .page(
            ChatPageRequest::before(first.before.unwrap(), demand(1)),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert!(eof.items.is_empty());
    assert!(eof.before.is_none());
    assert!(stored.reads.pages.lock().unwrap().is_empty());
}

#[tokio::test]
async fn insufficient_pending_only_requests_the_remaining_budget_before_captured_d() {
    let stored = Stored::with((1..=3).map(|seq| record(seq, "d")));
    let session = Session::new(stored.clone(), epoch("run-1"));
    let pending = session
        .publish_batch(vec![draft("a", "a"), draft("b", "b")])
        .await
        .unwrap();
    // Rows may already be committed while their writer acknowledgement is still in flight.
    for record in pending.iter() {
        stored.insert((**record).clone());
    }
    let budget = Budget::default();
    let page = session.page(latest(5), &budget).await.unwrap();
    assert_eq!(sequences(&page.items), [1, 2, 3, 4, 5]);
    let reads = stored.reads.pages.lock().unwrap();
    assert_eq!(reads.len(), 1);
    assert_eq!(reads[0].ceiling, 3);
    assert_eq!(reads[0].query, Some(query()));
    assert_eq!(reads[0].demand.max_items, 3);
    let used = pending
        .iter()
        .map(|record| budget.item_bytes(&record.header, PayloadMode::Inline))
        .sum::<usize>();
    assert_eq!(
        reads[0].demand.max_bytes,
        demand(5).max_bytes - budget.fixed_bytes() - used
    );
    assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn class_and_typed_parent_indexes_never_budget_hidden_candidates() {
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    let call = ChatKey::new("call", "same").unwrap();
    let turn = ChatKey::new("turn", "same").unwrap();
    let mut drafts = vec![draft("main", "opaque bytes")];
    for seq in 0..4096 {
        let mut item = ChatDraft::new(format!("activity-{seq}"), "activity", Arc::from([255, 0]));
        item.parent_id = Some(if seq == 17 {
            call.clone()
        } else {
            turn.clone()
        });
        drafts.push(item);
    }
    session.publish_batch(drafts).await.unwrap();
    let budget = Budget::default();
    let main = session.page(latest(1), &budget).await.unwrap();
    assert_eq!(sequences(&main.items), [1]);
    assert!(budget.visited.lock().unwrap().iter().all(|seq| *seq == 1));
    budget.visited.lock().unwrap().clear();
    let scoped = ChatQuery::new("activity", Some(call));
    let children = session
        .page(ChatPageRequest::latest(scoped, demand(1)), &budget)
        .await
        .unwrap();
    assert_eq!(sequences(&children.items), [19]);
    assert!(budget.visited.lock().unwrap().iter().all(|seq| *seq == 19));
    assert!(stored.reads.pages.lock().unwrap().is_empty());
}

#[tokio::test]
async fn deferred_uses_encoded_envelope_budget_does_not_read_full_payload_and_continues() {
    let stored = Stored::with([record(1, "old")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    session
        .publish_batch(vec![draft("new", &"x".repeat(100_000))])
        .await
        .unwrap();
    let budget = Budget::default();
    let header = ChatItemHeader {
        item_id: "new".into(),
        append_seq: 2,
        query_class: "conversation".into(),
        parent_id: None,
        byte_length: 100_000,
    };
    let bytes = budget.fixed_bytes() + budget.item_bytes(&header, PayloadMode::Deferred);
    let page = session
        .page(
            ChatPageRequest::latest(query(), ReadDemand::new(10, bytes)),
            &budget,
        )
        .await
        .unwrap();
    assert_eq!(sequences(&page.items), [2]);
    assert_eq!(
        page.items[0].payload,
        PayloadData::Deferred {
            item_id: "new".into(),
            byte_length: 100_000
        }
    );
    assert!(
        stored.reads.pages.lock().unwrap().is_empty(),
        "no SQL when byte budget is exhausted"
    );
    let older = session
        .page(
            ChatPageRequest::before(page.before.unwrap(), demand(10)),
            &budget,
        )
        .await
        .unwrap();
    assert_eq!(sequences(&older.items), [1]);
    assert!(older.before.is_none());
    assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn history_deferred_selects_headers_without_fetching_the_oversized_blob() {
    let stored = Stored::with([record(1, &"x".repeat(100_000))]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let page = session
        .page(
            ChatPageRequest::latest(query(), ReadDemand::new(1, 250)),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert!(matches!(
        page.items[0].payload,
        PayloadData::Deferred {
            byte_length: 100_000,
            ..
        }
    ));
    assert_eq!(stored.reads.payload_bytes.load(Ordering::SeqCst), 0);
    assert_eq!(stored.reads.item.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn too_small_envelope_never_skips_a_large_newer_identity_to_fetch_old_rows() {
    let stored = Stored::with([record(1, "old")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    session
        .publish_batch(vec![draft(&"id".repeat(500), "payload")])
        .await
        .unwrap();
    assert!(matches!(
        session
            .page(
                ChatPageRequest::latest(query(), ReadDemand::new(5, 300)),
                &Budget::default()
            )
            .await,
        Err(ChatError::InvalidDemand(_))
    ));
    assert!(stored.reads.pages.lock().unwrap().is_empty());
}

#[tokio::test]
async fn a_partial_memory_byte_cut_stops_before_the_next_envelope_without_querying_old_small_rows()
{
    let stored = Stored::with([record(1, "old")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    let long_id = "id".repeat(500);
    session
        .publish_batch(vec![draft(&long_id, "middle"), draft("new", "new")])
        .await
        .unwrap();
    let budget = Budget::default();
    let page = session
        .page(
            ChatPageRequest::latest(query(), ReadDemand::new(10, 300)),
            &budget,
        )
        .await
        .unwrap();
    assert_eq!(sequences(&page.items), [3]);
    assert!(stored.reads.pages.lock().unwrap().is_empty());
    let older = session
        .page(
            ChatPageRequest::before(page.before.unwrap(), demand(10)),
            &budget,
        )
        .await
        .unwrap();
    assert_eq!(sequences(&older.items), [1, 2]);
    assert_eq!(stored.reads.pages.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn capture_before_commit_clear_retains_arcs_and_fixed_h0_while_new_publication_continues() {
    let stored = Stored::with([record(1, "one")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("two", "two")])
        .await
        .unwrap();
    let read = {
        let session = session.clone();
        tokio::spawn(async move { session.page(latest(10), &Budget::default()).await })
    };
    gate.entered().await;
    stored.insert((*records[0]).clone());
    session.confirm_durable(2).unwrap();
    session
        .publish_batch(vec![draft("three", "three")])
        .await
        .unwrap();
    gate.release();
    let page = read.await.unwrap().unwrap();
    assert_eq!(page.ceiling, 2);
    assert_eq!(sequences(&page.items), [1, 2]);
    assert_eq!(stored.reads.pages.lock().unwrap()[0].ceiling, 1);
    if let PayloadData::Inline(bytes) = &page.items[1].payload {
        assert!(Arc::ptr_eq(bytes, &records[0].payload));
    } else {
        panic!("small payload");
    }
    // After clear, the newly opened short snapshot sees the committed prefix, still limited to H0.
    gate.release();
    let mut fixed = latest(10);
    fixed.ceiling = Some(2);
    let page = session.page(fixed, &Budget::default()).await.unwrap();
    assert_eq!(sequences(&page.items), [1, 2]);
    assert_eq!(stored.reads.pages.lock().unwrap()[1].ceiling, 2);
}

#[tokio::test]
async fn continuation_is_exclusive_scope_and_epoch_bound_and_keeps_h0() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let mut hidden = draft("hidden", "bytes");
    hidden.query_class = "activity".into();
    session
        .publish_batch(vec![draft("a", "a"), hidden, draft("b", "b")])
        .await
        .unwrap();
    let page = session.page(latest(1), &Budget::default()).await.unwrap();
    assert_eq!(sequences(&page.items), [3]);
    let cursor = page.before.unwrap();
    session.publish_batch(vec![draft("c", "c")]).await.unwrap();
    let older = session
        .page(
            ChatPageRequest::before(cursor.clone(), demand(5)),
            &Budget::default(),
        )
        .await
        .unwrap();
    assert_eq!(sequences(&older.items), [1]);
    assert_eq!(older.ceiling, 3);
    let mut wrong = ChatPageRequest::before(cursor.clone(), demand(5));
    wrong.query = ChatQuery::new("activity", None);
    assert!(matches!(
        session.page(wrong, &Budget::default()).await,
        Err(ChatError::InvalidArgument(_))
    ));
    let other = Session::new(Stored::default(), epoch("run-2"));
    assert!(matches!(
        other
            .page(
                ChatPageRequest::before(cursor, demand(5)),
                &Budget::default()
            )
            .await,
        Err(ChatError::EpochMismatch { .. })
    ));
}

#[tokio::test]
async fn invalid_demands_and_a_future_ceiling_are_typed_errors() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    for demand in [
        ReadDemand::new(0, 1024),
        ReadDemand::new(MAX_READ_ITEMS + 1, 1024),
        ReadDemand::new(1, 64),
        ReadDemand::new(1, MAX_READ_BYTES + 1),
    ] {
        assert!(matches!(
            session
                .page(ChatPageRequest::latest(query(), demand), &Budget::default())
                .await,
            Err(ChatError::InvalidDemand(_))
        ));
    }
    let mut request = latest(1);
    request.ceiling = Some(1);
    assert!(matches!(
        session.page(request, &Budget::default()).await,
        Err(ChatError::InvalidArgument(_))
    ));
}

#[tokio::test]
async fn cancelled_page_releases_capture_and_history_failure_is_not_eof_or_memory_fallback() {
    let stored = Stored::with([record(1, "one")]);
    let gate = Arc::new(HistoryGate::new());
    let mut history = GatedHistory::new(stored.clone());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history, epoch("run-1"));
    let records = session
        .publish_batch(vec![draft("two", "two")])
        .await
        .unwrap();
    let references = Arc::strong_count(&records[0]);
    let read = {
        let session = session.clone();
        tokio::spawn(async move { session.page(latest(10), &Budget::default()).await })
    };
    gate.entered().await;
    assert_eq!(Arc::strong_count(&records[0]), references + 1);
    read.abort();
    assert!(read.await.unwrap_err().is_cancelled());
    assert_eq!(Arc::strong_count(&records[0]), references);
    stored.fail_page.store(true, Ordering::SeqCst);
    gate.release();
    assert!(matches!(
        session.page(latest(10), &Budget::default()).await,
        Err(ChatError::History(_))
    ));
    gate.release();
    assert_eq!(
        sequences(
            &session
                .page(latest(10), &Budget::default())
                .await
                .unwrap()
                .items
        ),
        [1, 2]
    );
}
