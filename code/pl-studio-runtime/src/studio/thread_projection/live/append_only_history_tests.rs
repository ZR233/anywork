use super::super::observation_parts::observation_start;
use super::{LiveEvent, LiveProjection};
use crate::{
    ThreadContentLifecycle,
    history::{HistoryDemand, HistoryLimits, HistoryStore},
    studio::storage::thread_writer::HistoryChannel,
};
use anyhow::{Context, Result};
use pl_core::thread::{ThreadEffectBatch, ThreadSnapshot, TurnState, current::RuntimeEpoch};
use std::sync::Arc;

fn started(id: &str) -> pl_core::model::ModelStartedMember {
    use pl_core::model::{
        ObservedItemKind, ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
    };
    pl_core::model::ModelStartedMember {
        turn_id: "boundary-turn".into(),
        attempt_id: "boundary-attempt".into(),
        generation: 0,
        identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: id.into(),
            output_index: None,
            content_index: 0,
            item_kind: ObservedItemKind::Reasoning,
            part: ObservedPartKind::ReasoningText,
        }),
    }
}

#[tokio::test]
async fn stateless_projection_emits_atomic_events_without_boundary_cuts() -> Result<()> {
    use pl_core::model::{
        ActiveModelProgress, ModelProgress, ObservedPart, ObservedPartIdentity, ObservedPartKind,
        ProviderPartIdentity,
    };
    use pl_core::thread::{AttemptStatus, RequestAttempt, TurnRecord};
    use pl_model::completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    };
    use pl_model::runtime::{ModelMemberReceipt, ModelMemberState};

    let directory = tempfile::tempdir()?;
    let thread = crate::Thread::placeholder("stateless-owner");
    let history = HistoryStore::open(
        directory.path().join("history.sqlite"),
        &thread.id,
        HistoryLimits {
            pending_events: 64,
            pending_bytes: 1024 * 1024,
        },
    )
    .await?;
    let run = RuntimeEpoch::new();
    let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
    let mut projection = LiveProjection::new();
    projection.bind_execution(channel.order_index(), run, history.database_id().to_owned())?;

    let turn = TurnRecord {
        turn_id: "stateless-turn".into(),
        input_id: None,
        state: TurnState::Running,
        elapsed_ms: None,
        model_steps: 1,
    };
    let mut state = ThreadSnapshot {
        turns: Arc::from([turn.clone()]),
        attempts: Arc::from([RequestAttempt::new(
            "stateless-turn".into(),
            "stateless-attempt".into(),
            0,
            AttemptStatus::Running,
        )]),
        ..Default::default()
    };
    let effect = |sequence| ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence,
        committed_at: 10 + sequence as i64,
        ..Default::default()
    };
    let opening_member = started("A");
    let boundary_id = observation_start(
        &opening_member.attempt_id,
        opening_member.generation,
        &opening_member.identity,
        &ThreadContentLifecycle::streaming(),
    )
    .context("boundary member identity")?
    .0;
    let mut opening = effect(1);
    opening.turn = Some(turn);
    opening.model_member_starts = Arc::from([opening_member]);
    let (_, prepared_open) = projection.prepare(&thread, &opening, &state, false)?;
    history.accept_batch(&prepared_open.history_events).await?;

    let observed = started("A").identity;
    let part = ObservedPart::new(observed).appended("STREAM_PREFIX");
    state.model_progress = Some(ActiveModelProgress {
        attempt_id: "stateless-attempt".into(),
        progress: ModelProgress::new(0, vec![part]),
    });
    projection.stream(&thread, &state)?;

    let mut terminal = effect(2);
    let mut final_text = started("T");
    final_text.identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
        item_id: "T".into(),
        output_index: None,
        content_index: 0,
        item_kind: pl_core::model::ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
        part: ObservedPartKind::OutputText,
    });
    let final_id = observation_start(
        &final_text.attempt_id,
        final_text.generation,
        &final_text.identity,
        &ThreadContentLifecycle::streaming(),
    )
    .context("final text identity")?
    .0;
    terminal.model_member_content_available = vec![pl_core::model::ModelContentAvailableMember {
        turn_id: final_text.turn_id.clone(),
        attempt_id: final_text.attempt_id.clone(),
        generation: final_text.generation,
        identity: final_text.identity.clone(),
    }];
    terminal.model_member_starts = Arc::from([final_text]);
    let receipt = ModelMemberReceipt {
        item: CompletionPresentationItem {
            provider_item_id: "A".into(),
            output_index: None,
            kind: CompletionPresentationItemKind::Reasoning,
            parts: vec![CompletionPresentationPart {
                kind: CompletionPresentationPartKind::ReasoningText,
                content_index: 0,
                provider_part_id: None,
                text: "REASONING_BODY".into(),
            }],
        },
        state: ModelMemberState::Completed,
    };
    terminal.model_members = Arc::from([pl_core::model::ModelCompletedMember {
        turn_id: "stateless-turn".into(),
        attempt_id: "stateless-attempt".into(),
        generation: 0,
        member_id: "A".into(),
        payload: pl_core::context::OpaquePayload::new(
            "pl.model.completed-member",
            1,
            serde_json::to_string(&receipt)?,
        )?,
    }]);

    let (_, prepared) = projection.prepare(&thread, &terminal, &state, false)?;
    assert!(
        prepared
            .history_events
            .iter()
            .all(|event| { event.kind != crate::history::HistoryEventKind::LegacyObserved })
    );
    let text_start = prepared
        .history_events
        .iter()
        .find(|event| event.entity_id.as_deref() == Some(final_id.as_str()))
        .context("final text start event")?;
    assert_eq!(
        text_start.timeline_role,
        crate::history::HistoryTimelineRole::Hidden,
        "active non-terminal text start must not emit a duplicate Divider"
    );
    let terminal_reasoning_id = super::super::order::presentation_id(
        "stateless-attempt",
        0,
        "A",
        Some(super::super::order::PresentationPart::ReasoningText(0)),
    );
    let reasoning_done = prepared
        .history_events
        .iter()
        .find(|event| {
            event.entity_id.as_deref() == Some(terminal_reasoning_id.as_str())
                && event.kind == crate::history::HistoryEventKind::ReasoningCompleted
        })
        .context("terminal reasoning event")?;
    assert_eq!(
        reasoning_done.timeline_role,
        crate::history::HistoryTimelineRole::Work
    );
    history.accept_batch(&prepared.history_events).await?;
    history.flush().await?;

    let reader = history.reader();
    let timeline = reader
        .timeline_page(
            None,
            None,
            HistoryDemand {
                max_rows: 16,
                max_bytes: 128 * 1024,
            },
        )
        .await?;
    assert_eq!(timeline.items.len(), 1);
    let crate::history::HistoryTimelineItem::WorkRange(range) = &timeline.items[0] else {
        anyhow::bail!("expected WorkRange in timeline");
    };
    let work_page = reader
        .work_range_page(
            range.after_seq,
            range.before_seq,
            Some(timeline.cut),
            None,
            HistoryDemand {
                max_rows: 16,
                max_bytes: 128 * 1024,
            },
        )
        .await?;
    assert_eq!(work_page.events.len(), 1);
    let text = crate::history::read_event_body_bytes(
        &reader,
        &work_page.events[0],
        "part.reasoningText.0",
        Some(16 * 1024),
    )
    .await?
    .context("reasoning body bytes")?;
    assert_eq!(text, b"REASONING_BODY");

    state.model_progress = None;
    projection.stream(&thread, &state)?;
    assert!(projection.current_state().as_ref().is_some_and(|current| {
        current
            .projection()
            .atoms
            .iter()
            .all(|atom| atom.id != boundary_id)
    }));
    reader.close().await;
    channel.stop_and_join().await?;
    history.close().await?;
    Ok(())
}

#[tokio::test]
async fn background_exec_stop_and_late_completion_emit_unified_call_id_events() -> Result<()> {
    use pl_core::context::{ContextContent, ContextRecord, ContextSource, OpaquePayload};
    use pl_core::model::ModelToolCall;
    use pl_core::thread::{
        ToolDelivery, ToolDeliveryTarget, ToolOutcome, TurnRecord,
        inbox::{InboxRecord, ThreadMessage},
        journal::ContextChange,
        task::{TaskAcknowledgement, TaskRecord, TaskStatus},
    };
    use pl_core::tool::ToolOutput;

    let directory = tempfile::tempdir()?;
    let thread = crate::Thread::placeholder("exec-stop-bg");
    let history = HistoryStore::open(
        directory.path().join("exec-stop.sqlite"),
        &thread.id,
        HistoryLimits {
            pending_events: 64,
            pending_bytes: 1024 * 1024,
        },
    )
    .await?;
    let run = RuntimeEpoch::new();
    let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
    let mut projection = LiveProjection::new();
    projection.bind_execution(channel.order_index(), run, history.database_id().to_owned())?;

    let call_id = "call_43c813e84870403b8727b7f9".to_owned();
    let expected_entity_id = super::super::order::tool_id(&call_id);
    let invocation = ModelToolCall {
        call_id: call_id.clone(),
        tool_id: "exec".into(),
        arguments: OpaquePayload::new("application/json", 1, r#"{"command":"git fetch origin"}"#)?,
        presentation_contract: Some(pl_core::model::ToolPresentationContract::new("terminal@1")),
        rejection: None,
    };
    let turn_running = TurnRecord {
        turn_id: "turn-bg".into(),
        input_id: None,
        state: TurnState::Running,
        elapsed_ms: None,
        model_steps: 1,
    };
    let mut task = TaskRecord {
        id: "task:exec:1".into(),
        parent_call_id: None,
        invocation: Some(invocation.clone()),
        call_id: call_id.clone(),
        tool_id: "exec".into(),
        turn_id: turn_running.turn_id.clone(),
        revision: 1,
        status: TaskStatus::Running,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: Some(1),
    };
    let call_record = ContextRecord {
        id: "ctx-call-1".into(),
        turn_id: Some(turn_running.turn_id.clone()),
        source: ContextSource::Assistant,
        content: vec![],
        tool_calls: vec![invocation.clone()],
    };
    let mut state = ThreadSnapshot {
        turns: Arc::from([turn_running.clone()]),
        ..Default::default()
    };
    state.context.revision = 1;
    state.context.records = Arc::from([call_record.clone()]);
    state.tasks.insert(task.id.clone(), task.clone());

    // Effect 1: exec tool starts running -> emits ToolCalled.
    let effect1 = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence: 1,
        committed_at: 100,
        turn: Some(turn_running.clone()),
        tasks: Arc::from([task.clone()]),
        context: Some(ContextChange::Append {
            revision: 1,
            records: Arc::from([call_record.clone()]),
        }),
        ..Default::default()
    };
    let (_, p1) = projection.prepare(&thread, &effect1, &state, false)?;
    assert!(p1.history_events.iter().any(|ev| {
        ev.kind == crate::history::HistoryEventKind::ToolCalled
            && ev.call_id.as_deref() == Some(call_id.as_str())
            && ev.entity_id.as_deref() == Some(expected_entity_id.as_str())
            && ev.timeline_role == crate::history::HistoryTimelineRole::Work
    }));
    history.accept_batch(&p1.history_events).await?;

    // Effect 2: task hands off to background -> emits ToolBackgrounded and seals background_started_draft.
    task.revision = 2;
    task.acknowledgement = Some(TaskAcknowledgement {
        record_id: "ctx-ack-2".into(),
        context_revision: 2,
    });
    let ack_record = ContextRecord {
        id: "ctx-ack-2".into(),
        turn_id: Some(turn_running.turn_id.clone()),
        source: ContextSource::ToolResult {
            call_id: call_id.clone(),
            tool_id: "exec".into(),
        },
        content: vec![ContextContent::Text {
            text: "backgrounded".into(),
        }],
        tool_calls: vec![],
    };
    state.context.revision = 2;
    state.context.records = Arc::from([call_record, ack_record.clone()]);
    state.tasks.insert(task.id.clone(), task.clone());
    let effect2 = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence: 2,
        committed_at: 105,
        tasks: Arc::from([task.clone()]),
        context: Some(ContextChange::Append {
            revision: 2,
            records: Arc::from([ack_record]),
        }),
        ..Default::default()
    };
    let (_, p2) = projection.prepare(&thread, &effect2, &state, false)?;
    let bg_count = p2
        .history_events
        .iter()
        .filter(|ev| ev.kind == crate::history::HistoryEventKind::ToolBackgrounded)
        .count();
    assert_eq!(bg_count, 1);
    history.accept_batch(&p2.history_events).await?;

    // Effect 3: subsequent non-cancelling effect must NOT re-emit ToolBackgrounded (#488).
    let effect3 = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence: 3,
        committed_at: 106,
        tasks: Arc::from([task.clone()]),
        ..Default::default()
    };
    let (_, p3) = projection.prepare(&thread, &effect3, &state, false)?;
    assert!(
        p3.history_events.is_empty(),
        "sealed background_started must not repeat"
    );

    // Effect 4: user clicks Stop (cancel_requested = true, TurnState::Cancelled) while task is still running.
    task.revision = 3;
    task.cancel_requested = true;
    state.tasks.insert(task.id.clone(), task.clone());
    let turn_cancelled = TurnRecord {
        turn_id: "turn-bg".into(),
        input_id: None,
        state: TurnState::Cancelled,
        elapsed_ms: Some(10),
        model_steps: 1,
    };
    state.turns = Arc::from([turn_cancelled.clone()]);
    let effect4 = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence: 4,
        committed_at: 110,
        turn: Some(turn_cancelled),
        tasks: Arc::from([task.clone()]),
        ..Default::default()
    };
    let (_, p4) = projection.prepare(&thread, &effect4, &state, false)?;
    let cancel_ev = p4
        .history_events
        .iter()
        .find(|ev| ev.kind == crate::history::HistoryEventKind::ToolCancelRequested)
        .context("ToolCancelRequested must be emitted when Stop is clicked")?;
    assert_eq!(cancel_ev.call_id.as_deref(), Some(call_id.as_str()));
    assert_eq!(
        cancel_ev.entity_id.as_deref(),
        Some(expected_entity_id.as_str())
    );
    assert_eq!(
        cancel_ev.timeline_role,
        crate::history::HistoryTimelineRole::Work
    );
    let cancel_env = crate::history::decode_event_envelope(&cancel_ev.to_record())?;
    assert_eq!(cancel_env.data["cancelRequested"], serde_json::json!(true));
    history.accept_batch(&p4.history_events).await?;

    // Effect 5: late background delivery completes the task via inbox -> emits ToolCompleted with SAME call_id & entity_id!
    task.revision = 4;
    task.status = TaskStatus::Cancelled;
    state.tasks.remove(&task.id);
    state.terminal_tasks = Arc::from([task.clone()]);
    let inbox_msg = ThreadMessage {
        id: "msg-bg-finish-1".into(),
        source_id: task.id.clone(),
        kind: pl_core::context::AgentMessageKind::Unclassified,
        payload: OpaquePayload::new("pl.tool.background-result", 1, r#"{"exitCode":143}"#)?,
        context: vec![],
    };
    let inbox_rec = InboxRecord {
        sequence: 5,
        message: inbox_msg,
    };
    let output = ToolOutput::new(
        OpaquePayload::new(
            "pl.tool.exec-result",
            1,
            r#"{"stdout":"","stderr":"terminated","exitCode":143}"#,
        )?,
        vec![],
    );
    let delivery = ToolDelivery {
        target: ToolDeliveryTarget::Inbox {
            message_id: inbox_rec.message.id.clone(),
        },
        call_id: call_id.clone(),
        tool_id: "exec".into(),
        output,
        delivered_context: vec![],
        outcome: ToolOutcome::Cancelled,
    };
    state.inbox = Arc::from([inbox_rec.clone()]);
    let effect5 = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence: 5,
        committed_at: 120,
        tasks: Arc::from([task]),
        inbox: Arc::from([inbox_rec]),
        deliveries: Arc::from([delivery]),
        ..Default::default()
    };
    let (_, p5) = projection.prepare(&thread, &effect5, &state, false)?;
    let completed_ev = p5
        .history_events
        .iter()
        .find(|ev| ev.kind == crate::history::HistoryEventKind::ToolCompleted)
        .context("ToolCompleted must be emitted when background delivery arrives")?;
    assert_eq!(completed_ev.call_id.as_deref(), Some(call_id.as_str()));
    assert_eq!(
        completed_ev.entity_id.as_deref(),
        Some(expected_entity_id.as_str()),
        "background completion must NOT rename entity_id to message:..."
    );
    assert_eq!(completed_ev.message_id.as_deref(), Some("msg-bg-finish-1"));
    assert_eq!(
        completed_ev.timeline_role,
        crate::history::HistoryTimelineRole::Work
    );
    history.accept_batch(&p5.history_events).await?;
    history.flush().await?;

    let reader = history.reader();
    let timeline = reader
        .timeline_page(
            None,
            None,
            HistoryDemand {
                max_rows: 16,
                max_bytes: 128 * 1024,
            },
        )
        .await?;
    let work_ranges: Vec<_> = timeline
        .items
        .iter()
        .rev()
        .filter_map(|item| match item {
            crate::history::HistoryTimelineItem::WorkRange(r) => Some(r),
            _ => None,
        })
        .collect();
    assert_eq!(
        work_ranges.len(),
        2,
        "cancelled turn receipt divider splits pre-cancel and post-cancel work ranges"
    );
    let mut work_events = Vec::new();
    for work_range in work_ranges {
        let work_page = reader
            .work_range_page(
                work_range.after_seq,
                work_range.before_seq,
                Some(timeline.cut.clone()),
                None,
                HistoryDemand {
                    max_rows: 32,
                    max_bytes: 128 * 1024,
                },
            )
            .await?;
        work_events.extend(work_page.events);
    }
    let kinds: Vec<_> = work_events
        .iter()
        .filter(|ev| ev.call_id.as_deref() == Some(call_id.as_str()))
        .map(|ev| ev.kind.clone())
        .collect();
    assert_eq!(
        kinds,
        vec![
            crate::history::HistoryEventKind::ToolCalled,
            crate::history::HistoryEventKind::ToolBackgrounded,
            crate::history::HistoryEventKind::ToolCancelRequested,
            crate::history::HistoryEventKind::ToolCompleted,
        ]
    );
    let by_call = reader
        .events_page(
            crate::history::HistoryEventsQuery::Call {
                call_id: call_id.clone(),
            },
            Some(timeline.cut.clone()),
            None,
            HistoryDemand {
                max_rows: 32,
                max_bytes: 128 * 1024,
            },
        )
        .await?;
    let call_kinds: Vec<_> = by_call
        .entries
        .iter()
        .rev()
        .map(|ev| ev.kind.clone())
        .collect();
    assert_eq!(call_kinds, kinds);
    for ev in &work_events {
        let env = crate::history::decode_event_envelope(ev)?;
        assert_eq!(env.contract, "anywork.event/1");
    }
    let args = crate::history::read_event_body_bytes(
        &reader,
        &work_events[0],
        "tool.arguments",
        Some(16 * 1024),
    )
    .await?
    .context("exec arguments")?;
    assert!(String::from_utf8_lossy(&args).contains("git fetch origin"));

    reader.close().await;
    channel.stop_and_join().await?;
    history.close().await?;
    Ok(())
}

#[tokio::test]
async fn nested_task_invocation_is_projected_from_the_task_without_a_context_copy() -> Result<()> {
    use crate::{ChatAtomKind, ChatAtomLifecycle};
    use pl_core::{
        model::ModelToolCall,
        thread::{
            TurnRecord,
            task::{TaskRecord, TaskStatus},
        },
    };

    let thread = crate::Thread::placeholder("nested-task");
    let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
    let mut projection = LiveProjection::new();
    projection.bind_execution(
        channel.order_index(),
        RuntimeEpoch::new(),
        format!("history:{}", thread.id),
    )?;

    let turn = TurnRecord {
        turn_id: "nested-turn".into(),
        input_id: None,
        state: TurnState::Running,
        elapsed_ms: None,
        model_steps: 1,
    };
    let invocation = ModelToolCall {
        call_id: "outer:nested:1".into(),
        tool_id: "exec_command".into(),
        arguments: pl_core::context::OpaquePayload::new(
            "application/json",
            1,
            "{\"command\":\"printf original\"}",
        )?,
        presentation_contract: None,
        rejection: None,
    };
    let task = TaskRecord {
        id: "task:outer:nested:1".into(),
        parent_call_id: Some("outer".into()),
        invocation: Some(invocation.clone()),
        call_id: invocation.call_id.clone(),
        tool_id: invocation.tool_id.clone(),
        turn_id: turn.turn_id.clone(),
        revision: 1,
        status: TaskStatus::Running,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: Some(1),
    };
    let mut state = ThreadSnapshot {
        turns: Arc::from([turn.clone()]),
        ..Default::default()
    };
    state.tasks.insert(task.id.clone(), task.clone());
    let effect = ThreadEffectBatch {
        thread_id: thread.id.clone(),
        sequence: 1,
        committed_at: 10,
        turn: Some(turn),
        tasks: Arc::from([task]),
        ..Default::default()
    };
    projection.prepare(&thread, &effect, &state, false)?;
    projection.stream(&thread, &state)?;
    let current = projection.current_state().context("current State")?;
    let tool_id = super::super::order::tool_id(&invocation.call_id);
    let atom = current
        .projection()
        .atoms
        .iter()
        .find(|atom| atom.id == tool_id && atom.kind == ChatAtomKind::ToolCall)
        .context("nested tool invocation")?;
    assert!(matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }));
    assert_eq!(atom.turn_id.as_deref(), Some("nested-turn"));
    assert_eq!(
        atom.tool.as_ref().map(|tool| tool.call_id.as_str()),
        Some("outer:nested:1")
    );
    assert!(state.context.records.is_empty());
    let arguments = current
        .content(&atom.contents[0].reference)
        .context("nested invocation arguments")?
        .content();
    assert_eq!(
        arguments.data.range(0, arguments.data.len())?.as_bytes(),
        invocation.arguments.content().as_bytes()
    );
    channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn compaction_current_settles_each_real_outcome_without_a_history_item() -> Result<()> {
    use crate::{
        ChatAtomKind, ChatAtomLifecycle, ChatSourceId, ChatSourceLifecycle, ChatTerminalOutcome,
    };
    use pl_core::thread::{ContextCompactionEvent as Event, ContextCompactionOutcome as Outcome};

    let thread = crate::Thread::placeholder("compaction-current");
    for (case, outcome, terminal, associated) in [
        (
            "changed",
            Outcome::Changed {
                context_revision: 9,
            },
            ChatTerminalOutcome::Completed,
            true,
        ),
        (
            "unchanged",
            Outcome::Unchanged,
            ChatTerminalOutcome::Completed,
            false,
        ),
        (
            "failed",
            Outcome::Failed {
                message: "provider refused".into(),
            },
            ChatTerminalOutcome::Failed,
            true,
        ),
        (
            "cancelled",
            Outcome::Cancelled,
            ChatTerminalOutcome::Cancelled,
            false,
        ),
    ] {
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution(
            channel.order_index(),
            RuntimeEpoch::new(),
            format!("history:{}", thread.id),
        )?;
        let turn_id = associated.then(|| format!("{case}-turn"));
        let attempt_id = associated.then(|| format!("{case}-attempt"));
        let source = ChatSourceId::Operation {
            operation_id: case.into(),
        };
        let active = pl_core::thread::ActiveContextCompaction {
            operation_id: case.into(),
            turn_id: turn_id.clone(),
            attempt_id: attempt_id.clone(),
        };
        let active_state = ThreadSnapshot {
            commit_sequence: 1,
            active_context_compaction: Some(active),
            ..Default::default()
        };
        let start = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            context_compactions: Arc::from([Event::Started {
                operation_id: case.into(),
                turn_id: turn_id.clone(),
                attempt_id: attempt_id.clone(),
            }]),
            ..Default::default()
        };
        projection.prepare(&thread, &start, &active_state, false)?;
        projection.stream(&thread, &active_state)?;
        let current = projection.current_state().context("active compaction")?;
        let atom = current
            .projection()
            .atoms
            .iter()
            .find(|atom| atom.kind == ChatAtomKind::Compaction)
            .context("current compaction atom")?;
        assert_eq!(atom.source, source);
        assert_eq!(atom.turn_id, turn_id);
        assert_eq!(atom.attempt_id, attempt_id);
        assert!(matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }));
        assert!(atom.contents.is_empty());

        let finished_state = ThreadSnapshot {
            commit_sequence: 2,
            ..Default::default()
        };
        let finish = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 20,
            context_compactions: Arc::from([Event::Finished {
                operation_id: case.into(),
                outcome,
            }]),
            ..Default::default()
        };
        projection.prepare(&thread, &finish, &finished_state, false)?;
        projection.stream(&thread, &finished_state)?;
        let current = projection.current_state().context("settled compaction")?;
        assert!(
            current
                .projection()
                .atoms
                .iter()
                .all(|atom| atom.kind != ChatAtomKind::Compaction)
        );
        assert!(current.projection().sources.iter().any(|state| {
            state.source == source
                && matches!(
                    state.lifecycle,
                    ChatSourceLifecycle::Ended { outcome } if outcome == terminal
                )
        }));
        channel.stop_and_join().await?;
    }
    Ok(())
}

#[tokio::test]
async fn terminal_turn_revision_tracks_effect_sequence_across_short_followups() -> Result<()> {
    use pl_core::thread::{TurnOutcome, TurnRecord, TurnState};

    let thread = crate::Thread::placeholder("terminal-revision-order");
    let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
    let mut projection = LiveProjection::new();
    projection.bind_execution(
        channel.order_index(),
        RuntimeEpoch::new(),
        format!("history:{}", thread.id),
    )?;

    let turn1_id = "turn-long-1".to_owned();
    let mut state = ThreadSnapshot {
        commit_sequence: 1,
        turns: Arc::from([TurnRecord {
            turn_id: turn1_id.clone(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 0,
        }]),
        ..Default::default()
    };
    let (_, _) = projection.prepare(
        &thread,
        &ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 100,
            turn: Some(state.turns[0].clone()),
            ..Default::default()
        },
        &state,
        true,
    )?;

    // Drive Turn 1 through several phase transitions to inflate its item content revision.
    let phase_invocation = pl_core::model::ModelToolCall {
        call_id: "phase".into(),
        tool_id: "exec".into(),
        arguments: pl_core::context::OpaquePayload::text("{}"),
        presentation_contract: None,
        rejection: None,
    };
    for seq in 2_u64..=5 {
        state.commit_sequence = seq;
        let task = pl_core::thread::task::TaskRecord {
            id: "task:phase".into(),
            parent_call_id: None,
            invocation: Some(phase_invocation.clone()),
            call_id: "phase".into(),
            tool_id: "exec".into(),
            turn_id: turn1_id.clone(),
            revision: seq,
            status: if seq % 2 == 0 {
                pl_core::thread::task::TaskStatus::Running
            } else {
                pl_core::thread::task::TaskStatus::Succeeded
            },
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(2),
        };
        if seq % 2 == 0 {
            state.tasks.insert(task.id.clone(), task.clone());
        } else {
            state.tasks.clear();
        }
        let _ = projection.prepare(
            &thread,
            &ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: seq,
                committed_at: 100 + seq as i64,
                tasks: Arc::from([task]),
                ..Default::default()
            },
            &state,
            true,
        )?;
    }

    let turn1_done = TurnRecord {
        turn_id: turn1_id.clone(),
        input_id: None,
        state: TurnState::Finished(TurnOutcome::Completed),
        elapsed_ms: Some(25),
        model_steps: 2,
    };
    state.commit_sequence = 6;
    state.turns = Arc::from([turn1_done.clone()]);
    let (_, p_turn1) = projection.prepare(
        &thread,
        &ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 6,
            committed_at: 106,
            turn: Some(turn1_done.clone()),
            ..Default::default()
        },
        &state,
        true,
    )?;
    let terminal1 =
        super::super::prepared_terminal_turn(&p_turn1).context("turn 1 terminal projection")?;
    assert_eq!(terminal1.id, turn1_id);
    assert_eq!(terminal1.revision, 6);

    // Turn 2 is much shorter (fewer transitions than Turn 1), yet commits at higher sequence 8.
    let turn2_id = "turn-short-2".to_owned();
    let turn2_running = TurnRecord {
        turn_id: turn2_id.clone(),
        input_id: None,
        state: TurnState::Running,
        elapsed_ms: None,
        model_steps: 0,
    };
    state.commit_sequence = 7;
    state.turns = Arc::from([turn1_done.clone(), turn2_running.clone()]);
    let _ = projection.prepare(
        &thread,
        &ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 7,
            committed_at: 107,
            turn: Some(turn2_running),
            ..Default::default()
        },
        &state,
        true,
    )?;

    let turn2_done = TurnRecord {
        turn_id: turn2_id.clone(),
        input_id: None,
        state: TurnState::Finished(TurnOutcome::Completed),
        elapsed_ms: Some(5),
        model_steps: 1,
    };
    state.commit_sequence = 8;
    state.turns = Arc::from([turn1_done.clone(), turn2_done.clone()]);
    let (events2, p_turn2) = projection.prepare(
        &thread,
        &ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 8,
            committed_at: 108,
            turn: Some(turn2_done),
            ..Default::default()
        },
        &state,
        true,
    )?;
    let terminal2 =
        super::super::prepared_terminal_turn(&p_turn2).context("turn 2 terminal projection")?;
    assert_eq!(terminal2.id, turn2_id);
    assert_eq!(terminal2.revision, 8);
    assert!(terminal2.revision > terminal1.revision);
    let frame2 = events2
        .as_ref()
        .and_then(|list| {
            list.iter().find_map(|ev| match ev {
                LiveEvent::Turn { turn, .. } if turn.id == turn2_id => Some(turn),
                _ => None,
            })
        })
        .context("live frame for turn 2")?;
    assert_eq!(frame2.revision, 8);

    // A later effect referencing an already-retired Turn (effect.turn == None) must NOT emit a
    // synthetic prepared_terminal_turn for the old Turn.
    let late_invocation = pl_core::model::ModelToolCall {
        call_id: "late-turn1".into(),
        tool_id: "exec".into(),
        arguments: pl_core::context::OpaquePayload::text("{}"),
        presentation_contract: None,
        rejection: None,
    };
    let task_on_turn1 = pl_core::thread::task::TaskRecord {
        id: "task:late-turn1".into(),
        parent_call_id: None,
        invocation: Some(late_invocation),
        call_id: "late-turn1".into(),
        tool_id: "exec".into(),
        turn_id: turn1_id,
        revision: 1,
        status: pl_core::thread::task::TaskStatus::Cancelled,
        cancel_requested: true,
        acknowledgement: None,
        started_sequence: Some(2),
    };
    state.commit_sequence = 9;
    let (_, p_late) = projection.prepare(
        &thread,
        &ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 9,
            committed_at: 109,
            tasks: Arc::from([task_on_turn1]),
            ..Default::default()
        },
        &state,
        true,
    )?;
    assert!(
        super::super::prepared_terminal_turn(&p_late).is_none(),
        "effect without a terminal transition in effect.turn must not re-publish an old Turn"
    );

    channel.stop_and_join().await?;
    Ok(())
}
