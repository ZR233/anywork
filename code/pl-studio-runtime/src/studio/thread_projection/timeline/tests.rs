use super::*;
use pl_protocol::{
    ChatActiveStatus, ChatAtomContent, ChatContentRole, ChatFactPosition, ContentRef,
    ContentTarget, ThreadTextChannel,
};

fn pos(effect: u64, suborder: u32) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq: effect,
        suborder,
    }
}

fn source() -> ChatSourceId {
    ChatSourceId::ForegroundTurn {
        turn_id: "turn".into(),
    }
}

fn content() -> Vec<ChatAtomContent> {
    vec![ChatAtomContent {
        role: ChatContentRole::Body,
        reference: ContentRef {
            database_id: "db".into(),
            target: ContentTarget::ItemPayload {
                item_id: "member".into(),
            },
        },
    }]
}

fn active(
    id: &str,
    kind: ChatAtomKind,
    order: u64,
    started: ChatFactPosition,
    contents: Vec<ChatAtomContent>,
) -> ChatAtom {
    ChatAtom {
        id: id.into(),
        completion_item_id: None,
        content_present: None,
        completion_seq: None,
        source: source(),
        source_state: None,
        source_order: Some(order),
        kind,
        delivery: ChatDeliveryKind::Foreground,
        lifecycle: ChatAtomLifecycle::Active {
            started: Some(started),
            status: ChatActiveStatus::Running,
        },
        turn_id: Some("turn".into()),
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: match kind {
            ChatAtomKind::Text => Some(ThreadTextChannel::Final),
            _ => None,
        },
        started_at: Some(10),
        finished_at: None,
        contents,
        payload: None,
    }
}

fn terminal(
    id: &str,
    kind: ChatAtomKind,
    order: u64,
    started: ChatFactPosition,
    ended: ChatFactPosition,
    contents: Vec<ChatAtomContent>,
) -> ChatAtom {
    let mut atom = active(id, kind, order, started, contents);
    atom.completion_item_id = Some(id.into());
    atom.content_present = (id == "empty").then_some(false);
    atom.finished_at = Some(20);
    atom.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(started),
        ended: Some(ended),
        outcome: ChatTerminalOutcome::Completed,
    };
    atom
}

fn background(id: &str, order: u64, ended: ChatFactPosition) -> ChatAtom {
    let mut atom = terminal(id, ChatAtomKind::Receipt, order, ended, ended, content());
    atom.source = ChatSourceId::BackgroundResult {
        message_id: "message".into(),
    };
    atom.delivery = ChatDeliveryKind::Independent;
    atom.turn_id = None;
    atom.text_channel = None;
    atom
}

fn status(id: &str, order: u64, started: ChatFactPosition, ended: ChatFactPosition) -> ChatAtom {
    let mut atom = terminal(id, ChatAtomKind::Receipt, order, started, ended, content());
    atom.source = ChatSourceId::Receipt {
        receipt_id: id.into(),
    };
    atom.delivery = ChatDeliveryKind::Independent;
    atom.turn_id = None;
    atom.text_channel = None;
    atom
}

fn fold() -> TimelineProjection {
    TimelineProjection::new("db".into(), "test-generation".into(), 0)
}

fn assert_projection_retention(timeline: &TimelineProjection) -> u64 {
    let canonical = serde_json::to_vec(&(
        &timeline.items,
        &timeline.active,
        &timeline.committed,
        &timeline.changes,
        &timeline.facts,
    ))
    .unwrap();
    let expected = canonical.len() as u64 + std::mem::size_of::<OnceLock<u64>>() as u64;
    assert_eq!(timeline.retained_bytes(), expected);
    expected
}

#[test]
fn mutable_projection_retention_tracks_fold_restore_and_drains() {
    let mut timeline = fold();
    assert_projection_retention(&timeline);
    let started = active("tool", ChatAtomKind::ToolCall, 1, pos(1, 0), Vec::new());
    timeline.observe(&started, None).unwrap();
    let first = assert_projection_retention(&timeline);
    timeline.observe(&started, None).unwrap();
    timeline.refresh_current(&started).unwrap();
    assert_eq!(assert_projection_retention(&timeline), first);
    let mut waiting = started.clone();
    waiting.lifecycle = ChatAtomLifecycle::Active {
        started: Some(pos(1, 0)),
        status: ChatActiveStatus::Waiting,
    };
    waiting.contents = content();
    timeline.observe(&waiting, None).unwrap();
    assert_projection_retention(&timeline);
    timeline.refresh_current(&started).unwrap();
    assert_projection_retention(&timeline);
    let update = timeline.take_update().unwrap();
    assert_projection_retention(&timeline);
    let recovery = update.recovery().to_vec();
    let update_bytes = serde_json::to_vec(&update).unwrap();
    let mut restored = fold();
    assert_projection_retention(&restored);
    restored.restore_recovery(&recovery).unwrap();
    assert_projection_retention(&restored);
    assert_eq!(restored.current_items(), timeline.current_items());
    assert_eq!(restored.take_update().unwrap().recovery(), recovery);
    assert_projection_retention(&restored);
    let frozen = timeline.clone();
    let frozen_bytes = assert_projection_retention(&frozen);
    let ended = terminal(
        "tool",
        ChatAtomKind::ToolCall,
        1,
        pos(1, 0),
        pos(2, 0),
        content(),
    );
    timeline.observe(&ended, None).unwrap();
    assert_eq!(assert_projection_retention(&timeline), frozen_bytes);
    timeline
        .complete(
            ended,
            1,
            Some(PayloadData::Inline {
                bytes: b"done".to_vec(),
            }),
        )
        .unwrap();
    assert_projection_retention(&timeline);
    timeline.end_source(&source());
    let closed = assert_projection_retention(&timeline);
    timeline.end_source(&source());
    assert_eq!(assert_projection_retention(&timeline), closed);
    timeline.commit_ready().unwrap();
    assert_eq!(timeline.committed().len(), 1);
    let committed = assert_projection_retention(&timeline);
    timeline.commit_ready().unwrap();
    assert_eq!(assert_projection_retention(&timeline), committed);
    assert_eq!(timeline.take_committed().len(), 1);
    assert_projection_retention(&timeline);
    timeline.take_update().unwrap();
    assert_projection_retention(&timeline);
    assert_eq!(assert_projection_retention(&frozen), frozen_bytes);
    assert_eq!(serde_json::to_vec(&update).unwrap(), update_bytes);

    // A text start closes a preceding work group's admission, without completing its member.
    let work = active("work", ChatAtomKind::Reasoning, 2, pos(3, 0), Vec::new());
    timeline.observe(&work, None).unwrap();
    assert_projection_retention(&timeline);
    let text = active("text", ChatAtomKind::Text, 3, pos(4, 0), content());
    timeline.close_group_for(&source(), key(&text, None, false));
    assert_projection_retention(&timeline);
    timeline.observe(&text, None).unwrap();
    assert_projection_retention(&timeline);
    timeline
        .complete(
            terminal(
                "work",
                ChatAtomKind::Reasoning,
                2,
                pos(3, 0),
                pos(5, 0),
                Vec::new(),
            ),
            2,
            None,
        )
        .unwrap();
    assert_projection_retention(&timeline);
    timeline.commit_ready().unwrap();
    assert_projection_retention(&timeline);
    timeline
        .complete(
            terminal(
                "text",
                ChatAtomKind::Text,
                3,
                pos(4, 0),
                pos(6, 0),
                content(),
            ),
            3,
            None,
        )
        .unwrap();
    assert_projection_retention(&timeline);
    timeline.commit_ready().unwrap();
    assert_projection_retention(&timeline);
    assert_eq!(timeline.take_committed().len(), 2);
    assert_projection_retention(&timeline);
    timeline.take_update().unwrap();
    assert_projection_retention(&timeline);
}

#[test]
fn legacy_member_restore_invalidates_projection_retention() {
    let mut timeline = fold();
    let ended = terminal(
        "legacy",
        ChatAtomKind::ToolCall,
        1,
        pos(1, 0),
        pos(2, 0),
        content(),
    );
    assert_projection_retention(&timeline);
    timeline.admit_legacy_header(&ended).unwrap();
    assert_projection_retention(&timeline);
    let item = timeline.current_items().remove(0);
    timeline
        .restore_legacy_member(item.id.clone(), 0, &ended)
        .unwrap();
    let restored = assert_projection_retention(&timeline);
    timeline.restore_legacy_member(item.id, 0, &ended).unwrap();
    assert_eq!(assert_projection_retention(&timeline), restored);
    timeline.complete(ended, 1, None).unwrap();
    assert_projection_retention(&timeline);
    timeline.end_source(&source());
    assert_projection_retention(&timeline);
    timeline.commit_ready().unwrap();
    assert_projection_retention(&timeline);
    assert_eq!(timeline.take_committed().len(), 1);
    assert_projection_retention(&timeline);
}

// The persisted shape before retention caching, including its canonical field order.
fn canonical_update_bytes(update: &TimelineUpdate) -> Vec<u8> {
    #[derive(Serialize)]
    struct CanonicalUpdate<'a> {
        facts: &'a [ChatAtom],
        members: &'a [MemberChange],
        current: &'a [TimelineItem],
        recovery: &'a [u8],
        next_position: u64,
        generation: &'a str,
    }
    serde_json::to_vec(&CanonicalUpdate {
        facts: update.facts(),
        members: update.members(),
        current: update.current(),
        recovery: update.recovery(),
        next_position: update.next_position(),
        generation: update.generation(),
    })
    .unwrap()
}

#[test]
fn frozen_update_retention_preserves_canonical_serialization() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("tool", ChatAtomKind::ToolCall, 1, pos(1, 1), content()),
            None,
        )
        .unwrap();
    for update in [TimelineUpdate::default(), timeline.take_update().unwrap()] {
        let canonical = canonical_update_bytes(&update);
        let expected = canonical.len() as u64 + std::mem::size_of::<OnceLock<u64>>() as u64;
        assert_eq!(serde_json::to_vec(&update).unwrap(), canonical);
        assert_eq!(update.retained_bytes(), expected);
        assert_eq!(update.retained_bytes(), expected);
        assert_eq!(serde_json::to_vec(&update).unwrap(), canonical);
        let cloned = update.clone();
        assert_eq!(cloned.retained_bytes(), expected);
        assert_eq!(serde_json::to_vec(&cloned).unwrap(), canonical);
        let restored: TimelineUpdate = serde_json::from_slice(&canonical).unwrap();
        assert_eq!(restored.retained_bytes(), expected);
        assert_eq!(serde_json::to_vec(&restored).unwrap(), canonical);
    }
}

#[test]
fn frozen_update_retention_counts_recovery_json_numbers() {
    let mut timeline = TimelineProjection::new("db".into(), "test-generation".into(), 37);
    timeline
        .observe(
            &active(
                "retention",
                ChatAtomKind::ToolCall,
                17,
                pos(23, 4),
                content(),
            ),
            None,
        )
        .unwrap();
    let base = timeline.take_update().unwrap();
    assert!(!base.facts().is_empty());
    assert!(!base.members().is_empty());
    assert!(!base.current().is_empty());
    assert_ne!(base.next_position(), 0);
    assert!(!base.generation().is_empty());

    let cases = [
        Vec::new(),
        vec![0],
        vec![9],
        vec![10],
        vec![99],
        vec![100],
        vec![255],
        vec![0, 9, 10, 99, 100, 255],
        (0..=u8::MAX).collect(),
    ];
    for recovery in cases {
        let mut update = base.clone();
        update.recovery = recovery;
        let canonical = canonical_update_bytes(&update);
        assert_eq!(serde_json::to_vec(&update).unwrap(), canonical);
        let expected = canonical.len() as u64 + std::mem::size_of::<OnceLock<u64>>() as u64;
        assert_eq!(update.retained_bytes(), expected);
        assert_eq!(serde_json::to_vec(&update).unwrap(), canonical);
    }
}

fn kinds(items: &[TimelineItem]) -> Vec<(TimelineItemKind, u64)> {
    items
        .iter()
        .map(|item| (item.kind, item.position.unwrap_or(u64::MAX)))
        .collect()
}

#[test]
fn one_work_group_then_one_text_item_in_same_turn() {
    let mut timeline = fold();
    let reasoning = active(
        "reasoning",
        ChatAtomKind::Reasoning,
        1,
        pos(1, 0),
        Vec::new(),
    );
    timeline.observe(&reasoning, None).unwrap();
    timeline
        .complete(
            terminal(
                "reasoning",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(2, 0),
                Vec::new(),
            ),
            1,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert!(timeline.committed().is_empty());

    timeline
        .observe(
            &active("text", ChatAtomKind::Text, 2, pos(3, 0), content()),
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::WorkGroup, 0)]
    );
    assert_eq!(timeline.current_items().len(), 1);

    timeline
        .complete(
            terminal(
                "text",
                ChatAtomKind::Text,
                2,
                pos(3, 0),
                pos(4, 0),
                content(),
            ),
            2,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![
            (TimelineItemKind::WorkGroup, 0),
            (TimelineItemKind::Text, 1)
        ]
    );
}

#[test]
fn reverse_terminal_history_keeps_source_order() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .observe(
            &active("t", ChatAtomKind::Text, 2, pos(2, 0), content()),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal("t", ChatAtomKind::Text, 2, pos(2, 0), pos(3, 0), content()),
            1,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert!(timeline.committed().is_empty());
    timeline
        .complete(
            terminal(
                "r",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(4, 0),
                Vec::new(),
            ),
            2,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![
            (TimelineItemKind::WorkGroup, 0),
            (TimelineItemKind::Text, 1)
        ]
    );
}

#[test]
fn background_result_commits_before_a_still_running_text() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("t", ChatAtomKind::Text, 1, pos(1, 0), content()),
            None,
        )
        .unwrap();
    timeline
        .complete(background("b", 2, pos(2, 0)), 1, None)
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::Status, 0)]
    );
    timeline
        .complete(
            terminal("t", ChatAtomKind::Text, 1, pos(1, 0), pos(3, 0), content()),
            2,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::Status, 0), (TimelineItemKind::Text, 1)]
    );
}

#[test]
fn a_text_boundary_splits_work_into_two_groups() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("r1", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal(
                "r1",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(2, 0),
                Vec::new(),
            ),
            1,
            None,
        )
        .unwrap();
    timeline
        .observe(
            &active("t", ChatAtomKind::Text, 2, pos(3, 0), content()),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal("t", ChatAtomKind::Text, 2, pos(3, 0), pos(4, 0), content()),
            2,
            None,
        )
        .unwrap();
    timeline
        .observe(
            &active("r2", ChatAtomKind::Reasoning, 3, pos(5, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal(
                "r2",
                ChatAtomKind::Reasoning,
                3,
                pos(5, 0),
                pos(6, 0),
                Vec::new(),
            ),
            3,
            None,
        )
        .unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![
            (TimelineItemKind::WorkGroup, 0),
            (TimelineItemKind::Text, 1),
            (TimelineItemKind::WorkGroup, 2)
        ]
    );
}

#[test]
fn empty_text_splits_groups_without_painting_a_card() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("r1", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal(
                "r1",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(2, 0),
                Vec::new(),
            ),
            1,
            None,
        )
        .unwrap();
    timeline
        .observe(
            &active("empty", ChatAtomKind::Text, 2, pos(3, 0), vec![]),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal("empty", ChatAtomKind::Text, 2, pos(3, 0), pos(4, 0), vec![]),
            2,
            None,
        )
        .unwrap();
    timeline
        .observe(
            &active("r2", ChatAtomKind::Reasoning, 3, pos(5, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal(
                "r2",
                ChatAtomKind::Reasoning,
                3,
                pos(5, 0),
                pos(6, 0),
                Vec::new(),
            ),
            3,
            None,
        )
        .unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![
            (TimelineItemKind::WorkGroup, 0),
            (TimelineItemKind::WorkGroup, 1)
        ]
    );
}

#[test]
fn source_end_closes_admission_but_waits_for_the_last_terminal() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    assert!(timeline.committed().is_empty());
    timeline
        .complete(
            terminal(
                "r",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(2, 0),
                Vec::new(),
            ),
            1,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::WorkGroup, 0)]
    );
}

#[test]
fn repeated_observation_is_idempotent() {
    let mut timeline = fold();
    let atom = active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new());
    timeline.observe(&atom, None).unwrap();
    timeline.observe(&atom, None).unwrap();
    assert_eq!(timeline.current_items().len(), 1);
    assert_eq!(
        timeline.current_items()[0]
            .summary
            .as_ref()
            .unwrap()
            .member_count,
        1
    );
}

#[test]
fn restored_current_fragments_continue_the_same_projection() {
    let mut timeline = fold();
    let empty_recovery = serde_json::to_vec(&Recovery {
        items: timeline.items.clone(),
        active: timeline.active.clone(),
    })
    .unwrap();
    assert_eq!(timeline.take_update().unwrap().recovery, empty_recovery);
    timeline
        .observe(
            &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .observe(
            &active("t", ChatAtomKind::Text, 2, pos(2, 0), content()),
            None,
        )
        .unwrap();
    let current = timeline.current_items();
    let owned_recovery = serde_json::to_vec(&Recovery {
        items: timeline.items.clone(),
        active: timeline.active.clone(),
    })
    .unwrap();
    let recovery = timeline.take_update().unwrap().recovery;
    assert_eq!(recovery, owned_recovery);

    let mut restored = TimelineProjection::new("db".into(), "test-generation".into(), 0);
    restored.restore_recovery(&recovery).unwrap();
    assert_eq!(
        restored
            .current_items()
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>(),
        current
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>()
    );
    let restored_owned_recovery = serde_json::to_vec(&Recovery {
        items: restored.items.clone(),
        active: restored.active.clone(),
    })
    .unwrap();
    assert_eq!(
        restored.take_update().unwrap().recovery,
        restored_owned_recovery
    );

    for (projection, sequence) in [(&mut timeline, 1), (&mut restored, 1)] {
        projection
            .complete(
                terminal("t", ChatAtomKind::Text, 2, pos(2, 0), pos(3, 0), content()),
                sequence,
                None,
            )
            .unwrap();
        projection.commit_ready().unwrap();
    }
    assert!(timeline.committed().is_empty());
    assert!(restored.committed().is_empty());

    for (projection, sequence) in [(&mut timeline, 2), (&mut restored, 2)] {
        projection
            .complete(
                terminal(
                    "r",
                    ChatAtomKind::Reasoning,
                    1,
                    pos(1, 0),
                    pos(4, 0),
                    Vec::new(),
                ),
                sequence,
                None,
            )
            .unwrap();
        projection.commit_ready().unwrap();
    }
    assert_eq!(kinds(timeline.committed()), kinds(restored.committed()));
}

#[test]
fn independent_status_item_does_not_split_the_foreground_group() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
            None,
        )
        .unwrap();
    timeline
        .complete(status("receipt", 2, pos(2, 0), pos(2, 0)), 1, None)
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::Status, 0)]
    );
    assert_eq!(timeline.current_items().len(), 1);
    timeline
        .complete(
            terminal(
                "r",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(3, 0),
                Vec::new(),
            ),
            2,
            None,
        )
        .unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    assert_eq!(
        kinds(timeline.committed()),
        vec![
            (TimelineItemKind::Status, 0),
            (TimelineItemKind::WorkGroup, 1)
        ]
    );
}

#[test]
fn member_order_is_admission_order_and_recovery_does_not_grow_with_finished_members() {
    let mut timeline = fold();
    let mut max_recovery = 0;
    for index in 0..1024u64 {
        let id = format!("member-{:04}", 1024 - index);
        let atom = active(
            &id,
            ChatAtomKind::ToolCall,
            index + 1,
            pos(index + 1, 0),
            Vec::new(),
        );
        timeline.observe(&atom, None).unwrap();
        let start = timeline.take_update().unwrap();
        assert_eq!(start.members[0].member_order, index);
        let mut end = terminal(
            &id,
            ChatAtomKind::ToolCall,
            index + 1,
            pos(index + 1, 0),
            pos(index + 1, 1),
            Vec::new(),
        );
        if index % 2 == 0 {
            end.lifecycle = ChatAtomLifecycle::Terminal {
                started: Some(pos(index + 1, 0)),
                ended: Some(pos(index + 1, 1)),
                outcome: ChatTerminalOutcome::Failed,
            };
        }
        timeline
            .complete(
                end,
                index + 1,
                Some(PayloadData::Inline {
                    bytes: vec![b'x'; 8192],
                }),
            )
            .unwrap();
        let update = timeline.take_update().unwrap();
        assert_eq!(update.members[0].member_order, index);
        assert!(update.members[0].atom.payload.is_none());
        assert_eq!(update.members.len(), 1);
        max_recovery = max_recovery.max(update.recovery.len());
    }
    assert!(
        max_recovery < 4096,
        "completed members leaked into recovery: {max_recovery}"
    );
    let summary = timeline.current_items()[0].summary.clone().unwrap();
    assert_eq!(summary.member_count, 1024);
    assert_eq!(summary.failed_count, 512);
    assert_eq!(summary.active_count, 0);
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    assert_eq!(timeline.committed().len(), 1);
    assert_eq!(timeline.committed()[0].outcome, None);
}

#[test]
fn unknown_content_is_not_empty_and_text_keeps_real_terminal_outcome() {
    for (present, expected) in [(None, 1), (Some(true), 1), (Some(false), 0)] {
        let mut timeline = fold();
        let mut text = terminal(
            "text",
            ChatAtomKind::Text,
            1,
            pos(1, 0),
            pos(2, 0),
            Vec::new(),
        );
        text.content_present = present;
        text.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(pos(1, 0)),
            ended: Some(pos(2, 0)),
            outcome: ChatTerminalOutcome::Cancelled,
        };
        timeline.complete(text, 1, None).unwrap();
        timeline.commit_ready().unwrap();
        assert_eq!(timeline.committed().len(), expected);
        if expected > 0 {
            assert_eq!(
                timeline.committed()[0].outcome,
                Some(ChatTerminalOutcome::Cancelled)
            );
        }
    }
}

#[test]
fn latest_terminal_time_is_not_the_last_member_in_source_order() {
    let mut timeline = fold();
    for (id, order) in [("z", 1), ("a", 2)] {
        timeline
            .observe(
                &active(
                    id,
                    ChatAtomKind::ToolCall,
                    order,
                    pos(1, order as u32),
                    Vec::new(),
                ),
                None,
            )
            .unwrap();
    }
    let mut last_source = terminal(
        "a",
        ChatAtomKind::ToolCall,
        2,
        pos(1, 2),
        pos(2, 0),
        Vec::new(),
    );
    last_source.finished_at = Some(20);
    timeline.complete(last_source, 1, None).unwrap();
    let mut last_terminal = terminal(
        "z",
        ChatAtomKind::ToolCall,
        1,
        pos(1, 1),
        pos(3, 0),
        Vec::new(),
    );
    last_terminal.finished_at = Some(30);
    timeline.complete(last_terminal, 2, None).unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    assert_eq!(timeline.committed()[0].finished_at, Some(30));
}

#[test]
fn position_exhaustion_is_an_error_not_a_saturated_duplicate() {
    let mut timeline =
        TimelineProjection::new("db".into(), "test-generation".into(), i64::MAX as u64);
    timeline
        .complete(status("s", 1, pos(1, 0), pos(1, 1)), 1, None)
        .unwrap();
    assert!(timeline.commit_ready().is_err());
    assert!(timeline.committed().is_empty());
}

#[test]
fn active_turn_receipt_is_not_an_extra_current_item() {
    let mut timeline = fold();
    let receipt = active(
        "turn-preview",
        ChatAtomKind::TurnReceipt,
        1,
        pos(1, 0),
        Vec::new(),
    );
    timeline.observe(&receipt, None).unwrap();
    timeline.commit_ready().unwrap();
    assert!(timeline.current_items().is_empty());
    assert!(timeline.committed().is_empty());
}

#[test]
fn active_head_updates_never_rewrite_the_frozen_start_phase() {
    let mut timeline = fold();
    let wait = ThreadWaitPresentation::new(
        ThreadWaitIntent::Events {
            targets: vec![ThreadWaitTarget::new(
                "task:prior-turn-sleep-call".into(),
                Some("sleep".into()),
                None,
                Some(ThreadWaitTargetStatus::Running),
            )],
            timeout_ms: 5000,
        },
        ThreadWaitState::Waiting,
        None,
    );
    let mut started = active("tool", ChatAtomKind::ToolCall, 1, pos(1, 1), Vec::new());
    started.tool = Some(ChatToolIdentity {
        call_id: "wait-call".into(),
        name: "wait".into(),
    });
    started.wait = Some(wait.clone());
    timeline.observe(&started, None).unwrap();
    assert_projection_retention(&timeline);
    let mut waiting = started.clone();
    waiting.lifecycle = ChatAtomLifecycle::Active {
        started: Some(pos(1, 1)),
        status: ChatActiveStatus::Waiting,
    };
    waiting.contents = content();
    timeline.observe(&waiting, None).unwrap();
    assert_projection_retention(&timeline);
    let first = timeline.take_update().unwrap();
    assert_eq!(first.facts.len(), 1);
    assert_eq!(first.facts[0].id, "tool");
    assert_eq!(first.facts[0].lifecycle, started.lifecycle);
    assert!(first.facts[0].wait.is_none());
    assert_eq!(first.members.len(), 2);
    assert_eq!(first.members[0].atom.wait.as_ref(), Some(&wait));
    let head = &first.members[1].atom;
    assert_eq!(head.id, "tool");
    assert_eq!(head.source, source());
    assert_eq!(head.tool.as_ref().unwrap().call_id, "wait-call");
    assert_eq!(head.lifecycle, waiting.lifecycle);
    assert_eq!(head.contents, waiting.contents);
    assert_eq!(head.wait.as_ref(), Some(&wait));
    assert!(head.payload.is_none());

    let mut restored = fold();
    restored.restore_recovery(&first.recovery).unwrap();
    assert_eq!(restored.active["tool"].atom.wait.as_ref(), Some(&wait));
    assert_eq!(restored.active["tool"].atom.lifecycle, waiting.lifecycle);
    assert_projection_retention(&restored);
    restored.observe(&waiting, None).unwrap();
    assert!(
        restored.changes.is_empty(),
        "the recovered head changed without a new same-cut fact"
    );
    waiting.lifecycle = started.lifecycle.clone();
    waiting.wait = None;
    restored.observe(&waiting, None).unwrap();
    assert_projection_retention(&restored);
    let update = restored.take_update().unwrap();
    assert!(
        update.facts.is_empty(),
        "a restored mutable head became a new start"
    );
    assert_eq!(update.members.len(), 1);
    assert_eq!(update.members[0].atom.lifecycle, started.lifecycle);
    assert!(update.members[0].atom.wait.is_none());

    let mut completed = terminal(
        "tool",
        ChatAtomKind::ToolCall,
        1,
        pos(1, 1),
        pos(3, 1),
        content(),
    );
    completed.tool = started.tool;
    // A terminal publication must not duplicate the last active presentation,
    // even if the incoming metadata still carries it.
    completed.wait = Some(wait);
    restored.complete(completed, 1, None).unwrap();
    assert_projection_retention(&restored);
    let ended = restored.take_update().unwrap();
    assert_eq!(ended.facts.len(), 1);
    assert!(ended.facts[0].wait.is_none());
    assert_eq!(ended.members.len(), 1);
    assert!(ended.members[0].atom.wait.is_none());
    assert!(matches!(
        ended.members[0].atom.lifecycle,
        ChatAtomLifecycle::Terminal { .. }
    ));
    assert!(restored.active.is_empty());
}
