use anyhow::Result;
use pl_core::thread::{CoreEvent, CoreEventSink, CoreLiveEvent};
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

#[test]
fn wait_and_sleep_fold_to_one_tool_with_original_turn_and_both_deferred_bodies() -> Result<()> {
    let long_arguments = serde_json::json!({ "detail": "a".repeat(17 * 1024) }).to_string();
    let long_result = "r".repeat(17 * 1024);
    let cases = [
        (
            "wait",
            serde_json::json!({
                "intent": { "kind": "events", "data": { "timeoutMs": 1000, "targets": [] } },
                "state": "waiting",
            }),
            Some("turn-finished"),
        ),
        (
            "sleep",
            serde_json::json!({
                "intent": { "kind": "timer", "data": { "durationMs": 1000 } },
                "state": "waiting",
            }),
            None,
        ),
    ];
    for (tool, wait, completed_turn) in cases {
        let mut called = make_tool_event(
            "called",
            "wait-call",
            tool,
            HistoryEventKind::ToolCalled,
            &long_arguments,
            None,
            "turn-called",
            "history",
        )?;
        let mut call_payload: EventPayloadEnvelope = serde_json::from_str(&called.payload_json)?;
        call_payload.data["wait"] = wait.clone();
        called.payload_json = serde_json::to_string(&call_payload)?;
        called.seq = 11;
        let mut completed = make_tool_event(
            "completed",
            "wait-call",
            tool,
            HistoryEventKind::ToolCompleted,
            "",
            Some(&long_result),
            "payload-turn",
            "history",
        )?;
        let mut result_payload: EventPayloadEnvelope =
            serde_json::from_str(&completed.payload_json)?;
        result_payload
            .bodies
            .retain(|body| body.key != "tool.arguments");
        completed.payload_json = serde_json::to_string(&result_payload)?;
        completed.seq = 15;
        completed.turn_id = completed_turn.map(str::to_owned);

        let members =
            super::fold_work_group_members(vec![called.to_record(), completed.to_record()]);
        let [
            WorkGroupMember::ToolCall {
                id,
                seq,
                call_id,
                turn_id,
                tool_name,
                status,
                bodies,
                wait_json,
                ..
            },
        ] = members.as_slice()
        else {
            panic!("expected one completed {tool} call, got {members:?}");
        };
        assert_eq!(id, "call:wait-call");
        assert_eq!(*seq, 15);
        assert_eq!(call_id, "wait-call");
        assert_eq!(
            turn_id.as_deref(),
            Some(completed_turn.unwrap_or("turn-called"))
        );
        assert_eq!(tool_name, tool);
        assert_eq!(status, "succeeded");
        assert_eq!(wait_json.as_deref(), Some(wait.to_string().as_str()));
        let keys_and_owners: Vec<_> = bodies
            .iter()
            .map(|body| {
                (
                    body.body_key.as_str(),
                    body.owner_event_id.as_str(),
                    body.byte_length,
                )
            })
            .collect();
        assert_eq!(
            keys_and_owners,
            [
                ("tool.arguments", "called", long_arguments.len() as u64),
                ("tool.result", "completed", long_result.len() as u64),
            ]
        );
    }
    Ok(())
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
    let reader = HistoryStore::open_reader(&db_path, "thread-1", HistoryLimits::default()).await?;
    let feed =
        ConversationFeed::open_static("thread-1", reader, Some(bus.clone()), meta, 64).await?;

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
    let paused_flush = store.pause_flush().await;

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

    // 3. TextStreamStarted only changes live status; Work stays pending until Boundary.
    bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::TextStreamStarted {
            attempt_id: "att-1".into(),
            item_id: "text-1".into(),
            generation: 0,
        },
    ));

    // The status frame is an ordering barrier: no Timeline patch may precede it.
    loop {
        match tokio::time::timeout(Duration::from_secs(2), feed.next_event()).await? {
            Some(ConversationEvent::LiveStatus(snapshot))
                if matches!(snapshot.phase, LiveStatusPhase::StreamingText { .. }) =>
            {
                break;
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("unexpected event before Boundary: {other:?}"),
        }
    }

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
                assert_eq!(
                    items.len(),
                    2,
                    "Boundary must publish group and text together"
                );
                assert!(
                    matches!(&items[0], TimelineItem::WorkGroup { id, member_count: 2, .. }
                    if id == &format!("work:{first_work_seq}"))
                );
                live_items.extend(items);
                break;
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("unexpected event: {other:?}"),
        }
    }

    // 5. Verify WorkGroup expansion folds `ToolCalled` + `ToolCompleted` into 1 ToolCall member + 1 Reasoning member.
    assert_eq!(
        store.durable_head(),
        0,
        "Boundary must be visible before any flush"
    );
    assert_eq!(store.read_query_count(), baseline_reads);
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
    drop(paused_flush);
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
    assert_eq!(
        live_items, cold_items,
        "IDs, ranges and summaries must survive restart"
    );

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
            is_summary: false,
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
    assert!(matches!(
        snap.phase,
        LiveStatusPhase::Compacting { manual: false, .. }
    ));
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
    bus.admit_and_broadcast(vec![b1, w1, b2]).await?;
    store.flush().await?;
    let paused_flush = store.pause_flush().await;
    bus.admit_and_broadcast(vec![w2, b3]).await?;
    let mut memory_layer = super::timeline_layer::TimelineDataLayer::new();
    let reader = store.reader();
    let expected = match memory_layer.load_initial_page(&reader, 64, false).await? {
        TimelinePatch::Reset { items, .. } => items,
        other => panic!("expected Reset, got {other:?}"),
    };
    assert_eq!(
        expected.iter().map(TimelineItem::id).collect::<Vec<_>>(),
        ["msg:1", "work:2", "msg:3", "work:4", "msg:5"]
    );
    let mut paged = Vec::new();
    let mut memory_page = memory_layer.load_initial_page(&reader, 1, false).await?;
    loop {
        let (mut items, cursor) = match memory_page {
            TimelinePatch::Reset {
                items,
                older_cursor,
                ..
            }
            | TimelinePatch::PrependOlder {
                items,
                older_cursor,
                ..
            } => (items, older_cursor),
            other => panic!("unexpected page {other:?}"),
        };
        items.append(&mut paged);
        paged = items;
        match cursor {
            Some(cursor) => memory_page = memory_layer.load_older(&reader, cursor, 1).await?,
            None => break,
        }
    }
    assert_eq!(
        paged, expected,
        "paging across persisted/pending seam must match full page"
    );
    reader.close().await;
    drop(paused_flush);
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

    let mut cold_paged = items0;
    let patch1 = feed.load_older(cursor0, 1).await?;
    match patch1 {
        TimelinePatch::PrependOlder {
            mut items,
            older_cursor,
            ..
        } => {
            assert_eq!(
                items.len(),
                2,
                "expected [B2, WorkGroup(w2)], got {items:?}"
            );
            assert!(
                matches!(&items[0], TimelineItem::AssistantText { text, .. } if text == "second")
            );
            assert!(matches!(
                &items[1],
                TimelineItem::WorkGroup {
                    member_count: 1,
                    ..
                }
            ));
            items.append(&mut cold_paged);
            cold_paged = items;
            match feed
                .load_older(older_cursor.expect("B1 remains"), 1)
                .await?
            {
                TimelinePatch::PrependOlder {
                    mut items,
                    has_more_older: false,
                    ..
                } => {
                    items.append(&mut cold_paged);
                    cold_paged = items;
                }
                other => panic!("expected final older page, got {other:?}"),
            }
        }
        other => panic!("expected PrependOlder, got {other:?}"),
    }
    assert_eq!(
        cold_paged, expected,
        "cold pagination must preserve group IDs and member bounds"
    );

    feed.close().await;
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn live_sealed_work_group_expands_without_leaking_next_turn_and_broadcasts_coalesced_to_two_feeds()
-> Result<()> {
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
    bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::TextStreamStarted {
            attempt_id: "att-1".into(),
            item_id: "item-1".into(),
            generation: 0,
        },
    ));
    bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::TextStreamDelta {
            attempt_id: "att-1".into(),
            item_id: "item-1".into(),
            generation: 0,
            text: "abc".into(),
            replace: false,
        },
    ));
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
                if matches!(&snap.phase, LiveStatusPhase::StreamingText { text, .. } if text == "abc")
                {
                    saw_delta = true;
                    break;
                }
            }
        }
        assert!(
            saw_stream && saw_delta,
            "each feed must receive coalesced StreamingText"
        );
    }

    // A durable Boundary seals Turn 1; later Turn 2 work must stay outside its range.
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
    bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::TextStreamStarted {
            attempt_id: "att-2".into(),
            item_id: "item-2".into(),
            generation: 0,
        },
    ));
    bus.admit_and_broadcast(vec![make_text_event(
        "ans-t1",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "turn 1 done",
        "turn-1",
        &db_id,
    )?])
    .await?;

    let wg = loop {
        match tokio::time::timeout(Duration::from_secs(2), feed1.next_event()).await? {
            Some(ConversationEvent::Timeline(TimelinePatch::Append { mut items })) => {
                break items.remove(0);
            }
            Some(ConversationEvent::LiveStatus(_)) => {}
            other => panic!("expected Append WorkGroup, got {other:?}"),
        }
    };

    // Append Turn 2 work after the sealing Boundary.
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
    assert!(
        matches!(&members[0], WorkGroupMember::ToolCall { call_id, .. } if call_id == "call-t1")
    );

    // Seal Turn 2 before reopening in the middle of the next group.
    let ans1 = make_text_event(
        "ans-t2",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "turn 2 done",
        "turn-2",
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
    bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::ReasoningDelta {
            attempt_id: "att-3".into(),
            item_id: "reason-3".into(),
            generation: 0,
            text: "thinking".into(),
            replace: false,
            is_summary: false,
        },
    ));
    // Wait until LiveStatus becomes Working before opening feed3.
    loop {
        if matches!(
            bus.live_status().snapshot().phase,
            LiveStatusPhase::Working { .. }
        ) {
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
        reset3
            .iter()
            .all(|item| item.id() != format!("work:{w_t3_seq}")),
        "mid-turn open must keep trailing w_t3 in pending_work: {reset3:?}"
    );
    assert!(w_t2_seq < w_t3_seq);
    // Pre-open and post-open work must form one group when a Boundary arrives.
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
    bus.emit(pl_core::thread::CoreEvent::Live(
        CoreLiveEvent::TextStreamStarted {
            attempt_id: "att-3".into(),
            item_id: "item-3".into(),
            generation: 0,
        },
    ));
    bus.admit_and_broadcast(vec![make_text_event(
        "ans-t3",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "turn 3 done",
        "turn-3",
        &db_id,
    )?])
    .await?;
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
        matches!(
            sealed_mid,
            TimelineItem::WorkGroup {
                member_count: 2,
                ..
            }
        ),
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
    let prior_reply = make_text_event(
        "reply-old",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "old reply",
        "turn-old",
        &db_id,
    )?;
    prior_bus
        .admit_and_broadcast(vec![prior_input, prior_reply])
        .await?;
    store.flush().await?;
    prior_bus.close().await;

    // Open ConversationFeed while no bus is active (bus_tx = None).
    let (bus_tx, bus_rx) = tokio::sync::watch::channel(None);
    let feed = ConversationFeed::open(
        "thread-cold-live",
        HistoryStore::open_reader(&db_path, "thread-cold-live", HistoryLimits::default()).await?,
        bus_rx,
        SessionMetaLayer::empty("thread-cold-live").snapshot(),
        1,
    )
    .await?;

    let Some(ConversationEvent::Timeline(TimelinePatch::Reset {
        items,
        older_cursor,
        ..
    })) = feed.next_event().await
    else {
        panic!("cold feed should open with a reset");
    };
    assert_eq!(items.len(), 1);
    let older_cursor = older_cursor.expect("cold cut must have an older page");
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
    let early_seq = live_bus.admit_and_broadcast(vec![early_user]).await?[0];
    // A caught-up writer can already have reclaimed the unflushed log. The bus still replays
    // the original in-memory record without reading its persisted equivalent.
    store.flush().await?;
    assert!(store.durable_head() >= early_seq);
    let reads_before_attach = store.read_query_count();
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
    assert_eq!(store.read_query_count(), reads_before_attach);

    let paused_flush = store.pause_flush().await;
    let work = make_tool_event(
        "live-tool-completed",
        "new-call",
        "shell",
        HistoryEventKind::ToolCompleted,
        "{}",
        Some("result"),
        "turn-new",
        &db_id,
    )?;
    let long_reply = "pending long reply ".repeat(4096);
    let reply = make_text_event(
        "reply-new",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        &long_reply,
        "turn-new",
        &db_id,
    )?;
    let sequences = live_bus.admit_and_broadcast(vec![work, reply]).await?;
    let (members, body_ref) = loop {
        let event = tokio::time::timeout(Duration::from_secs(2), feed.next_event())
            .await?
            .ok_or_else(|| anyhow::anyhow!("feed closed before the new work group"))?;
        if let ConversationEvent::Timeline(TimelinePatch::Append { items }) = event
            && let Some(TimelineItem::WorkGroup {
                after_boundary_seq,
                before_boundary_seq,
                ..
            }) = items.first()
        {
            let members = feed
                .load_work_group_members(*after_boundary_seq, *before_boundary_seq)
                .await?;
            let Some(TimelineItem::AssistantText {
                body_ref: Some(reference),
                ..
            }) = items.get(1)
            else {
                panic!("new long reply must expose its body reference");
            };
            break (members, reference.clone());
        }
    };
    assert!(store.durable_head() < sequences[0]);
    assert!(
        matches!(members.as_slice(), [WorkGroupMember::ToolCall { call_id, .. }] if call_id == "new-call")
    );
    assert!(body_ref.inline_text.is_none());
    let offset = 65_536;
    let window = feed.read_body_window(&body_ref, offset, 4096).await?;
    assert_eq!(window.offset, offset);
    assert_eq!(window.total_bytes, long_reply.len() as u64);
    assert_eq!(
        window.text.as_deref(),
        Some(&long_reply[offset as usize..offset as usize + 4096])
    );
    assert!(!window.eof);
    assert!(store.durable_head() < sequences[0]);
    assert!(matches!(
        feed.load_older(older_cursor, 4).await?,
        TimelinePatch::PrependOlder { items, .. } if items.iter().any(|item|
            matches!(item, TimelineItem::UserMessage { text, .. } if text == "hello"))
    ));
    drop(paused_flush);

    bus_tx.send(None)?;
    let idle_revision = loop {
        if let Some(ConversationEvent::LiveStatus(snapshot)) =
            tokio::time::timeout(Duration::from_secs(2), feed.next_event()).await?
            && snapshot.phase == LiveStatusPhase::Idle
        {
            break snapshot.revision;
        }
    };
    let restarted_bus = MetaEventBus::open(
        test_thread("thread-cold-live"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    bus_tx.send(Some(restarted_bus.clone()))?;
    restarted_bus.emit(CoreEvent::Live(CoreLiveEvent::TextStreamStarted {
        attempt_id: "att-restarted".into(),
        item_id: "item-restarted".into(),
        generation: 0,
    }));
    loop {
        if let Some(ConversationEvent::LiveStatus(snapshot)) =
            tokio::time::timeout(Duration::from_secs(2), feed.next_event()).await?
            && matches!(snapshot.phase, LiveStatusPhase::StreamingText { item_id, .. } if item_id == "item-restarted")
        {
            assert!(snapshot.revision > idle_revision);
            break;
        }
    }

    feed.close().await;
    restarted_bus.close().await;
    live_bus.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn leading_work_before_first_boundary_is_materialized_with_no_more_older() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("history.sqlite");
    let store =
        HistoryStore::open(&db_path, "thread-leading-work", HistoryLimits::default()).await?;
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
async fn idle_and_restarted_tail_waits_for_boundary_with_or_without_prior_boundary() -> Result<()> {
    for prior_boundary in [false, true] {
        let temp = tempfile::tempdir()?;
        let db_path = temp.path().join("history.sqlite");
        let store = HistoryStore::open(&db_path, "tail", HistoryLimits::default()).await?;
        let db_id = store.database_id().to_owned();
        let paused_flush = store.pause_flush().await;
        if prior_boundary {
            store
                .accept_in_memory(&[make_text_event(
                    "input",
                    HistoryEventKind::InputAccepted,
                    HistoryTimelineRole::Boundary,
                    HistoryEntityKind::Input,
                    Some(ThreadTextChannel::User),
                    "begin",
                    "turn-1",
                    &db_id,
                )?])
                .await?;
        }
        let first_work = store
            .accept_in_memory(&[
                make_tool_event(
                    "w1",
                    "call-1",
                    "shell",
                    HistoryEventKind::ToolCompleted,
                    "{}",
                    Some("one"),
                    "turn-1",
                    &db_id,
                )?,
                HistoryEvent::new(
                    "ended",
                    HistoryEventKind::TurnEnded,
                    HistoryTimelineRole::Hidden,
                    1_000_200,
                ),
            ])
            .await?[0];

        let mut layers = Vec::new();
        let mut expected_initial = None;
        for working in [false, true] {
            let mut layer = super::timeline_layer::TimelineDataLayer::new();
            let items = match layer.load_initial_page(&store.reader(), 1, working).await? {
                TimelinePatch::Reset {
                    items,
                    has_more_older: false,
                    older_cursor: None,
                    ..
                } => items,
                other => panic!("unexpected tail page: {other:?}"),
            };
            assert_eq!(
                items.len(),
                usize::from(prior_boundary),
                "tail must stay pending"
            );
            if let Some(expected) = &expected_initial {
                assert_eq!(&items, expected, "live status must not change timeline");
            } else {
                expected_initial = Some(items);
            }
            layers.push(layer);
        }
        assert_eq!(store.durable_head(), 0);
        drop(paused_flush);
        store.close().await?;

        let reopened = HistoryStore::open(&db_path, "tail", HistoryLimits::default()).await?;
        let mut cold = super::timeline_layer::TimelineDataLayer::new();
        match cold.load_initial_page(&reopened.reader(), 1, false).await? {
            TimelinePatch::Reset { items, .. } => assert_eq!(Some(items), expected_initial),
            other => panic!("expected cold Reset, got {other:?}"),
        }
        layers.push(cold);

        let mut work = make_tool_event(
            "w2",
            "call-2",
            "shell",
            HistoryEventKind::ToolCompleted,
            "{}",
            Some("two"),
            "turn-2",
            &db_id,
        )?;
        let mut boundary = make_text_event(
            "text",
            HistoryEventKind::TextCompleted,
            HistoryTimelineRole::Boundary,
            HistoryEntityKind::Text,
            Some(ThreadTextChannel::Final),
            "done",
            "turn-2",
            &db_id,
        )?;
        let seqs = reopened
            .accept_in_memory(&[work.clone(), boundary.clone()])
            .await?;
        work.seq = seqs[0];
        boundary.seq = seqs[1];
        let mut expected_append = None;
        for mut layer in layers {
            assert!(layer.on_history_record(&work.to_record(), None).is_empty());
            let appended = layer.on_history_record(&boundary.to_record(), None);
            match &appended[..] {
                [ConversationEvent::Timeline(TimelinePatch::Append { items })] => {
                    assert_eq!(items.len(), 2);
                    assert!(matches!(&items[0], TimelineItem::WorkGroup {
                        id, member_count: 2, after_boundary_seq, before_boundary_seq, ..
                    } if id == &format!("work:{first_work}")
                        && *after_boundary_seq == prior_boundary.then_some(1)
                        && *before_boundary_seq == Some(boundary.seq)));
                }
                other => panic!("expected group plus Boundary, got {other:?}"),
            }
            if let Some(expected) = &expected_append {
                assert_eq!(&appended, expected);
            } else {
                expected_append = Some(appended);
            }
        }
        reopened.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn live_work_ignores_hidden_events_until_boundary() -> Result<()> {
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

    let mut ended = HistoryEvent::new(
        "ended",
        HistoryEventKind::TurnEnded,
        HistoryTimelineRole::Hidden,
        1_000_200,
    );
    ended.seq = 11;
    assert!(layer.on_history_record(&ended.to_record(), None).is_empty());

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
                    id,
                    member_count,
                    after_boundary_seq,
                    before_boundary_seq,
                    ..
                } => {
                    assert_eq!(id, "work:10");
                    assert_eq!(*member_count, 2);
                    assert_eq!(*after_boundary_seq, None);
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
async fn live_status_coalesces_reasoning_deltas_and_preserves_tool_progress_summary() -> Result<()>
{
    let layer = LiveStatusDataLayer::new();

    // First reasoning delta transitions Idle -> Working immediately.
    let first = layer.on_live_event(&CoreLiveEvent::ReasoningDelta {
        attempt_id: "att-r".into(),
        item_id: "item-r".into(),
        text: "Step 1".into(),
        replace: false,
        generation: 0,
        is_summary: false,
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
                is_summary: false,
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

    // ToolProgress updates result_preview only and never overwrites arguments/tool_name across ToolCompleted.
    let _ = layer.on_live_event(&CoreLiveEvent::ToolProgress {
        task_id: "task-x".into(),
        call_id: "call-x".into(),
        tool_id: "shell".into(),
        progress: pl_core::model::ToolProgress::default().applied(
            &pl_core::model::ToolProgressUpdate::replace("stdout", "running cargo test"),
        ),
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
            assert_eq!(items.len(), 2);
            assert!(matches!(&items[0], WorkGroupMember::Reasoning { .. }));
            assert!(matches!(
                &items[1],
                WorkGroupMember::ToolCall {
                    tool_name,
                    status,
                    arguments: Some(args),
                    result_preview: Some(res),
                    ..
                } if tool_name == "shell" && status == "succeeded" && args.contains("cargo test") && res == "ok"
            ));
        }
        other => panic!("expected Working phase, got {other:?}"),
    }

    Ok(())
}

#[tokio::test]
async fn live_status_state_machine_stopping_summary_boundary_and_stray_guard() -> Result<()> {
    use pl_core::thread::{ActiveExecution, ExecutionPhase};

    let layer = LiveStatusDataLayer::new();

    // Stray terminal Work event while Idle must NOT wake Working.
    let mut stray = make_tool_event(
        "ev-stray",
        "call-stray",
        "shell",
        HistoryEventKind::ToolCompleted,
        r#"{"command":"pwd"}"#,
        Some("ok"),
        "turn-0",
        "db-0",
    )?;
    stray.seq = 1;
    assert!(layer.on_history_record(&stray.to_record()).is_none());
    assert!(matches!(layer.snapshot().phase, LiveStatusPhase::Idle));

    // RunActivity(Preparing) transitions Idle -> Working immediately with empty container.
    let prep = layer
        .on_live_event(&CoreLiveEvent::RunActivity {
            execution: Some(ActiveExecution {
                id: "exec-1".into(),
                phase: ExecutionPhase::Preparing,
                turn_id: Some("turn-1".into()),
            }),
        })
        .unwrap();
    assert!(matches!(
        prep.phase,
        LiveStatusPhase::Working { ref items, .. } if items.is_empty()
    ));

    // Unmatched ToolCompleted while active appends completed item directly.
    let mut unmatched = make_tool_event(
        "ev-unmatched",
        "call-u",
        "read_file",
        HistoryEventKind::ToolCompleted,
        r#"{"path":"src/main.rs"}"#,
        Some("content"),
        "turn-1",
        "db-1",
    )?;
    unmatched.seq = 2;
    let snap = layer.on_history_record(&unmatched.to_record()).unwrap();
    match snap.phase {
        LiveStatusPhase::Working { items, .. } => {
            assert_eq!(items.len(), 1);
            assert!(matches!(
                &items[0],
                WorkGroupMember::ToolCall {
                    tool_name,
                    status,
                    finished_at_ms: Some(_),
                    ..
                } if tool_name == "read_file" && status == "succeeded"
            ));
        }
        other => panic!("expected Working, got {other:?}"),
    }

    // ReasoningDelta with is_summary=true takes precedence over body deltas in reasoning_preview.
    let _ = layer.on_live_event(&CoreLiveEvent::ReasoningDelta {
        attempt_id: "a1".into(),
        item_id: "r-sum".into(),
        text: "raw chain of thought".into(),
        replace: false,
        generation: 0,
        is_summary: false,
    });
    let _ = layer.on_live_event(&CoreLiveEvent::ReasoningDelta {
        attempt_id: "a1".into(),
        item_id: "r-sum".into(),
        text: "总结摘要".into(),
        replace: false,
        generation: 0,
        is_summary: true,
    });
    let flushed = layer.flush_coalesced().unwrap();
    assert!(matches!(
        &flushed.phase,
        LiveStatusPhase::Working {
            reasoning_preview: Some(preview),
            ..
        } if preview == "总结摘要"
    ));

    // Boundary clears previous working items without waiting for unfinished tools.
    let mut boundary = make_text_event(
        "ev-b1",
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Boundary,
        HistoryEntityKind::Text,
        Some(ThreadTextChannel::Final),
        "done text",
        "turn-1",
        "db-1",
    )?;
    boundary.seq = 3;
    let after_boundary = layer.on_history_record(&boundary.to_record()).unwrap();
    assert!(matches!(
        after_boundary.phase,
        LiveStatusPhase::Working { ref items, ref reasoning_preview, .. }
        if items.is_empty() && reasoning_preview.is_none()
    ));

    // Stopping latches until RunActivity(None) arrives.
    let stopping = layer
        .on_live_event(&CoreLiveEvent::RunActivity {
            execution: Some(ActiveExecution {
                id: "exec-1".into(),
                phase: ExecutionPhase::Stopping,
                turn_id: Some("turn-1".into()),
            }),
        })
        .unwrap();
    assert!(matches!(stopping.phase, LiveStatusPhase::Stopping { .. }));

    // Deltas while Stopping are ignored.
    assert!(
        layer
            .on_live_event(&CoreLiveEvent::TextStreamStarted {
                attempt_id: "a1".into(),
                item_id: "t-late".into(),
                generation: 0,
            })
            .is_none()
    );
    assert!(matches!(
        layer.snapshot().phase,
        LiveStatusPhase::Stopping { .. }
    ));

    // RunActivity(None) resets Stopping -> Idle.
    let idle = layer
        .on_live_event(&CoreLiveEvent::RunActivity { execution: None })
        .unwrap();
    assert!(matches!(idle.phase, LiveStatusPhase::Idle));

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
    bus.sink()
        .emit(pl_core::thread::CoreEvent::Durable(std::sync::Arc::new(
            pl_core::thread::CoreCommitEvent {
                thread_id: "child-1".into(),
                sequence: 1,
                export,
            },
        )));
    bus.wait_admitted_commit(1).await?;

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

#[tokio::test]
async fn meta_bus_broadcasts_only_records_newly_admitted_from_mixed_replays() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "mixed-replay", HistoryLimits::default()).await?;
    let event = |id: &str| {
        HistoryEvent::new(
            id,
            HistoryEventKind::RunStarted,
            HistoryTimelineRole::Hidden,
            1,
        )
    };
    store.accept_batch(&[event("seen")]).await?;
    store.flush().await?;
    store.close().await?;
    let store = HistoryStore::open(&path, "mixed-replay", HistoryLimits::default()).await?;
    let bus = MetaEventBus::open(
        test_thread("mixed-replay"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    let mut rx = bus.subscribe();
    let reads = store.read_query_count();
    let mut replay = event("seen");
    replay.payload_json = r#"{"ignored":true}"#.into();
    assert_eq!(
        bus.admit_and_broadcast(vec![event("new-a"), replay, event("new-b")])
            .await?,
        [2, 3]
    );
    let mut ids = Vec::new();
    while let Ok(meta) = rx.try_recv() {
        if let super::meta_bus::ThreadMetaEvent::History { record, .. } = meta {
            ids.push(record.event_id.clone());
        }
    }
    assert_eq!(ids, ["new-a", "new-b"]);
    assert_eq!(store.read_query_count(), reads);
    bus.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn meta_bus_capacity_failure_is_not_acknowledged_and_same_commit_can_retry() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("history.sqlite"),
        "admit-failure",
        HistoryLimits {
            pending_events: 1,
            pending_bytes: 64 * 1024,
        },
    )
    .await?;
    let paused = store.pause_flush().await;
    store
        .accept_batch(&[HistoryEvent::new(
            "fill",
            HistoryEventKind::RunStarted,
            HistoryTimelineRole::Hidden,
            1,
        )])
        .await?;
    let bus = MetaEventBus::open(
        test_thread("admit-failure"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );
    let commit = std::sync::Arc::new(pl_core::thread::CoreCommitEvent {
        thread_id: "admit-failure".into(),
        sequence: 1,
        export: std::sync::Arc::new(pl_core::thread::HistoryExport {
            effect: std::sync::Arc::new(pl_core::thread::ThreadEffectBatch {
                thread_id: "admit-failure".into(),
                sequence: 1,
                committed_at: 1_000,
                ..Default::default()
            }),
            state: Default::default(),
            output_claim: None,
        }),
    });
    let mut rx = bus.subscribe();
    let reads = store.read_query_count();
    bus.emit_core_event(pl_core::thread::CoreEvent::Durable(commit.clone()));
    let error = tokio::time::timeout(Duration::from_secs(2), bus.wait_admitted_commit(1))
        .await?
        .expect_err("capacity failure must not be acknowledged");
    assert!(format!("{error:#}").contains("history pending capacity reached"));
    assert_eq!(store.current_head(), 1);
    assert!(rx.try_recv().is_err());
    assert!(
        tokio::time::timeout(Duration::from_secs(2), bus.flush_through_commit(1))
            .await?
            .is_err()
    );
    drop(paused);
    store.flush().await?;
    bus.emit_core_event(pl_core::thread::CoreEvent::Durable(commit));
    let admitted = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if let super::meta_bus::ThreadMetaEvent::History { record, .. } = rx.recv().await? {
                break Ok::<_, anyhow::Error>(record);
            }
        }
    })
    .await??;
    assert_eq!(admitted.seq, 2);
    assert_eq!(admitted.kind, HistoryEventKind::RunStarted);
    bus.wait_admitted_commit(1).await?;
    assert_eq!(store.read_query_count(), reads);
    bus.close().await;
    assert!(bus.wait_admitted_commit(2).await.is_err());
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn meta_bus_records_hidden_input_lifecycle_and_step_preemption_events() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("meta-events.sqlite");
    let store = HistoryStore::open(&db_path, "meta-events", HistoryLimits::default()).await?;
    let bus = MetaEventBus::open(
        test_thread("meta-events"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );

    let make_hidden_input = |id: &str,
                             ordinal: u64,
                             revision: u64,
                             state: pl_core::thread::input::InputState|
     -> Result<pl_core::thread::input::InputRecord> {
        Ok(pl_core::thread::input::InputRecord {
            accepted_sequence: 1,
            input: pl_core::thread::input::ThreadInput {
                id: id.into(),
                purpose: pl_core::thread::input::InputPurpose::Message,
                payload: pl_core::context::OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    r#"{"text":"hidden","presentation":"hidden","attachments":[]}"#,
                )?,
                context: vec![pl_core::context::ContextContent::Text {
                    text: "hidden".into(),
                }],
            },
            ordinal,
            revision,
            state,
        })
    };
    let consumed_state = pl_core::thread::input::InputState::Consumed {
        turn_id: "turn-1".into(),
        attempt_id: "att-1".into(),
    };
    let discarded_state = pl_core::thread::input::InputState::Discarded;
    let state = pl_core::thread::ThreadSnapshot {
        inputs: std::sync::Arc::from([
            make_hidden_input("in-1", 1, 2, consumed_state.clone())?,
            make_hidden_input("in-2", 2, 3, discarded_state.clone())?,
        ]),
        ..Default::default()
    };
    let inputs = std::sync::Arc::from([
        pl_core::thread::input::InputChange::Transition {
            id: "in-1".into(),
            ordinal: 1,
            revision: 2,
            state: consumed_state,
            context_record_id: Some("input:in-1".into()),
            injected_mid_turn: true,
        },
        pl_core::thread::input::InputChange::Transition {
            id: "in-2".into(),
            ordinal: 2,
            revision: 3,
            state: discarded_state,
            context_record_id: None,
            injected_mid_turn: false,
        },
    ]);
    let step_preemptions = std::sync::Arc::from([pl_core::thread::StepPreemptionEvent {
        seq: 1,
        turn_id: "turn-1".into(),
        attempt_id: Some("att-1".into()),
        phase: pl_core::thread::PreemptedStepPhase::Streaming,
        trigger_input_ids: vec!["in-3".into()],
        partial_record_id: Some("att-1:partial".into()),
    }]);

    let commit = std::sync::Arc::new(pl_core::thread::CoreCommitEvent {
        thread_id: "meta-events".into(),
        sequence: 1,
        export: std::sync::Arc::new(pl_core::thread::HistoryExport {
            effect: std::sync::Arc::new(pl_core::thread::ThreadEffectBatch {
                thread_id: "meta-events".into(),
                sequence: 1,
                committed_at: 1_000,
                inputs,
                step_preemptions,
                ..Default::default()
            }),
            state,
            output_claim: None,
        }),
    });
    bus.sink().emit(pl_core::thread::CoreEvent::Durable(commit));
    bus.wait_admitted_commit(1).await?;

    let reader = store.reader();
    let (_, originals, _) = reader
        .events_window(
            crate::history::HistoryEventsQuery::AllEvents,
            None,
            None,
            true,
            crate::history::HistoryDemand::default(),
        )
        .await?;

    let consumed = originals
        .iter()
        .find(|ev| ev.kind == HistoryEventKind::InputConsumed)
        .expect("InputConsumed meta event should be recorded");
    assert_eq!(consumed.timeline_role, HistoryTimelineRole::Hidden);
    let consumed_json: serde_json::Value = serde_json::from_str(&consumed.payload_json)?;
    assert_eq!(consumed_json["factType"], "input_consumed");
    assert_eq!(consumed_json["inputId"], "in-1");
    assert_eq!(consumed_json["contextRecordId"], "input:in-1");
    assert_eq!(consumed_json["injectedMidTurn"], true);

    let discarded = originals
        .iter()
        .find(|ev| ev.kind == HistoryEventKind::InputDiscarded)
        .expect("InputDiscarded meta event should be recorded");
    assert_eq!(discarded.timeline_role, HistoryTimelineRole::Hidden);
    let discarded_json: serde_json::Value = serde_json::from_str(&discarded.payload_json)?;
    assert_eq!(discarded_json["factType"], "input_discarded");
    assert_eq!(discarded_json["inputId"], "in-2");

    let preempted = originals
        .iter()
        .find(|ev| ev.kind == HistoryEventKind::StepPreempted)
        .expect("StepPreempted meta event should be recorded");
    assert_eq!(preempted.timeline_role, HistoryTimelineRole::Hidden);
    let preempted_json: serde_json::Value = serde_json::from_str(&preempted.payload_json)?;
    assert_eq!(preempted_json["factType"], "step_preempted");
    assert_eq!(preempted_json["attemptId"], "att-1");
    assert_eq!(preempted_json["phase"], "streaming");
    assert_eq!(
        preempted_json["triggerInputIds"],
        serde_json::json!(["in-3"])
    );
    assert_eq!(preempted_json["partialRecordId"], "att-1:partial");

    let mut layer = super::timeline_layer::TimelineDataLayer::new();
    match layer.load_initial_page(&reader, 10, false).await? {
        TimelinePatch::Reset { items, .. } => assert!(items.is_empty()),
        other => panic!("hidden meta events must not render visible items: {other:?}"),
    }

    bus.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn meta_bus_streaming_soft_preemption_keeps_partial_text_and_suppresses_interrupted_receipt()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let db_path = temp.path().join("soft-preempt.sqlite");
    let store = HistoryStore::open(&db_path, "soft-preempt", HistoryLimits::default()).await?;
    let bus = MetaEventBus::open(
        test_thread("soft-preempt"),
        store.clone(),
        pl_core::thread::current::RuntimeEpoch::new(),
    );

    let attempt_update = pl_core::thread::journal::AttemptUpdate {
        request_metadata: None,
        usage_binding: None,
        tool_projection: None,
        turn_id: "turn-1".into(),
        attempt_id: "att-1".into(),
        retry_of: None,
        input_revision: 1,
        tools: std::sync::Arc::from([]),
        outcome: pl_core::thread::AttemptOutcome::Cancelled {
            result: Err(std::sync::Arc::new(pl_core::model::ModelError {
                kind: pl_core::model::ModelFailureKind::Cancelled,
                context_recovery: None,
                source: None,
                details: None,
                usage: Box::default(),
            })),
        },
        input_estimate: None,
    };
    let partial_record = pl_core::context::ContextRecord {
        id: "att-1:partial".into(),
        turn_id: Some("turn-1".into()),
        source: pl_core::context::ContextSource::Assistant,
        content: vec![pl_core::context::ContextContent::Text {
            text: "partial work".into(),
        }],
        tool_calls: Vec::new(),
    };
    let preemptions = std::sync::Arc::from([pl_core::thread::StepPreemptionEvent {
        seq: 1,
        turn_id: "turn-1".into(),
        attempt_id: Some("att-1".into()),
        phase: pl_core::thread::PreemptedStepPhase::Streaming,
        trigger_input_ids: vec!["in-2".into()],
        partial_record_id: Some("att-1:partial".into()),
    }]);

    let state = pl_core::thread::ThreadSnapshot {
        context: pl_core::context::ContextSnapshot {
            revision: 1,
            records: std::sync::Arc::from([partial_record.clone()]),
        },
        ..Default::default()
    };
    let effect = pl_core::thread::ThreadEffectBatch {
        thread_id: "soft-preempt".into(),
        sequence: 1,
        committed_at: 1_000,
        context: Some(pl_core::thread::journal::ContextChange::Append {
            revision: 1,
            records: std::sync::Arc::from([partial_record]),
        }),
        attempt: Some(attempt_update),
        step_preemptions: preemptions,
        ..Default::default()
    };
    let commit = std::sync::Arc::new(pl_core::thread::CoreCommitEvent {
        thread_id: "soft-preempt".into(),
        sequence: 1,
        export: std::sync::Arc::new(pl_core::thread::HistoryExport {
            effect: std::sync::Arc::new(effect),
            state,
            output_claim: None,
        }),
    });
    bus.sink().emit(pl_core::thread::CoreEvent::Durable(commit));
    bus.wait_admitted_commit(1).await?;

    let (_, originals, _) = store
        .reader()
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
    assert!(
        !originals
            .iter()
            .any(|ev| ev.kind == HistoryEventKind::TurnReceiptRecorded),
        "soft preemption must not emit interrupted TurnReceiptRecorded"
    );
    assert!(
        originals.iter().any(|ev| {
            ev.kind == HistoryEventKind::TextCompleted
                && ev.timeline_role == HistoryTimelineRole::Boundary
        }),
        "partial assistant text should be preserved as Boundary TextCompleted"
    );

    let mut hot = super::timeline_layer::TimelineDataLayer::new();
    let hot_items = match hot.load_initial_page(&store.reader(), 10, true).await? {
        TimelinePatch::Reset { items, .. } => items,
        other => panic!("expected hot Reset, got {other:?}"),
    };
    assert!(
        hot_items.iter().any(|item| matches!(
            item,
            TimelineItem::AssistantText {
                channel,
                outcome,
                is_final_turn_delivery: false,
                text,
                ..
            } if channel == "commentary" && outcome == "completed" && text == "partial work"
        )),
        "expected completed non-final partial commentary item, got {hot_items:?}"
    );

    store.flush().await?;
    bus.close().await;
    store.close().await?;

    let reopened = HistoryStore::open(&db_path, "soft-preempt", HistoryLimits::default()).await?;
    let mut cold = super::timeline_layer::TimelineDataLayer::new();
    let cold_items = match cold
        .load_initial_page(&reopened.reader(), 10, false)
        .await?
    {
        TimelinePatch::Reset { items, .. } => items,
        other => panic!("expected cold Reset, got {other:?}"),
    };
    assert_eq!(hot_items, cold_items);
    reopened.close().await?;
    Ok(())
}

#[test]
fn live_status_resets_streaming_text_to_working_on_step_preempted() {
    let layer = LiveStatusDataLayer::new();
    assert!(
        layer
            .on_live_event(&CoreLiveEvent::ReasoningDelta {
                attempt_id: "att-1".into(),
                item_id: "reason-1".into(),
                generation: 0,
                text: "old reasoning summary".into(),
                replace: false,
                is_summary: true,
            })
            .is_some()
    );
    assert!(
        layer
            .on_live_event(&CoreLiveEvent::TextStreamStarted {
                attempt_id: "att-1".into(),
                item_id: "item-1".into(),
                generation: 0,
            })
            .is_some()
    );
    assert!(
        layer
            .on_live_event(&CoreLiveEvent::TextStreamDelta {
                attempt_id: "att-1".into(),
                item_id: "item-1".into(),
                generation: 0,
                text: "partial delta".into(),
                replace: false,
            })
            .is_none()
    );

    let mut record = crate::protocol::history::HistoryEventRecord {
        seq: 1,
        event_id: "step-preempted:1".into(),
        kind: HistoryEventKind::StepPreempted,
        timeline_role: HistoryTimelineRole::Hidden,
        occurred_at: Some(2_000),
        recorded_at: 2_000,
        run_id: Some("run-1".into()),
        turn_id: Some("turn-1".into()),
        attempt_id: Some("att-1".into()),
        call_id: None,
        entity_id: Some("att-1".into()),
        message_id: None,
        tool_name: None,
        source: None,
        original: None,
        row_scope: None,
        row_key: None,
        payload_schema: "anywork.business/1".into(),
        payload_json: "{}".into(),
    };
    let snapshot = layer
        .on_history_record(&record)
        .expect("StepPreempted should immediately transition StreamingText -> Working");
    assert!(matches!(
        &snapshot.phase,
        LiveStatusPhase::Working {
            items,
            reasoning_preview: None,
            ..
        } if items.is_empty()
    ));
    assert!(
        layer.flush_coalesced().is_none(),
        "stale buffered stream_text must not re-emit StreamingText after preemption"
    );

    let stopping = layer
        .on_live_event(&CoreLiveEvent::RunActivity {
            execution: Some(pl_core::thread::ActiveExecution {
                id: "exec-1".into(),
                phase: pl_core::thread::ExecutionPhase::Stopping,
                turn_id: Some("turn-1".into()),
            }),
        })
        .expect("RunActivity(Stopping) should latch Stopping");
    assert!(matches!(stopping.phase, LiveStatusPhase::Stopping { .. }));
    assert!(
        layer.on_history_record(&record).is_none(),
        "StepPreempted must be ignored while Stopping is latched"
    );

    record.kind = HistoryEventKind::TurnEnded;
    let idle = layer
        .on_history_record(&record)
        .expect("TurnEnded should transition Stopping -> Idle");
    assert!(matches!(idle.phase, LiveStatusPhase::Idle));
}

#[test]
fn live_status_reasoning_deltas_across_attempts_and_items_stay_isolated() {
    let layer = LiveStatusDataLayer::new();

    let first = layer
        .on_live_event(&CoreLiveEvent::ReasoningDelta {
            attempt_id: "att-1".into(),
            item_id: "rs-1".into(),
            generation: 0,
            text: "**First thought**".into(),
            replace: false,
            is_summary: true,
        })
        .unwrap();
    assert!(matches!(
        &first.phase,
        LiveStatusPhase::Working {
            reasoning_preview: Some(p),
            items,
            ..
        } if p == "**First thought**" && items.len() == 1
    ));

    assert!(
        layer
            .on_live_event(&CoreLiveEvent::ReasoningDelta {
                attempt_id: "att-2".into(),
                item_id: "rs-1".into(),
                generation: 0,
                text: "**Second thought**".into(),
                replace: false,
                is_summary: true,
            })
            .is_none()
    );
    let flushed = layer.flush_coalesced().unwrap();
    match flushed.phase {
        LiveStatusPhase::Working {
            items,
            reasoning_preview,
            ..
        } => {
            assert_eq!(reasoning_preview.as_deref(), Some("**Second thought**"));
            assert_eq!(items.len(), 2);
            assert!(matches!(
                &items[0],
                WorkGroupMember::Reasoning { summary, .. } if summary == "**First thought**"
            ));
            assert!(matches!(
                &items[1],
                WorkGroupMember::Reasoning { summary, .. } if summary == "**Second thought**"
            ));
        }
        other => panic!("expected Working, got {other:?}"),
    }
}

#[test]
fn latest_reasoning_summary_preview_extracts_latest_bold_segment_and_truncates_right() {
    use super::latest_reasoning_summary_preview;

    assert_eq!(
        latest_reasoning_summary_preview("**A****B****C**").as_deref(),
        Some("**C**")
    );
    assert_eq!(
        latest_reasoning_summary_preview("...**A** body **B**").as_deref(),
        Some("**B**")
    );
    assert_eq!(
        latest_reasoning_summary_preview("**A****B").as_deref(),
        Some("**B")
    );
    assert_eq!(
        latest_reasoning_summary_preview("**First**\n\n**Second** detail").as_deref(),
        Some("**Second** detail")
    );

    let long = format!("**{}", "x".repeat(300));
    let preview = latest_reasoning_summary_preview(&long).unwrap();
    assert!(preview.chars().count() <= 240);
    assert!(preview.starts_with("**"));
    assert!(preview.ends_with("…**"));
    assert_eq!(preview.matches("**").count() % 2, 0);
}

#[test]
fn live_status_reasoning_completed_matches_fifo_and_refreshes_preview() -> Result<()> {
    let layer = LiveStatusDataLayer::new();

    let _ = layer.on_live_event(&CoreLiveEvent::ReasoningDelta {
        attempt_id: "att-1".into(),
        item_id: "r-1".into(),
        generation: 0,
        text: "**First streaming**".into(),
        replace: false,
        is_summary: true,
    });
    let _ = layer.on_live_event(&CoreLiveEvent::ReasoningDelta {
        attempt_id: "att-1".into(),
        item_id: "r-2".into(),
        generation: 0,
        text: "**Second streaming**".into(),
        replace: false,
        is_summary: true,
    });

    let mut done_1 = make_text_event(
        "ev-r1",
        HistoryEventKind::ReasoningCompleted,
        HistoryTimelineRole::Work,
        HistoryEntityKind::Reasoning,
        None,
        "First full reasoning",
        "turn-1",
        "db-1",
    )?;
    done_1.seq = 10;
    let snap_1 = layer.on_history_record(&done_1.to_record()).unwrap();
    match snap_1.phase {
        LiveStatusPhase::Working {
            items,
            reasoning_preview,
            ..
        } => {
            assert_eq!(items.len(), 2);
            // FIFO: first item settled first, second remains running and drives preview.
            assert!(matches!(
                &items[0],
                WorkGroupMember::Reasoning { id, outcome, .. } if id == "ev-r1" && outcome == "completed"
            ));
            assert!(matches!(
                &items[1],
                WorkGroupMember::Reasoning { outcome, summary, .. } if outcome == "running" && summary == "**Second streaming**"
            ));
            assert_eq!(reasoning_preview.as_deref(), Some("**Second streaming**"));
        }
        other => panic!("expected Working, got {other:?}"),
    }

    let mut done_2 = make_text_event(
        "ev-r2",
        HistoryEventKind::ReasoningCompleted,
        HistoryTimelineRole::Work,
        HistoryEntityKind::Reasoning,
        None,
        "Second completed summary",
        "turn-1",
        "db-1",
    )?;
    done_2.seq = 11;
    let snap_2 = layer.on_history_record(&done_2.to_record()).unwrap();
    match snap_2.phase {
        LiveStatusPhase::Working {
            items,
            reasoning_preview,
            ..
        } => {
            assert_eq!(items.len(), 2);
            assert!(matches!(
                &items[1],
                WorkGroupMember::Reasoning { id, outcome, .. } if id == "ev-r2" && outcome == "completed"
            ));
            assert_eq!(
                reasoning_preview.as_deref(),
                Some("Second completed summary")
            );
        }
        other => panic!("expected Working, got {other:?}"),
    }

    Ok(())
}

#[test]
fn live_status_tool_progress_preserves_arguments_across_failed_completion() -> Result<()> {
    let layer = LiveStatusDataLayer::new();
    let _ = layer.on_live_event(&CoreLiveEvent::RunActivity {
        execution: Some(pl_core::thread::ActiveExecution {
            id: "exec-1".into(),
            phase: pl_core::thread::ExecutionPhase::Preparing,
            turn_id: Some("turn-1".into()),
        }),
    });

    let mut called = make_tool_event(
        "ev-called",
        "call-sed",
        "exec",
        HistoryEventKind::ToolCalled,
        r#"{"command":"sed -n '1,10p' missing.txt"}"#,
        None,
        "turn-1",
        "db-1",
    )?;
    called.seq = 5;
    let _ = layer.on_history_record(&called.to_record()).unwrap();

    let snap_progress = layer
        .on_live_event(&CoreLiveEvent::ToolProgress {
            task_id: "task-sed".into(),
            call_id: "call-sed".into(),
            tool_id: "exec".into(),
            progress: pl_core::model::ToolProgress::default().applied(
                &pl_core::model::ToolProgressUpdate::replace(
                    "stderr",
                    "[stderr] sed: missing.txt: No such file or directory",
                ),
            ),
        })
        .unwrap();
    match snap_progress.phase {
        LiveStatusPhase::Working { items, .. } => {
            assert!(matches!(
                &items[0],
                WorkGroupMember::ToolCall {
                    tool_name,
                    arguments: Some(args),
                    result_preview: Some(res),
                    ..
                } if tool_name == "exec"
                    && args == r#"{"command":"sed -n '1,10p' missing.txt"}"#
                    && res.contains("[stderr] sed: missing.txt")
            ));
        }
        other => panic!("expected Working, got {other:?}"),
    }

    let mut failed = make_tool_event(
        "ev-failed",
        "call-sed",
        "exec",
        HistoryEventKind::ToolCompleted,
        "",
        Some("exit code 1"),
        "turn-1",
        "db-1",
    )?;
    let mut env: EventPayloadEnvelope = serde_json::from_str(&failed.payload_json)?;
    env.bodies.retain(|b| b.key != "tool.arguments");
    env.meta.state = HistoryEntityState::KnownTerminal {
        outcome: ChatTerminalOutcome::Failed,
    };
    env.data["state"] = serde_json::json!({ "kind": "failed" });
    failed.payload_json = serde_json::to_string(&env)?;
    failed.seq = 6;

    let snap_failed = layer.on_history_record(&failed.to_record()).unwrap();
    match snap_failed.phase {
        LiveStatusPhase::Working { items, .. } => {
            assert!(matches!(
                &items[0],
                WorkGroupMember::ToolCall {
                    status,
                    arguments: Some(args),
                    result_preview: Some(res),
                    ..
                } if status == "failed"
                    && args == r#"{"command":"sed -n '1,10p' missing.txt"}"#
                    && res == "exit code 1"
            ));
        }
        other => panic!("expected Working, got {other:?}"),
    }
    Ok(())
}

#[test]
fn live_status_preserves_structured_agent_file_change_and_skill_members() -> Result<()> {
    let layer = LiveStatusDataLayer::new();
    let _ = layer.on_live_event(&CoreLiveEvent::RunActivity {
        execution: Some(pl_core::thread::ActiveExecution {
            id: "exec-1".into(),
            phase: pl_core::thread::ExecutionPhase::Preparing,
            turn_id: Some("turn-1".into()),
        }),
    });

    let make_work_record = |event_id: &str,
                            seq: u64,
                            kind: HistoryEventKind,
                            entity_id: &str,
                            entity_kind: HistoryEntityKind,
                            item_type: &str,
                            state: HistoryEntityState,
                            data: serde_json::Value|
     -> Result<crate::protocol::history::HistoryEventRecord> {
        let mut ev = HistoryEvent::new(event_id, kind, HistoryTimelineRole::Work, 2_000);
        ev.seq = seq;
        ev.occurred_at = Some(2_000);
        ev.entity_id = Some(entity_id.into());
        let envelope = EventPayloadEnvelope {
            contract: "anywork.event/1".into(),
            item_type: item_type.into(),
            meta: HistoryEventMeta {
                entity_id: entity_id.into(),
                entity_kind,
                delivery: ChatDeliveryKind::Foreground,
                state,
                started_at: Some(2_000),
                finished_at: None,
                text_channel: None,
                model_recovery: None,
                single_visibility: None,
                presentation_contract: None,
                source_order: Some(1),
                content_present: Some(true),
                wait: None,
                tool: None,
            },
            data,
            bodies: Vec::new(),
            source_order: Some(1),
            turn_id: Some("turn-1".into()),
            captured_at: Some(2_000),
        };
        ev.payload_schema = "anywork.event/1".into();
        ev.payload_json = serde_json::to_string(&envelope)?;
        Ok(ev.to_record())
    };

    let spawned = make_work_record(
        "ev-ag-1",
        1,
        HistoryEventKind::AgentSpawned,
        "agent-1",
        HistoryEntityKind::Agent,
        "agent",
        HistoryEntityState::KnownActive {
            status: crate::ChatActiveStatus::Running,
        },
        serde_json::json!({
            "identity": {
                "id": "thread-child-1",
                "role": "rust-backend",
                "taskSummary": "Implement Phase A"
            },
            "outcome": { "kind": "running" }
        }),
    )?;
    let _ = layer.on_history_record(&spawned).unwrap();

    let completed = make_work_record(
        "ev-ag-2",
        2,
        HistoryEventKind::AgentCompleted,
        "agent-1",
        HistoryEntityKind::Agent,
        "agent",
        HistoryEntityState::KnownTerminal {
            outcome: ChatTerminalOutcome::Completed,
        },
        serde_json::json!({
            "identity": {
                "id": "thread-child-1",
                "role": "rust-backend",
                "taskSummary": "Implement Phase A"
            },
            "outcome": { "kind": "succeeded", "data": { "completedAt": 2500, "summary": "Done" } }
        }),
    )?;
    let _ = layer.on_history_record(&completed).unwrap();

    let file_ev = make_work_record(
        "ev-file-1",
        3,
        HistoryEventKind::ItemRecorded,
        "file-1",
        HistoryEntityKind::FileChange,
        "file",
        HistoryEntityState::KnownTerminal {
            outcome: ChatTerminalOutcome::Completed,
        },
        serde_json::json!({ "path": "src/main.rs" }),
    )?;
    let _ = layer.on_history_record(&file_ev).unwrap();

    let skill_ev = make_work_record(
        "ev-skill-1",
        4,
        HistoryEventKind::ItemRecorded,
        "skill-1",
        HistoryEntityKind::Skill,
        "skill",
        HistoryEntityState::KnownTerminal {
            outcome: ChatTerminalOutcome::Completed,
        },
        serde_json::json!({ "activation": { "name": "rust-code-quality" } }),
    )?;
    let snap = layer.on_history_record(&skill_ev).unwrap();

    match snap.phase {
        LiveStatusPhase::Working { items, .. } => {
            assert_eq!(items.len(), 3);
            assert!(matches!(
                &items[0],
                WorkGroupMember::Agent {
                    agent_id,
                    name,
                    status,
                    summary,
                    payload_json,
                    ..
                } if agent_id == "thread-child-1"
                    && name == "rust-backend"
                    && status == "completed"
                    && summary == "Implement Phase A"
                    && payload_json.contains("Implement Phase A")
            ));
            assert!(matches!(
                &items[1],
                WorkGroupMember::FileChange { summary, .. } if summary == "src/main.rs"
            ));
            assert!(matches!(
                &items[2],
                WorkGroupMember::Skill { name, .. } if name == "rust-code-quality"
            ));
        }
        other => panic!("expected Working, got {other:?}"),
    }
    Ok(())
}
