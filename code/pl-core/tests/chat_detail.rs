//! 按身份详情：UTF-8 分块续读、版本绑定、不存在与空字段、非法块与取消。

#[path = "support/timeline.rs"]
mod timeline_support;

use std::sync::Arc;

use pl_core::chat::{
    CHAT_ITEM_PREVIEW_BYTES, ChatDetailCursor, ChatDetailRequest, ChatError, ChatField,
    MIN_DETAIL_BYTES, Session,
};
use timeline_support::*;

/// Reads a whole field through the public continuation loop.
async fn read_all(
    session: &Session,
    item_id: &str,
    field: ChatField,
    revision: u64,
    max_bytes: usize,
) -> (String, u64, usize) {
    let mut text = String::new();
    let mut continuation = None;
    let mut blocks = 0usize;
    let mut total = 0u64;
    loop {
        let mut request =
            ChatDetailRequest::new(item_id, field.clone(), revision).with_max_bytes(max_bytes);
        if let Some(cursor) = continuation {
            request = request.with_continuation(cursor);
        }
        let chunk = session.read_detail(request).await.unwrap();
        assert!(!chunk.text.is_empty(), "a non-empty block must advance");
        if blocks > 0 {
            assert_eq!(chunk.total_bytes, total, "the total length is stable");
        }
        total = chunk.total_bytes;
        text.push_str(&chunk.text);
        blocks += 1;
        match chunk.continuation.clone() {
            Some(next) => {
                assert_eq!(
                    next.offset() as usize,
                    text.len(),
                    "the continuation advances to the bytes just delivered"
                );
                continuation = Some(next);
            }
            None => break,
        }
    }
    (text, total, blocks)
}

#[tokio::test]
async fn a_multibyte_field_is_read_in_utf8_aligned_blocks_that_join_into_the_original() {
    // Three-byte and four-byte code points make a naive byte split land inside a code point.
    let text = "中文🙂abc".repeat(2048);
    let session = Session::new(Stored::default());
    session
        .publish(identified("item-1", 1, 3, &text, true))
        .unwrap();

    let (read, total, blocks) =
        read_all(&session, "item-1", ChatField::Body, 3, MIN_DETAIL_BYTES).await;

    assert_eq!(read, text);
    assert_eq!(total, text.len() as u64);
    assert!(blocks > 1, "the field must span several bounded blocks");
}

#[tokio::test]
async fn a_durable_item_whose_preview_was_bounded_still_yields_its_whole_body() {
    // Just past the per-item preview budget, so the page cannot return the whole body.
    let text = "£".repeat(CHAT_ITEM_PREVIEW_BYTES / 2 + 1024);
    let history = Counting::new(Stored::with([item(1, 7, &text, true)]));
    let reads = history.item_reads.clone();
    let session = Session::new(history);

    let page = session
        .page(pl_core::chat::ChatPageRequest::latest())
        .await
        .unwrap();
    let preview = &page.items[0];
    assert!(
        (preview.body().unwrap().len() as u64)
            < preview.field_total_bytes(&ChatField::Body).unwrap(),
        "the page returns a bounded preview, not the whole body"
    );
    assert!(preview.omitted_bytes() > 0);

    let (read, total, _) = read_all(&session, "item-1", ChatField::Body, 7, 64 * 1024).await;
    assert_eq!(read, text);
    assert_eq!(total, text.len() as u64);
    assert!(
        reads.load(std::sync::atomic::Ordering::Relaxed) >= 1,
        "the complete body comes from durable history"
    );
}

#[tokio::test]
async fn a_changed_revision_is_reported_stale_and_never_spliced_into_one_text() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 1, "first", false)).unwrap();
    let first = session
        .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 1))
        .await
        .unwrap();
    assert_eq!(first.text, "first");
    assert_eq!(first.continuation, None);

    session
        .publish(appended(&item(1, 1, "first", false), 2, " second"))
        .unwrap();
    let stale = session
        .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 1))
        .await;
    assert!(matches!(
        stale,
        Err(ChatError::StaleRevision { revision: 1, .. })
    ));

    let current = session
        .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 2))
        .await
        .unwrap();
    assert_eq!(current.text, "first second");
}

#[tokio::test]
async fn a_missing_field_is_distinct_from_an_empty_field() {
    let session = Session::new(Stored::default());
    session
        .publish(with_fields(
            "item-1",
            1,
            1,
            [(ChatField::Body, String::new())],
            true,
        ))
        .unwrap();

    let empty = session
        .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 1))
        .await
        .unwrap();
    assert_eq!(empty.text, "");
    assert_eq!(empty.total_bytes, 0);
    assert_eq!(empty.continuation, None);

    let missing = session
        .read_detail(ChatDetailRequest::new(
            "item-1",
            ChatField::host("tool.absent"),
            1,
        ))
        .await;
    assert!(matches!(missing, Err(ChatError::NotFound(_))));

    let unknown_item = session
        .read_detail(ChatDetailRequest::new("absent", ChatField::Body, 1))
        .await;
    assert!(matches!(unknown_item, Err(ChatError::NotFound(_))));
}

#[tokio::test]
async fn an_unsupported_block_size_is_rejected_instead_of_quietly_widened() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 1, "body", true)).unwrap();
    for rejected in [0usize, 1, MIN_DETAIL_BYTES - 1, 256 * 1024 + 1] {
        assert!(matches!(
            session
                .read_detail(
                    ChatDetailRequest::new("item-1", ChatField::Body, 1).with_max_bytes(rejected)
                )
                .await,
            Err(ChatError::InvalidArgument(_))
        ));
    }
}

#[tokio::test]
async fn a_continuation_inside_a_code_point_is_rejected() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 1, "中文", true)).unwrap();
    // `中` occupies bytes 0..3, so offset 1 is inside a code point.
    let illegal = session
        .read_detail(
            ChatDetailRequest::new("item-1", ChatField::Body, 1)
                .with_continuation(ChatDetailCursor::new("item-1", ChatField::Body, 1, 1)),
        )
        .await;
    assert!(matches!(illegal, Err(ChatError::InvalidArgument(_))));

    let past_end = session
        .read_detail(
            ChatDetailRequest::new("item-1", ChatField::Body, 1)
                .with_continuation(ChatDetailCursor::new("item-1", ChatField::Body, 1, 999)),
        )
        .await;
    assert!(matches!(past_end, Err(ChatError::InvalidArgument(_))));
}

#[tokio::test]
async fn a_cancelled_detail_read_publishes_nothing_and_leaves_the_session_usable() {
    let mut history = GatedHistory::new(Stored::with([item(1, 1, "durable", true)]));
    let gate = Arc::new(HistoryGate::new());
    history.item_gate = Some(gate.clone());
    let session = Session::new(history);

    let read = tokio::spawn({
        let session = session.clone();
        async move {
            session
                .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 1))
                .await
        }
    });
    gate.entered().await;
    read.abort();
    // The cancelled future published no partial result and no version.
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest())
        .await
        .unwrap();
    assert_eq!(page.items.len(), 1);
    assert!(page.items[0].body().is_some());
}

/// 详情 continuation 绑定 item／field／revision：跨字段、跨条目或跨版本复用必须明确拒绝。
#[tokio::test]
async fn a_continuation_is_bound_to_its_item_field_and_revision() {
    let result_field = ChatField::host("tool.result");
    let session = Session::new(Stored::default());
    session
        .publish(with_fields(
            "item-1",
            1,
            1,
            [
                (ChatField::Body, "0123456789abcdef".to_owned()),
                (result_field.clone(), "result body".to_owned()),
            ],
            false,
        ))
        .unwrap();
    session
        .publish(with_fields(
            "item-2",
            2,
            1,
            [(ChatField::Body, "0123456789abcdef".to_owned())],
            true,
        ))
        .unwrap();
    let first = session
        .read_detail(
            ChatDetailRequest::new("item-1", ChatField::Body, 1).with_max_bytes(MIN_DETAIL_BYTES),
        )
        .await
        .unwrap();
    let continuation = first
        .continuation
        .clone()
        .expect("a longer field continues");
    assert_eq!(continuation.offset() as usize, first.text.len());
    assert_eq!(continuation.item_id(), "item-1");
    assert_eq!(continuation.field(), &ChatField::Body);
    assert_eq!(continuation.revision(), 1);

    // The token keeps working in its own context.
    let next = session
        .read_detail(
            ChatDetailRequest::new("item-1", ChatField::Body, 1)
                .with_max_bytes(MIN_DETAIL_BYTES)
                .with_continuation(continuation.clone()),
        )
        .await
        .unwrap();
    assert!(!next.text.is_empty());

    // Reusing it for another field of the same item is rejected, not silently read.
    let other_field = session
        .read_detail(
            ChatDetailRequest::new("item-1", result_field.clone(), 1)
                .with_max_bytes(MIN_DETAIL_BYTES)
                .with_continuation(continuation.clone()),
        )
        .await;
    assert!(matches!(other_field, Err(ChatError::InvalidArgument(_))));

    // Reusing it for another identity is rejected.
    let other_item = session
        .read_detail(
            ChatDetailRequest::new("item-2", ChatField::Body, 1)
                .with_max_bytes(MIN_DETAIL_BYTES)
                .with_continuation(continuation.clone()),
        )
        .await;
    assert!(matches!(other_item, Err(ChatError::InvalidArgument(_))));

    // Reusing it for another revision is rejected.
    session
        .publish(with_fields(
            "item-1",
            1,
            2,
            [
                (ChatField::Body, "0123456789abcdef plus".to_owned()),
                (result_field, "result body".to_owned()),
            ],
            false,
        ))
        .unwrap();
    let other_revision = session
        .read_detail(
            ChatDetailRequest::new("item-1", ChatField::Body, 2)
                .with_max_bytes(MIN_DETAIL_BYTES)
                .with_continuation(continuation),
        )
        .await;
    assert!(matches!(other_revision, Err(ChatError::InvalidArgument(_))));
}

/// 冷读挂起期间出现更高 revision：不能拿 SQL 旧行冒充当前正文。
///
/// 内存里同一 identity 只有更高 revision 的**预览**（字段不完整），因此旧实现会直接回落到 SQL 并
/// 成功返回旧版本；读后同一权威再核必须报过期。
#[tokio::test]
async fn a_cold_detail_read_that_awaited_a_newer_revision_reports_stale() {
    let durable = item(1, 3, "abcdefgh", false);
    let mut history = GatedHistory::new(Stored::with([durable.clone()]));
    let gate = Arc::new(HistoryGate::new());
    history.item_gate = Some(gate.clone());
    let session = Session::new(history);
    let mut newer = durable.clone();
    newer.revision = 4;
    session.publish_preview(preview_of(&newer, 4)).unwrap();

    let read = tokio::spawn({
        let session = session.clone();
        async move {
            session
                .read_detail(ChatDetailRequest::new("item-1", ChatField::Body, 3))
                .await
        }
    });
    gate.entered().await;
    gate.release();
    let result = read.await.unwrap();
    assert!(
        matches!(
            result,
            Err(ChatError::StaleRevision {
                revision: 3,
                ref item_id,
                ..
            }) if item_id == "item-1"
        ),
        "the cold row must not answer for a newer session revision"
    );
}

/// 冷读挂起期间字段被移除且 revision 前进：同样不能返回旧快照。
#[tokio::test]
async fn a_detail_read_that_awaited_a_field_removal_never_serves_the_old_snapshot() {
    let result_field = ChatField::host("tool.result");
    let durable = with_fields(
        "item-1",
        1,
        3,
        [
            (ChatField::Body, "abcdefgh".to_owned()),
            (result_field.clone(), "old result".to_owned()),
        ],
        false,
    );
    let mut history = GatedHistory::new(Stored::with([durable.clone()]));
    let gate = Arc::new(HistoryGate::new());
    history.item_gate = Some(gate.clone());
    let session = Session::new(history);
    session.publish_preview(preview_of(&durable, 4)).unwrap();

    let read = tokio::spawn({
        let session = session.clone();
        let result_field = result_field.clone();
        async move {
            session
                .read_detail(ChatDetailRequest::new("item-1", result_field, 3))
                .await
        }
    });
    gate.entered().await;
    // 挂起期间：更高 revision，且该字段被移除。
    let mut next = with_fields(
        "item-1",
        1,
        4,
        [(ChatField::Body, "abcdefgh".to_owned())],
        false,
    );
    next.saved = false;
    session.publish(next).unwrap();
    gate.release();

    let result = read.await.unwrap();
    assert!(matches!(
        result,
        Err(ChatError::StaleRevision { revision: 3, .. })
    ));
}
