use anyhow::Result;
use pl_core::thread::{CoreEventSink, CoreLiveEvent};
use tokio::time::Duration;

use crate::history::{
    EventPayloadEnvelope, HistoryBodyRole, HistoryEntityKind, HistoryEntityState, HistoryEvent,
    HistoryEventKind, HistoryEventMeta, HistoryLimits, HistoryStore, HistoryTimelineRole,
    PendingBody, pack_bodies,
};
use crate::{ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome, Thread, ThreadTextChannel};

use super::conversation_feed::{ConversationFeed, SessionMetaLayer};
use super::live_status_layer::{LiveStatusDataLayer, STREAMING_TEXT_COALESCE_INTERVAL};
use super::meta_bus::MetaEventBus;
use super::models::{
    ConversationEvent, LiveStatusPhase, TimelineItem, TimelinePatch, WorkGroupMember,
};

fn test_thread(id: &str) -> Thread {
    Thread::placeholder(id)
}

#[allow(clippy::too_many_arguments)]
fn make_text_event(
    id: &str,
    kind: HistoryEventKind,
    role: HistoryTimelineRole,
    entity_kind: HistoryEntityKind,
    channel: Option<ThreadTextChannel>,
    text: &str,
    turn_id: &str,
    database_id: &str,
) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(id, kind, role, 1_000_000);
    event.occurred_at = Some(1_000_000);
    event.run_id = Some("run-1".into());
    event.turn_id = Some(turn_id.into());
    event.entity_id = Some(id.into());
    if entity_kind == HistoryEntityKind::Input {
        event.source = Some(ChatSourceId::Input {
            input_id: id.into(),
        });
    }
    let bodies = pack_bodies(
        &mut event,
        vec![PendingBody::new(
            "body",
            HistoryBodyRole::Body,
            Some("text/plain; charset=utf-8".into()),
            text.as_bytes().to_vec(),
        )],
        database_id,
    )?;
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: if entity_kind == HistoryEntityKind::Reasoning {
            "thinking".into()
        } else {
            "text".into()
        },
        meta: HistoryEventMeta {
            entity_id: id.into(),
            entity_kind,
            delivery: if role == HistoryTimelineRole::Work {
                ChatDeliveryKind::Foreground
            } else {
                ChatDeliveryKind::Independent
            },
            state: HistoryEntityState::KnownTerminal {
                outcome: ChatTerminalOutcome::Completed,
            },
            started_at: Some(1_000_000),
            finished_at: Some(1_000_500),
            text_channel: channel,
            model_recovery: None,
            single_visibility: None,
            presentation_contract: None,
            source_order: Some(1),
            content_present: Some(!text.is_empty()),
            wait: None,
            tool: None,
        },
        data: serde_json::json!({ "channel": channel }),
        bodies,
        source_order: Some(1),
        turn_id: Some(turn_id.into()),
        captured_at: Some(1_000_000),
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(event)
}

#[allow(clippy::too_many_arguments)]
fn make_tool_event(
    event_id: &str,
    call_id: &str,
    tool_name: &str,
    kind: HistoryEventKind,
    arguments: &str,
    output: Option<&str>,
    turn_id: &str,
    database_id: &str,
) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(event_id, kind, HistoryTimelineRole::Work, 1_000_100);
    event.occurred_at = Some(1_000_100);
    event.run_id = Some("run-1".into());
    event.turn_id = Some(turn_id.into());
    event.call_id = Some(call_id.into());
    event.entity_id = Some(format!("tool:{}:{call_id}", call_id.len()));
    event.tool_name = Some(tool_name.into());

    let mut pending = vec![PendingBody::new(
        "tool.arguments",
        HistoryBodyRole::ToolArguments,
        Some("application/json".into()),
        arguments.as_bytes().to_vec(),
    )];
    if let Some(out) = output {
        pending.push(PendingBody::new(
            "tool.result",
            HistoryBodyRole::ToolOutput,
            Some("text/plain".into()),
            out.as_bytes().to_vec(),
        ));
    }
    let bodies = pack_bodies(&mut event, pending, database_id)?;
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "tool".into(),
        meta: HistoryEventMeta {
            entity_id: event.entity_id.clone().unwrap(),
            entity_kind: HistoryEntityKind::ToolCall,
            delivery: ChatDeliveryKind::Foreground,
            state: if output.is_some() {
                HistoryEntityState::KnownTerminal {
                    outcome: ChatTerminalOutcome::Completed,
                }
            } else {
                HistoryEntityState::KnownActive {
                    status: crate::ChatActiveStatus::Running,
                }
            },
            started_at: Some(1_000_100),
            finished_at: output.map(|_| 1_000_200),
            text_channel: None,
            model_recovery: None,
            single_visibility: None,
            presentation_contract: Some("shell@1".into()),
            source_order: Some(2),
            content_present: Some(true),
            wait: None,
            tool: Some(crate::ChatToolIdentity {
                call_id: call_id.into(),
                name: tool_name.into(),
            }),
        },
        data: serde_json::json!({
            "invocation": { "toolCallId": call_id, "name": tool_name },
            "state": { "kind": if output.is_some() { "succeeded" } else { "running" } }
        }),
        bodies,
        source_order: Some(2),
        turn_id: Some(turn_id.into()),
        captured_at: Some(1_000_100),
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(event)
}

#[tokio::test]
async fn live_turns_use_zero_sqlite_reads_and_seal_naturally_with_cold_isomorphism() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&db_path, "thread-1", HistoryLimits::default()).await?;
    let db_id = store.database_id().to_owned();
    let bus = MetaEventBus::open(
        test_thread("thread-1"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );

    let meta = SessionMetaLayer::empty("thread-1").snapshot();
    let feed =
        ConversationFeed::open_static("thread-1", store.reader(), Some(bus.clone()), meta, 64)
            .await?;

    // Drain initial Reset + LiveStatus(Idle) + SessionMeta.
    let reset = feed.next_event().await.unwrap();
    assert!(matches!(
        reset,
        ConversationEvent::Timeline(TimelinePatch::Reset { items, .. }) if items.is_empty()
    ));
    let _ = feed.next_event().await.unwrap();
    let _ = feed.next_event().await.unwrap();

    // Reset read count check baseline after initial cold open of empty DB.
    let baseline_reads = store.read_query_count();

    // 1. User input -> Boundary(2) emitted immediately.
    let user_ev = make_text_event(
        "input-1",
        HistoryEventKind::InputAccepted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Input,
        Some(ThreadTextChannel::User),
        "run ls",
        "turn-1",
        &db_id,
    )?;
    bus.admit_and_broadcast(vec![user_ev]).await?;

    let mut live_items = Vec::new();
    loop {
        match feed.next_event().await.unwrap() {
            ConversationEvent::Timeline(TimelinePatch::Append { items }) => {
                live_items.extend(items);
                break;
            }
            ConversationEvent::LiveStatus(_) => {}
            other => panic!("expected Append user message, got {other:?}"),
        }
    }
    assert!(matches!(
        feed.next_event().await.unwrap(),
        ConversationEvent::InputPresented { input_id, .. } if input_id == "input-1"
    ));

    // 2. Work items (Reasoning + ToolCalled + ToolCompleted) MUST NOT push to Timeline until sealed.
    let work1 = make_text_event(
        "reason-1",
        HistoryEventKind::ReasoningCompleted,
        HistoryTimelineRole::Work,
        HistoryEntityKind::Reasoning,
        None,
        "checking workspace",
        "turn-1",
        &db_id,
    )?;
    let work2 = make_tool_event(
        "tool-called-1",
        "call-1",
        "shell",
        HistoryEventKind::ToolCalled,
        r#"{"command":"ls"}"#,
        None,
        "turn-1",
        &db_id,
    )?;
    let work3 = make_tool_event(
        "tool-done-1",
        "call-1",
        "shell",
        HistoryEventKind::ToolCompleted,
        r#"{"command":"ls"}"#,
        Some("Cargo.toml"),
        "turn-1",
        &db_id,
    )?;
    let seqs = bus.admit_and_broadcast(vec![work1, work2, work3]).await?;
    let first_work_seq = seqs[0];
    assert_eq!(store.read_query_count(), baseline_reads);

    // 3. TextStreamStarted arrives -> seals pending WorkGroup("work:<first_work_seq>") immediately!
    bus.emit(pl_core::thread::CoreEvent::Live(CoreLiveEvent::TextStreamStarted {
        attempt_id: "att-1".into(),
        item_id: "text-1".into(),
        generation: 0,
    }));

    // Wait for LiveStatus(Working -> StreamingText) and Timeline(Append WorkGroup).
    loop {
        match tokio::time::timeout(Duration::from_secs(2), feed.next_event()).await? {
            Some(ConversationEvent::Timeline(TimelinePatch::Append { items })) => {
                live_items.extend(items);
                break;
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("unexpected event before WorkGroup seal: {other:?}"),
        }
    }
    assert!(matches!(
        live_items.last().unwrap(),
        TimelineItem::WorkGroup { id, member_count: 2, .. } if id == &format!("work:{first_work_seq}")
    ));

    // 4. Final AssistantText -> Boundary(2).
    let ans = make_text_event(
        "text-1",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "Done!",
        "turn-1",
        &db_id,
    )?;
    bus.admit_and_broadcast(vec![ans]).await?;
    loop {
        match tokio::time::timeout(Duration::from_secs(2), feed.next_event()).await? {
            Some(ConversationEvent::Timeline(TimelinePatch::Append { items })) => {
                live_items.extend(items);
                break;
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("unexpected event: {other:?}"),
        }
    }

    // 5. Verify WorkGroup expansion folds `ToolCalled` + `ToolCompleted` into 1 ToolCall member + 1 Reasoning member.
    let members = match &live_items[1] {
        TimelineItem::WorkGroup {
            after_boundary_seq,
            before_boundary_seq,
            ..
        } => {
            feed.load_work_group_members(*after_boundary_seq, *before_boundary_seq)
                .await?
        }
        other => panic!("expected WorkGroup, got {other:?}"),
    };
    assert_eq!(members.len(), 2);
    assert!(matches!(members[0], WorkGroupMember::Reasoning { .. }));
    assert!(matches!(
        &members[1],
        WorkGroupMember::ToolCall { call_id, status, arguments: Some(args), result_preview: Some(res), .. }
        if call_id == "call-1" && status == "succeeded" && args.contains("ls") && res == "Cargo.toml"
    ));

    // Zero SQLite reads happened during the entire live turn before the explicit expand query!
    // (`load_work_group_members` was the single on-demand read query after the turn.)
    assert_eq!(store.read_query_count(), baseline_reads + 1);

    // 6. Close feed & store, reopen cold from SQLite, and assert 100% isomorphic timeline IDs!
    feed.close().await;
    bus.close().await;
    store.close().await?;

    let reopened = HistoryStore::open(&db_path, "thread-1", HistoryLimits::default()).await?;
    let cold_feed = ConversationFeed::open_static(
        "thread-1",
        reopened.reader(),
        None,
        SessionMetaLayer::empty("thread-1").snapshot(),
        64,
    )
    .await?;
    let cold_items = match cold_feed.next_event().await.unwrap() {
        ConversationEvent::Timeline(TimelinePatch::Reset { items, .. }) => items,
        other => panic!("expected cold Reset, got {other:?}"),
    };
    let live_ids: Vec<&str> = live_items.iter().map(TimelineItem::id).collect();
    let cold_ids: Vec<&str> = cold_items.iter().map(TimelineItem::id).collect();
    assert_eq!(live_ids, cold_ids);

    cold_feed.close().await;
    reopened.close().await?;
    Ok(())
}

#[test]
fn live_status_state_machine_transitions_and_coalescing() {
    let sm = LiveStatusDataLayer::new();
    assert!(matches!(sm.snapshot().phase, LiveStatusPhase::Idle));

    // Reasoning switches Idle -> Working
    let snap = sm
        .on_live_event(&CoreLiveEvent::ReasoningDelta {
            attempt_id: "a1".into(),
            item_id: "r1".into(),
            generation: 0,
            text: "thinking step".into(),
            replace: false,
        })
        .unwrap();
    assert!(matches!(snap.phase, LiveStatusPhase::Working { .. }));

    // TextStreamStarted switches Working -> StreamingText immediately
    let snap = sm
        .on_live_event(&CoreLiveEvent::TextStreamStarted {
            attempt_id: "a1".into(),
            item_id: "t1".into(),
            generation: 0,
        })
        .unwrap();
    assert!(matches!(snap.phase, LiveStatusPhase::StreamingText { .. }));

    // TextStreamDelta is buffered (None) until 16ms flush_coalesced()
    assert!(
        sm.on_live_event(&CoreLiveEvent::TextStreamDelta {
            attempt_id: "a1".into(),
            item_id: "t1".into(),
            generation: 0,
            text: "Hello ".into(),
            replace: false,
        })
        .is_none()
    );
    assert!(
        sm.on_live_event(&CoreLiveEvent::TextStreamDelta {
            attempt_id: "a1".into(),
            item_id: "t1".into(),
            generation: 0,
            text: "world".into(),
            replace: false,
        })
        .is_none()
    );
    let flushed = sm.flush_coalesced().unwrap();
    assert!(matches!(
        &flushed.phase,
        LiveStatusPhase::StreamingText { text, .. } if text == "Hello world"
    ));
    assert!(STREAMING_TEXT_COALESCE_INTERVAL == Duration::from_millis(16));

    // TextStreamEnded while turn active -> Working
    let snap = sm
        .on_live_event(&CoreLiveEvent::TextStreamEnded {
            attempt_id: "a1".into(),
            item_id: "t1".into(),
            generation: 0,
        })
        .unwrap();
    assert!(matches!(snap.phase, LiveStatusPhase::Working { .. }));

    // CompactionStarted -> Compacting
    let snap = sm
        .on_live_event(&CoreLiveEvent::CompactionStarted {
            turn_id: Some("turn-1".into()),
            revision: 1,
            manual: false,
        })
        .unwrap();
    assert!(matches!(snap.phase, LiveStatusPhase::Compacting { manual: false, .. }));
}

#[tokio::test]
async fn load_older_preserves_page_seam_work_group_and_seals_bounded_ranges() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&db_path, "thread-pages", HistoryLimits::default()).await?;
    let db_id = store.database_id().to_owned();
    let bus = MetaEventBus::open(
        test_thread("thread-pages"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );

    // Build: B1 (user) -> W1 (tool) -> B2 (assistant) -> W2 (tool) -> B3 (assistant)
    let b1 = make_text_event(
        "b1",
        HistoryEventKind::InputAccepted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Input,
        Some(ThreadTextChannel::User),
        "first",
        "turn-1",
        &db_id,
    )?;
    let w1 = make_tool_event(
        "w1",
        "call-w1",
        "shell",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("ok1"),
        "turn-1",
        &db_id,
    )?;
    let b2 = make_text_event(
        "b2",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "second",
        "turn-1",
        &db_id,
    )?;
    let w2 = make_tool_event(
        "w2",
        "call-w2",
        "shell",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("ok2"),
        "turn-2",
        &db_id,
    )?;
    let b3 = make_text_event(
        "b3",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "third",
        "turn-2",
        &db_id,
    )?;
    bus.admit_and_broadcast(vec![b1, w1, b2, w2, b3]).await?;
    bus.close().await;
    store.close().await?;

    // Cold open with limit = 1 boundary (gets [B3]), then load_older(1) (must get [B2, WorkGroup(W2)])!
    let reopened = HistoryStore::open(&db_path, "thread-pages", HistoryLimits::default()).await?;
    let feed = ConversationFeed::open_static(
        "thread-pages",
        reopened.reader(),
        None,
        SessionMetaLayer::empty("thread-pages").snapshot(),
        1,
    )
    .await?;

    let (items0, cursor0) = match feed.next_event().await.unwrap() {
        ConversationEvent::Timeline(TimelinePatch::Reset {
            items,
            has_more_older,
            older_cursor,
            ..
        }) => {
            assert!(has_more_older);
            (items, older_cursor.unwrap())
        }
        other => panic!("expected Reset, got {other:?}"),
    };
    assert_eq!(items0.len(), 1);
    assert!(matches!(&items0[0], TimelineItem::AssistantText { text, .. } if text == "third"));

    let patch1 = feed.load_older(cursor0, 1).await?;
    match patch1 {
        TimelinePatch::PrependOlder { items, .. } => {
            assert_eq!(items.len(), 2, "expected [B2, WorkGroup(w2)], got {items:?}");
            assert!(matches!(&items[0], TimelineItem::AssistantText { text, .. } if text == "second"));
            assert!(matches!(&items[1], TimelineItem::WorkGroup { member_count: 1, .. }));
        }
        other => panic!("expected PrependOlder, got {other:?}"),
    }

    feed.close().await;
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn live_sealed_work_group_expands_without_leaking_next_turn_and_broadcasts_coalesced_to_two_feeds() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&db_path, "thread-multi", HistoryLimits::default()).await?;
    let db_id = store.database_id().to_owned();
    let bus = MetaEventBus::open(
        test_thread("thread-multi"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );

    let feed1 = ConversationFeed::open_static(
        "thread-multi",
        store.reader(),
        Some(bus.clone()),
        SessionMetaLayer::empty("thread-multi").snapshot(),
        64,
    )
    .await?;
    let feed2 = ConversationFeed::open_static(
        "thread-multi",
        store.reader(),
        Some(bus.clone()),
        SessionMetaLayer::empty("thread-multi").snapshot(),
        64,
    )
    .await?;

    // Drain initial Reset + LiveStatus + SessionMeta on both feeds.
    for f in [&feed1, &feed2] {
        for _ in 0..3 {
            let _ = f.next_event().await.unwrap();
        }
    }

    // Check dual-feed coalesced StreamingText delivery.
    bus.emit(pl_core::thread::CoreEvent::Live(CoreLiveEvent::TextStreamStarted {
        attempt_id: "att-1".into(),
        item_id: "item-1".into(),
        generation: 0,
    }));
    bus.emit(pl_core::thread::CoreEvent::Live(CoreLiveEvent::TextStreamDelta {
        attempt_id: "att-1".into(),
        item_id: "item-1".into(),
        generation: 0,
        text: "abc".into(),
        replace: false,
    }));
    for f in [&feed1, &feed2] {
        let mut saw_stream = false;
        let mut saw_delta = false;
        for _ in 0..4 {
            if let Ok(Some(ConversationEvent::LiveStatus(snap))) =
                tokio::time::timeout(Duration::from_millis(200), f.next_event()).await
            {
                if matches!(snap.phase, LiveStatusPhase::StreamingText { .. }) {
                    saw_stream = true;
                }
                if matches!(&snap.phase, LiveStatusPhase::StreamingText { text, .. } if text == "abc") {
                    saw_delta = true;
                    break;
                }
            }
        }
        assert!(saw_stream && saw_delta, "each feed must receive coalesced StreamingText");
    }

    // Admit Turn 1 tool -> TextStreamStarted seals WorkGroup -> later Turn 2 tool arrives.
    let w_t1 = make_tool_event(
        "w-t1",
        "call-t1",
        "shell",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("t1"),
        "turn-1",
        &db_id,
    )?;
    bus.admit_and_broadcast(vec![w_t1]).await?;
    bus.emit(pl_core::thread::CoreEvent::Live(CoreLiveEvent::TextStreamStarted {
        attempt_id: "att-2".into(),
        item_id: "item-2".into(),
        generation: 0,
    }));

    let wg = loop {
        match tokio::time::timeout(Duration::from_secs(2), feed1.next_event()).await? {
            Some(ConversationEvent::Timeline(TimelinePatch::Append { mut items })) => {
                break items.remove(0);
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("expected Append WorkGroup, got {other:?}"),
        }
    };

    // Append Turn 2 work item AFTER WorkGroup was sealed (no Boundary between them yet).
    let w_t2 = make_tool_event(
        "w-t2",
        "call-t2",
        "grep",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("t2"),
        "turn-2",
        &db_id,
    )?;
    let seqs_t2 = bus.admit_and_broadcast(vec![w_t2]).await?;
    let w_t2_seq = seqs_t2[0];

    // Expanding `wg` MUST only return `call-t1` (using latest head + bounded `before_boundary_seq`), never `call-t2`!
    let TimelineItem::WorkGroup {
        after_boundary_seq,
        before_boundary_seq,
        ..
    } = wg
    else {
        panic!("expected WorkGroup");
    };
    let members = feed1
        .load_work_group_members(after_boundary_seq, before_boundary_seq)
        .await?;
    assert_eq!(members.len(), 1);
    assert!(matches!(&members[0], WorkGroupMember::ToolCall { call_id, .. } if call_id == "call-t1"));

    // Emit Turn 1's TextCompleted Boundary before mid-Turn-2 test so Turn 1 and Turn 2 have a real DB Boundary.
    let ans1 = make_text_event(
        "ans-t1",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "turn 1 done",
        "turn-1",
        &db_id,
    )?;
    // Admit another Turn 2 work item + mid-turn cold open scenario after a fresh Boundary:
    bus.admit_and_broadcast(vec![ans1]).await?;
    let w_t3 = make_tool_event(
        "w-t3",
        "call-t3",
        "shell",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("t3"),
        "turn-3",
        &db_id,
    )?;
    let seqs_t3 = bus.admit_and_broadcast(vec![w_t3]).await?;
    let w_t3_seq = seqs_t3[0];

    // Mid-turn cold open while `LiveStatusPhase::Working` merges pre-open & post-open work into ONE WorkGroup.
    bus.emit(pl_core::thread::CoreEvent::Live(CoreLiveEvent::ReasoningDelta {
        attempt_id: "att-3".into(),
        item_id: "reason-3".into(),
        generation: 0,
        text: "thinking".into(),
        replace: false,
    }));
    // Wait until LiveStatus becomes Working before opening feed3.
    loop {
        if matches!(bus.live_status().snapshot().phase, LiveStatusPhase::Working { .. }) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    let feed3 = ConversationFeed::open_static(
        "thread-multi",
        store.reader(),
        Some(bus.clone()),
        SessionMetaLayer::empty("thread-multi").snapshot(),
        64,
    )
    .await?;
    let reset3 = match feed3.next_event().await.unwrap() {
        ConversationEvent::Timeline(TimelinePatch::Reset { items, .. }) => items,
        other => panic!("expected Reset on mid-turn open, got {other:?}"),
    };
    // `w_t3` must NOT have been prematurely sealed into Reset items while Working live!
    assert!(
        reset3.iter().all(|item| item.id() != format!("work:{w_t3_seq}")),
        "mid-turn open must keep trailing w_t3 in pending_work: {reset3:?}"
    );
    assert!(w_t2_seq < w_t3_seq);
    // Drain initial LiveStatus + SessionMeta, then emit another work + TextStreamStarted and expect ONE combined WorkGroup of 2 members!
    let _ = feed3.next_event().await.unwrap();
    let _ = feed3.next_event().await.unwrap();
    let w_t2_b = make_tool_event(
        "w-t2-b",
        "call-t2-b",
        "read",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("t2b"),
        "turn-2",
        &db_id,
    )?;
    bus.admit_and_broadcast(vec![w_t2_b]).await?;
    bus.emit(pl_core::thread::CoreEvent::Live(CoreLiveEvent::TextStreamStarted {
        attempt_id: "att-3".into(),
        item_id: "item-3".into(),
        generation: 0,
    }));
    let sealed_mid = loop {
        match tokio::time::timeout(Duration::from_secs(2), feed3.next_event()).await? {
            Some(ConversationEvent::Timeline(TimelinePatch::Append { mut items })) => {
                break items.remove(0);
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("expected combined WorkGroup, got {other:?}"),
        }
    };
    assert!(
        matches!(sealed_mid, TimelineItem::WorkGroup { member_count: 2, .. }),
        "expected combined 2-member WorkGroup, got {sealed_mid:?}"
    );

    feed1.close().await;
    feed2.close().await;
    feed3.close().await;
    bus.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn cold_opened_feed_transitions_seamlessly_when_bus_attaches() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&db_path, "thread-cold-live", HistoryLimits::default()).await?;
    let db_id = store.database_id().to_owned();

    // Seed one completed user turn while still cold.
    let prior_bus = MetaEventBus::open(
        test_thread("thread-cold-live"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    let prior_input = make_text_event(
        "input-old",
        HistoryEventKind::InputAccepted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Input,
        Some(ThreadTextChannel::User),
        "hello",
        "turn-old",
        &db_id,
    )?;
    prior_bus.admit_and_broadcast(vec![prior_input]).await?;
    prior_bus.close().await;

    // Open ConversationFeed while no bus is active (bus_tx = None).
    let (bus_tx, bus_rx) = tokio::sync::watch::channel(None);
    let feed = ConversationFeed::open(
        "thread-cold-live",
        store.reader(),
        bus_rx,
        SessionMetaLayer::empty("thread-cold-live").snapshot(),
        64,
    )
    .await?;

    let reset = feed.next_event().await.unwrap();
    assert!(matches!(
        reset,
        ConversationEvent::Timeline(TimelinePatch::Reset { items, .. }) if items.len() == 1
    ));
    let _ = feed.next_event().await.unwrap(); // initial Idle LiveStatus
    let _ = feed.next_event().await.unwrap(); // initial SessionMeta

    // Now start a live bus, admit an early commit BEFORE sending bus on watch (testing catchup!),
    // then attach it and emit a live streaming event.
    let live_bus = MetaEventBus::open(
        test_thread("thread-cold-live"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    let early_user = make_text_event(
        "input-new",
        HistoryEventKind::InputAccepted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Input,
        Some(ThreadTextChannel::User),
        "live follow-up",
        "turn-new",
        &db_id,
    )?;
    live_bus.admit_and_broadcast(vec![early_user]).await?;
    bus_tx.send(Some(live_bus.clone()))?;
    live_bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::TextStreamStarted {
            attempt_id: "att-live".into(),
            item_id: "item-live".into(),
            generation: 0,
        },
    ));

    let mut saw_new_user = false;
    let mut saw_stream = false;
    for _ in 0..8 {
        match tokio::time::timeout(Duration::from_secs(2), feed.next_event()).await? {
            Some(ConversationEvent::Timeline(TimelinePatch::Append { items })) => {
                if items
                    .iter()
                    .any(|item| matches!(item, TimelineItem::UserMessage { text, .. } if text == "live follow-up"))
                {
                    saw_new_user = true;
                }
            }
            Some(ConversationEvent::LiveStatus(snap)) => {
                if matches!(snap.phase, LiveStatusPhase::StreamingText { .. }) {
                    saw_stream = true;
                }
            }
            Some(ConversationEvent::InputPresented { .. } | ConversationEvent::SessionMeta(_)) => {}
            other => panic!("unexpected event on cold->live transition: {other:?}"),
        }
        if saw_new_user && saw_stream {
            break;
        }
    }
    assert!(saw_new_user && saw_stream);

    feed.close().await;
    live_bus.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn leading_work_before_first_boundary_is_materialized_with_no_more_older() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&db_path, "thread-leading-work", HistoryLimits::default()).await?;
    let db_id = store.database_id().to_owned();

    let work = make_tool_event(
        "ev-work-1",
        "call-1",
        "shell",
        HistoryEventKind::ToolCalled,
        r#"{"command":"ls"}"#,
        Some("ok"),
        "turn-1",
        &db_id,
    )?;
    let boundary = make_text_event(
        "ev-text-1",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "done",
        "turn-1",
        &db_id,
    )?;
    store.accept_batch(&[work, boundary]).await?;
    store.flush().await?;

    let mut layer = super::timeline_layer::TimelineDataLayer::new();
    let patch = layer.load_initial_page(&store.reader(), 64, false).await?;
    match patch {
        TimelinePatch::Reset {
            items,
            has_more_older,
            older_cursor,
            ..
        } => {
            assert!(!has_more_older, "leading work was already materialized");
            assert!(older_cursor.is_none());
            assert_eq!(items.len(), 2);
            assert!(matches!(items[0], TimelineItem::WorkGroup { .. }));
            assert!(matches!(items[1], TimelineItem::AssistantText { .. }));
        }
        other => panic!("expected Reset patch, got {other:?}"),
    }

    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn live_work_text_stream_work_boundary_seals_two_disjoint_groups() -> Result<()> {
    let mut layer = super::timeline_layer::TimelineDataLayer::new();

    let mut work1 = make_tool_event(
        "ev-w1",
        "call-w1",
        "read_file",
        HistoryEventKind::ToolCalled,
        r#"{"path":"a"}"#,
        Some("contents"),
        "turn-1",
        "db-1",
    )?;
    work1.seq = 10;
    assert!(layer.on_history_record(&work1.to_record(), None).is_empty());

    let seal1 = layer.on_live_event(&CoreLiveEvent::TextStreamStarted {
        attempt_id: "att-1".into(),
        item_id: "txt-1".into(),
        generation: 0,
    });
    assert_eq!(seal1.len(), 1);
    let (after1, before1) = match &seal1[0] {
        ConversationEvent::Timeline(TimelinePatch::Append { items }) => match &items[0] {
            TimelineItem::WorkGroup {
                after_boundary_seq,
                before_boundary_seq,
                ..
            } => (*after_boundary_seq, *before_boundary_seq),
            other => panic!("expected WorkGroup, got {other:?}"),
        },
        other => panic!("expected Append, got {other:?}"),
    };
    assert_eq!(after1, None);
    assert_eq!(before1, Some(11));

    let mut work2 = make_tool_event(
        "ev-w2",
        "call-w2",
        "edit_file",
        HistoryEventKind::ToolCalled,
        r#"{"path":"b"}"#,
        Some("edited"),
        "turn-1",
        "db-1",
    )?;
    work2.seq = 12;
    assert!(layer.on_history_record(&work2.to_record(), None).is_empty());

    let mut boundary = make_text_event(
        "ev-b2",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "all set",
        "turn-1",
        "db-1",
    )?;
    boundary.seq = 15;
    let seal2 = layer.on_history_record(&boundary.to_record(), None);
    assert_eq!(seal2.len(), 1);
    match &seal2[0] {
        ConversationEvent::Timeline(TimelinePatch::Append { items }) => {
            assert_eq!(items.len(), 2);
            match &items[0] {
                TimelineItem::WorkGroup {
                    after_boundary_seq,
                    before_boundary_seq,
                    ..
                } => {
                    assert_eq!(*after_boundary_seq, Some(10));
                    assert_eq!(*before_boundary_seq, Some(15));
                }
                other => panic!("expected WorkGroup, got {other:?}"),
            }
            assert!(matches!(items[1], TimelineItem::AssistantText { .. }));
        }
        other => panic!("expected Append, got {other:?}"),
    }

    Ok(())
}

#[tokio::test]
async fn live_status_coalesces_reasoning_deltas_and_preserves_tool_progress_summary() -> Result<()> {
    let layer = LiveStatusDataLayer::new();

    // First reasoning delta transitions Idle -> Working immediately.
    let first = layer.on_live_event(&CoreLiveEvent::ReasoningDelta {
        attempt_id: "att-r".into(),
        item_id: "item-r".into(),
        text: "Step 1".into(),
        replace: false,
        generation: 0,
    });
    assert!(matches!(
        first.map(|s| s.phase),
        Some(LiveStatusPhase::Working {
            reasoning_preview: Some(ref p),
            ..
        }) if p == "Step 1"
    ));

    // Subsequent reasoning deltas while Working coalesce until flush_coalesced().
    assert!(
        layer
            .on_live_event(&CoreLiveEvent::ReasoningDelta {
                attempt_id: "att-r".into(),
                item_id: "item-r".into(),
                text: " and 2".into(),
                replace: false,
                generation: 0,
            })
            .is_none()
    );
    let flushed = layer.flush_coalesced();
    assert!(matches!(
        flushed.map(|s| s.phase),
        Some(LiveStatusPhase::Working {
            reasoning_preview: Some(ref p),
            ..
        }) if p == "Step 1 and 2"
    ));
    assert!(layer.flush_coalesced().is_none());

    // Richer ToolProgress summary is preserved across ToolCompleted.
    let _ = layer.on_live_event(&CoreLiveEvent::ToolProgress {
        task_id: "task-x".into(),
        call_id: "call-x".into(),
        tool_id: "shell".into(),
        progress: pl_core::model::ToolProgress::default()
            .applied(&pl_core::model::ToolProgressUpdate::replace("stdout", "running cargo test")),
    });
    let mut completed = make_tool_event(
        "ev-tx",
        "call-x",
        "shell",
        HistoryEventKind::ToolCompleted,
        r#"{"command":"cargo test"}"#,
        Some("ok"),
        "turn-1",
        "db-1",
    )?;
    completed.seq = 20;
    let snap = layer.on_history_record(&completed.to_record()).unwrap();
    match snap.phase {
        LiveStatusPhase::Working { items, .. } => {
            assert_eq!(items.len(), 1);
            assert_eq!(items[0].status, "completed");
            assert_eq!(items[0].summary, "running cargo test");
        }
        other => panic!("expected Working phase, got {other:?}"),
    }

    Ok(())
}

#[tokio::test]
async fn meta_bus_translates_child_inbox_message_without_duplicate_event_ids() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("child-history.sqlite");
    let store = HistoryStore::open(&db_path, "child-1", HistoryLimits::default()).await?;

    let mut child = test_thread("child-1");
    child.parent_thread_id = Some("parent-1".into());

    let bus = MetaEventBus::open(
        child,
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );

    let payload: pl_core::context::OpaquePayload = serde_json::from_value(serde_json::json!({
        "format": "text/plain",
        "version": 1,
        "content": "child inbox instruction",
    }))?;
    let inbox = pl_core::thread::inbox::InboxRecord {
        sequence: 1,
        message: pl_core::thread::inbox::ThreadMessage {
            id: "msg-1".into(),
            source_id: "agent:parent-1".into(),
            kind: pl_core::context::AgentMessageKind::Unclassified,
            payload,
            context: Vec::new(),
        },
    };
    let state = pl_core::thread::ThreadSnapshot {
        inbox: std::sync::Arc::from([inbox.clone()]),
        ..Default::default()
    };
    let effect = pl_core::thread::ThreadEffectBatch {
        thread_id: "child-1".into(),
        sequence: 1,
        committed_at: 1_000,
        inbox: std::sync::Arc::from([inbox]),
        ..Default::default()
    };
    let export = std::sync::Arc::new(pl_core::thread::HistoryExport {
        effect: std::sync::Arc::new(effect),
        state,
        output_claim: None,
    });
    bus.sink().emit(pl_core::thread::CoreEvent::Durable(
        std::sync::Arc::new(pl_core::thread::CoreCommitEvent {
            thread_id: "child-1".into(),
            sequence: 1,
            export,
        }),
    ));
    bus.wait_admitted_commit(1).await;

    let reader = store.reader();
    let (_, originals, _) = reader
        .events_window(
            crate::history::HistoryEventsQuery::Originals {
                scope: crate::ChatScope {
                    query_class: crate::ChatClassFilter::All {},
                    parent_id: None,
                },
            },
            None,
            None,
            true,
            crate::history::HistoryDemand::default(),
        )
        .await?;
    let inbox_events: Vec<_> = originals
        .iter()
        .filter(|ev| ev.kind == HistoryEventKind::InboxMessageReceived)
        .collect();
    assert_eq!(inbox_events.len(), 1);
    assert!(matches!(
        inbox_events[0].source,
        Some(ChatSourceId::InboxMessage { ref message_id, .. }) if message_id == "msg-1"
    ));

    bus.close().await;
    store.close().await?;
    Ok(())
}
