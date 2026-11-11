use super::*;
use pl_protocol::WorkSummary;

fn atom(id: &str, kind: ChatAtomKind, terminal: bool) -> ChatAtom {
    ChatAtom {
        id: id.into(),
        completion_item_id: None,
        completion_seq: None,
        source: ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        },
        source_state: None,
        source_order: None,
        kind,
        delivery: ChatDeliveryKind::Foreground,
        lifecycle: if terminal {
            ChatAtomLifecycle::Terminal {
                started: Some(at(1)),
                ended: Some(at(2)),
                outcome: ChatTerminalOutcome::Completed,
            }
        } else {
            ChatAtomLifecycle::Active {
                started: Some(at(1)),
                status: ChatActiveStatus::Running,
            }
        },
        turn_id: Some("turn".into()),
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: None,
        started_at: Some(10),
        finished_at: terminal.then_some(20),
        content_present: None,
        contents: Vec::new(),
        payload: None,
    }
}

#[test]
fn start_and_end_merge_only_in_the_open_group() -> Result<()> {
    let mut s = state();
    let start = atom("call", ChatAtomKind::ToolCall, false);
    s.prepare(1, 10, &[start], &[], &[])?;
    let key = s.member_heads(&s.blocks[&1].id, None, 8)[0]
        .head
        .member_key
        .clone();
    let merged = s.prepare(
        2,
        20,
        &[atom("call", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    assert_eq!(merged.members.len(), 1);
    assert_eq!(merged.members[0].head.member_key, key);
    assert_eq!(merged.members[0].head.record.start_fact, Some(at(1)));
    assert_eq!(merged.members[0].head.record.end_fact, Some(at(2)));
    let only_end = s.prepare(
        3,
        30,
        &[atom("only-end", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    assert_eq!(only_end.members[0].head.record.start_fact, None);
    assert_eq!(summary(&s.blocks[&1]).total, 2);
    Ok(())
}

#[test]
fn same_effect_terminal_capture_uses_the_full_boundary_position() -> Result<()> {
    for end_suborder in [0, 1, 2] {
        let mut s = state();
        let active = atom("call", ChatAtomKind::ToolCall, false);
        s.prepare(1, 10, std::slice::from_ref(&active), &[], &[])?;
        let old = s.blocks[&1].id.clone();
        let mut text = atom("body", ChatAtomKind::Text, false);
        let boundary = ChatFactPosition {
            effect_seq: 2,
            suborder: 1,
        };
        text.lifecycle = ChatAtomLifecycle::Active {
            started: Some(boundary),
            status: ChatActiveStatus::Running,
        };
        let mut terminal = atom("call", ChatAtomKind::ToolCall, true);
        let end = ChatFactPosition {
            effect_seq: 2,
            suborder: end_suborder,
        };
        terminal.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(at(1)),
            ended: Some(end),
            outcome: ChatTerminalOutcome::Completed,
        };
        let facts = if end <= boundary {
            vec![terminal, text]
        } else {
            vec![text, terminal]
        };
        let mut captured = 0;
        let delta = s.prepare_capturing(2, 20, &facts, &[], &[], |_| {
            captured += 1;
            Ok(ObservationInput::for_test(active.clone(), Vec::new()))
        })?;
        assert_eq!(captured, usize::from(end > boundary));
        let members = s.member_heads(&old, None, 8);
        assert_eq!(
            members[0].head.record.end_fact,
            if end <= boundary { Some(end) } else { None }
        );
        if end > boundary {
            let late = delta
                .members
                .iter()
                .find(|m| m.block_id != old && m.head.record.atom.id == "call")
                .unwrap();
            assert_eq!(late.head.record.start_fact, None);
            assert_eq!(late.head.record.end_fact, Some(end));
            assert_ne!(late.head.member_key, members[0].head.member_key);
        }
    }
    Ok(())
}

#[test]
fn terminal_without_original_cannot_authorize_a_dynamic_body() -> Result<()> {
    let mut s = state();
    let mut terminal = atom("interrupted", ChatAtomKind::Reasoning, true);
    terminal.contents.push(pl_protocol::ChatAtomContent {
        role: ChatContentRole::Body,
        reference: ContentRef {
            database_id: "db".into(),
            target: ContentTarget::Body {
                owner: pl_protocol::ContentOwner::Item {
                    item_id: "interrupted".into(),
                },
                key: "body".into(),
            },
        },
    });
    assert!(s.prepare(1, 10, &[terminal], &[], &[]).is_err());
    assert_eq!(s.applied_effect, 0);
    assert!(s.blocks.is_empty());
    Ok(())
}

#[test]
fn boundary_freezes_content_state_time_and_late_end_gets_a_new_key() -> Result<()> {
    use pl_core::{
        chat::{ChatContentKey, ContentData, ContentDescriptor},
        model::ContentBlock,
    };
    use pl_protocol::{ChatAtomContent, ContentOwner};
    let mut s = state();
    let mut start = atom("call", ChatAtomKind::ToolCall, false);
    let owner = ContentOwner::Item {
        item_id: "call".into(),
    };
    start.contents.push(ChatAtomContent {
        role: ChatContentRole::ToolOutput,
        reference: ContentRef {
            database_id: "db".into(),
            target: ContentTarget::Body {
                owner: owner.clone(),
                key: "tool.result".into(),
            },
        },
    });
    let prefix = ContentBlock::from_text("prefix");
    let content = Arc::new(ChatContent {
        descriptor: ContentDescriptor {
            key: ChatContentKey {
                owner: crate::studio::conversation_identity::content_owner_key(&owner)?,
                key: "tool.result".into(),
            },
            byte_length: 6,
            generation: 1,
            media_type: None,
        },
        data: ContentData::text(prefix.clone()),
    });
    s.prepare(1, 10, &[start.clone()], &[], &[])?;
    let block = s.blocks[&1].id.clone();
    let old_key = s.member_heads(&block, None, 8)[0].head.member_key.clone();
    let mut observed = start.clone();
    observed.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(1)),
        status: ChatActiveStatus::Waiting,
    };
    observed.payload = Some(PayloadData::Inline {
        bytes: br#"{"public":"cut"}"#.to_vec(),
    });
    let cut = s.prepare_capturing(
        2,
        25,
        &[atom("text", ChatAtomKind::Text, false)],
        &[],
        &[],
        |_| {
            Ok(ObservationInput::for_test(
                observed.clone(),
                vec![content.clone()],
            ))
        },
    )?;
    assert_eq!(
        cut.published_through, 1,
        "unfinished members do not delay freezing"
    );
    let frozen = s.pending[&1].clone();
    let member = s.member_heads(&block, None, 8)[0].clone();
    assert_eq!(member.head.member_key, old_key);
    assert_eq!(member.head.record.end_fact, None);
    assert!(matches!(
        member.head.record.content_source,
        DisplayContentSource::FrozenObservation {
            captured_at: Some(25),
            available: true
        }
    ));
    assert_eq!(
        (
            summary(&cut.blocks[0].header).running,
            summary(&cut.blocks[0].header).waiting
        ),
        (0, 1)
    );
    assert!(!s.accepts_update(&start));
    let appended = ContentBlock::append(&prefix, "-later");
    let replacement = ContentBlock::from_text("OTHER!");
    assert_eq!(appended.len(), 12);
    assert_eq!(replacement.len(), 6);
    let ContentTarget::Body { owner, key } = &member.head.record.atom.contents[0].reference.target
    else {
        panic!()
    };
    let key = ChatContentKey {
        owner: crate::studio::conversation_identity::content_owner_key(owner)?,
        key: key.clone(),
    };
    assert_eq!(
        s.observation_content(&key)
            .unwrap()
            .data
            .range(0, 64)?
            .as_bytes(),
        b"prefix"
    );
    let late = s.prepare(
        3,
        99,
        &[atom("call", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    assert_ne!(late.members[0].head.member_key, old_key);
    assert_eq!(late.members[0].head.record.start_fact, None);
    assert_eq!(
        summary(
            &late
                .blocks
                .iter()
                .find(|w| matches!(w.header.body, DisplayBlockBody::Work { .. }))
                .unwrap()
                .header
        )
        .created_at,
        Some(99)
    );
    assert_eq!(*s.pending[&1], *frozen);
    assert_eq!(s.member_heads(&block, None, 8)[0].head, member.head);
    Ok(())
}

#[test]
fn failed_boundary_capture_keeps_the_effect_retryable() -> Result<()> {
    let mut s = state();
    s.prepare(
        1,
        10,
        &[atom("call", ChatAtomKind::ToolCall, false)],
        &[],
        &[],
    )?;
    let before = s.blocks[&1].clone();
    assert!(
        s.prepare_capturing(
            2,
            20,
            &[atom("body", ChatAtomKind::Text, false)],
            &[],
            &[],
            |_| anyhow::bail!("injected capture failure")
        )
        .is_err()
    );
    assert_eq!(s.applied_effect, 1);
    assert_eq!(s.blocks[&1], before);
    assert_eq!(s.blocks.len(), 1);
    assert_eq!(s.published, 0);
    assert!(
        s.prepare_capturing(
            2,
            20,
            &[atom("body", ChatAtomKind::Text, false)],
            &[],
            &[],
            |member| {
                let mut input =
                    ObservationInput::for_test(member.head.record.atom.clone(), Vec::new());
                input.state =
                    pl_protocol::ThreadItemState::Thinking(pl_protocol::ThreadThinkingItem::new(
                        Vec::new(),
                        Vec::new(),
                        pl_protocol::ThreadContentLifecycle::completed(20),
                    ));
                Ok(input)
            },
        )
        .is_err(),
        "invalid observation encoding must fail before revoking membership"
    );
    assert_eq!(s.applied_effect, 1);
    assert_eq!(s.blocks[&1], before);
    let retry = s.prepare(2, 20, &[atom("body", ChatAtomKind::Text, false)], &[], &[])?;
    assert_eq!(retry.published_through, 1);
    Ok(())
}
fn at(effect_seq: u64) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq,
        suborder: 0,
    }
}
fn state() -> PresentationState {
    let mut s = PresentationState::default();
    s.bind("db").unwrap();
    s
}
fn summary(h: &DisplayHeader) -> &WorkSummary {
    let DisplayBlockBody::Work { summary, .. } = &h.body else {
        panic!("expected work")
    };
    summary
}

#[test]
fn completed_members_wait_for_a_real_boundary_and_text_start_needs_no_new_completion() -> Result<()>
{
    let mut s = state();
    let a = atom("A", ChatAtomKind::ToolCall, false);
    s.prepare(1, 10, &[a], &[], &[])?;
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).created_at,
        Some(10)
    );
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).elapsed_ms,
        Some(0)
    );
    let done = atom("A", ChatAtomKind::ToolCall, true);
    s.prepare(2, 20, std::slice::from_ref(&done), &[], &[])?;
    s.confirm(2);
    assert_eq!(s.published, 0);
    assert_eq!(summary(s.blocks.values().next().unwrap()).terminal, 1);
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).elapsed_ms,
        Some(10_000)
    );
    // No successor boundary: idle time still belongs to the same live group.
    let id = s.blocks.values().next().unwrap().id.clone();
    let mut next = atom("B", ChatAtomKind::ToolCall, false);
    next.started_at = Some(1000); // The old active-interval metric excludes this gap.
    s.prepare(3, 1000, &[next.clone()], &[], &[])?;
    assert_eq!(s.blocks.values().next().unwrap().id, id);
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).created_at,
        Some(10)
    );
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).elapsed_ms,
        Some(990_000)
    );
    next.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(3)),
        ended: Some(at(4)),
        outcome: ChatTerminalOutcome::Completed,
    };
    next.finished_at = Some(1010);
    s.prepare(4, 1010, &[next], &[], &[])?;
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).duration_ms,
        Some(20)
    );
    assert_eq!(s.published, 0);
    let delta = s.prepare(5, 1200, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert_eq!(delta.published_through, 1);
    let frozen = delta.blocks.iter().find(|b| b.published.is_some()).unwrap();
    assert_eq!(summary(&frozen.header).created_at, Some(10));
    assert_eq!(summary(&frozen.header).elapsed_ms, Some(1_190_000));
    assert_eq!(
        delta
            .blocks
            .iter()
            .filter(|w| w.published.is_some())
            .count(),
        1
    );
    assert_eq!(s.capture(None, 8, 0, 8).open.len(), 1);
    assert!(Arc::ptr_eq(
        delta
            .blocks
            .iter()
            .find_map(|w| w.published.as_ref())
            .unwrap(),
        &s.pending[&1]
    ));
    s.confirm(5);
    assert_eq!(s.durable, 1);
    s.prepare(6, 1300, &[atom("T", ChatAtomKind::Text, true)], &[], &[])?;
    assert_eq!(summary(&frozen.header).elapsed_ms, Some(1_190_000));
    assert!(s.member_heads(&id, None, 8).is_empty());
    Ok(())
}

#[test]
fn restored_old_head_never_acquires_creation_time_from_new_members_or_boundary() -> Result<()> {
    let mut original = state();
    original.prepare(
        1,
        10,
        &[atom("old", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    let mut old = serde_json::to_value(original.blocks[&1].as_ref())?;
    let old_summary = old["body"]["summary"].as_object_mut().unwrap();
    old_summary.remove("createdAt");
    old_summary.remove("elapsedMs");
    let header: DisplayHeader = serde_json::from_value(old)?;
    let mut restored = PresentationState::default();
    restored.restore("db", 0, 1, 1, vec![header], vec![])?;
    restored.prepare(
        2,
        100,
        &[atom("new", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    let head = restored.blocks[&1].as_ref();
    assert_eq!(summary(head).total, 2);
    assert_eq!(summary(head).created_at, None);
    assert_eq!(summary(head).elapsed_ms, None);
    let delta = restored.prepare(3, 200, &[atom("text", ChatAtomKind::Text, false)], &[], &[])?;
    let published = delta.blocks.iter().find(|b| b.published.is_some()).unwrap();
    assert_eq!(summary(&published.header).created_at, None);
    assert_eq!(summary(&published.header).elapsed_ms, None);
    Ok(())
}

#[test]
fn direct_completion_uses_creation_effect_and_checked_elapsed_evidence() -> Result<()> {
    // A completed member's old/unknown active start is not its group creation time.
    for (created, observed, elapsed) in [
        (100, 150, Some(50_000)),
        (100, 99, None),
        (i64::MIN, i64::MAX, None),
        (0, i64::MAX, None),
    ] {
        let mut s = state();
        let mut done = atom("done", ChatAtomKind::ToolCall, true);
        done.started_at = None;
        s.prepare(1, created, &[done], &[], &[])?;
        assert_eq!(summary(&s.blocks[&1]).created_at, Some(created));
        assert_eq!(summary(&s.blocks[&1]).elapsed_ms, Some(0));
        let delta = s.prepare(
            2,
            observed,
            &[atom("text", ChatAtomKind::Text, false)],
            &[],
            &[],
        )?;
        let frozen = delta.blocks.iter().find(|b| b.published.is_some()).unwrap();
        assert_eq!(summary(&frozen.header).created_at, Some(created));
        assert_eq!(summary(&frozen.header).elapsed_ms, elapsed);
        assert_eq!(summary(&frozen.header).duration_ms, None);
    }
    Ok(())
}

#[test]
fn reverse_terminals_keep_source_prefix_while_background_and_input_advance() -> Result<()> {
    let mut s = state();
    s.prepare(
        1,
        10,
        &[
            atom("R", ChatAtomKind::Reasoning, false),
            atom("A", ChatAtomKind::ToolCall, false),
        ],
        &[],
        &[],
    )?;
    s.prepare(2, 20, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert_eq!(
        s.published, 1,
        "TextStarted freezes unfinished R/A immediately"
    );
    let first = s.pending[&1].clone();
    s.prepare(3, 30, &[atom("T", ChatAtomKind::Text, true)], &[], &[])?;
    s.prepare(4, 40, &[atom("A", ChatAtomKind::ToolCall, true)], &[], &[])?;
    assert_eq!(s.published, 2);
    let mut background = atom("A", ChatAtomKind::ToolCall, true);
    background.source = ChatSourceId::BackgroundResult {
        message_id: "result".into(),
    };
    background.delivery = ChatDeliveryKind::Independent;
    let mut input = atom("input", ChatAtomKind::Input, true);
    input.source = ChatSourceId::Input {
        input_id: "input".into(),
    };
    input.delivery = ChatDeliveryKind::Independent;
    s.prepare(5, 50, &[background, input], &[], &[])?;
    assert_eq!(s.published, 4);
    assert_eq!(s.blocks.len(), 1);
    assert_eq!(summary(&s.blocks[&3]).created_at, Some(40));
    assert_eq!(summary(&s.blocks[&3]).elapsed_ms, Some(0));
    let ended = s.prepare(6, 60, &[atom("R", ChatAtomKind::Reasoning, true)], &[], &[])?;
    assert_eq!(ended.members[0].head.record.start_fact, None);
    assert_eq!(s.published, 4);
    let delta = s.prepare(7, 70, &[atom("T2", ChatAtomKind::Text, false)], &[], &[])?;
    assert_eq!(
        delta
            .blocks
            .iter()
            .filter_map(|w| w.header.history_pos)
            .collect::<Vec<_>>(),
        vec![5]
    );
    assert_eq!(
        *s.pending[&1], *first,
        "late terminals never rewrite the boundary cut"
    );
    assert!(matches!(s.pending[&5].body, DisplayBlockBody::Work { .. }));
    assert!(
        matches!(&s.pending[&5].body, DisplayBlockBody::Work { summary, .. }
        if summary.created_at == Some(40) && summary.elapsed_ms == Some(30_000))
    );
    assert!(matches!(
        s.pending[&2].body,
        DisplayBlockBody::Single { .. }
    ));
    Ok(())
}

#[test]
fn transfer_and_background_result_have_distinct_keys_and_empty_text_is_removed() -> Result<()> {
    let mut s = state();
    let mut handoff = atom("call", ChatAtomKind::ToolCall, true);
    handoff.delivery = ChatDeliveryKind::BackgroundHandoff;
    if let ChatAtomLifecycle::Terminal { outcome, .. } = &mut handoff.lifecycle {
        *outcome = ChatTerminalOutcome::Transferred;
    }
    s.prepare(1, 10, &[handoff.clone()], &[], &[])?;
    let mut result = handoff.clone();
    result.source = ChatSourceId::BackgroundResult {
        message_id: "bg".into(),
    };
    result.delivery = ChatDeliveryKind::Independent;
    if let ChatAtomLifecycle::Terminal { outcome, .. } = &mut result.lifecycle {
        *outcome = ChatTerminalOutcome::Completed;
    }
    assert_ne!(member_key(&handoff)?, member_key(&result)?);
    s.prepare(2, 20, &[result], &[], &[])?;
    s.prepare(3, 30, &[atom("empty", ChatAtomKind::Text, false)], &[], &[])?;
    let mut empty = atom("empty", ChatAtomKind::Text, true);
    empty.content_present = Some(false);
    let delta = s.prepare(4, 40, &[empty], &[], &[])?;
    assert_eq!(delta.remove_empty.len(), 1);
    assert_eq!(s.published, 2); // background + foreground Work, not the empty Text
    let old = s.pending[&2].id.clone();
    s.prepare(
        5,
        50,
        &[atom("next", ChatAtomKind::ToolCall, false)],
        &[],
        &[],
    )?;
    assert_ne!(s.blocks.values().next().unwrap().id, old);
    Ok(())
}

#[test]
fn waiting_and_duplicate_facts_do_not_change_members_or_accept_conflicts() -> Result<()> {
    let mut s = state();
    let mut waiting = atom("q", ChatAtomKind::ToolCall, false);
    waiting.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(1)),
        status: ChatActiveStatus::Waiting,
    };
    s.prepare(1, 10, &[waiting.clone()], &[], &[])?;
    let revision = s.revision;
    let mut watch = s.subscribe_members();
    s.prepare(2, 20, &[waiting], &[], &[])?;
    assert_eq!(s.revision, revision);
    assert!(!watch.has_changed()?);
    assert_eq!(summary(s.blocks.values().next().unwrap()).waiting, 1);
    let terminal = atom("q", ChatAtomKind::ToolCall, true);
    s.prepare(3, 30, std::slice::from_ref(&terminal), &[], &[])?;
    assert_eq!(
        s.revision, revision,
        "terminal/summary changes do not stale live older"
    );
    assert!(watch.has_changed()?);
    watch.borrow_and_update();
    s.prepare(4, 40, std::slice::from_ref(&terminal), &[], &[])?;
    assert!(!watch.has_changed()?);
    let before = s.revision;
    let mut conflict = terminal;
    conflict.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(1)),
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Failed,
    };
    assert!(s.prepare(5, 50, &[conflict], &[], &[]).is_err());
    assert_eq!(s.revision, before);
    assert_eq!(summary(s.blocks.values().next().unwrap()).terminal, 1);
    s.prepare(6, 60, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert!(
        s.revision > revision,
        "create/handoff must stale the structural cursor"
    );
    Ok(())
}

#[test]
fn parallel_member_without_start_invalidates_the_work_duration() -> Result<()> {
    let mut s = state();
    s.prepare(1, 10, &[atom("A", ChatAtomKind::ToolCall, false)], &[], &[])?;
    let mut b = atom("B", ChatAtomKind::ToolCall, true);
    b.started_at = None;
    b.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(2, 20, &[b], &[], &[])?;
    let mut a = atom("A", ChatAtomKind::ToolCall, true);
    a.finished_at = Some(30);
    s.prepare(3, 30, &[a], &[], &[])?;
    let head = s.blocks.values().next().unwrap();
    assert_eq!(summary(head).started_at, None);
    assert_eq!(summary(head).finished_at, Some(30));
    assert_eq!(summary(head).duration_ms, None);
    Ok(())
}

#[test]
fn missing_work_time_stays_unknown_after_later_measured_intervals() -> Result<()> {
    let mut s = state();
    let mut unknown = atom("unknown", ChatAtomKind::ToolCall, true);
    unknown.started_at = None;
    s.prepare(1, 10, &[unknown], &[], &[])?;
    s.prepare(
        2,
        20,
        &[atom("known", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    let head = s.blocks.values().next().unwrap();
    assert_eq!(summary(head).started_at, None);
    assert_eq!(summary(head).duration_ms, None);
    Ok(())
}

#[test]
fn hundred_thousand_members_have_a_bounded_head_delta_and_no_inline_saved_bodies() -> Result<()> {
    let mut s = state();
    for index in 0..100_000 {
        let mut member = atom(&format!("tool-{index}"), ChatAtomKind::ToolCall, true);
        member.completion_item_id = Some(format!("original-{index}"));
        member.payload = Some(PayloadData::Inline {
            bytes: vec![42; 1024],
        });
        if index == 99_999 {
            member.lifecycle = ChatAtomLifecycle::Terminal {
                started: Some(at(100_000)),
                ended: Some(at(100_001)),
                outcome: ChatTerminalOutcome::Completed,
            };
            let mut started = member.clone();
            started.completion_item_id = None;
            started.payload = None;
            started.finished_at = None;
            started.lifecycle = ChatAtomLifecycle::Active {
                started: Some(at(100_000)),
                status: ChatActiveStatus::Running,
            };
            s.prepare(100_000, 100_000, &[started], &[], &[])?;
        }
        let measured = matches!(index, 0 | 99 | 9_999 | 99_999);
        if measured {
            s.begin_cost_observation();
        }
        let delta = s.prepare(
            index + 1 + u64::from(index == 99_999),
            i64::try_from(index + 1)?,
            &[member],
            &[],
            &[],
        )?;
        if measured {
            let visits = s.finish_cost_observation();
            assert_eq!(visits.members.keys.len(), 1);
            assert_eq!(visits.heads.keys.len(), 1);
            assert!(
                visits.members.reads <= 2 && visits.members.writes == 1,
                "{visits:?}"
            );
            assert!(
                visits.heads.reads <= 8 && visits.heads.writes <= 2,
                "{visits:?}"
            );
            eprintln!(
                "PRESENTATION_COST {}",
                serde_json::json!({
                    "event": if index == 99_999 { "existing_member_terminal" } else { "direct_member_terminal" },
                    "members": s.members.len(), "open_heads": s.blocks.len(),
                    "retained_estimate_bytes": s.retained_bytes(),
                    "head_json_bytes": serde_json::to_vec(delta.blocks[0].header.as_ref())?.len(),
                    "delta_json_bytes": serde_json::to_vec(delta.as_ref())?.len(),
                    "member_reads": visits.members.reads, "member_writes": visits.members.writes,
                    "unique_members": visits.members.keys.len(), "member_lookup_misses": visits.members.misses,
                    "head_reads": visits.heads.reads, "head_writes": visits.heads.writes,
                    "unique_heads": visits.heads.keys.len(), "head_lookup_misses": visits.heads.misses,
                })
            );
        }
        assert_eq!(delta.blocks.len(), 1);
        assert_eq!(delta.members.len(), 1);
        assert!(serde_json::to_vec(delta.blocks[0].header.as_ref())?.len() < 2048);
        assert!(matches!(
            delta.members[0].head.record.atom.payload,
            Some(PayloadData::Deferred { .. })
        ));
    }
    assert_eq!(s.members.len(), 100_000); // The lightweight index genuinely grows; not constant memory.
    let cut = s.capture(None, 1, 0, 1);
    assert_eq!(cut.open.len(), 1);
    assert_eq!(summary(&cut.open[0]).total, 100_000);
    s.begin_cost_observation();
    let delta = s.prepare(
        100_002,
        100_002,
        &[atom("text", ChatAtomKind::Text, false)],
        &[],
        &[],
    )?;
    let visits = s.finish_cost_observation();
    assert_eq!(
        visits.members.reads, 0,
        "boundary read an old member: {visits:?}"
    );
    assert_eq!(visits.members.writes, 1);
    assert_eq!(visits.members.keys.len(), 1);
    assert_eq!(visits.heads.keys.len(), 2);
    assert!(visits.heads.reads <= 12, "{visits:?}");
    eprintln!(
        "PRESENTATION_COST {}",
        serde_json::json!({
            "event":"text_boundary", "members":s.members.len(), "open_heads":s.blocks.len(),
            "retained_estimate_bytes":s.retained_bytes(),
            "head_json_bytes":delta.blocks.iter().map(|b| serde_json::to_vec(b.header.as_ref()).map(|v| v.len())).collect::<std::result::Result<Vec<_>,_>>()?,
            "delta_json_bytes":serde_json::to_vec(delta.as_ref())?.len(),
            "member_reads":visits.members.reads, "member_writes":visits.members.writes,
            "unique_members":visits.members.keys.len(), "head_reads":visits.heads.reads,
            "head_writes":visits.heads.writes, "unique_heads":visits.heads.keys.len(),
        })
    );
    assert_eq!(delta.members.len(), 1); // No fold/rewrite of the 100k saved member heads.
    assert_eq!(delta.blocks.len(), 2);
    assert_eq!(delta.published_through, 1);
    s.confirm(100_002);
    assert_eq!(s.members.len(), 1);
    eprintln!(
        "PRESENTATION_COST {}",
        serde_json::json!({
            "event":"durable_confirmation", "members":s.members.len(),
            "retained_estimate_bytes":s.retained_bytes(),
        })
    );
    Ok(())
}
