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

fn summary_input(atom: ChatAtom, summary: Option<&str>) -> TimelineInput {
    TimelineInput::Atom {
        atom: Box::new(atom),
        payload: None,
        thinking_summary: summary.map(str::to_owned),
    }
}

#[test]
fn independent_background_tools_commit_without_splitting_foreground_or_waiting_for_text() {
    let mut timeline = fold();
    timeline
        .observe(
            &active("text", ChatAtomKind::Text, 1, pos(1, 0), content()),
            None,
        )
        .unwrap();
    timeline
        .apply_input(summary_input(
            active(
                "thinking",
                ChatAtomKind::Reasoning,
                2,
                pos(2, 0),
                Vec::new(),
            ),
            Some("前台组摘要"),
        ))
        .unwrap();
    let foreground_id = timeline.current_items()[1].id.clone();
    for (offset, id) in ["background-a", "background-b"].into_iter().enumerate() {
        let mut atom = background(id, 1, pos(3 + offset as u64, 0));
        atom.kind = ChatAtomKind::ToolCall;
        atom.source = ChatSourceId::BackgroundResult {
            message_id: format!("result-{offset}"),
        };
        let source = atom.source.clone();
        timeline.apply_input(summary_input(atom, None)).unwrap();
        let committed = timeline.take_committed();
        assert_eq!(committed.len(), 1);
        let group = &committed[0];
        assert_eq!(group.kind, TimelineItemKind::WorkGroup);
        assert_eq!(group.source, source);
        assert_eq!(group.delivery, ChatDeliveryKind::Independent);
        assert_eq!(group.outcome, None);
        assert!(group.admission_closed);
        assert_eq!(group.position, Some(offset as u64));
        assert_eq!(group.summary.as_ref().unwrap().member_count, 1);
        assert_eq!(group.summary.as_ref().unwrap().active_count, 0);
        assert_eq!(
            group.summary.as_ref().unwrap().latest_thinking_summary,
            None
        );
        assert!(group.members.is_some());
    }
    timeline
        .observe(
            &active(
                "foreground-tool",
                ChatAtomKind::ToolCall,
                3,
                pos(5, 0),
                Vec::new(),
            ),
            None,
        )
        .unwrap();
    let current = timeline.current_items();
    assert_eq!(current.len(), 2);
    assert_eq!(current[0].kind, TimelineItemKind::Text);
    assert_eq!(current[1].id, foreground_id);
    assert!(!current[1].admission_closed);
    assert_eq!(current[1].summary.as_ref().unwrap().member_count, 2);
    assert_eq!(
        current[1]
            .summary
            .as_ref()
            .unwrap()
            .latest_thinking_summary
            .as_deref(),
        Some("前台组摘要")
    );
    timeline
        .apply_input(summary_input(background("non-tool", 1, pos(6, 0)), None))
        .unwrap();
    assert_eq!(timeline.take_committed()[0].kind, TimelineItemKind::Status);
}

fn group_summary(timeline: &TimelineProjection) -> Option<String> {
    timeline.current_items()[0]
        .summary
        .as_ref()
        .unwrap()
        .latest_thinking_summary
        .clone()
}

#[test]
fn thinking_summary_advances_without_metadata_changes_and_survives_tools_and_empty_parts() {
    let mut timeline = fold();
    let first = active("first", ChatAtomKind::Reasoning, 1, pos(1, 0), Vec::new());
    timeline
        .apply_input(summary_input(first.clone(), Some("旧摘要")))
        .unwrap();
    timeline
        .apply_input(summary_input(first, Some("流式新摘要")))
        .unwrap();
    assert_eq!(group_summary(&timeline).as_deref(), Some("流式新摘要"));
    let tool = active("tool", ChatAtomKind::ToolCall, 2, pos(2, 0), Vec::new());
    timeline
        .apply_input(summary_input(tool, Some("工具不能提供思考摘要")))
        .unwrap();
    let empty = active("empty", ChatAtomKind::Reasoning, 3, pos(3, 0), Vec::new());
    timeline
        .apply_input(summary_input(empty, Some(" \r\n ")))
        .unwrap();
    assert_eq!(group_summary(&timeline).as_deref(), Some("流式新摘要"));
    let latest = active("latest", ChatAtomKind::Reasoning, 4, pos(4, 0), Vec::new());
    timeline
        .apply_input(summary_input(latest.clone(), None))
        .unwrap();
    assert_eq!(group_summary(&timeline).as_deref(), Some("流式新摘要"));
    timeline
        .apply_input(summary_input(latest, Some("较晚成员的摘要")))
        .unwrap();
    assert_eq!(group_summary(&timeline).as_deref(), Some("较晚成员的摘要"));
}

#[test]
fn thinking_summary_source_order_survives_recovery_late_terminal_and_history_handoff() {
    let mut timeline = fold();
    for (id, order, text) in [("early", 1, "早摘要"), ("late", 2, "晚摘要")] {
        timeline
            .apply_input(summary_input(
                active(
                    id,
                    ChatAtomKind::Reasoning,
                    order,
                    pos(order, 0),
                    Vec::new(),
                ),
                Some(text),
            ))
            .unwrap();
    }
    let update = timeline.take_update().unwrap();
    let mut restored = fold();
    restored.restore_recovery(update.recovery()).unwrap();
    assert_eq!(group_summary(&restored).as_deref(), Some("晚摘要"));
    restored
        .apply_input(summary_input(
            terminal(
                "late",
                ChatAtomKind::Reasoning,
                2,
                pos(2, 0),
                pos(3, 0),
                Vec::new(),
            ),
            None,
        ))
        .unwrap();
    restored
        .apply_input(summary_input(
            terminal(
                "early",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(4, 0),
                Vec::new(),
            ),
            Some("迟到的较早摘要"),
        ))
        .unwrap();
    assert_eq!(group_summary(&restored).as_deref(), Some("晚摘要"));
    restored
        .apply_input(summary_input(
            terminal(
                "boundary",
                ChatAtomKind::Text,
                3,
                pos(5, 0),
                pos(5, 1),
                content(),
            ),
            None,
        ))
        .unwrap();
    let history = restored.take_committed();
    assert_eq!(history.len(), 2);
    assert_eq!(
        history[0]
            .summary
            .as_ref()
            .unwrap()
            .latest_thinking_summary
            .as_deref(),
        Some("晚摘要")
    );
    assert!(history[0].position.is_some());
    restored
        .apply_input(summary_input(
            active(
                "new-group",
                ChatAtomKind::Reasoning,
                4,
                pos(6, 0),
                Vec::new(),
            ),
            None,
        ))
        .unwrap();
    assert_eq!(group_summary(&restored), None);
    let mut other_source = active("other", ChatAtomKind::Reasoning, 1, pos(7, 0), Vec::new());
    other_source.source = ChatSourceId::ForegroundTurn {
        turn_id: "other-turn".into(),
    };
    other_source.turn_id = Some("other-turn".into());
    restored
        .apply_input(summary_input(other_source, Some("其他组摘要")))
        .unwrap();
    assert_eq!(group_summary(&restored), None);
    assert_eq!(
        restored.current_items()[1]
            .summary
            .as_ref()
            .unwrap()
            .latest_thinking_summary
            .as_deref(),
        Some("其他组摘要")
    );
}

#[test]
fn completed_summary_reads_only_bounded_summary_roles_and_handles_utf8_tail() {
    use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
    use std::sync::Arc;

    let owner = ContentOwner::Item {
        item_id: "reason".into(),
    };
    let key = ChatContentKey {
        owner: crate::studio::conversation_identity::content_owner_key(&owner).unwrap(),
        key: "part.summaryText.0".into(),
    };
    let text = format!("{}\r\n最新摘要\r\n", "🦀".repeat(4096));
    let bytes: Arc<[u8]> = Arc::from(text.as_bytes());
    let mut contents = pl_core::chat::ChatContents::new();
    contents.insert(
        key.clone(),
        Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: key.clone(),
                byte_length: bytes.len() as u64,
                generation: 1,
                media_type: None,
            },
            data: ContentData::Bytes(bytes),
        }),
    );
    let mut atom = active(
        "reason",
        ChatAtomKind::Reasoning,
        1,
        pos(1, 0),
        vec![ChatAtomContent {
            role: ChatContentRole::ReasoningSummary,
            reference: ContentRef {
                database_id: "db".into(),
                target: ContentTarget::Body {
                    owner,
                    key: key.key,
                },
            },
        }],
    );
    assert_eq!(
        completed_thinking_summary(&atom, &contents)
            .unwrap()
            .as_deref(),
        Some("最新摘要")
    );
    atom.contents[0].role = ChatContentRole::Body;
    assert_eq!(
        completed_thinking_summary(&atom, &Default::default()).unwrap(),
        None
    );
    assert_eq!(
        thinking_summary_tail("🦀最新".as_bytes().get(1..).unwrap())
            .unwrap()
            .as_deref(),
        Some("最新")
    );
    let long = "长".repeat(1024);
    assert_eq!(
        thinking_summary_tail(long.as_bytes())
            .unwrap()
            .unwrap()
            .chars()
            .count(),
        512
    );
}

#[test]
fn published_timeline_phase_keeps_its_original_unknown_work_rule() {
    let mut timeline = fold();
    timeline.published_classification();
    timeline
        .complete(
            terminal(
                "old-unknown",
                ChatAtomKind::Unknown,
                1,
                pos(1, 0),
                pos(1, 1),
                vec![],
            ),
            1,
            None,
        )
        .unwrap();
    timeline
        .complete(
            terminal(
                "work",
                ChatAtomKind::Reasoning,
                2,
                pos(2, 0),
                pos(2, 1),
                vec![],
            ),
            2,
            None,
        )
        .unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    let items = timeline.take_committed();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].kind, TimelineItemKind::WorkGroup);
    assert_eq!(items[0].summary.as_ref().unwrap().member_count, 2);
}

#[test]
fn foreground_neutral_sources_are_independent_status_boundaries() {
    for kind in [
        ChatAtomKind::Raw,
        ChatAtomKind::Agent,
        ChatAtomKind::Unknown,
    ] {
        let mut timeline = fold();
        let mut neutral = terminal("neutral", kind, 2, pos(2, 0), pos(3, 0), vec![]);
        neutral.completion_seq = Some(2);
        timeline
            .complete(
                terminal(
                    "before",
                    ChatAtomKind::Reasoning,
                    1,
                    pos(1, 0),
                    pos(1, 1),
                    vec![],
                ),
                1,
                None,
            )
            .unwrap();
        timeline
            .observe(&active("neutral", kind, 2, pos(2, 0), vec![]), None)
            .unwrap();
        timeline.complete(neutral.clone(), 2, None).unwrap();
        timeline
            .complete(
                terminal(
                    "after",
                    ChatAtomKind::ToolCall,
                    3,
                    pos(4, 0),
                    pos(4, 1),
                    vec![],
                ),
                3,
                None,
            )
            .unwrap();
        timeline.end_source(&source());
        timeline.commit_ready().unwrap();
        let items = timeline.take_committed();
        assert_eq!(
            items.iter().map(|item| item.kind).collect::<Vec<_>>(),
            [
                TimelineItemKind::WorkGroup,
                TimelineItemKind::Status,
                TimelineItemKind::WorkGroup
            ]
        );
        assert_eq!(items[1].atom_kind, Some(kind));
        assert_eq!(items[1].source, neutral.source);
        assert_eq!(items[1].outcome, Some(ChatTerminalOutcome::Completed));
        assert_eq!(items[1].content_item_id.as_deref(), Some("neutral"));
        let update = timeline.take_update().unwrap();
        assert_eq!(
            update
                .members()
                .iter()
                .map(|member| member.atom.id.as_str())
                .collect::<Vec<_>>(),
            ["before", "after"]
        );
    }
}

#[test]
fn inference_is_noop_between_work_including_legacy_and_current_entries() {
    let mut timeline = fold();
    timeline
        .complete(
            terminal(
                "before",
                ChatAtomKind::Reasoning,
                1,
                pos(1, 0),
                pos(1, 1),
                vec![],
            ),
            1,
            None,
        )
        .unwrap();
    let diagnostic = active("diagnostic", ChatAtomKind::Inference, 2, pos(2, 0), vec![]);
    timeline.observe(&diagnostic, None).unwrap();
    timeline.refresh_current(&diagnostic, None).unwrap();
    let done = terminal(
        "diagnostic",
        ChatAtomKind::Inference,
        2,
        pos(2, 0),
        pos(2, 1),
        vec![],
    );
    timeline.admit_legacy_header(&done).unwrap();
    timeline.complete(done, 2, None).unwrap();
    timeline
        .complete(
            terminal(
                "after",
                ChatAtomKind::ToolCall,
                3,
                pos(3, 0),
                pos(3, 1),
                vec![],
            ),
            3,
            None,
        )
        .unwrap();
    timeline.end_source(&source());
    timeline.commit_ready().unwrap();
    let items = timeline.take_committed();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].kind, TimelineItemKind::WorkGroup);
    assert_eq!(items[0].summary.as_ref().unwrap().member_count, 2);
    let update = timeline.take_update().unwrap();
    assert_eq!(
        update
            .members()
            .iter()
            .map(|member| member.atom.id.as_str())
            .collect::<Vec<_>>(),
        ["before", "after"]
    );
    assert!(update.facts().iter().all(|atom| atom.id != "diagnostic"));
}

#[test]
fn terminal_text_freezes_its_authoritative_channel() {
    let mut timeline = fold();
    let mut start = active("answer", ChatAtomKind::Text, 1, pos(1, 0), content());
    start.text_channel = Some(ThreadTextChannel::Commentary);
    timeline.observe(&start, None).unwrap();
    timeline
        .complete(
            terminal(
                "answer",
                ChatAtomKind::Text,
                1,
                pos(1, 0),
                pos(2, 0),
                content(),
            ),
            1,
            None,
        )
        .unwrap();
    timeline.commit_ready().unwrap();
    assert_eq!(
        timeline.committed()[0].text_channel,
        Some(ThreadTextChannel::Final)
    );
}

#[test]
fn many_reverse_terminals_keep_the_source_prefix_and_independent_result_order() {
    for count in [8, 64] {
        let mut timeline = fold();
        for index in 0..count {
            timeline
                .observe(
                    &active(
                        &format!("part-{index}"),
                        ChatAtomKind::Text,
                        index + 1,
                        pos(index + 1, 0),
                        content(),
                    ),
                    None,
                )
                .unwrap();
        }
        timeline
            .complete(background("background", 1, pos(count + 1, 0)), 1, None)
            .unwrap();
        timeline.commit_ready().unwrap();
        assert_eq!(timeline.committed().len(), 1);
        assert_eq!(timeline.committed()[0].id, "status:background");
        for index in (0..count).rev() {
            timeline
                .complete(
                    terminal(
                        &format!("part-{index}"),
                        ChatAtomKind::Text,
                        index + 1,
                        pos(index + 1, 0),
                        pos(count * 2 - index + 1, 0),
                        content(),
                    ),
                    count - index + 1,
                    None,
                )
                .unwrap();
            timeline.commit_ready().unwrap();
        }
        let expected: Vec<_> = std::iter::once("status:background".to_owned())
            .chain((0..count).map(|index| format!("text:part-{index}")))
            .collect();
        assert_eq!(
            timeline
                .committed()
                .iter()
                .map(|item| item.id.clone())
                .collect::<Vec<_>>(),
            expected
        );
        assert!(timeline.current_items().is_empty());
    }
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
    let retained = timeline.retained_bytes();
    assert!(
        retained >= expected + 128 * timeline.items.len() as u64,
        "the source/order indexes must retain their node and key charges"
    );
    retained
}

#[test]
fn mutable_projection_retention_tracks_fold_restore_and_drains() {
    let mut timeline = fold();
    assert_projection_retention(&timeline);
    let started = active("tool", ChatAtomKind::ToolCall, 1, pos(1, 0), Vec::new());
    timeline.observe(&started, None).unwrap();
    let first = assert_projection_retention(&timeline);
    timeline.observe(&started, None).unwrap();
    timeline.refresh_current(&started, None).unwrap();
    assert_eq!(assert_projection_retention(&timeline), first);
    let mut waiting = started.clone();
    waiting.lifecycle = ChatAtomLifecycle::Active {
        started: Some(pos(1, 0)),
        status: ChatActiveStatus::Waiting,
    };
    waiting.contents = content();
    timeline.observe(&waiting, None).unwrap();
    assert_projection_retention(&timeline);
    timeline.refresh_current(&started, None).unwrap();
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
        items: timeline.items.values().cloned().collect(),
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
        items: timeline.items.values().cloned().collect(),
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
        items: restored.items.values().cloned().collect(),
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
