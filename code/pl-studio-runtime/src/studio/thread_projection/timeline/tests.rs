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
    TimelineProjection::new("db".into(), 0)
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
    timeline.observe(&reasoning, None);
    timeline.complete(
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
    );
    timeline.commit_ready();
    assert!(timeline.committed().is_empty());

    timeline.observe(
        &active("text", ChatAtomKind::Text, 2, pos(3, 0), content()),
        None,
    );
    timeline.commit_ready();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::WorkGroup, 0)]
    );
    assert_eq!(timeline.current_items().len(), 1);

    timeline.complete(
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
    );
    timeline.commit_ready();
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
    timeline.observe(
        &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
        None,
    );
    timeline.observe(
        &active("t", ChatAtomKind::Text, 2, pos(2, 0), content()),
        None,
    );
    timeline.complete(
        terminal("t", ChatAtomKind::Text, 2, pos(2, 0), pos(3, 0), content()),
        1,
        None,
    );
    timeline.commit_ready();
    assert!(timeline.committed().is_empty());
    timeline.complete(
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
    );
    timeline.commit_ready();
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
    timeline.observe(
        &active("t", ChatAtomKind::Text, 1, pos(1, 0), content()),
        None,
    );
    timeline.complete(background("b", 2, pos(2, 0)), 1, None);
    timeline.commit_ready();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::Status, 0)]
    );
    timeline.complete(
        terminal("t", ChatAtomKind::Text, 1, pos(1, 0), pos(3, 0), content()),
        2,
        None,
    );
    timeline.commit_ready();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::Status, 0), (TimelineItemKind::Text, 1)]
    );
}

#[test]
fn a_text_boundary_splits_work_into_two_groups() {
    let mut timeline = fold();
    timeline.observe(
        &active("r1", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
        None,
    );
    timeline.complete(
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
    );
    timeline.observe(
        &active("t", ChatAtomKind::Text, 2, pos(3, 0), content()),
        None,
    );
    timeline.complete(
        terminal("t", ChatAtomKind::Text, 2, pos(3, 0), pos(4, 0), content()),
        2,
        None,
    );
    timeline.observe(
        &active("r2", ChatAtomKind::Reasoning, 3, pos(5, 0), Vec::new()),
        None,
    );
    timeline.complete(
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
    );
    timeline.end_source(&source());
    timeline.commit_ready();
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
    timeline.observe(
        &active("r1", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
        None,
    );
    timeline.complete(
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
    );
    timeline.observe(
        &active("empty", ChatAtomKind::Text, 2, pos(3, 0), vec![]),
        None,
    );
    timeline.complete(
        terminal("empty", ChatAtomKind::Text, 2, pos(3, 0), pos(4, 0), vec![]),
        2,
        None,
    );
    timeline.observe(
        &active("r2", ChatAtomKind::Reasoning, 3, pos(5, 0), Vec::new()),
        None,
    );
    timeline.complete(
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
    );
    timeline.end_source(&source());
    timeline.commit_ready();
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
    timeline.observe(
        &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
        None,
    );
    timeline.end_source(&source());
    timeline.commit_ready();
    assert!(timeline.committed().is_empty());
    timeline.complete(
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
    );
    timeline.commit_ready();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::WorkGroup, 0)]
    );
}

#[test]
fn repeated_observation_is_idempotent() {
    let mut timeline = fold();
    let atom = active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new());
    timeline.observe(&atom, None);
    timeline.observe(&atom, None);
    assert_eq!(timeline.current_items().len(), 1);
    assert_eq!(timeline.current_items()[0].current_members, vec!["r"]);
}

#[test]
fn restored_current_fragments_continue_the_same_projection() {
    let mut timeline = fold();
    timeline.observe(
        &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
        None,
    );
    timeline.observe(
        &active("t", ChatAtomKind::Text, 2, pos(2, 0), content()),
        None,
    );
    let current = timeline.current_items();
    let members = timeline.current_members();

    let mut restored = TimelineProjection::new("db".into(), 0);
    restored.restore(&current, &members).unwrap();
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

    for (projection, sequence) in [(&mut timeline, 1), (&mut restored, 1)] {
        projection.complete(
            terminal("t", ChatAtomKind::Text, 2, pos(2, 0), pos(3, 0), content()),
            sequence,
            None,
        );
        projection.commit_ready();
    }
    assert!(timeline.committed().is_empty());
    assert!(restored.committed().is_empty());

    for (projection, sequence) in [(&mut timeline, 2), (&mut restored, 2)] {
        projection.complete(
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
        );
        projection.commit_ready();
    }
    assert_eq!(kinds(timeline.committed()), kinds(restored.committed()));
}

#[test]
fn independent_status_item_does_not_split_the_foreground_group() {
    let mut timeline = fold();
    timeline.observe(
        &active("r", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new()),
        None,
    );
    timeline.complete(status("receipt", 2, pos(2, 0), pos(2, 0)), 1, None);
    timeline.commit_ready();
    assert_eq!(
        kinds(timeline.committed()),
        vec![(TimelineItemKind::Status, 0)]
    );
    assert_eq!(timeline.current_items().len(), 1);
    timeline.complete(
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
    );
    timeline.end_source(&source());
    timeline.commit_ready();
    assert_eq!(
        kinds(timeline.committed()),
        vec![
            (TimelineItemKind::Status, 0),
            (TimelineItemKind::WorkGroup, 1)
        ]
    );
}
