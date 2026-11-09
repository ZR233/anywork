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
    s.prepare(1, &[a], &[], &[])?;
    let done = atom("A", ChatAtomKind::ToolCall, true);
    s.prepare(2, std::slice::from_ref(&done), &[], &[])?;
    s.confirm(2);
    assert_eq!(s.published, 0);
    assert_eq!(summary(s.blocks.values().next().unwrap()).terminal, 1);
    let id = s.blocks.values().next().unwrap().id.clone();
    let mut next = atom("B", ChatAtomKind::ToolCall, false);
    next.started_at = Some(1000); // Waiting for a successor is not work time.
    s.prepare(3, &[next.clone()], &[], &[])?;
    assert_eq!(s.blocks.values().next().unwrap().id, id);
    next.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(3)),
        ended: Some(at(4)),
        outcome: ChatTerminalOutcome::Completed,
    };
    next.finished_at = Some(1010);
    s.prepare(4, &[next], &[], &[])?;
    assert_eq!(
        summary(s.blocks.values().next().unwrap()).duration_ms,
        Some(20)
    );
    let delta = s.prepare(5, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert_eq!(delta.published_through, 1);
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
    assert!(s.member_heads(&id, None, 8).is_empty());
    Ok(())
}

#[test]
fn reverse_terminals_keep_source_prefix_while_background_and_input_advance() -> Result<()> {
    let mut s = state();
    s.prepare(
        1,
        &[
            atom("R", ChatAtomKind::Reasoning, false),
            atom("A", ChatAtomKind::ToolCall, false),
        ],
        &[],
        &[],
    )?;
    s.prepare(2, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    s.prepare(3, &[atom("T", ChatAtomKind::Text, true)], &[], &[])?;
    s.prepare(4, &[atom("A", ChatAtomKind::ToolCall, true)], &[], &[])?;
    assert_eq!(s.published, 0);
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
    s.prepare(5, &[background, input], &[], &[])?;
    assert_eq!(s.published, 2);
    assert_eq!(s.blocks.len(), 2);
    let delta = s.prepare(6, &[atom("R", ChatAtomKind::Reasoning, true)], &[], &[])?;
    assert_eq!(s.published, 4);
    assert_eq!(
        delta
            .blocks
            .iter()
            .filter_map(|w| w.header.history_pos)
            .collect::<Vec<_>>(),
        vec![3, 4]
    );
    assert!(matches!(s.pending[&3].body, DisplayBlockBody::Work { .. }));
    assert!(matches!(
        s.pending[&4].body,
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
    s.prepare(1, &[handoff.clone()], &[], &[])?;
    let mut result = handoff.clone();
    result.source = ChatSourceId::BackgroundResult {
        message_id: "bg".into(),
    };
    result.delivery = ChatDeliveryKind::Independent;
    if let ChatAtomLifecycle::Terminal { outcome, .. } = &mut result.lifecycle {
        *outcome = ChatTerminalOutcome::Completed;
    }
    assert_ne!(member_key(&handoff)?, member_key(&result)?);
    s.prepare(2, &[result], &[], &[])?;
    s.prepare(3, &[atom("empty", ChatAtomKind::Text, false)], &[], &[])?;
    let mut empty = atom("empty", ChatAtomKind::Text, true);
    empty.content_present = Some(false);
    let delta = s.prepare(4, &[empty], &[], &[])?;
    assert_eq!(delta.remove_empty.len(), 1);
    assert_eq!(s.published, 2); // background + foreground Work, not the empty Text
    let old = s.pending[&2].id.clone();
    s.prepare(5, &[atom("next", ChatAtomKind::ToolCall, false)], &[], &[])?;
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
    s.prepare(1, &[waiting.clone()], &[], &[])?;
    let revision = s.revision;
    let mut watch = s.subscribe_members();
    s.prepare(2, &[waiting], &[], &[])?;
    assert_eq!(s.revision, revision);
    assert!(!watch.has_changed()?);
    assert_eq!(summary(s.blocks.values().next().unwrap()).waiting, 1);
    let terminal = atom("q", ChatAtomKind::ToolCall, true);
    s.prepare(3, std::slice::from_ref(&terminal), &[], &[])?;
    assert_eq!(
        s.revision, revision,
        "terminal/summary changes do not stale live older"
    );
    assert!(watch.has_changed()?);
    watch.borrow_and_update();
    s.prepare(4, std::slice::from_ref(&terminal), &[], &[])?;
    assert!(!watch.has_changed()?);
    let before = s.revision;
    let mut conflict = terminal;
    conflict.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(1)),
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Failed,
    };
    assert!(s.prepare(5, &[conflict], &[], &[]).is_err());
    assert_eq!(s.revision, before);
    assert_eq!(summary(s.blocks.values().next().unwrap()).terminal, 1);
    s.prepare(6, &[atom("T", ChatAtomKind::Text, false)], &[], &[])?;
    assert!(
        s.revision > revision,
        "create/handoff must stale the structural cursor"
    );
    Ok(())
}

#[test]
fn parallel_member_without_start_invalidates_the_work_duration() -> Result<()> {
    let mut s = state();
    s.prepare(1, &[atom("A", ChatAtomKind::ToolCall, false)], &[], &[])?;
    let mut b = atom("B", ChatAtomKind::ToolCall, true);
    b.started_at = None;
    b.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Completed,
    };
    s.prepare(2, &[b], &[], &[])?;
    let mut a = atom("A", ChatAtomKind::ToolCall, true);
    a.finished_at = Some(30);
    s.prepare(3, &[a], &[], &[])?;
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
    s.prepare(1, &[unknown], &[], &[])?;
    s.prepare(2, &[atom("known", ChatAtomKind::ToolCall, true)], &[], &[])?;
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
            s.prepare(100_000, &[started], &[], &[])?;
        }
        let measured = matches!(index, 0 | 99 | 9_999 | 99_999);
        if measured {
            s.begin_cost_observation();
        }
        let delta = s.prepare(index + 1 + u64::from(index == 99_999), &[member], &[], &[])?;
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
            delta.members[0].head.atom.payload,
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
