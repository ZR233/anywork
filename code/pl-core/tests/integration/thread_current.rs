use std::sync::Arc;

use pl_core::context::{
    ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
};
use pl_core::model::{
    CancellationToken, CurrentCaptureHandle, DynModelSession, ModelCallExit, ModelError,
    ModelFailureKind, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall, ModelUsage,
    PreparedModelCall, ToolCallMode, ToolProgress, ToolProgressUpdate,
};
use pl_core::thread::current::{
    CurrentError, CurrentModelCall, PendingStepInput, RuntimeEpoch, SavedModelPhase,
    SavedToolProgress, ThreadCurrent, ThreadCurrentState,
};
use pl_core::thread::{
    ModelExecutionPhase, ModelStepLimit, StepInput, ThreadHandle, ThreadSnapshot, ToolDelivery,
    ToolDeliveryTarget, ToolOutcome, TurnInput, input, task,
};
use tokio::sync::Notify;

fn text(value: &str) -> ContextContent {
    ContextContent::Text {
        text: Arc::from(value),
    }
}

fn call(id: &str) -> ModelToolCall {
    ModelToolCall {
        call_id: id.into(),
        tool_id: "tool".into(),
        arguments: OpaquePayload::text("{}"),
        presentation_contract: None,
        rejection: None,
    }
}

fn saved_call(epoch: RuntimeEpoch, phase: SavedModelPhase) -> CurrentModelCall {
    CurrentModelCall {
        source_run_id: epoch,
        source_execution_id: uuid::Uuid::new_v4().to_string(),
        source_turn_id: "turn".into(),
        source_attempt_id: "old-attempt".into(),
        tools: Arc::from([]),
        tool_call_mode: ToolCallMode::Parallel,
        solo_tool_ids: Arc::from([]),
        prepared_parameters: Some(
            OpaquePayload::new("pl.model.prepared-request", 1, "full options").unwrap(),
        ),
        phase,
    }
}

fn output(attempt: &str, revision: u64) -> ModelStepOutput {
    ModelStepOutput {
        turn_action: Default::default(),
        attempt_id: attempt.into(),
        base_context_revision: revision,
        content: vec![text("complete assistant")],
        tool_calls: Vec::new(),
        private_context: Some(OpaquePayload::text("signed native replay")),
        usage: ModelUsage {
            input_tokens: Some(7),
            output_tokens: Some(3),
            cache_read_tokens: Some(0),
            ..Default::default()
        },
    }
}

fn delivery(id: &str, target: ToolDeliveryTarget) -> ToolDelivery {
    ToolDelivery {
        target,
        call_id: id.into(),
        tool_id: "tool".into(),
        output: pl_core::tool::ToolOutput::new(
            OpaquePayload::text(format!("full payload:{id}")),
            vec![text(&format!("known:{id}"))],
        ),
        delivered_context: vec![text(&format!("known:{id}"))],
        outcome: ToolOutcome::Succeeded,
    }
}

fn task_record(id: &str, order: u64) -> task::TaskRecord {
    task::TaskRecord {
        id: format!("task:{id}"),
        parent_call_id: None,
        invocation: None,
        call_id: id.into(),
        tool_id: "tool".into(),
        turn_id: "turn".into(),
        revision: 1,
        status: task::TaskStatus::Running,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: Some(order),
    }
}

#[test]
fn schema_one_is_complete_inline_and_excludes_legacy_fences() {
    let epoch = RuntimeEpoch::new();
    let full = "长正文".repeat(30_000);
    let progress = ToolProgress::default()
        .applied(&ToolProgressUpdate::append("stdout", "x".repeat(64 * 1024)));
    let mut state = ThreadSnapshot {
        commit_sequence: 999,
        ..Default::default()
    };
    state.usage_summary.applied_sequence = 999;
    state.context = ContextSnapshot {
        revision: 4,
        records: vec![ContextRecord {
            id: "user".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![text(&full)],
            tool_calls: vec![],
        }]
        .into(),
    };
    state
        .tasks
        .insert("task:call".into(), task_record("call", 700));
    state.tool_progress.insert("task:call".into(), progress);
    let mut current = ThreadCurrent::new("thread".into(), epoch);
    current.state = ThreadCurrentState::from_snapshot(&state, epoch).unwrap();
    current.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Streaming {
            stream: OpaquePayload::new(
                "pl.model.stream-current",
                1,
                "{\"partial\":\"{\\\"path\\\":\\\"src/ma\"}",
            )
            .unwrap(),
        },
    ));
    let encoded = serde_json::to_vec(&current).unwrap();
    let json: serde_json::Value = serde_json::from_slice(&encoded).unwrap();
    let fields = json["state"].as_object().unwrap();
    let expected = [
        "lifecycle",
        "execution",
        "continuation",
        "continuationOperations",
        "inputs",
        "inputOrdinal",
        "terminalInputs",
        "context",
        "privateContext",
        "tasks",
        "taskStartOrdinal",
        "toolPreviews",
        "deliveries",
        "discoveredTools",
        "runtimeFacts",
        "extensions",
        "extensionSequence",
        "inbox",
        "inboxSequence",
        "consumedMessages",
        "wakeMessagesThrough",
        "consumedMessageIdentities",
        "interactions",
        "permissions",
        "lastAttemptUsage",
        "lastAttemptUsageOrigin",
        "usageSummary",
    ]
    .into_iter()
    .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(
        fields
            .keys()
            .map(String::as_str)
            .collect::<std::collections::BTreeSet<_>>(),
        expected
    );
    for excluded in [
        "commitSequence",
        "persistence",
        "requiredDurableSequence",
        "attempts",
        "turns",
        "liveCalls",
        "attemptIds",
        "terminalTasks",
        "toolProgress",
        "observationRevision",
    ] {
        assert!(!fields.contains_key(excluded), "unexpected {excluded}");
    }
    assert!(
        json["state"]["usageSummary"]
            .get("appliedSequence")
            .is_none()
    );
    assert_eq!(json["state"]["tasks"]["task:call"]["startedOrder"], 1);
    assert!(
        json["state"]["tasks"]["task:call"]
            .get("startedSequence")
            .is_none()
    );
    assert_eq!(state.tasks["task:call"].started_sequence, Some(700));
    let mut local = current.state.clone();
    local.start_task(task_record("next", 9999)).unwrap();
    local.tasks.remove("task:call");
    local.start_task(task_record("latest", 9999)).unwrap();
    assert_eq!(local.task_start_ordinal, 3);
    assert_eq!(local.tasks["task:next"].started_sequence, Some(2));
    assert_eq!(local.tasks["task:latest"].started_sequence, Some(3));
    assert!(json["state"]["toolPreviews"].get("task:call").is_none());
    assert_eq!(
        json["state"]["toolPreviews"]["call"]["parts"][0]["text"]
            .as_str()
            .unwrap()
            .len(),
        64 * 1024
    );
    let decoded = ThreadCurrent::from_json(&encoded, "thread").unwrap();
    assert_eq!(decoded.state.context.records[0].content, vec![text(&full)]);
    assert_eq!(decoded.state.tool_previews["call"].source_run_id, epoch);
    assert!(matches!(
        ThreadCurrent::from_json(&encoded, "other"),
        Err(CurrentError::ThreadIdentity(_))
    ));
    let mut unknown = json.clone();
    unknown["schemaVersion"] = 2.into();
    assert!(matches!(
        ThreadCurrent::from_json(&serde_json::to_vec(&unknown).unwrap(), "thread"),
        Err(CurrentError::Schema(2))
    ));
    let mut bad = json;
    bad["state"]["historyFence"] = 10.into();
    assert!(ThreadCurrent::from_json(&serde_json::to_vec(&bad).unwrap(), "thread").is_err());
}

#[test]
fn full_tool_baseline_preserves_identity_version_text_without_old_lineage() {
    let progress = ToolProgress::default().applied(&ToolProgressUpdate::append("stdout", "old"));
    let old_baseline = progress.part("stdout").unwrap().baseline();
    let progress = progress
        .applied(&ToolProgressUpdate::append("stdout", " tail"))
        .applied(&ToolProgressUpdate::replace("stderr", "err"));
    let saved = SavedToolProgress::capture(RuntimeEpoch::new(), &progress);
    let restored = saved.restore().unwrap();
    assert_eq!(restored.version(), progress.version());
    assert_eq!(restored.part("stdout").unwrap().version(), 2);
    assert_eq!(restored.part("stdout").unwrap().text(), "old tail");
    assert_eq!(restored.part("stderr").unwrap().text(), "err");
    assert!(matches!(
        restored
            .part("stdout")
            .unwrap()
            .increment_since(&old_baseline),
        pl_core::model::ContentIncrement::Replace { .. }
    ));
    let mut invalid = saved;
    invalid.parts[0].text = "x".repeat(64 * 1024 + 1);
    assert!(matches!(
        invalid.restore(),
        Err(CurrentError::InvalidToolPreview)
    ));
}

#[test]
fn known_deliveries_win_unknown_pairs_and_nested_results_are_not_redispatched() {
    let epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new("thread".into(), epoch);
    current.state.context = ContextSnapshot {
        revision: 1,
        records: vec![ContextRecord {
            id: "assistant".into(),
            turn_id: Some("turn".into()),
            source: ContextSource::Assistant,
            content: vec![],
            tool_calls: vec![call("known"), call("unknown")],
        }]
        .into(),
    };
    current.state.deliveries = vec![
        delivery("known", ToolDeliveryTarget::CallResult),
        delivery(
            "nested",
            ToolDeliveryTarget::Nested {
                parent_call_id: "unknown".into(),
            },
        ),
    ]
    .into();
    current.apply_saved_local_deliveries_once().unwrap();
    current.apply_saved_local_deliveries_once().unwrap();
    current.normalize_unpaired_old_calls_as_unknown().unwrap();
    current.normalize_unpaired_old_calls_as_unknown().unwrap();
    current.state.context.validate_complete().unwrap();
    let results = current
        .state
        .context
        .records
        .iter()
        .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
        .collect::<Vec<_>>();
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].content, vec![text("known:known")]);
    assert!(
        matches!(&results[1].content[0], ContextContent::Text { text } if text.contains("结果未知"))
    );
    assert!(current.state.deliveries.is_empty());
    assert_eq!(current.state.inbox.len(), 1);
    assert_eq!(
        current.state.inbox[0].message.payload.content(),
        "full payload:nested"
    );
    assert_eq!(
        current.state.inbox[0].message.context,
        vec![text("known:nested")]
    );
    let json = serde_json::to_value(&current).unwrap();
    assert!(json["state"].get("attempts").is_none());
    assert!(json["state"].get("turns").is_none());
}

#[test]
fn background_ack_keeps_original_message_identity_and_never_gets_second_tool_result() {
    let epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new("thread".into(), epoch);
    current.model_call = Some(saved_call(epoch, SavedModelPhase::Applied));
    current.state.context = ContextSnapshot {
        revision: 2,
        records: vec![
            ContextRecord {
                id: "assistant".into(),
                turn_id: None,
                source: ContextSource::Assistant,
                content: vec![],
                tool_calls: vec![call("background")],
            },
            ContextRecord {
                id: "ack".into(),
                turn_id: None,
                source: ContextSource::ToolResult {
                    call_id: "background".into(),
                    tool_id: "tool".into(),
                },
                content: vec![text("running in background")],
                tool_calls: vec![],
            },
        ]
        .into(),
    };
    let result = delivery(
        "background",
        ToolDeliveryTarget::Inbox {
            message_id: "original-result-message".into(),
        },
    );
    current.state.deliveries = vec![result.clone()].into();
    current.apply_saved_local_deliveries_once().unwrap();
    let sequence = current.state.inbox[0].sequence;
    current.state.deliveries = vec![result].into();
    current.apply_saved_local_deliveries_once().unwrap();
    current.normalize_unpaired_old_calls_as_unknown().unwrap();
    assert_eq!(current.state.inbox.len(), 1);
    assert_eq!(current.state.inbox[0].message.id, "original-result-message");
    assert_eq!(current.state.inbox[0].sequence, sequence);
    assert_eq!(current.state.context.records.len(), 2);
    current.state.context.validate_complete().unwrap();
    assert_eq!(current.state.inbox[0].sequence, sequence);
}

#[derive(Debug, Clone)]
struct ProducerSession {
    prepare_entered: Arc<Notify>,
    prepare_release: Arc<Notify>,
    finish: Arc<Notify>,
    change: Arc<Notify>,
    finish_on_capture: bool,
}

impl ProducerSession {
    fn new() -> Self {
        Self {
            prepare_entered: Arc::new(Notify::new()),
            prepare_release: Arc::new(Notify::new()),
            finish: Arc::new(Notify::new()),
            change: Arc::new(Notify::new()),
            finish_on_capture: false,
        }
    }
}

impl ModelSession for ProducerSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.prepare_entered.notify_one();
        tokio::select! {
            () = self.prepare_release.notified() => {},
            () = request.cancellation.cancelled() => return Err(ModelError { details: None, kind: ModelFailureKind::Cancelled, usage: Box::default(), source: None }),
        }
        let (capture, mut receiver) = CurrentCaptureHandle::channel();
        let finish = self.finish.clone();
        let change = self.change.clone();
        let finish_on_capture = self.finish_on_capture;
        let prepared = PreparedModelCall::new_with_current(async move {
            let final_stream = OpaquePayload::text("last complete accepted stream");
            let mut current_text = OpaquePayload::text("full current while network is pending");
            loop {
                tokio::select! {
                    () = request.cancellation.cancelled() => return ModelCallExit {
                        result: Err(ModelError { details: None, kind: ModelFailureKind::Cancelled, usage: Box::default(), source: None }),
                        current: Some(final_stream),
                    },
                    () = finish.notified() => return ModelCallExit {
                        result: Ok(output(&request.attempt_id, request.context.revision)), current: Some(final_stream),
                    },
                    () = change.notified() => {
                        current_text = OpaquePayload::text("changed opaque-only state");
                        receiver.mark_dirty();
                    },
                    Some(capture) = receiver.recv() => {
                        assert_eq!(capture.attempt_id, request.attempt_id);
                        if finish_on_capture {
                            return ModelCallExit { result: Ok(output(&request.attempt_id, request.context.revision)), current: Some(final_stream) };
                        }
                        if !capture.cancellation.is_cancelled() { let _ = capture.reply.send(Ok(current_text.clone())); }
                    }
                }
            }
        }).with_current_capture(capture).with_request_metadata(OpaquePayload::text("frozen options"));
        Ok(prepared)
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

async fn wait_running(thread: &ThreadHandle) {
    let mut snapshots = thread.subscribe();
    loop {
        if thread.snapshot().model_execution == Some(ModelExecutionPhase::Running) {
            return;
        }
        snapshots.next().await.unwrap();
    }
}

#[tokio::test]
async fn direct_step_input_survives_preparation_and_admits_once_then_stream_capture_does_not_deadlock()
 {
    let session = ProducerSession::new();
    let thread =
        ThreadHandle::start("thread".into(), DynModelSession::new(session.clone())).unwrap();
    let epoch = thread.runtime_epoch();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: "turn".into(),
                    attempt_id: "direct-attempt".into(),
                    content: vec![text("direct only")],
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    session.prepare_entered.notified().await;
    let preparing = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(preparing.state.context.records.is_empty());
    assert!(matches!(&preparing.model_call.as_ref().unwrap().phase,
        SavedModelPhase::Preparing { pending_step_input: Some(PendingStepInput { content }) } if *content == vec![text("direct only")]));
    session.prepare_release.notify_one();
    wait_running(&thread).await;
    let streaming = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        thread.capture_current(CancellationToken::new()),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(streaming.saved_runtime_epoch, epoch);
    assert_eq!(streaming.state.context.records.len(), 1);
    assert_eq!(
        streaming.state.context.records[0].content,
        vec![text("direct only")]
    );
    assert!(
        matches!(&streaming.model_call.as_ref().unwrap().phase, SavedModelPhase::Streaming { stream } if stream.content() == "full current while network is pending")
    );
    session.finish.notify_one();
    run.await.unwrap().unwrap();
    let applied = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(applied.state.context.records.len(), 2);
    assert!(
        applied.model_call.is_none(),
        "finished work must not become an attempt ledger"
    );
    assert_eq!(applied.state.usage_summary.totals.inference_count, 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn opaque_only_changes_mark_current_dirty_without_a_display_preview() {
    let session = ProducerSession::new();
    session.prepare_release.notify_one();
    let thread =
        ThreadHandle::start("thread".into(), DynModelSession::new(session.clone())).unwrap();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: "turn".into(),
                    attempt_id: "attempt".into(),
                    content: vec![],
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    wait_running(&thread).await;
    let before = thread.snapshot().observation_revision;
    let mut dirty = thread.subscribe_current_dirty();
    dirty.borrow_and_update();
    session.change.notify_one();
    tokio::time::timeout(std::time::Duration::from_secs(1), dirty.changed())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        thread.snapshot().observation_revision,
        before,
        "opaque dirty notification must not publish a UI snapshot"
    );
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(
        matches!(current.model_call.unwrap().phase, SavedModelPhase::Streaming { stream } if stream.content() == "changed opaque-only state")
    );
    thread.close().await.unwrap();
    assert!(run.await.unwrap().is_err());
}

#[derive(Debug, Clone, Default)]
struct GatedCaptureSession {
    entered: Arc<Notify>,
    release: Arc<Notify>,
    finish: Arc<Notify>,
    captures: Arc<std::sync::atomic::AtomicUsize>,
}

impl ModelSession for GatedCaptureSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let (capture, mut receiver) = CurrentCaptureHandle::channel();
        let session = self.clone();
        Ok(PreparedModelCall::new_with_current(async move {
            loop {
                tokio::select! {
                    () = session.finish.notified() => return ModelCallExit {
                        result: Ok(output(&request.attempt_id, request.context.revision)),
                        current: Some(OpaquePayload::text("final stream")),
                    },
                    Some(capture) = receiver.recv() => {
                        session.captures.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                        session.entered.notify_one();
                        session.release.notified().await;
                        let _ = capture.reply.send(Ok(OpaquePayload::text("complete stream")));
                    }
                }
            }
        })
        .with_current_capture(capture))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn current_capture_accepts_inbox_changes_without_recapturing_stream() {
    let session = GatedCaptureSession::default();
    let thread = ThreadHandle::start_current(
        "capture-inbox".into(),
        Some(DynModelSession::new(session.clone())),
    )
    .unwrap();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "turn".into(),
                    attempt_prefix: "turn".into(),
                    content: vec![text("input")],
                    max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    wait_running(&thread).await;
    let capture = tokio::spawn({
        let thread = thread.clone();
        async move { thread.capture_current(CancellationToken::new()).await }
    });
    session.entered.notified().await;
    thread
        .send_message(pl_core::thread::inbox::ThreadMessage {
            id: "arrived".into(),
            source_id: "host".into(),
            kind: Default::default(),
            payload: OpaquePayload::text("new message"),
            context: vec![text("new message")],
        })
        .await
        .unwrap();
    session.release.notify_one();
    let current = capture.await.unwrap().unwrap();
    assert_eq!(current.state.inbox.len(), 1);
    assert!(
        matches!(current.model_call.unwrap().phase, SavedModelPhase::Streaming { stream } if stream.content() == "complete stream")
    );
    assert_eq!(
        session.captures.load(std::sync::atomic::Ordering::SeqCst),
        1
    );
    session.finish.notify_one();
    run.await.unwrap().unwrap();
    thread.close().await.unwrap();
}

struct SwitchingCaptureSession {
    first_capture: Option<
        tokio::sync::oneshot::Sender<(
            pl_core::model::ModelCurrentCaptureRequest,
            pl_core::model::CurrentCaptureReceiver,
        )>,
    >,
    transition: Arc<Notify>,
    second_ready: Arc<Notify>,
    finish: Arc<Notify>,
}

impl ModelSession for SwitchingCaptureSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let first_capture = self.first_capture.take();
        let transition = self.transition.clone();
        let second_ready = self.second_ready.clone();
        let finish = self.finish.clone();
        let (capture, mut receiver) = CurrentCaptureHandle::channel();
        Ok(PreparedModelCall::new_with_current(async move {
            if let Some(first_capture) = first_capture {
                let captured = receiver.recv().await.unwrap();
                let _ = first_capture.send((captured, receiver));
                transition.notified().await;
                let mut result = output(&request.attempt_id, request.context.revision);
                result.turn_action = pl_core::model::ModelTurnAction::Continue;
                return ModelCallExit { result: Ok(result), current: Some(OpaquePayload::text("first final")) };
            }
            second_ready.notify_one();
            loop {
                tokio::select! {
                    Some(captured) = receiver.recv() => { let _ = captured.reply.send(Ok(OpaquePayload::text("second stream"))); },
                    () = finish.notified() => return ModelCallExit {
                        result: Ok(output(&request.attempt_id, request.context.revision)),
                        current: Some(OpaquePayload::text("second final")),
                    },
                }
            }
        }).with_current_capture(capture))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn stale_capture_is_retried_for_the_new_attempt() {
    let (first_capture, captured) = tokio::sync::oneshot::channel();
    let transition = Arc::new(Notify::new());
    let second_ready = Arc::new(Notify::new());
    let finish = Arc::new(Notify::new());
    let thread = ThreadHandle::start_current(
        "switch-capture".into(),
        Some(DynModelSession::new(SwitchingCaptureSession {
            first_capture: Some(first_capture),
            transition: transition.clone(),
            second_ready: second_ready.clone(),
            finish: finish.clone(),
        })),
    )
    .unwrap();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "turn".into(),
                    attempt_prefix: "turn".into(),
                    content: vec![text("input")],
                    max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    wait_running(&thread).await;
    let capture = tokio::spawn({
        let thread = thread.clone();
        async move { thread.capture_current(CancellationToken::new()).await }
    });
    let (old_capture, old_receiver) = captured.await.unwrap();
    let old_attempt = old_capture.attempt_id.clone();
    transition.notify_one();
    second_ready.notified().await;
    old_capture
        .reply
        .send(Ok(OpaquePayload::text("stale stream")))
        .unwrap();
    let current = capture.await.unwrap().unwrap();
    let call = current.model_call.unwrap();
    assert_ne!(call.source_attempt_id, old_attempt);
    assert!(
        matches!(call.phase, SavedModelPhase::Streaming { stream } if stream.content() == "second stream")
    );
    drop(old_receiver);
    finish.notify_one();
    run.await.unwrap().unwrap();
    thread.close().await.unwrap();
}

#[tokio::test]
async fn capture_rechecks_terminal_state_even_when_producer_closed_its_pending_reply() {
    let mut session = ProducerSession::new();
    session.finish_on_capture = true;
    session.prepare_release.notify_one();
    let thread = ThreadHandle::start("thread".into(), DynModelSession::new(session)).unwrap();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: "turn".into(),
                    attempt_id: "attempt".into(),
                    content: vec![],
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    wait_running(&thread).await;
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(current.model_call.is_none());
    assert_eq!(current.state.context.records.len(), 1);
    assert_eq!(current.state.context.records[0].id, "attempt:output");
    run.await.unwrap().unwrap();
    thread.close().await.unwrap();
}

#[tokio::test]
async fn run_turn_saves_direct_input_while_preparing_the_request() {
    let session = ProducerSession::new();
    let thread =
        ThreadHandle::start_current("thread".into(), Some(DynModelSession::new(session.clone())))
            .unwrap();
    let cancellation = CancellationToken::new();
    let run = tokio::spawn({
        let thread = thread.clone();
        let cancellation = cancellation.clone();
        async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "turn".into(),
                    attempt_prefix: "prefix".into(),
                    content: vec![text("before turn admission")],
                    max_model_steps: ModelStepLimit::Limited(std::num::NonZeroU32::new(1).unwrap()),
                    cancellation,
                })
                .await
        }
    });
    session.prepare_entered.notified().await;
    let saved = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(saved.state.context.records.is_empty());
    assert!(matches!(
        saved.model_call.unwrap().phase,
        SavedModelPhase::Preparing {
            pending_step_input: Some(_)
        }
    ));
    cancellation.cancel();
    assert!(run.await.unwrap().is_err());
    thread.close().await.unwrap();
}

#[tokio::test]
async fn close_uses_terminal_handoff_without_asking_destroyed_producer_for_capture() {
    let session = ProducerSession::new();
    session.prepare_release.notify_one();
    let thread = ThreadHandle::start("thread".into(), DynModelSession::new(session)).unwrap();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: "turn".into(),
                    attempt_id: "attempt".into(),
                    content: vec![text("input")],
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    wait_running(&thread).await;
    tokio::time::timeout(std::time::Duration::from_secs(2), thread.close())
        .await
        .unwrap()
        .unwrap();
    assert!(run.await.unwrap().is_err());
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(
        matches!(current.model_call.unwrap().phase, SavedModelPhase::Streaming { stream } if stream.content() == "last complete accepted stream")
    );
}

struct CallSession;

impl ModelSession for CallSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let mut result = output(&request.attempt_id, request.context.revision);
        result.tool_calls = vec![call("known-before-commit")];
        Ok(PreparedModelCall::new(async move { Ok(result) }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[derive(Debug)]
struct KnownBeforeCommitTool(Arc<std::sync::atomic::AtomicUsize>);

impl pl_agent_tool::Tool for KnownBeforeCommitTool {
    type Input = OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("KnownBeforeCommit", "Known completion fixture")
                    .unwrap()
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        _: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        self.0.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok(pl_core::tool::ToolOutput::new(
            OpaquePayload::text("full result before local commit"),
            vec![text("known external result")],
        )
        .with_interaction(OpaquePayload::text("complete proposed question")))
    }
}

#[tokio::test]
async fn rejected_tool_control_still_accepts_known_output_once_without_an_executor_retry() {
    let state = ThreadSnapshot {
        interaction_collection_revision: u64::MAX,
        ..Default::default()
    };
    let checkpoint = pl_core::thread::ThreadCheckpoint::capture("thread".into(), 0, state).unwrap();
    let thread = ThreadHandle::resume(
        "thread".into(),
        DynModelSession::new(CallSession),
        Some(checkpoint),
    )
    .unwrap();
    let executions = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    thread
        .register_tools(vec![
            pl_core::tool::opaque::Registration::prepare(
                "tool".into(),
                OpaquePayload::text("tool"),
            )
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(
                KnownBeforeCommitTool(executions.clone()),
            ))
            .with_interactions()
            .foreground(),
        ])
        .await
        .unwrap();
    thread
        .step(StepInput {
            turn_id: "turn".into(),
            attempt_id: "attempt".into(),
            content: vec![],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    let result = thread
        .execute_tool("known-before-commit".into(), CancellationToken::new())
        .await;
    assert!(matches!(
        result,
        Err(pl_core::thread::ThreadError::Tool(ref error)) if error.source.downcast_ref::<pl_core::thread::ThreadError>().is_some_and(|error| matches!(error, pl_core::thread::ThreadError::RevisionExhausted))
    ));
    assert!(
        thread.snapshot().interactions.is_empty(),
        "the failed control never installed an interaction"
    );
    let mut current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(
        current.state.deliveries.is_empty(),
        "the known result already entered confirmed context"
    );
    let effects = thread.effects().await.unwrap();
    let delivery = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.call_id == "known-before-commit")
        .unwrap();
    assert_eq!(
        delivery.output.payload().content(),
        "full result before local commit"
    );
    assert_eq!(
        delivery.output.interaction().unwrap().content(),
        "complete proposed question"
    );
    current.apply_saved_local_deliveries_once().unwrap();
    current.normalize_unpaired_old_calls_as_unknown().unwrap();
    let result = current
        .state
        .context
        .records
        .iter()
        .find(|record| {
            matches!(record.source,
        ContextSource::ToolResult { ref call_id, .. } if call_id == "known-before-commit")
        })
        .unwrap();
    assert_eq!(result.content.first(), Some(&text("known external result")));
    assert!(result.content.iter().any(|content| matches!(content, ContextContent::Text { text } if text.contains("revision exhausted"))));
    assert_eq!(executions.load(std::sync::atomic::Ordering::SeqCst), 1);
    // The rejected control left no pending installation or executor to replay.
    thread.close_for_deletion().await.unwrap();
}

#[tokio::test]
async fn freshly_created_current_turn_uses_uuid_attempt_not_the_legacy_prefix_allocator() {
    let session = ProducerSession::new();
    session.prepare_release.notify_one();
    let thread =
        ThreadHandle::start_current("fresh".into(), Some(DynModelSession::new(session.clone())))
            .unwrap();
    let epoch = thread.runtime_epoch();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "new-turn".into(),
                    attempt_prefix: "legacy-prefix".into(),
                    content: vec![text("fresh user input")],
                    max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    wait_running(&thread).await;
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    let call = current.model_call.as_ref().unwrap();
    assert_eq!(call.source_run_id, epoch);
    assert_eq!(
        uuid::Uuid::parse_str(&call.source_execution_id)
            .unwrap()
            .get_version_num(),
        4
    );
    assert_eq!(
        uuid::Uuid::parse_str(&call.source_attempt_id)
            .unwrap()
            .get_version_num(),
        4
    );
    assert_ne!(call.source_attempt_id, "legacy-prefix:0");
    session.finish.notify_one();
    run.await.unwrap().unwrap();
    assert_eq!(thread.runtime_epoch(), epoch);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn old_permission_answer_is_saved_but_never_recreates_a_task_execution_lease() {
    use pl_core::thread::permissions::{
        PermissionDecision, PermissionRecord, PermissionResolution, PermissionState,
    };
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("permission".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Streaming {
            stream: OpaquePayload::text("old stream"),
        },
    ));
    saved
        .state
        .tasks
        .insert("task:old".into(), task_record("old", 1));
    saved.state.task_start_ordinal = 1;
    saved.state.permissions.insert(
        "permission:old".into(),
        PermissionRecord {
            created_at: 1,
            updated_at: 1,
            response: None,
            id: "permission:old".into(),
            task_id: "task:old".into(),
            call_id: "old".into(),
            turn_id: "turn".into(),
            tool_id: "tool".into(),
            revision: 1,
            payload: OpaquePayload::text("full permission prompt"),
            state: PermissionState::Pending,
        },
    );
    let thread = ThreadHandle::restore_current(saved, None).unwrap();
    assert!(matches!(
        thread
            .resume_current(
                "new-turn".into(),
                ModelStepLimit::Unlimited,
                CancellationToken::new()
            )
            .await,
        Err(CurrentError::PendingPermission)
    ));
    let answer = thread
        .resolve_execution_permission(PermissionResolution {
            id: "permission:old".into(),
            expected_revision: 1,
            decision: PermissionDecision::Allow,
            payload: Some(OpaquePayload::text("old prompt answered")),
        })
        .await
        .unwrap();
    assert_eq!(answer.state, PermissionState::Allowed);
    assert!(
        thread.cancel_task("task:old".into()).await.is_err(),
        "an old task has no live token"
    );
    assert!(matches!(
        thread
            .resume_current(
                "new-turn".into(),
                ModelStepLimit::Unlimited,
                CancellationToken::new()
            )
            .await,
        Err(CurrentError::Owner(_))
    ));
    assert!(
        thread
            .execute_tool("old".into(), CancellationToken::new())
            .await
            .is_err()
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn current_task_start_ordinal_outlives_completed_tasks_and_is_not_an_effect_fence() {
    let thread =
        ThreadHandle::start_current("task-order".into(), Some(DynModelSession::new(CallSession)))
            .unwrap();
    thread
        .register_tools(vec![
            pl_core::tool::opaque::Registration::prepare(
                "tool".into(),
                OpaquePayload::text("tool"),
            )
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(
                KnownBeforeCommitTool(Arc::new(std::sync::atomic::AtomicUsize::new(0))),
            ))
            .with_interactions()
            .foreground(),
        ])
        .await
        .unwrap();
    thread
        .step(StepInput {
            turn_id: "turn".into(),
            attempt_id: uuid::Uuid::new_v4().to_string(),
            content: vec![],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    thread
        .execute_tool("known-before-commit".into(), CancellationToken::new())
        .await
        .unwrap();
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(current.state.tasks.is_empty());
    assert_eq!(current.state.task_start_ordinal, 1);
    assert!(thread.snapshot().commit_sequence > 1);
    thread.close().await.unwrap();
    let restored = ThreadHandle::restore_current(current, None).unwrap();
    assert_eq!(
        restored
            .capture_current(CancellationToken::new())
            .await
            .unwrap()
            .state
            .task_start_ordinal,
        1
    );
    restored.close().await.unwrap();
}

#[derive(Debug, Clone, Copy)]
enum FirstReply {
    Succeed,
    FailPreparation,
    ContextLimit,
    UnknownTool,
}

#[derive(Debug, Clone)]
struct RecordingSession {
    first: FirstReply,
    requests: Arc<std::sync::Mutex<Vec<ModelRequest>>>,
    executions: Arc<std::sync::atomic::AtomicUsize>,
}

impl RecordingSession {
    fn new(first: FirstReply) -> Self {
        Self {
            first,
            requests: Default::default(),
            executions: Default::default(),
        }
    }

    fn counts(&self) -> (usize, usize) {
        (
            self.requests.lock().unwrap().len(),
            self.executions.load(std::sync::atomic::Ordering::SeqCst),
        )
    }
}

impl ModelSession for RecordingSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let first = {
            let mut requests = self.requests.lock().unwrap();
            let first = requests.is_empty();
            requests.push(request.clone());
            first
        };
        let reply = if first {
            self.first
        } else {
            FirstReply::Succeed
        };
        if matches!(reply, FirstReply::FailPreparation) {
            return Err(ModelError {
                kind: ModelFailureKind::Unavailable,
                details: None,
                usage: Default::default(),
                source: None,
            });
        }
        let executions = self.executions.clone();
        let prepared = PreparedModelCall::new(async move {
            executions.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if matches!(reply, FirstReply::ContextLimit) {
                return Err(ModelError {
                    kind: ModelFailureKind::ContextLimit,
                    details: None,
                    usage: Default::default(),
                    source: None,
                });
            }
            let mut result = output(&request.attempt_id, request.context.revision);
            if matches!(reply, FirstReply::UnknownTool) {
                result.tool_calls.push(call("unknown"));
            }
            Ok(result)
        });
        Ok(prepared)
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn restored_current_waits_for_continue_and_uses_current_services() {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("restored".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Streaming {
            stream: OpaquePayload::text("unconfirmed old partial"),
        },
    ));
    saved.state.context.records = vec![ContextRecord {
        id: "confirmed".into(),
        turn_id: None,
        source: ContextSource::User,
        content: vec![text("confirmed input")],
        tool_calls: Vec::new(),
    }]
    .into();
    let session = RecordingSession::new(FirstReply::Succeed);
    let tool_calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    assert_ne!(thread.runtime_epoch(), epoch);
    thread
        .register_tools(vec![
            pl_core::tool::opaque::Registration::prepare(
                "tool".into(),
                OpaquePayload::text("current catalog"),
            )
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(
                KnownBeforeCommitTool(tool_calls.clone()),
            ))
            .foreground(),
        ])
        .await
        .unwrap();
    assert_eq!(session.counts(), (0, 0));
    assert_eq!(tool_calls.load(std::sync::atomic::Ordering::SeqCst), 0);
    assert!(matches!(
        thread.snapshot().input_execution,
        input::InputExecution::Paused
    ));

    thread
        .resume_current(
            "continued".into(),
            ModelStepLimit::Limited(1.try_into().unwrap()),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    let requests = session.requests.lock().unwrap().clone();
    assert_eq!(requests.len(), 1);
    assert_eq!(
        requests[0].tools.len(),
        1,
        "the current catalog replaces the saved empty catalog"
    );
    assert_eq!(
        uuid::Uuid::parse_str(&requests[0].attempt_id)
            .unwrap()
            .get_version_num(),
        4
    );
    assert_ne!(requests[0].attempt_id, "old-attempt");
    assert_eq!(
        requests[0].context.records[0].content,
        vec![text("confirmed input")]
    );
    assert!(!format!("{:?}", requests[0].context).contains("unconfirmed old partial"));
    assert_eq!(tool_calls.load(std::sync::atomic::Ordering::SeqCst), 0);
    assert_eq!(
        thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap()
            .state
            .usage_summary
            .totals
            .inference_count,
        1
    );
    assert!(matches!(
        thread
            .resume_current(
                "again".into(),
                ModelStepLimit::Unlimited,
                CancellationToken::new()
            )
            .await,
        Err(CurrentError::NotPaused)
    ));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn failed_preparation_keeps_direct_and_queued_input_for_a_new_attempt() {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("pending".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("direct")],
            }),
        },
    ));
    saved.state.inputs = vec![input::InputRecord {
        accepted_sequence: 0,
        delivery: input::InputDelivery::NextTurn,
        input: input::ThreadInput {
            id: "queued".into(),
            purpose: input::InputPurpose::Message,
            payload: OpaquePayload::text("queued body"),
            context: vec![text("queued")],
        },
        ordinal: 1,
        revision: 1,
        state: input::InputState::Pending,
    }]
    .into();
    saved.state.input_ordinal = 1;
    let session = RecordingSession::new(FirstReply::FailPreparation);
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    assert!(matches!(
        thread
            .resume_current(
                "first".into(),
                ModelStepLimit::Unlimited,
                CancellationToken::new()
            )
            .await,
        Err(CurrentError::Owner(_))
    ));
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(current.state.context.records.is_empty());
    assert_eq!(current.state.inputs.len(), 1);
    assert!(
        matches!(&current.model_call.unwrap().phase, SavedModelPhase::Preparing { pending_step_input: Some(input) } if input.content == vec![text("direct")])
    );
    assert_eq!(session.counts(), (1, 0));

    thread
        .resume_current(
            "second".into(),
            ModelStepLimit::Limited(1.try_into().unwrap()),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    let requests = session.requests.lock().unwrap().clone();
    assert_eq!(requests.len(), 2);
    assert_ne!(requests[0].attempt_id, requests[1].attempt_id);
    let input = requests[1]
        .context
        .records
        .iter()
        .find(|record| matches!(record.source, ContextSource::User))
        .unwrap();
    assert_eq!(input.content, vec![text("direct"), text("queued")]);
    assert!(
        thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap()
            .state
            .inputs
            .is_empty()
    );
    assert_eq!(session.counts(), (2, 1));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn cancelling_continue_during_preparation_keeps_unadmitted_input_paused() {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("cancelled-resume".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("unadmitted input")],
            }),
        },
    ));
    let session = ProducerSession::new();
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    let cancellation = CancellationToken::new();
    let run = tokio::spawn({
        let thread = thread.clone();
        let cancellation = cancellation.clone();
        async move {
            thread
                .resume_current("cancelled".into(), ModelStepLimit::Unlimited, cancellation)
                .await
        }
    });
    session.prepare_entered.notified().await;
    cancellation.cancel();
    assert!(
        matches!(run.await.unwrap(), Err(CurrentError::Owner(ref error)) if matches!(error.as_ref(), pl_core::thread::ThreadError::Cancelled))
    );
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(current.state.context.records.is_empty());
    assert!(
        matches!(current.model_call.unwrap().phase, SavedModelPhase::Preparing { pending_step_input: Some(input) } if input.content == vec![text("unadmitted input")])
    );
    assert!(matches!(
        thread.snapshot().input_execution,
        input::InputExecution::Paused
    ));
    thread.close().await.unwrap();
}

async fn current_business_json(thread: &ThreadHandle) -> serde_json::Value {
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    current.validate(&current.thread_id).unwrap();
    serde_json::to_value((&current.state, &current.model_call)).unwrap()
}

#[tokio::test]
async fn invalid_current_step_identity_never_overwrites_the_capturable_current() {
    let session = RecordingSession::new(FirstReply::Succeed);
    let thread = ThreadHandle::start_current(
        "valid-current".into(),
        Some(DynModelSession::new(session.clone())),
    )
    .unwrap();
    let before = current_business_json(&thread).await;
    for (turn_id, attempt_id) in [
        ("".into(), uuid::Uuid::new_v4().to_string()),
        ("turn".into(), String::new()),
        ("turn".into(), "not-a-uuid".into()),
    ] {
        assert!(matches!(
            thread
                .step(StepInput {
                    turn_id,
                    attempt_id,
                    content: vec![text("invalid must not survive")],
                    cancellation: CancellationToken::new(),
                })
                .await,
            Err(pl_core::thread::ThreadError::InvalidIdentity)
        ));
        assert_eq!(current_business_json(&thread).await, before);
    }
    assert_eq!(session.counts(), (0, 0));
    let attempt_id = uuid::Uuid::new_v4().to_string();
    thread
        .step(StepInput {
            turn_id: "turn".into(),
            attempt_id: attempt_id.clone(),
            content: vec![text("valid")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    let before = current_business_json(&thread).await;
    assert!(matches!(
        thread
            .step(StepInput {
                turn_id: "turn".into(),
                attempt_id,
                content: vec![text("duplicate")],
                cancellation: CancellationToken::new()
            })
            .await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    assert_eq!(session.counts(), (1, 1));
    assert_eq!(current_business_json(&thread).await, before);
    let saved = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    let restored = ThreadHandle::restore_current(saved, None).unwrap();
    restored.close().await.unwrap();
    thread.close().await.unwrap();
}

#[derive(Debug, Default, Clone)]
struct RecoveryAttempts(Arc<std::sync::Mutex<Vec<(bool, String)>>>);

impl pl_core::thread::context_preparation::ContextPreparationHook for RecoveryAttempts {
    async fn before_step(
        &self,
        request: pl_core::thread::context_preparation::ContextPreparationRequest,
    ) -> pl_core::thread::context_preparation::ContextPreparation {
        use pl_core::thread::context_preparation::ContextPreparation;
        self.0
            .lock()
            .unwrap()
            .push((request.force_compaction, request.model.attempt_id.clone()));
        if !request.force_compaction {
            return ContextPreparation::Unchanged;
        }
        request.enter_compacting().await.unwrap();
        let mut records = request.committed_context.records.to_vec();
        records.insert(
            0,
            ContextRecord {
                id: "compacted-summary".into(),
                turn_id: None,
                source: ContextSource::Runtime {
                    source_id: "summary".into(),
                },
                content: vec![text("summary")],
                tool_calls: vec![],
            },
        );
        ContextPreparation::Prepared {
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![],
            excluded_tool_ids: vec![],
            replacement: Some(pl_core::thread::ReplaceContext {
                expected_revision: request.committed_context.revision,
                reason: pl_core::thread::ContextReplacementReason::Compaction,
                records,
            }),
            facts: request.current_facts.to_vec(),
            mutations: vec![],
        }
    }
}

#[tokio::test]
async fn current_capacity_recovery_preserves_failed_and_preselected_next_attempt_ids() {
    for current in [false, true] {
        let session = RecordingSession::new(FirstReply::ContextLimit);
        let model = DynModelSession::new(session.clone());
        let thread = if current {
            ThreadHandle::start_current("capacity".into(), Some(model)).unwrap()
        } else {
            ThreadHandle::start("capacity".into(), model).unwrap()
        };
        let hook = RecoveryAttempts::default();
        thread
            .set_context_preparation(Some(
                pl_core::thread::context_preparation::ContextPreparer::new(hook.clone()),
            ))
            .await
            .unwrap();
        let input = TurnInput {
            turn_id: "capacity-turn".into(),
            attempt_prefix: "prefix".into(),
            content: vec![text("input once")],
            max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
            cancellation: CancellationToken::new(),
        };
        assert_eq!(thread.run_turn(input).await.unwrap().model_steps, 2);
        assert_eq!(session.counts(), (2, 2));
        let requests = session.requests.lock().unwrap().clone();
        if current {
            for request in &requests {
                assert_eq!(
                    uuid::Uuid::parse_str(&request.attempt_id)
                        .unwrap()
                        .get_version_num(),
                    4
                );
            }
        } else {
            assert_eq!(
                requests
                    .iter()
                    .map(|r| r.attempt_id.as_str())
                    .collect::<Vec<_>>(),
                ["prefix:0", "prefix:1"]
            );
        }
        let forced = hook
            .0
            .lock()
            .unwrap()
            .iter()
            .filter(|(force, _)| *force)
            .map(|(_, attempt)| attempt.clone())
            .collect::<Vec<_>>();
        assert_eq!(forced, [requests[1].attempt_id.clone()]);
        let events = thread
            .effects()
            .await
            .unwrap()
            .iter()
            .flat_map(|effect| effect.context_compactions.iter().cloned())
            .collect::<Vec<_>>();
        assert!(
            matches!(&events[0], pl_core::thread::ContextCompactionEvent::Started { attempt_id: Some(source), .. } if source.as_str() == requests[0].attempt_id.as_str())
        );
        assert_eq!(
            requests[1]
                .context
                .records
                .iter()
                .filter(|record| record.content == vec![text("input once")])
                .count(),
            1
        );
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn current_correction_uses_the_rejected_uuid_and_runtime_feedback_source() {
    for current in [false, true] {
        let session = RecordingSession::new(FirstReply::UnknownTool);
        let model = DynModelSession::new(session.clone());
        let thread = if current {
            ThreadHandle::start_current("correction".into(), Some(model)).unwrap()
        } else {
            ThreadHandle::start("correction".into(), model).unwrap()
        };
        thread
            .run_turn(TurnInput {
                turn_id: "correction-turn".into(),
                attempt_prefix: "prefix".into(),
                content: vec![],
                max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
                cancellation: CancellationToken::new(),
            })
            .await
            .unwrap();
        assert_eq!(session.counts(), (2, 2));
        let requests = session.requests.lock().unwrap().clone();
        let feedback = requests[1]
            .context
            .records
            .iter()
            .find(|record| record.id == format!("{}:input", requests[1].attempt_id))
            .unwrap();
        assert_eq!(
            feedback.source,
            ContextSource::Runtime {
                source_id: "model-output-correction".into()
            }
        );
        let attempts = thread
            .effects()
            .await
            .unwrap()
            .iter()
            .filter_map(|effect| effect.attempt.clone())
            .collect::<Vec<_>>();
        assert_eq!(
            attempts.last().unwrap().retry_of.as_deref(),
            Some(requests[0].attempt_id.as_str())
        );
        thread.close().await.unwrap();
    }
}

#[derive(Debug, Clone, Default)]
struct DirectResources(Arc<std::sync::Mutex<Vec<String>>>);
impl pl_core::context::ResourceReader for DirectResources {
    async fn read(
        &self,
        reference: pl_core::context::ResourceReference,
        _: CancellationToken,
    ) -> Result<Arc<[u8]>, pl_core::context::ResourceReadError> {
        self.0.lock().unwrap().push(reference.id().to_owned());
        Ok(Arc::from(&b"x"[..]))
    }
}

#[tokio::test]
async fn recovery_contents_cover_all_locations_and_core_validates_only_direct_resources() {
    fn contents(id: &str) -> Vec<ContextContent> {
        vec![
            ContextContent::Resource {
                reference: pl_core::context::ResourceReference::new(
                    id.into(),
                    pl_core::context::content_hash(b"x"),
                    1,
                    "text/plain".into(),
                )
                .unwrap(),
            },
            ContextContent::Opaque {
                payload: OpaquePayload::new("pl.model.attachment", 1, "not Core-decodable JSON")
                    .unwrap(),
            },
        ]
    }
    {
        let epoch = RuntimeEpoch::new();
        let mut current = ThreadCurrent::new("resources".into(), epoch);
        current.state.context = ContextSnapshot {
            revision: 1,
            records: vec![ContextRecord {
                id: "context".into(),
                turn_id: None,
                source: ContextSource::User,
                content: contents("context"),
                tool_calls: vec![],
            }]
            .into(),
        };
        current.state.inputs = vec![input::InputRecord {
            accepted_sequence: 0,
            delivery: input::InputDelivery::NextTurn,
            input: input::ThreadInput {
                id: "input".into(),
                purpose: input::InputPurpose::Message,
                payload: OpaquePayload::text("input"),
                context: contents("input"),
            },
            ordinal: 1,
            revision: 1,
            state: input::InputState::Pending,
        }]
        .into();
        current.state.inbox = vec![pl_core::thread::inbox::InboxRecord {
            sequence: 1,
            message: pl_core::thread::inbox::ThreadMessage {
                id: "inbox".into(),
                source_id: "host".into(),
                kind: pl_core::context::AgentMessageKind::Report,
                payload: OpaquePayload::text("inbox"),
                context: contents("inbox"),
            },
        }]
        .into();
        let mut result = delivery("delivery", ToolDeliveryTarget::CallResult);
        result.output =
            pl_core::tool::ToolOutput::new(OpaquePayload::text("result"), contents("output"));
        result.delivered_context = contents("delivered");
        current.state.deliveries = vec![result].into();
        current.state.runtime_facts = vec![pl_core::thread::RuntimeFact {
            source_id: "fact".into(),
            content: contents("facts"),
        }]
        .into();
        current.model_call = Some(saved_call(
            epoch,
            SavedModelPhase::Preparing {
                pending_step_input: Some(PendingStepInput {
                    content: contents("pending"),
                }),
            },
        ));
        let all = current.recovery_contents();
        assert_eq!(all.len(), 14);
        assert_eq!(
            all.iter()
                .filter(|item| matches!(item, ContextContent::Opaque { .. }))
                .count(),
            7
        );
        let reader = DirectResources::default();
        current
            .validate_resources(
                &pl_core::context::ResourceAccess::new(reader.clone()),
                CancellationToken::new(),
            )
            .await
            .unwrap();
        let mut actual = reader.0.lock().unwrap().clone();
        actual.sort();
        let mut expected = vec![
            "context",
            "input",
            "inbox",
            "output",
            "delivered",
            "facts",
            "pending",
        ];
        expected.sort();
        assert_eq!(actual, expected);
    }
}

#[tokio::test]
async fn explicit_input_resumes_saved_current_through_the_existing_queue_driver() {
    for continue_existing in [false, true] {
        let epoch = RuntimeEpoch::new();
        let mut saved = ThreadCurrent::new("queue-resume".into(), epoch);
        saved.model_call = Some(saved_call(
            epoch,
            SavedModelPhase::Preparing {
                pending_step_input: Some(PendingStepInput {
                    content: vec![text("unsent direct input")],
                }),
            },
        ));
        let session = RecordingSession::new(FirstReply::Succeed);
        let thread =
            ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone())))
                .unwrap();
        // A normal read after restore does not authorize work or discard the saved direct input.
        thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(session.counts(), (0, 0));
        let input = input::ThreadInput {
            id: "new-user-input".into(),
            purpose: input::InputPurpose::Message,
            payload: OpaquePayload::text("new user input"),
            context: vec![text("new user input")],
        };
        let options = input::InputDriverOptions {
            max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
        };
        let mut updates = thread.subscribe();
        if continue_existing {
            thread
                .submit_input_and_continue(input, options)
                .await
                .unwrap();
        } else {
            thread.submit_input_and_run(input, options).await.unwrap();
        }
        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            while let Some(snapshot) = updates.next().await {
                if session.counts() == (1, 1)
                    && snapshot.execution.is_none()
                    && snapshot.inputs.is_empty()
                {
                    return;
                }
            }
            panic!("Current owner closed before its authorized input completed");
        })
        .await
        .expect("authorized input must use Current resume, not fail CurrentPaused");
        let requests = session.requests.lock().unwrap().clone();
        assert_eq!(requests.len(), 1);
        let admitted = requests[0]
            .context
            .records
            .iter()
            .find(|record| matches!(record.source, ContextSource::User))
            .unwrap();
        assert_eq!(
            admitted.content,
            vec![text("unsent direct input"), text("new user input")]
        );
        assert_ne!(requests[0].attempt_id, "old-attempt");
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn stopping_a_resumed_current_queue_preserves_a_paused_continuation() {
    let saved = ThreadCurrent::new("stop-current-queue".into(), RuntimeEpoch::new());
    let session = ProducerSession::new();
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    thread
        .submit_input_and_continue(
            input::ThreadInput {
                id: "explicit-resume".into(),
                purpose: input::InputPurpose::Message,
                payload: OpaquePayload::text("resume then stop"),
                context: vec![text("resume then stop")],
            },
            input::InputDriverOptions {
                max_model_steps: ModelStepLimit::Unlimited,
            },
        )
        .await
        .unwrap();
    session.prepare_entered.notified().await;
    session.prepare_release.notify_one();
    wait_running(&thread).await;
    let execution = thread.snapshot().execution.unwrap().id;
    let mut updates = thread.subscribe();
    thread.interrupt_execution(execution).await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        while let Some(snapshot) = updates.next().await {
            if snapshot.execution.is_none() && snapshot.continuation.is_some() {
                assert!(matches!(
                    snapshot.input_execution,
                    input::InputExecution::Paused
                ));
                return;
            }
        }
        panic!("Current owner closed before stop settled");
    })
    .await
    .unwrap();
    thread.close().await.unwrap();
}
