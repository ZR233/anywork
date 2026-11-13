use super::*;
use pl_protocol::{ChatSourceLifecycle, WorkTiming};

#[test]
fn work_lifetime_is_frozen_at_the_first_visible_boundary() -> Result<()> {
    let mut owner = state();
    owner.prepare(
        1,
        10,
        &[atom("work", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    let delta = owner.prepare(
        2,
        135,
        &[atom("answer", ChatAtomKind::Text, false)],
        &[],
        &[],
    )?;
    let work = delta
        .blocks
        .iter()
        .find(|block| block.published.is_some())
        .unwrap();
    assert_eq!(timing(&work.header).started_at, 10);
    assert_eq!(timing(&work.header).finished_at, Some(135));
    Ok(())
}

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
        tool: (kind == ChatAtomKind::ToolCall).then(|| pl_protocol::ChatToolIdentity {
            call_id: id.into(),
            name: "exec".into(),
        }),
        wait: None,
        text_channel: None,
        started_at: Some(10),
        finished_at: terminal.then_some(20),
        content_present: (kind == ChatAtomKind::Text).then_some(true),
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
        &[at_effect(atom("only-end", ChatAtomKind::ToolCall, true), 3)],
        &[],
        &[],
    )?;
    assert_eq!(only_end.members[0].head.record.start_fact, None);
    assert_eq!(s.blocks[&1].next_member, 2);
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
    assert_eq!(cut.blocks[0].header.unfinished, 1);
    assert!(matches!(
        member.head.record.atom.lifecycle,
        ChatAtomLifecycle::Active {
            status: ChatActiveStatus::Waiting,
            ..
        }
    ));
    assert_eq!(timing(&cut.blocks[0].header).finished_at, Some(25));
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
        &[at_effect(atom("call", ChatAtomKind::ToolCall, true), 3)],
        &[],
        &[],
    )?;
    assert_ne!(late.members[0].head.member_key, old_key);
    assert_eq!(late.members[0].head.record.start_fact, None);
    assert_eq!(
        timing(
            &late
                .blocks
                .iter()
                .find(|w| matches!(w.header.body, DisplayBlockBody::Work { .. }))
                .unwrap()
                .header
        )
        .started_at,
        99
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
fn at_effect(mut atom: ChatAtom, effect: u64) -> ChatAtom {
    match &mut atom.lifecycle {
        ChatAtomLifecycle::Active { started, .. } => *started = Some(at(effect)),
        ChatAtomLifecycle::Terminal { ended, .. } => *ended = Some(at(effect)),
    }
    atom
}
fn state() -> PresentationState {
    let mut s = PresentationState::default();
    s.bind("db").unwrap();
    s
}
fn timing(h: &DisplayHeader) -> &WorkTiming {
    let DisplayBlockBody::Work {
        timing: summary, ..
    } = &h.body
    else {
        panic!("expected work")
    };
    summary
}

fn source_ended(atom: &ChatAtom, effect_seq: u64) -> ChatSourceState {
    ChatSourceState {
        source: atom.source.clone(),
        lifecycle: ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Completed,
        },
        started: None,
        ended: Some(ChatFactPosition {
            effect_seq,
            suborder: 1,
        }),
    }
}

#[test]
fn v364_cross_source_work_joins_one_tail_and_input_seals_it() -> Result<()> {
    let mut s = state();
    let foreground = atom("foreground", ChatAtomKind::ToolCall, false);
    s.prepare(1, 10, &[foreground], &[], &[])?;
    let tail = s.blocks[&1].id.clone();
    let mut background = atom("background", ChatAtomKind::ToolCall, true);
    background.source = ChatSourceId::BackgroundResult {
        message_id: "result".into(),
    };
    background.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(2, 20, &[background], &[], &[])?;
    assert_eq!(
        s.blocks.len(),
        1,
        "different sources must share the current Work"
    );
    assert_eq!(s.blocks[&1].next_member, 2);
    let mut input = atom("input", ChatAtomKind::Input, true);
    input.source = ChatSourceId::ForegroundTurn {
        turn_id: "another-turn".into(),
    };
    input.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(at(3)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(3, 30, &[input], &[], &[])?;
    assert_eq!(
        s.pending[&1].id, tail,
        "a cross-source Single must freeze the tail"
    );
    Ok(())
}

#[test]
fn v364_empty_text_started_and_closed_never_create_a_boundary() -> Result<()> {
    let mut s = state();
    s.prepare(
        1,
        10,
        &[atom("work", ChatAtomKind::ToolCall, false)],
        &[],
        &[],
    )?;
    let tail = s.blocks[&1].clone();
    let mut text = atom("empty", ChatAtomKind::Text, false);
    text.content_present = Some(false);
    text.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(2)),
        status: ChatActiveStatus::Running,
    };
    s.prepare(2, 20, &[text], &[], &[])?;
    assert_eq!(s.published, 0, "zero-byte Started cannot freeze Work");
    assert_eq!(s.blocks[&1], tail);
    let mut terminal = atom("empty", ChatAtomKind::Text, true);
    terminal.content_present = Some(false);
    terminal.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(2)),
        ended: Some(at(3)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(3, 30, &[terminal], &[], &[])?;
    assert_eq!(s.blocks.len(), 1);
    assert_eq!(s.published, 0);
    Ok(())
}

#[test]
fn v364_source_ended_and_idle_restore_preserve_the_same_open_work() -> Result<()> {
    let mut s = state();
    let work = atom("done", ChatAtomKind::ToolCall, true);
    s.prepare(1, 10, std::slice::from_ref(&work), &[], &[])?;
    let id = s.blocks[&1].id.clone();
    s.prepare(2, 20, &[], &[source_ended(&work, 2)], &[])?;
    assert_eq!(s.published, 0, "SourceEnded is not a visible boundary");
    assert!(!s.blocks[&1].sealed);
    let mut cold = state();
    cold.restore(
        "db",
        0,
        s.next_order,
        2,
        vec![s.blocks[&1].as_ref().clone()],
        vec![],
    )?;
    let mut next = atom("resumed", ChatAtomKind::Reasoning, false);
    next.source = ChatSourceId::ForegroundTurn {
        turn_id: "resumed-turn".into(),
    };
    next.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(3)),
        status: ChatActiveStatus::Running,
    };
    cold.prepare(3, 100_000, &[next], &[], &[])?;
    assert_eq!(cold.blocks.len(), 1);
    assert_eq!(cold.blocks[&1].id, id);
    assert_eq!(cold.blocks[&1].next_member, 2);
    Ok(())
}

#[test]
fn v364_text_terminal_does_not_seal_the_later_work() -> Result<()> {
    let mut s = state();
    s.prepare(
        1,
        10,
        &[atom("A", ChatAtomKind::Reasoning, false)],
        &[],
        &[],
    )?;
    let mut text = atom("T", ChatAtomKind::Text, false);
    text.content_present = Some(true);
    text.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(2)),
        status: ChatActiveStatus::Running,
    };
    s.prepare(2, 20, &[text], &[], &[])?;
    let mut b = atom("B", ChatAtomKind::ToolCall, false);
    b.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(3)),
        status: ChatActiveStatus::Running,
    };
    s.prepare(3, 30, &[b], &[], &[])?;
    let tail = s.blocks[&3].id.clone();
    let mut end = atom("T", ChatAtomKind::Text, true);
    end.content_present = Some(true);
    end.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(2)),
        ended: Some(at(4)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(4, 40, &[end], &[], &[])?;
    let mut y = atom("Y", ChatAtomKind::ToolCall, true);
    y.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(at(5)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(5, 50, &[y], &[], &[])?;
    assert_eq!(s.blocks.len(), 1);
    assert_eq!(s.blocks[&3].id, tail);
    assert_eq!(s.blocks[&3].next_member, 2);
    Ok(())
}

#[test]
fn background_tools_join_the_tail_and_only_independent_files_create_a_boundary() -> Result<()> {
    for name in ["exec", "search", pl_tool::file_display::TOOL_SHOW_FILES] {
        for outcome in [ChatTerminalOutcome::Completed, ChatTerminalOutcome::Failed] {
            let mut s = state();
            s.prepare(
                1,
                10,
                &[atom("foreground", ChatAtomKind::ToolCall, false)],
                &[],
                &[],
            )?;
            let foreground = s.blocks[&1].clone();
            let mut result = atom("result", ChatAtomKind::ToolCall, true);
            result.tool.as_mut().unwrap().name = name.into();
            result.source = ChatSourceId::BackgroundResult {
                message_id: "inbox-result".into(),
            };
            result.delivery = ChatDeliveryKind::Independent;
            result.completion_item_id = Some("real-completion".into());
            result.started_at = None;
            result.lifecycle = ChatAtomLifecycle::Terminal {
                started: None,
                ended: Some(at(2)),
                outcome,
            };
            let delta = s.prepare(
                2,
                20,
                std::slice::from_ref(&result),
                &[source_ended(&result, 2)],
                &[],
            )?;
            let result_member = delta
                .members
                .iter()
                .find(|m| m.head.record.atom.id == result.id)
                .unwrap();
            assert_eq!(result_member.head.record.atom, result);
            assert_eq!(
                crate::studio::runtime::chat_item::native_read_class_v1("conversation", &result)
                    .main_presentation,
                pl_protocol::MainPresentation::BackgroundResults
            );
            assert_eq!(result_member.head.record.start_fact, None);
            assert_eq!(result_member.head.record.end_fact, Some(at(2)));
            if name == pl_tool::file_display::TOOL_SHOW_FILES {
                assert_eq!(s.published, 2);
                assert_eq!(s.pending[&1].id, foreground.id);
                assert!(matches!(
                    s.pending[&2].body,
                    DisplayBlockBody::Single { .. }
                ));
            } else {
                assert_eq!(s.published, 0);
                assert_eq!(s.blocks.len(), 1);
                assert_eq!(s.blocks[&1].id, foreground.id);
                let DisplayBlockBody::Work {
                    timing: summary,
                    members,
                } = &s.blocks[&1].body
                else {
                    panic!("ordinary background tool must be Work");
                };
                assert_eq!(s.blocks[&1].next_member, 2);
                assert_eq!(s.blocks[&1].unfinished, 1);
                assert_eq!(summary.started_at, 10);
                assert_eq!(summary.finished_at, None);
                assert_eq!(members.block_id, foreground.id);
                assert_eq!(members.database_id, "db");
                assert!(!s.blocks[&1].sealed);
                assert_eq!(s.blocks[&1].source, foreground.source);
            }
        }
    }
    Ok(())
}

#[test]
fn completed_members_wait_for_visible_content_and_the_interval_includes_idle() -> Result<()> {
    let mut s = state();
    let a = atom("A", ChatAtomKind::ToolCall, false);
    s.prepare(1, 10, &[a], &[], &[])?;
    assert_eq!(timing(s.blocks.values().next().unwrap()).started_at, 10);
    assert_eq!(timing(s.blocks.values().next().unwrap()).finished_at, None);
    let done = atom("A", ChatAtomKind::ToolCall, true);
    s.prepare(2, 20, std::slice::from_ref(&done), &[], &[])?;
    s.confirm(2);
    assert_eq!(s.published, 0);
    assert_eq!(
        (s.blocks.values().next().unwrap().next_member
            - s.blocks.values().next().unwrap().unfinished),
        1
    );
    assert_eq!(timing(s.blocks.values().next().unwrap()).finished_at, None);
    // No visible boundary: the same open interval includes the idle gap.
    let id = s.blocks.values().next().unwrap().id.clone();
    let mut next = atom("B", ChatAtomKind::ToolCall, false);
    next.started_at = Some(1000); // The old active-interval metric excludes this gap.
    next = at_effect(next, 3);
    s.prepare(3, 1000, &[next.clone()], &[], &[])?;
    assert_eq!(s.blocks.values().next().unwrap().id, id);
    assert_eq!(timing(s.blocks.values().next().unwrap()).started_at, 10);
    assert_eq!(timing(s.blocks.values().next().unwrap()).finished_at, None);
    next.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(3)),
        ended: Some(at(4)),
        outcome: ChatTerminalOutcome::Completed,
    };
    next.finished_at = Some(1010);
    s.prepare(4, 1010, &[next], &[], &[])?;
    assert_eq!(timing(s.blocks.values().next().unwrap()).finished_at, None);
    assert_eq!(s.published, 0);
    let delta = s.prepare(5, 1200, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert_eq!(delta.published_through, 1);
    let frozen = delta.blocks.iter().find(|b| b.published.is_some()).unwrap();
    assert_eq!(timing(&frozen.header).started_at, 10);
    assert_eq!(timing(&frozen.header).finished_at, Some(1200));
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
    assert_eq!(timing(&frozen.header).finished_at, Some(1200));
    assert!(s.member_heads(&id, None, 8).is_empty());
    Ok(())
}

#[test]
fn current_snapshot_requires_the_group_start_and_never_persists_the_thought() -> Result<()> {
    let mut original = state();
    original.prepare(
        1,
        10,
        &[atom("work", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    let mut header = original.blocks[&1].as_ref().clone();
    header.thinking_summary = Some("transient thought".into());
    let wire = serde_json::to_value(&header)?;
    assert!(wire.get("thinking_summary").is_none());
    let restored: DisplayHeader = serde_json::from_value(wire.clone())?;
    assert!(restored.thinking_summary.is_none());
    assert_eq!(timing(&restored).started_at, 10);
    let mut missing = wire;
    missing["body"]["timing"]
        .as_object_mut()
        .unwrap()
        .remove("startedAt");
    assert!(serde_json::from_value::<DisplayHeader>(missing).is_err());
    Ok(())
}

#[test]
fn direct_completion_keeps_its_group_interval_independent_of_member_time() -> Result<()> {
    // A completed member's old/unknown active start is not its group creation time.
    for (created, observed) in [(100, 150), (100, 99), (i64::MIN, i64::MAX), (0, i64::MAX)] {
        let mut s = state();
        let mut done = atom("done", ChatAtomKind::ToolCall, true);
        done.started_at = None;
        s.prepare(1, created, &[done], &[], &[])?;
        assert_eq!(timing(&s.blocks[&1]).started_at, created);
        assert_eq!(timing(&s.blocks[&1]).finished_at, None);
        let delta = s.prepare(
            2,
            observed,
            &[atom("text", ChatAtomKind::Text, false)],
            &[],
            &[],
        )?;
        let frozen = delta.blocks.iter().find(|b| b.published.is_some()).unwrap();
        assert_eq!(timing(&frozen.header).started_at, created);
        assert_eq!(timing(&frozen.header).finished_at, Some(observed));
    }
    Ok(())
}

#[test]
fn late_terminals_and_cross_source_input_keep_the_global_creation_prefix() -> Result<()> {
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
        "first visible content freezes unfinished R/A immediately"
    );
    let first = s.pending[&1].clone();
    s.prepare(
        3,
        30,
        &[at_effect(atom("T", ChatAtomKind::Text, true), 3)],
        &[],
        &[],
    )?;
    s.prepare(
        4,
        40,
        &[at_effect(atom("A", ChatAtomKind::ToolCall, true), 4)],
        &[],
        &[],
    )?;
    assert_eq!(s.published, 2);
    let mut background = atom("A", ChatAtomKind::ToolCall, true);
    background.source = ChatSourceId::BackgroundResult {
        message_id: "result".into(),
    };
    background.delivery = ChatDeliveryKind::Independent;
    background = at_effect(background, 5);
    let mut input = atom("input", ChatAtomKind::Input, true);
    input.source = ChatSourceId::Input {
        input_id: "input".into(),
    };
    input.delivery = ChatDeliveryKind::Independent;
    input.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(ChatFactPosition {
            effect_seq: 5,
            suborder: 1,
        }),
        outcome: ChatTerminalOutcome::Completed,
    };
    let ended = source_ended(&background, 5);
    s.prepare(5, 50, &[background, input], &[ended], &[])?;
    assert_eq!(s.published, 4);
    assert!(s.blocks.is_empty());
    let DisplayBlockBody::Work {
        timing: summary, ..
    } = &s.pending[&3].body
    else {
        panic!("Work")
    };
    assert_eq!(s.frozen_headers[&s.retired[&3].1].next_member, 2);
    assert_eq!(summary.started_at, 40);
    assert_eq!(summary.finished_at, Some(50));
    let ended = s.prepare(
        6,
        60,
        &[at_effect(atom("R", ChatAtomKind::Reasoning, true), 6)],
        &[],
        &[],
    )?;
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
        matches!(&s.pending[&5].body, DisplayBlockBody::Work { timing: summary, .. }
        if summary.started_at == 60 && summary.finished_at == Some(70))
    );
    assert!(matches!(
        s.pending[&2].body,
        DisplayBlockBody::Single { .. }
    ));
    Ok(())
}

#[test]
fn transfer_and_background_result_have_distinct_rows_and_empty_text_keeps_the_tail() -> Result<()> {
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
    let ended = source_ended(&result, 2);
    s.prepare(2, 20, &[result], &[ended], &[])?;
    let tail = s.blocks[&1].id.clone();
    let mut empty_start = at_effect(atom("empty", ChatAtomKind::Text, false), 3);
    empty_start.content_present = Some(false);
    s.prepare(3, 30, &[empty_start], &[], &[])?;
    let mut empty = atom("empty", ChatAtomKind::Text, true);
    empty.content_present = Some(false);
    let delta = s.prepare(4, 40, &[at_effect(empty, 4)], &[], &[])?;
    assert!(delta.remove_empty.is_empty());
    assert_eq!(s.published, 0);
    assert_eq!(s.blocks[&1].next_member, 2);
    s.prepare(
        5,
        50,
        &[at_effect(atom("next", ChatAtomKind::ToolCall, false), 5)],
        &[],
        &[],
    )?;
    assert_eq!(s.blocks.values().next().unwrap().id, tail);
    assert_eq!(s.blocks[&1].next_member, 3);
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
    assert_eq!(s.blocks.values().next().unwrap().unfinished, 1);
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
    assert_eq!(
        (s.blocks.values().next().unwrap().next_member
            - s.blocks.values().next().unwrap().unfinished),
        1
    );
    s.prepare(6, 60, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert!(
        s.revision > revision,
        "create/handoff must stale the structural cursor"
    );
    Ok(())
}

#[test]
fn member_without_start_does_not_change_the_group_interval() -> Result<()> {
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
    assert_eq!(timing(head).started_at, 10);
    assert_eq!(timing(head).finished_at, None);

    Ok(())
}

#[test]
fn later_members_do_not_reset_the_group_start() -> Result<()> {
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
    assert_eq!(timing(head).started_at, 10);

    Ok(())
}

#[test]
fn members_have_a_bounded_head_delta_and_no_inline_saved_bodies() -> Result<()> {
    bounded_head_delta_and_deferred_bodies(1_000)
}

#[test]
#[ignore = "十万成员规模检查，由 Rust Scale Checks 定时或手动运行"]
fn hundred_thousand_members_have_a_bounded_head_delta_and_no_inline_saved_bodies() -> Result<()> {
    bounded_head_delta_and_deferred_bodies(100_000)
}

fn bounded_head_delta_and_deferred_bodies(member_count: u64) -> Result<()> {
    let mut s = state();
    for index in 0..member_count {
        let mut member = atom(&format!("tool-{index}"), ChatAtomKind::ToolCall, true);
        let effect = index + 1 + u64::from(index + 1 == member_count);
        member.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(at(effect)),
            ended: Some(at(effect)),
            outcome: ChatTerminalOutcome::Completed,
        };
        member.completion_item_id = Some(format!("original-{index}"));
        member.payload = Some(PayloadData::Inline {
            bytes: vec![42; 1024],
        });
        if index + 1 == member_count {
            member.lifecycle = ChatAtomLifecycle::Terminal {
                started: Some(at(member_count)),
                ended: Some(at(member_count + 1)),
                outcome: ChatTerminalOutcome::Completed,
            };
            let mut started = member.clone();
            started.completion_item_id = None;
            started.payload = None;
            started.finished_at = None;
            started.lifecycle = ChatAtomLifecycle::Active {
                started: Some(at(member_count)),
                status: ChatActiveStatus::Running,
            };
            s.prepare(member_count, member_count as i64, &[started], &[], &[])?;
        }
        let measured = matches!(index, 0 | 99 | 9_999) || index + 1 == member_count;
        if measured {
            s.begin_cost_observation();
        }
        let delta = s.prepare(effect, i64::try_from(index + 1)?, &[member], &[], &[])?;
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
                    "event": if index + 1 == member_count { "existing_member_terminal" } else { "direct_member_terminal" },
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
        s.confirm(effect);
        assert!(
            s.members.is_empty(),
            "durable terminal rows must leave the open tail"
        );
        assert!(s.current_work_rows.is_empty());
    }
    assert_eq!(s.members.len(), 0);
    let cut = s.capture(None, 1, 0, 1);
    assert_eq!(cut.open.len(), 1);
    assert_eq!(cut.open[0].next_member, member_count);
    assert!(s.retained_bytes() < 4096);
    let mut text = atom("text", ChatAtomKind::Text, false);
    text.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(member_count + 2)),
        status: ChatActiveStatus::Running,
    };
    s.begin_cost_observation();
    let delta = s.prepare(
        member_count + 2,
        i64::try_from(member_count + 2)?,
        &[text],
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
    assert_eq!(delta.members.len(), 1); // No fold/rewrite of saved member heads.
    assert_eq!(delta.blocks.len(), 2);
    assert_eq!(delta.published_through, 1);
    s.confirm(member_count + 2);
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

#[test]
fn completed_reasoning_updates_open_work_thinking_summary_without_leaking_across_boundary()
-> Result<()> {
    use pl_core::chat::{ChatDraft, ChatItem};
    use pl_protocol::{ThreadContentLifecycle, ThreadItem, ThreadItemState, ThreadThinkingItem};

    fn completed_reasoning(
        id: &str,
        ordinal: u64,
        effect_seq: u64,
        summaries: Vec<String>,
        contents: Vec<String>,
        append_seq: u64,
    ) -> Result<(ChatAtom, Arc<ChatItem>)> {
        let item = ThreadItem::new(
            id.into(),
            "thread".into(),
            "turn".into(),
            ordinal,
            1,
            10,
            20,
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                summaries,
                contents,
                ThreadContentLifecycle::completed(20),
            )),
        );
        let draft: ChatDraft =
            crate::studio::runtime::chat_item::completion_draft(&item, effect_seq, "db")?;
        let mut atom: ChatAtom = serde_json::from_slice(&draft.metadata)?;
        atom.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(at(effect_seq - 1)),
            ended: Some(at(effect_seq)),
            outcome: ChatTerminalOutcome::Completed,
        };
        atom.started_at = Some(10);
        atom.finished_at = Some(20);
        Ok((atom, Arc::new(ChatItem::complete(draft, append_seq, None))))
    }

    let mut s = state();
    // 1. Reasoning R1 starts active -> completes with multi-chunk Markdown summary.
    let mut r1_active = atom("r1", ChatAtomKind::Reasoning, false);
    r1_active.source_order = Some(1);
    s.prepare(1, 10, &[r1_active], &[], &[])?;
    assert_eq!(s.blocks[&1].thinking_summary, None);
    let persisted = serde_json::to_value(&s.blocks[&1])?;
    let revision = s.blocks[&1].revision;
    s.members.begin();
    s.observe_thinking_summary("流式 **摘要**");
    s.observe_thinking_summary("最新流式 **摘要**");
    let accesses = s.members.finish();
    assert_eq!(
        (accesses.reads, accesses.writes, accesses.misses),
        (0, 0, 0)
    );
    assert_eq!(
        s.blocks[&1].thinking_summary.as_deref(),
        Some("最新流式 **摘要**")
    );
    assert_eq!(s.blocks[&1].revision, revision);
    assert_eq!(serde_json::to_value(&s.blocks[&1])?, persisted);

    let (r1_done, r1_item) = completed_reasoning(
        "r1",
        1,
        2,
        vec![
            "旧段落摘要".into(),
            "第一段说明\n梳理 **会话共享组件** 与 `LiveStatusBar` 边界".into(),
        ],
        vec!["完整推理正文".into()],
        1,
    )?;
    s.prepare(2, 20, &[r1_done], &[], &[r1_item])?;
    assert_eq!(
        s.blocks[&1].thinking_summary.as_deref(),
        Some("梳理 **会话共享组件** 与 `LiveStatusBar` 边界")
    );

    // 2. Subsequent exec tool runs and finishes inside the same open Work: thinking_summary stays intact.
    s.prepare(
        3,
        25,
        &[atom("exec-1", ChatAtomKind::ToolCall, false)],
        &[],
        &[],
    )?;
    assert_eq!(
        s.blocks[&1].thinking_summary.as_deref(),
        Some("梳理 **会话共享组件** 与 `LiveStatusBar` 边界")
    );
    s.prepare(
        4,
        30,
        &[atom("exec-1", ChatAtomKind::ToolCall, true)],
        &[],
        &[],
    )?;
    assert_eq!(
        s.blocks[&1].thinking_summary.as_deref(),
        Some("梳理 **会话共享组件** 与 `LiveStatusBar` 边界")
    );

    // 3. A raw-only reasoning step without summary does NOT wipe the current group's thinking_summary.
    let (r_nosummary, r_nosummary_item) =
        completed_reasoning("r-raw", 2, 6, vec![], vec!["仅有正文无摘要".into()], 2)?;
    s.prepare(6, 35, &[r_nosummary], &[], &[r_nosummary_item])?;
    assert_eq!(
        s.blocks[&1].thinking_summary.as_deref(),
        Some("梳理 **会话共享组件** 与 `LiveStatusBar` 边界")
    );

    // 4. A later reasoning step in the SAME open Work with a new summary replaces it in-place.
    let (r2_done, r2_item) = completed_reasoning(
        "r2",
        3,
        8,
        vec!["### 确认收尾检查与 `cargo flutter analyze`".into()],
        vec!["再次核对".into()],
        3,
    )?;
    s.prepare(8, 40, &[r2_done], &[], &[r2_item])?;
    assert_eq!(
        s.blocks[&1].thinking_summary.as_deref(),
        Some("### 确认收尾检查与 `cargo flutter analyze`")
    );

    // 5. Text boundary seals the first Work; opening a new Work after Text starts fresh with None.
    s.prepare(
        9,
        50,
        &[atom("reply-1", ChatAtomKind::Text, false)],
        &[],
        &[],
    )?;
    let mut reply_done = atom("reply-1", ChatAtomKind::Text, true);
    reply_done.content_present = Some(true);
    s.prepare(10, 55, &[reply_done], &[], &[])?;
    s.prepare(
        11,
        60,
        &[at_effect(atom("exec-2", ChatAtomKind::ToolCall, false), 11)],
        &[],
        &[],
    )?;
    let next_work = s
        .blocks
        .values()
        .find(|block| matches!(block.body, DisplayBlockBody::Work { .. }) && !block.sealed)
        .expect("new open Work after boundary");
    assert_eq!(next_work.thinking_summary, None);
    Ok(())
}
