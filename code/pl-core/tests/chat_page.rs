//! 完成页契约：Latest/Before keyset 分页、有界预算与统一合并校验。
//!
//! 页读取从 pending 与持久化两个有界来源合并：同身份/同序号的不同载荷必须报类型化冲突，捕获与
//! 提交交错不丢不重；`has_older` 只来自真实存在性证明；预算截页保留真实更旧边界；旧代际游标即使
//! 被当前 head 追过也按代际失配拒绝。

#[path = "support/timeline.rs"]
mod support;

use std::sync::Arc;

use pl_core::chat::{
    ChatCursor, ChatError, ChatField, ChatHistory, ChatPageRequest, Session, TimelineEpoch,
    presentation_prefix,
};
use support::{
    BoundedReads, FailsOnce, GatedHistory, HistoryGate, Stored, draft, epoch, record,
    record_identified, record_with_fields,
};

#[tokio::test]
async fn pending_and_stored_records_merge_into_one_contiguous_page() {
    let stored = Stored::with([record(1, "one"), record(2, "two")]);
    let session = Session::new(stored.clone(), epoch("run-1"));
    // A third completion is visible in memory while the writer has not confirmed it yet.
    session
        .publish_batch(vec![draft("item-3", "three")])
        .await
        .expect("the completion is admitted");
    let page = session
        .page(ChatPageRequest::latest())
        .await
        .expect("the page is readable");
    let sequences: Vec<u64> = page.items.iter().map(|item| item.append_seq).collect();
    assert_eq!(sequences, [1, 2, 3], "no hole and no duplicate identity");
    assert!(!page.has_older, "nothing is older than the durable start");
    assert_eq!(stored.len(), 2, "the pending tail is not in storage yet");
}

#[tokio::test]
async fn has_older_only_comes_from_a_real_older_row() {
    let stored = Stored::with([record(1, "one"), record(2, "two"), record(3, "three")]);
    let session = Session::new(stored, epoch("run-1"));
    let page = session
        .page(ChatPageRequest::latest().with_limit(2))
        .await
        .expect("the page is readable");
    assert_eq!(page.items.len(), 2);
    assert!(page.has_older, "the dropped candidate proves an older row");
    let before = page.before.expect("a real boundary is returned");
    assert_eq!(
        before.append_seq, 2,
        "the boundary names this page's oldest row"
    );
    // The next page is strictly older and does not repeat the boundary row.
    let older = session
        .page(ChatPageRequest::before(before))
        .await
        .expect("the older page is readable");
    let sequences: Vec<u64> = older.items.iter().map(|item| item.append_seq).collect();
    assert_eq!(sequences, [1]);
    assert!(!older.has_older);
    // A short page is not EOF on its own: the same store with the default limit still reports the
    // real boundary only when a row was actually dropped.
    let full = session
        .page(ChatPageRequest::latest())
        .await
        .expect("the full page is readable");
    assert_eq!(full.items.len(), 3);
    assert!(
        !full.has_older,
        "no row was dropped, so no older history is claimed"
    );
}

#[tokio::test]
async fn an_explicit_limit_outside_the_supported_range_is_rejected() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    for limit in [0, 101] {
        let error = session
            .page(ChatPageRequest::latest().with_limit(limit))
            .await
            .expect_err("an unsupported limit is rejected");
        assert!(matches!(error, ChatError::InvalidArgument(_)));
    }
}

#[tokio::test]
async fn every_page_read_is_bounded_by_the_requested_window() {
    let stored = Stored::with((1..=50).map(|seq| record(seq, "row")));
    let bounded = BoundedReads::new(stored);
    let session = Session::new(bounded.clone(), epoch("run-1"));
    session
        .page(ChatPageRequest::latest().with_limit(5))
        .await
        .expect("the page is readable");
    assert_eq!(
        *bounded.largest_page.lock().unwrap(),
        5,
        "storage is asked for at most the requested page"
    );
}

#[tokio::test]
async fn the_page_preview_budget_truncates_the_oldest_end_and_keeps_a_real_boundary() {
    let fat: Vec<_> = (1..=10)
        .map(|seq| record(seq, &"x".repeat(300 * 1024)))
        .collect();
    let stored = Stored::with(fat);
    let session = Session::new(stored, epoch("run-1"));
    let page = session
        .page(ChatPageRequest::latest())
        .await
        .expect("the page is readable");
    assert!(
        page.items.len() < 10,
        "the byte budget cuts the page before the item limit"
    );
    assert!(page.has_older, "a budget cut proves older content exists");
    let before = page.before.expect("the boundary survives the cut");
    let older = session
        .page(ChatPageRequest::before(before))
        .await
        .expect("the older page is readable");
    assert!(!older.items.is_empty(), "paging continues across the cut");
}

#[tokio::test]
async fn a_cursor_boundary_is_strict_and_rejects_the_row_it_names() {
    let stored = Stored::with([record(1, "one"), record(2, "two"), record(3, "three")]);
    let session = Session::new(stored, epoch("run-1"));
    let boundary = ChatCursor::new(
        TimelineEpoch::new("run-1").unwrap(),
        2,
        record(2, "two").item_id,
    );
    let page = session
        .page(ChatPageRequest::before(boundary))
        .await
        .expect("the page is readable");
    let sequences: Vec<u64> = page.items.iter().map(|item| item.append_seq).collect();
    assert_eq!(sequences, [1], "the boundary row itself is excluded");
}

#[tokio::test]
async fn a_cursor_from_another_epoch_is_rejected_even_when_the_head_moved_past_it() {
    let stored = Stored::with([record(1, "one"), record(2, "two")]);
    // A cursor the previous run minted; the rebuilt run's head will move past it.
    let stale_cursor = ChatCursor::of(&epoch("previous-run"), &record(1, "one"));
    let rebuilt = Session::new(stored.clone(), epoch("rebuilt"));
    let latest = rebuilt
        .publish_batch(vec![draft("item-4", "a fresh completion")])
        .await
        .expect("the rebuilt run publishes again");
    assert!(
        latest[0].append_seq > stale_cursor.append_seq,
        "the new head has moved past the stale cursor"
    );
    let error = rebuilt
        .page(ChatPageRequest::before(stale_cursor.clone()))
        .await
        .expect_err("a stale-generation cursor is rejected");
    assert!(matches!(error, ChatError::EpochMismatch { .. }));
    let error = rebuilt
        .page(ChatPageRequest::before(stale_cursor))
        .await
        .expect_err("the rejection is stable, not a one-shot race");
    assert!(matches!(error, ChatError::EpochMismatch { .. }));
}

#[tokio::test]
async fn an_empty_store_returns_an_empty_page_and_never_a_fake_boundary() {
    let session = Session::new(Stored::default(), epoch("run-1"));
    let page = session
        .page(ChatPageRequest::latest())
        .await
        .expect("the empty page is readable");
    assert!(page.items.is_empty());
    assert_eq!(page.before, None);
    assert!(!page.has_older);
    assert_eq!(
        page.epoch,
        epoch("run-1"),
        "the page carries its generation"
    );
}

#[tokio::test]
async fn a_storage_failure_is_reported_instead_of_looking_like_the_beginning_of_history() {
    let failing = FailsOnce::new(Stored::with([record(1, "one")]));
    let session = Session::new(failing.clone(), epoch("run-1"));
    failing
        .fail_next_page
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let error = session
        .page(ChatPageRequest::latest())
        .await
        .expect_err("the storage failure propagates");
    assert!(matches!(error, ChatError::History(_)));
    // The failure is not sticky: the next read answers normally.
    let page = session
        .page(ChatPageRequest::latest())
        .await
        .expect("the next read is readable");
    assert_eq!(page.items.len(), 1);
}

#[tokio::test]
async fn a_page_keeps_its_captured_head_when_a_completion_is_published_during_io() {
    let stored = Stored::with([record(1, "one")]);
    let history = GatedHistory::new(stored);
    let gate = Arc::new(HistoryGate::new());
    let gated = {
        let mut gated = history;
        gated.page_gate = Some(gate.clone());
        gated
    };
    let session = Session::new(gated, epoch("run-1"));
    let paging = session.clone();
    let read = tokio::spawn(async move { paging.page(ChatPageRequest::latest()).await });
    gate.entered().await;
    // The completion lands while the storage read is held open.
    session
        .publish_batch(vec![draft("item-2", "two")])
        .await
        .expect("the completion is admitted");
    gate.release();
    let page = read.await.expect("the read finishes").expect("it succeeds");
    let sequences: Vec<u64> = page.items.iter().map(|item| item.append_seq).collect();
    assert_eq!(
        sequences,
        [1],
        "a page stays at its captured head; later publications belong to the tail"
    );
}

#[tokio::test]
async fn a_commit_that_lands_during_a_page_read_does_not_duplicate_or_lose_the_record() {
    let stored = Stored::default();
    let history = GatedHistory::new(stored.clone());
    let gate = Arc::new(HistoryGate::new());
    let gated = {
        let mut gated = history;
        gated.page_gate = Some(gate.clone());
        gated
    };
    let session = Session::new(gated, epoch("run-1"));
    let published = session
        .publish_batch(vec![draft("item-1", "one")])
        .await
        .expect("the completion is admitted");
    let paging = session.clone();
    let read = tokio::spawn(async move { paging.page(ChatPageRequest::latest()).await });
    gate.entered().await;
    // The writer lands the row and confirms the prefix while the read is held open: the captured
    // pending reference and the fresh storage row must collapse into one record.
    stored.insert(published[0].as_ref().clone());
    session
        .confirm_durable(1)
        .expect("the durable prefix is confirmed");
    gate.release();
    let page = read.await.expect("the read finishes").expect("it succeeds");
    assert_eq!(page.items.len(), 1, "both sources agree on one record");
    assert_eq!(page.items[0].item_id, "item-1");
}

#[tokio::test]
async fn divergent_payloads_across_sources_are_a_typed_conflict() {
    // Same identity, same sequence, a different body.
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    session
        .publish_batch(vec![draft("x", "the sealed body")])
        .await
        .expect("the completion is admitted");
    stored.insert(record_identified("x", 1, "a divergent durable body"));
    let error = session
        .page(ChatPageRequest::latest())
        .await
        .expect_err("one identity with two payloads cannot be merged");
    assert!(matches!(error, ChatError::Conflict(_)));

    // Same sequence claimed by two identities.
    let stored = Stored::default();
    let session = Session::new(stored.clone(), epoch("run-1"));
    session
        .publish_batch(vec![draft("x", "the sealed body")])
        .await
        .expect("the completion is admitted");
    stored.insert(record_identified(
        "y",
        1,
        "another identity at the same sequence",
    ));
    let error = session
        .page(ChatPageRequest::latest())
        .await
        .expect_err("one sequence with two identities cannot be merged");
    assert!(matches!(error, ChatError::Conflict(_)));
}

#[test]
fn preview_structure_accounting_charges_identities_and_host_keys() {
    let identity = "i".repeat(300);
    let key: Arc<str> = Arc::from("k".repeat(500).as_str());
    let record = record_with_fields(
        &identity,
        1,
        [
            (ChatField::Body, "body".to_owned()),
            (ChatField::host(key), "host".to_owned()),
        ],
    );
    // 128 record + 2 meta + 300 identity + 2 * 128 fields + 500 host key bytes.
    assert_eq!(
        record.preview_structure_bytes(),
        128 + 2 + 300 + 2 * 128 + 500
    );
}

#[test]
fn an_unshrinkable_structure_over_budget_is_a_typed_resource_limit() {
    let fat: Vec<_> = (0..3000)
        .map(|index| (ChatField::host(format!("key-{index}")), "x".to_owned()))
        .collect();
    let record = record_with_fields("x", 1, fat);
    let error = ChatHistory::bounded(&Stored::default(), &record)
        .expect_err("an unshrinkable structure cannot be previewed");
    assert!(matches!(error, ChatError::Overloaded(_)));
}

#[test]
fn the_structure_share_reduces_the_body_cap_without_rewriting_identity_or_total() {
    let meta = Arc::from(vec![b'm'; 100 * 1024]);
    let record = record_identified("x", 1, &"b".repeat(200 * 1024));
    let mut heavy = record.clone();
    heavy.meta = meta;
    let preview = ChatHistory::bounded(&Stored::default(), &heavy)
        .expect("the preview fits once the body share is reduced");
    let body = preview.body().expect("the body field survives");
    let structure = preview.preview_structure_bytes();
    assert!(
        body.len() + structure <= 256 * 1024,
        "structure and body fit the single-record budget"
    );
    assert!(
        body.len() < 200 * 1024,
        "the structure share reduces the body bytes actually kept"
    );
    assert_eq!(
        preview.field_total_bytes(&ChatField::Body),
        Some(200 * 1024),
        "the complete length is not rewritten by the cut"
    );
    assert_eq!(preview.item_id, record.item_id);
}

#[test]
fn presentation_identities_stay_product_stable() {
    // The ID helpers remain the stable business identity source for completion records.
    let id = support::presentation("attempt-1", "part-1");
    assert!(id.starts_with(&presentation_prefix("attempt-1")));
    assert!(id.ends_with(":text:0"));
}
