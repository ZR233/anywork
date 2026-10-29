//! 生产与保存准入的不变量：顺序分配、终态、保存水位、预览释放与冲突。
//!
//! 这些信号不随窗口删除而降低标准：它们保证唯一生产者、稳定身份与顺序，以及“可靠待保存事实在
//! 确认前不被显示缓存淘汰”这些与读取接口无关的事实。

#[path = "support/timeline.rs"]
mod timeline_support;

use pl_core::chat::{ChatError, Session};
use timeline_support::*;

#[tokio::test]
async fn a_save_acknowledgement_keeps_identity_order_revision_and_body() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 3, "streamed", false)).unwrap();
    let before = visible_item(&session, "item-1").await.unwrap();

    session.confirm_saved("item-1", 3);
    let after = visible_item(&session, "item-1").await.unwrap();

    assert!(after.is_saved());
    assert!(
        after.is_streaming(),
        "a save receipt never advances the execution lifecycle"
    );
    assert_eq!(after.item_id, before.item_id);
    assert_eq!(after.order, before.order);
    assert_eq!(after.revision, before.revision);
    assert_eq!(body_text(&after), body_text(&before));

    // Acknowledging a streaming identity never freezes it.
    session.publish(appended(&after, 4, " more")).unwrap();
    let advanced = visible_item(&session, "item-1").await.unwrap();
    assert_eq!(advanced.revision, 4);
    assert_eq!(body_text(&advanced), "streamed more");
    assert!(advanced.is_streaming());
    assert!(
        !advanced.is_saved(),
        "a new revision is unacknowledged until the writer confirms it"
    );
}

#[tokio::test]
async fn a_stale_writer_acknowledgement_does_not_mark_a_newer_revision_saved() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 2, "second", false)).unwrap();
    session.confirm_saved("item-1", 1);
    assert!(!visible_item(&session, "item-1").await.unwrap().is_saved());
    session.confirm_saved("item-1", 2);
    assert!(visible_item(&session, "item-1").await.unwrap().is_saved());
}

#[tokio::test]
async fn a_terminal_item_can_stay_unsaved_and_a_late_preview_is_refused() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 4, "final", true)).unwrap();
    let visible = visible_item(&session, "item-1").await.unwrap();
    assert!(visible.is_terminal());
    assert!(!visible.is_saved());

    // The late preview is refused from the execution lifecycle alone, before any save confirmation.
    assert!(matches!(
        session.publish_preview(item(1, 4, "stale", false)),
        Err(ChatError::Conflict(_))
    ));
    assert_eq!(
        body_text(&visible_item(&session, "item-1").await.unwrap()),
        "final"
    );
}

#[tokio::test]
async fn the_same_revision_cannot_carry_a_different_body() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 2, "authoritative", false)).unwrap();
    assert!(matches!(
        session.publish(item(1, 2, "different", false)),
        Err(ChatError::Conflict(_))
    ));
    assert_eq!(
        body_text(&visible_item(&session, "item-1").await.unwrap()),
        "authoritative"
    );
}

#[tokio::test]
async fn two_identities_cannot_claim_one_order() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 1, "first", false)).unwrap();
    let mut conflicting = item(1, 1, "second", false);
    conflicting.item_id = "another-item".to_owned();
    assert!(matches!(
        session.publish(conflicting),
        Err(ChatError::Conflict(id)) if id == "another-item"
    ));
    let page = visible(&session, 100).await;
    assert_eq!(page.len(), 1);
    assert_eq!(page[0].item_id, "item-1");
    assert_eq!(body_text(&page[0]), "first");
}

#[tokio::test]
async fn a_committed_identity_survives_the_preview_release_after_a_save_acknowledgement() {
    let session = Session::new(Stored::default());
    let prefix = attempt_prefix("attempt");
    let id = presentation("attempt", "message-1");
    session
        .publish_preview(identified(&id, 1, 1, "realtime ", false))
        .unwrap();
    assert_eq!(
        body_text(&visible_item(&session, &id).await.unwrap()),
        "realtime "
    );

    session
        .publish(identified(&id, 1, 2, "realtime delayed first token", true))
        .unwrap();
    session.confirm_saved(&id, 2);
    assert!(session.is_committed(&id));
    session.drop_previews_with_prefix(&prefix);

    let kept = visible_item(&session, &id).await.unwrap();
    assert_eq!(kept.order, 1, "the committed position is final");
    assert_eq!(kept.revision, 2);
    assert_eq!(body_text(&kept), "realtime delayed first token");
    assert!(kept.is_saved());
    assert!(kept.is_terminal());
}

#[tokio::test]
async fn a_preview_release_still_removes_an_identity_that_never_committed() {
    let session = Session::new(Stored::default());
    let prefix = attempt_prefix("attempt");
    let dropped = presentation("attempt", "message-2");
    session.publish_preview(item(1, 1, "kept", false)).unwrap();
    session
        .publish_preview(identified(&dropped, 2, 1, "in-flight", false))
        .unwrap();
    assert_eq!(visible(&session, 100).await.len(), 2);

    session.drop_previews_with_prefix(&prefix);

    let page = visible(&session, 100).await;
    assert_eq!(page.len(), 1);
    assert_eq!(page[0].item_id, "item-1");
}

#[tokio::test]
async fn a_preview_release_spares_the_identities_the_commit_just_confirmed() {
    let session = Session::new(Stored::default());
    let prefix = attempt_prefix("attempt");
    let confirmed = presentation("attempt", "message-1");
    let dropped = presentation("attempt", "message-2");
    session
        .publish_preview(identified(&confirmed, 1, 1, "realtime ", false))
        .unwrap();
    session
        .publish_preview(identified(&dropped, 2, 1, "in-flight", false))
        .unwrap();

    session.drop_previews_with_prefix_except(&prefix, [confirmed.as_str()]);

    let page = visible(&session, 100).await;
    assert_eq!(page.len(), 1);
    assert_eq!(page[0].item_id, confirmed);
    assert_eq!(page[0].order, 1);
}

#[tokio::test]
async fn a_late_preview_never_reopens_a_committed_identity_after_cache_eviction() {
    let session = Session::new(Stored::default());
    let id = presentation("attempt", "message-1");
    session
        .publish(identified(&id, 1, 5, "committed", true))
        .unwrap();
    // Push the committed identity out of the bounded preview cache.
    for order in 2..=220 {
        session.publish(item(order, 1, "tail", true)).unwrap();
    }
    assert!(matches!(
        session.publish_preview(identified(&id, 1, 5, "late", false)),
        Err(ChatError::Conflict(_))
    ));
    assert!(matches!(
        session.publish_preview(identified(&id, 1, 9, "later", false)),
        Err(ChatError::Conflict(_))
    ));
}

#[tokio::test]
async fn a_reliable_terminal_revision_can_still_update_a_committed_identity() {
    let session = Session::new(Stored::default());
    let id = presentation("attempt", "message-1");
    session
        .publish(identified(&id, 1, 5, "committed", true))
        .unwrap();
    for order in 2..=220 {
        session.publish(item(order, 1, "tail", true)).unwrap();
    }
    // A reliable terminal fact (for example a resource supplement) is still legal after eviction.
    session
        .publish(identified(&id, 1, 6, "committed and extended", true))
        .unwrap();
    // The identity sits outside the bounded preview window, so it is read through its own page.
    let page = session
        .page(pl_core::chat::ChatPageRequest::before(
            pl_core::chat::ChatCursor::new(2, "item-2"),
        ))
        .await
        .unwrap();
    let updated = page
        .items
        .iter()
        .find(|item| item.item_id == id)
        .expect("the reliable terminal revision stays visible");
    assert_eq!(updated.revision, 6);
    assert_eq!(body_text(updated), "committed and extended");
}

#[tokio::test]
async fn orders_are_allocated_from_the_persisted_ceiling_and_never_reused() {
    let session = Session::new(Stored::with([
        item(1, 1, "durable", true),
        item(2, 1, "durable", true),
    ]));
    session.initialize_order_allocator().await.unwrap();
    assert_eq!(session.reserve_order_in_memory("fresh").unwrap(), 3);
    // A repeated identity keeps its order instead of allocating a new one.
    assert_eq!(session.reserve_order_in_memory("fresh").unwrap(), 3);
    session.release_unpublished_order("fresh");
    assert_eq!(
        session.reserve_order_in_memory("another").unwrap(),
        4,
        "an abandoned reservation is never reused"
    );
}

#[tokio::test]
async fn a_preview_keeps_its_order_until_terminal_admission() {
    let session = Session::new(Stored::default());
    session.initialize_order_allocator().await.unwrap();
    for index in 1..=200 {
        let id = format!("item-{index}");
        assert_eq!(session.reserve_order_in_memory(&id).unwrap(), index);
        session
            .publish_preview(identified(&id, index, 1, "preview", false))
            .unwrap();
    }
    // The newest speculative order survives eviction from the bounded preview cache.
    assert_eq!(session.assigned_order("item-200"), Some(200));
}

/// 终态标记被淘汰后，靠单调顺序水位拒绝迟到预览。
///
/// 4096 条终态身份把最早那条的标记挤出缓存，此后该 identity 的顺序槽已经不可能被复用，因此迟到的
/// 预览仍然被拒绝——不是靠“它还在缓存里”，而是靠顺序事实本身。
#[tokio::test]
async fn a_late_preview_below_an_evicted_terminal_floor_is_rejected() {
    let session = Session::new(Stored::default());
    session
        .publish(item(1, 1, "committed first", true))
        .unwrap();
    session.confirm_saved("item-1", 1);
    for order in 2..=4200 {
        session.publish(saved_item(order, 1, "tail", true)).unwrap();
    }
    // 标记已淘汰：确认它既不在热预览里，也不在可靠待保存集合里。
    assert!(visible_item(&session, "item-1").await.is_none());
    assert!(matches!(
        session.publish_preview(identified("item-1", 1, 9, "late", false)),
        Err(ChatError::Conflict(_))
    ));
    // 同一条条目的权威终态修订仍然合法（写入方拥有它自己的持久事实）。
    session
        .publish(identified("item-1", 1, 10, "extended", true))
        .unwrap();
}

#[tokio::test]
async fn a_save_flag_cannot_replace_the_body_at_the_same_revision() {
    let session = Session::new(Stored::default());
    session.publish(item(1, 2, "authoritative", false)).unwrap();
    let mut altered = item(1, 2, "different", false);
    altered.saved = true;
    assert!(matches!(
        session.publish(altered),
        Err(ChatError::Conflict(_))
    ));
    let kept = visible_item(&session, "item-1").await.unwrap();
    assert_eq!(body_text(&kept), "authoritative");
    assert!(
        !kept.is_saved(),
        "a refused replacement acknowledges no data"
    );
    session.confirm_saved("item-1", 2);
    let saved = visible_item(&session, "item-1").await.unwrap();
    assert!(saved.is_saved());
    assert_eq!(body_text(&saved), "authoritative");
}
