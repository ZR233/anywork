//! 冻结详情契约：按记录、字段与字节偏移分块读取完整正文。
//!
//! 详情绑定不可变记录身份与字段身份，没有内容版本；pending 记录从内存完整正文应答，已确认记录从
//! 存储读取一次；continuation 绑定记录与字段并在 UTF-8 边界上推进；不存在字段与空字段分开。

#[path = "support/timeline.rs"]
mod support;

use std::{sync::Arc, time::Duration};

use pl_core::chat::{ChatDetailCursor, ChatDetailRequest, ChatError, ChatField, Session};
use support::{
    Counting, GatedHistory, HistoryGate, Stored, draft, epoch, record_identified,
    record_with_fields,
};

/// Reads one field to the end through its continuations and returns the joined text.
async fn read_all(
    session: &Session,
    item_id: &str,
    field: ChatField,
    block_bytes: usize,
) -> String {
    let mut request = ChatDetailRequest::new(item_id, field).with_max_bytes(block_bytes);
    let mut joined = String::new();
    loop {
        let chunk = session
            .read_detail(request.clone())
            .await
            .expect("the detail block is readable");
        joined.push_str(&chunk.text);
        let Some(next) = chunk.continuation else {
            return joined;
        };
        request = request.with_continuation(next);
    }
}

#[tokio::test]
async fn a_multibyte_field_is_read_in_utf8_aligned_blocks_that_join_into_the_original() {
    let body = "汉语文本 mixed with English and an emoji 📖 plus more text to span several blocks";
    let stored = Stored::with([record_identified("x", 1, body)]);
    let session = Session::new(stored, epoch("run-1"));
    let joined = read_all(&session, "x", ChatField::Body, 7).await;
    assert_eq!(joined, body, "every block boundary respects UTF-8");
}

#[tokio::test]
async fn a_durable_record_whose_page_preview_was_bounded_still_yields_its_whole_body() {
    let body = "x".repeat(300 * 1024);
    let stored = Stored::with([record_identified("x", 1, &body)]);
    let session = Session::new(stored, epoch("run-1"));
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest())
        .await
        .expect("the page is readable");
    let preview = &page.items[0];
    assert!(
        preview.omitted_bytes() > 0,
        "the page carries a bounded preview of the oversized body"
    );
    let joined = read_all(&session, "x", ChatField::Body, 64 * 1024).await;
    assert_eq!(joined.len(), body.len());
    assert_eq!(joined, body, "detail serves the complete frozen body");
}

#[tokio::test]
async fn a_missing_field_is_distinct_from_an_empty_field() {
    let stored = Stored::with([record_with_fields(
        "x",
        1,
        [
            (ChatField::Body, String::new()),
            (ChatField::host("args"), "arguments".to_owned()),
        ],
    )]);
    let session = Session::new(stored, epoch("run-1"));
    let empty = session
        .read_detail(ChatDetailRequest::new("x", ChatField::Body))
        .await
        .expect("an empty field is a readable field");
    assert_eq!(empty.text, "");
    assert_eq!(empty.total_bytes, 0);
    assert_eq!(empty.continuation, None, "an empty field is complete");
    let error = session
        .read_detail(ChatDetailRequest::new("x", ChatField::host("result")))
        .await
        .expect_err("a field the record never carried is not found");
    assert!(matches!(error, ChatError::NotFound(_)));
    let error = session
        .read_detail(ChatDetailRequest::new("missing", ChatField::Body))
        .await
        .expect_err("an unknown record is not found");
    assert!(matches!(error, ChatError::NotFound(_)));
}

#[tokio::test]
async fn an_unsupported_block_size_is_rejected_instead_of_quietly_widened() {
    let stored = Stored::with([record_identified("x", 1, "body")]);
    let session = Session::new(stored, epoch("run-1"));
    for block_bytes in [3, 256 * 1024 + 1] {
        let error = session
            .read_detail(ChatDetailRequest::new("x", ChatField::Body).with_max_bytes(block_bytes))
            .await
            .expect_err("an unsupported block size is rejected");
        assert!(matches!(error, ChatError::InvalidArgument(_)));
    }
}

#[tokio::test]
async fn a_continuation_inside_a_code_point_is_rejected() {
    let stored = Stored::with([record_identified("x", 1, "汉")]);
    let session = Session::new(stored, epoch("run-1"));
    // The first byte of the three-byte scalar is not a UTF-8 boundary.
    let error =
        session
            .read_detail(
                ChatDetailRequest::new("x", ChatField::Body)
                    .with_continuation(ChatDetailCursor::new("x", ChatField::Body, 1)),
            )
            .await
            .expect_err("an offset inside a code point is rejected");
    assert!(matches!(error, ChatError::InvalidArgument(_)));
}

#[tokio::test]
async fn a_continuation_is_bound_to_its_item_and_field() {
    let stored = Stored::with([record_with_fields(
        "x",
        1,
        [
            (ChatField::Body, "body".repeat(90 * 1024)),
            (ChatField::host("args"), "arguments".repeat(90 * 1024)),
        ],
    )]);
    let session = Session::new(stored, epoch("run-1"));
    let chunk = session
        .read_detail(ChatDetailRequest::new("x", ChatField::Body))
        .await
        .expect("the first block is readable");
    let continuation = chunk.continuation.expect("the body continues");
    let error = session
        .read_detail(
            ChatDetailRequest::new("x", ChatField::host("args"))
                .with_continuation(continuation.clone()),
        )
        .await
        .expect_err("a continuation of another field is rejected");
    assert!(matches!(error, ChatError::InvalidArgument(_)));
    let error = session
        .read_detail(ChatDetailRequest::new("y", ChatField::Body).with_continuation(continuation))
        .await
        .expect_err("a continuation of another record is rejected");
    assert!(matches!(error, ChatError::InvalidArgument(_)));
}

#[tokio::test]
async fn a_pending_record_is_served_from_memory_without_storage_io() {
    let counting = Counting::new(Stored::default());
    let session = Session::new(counting.clone(), epoch("run-1"));
    let body = "y".repeat(100 * 1024);
    session
        .publish_batch(vec![draft("x", &body)])
        .await
        .expect("the completion is admitted, writer paused");
    let reads_before_detail = counting
        .item_reads
        .load(std::sync::atomic::Ordering::SeqCst);
    let joined = read_all(&session, "x", ChatField::Body, 64 * 1024).await;
    assert_eq!(
        joined, body,
        "the whole frozen body is readable while pending"
    );
    assert_eq!(
        counting
            .item_reads
            .load(std::sync::atomic::Ordering::SeqCst),
        reads_before_detail,
        "a pending record is served without any storage read"
    );
}

#[tokio::test]
async fn a_committed_record_detail_reads_storage_once() {
    let counting = Counting::new(Stored::with([record_identified("x", 1, "body")]));
    let session = Session::new(counting.clone(), epoch("run-1"));
    let chunk = session
        .read_detail(ChatDetailRequest::new("x", ChatField::Body))
        .await
        .expect("the committed record is readable");
    assert_eq!(chunk.text, "body");
    assert_eq!(
        counting
            .item_reads
            .load(std::sync::atomic::Ordering::SeqCst),
        1,
        "one detail read of a reclaimed record is one storage read"
    );
}

#[tokio::test]
async fn a_cancelled_detail_read_publishes_nothing_and_leaves_the_session_usable() {
    let history = GatedHistory::new(Stored::with([record_identified("x", 1, "body")]));
    let gate = Arc::new(HistoryGate::new());
    let gated = {
        let mut gated = history;
        gated.item_gate = Some(gate.clone());
        gated
    };
    let session = Session::new(gated, epoch("run-1"));
    let mut read = Box::pin(session.read_detail(ChatDetailRequest::new("x", ChatField::Body)));
    tokio::time::timeout(Duration::from_secs(2), async {
        tokio::select! {
            () = gate.entered() => {}
            result = &mut read => panic!("the gated read completed before cancellation: {result:?}"),
        }
    })
    .await
    .expect("the detail future is polled into the storage barrier");
    drop(read);
    // The cancelled read publishes no partial result, and the session keeps working.
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest())
        .await
        .expect("pages are unaffected by the cancelled detail read");
    assert_eq!(page.items.len(), 1);
    gate.release();
    let chunk = session
        .read_detail(ChatDetailRequest::new("x", ChatField::Body))
        .await
        .expect("a fresh detail read completes once the gate opens");
    assert_eq!(chunk.text, "body");
}
