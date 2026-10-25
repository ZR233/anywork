//! 按给定身份读取当前元数据：热冷合并、发布竞争、完整长度、资源预算及只读取消。

#[path = "support/timeline.rs"]
mod timeline_support;

use std::{
    collections::BTreeMap,
    sync::{Arc, atomic::Ordering},
};

use pl_core::chat::{
    ChatError, ChatField, ChatItemMetadata, ChatItemMetadataRead, ChatLifecycle,
    PAGE_PREVIEW_BYTES, Session,
};
use pretty_assertions::assert_eq;
use timeline_support::*;

async fn version(session: &Session) -> u64 {
    let mut tail = session.subscribe_tail().await.unwrap();
    tail.initial().unwrap().version
}

fn ids(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| (*value).to_owned()).collect()
}

fn present(item: &pl_core::chat::ChatItem) -> ChatItemMetadataRead {
    ChatItemMetadataRead::Present(ChatItemMetadata {
        item_id: item.item_id.clone(),
        turn_id: item.turn_id.clone(),
        order: item.order,
        revision: item.revision,
        meta: item.meta.clone(),
        fields: item
            .fields
            .iter()
            .map(|(field, preview)| (field.clone(), preview.total_bytes))
            .collect(),
        saved: item.saved,
        lifecycle: item.lifecycle,
    })
}

#[tokio::test]
async fn noncontiguous_identities_merge_hot_cold_and_missing_without_paging_or_retaining_bodies() {
    let mut cold = with_fields(
        "cold-900",
        900,
        7,
        [
            (ChatField::Body, "é".repeat(200_000)),
            (ChatField::host("empty"), String::new()),
        ],
        true,
    );
    cold.meta = Arc::from([0, 255, 17]);
    cold.saved = true;
    let body = cold.body().unwrap().clone();
    let history = Counting::new(Stored::with([
        cold.clone(),
        identified("hot-10", 10, 1, "stale cold", false),
        identified("unrequested-5000", 5000, 1, "not requested", true),
    ]));
    let item_reads = history.item_reads.clone();
    let page_reads = history.page_reads.clone();
    let session = Session::new(history);
    let hot = identified("hot-10", 10, 3, "new hot body", false);
    session.publish_preview(preview_of(&hot, 1)).unwrap();
    session.reserve_order("unpublished").await.unwrap();
    let body_owners = Arc::strong_count(&body);

    let read = session
        .read_metadata(&ids(&["cold-900", "absent", "hot-10", "unpublished"]))
        .await
        .unwrap();

    assert_eq!(
        read,
        vec![
            present(&cold),
            ChatItemMetadataRead::Missing {
                item_id: "absent".to_owned()
            },
            present(&hot),
            ChatItemMetadataRead::Missing {
                item_id: "unpublished".to_owned()
            },
        ]
    );
    assert_eq!(
        item_reads.load(Ordering::Relaxed),
        3,
        "only nonresident IDs use cold point reads"
    );
    assert_eq!(
        page_reads.load(Ordering::Relaxed),
        0,
        "arbitrary IDs must not scan history pages"
    );
    assert_eq!(
        Arc::strong_count(&body),
        body_owners,
        "a result retains no body handle"
    );
    assert_eq!(
        session.resident_revision("cold-900"),
        None,
        "point reads do not seed a cache"
    );
    assert_eq!(session.assigned_order("absent"), None);
    assert!(!session.is_committed("hot-10"));
}

#[tokio::test]
async fn one_hundred_large_cold_items_release_each_decoded_body_before_reading_the_next() {
    let history = GeneratedBodies::new(1024 * 1024);
    let reads = history.item_reads.clone();
    let last_body = history.last_body.clone();
    let session = Session::new(history);
    let requested: Vec<_> = (0..100).map(|index| format!("large-{index}")).collect();

    let result = session.read_metadata(&requested).await.unwrap();

    assert_eq!(result.len(), 100);
    for (index, metadata) in result.into_iter().enumerate() {
        assert_eq!(
            metadata,
            ChatItemMetadataRead::Present(ChatItemMetadata {
                item_id: requested[index].clone(),
                turn_id: "turn-1".to_owned(),
                order: index as u64 + 1,
                revision: 7,
                meta: empty_meta(),
                fields: BTreeMap::from([(ChatField::Body, 1024 * 1024)]),
                saved: false,
                lifecycle: ChatLifecycle::Terminal,
            })
        );
    }
    assert_eq!(reads.load(Ordering::Relaxed), 100);
    assert!(last_body.lock().unwrap().upgrade().is_none());
}

#[tokio::test]
async fn a_cold_wait_reconciles_new_revision_field_set_save_and_terminal_facts() {
    // Revision 1 exercises independent same-revision flags on a captured hot item. Revision 2
    // starts entirely cold and exercises changed field identities, lengths and opaque metadata.
    for revision in [1, 2] {
        let mut initial = with_fields(
            "item-1",
            1,
            1,
            [
                (ChatField::Body, "old body".to_owned()),
                (ChatField::host("removed"), "old field".to_owned()),
            ],
            false,
        );
        if revision == 2 {
            // Even an oversized old cold shell must not cause a budget error after a newer hot
            // revision replaced it while IO awaited. Only the winning metadata is charged.
            initial.meta = Arc::from(vec![0; PAGE_PREVIEW_BYTES + 1]);
        }
        let mut history = GatedHistory::new(Stored::with([initial.clone()]));
        let gate = Arc::new(HistoryGate::new());
        history.item_gate = Some(gate.clone());
        let session = Session::new(history);
        let requested = if revision == 1 {
            session.publish(initial.clone()).unwrap();
            ids(&["item-1", "absent"])
        } else {
            ids(&["item-1"])
        };
        let read = tokio::spawn({
            let session = session.clone();
            async move { session.read_metadata(&requested).await }
        });
        gate.entered().await;
        let mut current = if revision == 1 {
            initial
        } else {
            let mut next = with_fields(
                "item-1",
                1,
                2,
                [
                    (ChatField::Body, "new".to_owned()),
                    (ChatField::host("added"), String::new()),
                ],
                false,
            );
            next.meta = Arc::from([255, 0, 41]);
            next
        };
        current.lifecycle = ChatLifecycle::Terminal;
        current.turn_id = "terminal-turn".to_owned();
        session.publish(current.clone()).unwrap();
        session.confirm_saved("item-1", revision);
        current.saved = true;
        gate.release();

        let mut expected = vec![present(&current)];
        if revision == 1 {
            expected.push(ChatItemMetadataRead::Missing {
                item_id: "absent".to_owned(),
            });
        }
        assert_eq!(read.await.unwrap().unwrap(), expected);
    }
}

#[tokio::test]
async fn a_withdrawal_invalidates_captured_metadata_without_becoming_a_durable_tombstone() {
    for republish_during_read in [false, true] {
        let mut history = GatedHistory::new(Stored::default());
        let gate = Arc::new(HistoryGate::new());
        history.item_gate = Some(gate.clone());
        let session = Session::new(history);
        session
            .publish_preview(item(1, 9, "withdrawn", false))
            .unwrap();
        let read = tokio::spawn({
            let session = session.clone();
            async move { session.read_metadata(&ids(&["item-1", "absent"])).await }
        });
        gate.entered().await;
        session.drop_preview("item-1");
        // Reuse of the string is a new admission, not permission to return the higher pre-withdrawal
        // revision. Both its order and revision differ from the captured candidate.
        let replacement = identified("item-1", 2, 1, "a new admission", true);
        if republish_during_read {
            session.publish(replacement.clone()).unwrap();
        }
        gate.release();
        assert!(matches!(
            read.await.unwrap(),
            Err(ChatError::ReadInvalidated)
        ));
        if !republish_during_read {
            assert_eq!(session.resident_revision("item-1"), None);
            gate.release();
            assert_eq!(
                session.read_metadata(&ids(&["item-1"])).await.unwrap(),
                vec![ChatItemMetadataRead::Missing {
                    item_id: "item-1".to_owned()
                },]
            );
            session.publish(replacement.clone()).unwrap();
        }
        assert_eq!(
            session.read_metadata(&ids(&["item-1"])).await.unwrap(),
            vec![present(&replacement)]
        );
    }
}

#[tokio::test]
async fn an_unprovable_publication_window_or_a_new_shell_lost_during_io_cannot_return_old_metadata()
{
    for expire_window in [false, true] {
        let old = saved_item(1, 1, "same bytes", true);
        let mut history = GatedHistory::new(Stored::with([old.clone()]));
        let gate = Arc::new(HistoryGate::new());
        history.item_gate = Some(gate.clone());
        let session = Session::new(history);
        let read = tokio::spawn({
            let session = session.clone();
            async move { session.read_metadata(&ids(&["item-1"])).await }
        });
        gate.entered().await;
        let mut current = old;
        current.meta = Arc::from([20, 21]);
        session.publish(current).unwrap();
        for order in 2..=if expire_window { 600 } else { 101 } {
            session.publish(saved_item(order, 1, "tail", true)).unwrap();
        }
        gate.release();
        assert!(matches!(
            read.await.unwrap(),
            Err(ChatError::ReadInvalidated)
        ));
    }
}

#[tokio::test]
async fn known_evicted_updates_are_unreadable_instead_of_old_cold_rows_or_missing() {
    // An item's content revision does not identify its opaque shell or field index. These three
    // accepted previews keep the cold order/revision/progress facts while changing the exposed
    // shell, field identities, or complete length. They must not turn into old cold metadata merely
    // because all three leave the recent cache before the query begins.
    let old_shell = identified("item-1", 1, 1, "same body", false);
    let mut current_shell = old_shell.clone();
    current_shell.turn_id = "new-turn".to_owned();
    current_shell.meta = Arc::from([255, 0, 42]);
    let old_index = with_fields(
        "item-2",
        2,
        1,
        [
            (ChatField::Body, "same body".to_owned()),
            (ChatField::host("removed"), String::new()),
        ],
        false,
    );
    let current_index = with_fields(
        "item-2",
        2,
        1,
        [
            (ChatField::Body, "same body".to_owned()),
            (ChatField::host("added"), String::new()),
        ],
        false,
    );
    let old_length = identified("item-3", 3, 1, "old", false);
    let current_length = identified("item-3", 3, 1, "longer body", false);
    let session = Session::new(Stored::with([old_shell, old_index, old_length]));
    let current = [current_shell, current_index, current_length];
    for item in &current {
        session.publish_preview(item.clone()).unwrap();
    }
    let requested: Vec<_> = current.iter().map(|item| item.item_id.clone()).collect();
    let expected: Vec<_> = current.iter().map(present).collect();
    assert_eq!(session.read_metadata(&requested).await.unwrap(), expected);
    for order in 4..=103 {
        session.publish(saved_item(order, 1, "tail", true)).unwrap();
    }
    for id in &requested {
        let read = session.read_metadata(std::slice::from_ref(id)).await;
        assert!(
            matches!(read, Err(ChatError::ReadInvalidated)),
            "an evicted same-revision metadata update cannot return the old cold shell/index: {id}: {read:?}"
        );
    }
    // Reliable ownership makes the exact current metadata readable again even outside recent.
    for item in current {
        session.publish(item).unwrap();
    }
    assert_eq!(session.read_metadata(&requested).await.unwrap(), expected);

    for has_cold_row in [false, true] {
        let history = Stored::with(has_cold_row.then(|| saved_item(1, 1, "old", false)));
        let session = Session::new(history);
        // The old reliable effect remains pending, but a newer acknowledged streaming revision is
        // no longer resident after the tail advances. The publication log proves the old effect is
        // not the current item. Neither that effect nor the stale/absent cold row may answer.
        session.publish(item(1, 1, "pending", false)).unwrap();
        session
            .publish(saved_item(1, 2, "newer durable", false))
            .unwrap();
        for order in 2..=101 {
            session.publish(saved_item(order, 1, "tail", true)).unwrap();
        }
        assert!(matches!(
            session.read_metadata(&ids(&["item-1"])).await,
            Err(ChatError::ReadInvalidated)
        ));
        // An acknowledgement of the older pending effect must not erase the newer publication's
        // progress proof merely by being the last log entry for the identity.
        session.confirm_saved("item-1", 1);
        assert!(matches!(
            session.read_metadata(&ids(&["item-1"])).await,
            Err(ChatError::ReadInvalidated)
        ));
    }
    // A published speculative identity can lose its preview without becoming Missing. Its existing
    // reservation/terminal proof still defeats a cold same-revision nonterminal row.
    let session = Session::new(Stored::with([saved_item(1, 1, "old", false)]));
    session
        .publish_preview(item(1, 1, "terminal preview", true))
        .unwrap();
    for order in 2..=600 {
        session.publish(saved_item(order, 1, "tail", true)).unwrap();
    }
    assert!(matches!(
        session.read_metadata(&ids(&["item-1"])).await,
        Err(ChatError::ReadInvalidated)
    ));
}

#[tokio::test]
async fn validation_and_known_budget_failures_reject_before_cold_io_without_session_side_effects() {
    let history = Counting::new(Stored::default());
    let reads = history.item_reads.clone();
    let session = Session::new(history);
    let before = version(&session).await;
    for rejected in [
        Vec::new(),
        (0..101).map(|index| format!("item-{index}")).collect(),
        ids(&["item-1", "item-1"]),
        ids(&["item-1", ""]),
    ] {
        assert!(matches!(
            session.read_metadata(&rejected).await,
            Err(ChatError::InvalidArgument(_))
        ));
    }
    assert!(matches!(
        session
            .read_metadata(&["x".repeat(PAGE_PREVIEW_BYTES)])
            .await,
        Err(ChatError::Overloaded(_))
    ));
    assert_eq!(reads.load(Ordering::Relaxed), 0);
    assert_eq!(version(&session).await, before);
    let accepted: Vec<_> = (0..100).map(|index| format!(" /中文\t{index}- ")).collect();
    assert_eq!(
        session.read_metadata(&accepted).await.unwrap(),
        accepted
            .iter()
            .map(|id| ChatItemMetadataRead::Missing {
                item_id: id.clone()
            })
            .collect::<Vec<_>>()
    );
    assert_eq!(reads.load(Ordering::Relaxed), 100);
    assert_eq!(version(&session).await, before);
    assert_eq!(session.assigned_order(&accepted[0]), None);
    assert_eq!(session.reserve_order("after-read").await.unwrap(), 1);
    session.release_unpublished_order("after-read");

    for order in 1..=10 {
        let mut item = item(order, 1, "", false);
        item.meta = Arc::from(vec![0; 220 * 1024]);
        session.publish(item).unwrap();
    }
    let before = version(&session).await;
    let requested = std::iter::once("not-hot".to_owned())
        .chain((1..=10).map(|order| format!("item-{order}")))
        .collect::<Vec<_>>();
    assert!(matches!(
        session.read_metadata(&requested).await,
        Err(ChatError::Overloaded(_))
    ));
    assert_eq!(
        reads.load(Ordering::Relaxed),
        100,
        "all known metadata is charged before any cold IO"
    );
    assert_eq!(version(&session).await, before);
    assert_eq!(session.assigned_order("not-hot"), None);
    session.confirm_saved("item-1", 1);
    assert_eq!(
        version(&session).await,
        before + 1,
        "the rejected read did not acknowledge the pending effect"
    );
}

#[tokio::test]
async fn the_metadata_budget_charges_the_whole_structure_and_never_truncates_or_reads_past_failure()
{
    let mut exact = with_fields(
        "item-1",
        1,
        1,
        [
            (ChatField::Body, "x".repeat(3 * 1024 * 1024)),
            (ChatField::host("variable-key"), String::new()),
        ],
        true,
    );
    exact.meta = Arc::from(vec![
        255;
        PAGE_PREVIEW_BYTES - exact.preview_structure_bytes()
            + exact.meta.len()
    ]);
    assert_eq!(exact.preview_structure_bytes(), PAGE_PREVIEW_BYTES);
    let session = Session::new(Stored::with([exact.clone()]));
    assert_eq!(
        session.read_metadata(&ids(&["item-1"])).await.unwrap(),
        vec![present(&exact)]
    );

    let mut longer_id = exact.clone();
    longer_id.item_id.push('x');
    let mut longer_turn = exact.clone();
    longer_turn.turn_id.push('x');
    let mut longer_meta = exact.clone();
    longer_meta.meta = Arc::from(vec![255; longer_meta.meta.len() + 1]);
    let mut longer_key = exact.clone();
    let empty = longer_key
        .fields
        .remove(&ChatField::host("variable-key"))
        .unwrap();
    longer_key
        .fields
        .insert(ChatField::host("variable-keyx"), empty);
    let mut extra_field = exact.clone();
    extra_field.fields.insert(
        ChatField::host(""),
        pl_core::chat::ChatFieldPreview::complete(pl_core::model::ContentBlock::from_text("")),
    );
    for oversized in [longer_id, longer_turn, longer_meta, longer_key, extra_field] {
        let id = oversized.item_id.clone();
        let history = Counting::new(Stored::with([oversized]));
        let reads = history.item_reads.clone();
        let session = Session::new(history);
        assert!(matches!(
            session.read_metadata(&[id]).await,
            Err(ChatError::Overloaded(_))
        ));
        assert_eq!(reads.load(Ordering::Relaxed), 1);
        assert_eq!(session.resident_revision("item-1"), None);
    }
    let history = Counting::new(Stored::with([exact]));
    let reads = history.item_reads.clone();
    let session = Session::new(history);
    assert!(matches!(
        session
            .read_metadata(&ids(&["item-1", "must-not-be-read"]))
            .await,
        Err(ChatError::Overloaded(_))
    ));
    assert_eq!(
        reads.load(Ordering::Relaxed),
        1,
        "no further IO follows a known result-budget overflow"
    );
}

#[tokio::test]
async fn metadata_growth_during_cold_io_rechecks_the_whole_budget_without_publishing_partial_results()
 {
    // Ten legal cold shells fit, but the eleventh would exceed the old running total. While its IO
    // waits, the first identity advances to a smaller revision: the complete current result fits and
    // must be returned, rather than rejected using the first identity's stale captured cost.
    {
        let durable: Vec<_> = (1..=11)
            .map(|order| {
                let mut item = saved_item(order, 1, "", false);
                item.meta = Arc::from(vec![0; 200 * 1024]);
                item
            })
            .collect();
        let requested: Vec<_> = durable.iter().map(|item| item.item_id.clone()).collect();
        let mut expected: Vec<_> = durable.iter().map(present).collect();
        let mut history = GatedHistory::new(Stored::with(durable));
        let gate = Arc::new(HistoryGate::new());
        history.item_gate = Some(gate.clone());
        let session = Session::new(history);
        let read = tokio::spawn({
            let session = session.clone();
            async move { session.read_metadata(&requested).await }
        });
        for _ in 0..10 {
            gate.entered().await;
            gate.release();
        }
        gate.entered().await;
        let mut smaller = item(1, 2, "", false);
        smaller.meta = Arc::from([1, 2]);
        session.publish(smaller.clone()).unwrap();
        expected[0] = present(&smaller);
        let after_publication = version(&session).await;
        gate.release();
        assert_eq!(read.await.unwrap().unwrap(), expected);
        assert_eq!(version(&session).await, after_publication);
        assert_eq!(session.resident_revision("item-1"), Some(2));
        assert_eq!(
            session.assigned_order("item-11"),
            None,
            "cold metadata reads do not hydrate items or allocate orders"
        );
    }

    let mut history = GatedHistory::new(Stored::default());
    let gate = Arc::new(HistoryGate::new());
    history.item_gate = Some(gate.clone());
    let session = Session::new(history);
    for order in 1..=10 {
        let mut initial = item(order, 1, "", false);
        initial.meta = Arc::from(vec![0; 200 * 1024]);
        session.publish(initial).unwrap();
    }
    let requested = (1..=10)
        .map(|order| format!("item-{order}"))
        .chain(std::iter::once("absent".to_owned()))
        .collect::<Vec<_>>();
    let read = tokio::spawn({
        let session = session.clone();
        async move { session.read_metadata(&requested).await }
    });
    gate.entered().await;
    for order in 1..=3 {
        let mut next = item(order, 2, "", false);
        next.meta = Arc::from(vec![0; 220 * 1024]);
        session.publish(next).unwrap();
    }
    let after_publication = version(&session).await;
    gate.release();
    assert!(matches!(read.await.unwrap(), Err(ChatError::Overloaded(_))));
    assert_eq!(version(&session).await, after_publication);
    assert_eq!(session.assigned_order("absent"), None);
    assert_eq!(session.resident_revision("item-1"), Some(2));
}

#[tokio::test]
async fn a_cancelled_metadata_future_releases_candidates_and_leaves_version_and_order_unchanged() {
    let mut history = GatedHistory::new(Stored::with([saved_item(1, 1, "cold", true)]));
    let gate = Arc::new(HistoryGate::new());
    history.item_gate = Some(gate.clone());
    let session = Session::new(history);
    let before = version(&session).await;
    let read = tokio::spawn({
        let session = session.clone();
        async move { session.read_metadata(&ids(&["absent"])).await }
    });
    gate.entered().await;
    read.abort();
    assert!(read.await.unwrap_err().is_cancelled());
    assert_eq!(version(&session).await, before);
    assert_eq!(session.assigned_order("absent"), None);
    gate.release();
    assert_eq!(
        session.read_metadata(&ids(&["absent"])).await.unwrap(),
        vec![ChatItemMetadataRead::Missing {
            item_id: "absent".to_owned()
        }]
    );
    assert_eq!(version(&session).await, before);
}
