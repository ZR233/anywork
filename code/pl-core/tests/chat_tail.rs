//! 有界尾部订阅：一致基线、连续补丁、合帧边界、重同步与非删除的缓存退出。

#[path = "support/timeline.rs"]
mod timeline_support;

use std::{sync::Arc, time::Duration};

use pl_core::chat::{
    ChatError, ChatField, ChatResyncReason, ChatTailUpdate, ChatUpdatePriority, FieldChange,
    Session, TailChange,
};
use pretty_assertions::assert_eq;
use timeline_support::*;

fn next_patch(update: ChatTailUpdate) -> pl_core::chat::ChatTailPatch {
    match update {
        ChatTailUpdate::Patch(patch) => patch,
        ChatTailUpdate::Resync { reason, .. } => {
            panic!("expected a continuous patch, got resync {reason:?}")
        }
    }
}

#[tokio::test]
async fn a_new_tail_captures_the_latest_small_page_and_continues_from_it() {
    let session = Session::new(Stored::with(
        (1..=40).map(|order| item(order, 1, "x", true)),
    ));
    // With no observer, content and save facts still advance and belong in the next baseline.
    assert!(!session.has_subscribers());
    session.publish(item(40, 2, "\nlatest\n", true)).unwrap();
    session.confirm_saved("item-40", 2);
    assert!(!session.has_subscribers());
    let mut tail = session.subscribe_tail().await.unwrap();
    assert!(session.has_subscribers());
    assert!(
        matches!(tail.next().await, Err(ChatError::Conflict(_))),
        "the first frame must be taken before awaiting updates"
    );

    // 首帧是单次移交：取一次就拿到全部条目与真实边界。
    let baseline = take_initial(&mut tail);
    assert_eq!(baseline.items.len(), 32);
    assert_eq!(baseline.items.first().unwrap().order, 9);
    assert_eq!(baseline.items.last().unwrap().order, 40);
    assert_eq!(
        baseline.items.last(),
        Some(&saved_item(40, 2, "\nlatest\n", true))
    );
    assert!(baseline.version > 0);
    assert!(
        matches!(tail.initial(), Err(ChatError::Conflict(_))),
        "the first frame is a one-shot handover"
    );
    // 首帧自己就带真实更旧边界，客户端不需要另发一次 latest 查询再拼两份基线。
    assert!(baseline.has_older);
    assert_eq!(
        baseline.before,
        Some(pl_core::chat::ChatCursor::new(9, "item-9"))
    );
    let older = session
        .page(
            pl_core::chat::ChatPageRequest::before(baseline.before.clone().unwrap()).with_limit(32),
        )
        .await
        .unwrap();
    assert_eq!(
        older
            .items
            .iter()
            .map(|item| item.order)
            .collect::<Vec<_>>(),
        (1..=8).collect::<Vec<_>>()
    );
    assert!(!older.has_older);

    session.publish(item(41, 1, "new", false)).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.from, baseline.version);
    assert!(patch.to > patch.from);
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [TailChange::Add { item }] => {
            assert_eq!(item.item_id, "item-41");
            assert_eq!(item.revision, 1);
        }
        other => panic!("expected one added identity, got {other:?}"),
    }
}

#[tokio::test]
async fn an_append_to_a_delivered_identity_arrives_as_a_typed_field_append() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    // The producer keeps one block lineage across revisions, so the append is a real extension.
    let first = item(1, 1, "hello", false);
    session.publish(first.clone()).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));

    session.publish(appended(&first, 2, " world")).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Coalesced);
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                item_id,
                expected_revision,
                revision,
                fields,
                ..
            },
        ] => {
            assert_eq!(item_id, "item-1");
            assert_eq!(*expected_revision, 1);
            assert_eq!(*revision, 2);
            assert_eq!(
                fields,
                &[pl_core::chat::FieldUpdate {
                    field: ChatField::Body,
                    change: FieldChange::Append(" world".to_string()),
                    total_bytes: 11,
                    preview_bytes: 11,
                }]
            );
        }
        other => panic!("expected one typed update, got {other:?}"),
    }
}

#[tokio::test]
async fn a_save_acknowledgement_is_a_legal_update_at_the_same_revision() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    session.publish(item(1, 3, "streamed", false)).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));

    session.confirm_saved("item-1", 3);
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                expected_revision,
                revision,
                saved,
                lifecycle,
                fields,
                ..
            },
        ] => {
            assert_eq!(expected_revision, revision);
            assert_eq!(*revision, 3);
            assert!(saved);
            assert!(lifecycle.is_streaming());
            assert_eq!(
                fields,
                &[pl_core::chat::FieldUpdate {
                    field: ChatField::Body,
                    change: FieldChange::Unchanged,
                    total_bytes: 8,
                    preview_bytes: 8,
                }],
                "a version-only frame still carries its field baseline"
            );
        }
        other => panic!("expected one save update, got {other:?}"),
    }
}

#[tokio::test]
async fn one_publication_that_changes_two_fields_commits_one_revision() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    let arguments = ChatField::host("tool.arguments");
    let result = ChatField::host("tool.result");
    session
        .publish(with_fields(
            "item-1",
            1,
            1,
            [
                (arguments.clone(), "{}".to_string()),
                (result.clone(), "partial".to_string()),
            ],
            false,
        ))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));

    session
        .publish(with_fields(
            "item-1",
            1,
            2,
            [
                (arguments, "{\"a\":1}".to_string()),
                (result, "partial done".to_string()),
            ],
            false,
        ))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                revision, fields, ..
            },
        ] => {
            assert_eq!(*revision, 2);
            assert_eq!(fields.len(), 2, "both fields arrive in one commit");
        }
        other => panic!("expected one multi-field update, got {other:?}"),
    }
}

#[tokio::test(start_paused = true)]
async fn two_tails_keep_independent_baselines_and_closing_one_leaves_the_other_working() {
    let session = Session::new(Stored::default());
    let mut first = session.subscribe_tail().await.unwrap();
    let first_baseline = first.initial().expect("its own first frame");
    assert!(first_baseline.items.is_empty());
    let original = item(1, 1, "one", false);
    session.publish(original.clone()).unwrap();
    let patch = next_patch(first.next().await.unwrap().unwrap());
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));
    // The second observation starts from the newer baseline, so it is not missing anything.
    let mut second = session.subscribe_tail().await.unwrap();
    let second_baseline = second.initial().expect("its own first frame");
    assert_eq!(second_baseline.items.len(), 1);
    assert_eq!(second_baseline.items[0].item_id, "item-1");

    // Both observers receive the very same body delta, but own separate delivery watermarks.
    let continued = appended(&original, 2, "\n\ntwo\n");
    session.publish(continued.clone()).unwrap();
    let first_append = next_patch(first.next().await.unwrap().unwrap());
    let second_append = next_patch(second.next().await.unwrap().unwrap());
    assert_eq!(first_append.from, patch.to);
    assert_eq!(second_append.from, second_baseline.version);
    assert_eq!(first_append, second_append);
    match &first_append.changes[..] {
        [
            TailChange::UpdateItem {
                expected_revision,
                revision,
                fields,
                ..
            },
        ] => {
            assert_eq!((*expected_revision, *revision), (1, 2));
            assert_eq!(
                fields,
                &[pl_core::chat::FieldUpdate {
                    field: ChatField::Body,
                    change: FieldChange::Append("\n\ntwo\n".to_owned()),
                    total_bytes: 9,
                    preview_bytes: 9,
                }]
            );
        }
        other => panic!("expected the original newline-preserving append, got {other:?}"),
    }
    session.publish(appended(&continued, 3, "three")).unwrap();
    let ahead = next_patch(first.next().await.unwrap().unwrap());

    first.close();
    first.close();
    assert!(
        session.has_subscribers(),
        "the second observation still owns demand"
    );
    assert!(
        matches!(first.initial(), Err(ChatError::Cancelled)),
        "close releases the content"
    );
    assert!(matches!(first.next().await, Err(ChatError::Cancelled)));
    let catching_up = next_patch(second.next().await.unwrap().unwrap());
    assert_eq!(catching_up.from, second_append.to);
    assert_eq!(
        catching_up, ahead,
        "the first reader cannot consume the second reader's progress"
    );

    session.publish(item(2, 1, "two", false)).unwrap();
    let patch = next_patch(second.next().await.unwrap().unwrap());
    match &patch.changes[..] {
        [TailChange::Add { item }] => assert_eq!(item.item_id, "item-2"),
        other => panic!("expected the surviving observation to deliver, got {other:?}"),
    }

    // Cancel the caller-owned next future before close; its temporary waiter must not leak demand.
    {
        let mut pending = Box::pin(second.next());
        assert!(futures::poll!(&mut pending).is_pending());
    }
    second.close();
    second.close();
    assert!(
        !session.has_subscribers(),
        "closed objects still exist but own no receivers"
    );
    assert!(matches!(second.initial(), Err(ChatError::Cancelled)));
    assert!(matches!(second.next().await, Err(ChatError::Cancelled)));

    session.publish(item(3, 1, "after close", true)).unwrap();
    session.confirm_saved("item-3", 1);
    assert_eq!(
        visible(&session, 32).await,
        vec![
            appended(&continued, 3, "three"),
            item(2, 1, "two", false),
            saved_item(3, 1, "after close", true),
        ]
    );
    assert!(!session.has_subscribers(), "paging is not a subscription");
    let reopened = session.subscribe_tail().await.unwrap();
    assert!(session.has_subscribers());
    drop(reopened);
    assert!(
        !session.has_subscribers(),
        "dropping an unconsumed tail releases demand too"
    );
    let weak_session = session.downgrade();
    drop(session);
    assert!(
        weak_session.upgrade().is_none(),
        "closed tails must not pin the session either"
    );
}

#[tokio::test]
async fn a_slow_observation_resynchronizes_instead_of_stitching_disjoint_facts() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    let mut fast = session.subscribe_tail().await.unwrap();
    let mut fast_version = take_initial(&mut fast).version;
    // Far more publications than the bounded continuity window can describe.
    for order in 1..=700 {
        session.publish(item(order, 1, "x", true)).unwrap();
        let patch = next_patch(fast.next().await.unwrap().unwrap());
        assert_eq!(patch.from, fast_version);
        assert_eq!(
            patch.changes,
            vec![TailChange::Add {
                item: item(order, 1, "x", true)
            }]
        );
        fast_version = patch.to;
    }

    let resync_version = match tail.next().await.unwrap().unwrap() {
        ChatTailUpdate::Resync { reason, baseline } => {
            assert_eq!(reason, ChatResyncReason::Lagging);
            assert!(baseline.version > 0);
            assert!(baseline.items.len() <= 32);
            assert_eq!(baseline.items.last().unwrap().order, 700);
            baseline.version
        }
        ChatTailUpdate::Patch(patch) => panic!("expected a resync, got patch {patch:?}"),
    };
    assert_eq!(resync_version, fast_version);
    // The observation continues from the new baseline.
    session.publish(item(701, 1, "x", true)).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.from, resync_version);
    assert!(patch.to > patch.from);
    let fast_patch = next_patch(fast.next().await.unwrap().unwrap());
    assert_eq!(
        fast_patch, patch,
        "one observation's resync cannot reset another's baseline"
    );
}

#[tokio::test]
async fn a_failed_initial_capture_releases_demand_and_can_be_retried() {
    let history = FailsOnce::new(Stored::default());
    let fail_next_page = history.fail_next_page.clone();
    let session = Session::new(history);
    session
        .publish(item(1, 1, "before failure", false))
        .unwrap();
    fail_next_page.store(true, std::sync::atomic::Ordering::SeqCst);

    assert!(matches!(
        session.subscribe_tail().await,
        Err(ChatError::History(_))
    ));
    assert!(!session.has_subscribers(), "a failed open owns no receiver");

    let current = item(1, 2, "after failure", true);
    session.publish(current.clone()).unwrap();
    let mut tail = session.subscribe_tail().await.unwrap();
    assert!(session.has_subscribers());
    let baseline = take_initial(&mut tail);
    assert_eq!(baseline.items, vec![current]);
    drop(tail);
    assert!(!session.has_subscribers());
}

#[tokio::test]
async fn cancelling_an_initial_capture_releases_its_registered_receiver() {
    let mut history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);

    let mut opening = Box::pin(session.subscribe_tail());
    assert!(futures::poll!(&mut opening).is_pending());
    gate.entered().await;
    assert!(
        session.has_subscribers(),
        "opening registers before awaiting history"
    );
    let current = item(1, 1, "published while opening", true);
    session.publish(current.clone()).unwrap();
    drop(opening);
    assert!(
        !session.has_subscribers(),
        "cancelled opening releases its receiver"
    );

    let mut reopening = Box::pin(session.subscribe_tail());
    assert!(futures::poll!(&mut reopening).is_pending());
    gate.entered().await;
    let revised = item(1, 2, "published during the successful capture", true);
    session.publish(revised.clone()).unwrap();
    gate.release();
    let mut tail = reopening.await.unwrap();
    let baseline = take_initial(&mut tail);
    assert_eq!(baseline.items, vec![revised]);
    tail.close();
    // Closing with a still-unconsumed initial frame also prioritizes cancellation over conflict.
    gate.release();
    let mut unconsumed = session.subscribe_tail().await.unwrap();
    unconsumed.close();
    assert!(!session.has_subscribers());
    assert!(matches!(unconsumed.initial(), Err(ChatError::Cancelled)));
    assert!(matches!(unconsumed.next().await, Err(ChatError::Cancelled)));
}

#[tokio::test]
async fn leaving_the_preview_window_is_never_delivered_as_a_removal() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    for order in 1..=150 {
        session.publish(item(order, 1, "x", true)).unwrap();
        let patch = next_patch(tail.next().await.unwrap().unwrap());
        assert!(
            !patch
                .changes
                .iter()
                .any(|change| matches!(change, TailChange::Remove { .. })),
            "a preview-cache eviction must never delete a delivered message"
        );
    }
}

#[tokio::test]
async fn a_real_preview_release_is_delivered_as_a_removal() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    let prefix = attempt_prefix("attempt");
    let in_flight = presentation("attempt", "message-1");
    session
        .publish_preview(identified(&in_flight, 1, 1, "in-flight", false))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));

    session.drop_previews_with_prefix(&prefix);

    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [TailChange::Remove { item_id }] => assert_eq!(item_id, &in_flight),
        other => panic!("expected one removal, got {other:?}"),
    }
}

#[tokio::test(start_paused = true)]
async fn ordinary_text_merges_into_one_frame_while_a_boundary_preempts_the_window() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    // A first byte is a boundary and is ready at once.
    let first = item(1, 1, "a", false);
    session.publish(first.clone()).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);

    // Three ordinary appends within one fixed coalescing window arrive as a single frame that still
    // carries every byte.
    let mut current = first;
    for revision in 2..=4 {
        current = appended(&current, revision, "b");
        session.publish(current.clone()).unwrap();
    }
    let read = tokio::time::timeout(Duration::from_millis(1), tail.next()).await;
    assert!(
        read.is_err(),
        "ordinary text waits for the fixed deadline instead of delivering per token"
    );
    tokio::time::advance(Duration::from_millis(33)).await;
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Coalesced);
    match &patch.changes[..] {
        [TailChange::UpdateItem { fields, .. }] => assert_eq!(
            fields,
            &[pl_core::chat::FieldUpdate {
                field: ChatField::Body,
                change: FieldChange::Append("bbb".to_string()),
                total_bytes: 4,
                preview_bytes: 4,
            }]
        ),
        other => panic!("expected one merged update, got {other:?}"),
    }

    // A terminal admission is a boundary: it does not wait for the coalescing window.
    session.publish(item(1, 5, "abbb", true)).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [TailChange::UpdateItem { lifecycle, .. }] => assert!(lifecycle.is_terminal()),
        other => panic!("expected a terminal update, got {other:?}"),
    }
}

/// 预览正文封顶后，原文继续增长仍必须把真实 total／revision／省略量交付出去。
///
/// 消费者因此知道“屏幕上的这段文字之外还有正文”，既不必自己按 UTF-8 推断省略量，也不必为了得到
/// 长度而先读整段全文；同 revision 的保存确认也照样是一次合法更新。
#[tokio::test]
async fn a_capped_preview_still_reports_the_growing_original_and_its_own_save_state() {
    let body = "0123456789abcdefghijklmnopqrstuvwxyz";
    let session = Session::new(Bounded::new(Stored::default(), 16));
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first_frame = take_initial(&mut tail);
    let first = item(1, 1, body, false);
    session.publish(first.clone()).unwrap();

    match tail.next().await.unwrap().unwrap() {
        ChatTailUpdate::Patch(patch) => match &patch.changes[..] {
            [TailChange::Add { item }] => {
                assert_eq!(item.body().unwrap().text(), "0123456789abcdef");
                assert_eq!(item.field_total_bytes(&ChatField::Body), Some(36));
                assert_eq!(item.omitted_bytes(), 20);
            }
            other => panic!("expected one added identity, got {other:?}"),
        },
        other => panic!("expected a patch, got {other:?}"),
    }

    // A streamed revision whose preview is already capped: the text stays identical while the original
    // length, the revision and the omitted amount all advance in one delivered frame.
    session.publish(appended(&first, 2, " and more")).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Coalesced);
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                expected_revision,
                revision,
                omitted_bytes,
                saved,
                fields,
                ..
            },
        ] => {
            assert_eq!(*expected_revision, 1);
            assert_eq!(*revision, 2);
            assert!(!saved);
            assert_eq!(*omitted_bytes, 29);
            assert_eq!(
                fields,
                &[pl_core::chat::FieldUpdate {
                    field: ChatField::Body,
                    change: FieldChange::Unchanged,
                    total_bytes: 45,
                    preview_bytes: 16,
                }]
            );
        }
        other => panic!("expected one metadata update, got {other:?}"),
    }

    // The same revision can still be acknowledged: the save watermark moves without new content.
    session.confirm_saved("item-1", 2);
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                expected_revision,
                revision,
                saved,
                fields,
                ..
            },
        ] => {
            assert_eq!(expected_revision, revision);
            assert_eq!(*revision, 2);
            assert!(saved);
            assert_eq!(fields[0].total_bytes, 45);
            assert_eq!(fields[0].preview_bytes, 16);
            assert_eq!(fields[0].change, FieldChange::Unchanged);
        }
        other => panic!("expected one save update, got {other:?}"),
    }
}

/// 一个几乎以满页开头的订阅，其首帧也由同次读取给出真实边界。
#[tokio::test]
async fn a_short_history_baseline_does_not_claim_more_history() {
    let session = Session::new(Stored::with((1..=3).map(|order| item(order, 1, "x", true))));
    let tail = session.subscribe_tail().await.unwrap();
    let mut tail = tail;
    let baseline = tail.initial().expect("the first frame");
    assert_eq!(baseline.items.len(), 3);
    assert!(!baseline.has_older);
    assert_eq!(baseline.before, None);
}

/// 连续性窗口丢失后的重同步必须给出**权威最新小页**，与同 Session 的页一致。
///
/// 冷 durable 历史 + 一段越过连续性窗口的流式发布：重同步不能把只有热预览的记忆尾当成最新页，
/// 也不能因此声称“到头”。
#[tokio::test]
async fn a_resync_delivers_the_authoritative_latest_page() {
    let session = Session::new(Stored::with(
        (1..=100).map(|order| item(order, 1, "x", true)),
    ));
    let mut tail = session.subscribe_tail().await.unwrap();
    let first = take_initial(&mut tail);
    assert_eq!(first.items.len(), 32);
    assert!(first.has_older);

    let mut streamed = item(101, 1, "streamed", false);
    session.publish(streamed.clone()).unwrap();
    for revision in 2..=600 {
        streamed = appended(&streamed, revision, "x");
        session.publish(streamed.clone()).unwrap();
    }

    let baseline = match tail.next().await.unwrap().unwrap() {
        ChatTailUpdate::Resync { reason, baseline } => {
            assert_eq!(reason, ChatResyncReason::Lagging);
            baseline
        }
        ChatTailUpdate::Patch(patch) => panic!("expected a resync, got patch {patch:?}"),
    };

    // 与同 Session 的权威最新页逐项一致：条目、边界、真实 has_older。
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest().with_limit(32))
        .await
        .unwrap();
    assert_eq!(
        baseline
            .items
            .iter()
            .map(|item| item.item_id.clone())
            .collect::<Vec<_>>(),
        page.items
            .iter()
            .map(|item| item.item_id.clone())
            .collect::<Vec<_>>()
    );
    assert_eq!(baseline.items.len(), 32);
    assert_eq!(baseline.has_older, page.has_older);
    assert!(
        baseline.has_older,
        "100 durable rows still have older content"
    );
    assert_eq!(baseline.before, page.before);
    // 并且真的可以继续翻更旧一页。
    let older = session
        .page(
            pl_core::chat::ChatPageRequest::before(baseline.before.clone().unwrap()).with_limit(32),
        )
        .await
        .unwrap();
    assert_eq!(older.items.len(), 32);
    assert!(older.has_older);

    // 重同步之后继续从新基线推进。
    session
        .publish(item(102, 1, "after resync", false))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.from, baseline.version);
}

/// 重建基线失败时必须是类型化错误，而不是伪装成内容结束。
#[tokio::test]
async fn a_failed_resync_capture_is_an_error_not_an_end_of_content() {
    let session = Session::new(FailAfter::new(
        Stored::with((1..=100).map(|order| item(order, 1, "x", true))),
        1,
    ));
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first = take_initial(&mut tail);
    for revision in 1..=600 {
        session
            .publish(identified("streamed", 101, revision, "x", false))
            .unwrap();
    }
    assert!(matches!(tail.next().await, Err(ChatError::History(_))));
    // 失败不提交任何水位，也不会转成 Ok(None)：下一次调用继续报告真实失败。
    assert!(matches!(tail.next().await, Err(ChatError::History(_))));
}

/// 字段删除与权威替换是立即边界，并且一次提交里带齐所有字段。
#[tokio::test]
async fn a_field_removal_and_an_authoritative_replacement_are_immediate_boundaries() {
    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first = take_initial(&mut tail);
    let body = ChatField::Body;
    let result = ChatField::host("tool.result");
    session
        .publish(with_fields(
            "item-1",
            1,
            1,
            [
                (body.clone(), "draft".to_owned()),
                (result.clone(), "old result".to_owned()),
            ],
            false,
        ))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));

    // 同一次提交：正文被权威替换（不是前缀扩展），工具结果被真实移除。
    session
        .publish(with_fields(
            "item-1",
            1,
            2,
            [(body.clone(), "rewritten".to_owned())],
            false,
        ))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                item_id,
                expected_revision,
                revision,
                fields,
                ..
            },
        ] => {
            assert_eq!(item_id, "item-1");
            assert_eq!((*expected_revision, *revision), (1, 2));
            assert_eq!(fields.len(), 2, "both fields travel in one commit");
            assert!(fields.iter().any(|field| field.field == body
                && matches!(&field.change, FieldChange::Replace(text) if text.text() == "rewritten")));
            assert!(
                fields
                    .iter()
                    .any(|field| field.field == result && field.change == FieldChange::Remove)
            );
        }
        other => panic!("expected one authoritative update, got {other:?}"),
    }

    // 只有权威替换（没有删除）也必须是立即边界。
    session
        .publish(with_fields(
            "item-1",
            1,
            3,
            [(body, "rewritten again".to_owned())],
            false,
        ))
        .unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [
            TailChange::UpdateItem {
                revision, fields, ..
            },
        ] => {
            assert_eq!(*revision, 3);
            assert!(matches!(&fields[0].change, FieldChange::Replace(_)));
        }
        other => panic!("expected one replacement update, got {other:?}"),
    }
}

/// 首帧移交出去以后，观察不再为整个连接额外保一份最新页正文。
///
/// 证明方式：首帧条目离开会话热预览与该观察的有界连续性副本后，只剩测试自己持有的那一份引用。
#[tokio::test]
async fn a_taken_first_frame_is_not_kept_for_the_life_of_the_observation() {
    let session = Session::new(Stored::default());
    let held = {
        let published = item(1, 1, "unique-first-frame-body", true);
        let held = published.body().unwrap().clone();
        session.publish(published).unwrap();
        held
    };
    // 让 writer 确认这一条，可靠待保存事实就不再额外持有它。
    session.confirm_saved("item-1", 1);
    let mut tail = session.subscribe_tail().await.unwrap();
    let baseline = take_initial(&mut tail);
    assert_eq!(baseline.items.len(), 1);
    drop(baseline);

    for order in 2..=150 {
        session.publish(item(order, 1, "tail", true)).unwrap();
        tail.next()
            .await
            .unwrap()
            .expect("every publication is deliverable");
    }

    assert_eq!(
        std::sync::Arc::strong_count(&held),
        1,
        "neither the session nor the observation keeps the handed-over first frame body"
    );
}

/// 首帧与页使用同一份预览预算：大条目时条数可以少于 32，但边界与 has_older 仍然真实。
#[tokio::test]
async fn a_first_frame_uses_the_same_page_budget_as_a_page() {
    let text = "a".repeat(300 * 1024);
    let session = Session::new(Stored::with(
        (1..=10).map(|order| item(order, 1, &text, true)),
    ));
    let mut tail = session.subscribe_tail().await.unwrap();
    let baseline = take_initial(&mut tail);
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest().with_limit(32))
        .await
        .unwrap();
    assert_eq!(baseline.items.len(), page.items.len());
    assert!(baseline.items.len() < 32, "the page preview budget applies");
    assert!(baseline.has_older);
    assert_eq!(baseline.has_older, page.has_older);
    assert_eq!(baseline.before, page.before);
    assert_eq!(
        baseline.items.first().unwrap().item_id,
        page.items.first().unwrap().item_id
    );
}

/// 首帧捕获跨过一次真实撤回时，基线版本覆盖这次删除，但它的 items 不能含被撤回的身份。
///
/// 观察先登记、再读冷历史：如果读取期间权威释放了一条推测内容，而基线把删除版本和这条身份同时带上，
/// 后续就再没有删除事实来纠正它——那不是可接受的历史快照。版本与条目必须来自同一个临界区。
#[tokio::test]
async fn a_baseline_captured_across_a_withdrawal_never_carries_the_withdrawn_identity() {
    let mut history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    history.page_gate = Some(gate.clone());
    let session = Session::new(history);
    let prefix = attempt_prefix("attempt");
    let in_flight = presentation("attempt", "message-1");
    session
        .publish_preview(identified(&in_flight, 1, 1, "in-flight", false))
        .unwrap();

    let subscribed = tokio::spawn({
        let session = session.clone();
        async move { session.subscribe_tail().await }
    });
    gate.entered().await;
    // 读取停在存储期间，权威真实释放这条推测内容。
    session.drop_previews_with_prefix(&prefix);
    gate.release();

    let mut tail = subscribed.await.unwrap().unwrap();
    let baseline = take_initial(&mut tail);
    assert!(
        baseline.items.iter().all(|item| item.item_id != in_flight),
        "a baseline must not list an identity withdrawn in its own window: {baseline:?}"
    );
    assert!(baseline.items.is_empty());
    // 版本确实覆盖了那次删除（预览发布 v1、撤回 v2），却没有把它当成 phantom 内容交付。
    assert_eq!(baseline.version, 2);
    assert!(!baseline.has_older);
    assert_eq!(baseline.before, None);

    // 连续性从这条基线继续，且不会补发一个消费者从未持有的 ghost。
    session.publish(saved_item(2, 1, "after", true)).unwrap();
    let patch = next_patch(
        tail.next()
            .await
            .unwrap()
            .expect("a publication is deliverable"),
    );
    assert_eq!(patch.from, baseline.version);
    match &patch.changes[..] {
        [TailChange::Add { item }] => assert_eq!(item.item_id, "item-2"),
        other => panic!("expected the new identity only, got {other:?}"),
    }
}

/// 同一 `ChatItem` clone（同 revision、共享同一 `ContentBlock`）的重复发布是合法的，并产生一个真正的
/// 空 range：没有可见变化，就没有帧可交付。
///
/// 这条空事件只能推进 observed 水位；`delivered` 必须停在消费者真正收到的那一帧，否则下一帧的 `from`
/// 会跳过消费者。用同一个 `next()` future 手工 poll 一次（无 sleep）确认空事件确实存在，再断言随后的
/// 补丁从消费者实际持有的版本继续。
#[tokio::test(start_paused = true)]
async fn a_duplicate_publication_is_an_empty_frame_that_moves_no_consumer_watermark() {
    use std::{
        future::Future,
        task::{Context, Poll, Waker},
    };

    let session = Session::new(Stored::default());
    let mut tail = session.subscribe_tail().await.unwrap();
    let _first = take_initial(&mut tail);

    let published = item(1, 1, "same", true);
    session.publish(published.clone()).unwrap();
    let patch = next_patch(
        tail.next()
            .await
            .unwrap()
            .expect("the first publication is a frame"),
    );
    assert!(matches!(&patch.changes[..], [TailChange::Add { .. }]));
    let consumer_version = patch.to;

    // 同一个 clone 再发布一次：内容与 revision 完全一致，因此是不可见的空 range。
    session.publish(published).unwrap();
    let mut future = std::pin::pin!(tail.next());
    let mut context = Context::from_waker(Waker::noop());
    // 重复发布不是帧边界，所以它要等同一个合帧窗口；受控时钟推进后这个空 range 才真正被处理。
    assert!(matches!(future.as_mut().poll(&mut context), Poll::Pending));
    tokio::time::advance(Duration::from_millis(40)).await;
    assert!(
        matches!(future.as_mut().poll(&mut context), Poll::Pending),
        "a duplicate publication with identical content is not a deliverable frame"
    );

    session.publish(item(2, 1, "next", true)).unwrap();
    let update = match future.as_mut().poll(&mut context) {
        Poll::Ready(result) => result.unwrap().expect("a real publication is a frame"),
        Poll::Pending => panic!("a boundary publication must not wait for the coalescing window"),
    };
    let patch = next_patch(update);
    assert_eq!(
        patch.from, consumer_version,
        "the empty range must not move the consumer watermark"
    );
    assert_eq!(
        patch.to,
        consumer_version + 2,
        "the empty version is consumed but never delivered"
    );
    match &patch.changes[..] {
        [TailChange::Add { item }] => assert_eq!(item.item_id, "item-2"),
        other => panic!("the duplicate must not produce a change of its own: {other:?}"),
    }
}

/// 真实删除按身份自包含交付，并且没有交付帧的观察不许推进消费者水位。
///
/// 100 条 speculative preview 之后，订阅基线只带最新 32 条；但同一会话的页能把更旧的 item-1 交给
/// 消费者，因此“我的连续性副本里没有它”不等于“权威没有删除它”。释放 item-1 之后，观察必须显式交付
/// `Remove(item-1)`，且该补丁的 `from` 必须等于消费者真实持有的基线版本。
///
/// 手工 poll 同一个 future 一次：旧实现在这里必须已经是 Pending（事实被吞、没有任何帧可发），而新实现
/// 第一次 poll 就该给出这一帧；随后新发布会从消费者实际版本继续，不会出现 `from` 跳过消费者的空洞。
#[tokio::test]
async fn a_released_identity_outside_the_tail_is_delivered_and_moves_no_watermark() {
    use std::{
        future::Future,
        task::{Context, Poll, Waker},
    };

    let session = Session::new(Stored::default());
    for order in 1..=100 {
        session
            .publish_preview(identified(
                &presentation("attempt", &format!("message-{order}")),
                order,
                1,
                "x",
                false,
            ))
            .unwrap();
    }

    let mut tail = session.subscribe_tail().await.unwrap();
    let first = take_initial(&mut tail);
    assert_eq!(first.items.len(), 32);
    assert_eq!(first.items.first().unwrap().order, 69);
    let page = session
        .page(pl_core::chat::ChatPageRequest::latest().with_limit(100))
        .await
        .unwrap();
    let released = page
        .items
        .iter()
        .find(|item| item.order == 1)
        .expect("the consumer can load an identity the bounded tail does not keep")
        .item_id
        .clone();
    assert!(
        first.items.iter().all(|item| item.item_id != released),
        "the released identity really is outside the baseline"
    );

    session.drop_preview(&released);

    let update = {
        let mut future = std::pin::pin!(tail.next());
        let mut context = Context::from_waker(Waker::noop());
        match future.as_mut().poll(&mut context) {
            Poll::Ready(result) => result.unwrap().expect("a released identity is a real fact"),
            Poll::Pending => panic!(
                "a released identity must be delivered without waiting for another publication"
            ),
        }
    };
    let patch = next_patch(update);
    assert_eq!(
        patch.from, first.version,
        "the consumer's real version is the baseline: no frame was delivered before this one"
    );
    assert!(patch.to > patch.from);
    assert_eq!(patch.priority, ChatUpdatePriority::Immediate);
    match &patch.changes[..] {
        [TailChange::Remove { item_id }] => assert_eq!(item_id, &released),
        other => panic!("expected one self-contained removal, got {other:?}"),
    }
    let consumer_version = patch.to;

    // 消费者已经收下这一帧：后续发布必须从它实际持有的版本继续。
    session.publish(saved_item(101, 1, "after", true)).unwrap();
    let patch = next_patch(
        tail.next()
            .await
            .unwrap()
            .expect("a publication is deliverable"),
    );
    assert_eq!(
        patch.from, consumer_version,
        "a delivered frame advances the consumer watermark to its own `to`"
    );
}

/// 重同步捕获失败时，本帧已经 staged 的变化不能留在观察里。
///
/// 场景：先交付 99 条 speculative preview，让订阅在一个正常补丁后继续观察；随后发布新身份 6（在
/// horizon 内，本帧第一个 fact 会形成 `Add`），再发布消费者基线里旧身份 5 的 revision 2（可靠待保存，
/// 因此留在热点候选里），此时 100 条热点候选被 6..105 占满，5 暂时越出 horizon。
///
/// 第一次取帧因此在处理完 6 之后必须重同步，而这次捕获失败。真实丢弃那 99 条 preview（可靠事实一条
/// 都不删）之后，5 重新回到 horizon，重试应当交付**完整的连续补丁**：`Add` 6 + `UpdateItem` 5@2 +
/// 99 条真实 `Remove`。旧实现会在这之前就把 6 写进连续性副本，重试便把它当成“本帧无变化”跳过，
/// 消费者永久收不到 6。
#[tokio::test]
async fn a_failed_resync_capture_keeps_no_change_it_had_staged() {
    let storage = FailsOnce::new(Stored::with((1..=5).map(|order| item(order, 1, "x", true))));
    let fail_next_page = storage.fail_next_page.clone();
    let session = Session::new(storage);
    let mut tail = session.subscribe_tail().await.unwrap();
    let first = take_initial(&mut tail);
    assert_eq!(first.items.len(), 5);

    // 先让 99 条 speculative preview 成为已交付内容：它们在重试时只能作为真实 `Remove` 出现。
    let prefix = attempt_prefix("attempt");
    for order in 7..=105 {
        session
            .publish_preview(identified(
                &presentation("attempt", &format!("message-{order}")),
                order,
                1,
                "y",
                false,
            ))
            .unwrap();
    }
    let delivered = next_patch(
        tail.next()
            .await
            .unwrap()
            .expect("previews are deliverable"),
    );
    assert_eq!(delivered.changes.len(), 99);

    // horizon 内的新身份：本帧第一个 fact 会形成 `Add`。
    session.publish(saved_item(6, 1, "new", true)).unwrap();
    // 消费者基线里的旧身份发生变化，且仍是可靠待保存事实：它不会被 preview 释放清掉。
    session.publish(item(5, 2, "changed", true)).unwrap();

    fail_next_page.store(true, std::sync::atomic::Ordering::SeqCst);
    assert!(
        matches!(tail.next().await, Err(ChatError::History(_))),
        "a failed capture is a typed error, not an end of content"
    );

    // 只丢弃 speculative preview：5 与 6 都是可靠事实，一条都不删。
    session.drop_previews_with_prefix(&prefix);

    let patch = next_patch(
        tail.next()
            .await
            .unwrap()
            .expect("the retry delivers the whole range"),
    );
    assert_eq!(
        patch.from, delivered.to,
        "a failed capture must not advance the delivered watermark"
    );
    assert!(
        patch.changes.iter().any(|change| matches!(
            change,
            TailChange::Add { item } if item.item_id == "item-6" && item.revision == 1
        )),
        "a change staged before the resync must still be delivered: {patch:?}"
    );
    assert!(
        patch.changes.iter().any(|change| matches!(
            change,
            TailChange::UpdateItem { item_id, revision, .. }
                if item_id == "item-5" && *revision == 2
        )),
        "the change that forced the resync must be delivered too: {patch:?}"
    );
    assert_eq!(
        patch
            .changes
            .iter()
            .filter(|change| matches!(change, TailChange::Remove { .. }))
            .count(),
        99,
        "the released previews are still real removals: {patch:?}"
    );
}

/// 已记录的真实变化在 identity 被逐出热预览后不能被当成“本页无变化”跳过。
///
/// 场景：先改一条旧条目，再连续发布 100 条新条目把它挤出 horizon，然后只读一次。旧实现会交付这批
/// 新条目并顺带推进水位，消费者永久停在旧 revision，而连续性看起来仍然正常。
#[tokio::test]
async fn a_change_whose_identity_left_the_preview_tail_resynchronizes_instead_of_being_skipped() {
    let session = Session::new(Stored::with((1..=5).map(|order| item(order, 1, "x", true))));
    let mut tail = session.subscribe_tail().await.unwrap();
    let first = take_initial(&mut tail);
    assert_eq!(first.items.len(), 5);

    // 一条真实变化（已落盘水位由 writer 确认，因此不会留在可靠待保存集合里）。
    session.publish(saved_item(5, 2, "changed", true)).unwrap();
    // 再把这条 identity 挤出 horizon：100 条新条目占满热预览。
    for order in 6..=105 {
        session.publish(saved_item(order, 1, "y", true)).unwrap();
    }

    match tail.next().await.unwrap().unwrap() {
        ChatTailUpdate::Resync { reason, baseline } => {
            assert_eq!(reason, ChatResyncReason::Unavailable);
            assert_eq!(baseline.items.len(), 32);
            assert_eq!(baseline.items.last().unwrap().order, 105);
            assert!(baseline.has_older);
        }
        ChatTailUpdate::Patch(patch) => {
            let delivered = patch.changes.iter().any(|change| {
                matches!(
                    change,
                    TailChange::UpdateItem { item_id, revision, .. }
                        if item_id == "item-5" && *revision == 2
                )
            });
            assert!(
                delivered,
                "a real change of item-5 must be delivered or explicitly resynchronized: {patch:?}"
            );
        }
    }

    // 重同步之后连续性恢复：新发布照常作为连续补丁交付。
    session.publish(saved_item(106, 1, "z", true)).unwrap();
    let patch = next_patch(tail.next().await.unwrap().unwrap());
    assert!(patch.to > patch.from);
}
