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
    CurrentError, CurrentModelCall, ExecutionIdentity, PendingStepInput, RuntimeEpoch,
    SavedModelPhase, SavedToolProgress, ThreadCurrent, ThreadCurrentState,
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
fn saved_outcome_applies_atomically_once_and_conflict_keeps_pending() {
    let epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new("thread".into(), epoch);
    current.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::ReadyToApply {
            output: output("old-attempt", 0),
        },
    ));
    current.apply_saved_model_outcome_once().unwrap();
    assert_eq!(current.state.context.records.len(), 1);
    assert_eq!(current.state.context.records[0].id, "old-attempt:output");
    assert_eq!(current.state.usage_summary.totals.inference_count, 1);
    assert_eq!(current.state.usage_summary.totals.prompt_tokens, 7);
    assert_eq!(
        current.state.private_context.as_ref().unwrap().content(),
        "signed native replay"
    );
    current.apply_saved_model_outcome_once().unwrap();
    // Local stable-ID defense also covers a saved outcome whose identical record is already present.
    current.model_call.as_mut().unwrap().phase = SavedModelPhase::ReadyToApply {
        output: output("old-attempt", 0),
    };
    current.apply_saved_model_outcome_once().unwrap();
    assert_eq!(current.state.context.records.len(), 1);
    assert_eq!(current.state.usage_summary.totals.inference_count, 1);
    let mut conflicting = output("old-attempt", 0);
    conflicting.content = vec![text("conflicting")];
    current.model_call.as_mut().unwrap().phase = SavedModelPhase::ReadyToApply {
        output: conflicting,
    };
    let before = serde_json::to_value(&current).unwrap();
    assert!(matches!(
        current.apply_saved_model_outcome_once(),
        Err(CurrentError::RecordConflict(_))
    ));
    assert_eq!(serde_json::to_value(current).unwrap(), before);
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
    let resumed = current
        .prepare_after_user_resume(ExecutionIdentity::new(epoch, "new-turn".into()), |_| Ok(()))
        .unwrap();
    resumed.request.context.validate_complete().unwrap();
    assert_eq!(
        resumed
            .request
            .context
            .records
            .iter()
            .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
            .count(),
        1
    );
    assert_eq!(
        resumed
            .request
            .context
            .records
            .iter()
            .filter(|record| record.id == format!("inbox:{sequence}"))
            .count(),
        1
    );
}

#[test]
fn new_epoch_retains_old_sources_and_fresh_request_never_uses_old_partial_stream() {
    let old_epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new("thread".into(), old_epoch);
    current.model_call = Some(saved_call(
        old_epoch,
        SavedModelPhase::Streaming {
            stream: OpaquePayload::text("old partial not model input"),
        },
    ));
    let mut current = current.activate_paused("thread").unwrap();
    assert_ne!(current.saved_runtime_epoch, old_epoch);
    assert_eq!(
        current.model_call.as_ref().unwrap().source_run_id,
        old_epoch
    );
    let saved = serde_json::to_value(&current).unwrap();
    assert_eq!(saved["modelCall"]["sourceRunId"], old_epoch.to_string());
    let before = serde_json::to_value(&current).unwrap();
    let identity = ExecutionIdentity::new(current.saved_runtime_epoch, "fresh-turn".into());
    let attempt = identity.attempt_id.clone();
    assert_eq!(
        uuid::Uuid::parse_str(&identity.execution_id)
            .unwrap()
            .get_version_num(),
        4
    );
    let error = current
        .prepare_after_user_resume(identity.clone(), |_| {
            Err(ModelError {
                details: None,
                kind: ModelFailureKind::IncompatibleContext,
                usage: Box::default(),
                source: None,
            })
        })
        .unwrap_err();
    assert!(matches!(error, CurrentError::Model(_)));
    assert_eq!(serde_json::to_value(&current).unwrap(), before);
    let result = current
        .prepare_after_user_resume(identity, |parameters| {
            assert_eq!(parameters.unwrap().content(), "full options");
            Ok(())
        })
        .unwrap();
    assert!(result.request.context.records.is_empty());
    assert_eq!(result.request.attempt_id, attempt);
    assert!(result.request.progress.is_none());
    assert!(!result.request.cancellation.is_cancelled());
    assert_eq!(
        current.model_call.as_ref().unwrap().source_run_id,
        current.saved_runtime_epoch
    );
}

#[test]
fn preparing_direct_input_and_queue_have_single_owners_through_resume_admission() {
    let epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new("thread".into(), epoch);
    current.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("direct")],
            }),
        },
    ));
    current.state.inputs = vec![input::InputRecord {
        accepted_sequence: 91,
        continuation: None,
        delivery: input::InputDelivery::NextTurn,
        input: input::ThreadInput {
            id: "queued".into(),
            purpose: input::InputPurpose::Message,
            payload: OpaquePayload::text("full queued body"),
            context: vec![text("queued")],
        },
        ordinal: 1,
        revision: 1,
        state: input::InputState::Pending,
    }]
    .into();
    let saved = serde_json::to_value(&current).unwrap();
    assert!(
        saved["state"]["inputs"][0]
            .get("acceptedSequence")
            .is_none()
    );
    let current_json = serde_json::to_vec(&current).unwrap();
    let mut restored = ThreadCurrent::from_json(&current_json, "thread")
        .unwrap()
        .activate_paused("thread")
        .unwrap();
    assert_eq!(
        restored.state.inputs[0].input.payload.content(),
        "full queued body"
    );
    let identity = ExecutionIdentity::new(restored.saved_runtime_epoch, "new-turn".into());
    let first = restored
        .prepare_after_user_resume(identity, |_| Ok(()))
        .unwrap();
    assert_eq!(
        first
            .request
            .context
            .records
            .iter()
            .filter(|record| record.content == vec![text("direct")])
            .count(),
        1
    );
    assert_eq!(
        first
            .request
            .context
            .records
            .iter()
            .filter(|record| record.content == vec![text("queued")])
            .count(),
        1
    );
    assert!(restored.state.inputs.is_empty());
    assert_eq!(restored.state.terminal_inputs.len(), 1);
    assert!(matches!(
        restored.model_call.as_ref().unwrap().phase,
        SavedModelPhase::Preparing {
            pending_step_input: None
        }
    ));
    let identity = ExecutionIdentity::new(restored.saved_runtime_epoch, "another-turn".into());
    let second = restored
        .prepare_after_user_resume(identity, |_| Ok(()))
        .unwrap();
    assert_eq!(second.request.context, first.request.context);
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
        let recovery_parameters = request.recovery_parameters.clone();
        let mut prepared = PreparedModelCall::new_with_current(async move {
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
        if let Some(parameters) = recovery_parameters {
            prepared = prepared.with_applied_recovery_parameters(parameters);
        }
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
    let mut snapshots = thread.subscribe();
    session.change.notify_one();
    loop {
        if thread.snapshot().observation_revision > before {
            break;
        }
        snapshots.next().await.unwrap();
    }
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
async fn run_turn_saves_direct_input_before_its_first_admission_wait() {
    let session = ProducerSession::new();
    let gate = pl_core::thread::admission::TurnAdmissionGate::new();
    let hold = gate.close();
    let thread = ThreadHandle::start_current_with_turn_admission_gate(
        "thread".into(),
        DynModelSession::new(session),
        gate,
    )
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
    let mut snapshots = thread.subscribe();
    while thread
        .snapshot()
        .execution
        .as_ref()
        .is_none_or(|execution| {
            execution.phase != pl_core::thread::ExecutionPhase::AwaitingAdmission
        })
    {
        snapshots.next().await.unwrap();
    }
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
    drop(hold);
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
async fn retained_uncommitted_tool_completion_is_known_current_data_not_an_unknown_call() {
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
        Err(pl_core::thread::ThreadError::RevisionExhausted)
    ));
    assert!(
        thread.snapshot().deliveries.is_empty(),
        "the ordinary local commit was rolled back"
    );
    let mut current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.state.deliveries.len(), 1);
    assert_eq!(
        current.state.deliveries[0].output.payload().content(),
        "full result before local commit"
    );
    assert_eq!(
        current.state.deliveries[0]
            .output
            .interaction()
            .unwrap()
            .content(),
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
    assert_eq!(result.content, vec![text("known external result")]);
    assert_eq!(executions.load(std::sync::atomic::Ordering::SeqCst), 1);
    // This fixture owns no durable data. Dispose only its synthetic retained completion so its
    // intentionally exhausted old commit path cannot keep an owner/resource alive after the test.
    thread.close_for_deletion().await.unwrap();
}

#[tokio::test]
async fn current_owner_loads_paused_then_applies_saved_output_and_executes_a_fresh_uuid_request() {
    let old_epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("restored".into(), old_epoch);
    saved.model_call = Some(saved_call(
        old_epoch,
        SavedModelPhase::ReadyToApply {
            output: output("old-attempt", 0),
        },
    ));
    saved.state.execution = Some(pl_core::thread::ActiveExecution {
        id: "old-execution".into(),
        phase: pl_core::thread::ExecutionPhase::Running,
        turn_id: Some("turn".into()),
    });
    let session = ProducerSession::new();
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    let epoch = thread.runtime_epoch();
    assert_ne!(epoch, old_epoch);
    assert!(thread.snapshot().execution.is_none());
    assert!(matches!(
        thread.snapshot().input_execution,
        input::InputExecution::Paused
    ));
    let before = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(before.state.execution.as_ref().unwrap().id, "old-execution");
    assert_eq!(before.model_call.as_ref().unwrap().source_run_id, old_epoch);
    assert!(matches!(
        thread
            .step(StepInput {
                turn_id: "bypass".into(),
                attempt_id: uuid::Uuid::new_v4().to_string(),
                content: vec![],
                cancellation: CancellationToken::new()
            })
            .await,
        Err(pl_core::thread::ThreadError::CurrentPaused)
    ));
    let request = thread
        .prepare_current_resume("new-turn".into(), |parameters| {
            assert_eq!(parameters.unwrap().content(), "full options");
            Ok(())
        })
        .await
        .unwrap();
    assert_eq!(request.request.context.records.len(), 1);
    assert_eq!(request.request.context.records[0].id, "old-attempt:output");
    assert_eq!(
        uuid::Uuid::parse_str(&request.request.attempt_id)
            .unwrap()
            .get_version_num(),
        4
    );
    assert!(thread.snapshot().attempt_ids.is_empty());
    assert!(thread.snapshot().turns.is_empty());
    assert_eq!(
        thread.snapshot().commit_sequence,
        0,
        "pure recovery must not export an old model terminal"
    );
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: request.request.turn_id,
                    attempt_id: request.request.attempt_id,
                    content: vec![],
                    cancellation: request.request.cancellation,
                })
                .await
        }
    });
    session.prepare_entered.notified().await;
    session.prepare_release.notify_one();
    wait_running(&thread).await;
    session.finish.notify_one();
    run.await.unwrap().unwrap();
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.saved_runtime_epoch, epoch);
    assert_eq!(current.state.context.records.len(), 2);
    assert_eq!(current.state.usage_summary.totals.inference_count, 2);
    assert!(current.state.execution.is_none());
    assert!(thread.snapshot().live_calls.is_empty());
    assert!(thread.snapshot().attempt_ids.is_empty());
    let revision = current.snapshot_revision;
    thread
        .release_history_through(thread.snapshot().commit_sequence)
        .unwrap();
    assert_eq!(
        thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap()
            .snapshot_revision,
        revision
    );
    thread.close().await.unwrap();
    thread
        .release_history_through(thread.snapshot().commit_sequence)
        .unwrap();
}

#[tokio::test]
async fn freshly_created_current_turn_uses_uuid_attempt_not_the_legacy_prefix_allocator() {
    let session = ProducerSession::new();
    session.prepare_release.notify_one();
    let thread =
        ThreadHandle::start_current("fresh".into(), DynModelSession::new(session.clone())).unwrap();
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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn current_resume_compare_and_swap_keeps_input_that_arrives_during_binding_validation() {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("race".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("direct")],
            }),
        },
    ));
    let thread = ThreadHandle::restore_current(saved, None).unwrap();
    let runtime = tokio::runtime::Handle::current();
    let submitter = thread.clone();
    let result = thread
        .prepare_current_resume("new-turn".into(), move |_| {
            std::thread::spawn(move || {
                runtime.block_on(submitter.submit_input(input::ThreadInput {
                    id: "arrived".into(),
                    purpose: input::InputPurpose::Message,
                    payload: OpaquePayload::text("arrived body"),
                    context: vec![text("arrived")],
                }))
            })
            .join()
            .unwrap()
            .unwrap();
            Ok(())
        })
        .await;
    assert!(matches!(result, Err(CurrentError::StateConflict)));
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.state.inputs.len(), 1);
    assert_eq!(current.state.inputs[0].input.id, "arrived");
    assert!(matches!(
        current.model_call.unwrap().phase,
        SavedModelPhase::Preparing {
            pending_step_input: Some(_)
        }
    ));
    assert!(matches!(
        thread.snapshot().input_execution,
        input::InputExecution::Paused
    ));
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
            .prepare_current_resume("new-turn".into(), |_| Ok(()))
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
    let request = thread
        .prepare_current_resume("new-turn".into(), |_| Ok(()))
        .await
        .unwrap();
    assert!(!request.request.cancellation.is_cancelled());
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
        ThreadHandle::start_current("task-order".into(), DynModelSession::new(CallSession))
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

#[tokio::test]
async fn unavailable_provider_keeps_ready_outcome_locally_applied_while_owner_stays_paused() {
    let old_epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("unavailable".into(), old_epoch);
    saved.model_call = Some(saved_call(
        old_epoch,
        SavedModelPhase::ReadyToApply {
            output: output("old-attempt", 0),
        },
    ));
    let thread = ThreadHandle::restore_current(saved, None).unwrap();
    let result = thread
        .prepare_current_resume("new-turn".into(), |_| {
            Err(ModelError {
                details: None,
                kind: ModelFailureKind::IncompatibleContext,
                usage: Box::default(),
                source: None,
            })
        })
        .await;
    assert!(matches!(result, Err(CurrentError::Model(_))));
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.state.context.records.len(), 1);
    assert_eq!(current.state.usage_summary.totals.inference_count, 1);
    assert!(matches!(
        current.model_call.as_ref().unwrap().phase,
        SavedModelPhase::Applied
    ));
    assert_eq!(
        current.model_call.as_ref().unwrap().source_run_id,
        old_epoch
    );
    assert!(thread.snapshot().execution.is_none());
    assert!(matches!(
        thread.snapshot().input_execution,
        input::InputExecution::Paused
    ));
    assert_eq!(thread.snapshot().commit_sequence, 0);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn preparing_resume_executes_pre_admitted_direct_content_once_and_leaves_later_inbox_pending()
{
    let old_epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("preparing".into(), old_epoch);
    saved.model_call = Some(saved_call(
        old_epoch,
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("saved direct content")],
            }),
        },
    ));
    let session = ProducerSession::new();
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    let request = thread
        .prepare_current_resume("new-turn".into(), |_| Ok(()))
        .await
        .unwrap();
    assert_eq!(request.request.context.records.len(), 1);
    let attempt_id = request.request.attempt_id.clone();
    assert_eq!(
        request.request.context.records[0].id,
        format!("{attempt_id}:input")
    );
    thread
        .send_message(pl_core::thread::inbox::ThreadMessage {
            id: "late".into(),
            source_id: "host".into(),
            kind: pl_core::context::AgentMessageKind::Report,
            payload: OpaquePayload::text("late full message"),
            context: vec![text("late inbox")],
        })
        .await
        .unwrap();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: request.request.turn_id,
                    attempt_id: request.request.attempt_id,
                    content: vec![],
                    cancellation: request.request.cancellation,
                })
                .await
        }
    });
    session.prepare_entered.notified().await;
    session.prepare_release.notify_one();
    wait_running(&thread).await;
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.state.context.records.len(), 1);
    assert_eq!(
        current.state.context.records[0].content,
        vec![text("saved direct content")]
    );
    assert_eq!(current.state.inbox.len(), 1);
    assert_eq!(current.state.inbox[0].message.id, "late");
    session.finish.notify_one();
    run.await.unwrap().unwrap();
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.state.context.records.len(), 2);
    assert_eq!(
        current
            .state
            .context
            .records
            .iter()
            .filter(|record| record.content == vec![text("saved direct content")])
            .count(),
        1
    );
    assert_eq!(current.state.inbox.len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn current_resume_execution_is_bound_to_owner_epoch_and_its_single_selected_attempt() {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("bound".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("single selected input")],
            }),
        },
    ));
    let session = ProducerSession::new();
    session.prepare_release.notify_one();
    let thread =
        ThreadHandle::restore_current(saved, Some(DynModelSession::new(session.clone()))).unwrap();
    let request = thread
        .prepare_current_resume("selected".into(), |_| Ok(()))
        .await
        .unwrap();
    let replay = request.clone();
    let mut stale = request.clone();
    stale.runtime_epoch = RuntimeEpoch::new();
    assert!(matches!(
        thread
            .execute_current_resume(stale, ModelStepLimit::Limited(1.try_into().unwrap()))
            .await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .execute_current_resume(request, ModelStepLimit::Limited(1.try_into().unwrap()))
                .await
        }
    });
    wait_running(&thread).await;
    session.finish.notify_one();
    run.await.unwrap().unwrap();
    assert!(matches!(
        thread
            .execute_current_resume(replay, ModelStepLimit::Limited(1.try_into().unwrap()))
            .await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(
        current
            .state
            .context
            .records
            .iter()
            .filter(|record| record.content == vec![text("single selected input")])
            .count(),
        1
    );
    thread.close().await.unwrap();
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
        let recovery_parameters = request.recovery_parameters.clone();
        let mut prepared = PreparedModelCall::new(async move {
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
        if let Some(parameters) = recovery_parameters {
            prepared = prepared.with_applied_recovery_parameters(parameters);
        }
        Ok(prepared)
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

async fn selected_resume(
    session: impl ModelSession + 'static,
    pending: bool,
) -> (ThreadHandle, pl_core::thread::current::CurrentResumeRequest) {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("claim".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::Preparing {
            pending_step_input: pending.then(|| PendingStepInput {
                content: vec![text("saved direct input")],
            }),
        },
    ));
    let thread = ThreadHandle::restore_current(saved, Some(DynModelSession::new(session))).unwrap();
    let resume = thread
        .prepare_current_resume("selected".into(), |_| Ok(()))
        .await
        .unwrap();
    (thread, resume)
}

fn resume_step(resume: &pl_core::thread::current::CurrentResumeRequest) -> StepInput {
    StepInput {
        turn_id: resume.request.turn_id.clone(),
        attempt_id: resume.request.attempt_id.clone(),
        content: vec![],
        cancellation: CancellationToken::new(),
    }
}

fn resume_turn(resume: &pl_core::thread::current::CurrentResumeRequest) -> TurnInput {
    TurnInput {
        turn_id: resume.request.turn_id.clone(),
        attempt_prefix: resume.request.attempt_id.clone(),
        content: vec![],
        max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
        cancellation: CancellationToken::new(),
    }
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
async fn stopped_current_resume_cannot_enter_through_step_turn_or_the_resume_command() {
    let session = RecordingSession::new(FirstReply::Succeed);
    let (thread, resume) = selected_resume(session.clone(), true).await;
    thread
        .interrupt_execution(resume.execution_id.clone())
        .await
        .unwrap();
    let before = current_business_json(&thread).await;
    assert!(matches!(
        thread.step(resume_step(&resume)).await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    assert!(matches!(
        thread.run_turn(resume_turn(&resume)).await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    assert!(matches!(
        thread
            .execute_current_resume(resume.clone(), ModelStepLimit::Unlimited)
            .await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    assert_eq!(session.counts(), (0, 0));
    assert_eq!(current_business_json(&thread).await, before);
    thread
        .step(StepInput {
            turn_id: "fresh-direct".into(),
            attempt_id: uuid::Uuid::new_v4().to_string(),
            content: vec![text("new explicit direct work")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    assert_eq!(session.counts(), (1, 1));
    assert!(thread.snapshot().execution.is_none());
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_ne!(
        current.model_call.unwrap().source_execution_id,
        resume.execution_id
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn current_resume_rejects_changed_identity_and_input_without_spending_the_claim() {
    let session = RecordingSession::new(FirstReply::Succeed);
    let (thread, resume) = selected_resume(session.clone(), true).await;
    let before = current_business_json(&thread).await;
    for change in 0..3 {
        let mut input = resume_step(&resume);
        match change {
            0 => input.turn_id = "different-turn".into(),
            1 => input.attempt_id = uuid::Uuid::new_v4().to_string(),
            _ => input.content = vec![text("unselected input")],
        }
        assert!(matches!(
            thread.step(input).await,
            Err(pl_core::thread::ThreadError::InvalidIdentity)
        ));
        assert_eq!(current_business_json(&thread).await, before);
    }
    let mut changed_turn = resume_turn(&resume);
    changed_turn.attempt_prefix = uuid::Uuid::new_v4().to_string();
    assert!(matches!(
        thread.run_turn(changed_turn).await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    assert_eq!(session.counts(), (0, 0));
    thread.step(resume_step(&resume)).await.unwrap();
    assert_eq!(session.counts(), (1, 1));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn current_resume_claim_is_spent_even_if_model_preparation_fails_before_admission() {
    let session = RecordingSession::new(FirstReply::FailPreparation);
    let (thread, resume) = selected_resume(session.clone(), false).await;
    assert!(matches!(
        thread.step(resume_step(&resume)).await,
        Err(pl_core::thread::ThreadError::Model(_))
    ));
    assert_eq!(session.counts(), (1, 0));
    thread
        .release_history_through(thread.snapshot().commit_sequence)
        .unwrap();
    assert!(matches!(
        thread.step(resume_step(&resume)).await,
        Err(pl_core::thread::ThreadError::CurrentPaused)
    ));
    assert!(matches!(
        thread
            .execute_current_resume(resume.clone(), ModelStepLimit::Unlimited)
            .await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    assert_eq!(session.counts(), (1, 0));
    resume.request.cancellation.cancel();
    let retry = thread
        .prepare_current_resume("explicit-retry".into(), |_| Ok(()))
        .await
        .unwrap();
    assert!(matches!(
        thread.step(resume_step(&resume)).await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    thread.step(resume_step(&retry)).await.unwrap();
    assert_eq!(session.counts(), (2, 1));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn invalid_current_step_identity_never_overwrites_the_capturable_current() {
    let session = RecordingSession::new(FirstReply::Succeed);
    let thread = ThreadHandle::start_current(
        "valid-current".into(),
        DynModelSession::new(session.clone()),
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
            expected_extension_sequence: request.extension_sequence,
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
            ThreadHandle::start_current("capacity".into(), model).unwrap()
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
            ThreadHandle::start_current("correction".into(), model).unwrap()
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

#[derive(Debug, Clone, Copy)]
enum ResumeEntry {
    Step,
    Turn,
    Resume,
}

async fn enter_resume(
    thread: &ThreadHandle,
    resume: &pl_core::thread::current::CurrentResumeRequest,
    entry: ResumeEntry,
    cancellation: CancellationToken,
) -> Result<(), pl_core::thread::ThreadError> {
    match entry {
        ResumeEntry::Step => {
            let mut input = resume_step(resume);
            input.cancellation = cancellation;
            thread.step(input).await.map(|_| ())
        }
        ResumeEntry::Turn => {
            let mut input = resume_turn(resume);
            input.cancellation = cancellation;
            thread.run_turn(input).await.map(|_| ())
        }
        ResumeEntry::Resume => {
            let mut resume = resume.clone();
            resume.request.cancellation = cancellation;
            thread
                .execute_current_resume(resume, ModelStepLimit::Unlimited)
                .await
                .map(|_| ())
        }
    }
}

#[tokio::test]
async fn current_resume_original_cancellation_rejects_new_tokens_at_every_entry() {
    for entry in [ResumeEntry::Step, ResumeEntry::Turn, ResumeEntry::Resume] {
        let session = RecordingSession::new(FirstReply::Succeed);
        let (thread, resume) = selected_resume(session.clone(), true).await;
        let before = current_business_json(&thread).await;
        resume.request.cancellation.cancel();
        assert!(
            matches!(
                enter_resume(&thread, &resume, entry, CancellationToken::new()).await,
                Err(pl_core::thread::ThreadError::InvalidIdentity)
            ),
            "cancelled original qualification must reject {entry:?}"
        );
        assert_eq!(session.counts(), (0, 0));
        assert_eq!(current_business_json(&thread).await, before);
        thread
            .step(StepInput {
                turn_id: "fresh-direct".into(),
                attempt_id: uuid::Uuid::new_v4().to_string(),
                content: vec![text("new direct authorization")],
                cancellation: CancellationToken::new(),
            })
            .await
            .unwrap();
        assert_eq!(session.counts(), (1, 1));
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn current_resume_cancellation_during_prepare_and_streaming_reaches_the_producer() {
    use std::time::Duration;
    for entry in [ResumeEntry::Step, ResumeEntry::Turn, ResumeEntry::Resume] {
        for streaming in [false, true] {
            for cancel_original in [true, false] {
                let session = ProducerSession::new();
                if streaming {
                    session.prepare_release.notify_one();
                }
                let (thread, resume) = selected_resume(session.clone(), false).await;
                let original = resume.request.cancellation.clone();
                let caller = CancellationToken::new();
                let mut run = tokio::spawn({
                    let thread = thread.clone();
                    let caller = caller.clone();
                    async move { enter_resume(&thread, &resume, entry, caller).await }
                });
                tokio::time::timeout(Duration::from_secs(2), session.prepare_entered.notified())
                    .await
                    .unwrap();
                if streaming {
                    tokio::time::timeout(Duration::from_secs(2), wait_running(&thread))
                        .await
                        .unwrap();
                }
                if cancel_original {
                    original.cancel();
                } else {
                    caller.cancel();
                }
                let completed = tokio::time::timeout(Duration::from_secs(2), &mut run).await;
                if completed.is_err() {
                    // Retain and join the actual work even when the regression fails to cancel it.
                    thread.interrupt();
                    let _ = run.await;
                    thread.close().await.unwrap();
                    panic!(
                        "cancellation did not reach {entry:?}, streaming={streaming}, original={cancel_original}"
                    );
                }
                let cancelled = match completed.unwrap().unwrap() {
                    Err(pl_core::thread::ThreadError::Cancelled) => true,
                    Err(pl_core::thread::ThreadError::Model(error)) => {
                        error.kind == ModelFailureKind::Cancelled
                    }
                    _ => false,
                };
                assert!(cancelled);
                assert_eq!(original.is_cancelled(), cancel_original);
                assert_eq!(caller.is_cancelled(), !cancel_original);
                assert_eq!(thread.snapshot().model_execution, None);
                let current = thread
                    .capture_current(CancellationToken::new())
                    .await
                    .unwrap();
                current.validate(&current.thread_id).unwrap();
                if streaming {
                    assert!(matches!(current.model_call.unwrap().phase,
                        SavedModelPhase::Streaming { stream } if stream.content() == "last complete accepted stream"));
                }
                thread.close().await.unwrap();
            }
        }
    }
}

#[tokio::test]
async fn current_resume_cancellation_racing_turn_admission_never_dispatches_the_model() {
    use std::time::Duration;
    for entry in [ResumeEntry::Turn, ResumeEntry::Resume] {
        let session = RecordingSession::new(FirstReply::Succeed);
        let gate = pl_core::thread::admission::TurnAdmissionGate::new();
        let hold = gate.close();
        let thread = ThreadHandle::restore_current_with_turn_admission_gate(
            ThreadCurrent::new("admission-cancel".into(), RuntimeEpoch::new()),
            Some(DynModelSession::new(session.clone())),
            gate,
        )
        .unwrap();
        let resume = thread
            .prepare_current_resume("selected".into(), |_| Ok(()))
            .await
            .unwrap();
        let original = resume.request.cancellation.clone();
        let mut run = tokio::spawn({
            let thread = thread.clone();
            async move { enter_resume(&thread, &resume, entry, CancellationToken::new()).await }
        });
        tokio::time::timeout(Duration::from_secs(2), async {
            let mut snapshots = thread.subscribe();
            while thread
                .snapshot()
                .execution
                .as_ref()
                .is_none_or(|execution| {
                    execution.phase != pl_core::thread::ExecutionPhase::AwaitingAdmission
                })
            {
                snapshots.next().await.unwrap();
            }
        })
        .await
        .unwrap();
        original.cancel();
        drop(hold);
        let completed = tokio::time::timeout(Duration::from_secs(2), &mut run).await;
        if completed.is_err() {
            thread.interrupt();
            let _ = run.await;
            thread.close().await.unwrap();
            panic!("cancelled admission did not settle for {entry:?}");
        }
        assert!(matches!(
            completed.unwrap().unwrap(),
            Err(pl_core::thread::ThreadError::Cancelled)
        ));
        assert_eq!(session.counts(), (0, 0));
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn empty_current_resume_turn_preserves_ready_outcome_bytes_and_never_calls_validator() {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("invalid-resume".into(), epoch);
    saved.model_call = Some(saved_call(
        epoch,
        SavedModelPhase::ReadyToApply {
            output: output("old-attempt", 0),
        },
    ));
    let thread = ThreadHandle::restore_current(saved, None).unwrap();
    let before = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert!(before.state.context.records.is_empty());
    assert_eq!(before.state.usage_summary.totals.inference_count, 0);
    let validations = std::sync::atomic::AtomicUsize::new(0);
    assert!(matches!(
        thread
            .prepare_current_resume(String::new(), |_| {
                validations.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Ok(())
            })
            .await,
        Err(CurrentError::InvalidIdentity)
    ));
    let mut after = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    // Capture time is the observation's wall clock, not a logical-current mutation.
    after.saved_at = before.saved_at;
    assert_eq!(
        serde_json::to_vec(&after).unwrap(),
        serde_json::to_vec(&before).unwrap()
    );
    assert_eq!(validations.load(std::sync::atomic::Ordering::SeqCst), 0);
    assert!(matches!(
        after.model_call.unwrap().phase,
        SavedModelPhase::ReadyToApply { .. }
    ));
    thread.close().await.unwrap();
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FrozenReply {
    Confirm,
    Missing,
    Wrong,
    Reject,
    LocalCapacity,
    RemoteCapacity,
}

#[derive(Debug, Clone)]
struct FrozenSession {
    mode: Arc<std::sync::Mutex<FrozenReply>>,
    requests: Arc<std::sync::Mutex<Vec<ModelRequest>>>,
    executions: Arc<std::sync::atomic::AtomicUsize>,
    entered: Arc<Notify>,
    release: Option<Arc<Notify>>,
}

impl FrozenSession {
    fn new(mode: FrozenReply) -> Self {
        Self {
            mode: Arc::new(std::sync::Mutex::new(mode)),
            requests: Default::default(),
            executions: Default::default(),
            entered: Default::default(),
            release: None,
        }
    }
    fn counts(&self) -> (usize, usize) {
        (
            self.requests.lock().unwrap().len(),
            self.executions.load(std::sync::atomic::Ordering::SeqCst),
        )
    }
}

impl ModelSession for FrozenSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let first = {
            let mut requests = self.requests.lock().unwrap();
            let first = requests.is_empty();
            requests.push(request.clone());
            first
        };
        let mode = *self.mode.lock().unwrap();
        self.entered.notify_one();
        if mode == FrozenReply::Reject
            && let Some(release) = &self.release
        {
            tokio::select! {
                () = release.notified() => {},
                () = request.cancellation.cancelled() => return Err(ModelError { kind: ModelFailureKind::Cancelled, details: None, usage: Default::default(), source: None }),
            }
        }
        if mode == FrozenReply::Reject || (first && mode == FrozenReply::LocalCapacity) {
            return Err(ModelError {
                kind: if mode == FrozenReply::Reject {
                    ModelFailureKind::IncompatibleContext
                } else {
                    ModelFailureKind::ContextLimit
                },
                details: None,
                usage: Default::default(),
                source: None,
            });
        }
        let expected = request.recovery_parameters.clone();
        let executions = self.executions.clone();
        let mut prepared = PreparedModelCall::new_with_current(async move {
            executions.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            let result = if first && mode == FrozenReply::RemoteCapacity {
                Err(ModelError {
                    kind: ModelFailureKind::ContextLimit,
                    details: None,
                    usage: Default::default(),
                    source: None,
                })
            } else {
                let mut result = output(&request.attempt_id, request.context.revision);
                if request.recovery_parameters.is_some()
                    && matches!(mode, FrozenReply::Missing | FrozenReply::Wrong)
                {
                    result.tool_calls.push(call("must-not-run"));
                }
                Ok(result)
            };
            ModelCallExit {
                result,
                current: Some(OpaquePayload::text("complete frozen-model stream")),
            }
        })
        .with_request_metadata(OpaquePayload::text(
            "different currently configured options",
        ));
        if let Some(expected) = expected {
            prepared = match mode {
                FrozenReply::Missing => prepared,
                FrozenReply::Wrong => {
                    prepared.with_applied_recovery_parameters(OpaquePayload::text("wrong options"))
                }
                _ => prepared.with_applied_recovery_parameters(expected),
            };
        }
        Ok(prepared)
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

async fn frozen_owner(
    session: FrozenSession,
    phase: SavedModelPhase,
    parameters: Option<OpaquePayload>,
) -> (ThreadHandle, Arc<std::sync::atomic::AtomicUsize>) {
    let epoch = RuntimeEpoch::new();
    let mut saved = ThreadCurrent::new("frozen-owner".into(), epoch);
    let mut saved_model = saved_call(epoch, phase);
    saved_model.prepared_parameters = parameters;
    let tools = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let registration =
        pl_core::tool::opaque::Registration::prepare("tool".into(), OpaquePayload::text("tool"))
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(
                KnownBeforeCommitTool(tools.clone()),
            ));
    saved_model.tools = vec![registration.declaration().clone()].into();
    saved.model_call = Some(saved_model);
    let thread = ThreadHandle::restore_current(saved, Some(DynModelSession::new(session))).unwrap();
    thread.register_tools(vec![registration]).await.unwrap();
    (thread, tools)
}

fn original_parameters() -> OpaquePayload {
    OpaquePayload::new(
        "test.saved-model-options",
        1,
        "original account / model / hosted tools",
    )
    .unwrap()
}

#[tokio::test]
async fn frozen_parameters_use_owner_facts_and_ignore_public_proposal_edits() {
    let session = FrozenSession::new(FrozenReply::Confirm);
    let parameters = original_parameters();
    let (thread, _) = frozen_owner(
        session.clone(),
        SavedModelPhase::Streaming {
            stream: OpaquePayload::text("old complete stream"),
        },
        Some(parameters.clone()),
    )
    .await;
    let mut resume = thread
        .prepare_current_resume("bound".into(), |_| Ok(()))
        .await
        .unwrap();
    resume.prepared_parameters = Some(OpaquePayload::text("forged proposal"));
    resume.request.recovery_parameters = Some(OpaquePayload::text("forged model request"));
    thread
        .execute_current_resume(resume, ModelStepLimit::Limited(1.try_into().unwrap()))
        .await
        .unwrap();
    assert_eq!(session.counts(), (1, 1));
    assert_eq!(
        session.requests.lock().unwrap()[0]
            .recovery_parameters
            .as_ref(),
        Some(&parameters)
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn frozen_parameters_refuse_unconfirmed_mismatched_and_incompatible_producers_without_dispatch()
 {
    for mode in [
        FrozenReply::Missing,
        FrozenReply::Wrong,
        FrozenReply::Reject,
    ] {
        for phase in [
            SavedModelPhase::Preparing {
                pending_step_input: Some(PendingStepInput {
                    content: vec![text("saved input once")],
                }),
            },
            SavedModelPhase::Streaming {
                stream: OpaquePayload::text("original full stream"),
            },
            SavedModelPhase::ReadyToApply {
                output: output("old-attempt", 0),
            },
        ] {
            let session = FrozenSession::new(mode);
            let parameters = if mode == FrozenReply::Reject {
                OpaquePayload::new("unknown.provider.options", 99, "unknown source account")
                    .unwrap()
            } else {
                original_parameters()
            };
            let (thread, tools) =
                frozen_owner(session.clone(), phase.clone(), Some(parameters.clone())).await;
            let resume = thread
                .prepare_current_resume("refused".into(), |_| Ok(()))
                .await
                .unwrap();
            assert!(
                matches!(thread.execute_current_resume(resume.clone(), ModelStepLimit::Limited(1.try_into().unwrap())).await,
                Err(pl_core::thread::ThreadError::Model(ref error)) if error.kind == ModelFailureKind::IncompatibleContext)
            );
            assert_eq!(session.counts(), (1, 0));
            assert_eq!(tools.load(std::sync::atomic::Ordering::SeqCst), 0);
            let current = thread
                .capture_current(CancellationToken::new())
                .await
                .unwrap();
            current.validate(&current.thread_id).unwrap();
            let saved = current.model_call.as_ref().unwrap();
            assert_eq!(saved.prepared_parameters.as_ref(), Some(&parameters));
            assert_eq!(saved.source_attempt_id, "old-attempt");
            match &phase {
                SavedModelPhase::Preparing { .. } => assert_eq!(
                    current
                        .state
                        .context
                        .records
                        .iter()
                        .filter(|record| record.content == vec![text("saved input once")])
                        .count(),
                    1
                ),
                SavedModelPhase::Streaming { stream } => assert!(
                    matches!(&saved.phase, SavedModelPhase::Streaming { stream: actual } if actual == stream)
                ),
                SavedModelPhase::ReadyToApply { .. } => {
                    assert!(matches!(saved.phase, SavedModelPhase::Applied));
                    assert_eq!(current.state.usage_summary.totals.inference_count, 1);
                }
                _ => unreachable!(),
            }
            assert!(matches!(
                thread
                    .step(StepInput {
                        turn_id: "bypass".into(),
                        attempt_id: uuid::Uuid::new_v4().to_string(),
                        content: vec![],
                        cancellation: CancellationToken::new()
                    })
                    .await,
                Err(pl_core::thread::ThreadError::CurrentPaused)
            ));
            assert!(matches!(
                thread
                    .execute_current_resume(resume.clone(), ModelStepLimit::Unlimited)
                    .await,
                Err(pl_core::thread::ThreadError::InvalidIdentity)
            ));
            resume.request.cancellation.cancel();
            *session.mode.lock().unwrap() = FrozenReply::Confirm;
            let retry = thread
                .prepare_current_resume("compatible-retry".into(), |_| Ok(()))
                .await
                .unwrap();
            assert!(matches!(
                thread.step(resume_step(&resume)).await,
                Err(pl_core::thread::ThreadError::InvalidIdentity)
            ));
            thread
                .execute_current_resume(retry, ModelStepLimit::Limited(1.try_into().unwrap()))
                .await
                .unwrap();
            assert_eq!(session.counts(), (2, 1));
            assert_eq!(tools.load(std::sync::atomic::Ordering::SeqCst), 0);
            assert_eq!(
                session.requests.lock().unwrap()[1]
                    .recovery_parameters
                    .as_ref(),
                Some(&parameters)
            );
            let after = thread
                .capture_current(CancellationToken::new())
                .await
                .unwrap();
            if matches!(&phase, SavedModelPhase::Preparing { .. }) {
                assert_eq!(
                    after
                        .state
                        .context
                        .records
                        .iter()
                        .filter(|record| record.content == vec![text("saved input once")])
                        .count(),
                    1
                );
            }
            thread.close().await.unwrap();
        }
    }
}

#[tokio::test]
async fn frozen_parameters_failure_keeps_late_input_and_retry_does_not_reapply_saved_outcome() {
    let mut session = FrozenSession::new(FrozenReply::Reject);
    let release = Arc::new(Notify::new());
    session.release = Some(release.clone());
    let (thread, tools) = frozen_owner(
        session.clone(),
        SavedModelPhase::ReadyToApply {
            output: output("old-attempt", 0),
        },
        Some(original_parameters()),
    )
    .await;
    let resume = thread
        .prepare_current_resume("first".into(), |_| Ok(()))
        .await
        .unwrap();
    let stale = resume.clone();
    let run = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .execute_current_resume(resume, ModelStepLimit::Unlimited)
                .await
        }
    });
    session.entered.notified().await;
    thread
        .submit_input(input::ThreadInput {
            id: "late-input".into(),
            purpose: input::InputPurpose::Message,
            payload: OpaquePayload::text("late complete input"),
            context: vec![text("late input")],
        })
        .await
        .unwrap();
    thread
        .send_message(pl_core::thread::inbox::ThreadMessage {
            id: "late-message".into(),
            source_id: "host".into(),
            kind: pl_core::context::AgentMessageKind::Report,
            payload: OpaquePayload::text("late complete inbox"),
            context: vec![text("late inbox")],
        })
        .await
        .unwrap();
    release.notify_one();
    assert!(run.await.unwrap().is_err());
    let paused = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(paused.state.inputs.len(), 1);
    assert_eq!(paused.state.inbox.len(), 1);
    assert_eq!(paused.state.usage_summary.totals.inference_count, 1);
    stale.request.cancellation.cancel();
    *session.mode.lock().unwrap() = FrozenReply::Confirm;
    let retry = thread
        .prepare_current_resume("retry".into(), |_| Ok(()))
        .await
        .unwrap();
    assert!(!retry.request.cancellation.is_cancelled());
    assert!(matches!(
        thread.step(resume_step(&stale)).await,
        Err(pl_core::thread::ThreadError::InvalidIdentity)
    ));
    thread
        .execute_current_resume(retry, ModelStepLimit::Limited(1.try_into().unwrap()))
        .await
        .unwrap();
    assert_eq!(session.counts(), (2, 1));
    assert_eq!(tools.load(std::sync::atomic::Ordering::SeqCst), 0);
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(current.state.usage_summary.totals.inference_count, 2);
    for body in ["late input", "late inbox"] {
        assert_eq!(
            current
                .state
                .context
                .records
                .iter()
                .filter(|record| record.content == vec![text(body)])
                .count(),
            1
        );
    }
    thread.close().await.unwrap();
}

#[derive(Debug, Clone, Default)]
struct FrozenPreparations {
    requests: Arc<std::sync::Mutex<Vec<ModelRequest>>>,
    recovery: RecoveryAttempts,
}
impl pl_core::thread::context_preparation::ContextPreparationHook for FrozenPreparations {
    async fn before_step(
        &self,
        request: pl_core::thread::context_preparation::ContextPreparationRequest,
    ) -> pl_core::thread::context_preparation::ContextPreparation {
        self.requests.lock().unwrap().push(request.model.clone());
        pl_core::thread::context_preparation::ContextPreparationHook::before_step(
            &self.recovery,
            request,
        )
        .await
    }
}

#[tokio::test]
async fn frozen_parameters_survive_local_and_service_capacity_preparation() {
    for mode in [FrozenReply::LocalCapacity, FrozenReply::RemoteCapacity] {
        let session = FrozenSession::new(mode);
        let parameters = original_parameters();
        let (thread, _) = frozen_owner(
            session.clone(),
            SavedModelPhase::Preparing {
                pending_step_input: Some(PendingStepInput {
                    content: vec![text("capacity input once")],
                }),
            },
            Some(parameters.clone()),
        )
        .await;
        let preparation = FrozenPreparations::default();
        thread
            .set_context_preparation(Some(
                pl_core::thread::context_preparation::ContextPreparer::new(preparation.clone()),
            ))
            .await
            .unwrap();
        let resume = thread
            .prepare_current_resume("capacity".into(), |_| Ok(()))
            .await
            .unwrap();
        thread
            .execute_current_resume(resume, ModelStepLimit::Limited(2.try_into().unwrap()))
            .await
            .unwrap();
        assert_eq!(
            session.counts(),
            (
                2,
                if mode == FrozenReply::LocalCapacity {
                    1
                } else {
                    2
                }
            )
        );
        for request in session
            .requests
            .lock()
            .unwrap()
            .iter()
            .chain(preparation.requests.lock().unwrap().iter())
        {
            assert_eq!(request.recovery_parameters.as_ref(), Some(&parameters));
        }
        assert!(
            preparation
                .recovery
                .0
                .lock()
                .unwrap()
                .iter()
                .any(|(forced, _)| *forced)
        );
        let current = thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(
            current
                .state
                .context
                .records
                .iter()
                .filter(|record| record.content == vec![text("capacity input once")])
                .count(),
            1
        );
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn frozen_parameters_are_absent_for_ordinary_requests_and_unfrozen_preparing_resume() {
    for current in [false, true] {
        let session = FrozenSession::new(FrozenReply::Missing);
        let model = DynModelSession::new(session.clone());
        let thread = if current {
            ThreadHandle::start_current("ordinary".into(), model).unwrap()
        } else {
            ThreadHandle::start("ordinary".into(), model).unwrap()
        };
        thread
            .run_turn(TurnInput {
                turn_id: "ordinary".into(),
                attempt_prefix: "prefix".into(),
                content: vec![text("ordinary input")],
                max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                cancellation: CancellationToken::new(),
            })
            .await
            .unwrap();
        assert_eq!(session.counts(), (1, 1));
        assert!(
            session.requests.lock().unwrap()[0]
                .recovery_parameters
                .is_none()
        );
        thread.close().await.unwrap();
    }
    let session = FrozenSession::new(FrozenReply::Missing);
    let (thread, _) = frozen_owner(
        session.clone(),
        SavedModelPhase::Preparing {
            pending_step_input: Some(PendingStepInput {
                content: vec![text("not frozen yet")],
            }),
        },
        None,
    )
    .await;
    let resume = thread
        .prepare_current_resume("unfrozen".into(), |_| Ok(()))
        .await
        .unwrap();
    thread
        .execute_current_resume(resume, ModelStepLimit::Limited(1.try_into().unwrap()))
        .await
        .unwrap();
    assert_eq!(session.counts(), (1, 1));
    assert!(
        session.requests.lock().unwrap()[0]
            .recovery_parameters
            .is_none()
    );
    thread.close().await.unwrap();
    let session = FrozenSession::new(FrozenReply::Missing);
    let idle = ThreadHandle::restore_current(
        ThreadCurrent::new("truly-idle".into(), RuntimeEpoch::new()),
        Some(DynModelSession::new(session.clone())),
    )
    .unwrap();
    let resume = idle
        .prepare_current_resume("new-idle-work".into(), |_| Ok(()))
        .await
        .unwrap();
    assert!(resume.request.recovery_parameters.is_none());
    idle.execute_current_resume(resume, ModelStepLimit::Limited(1.try_into().unwrap()))
        .await
        .unwrap();
    assert_eq!(session.counts(), (1, 1));
    assert!(
        session.requests.lock().unwrap()[0]
            .recovery_parameters
            .is_none()
    );
    idle.close().await.unwrap();
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
    for pending in [true, false] {
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
            continuation: None,
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
            if pending {
                SavedModelPhase::Preparing {
                    pending_step_input: Some(PendingStepInput {
                        content: contents("pending"),
                    }),
                }
            } else {
                let mut result = output("old-attempt", 1);
                result.content = contents("outcome");
                SavedModelPhase::ReadyToApply { output: result }
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
            if pending { "pending" } else { "outcome" },
        ];
        expected.sort();
        assert_eq!(actual, expected);
    }
}

#[tokio::test]
async fn started_calls_without_frozen_parameters_remain_readable_but_cannot_resume() {
    for phase in [
        SavedModelPhase::Streaming {
            stream: OpaquePayload::text("saved source unknown"),
        },
        SavedModelPhase::ReadyToApply {
            output: output("old-attempt", 0),
        },
        SavedModelPhase::Applied,
    ] {
        let session = FrozenSession::new(FrozenReply::Confirm);
        let (thread, tools) = frozen_owner(session.clone(), phase.clone(), None).await;
        let before = thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap();
        let mut readonly =
            ThreadCurrent::from_json(&serde_json::to_vec(&before).unwrap(), "frozen-owner")
                .unwrap();
        let validations = std::sync::atomic::AtomicUsize::new(0);
        let result = thread
            .prepare_current_resume("unknown-source".into(), |_| {
                validations.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Ok(())
            })
            .await;
        let blocked = match result {
            Err(CurrentError::Model(error)) => error.kind == ModelFailureKind::IncompatibleContext,
            Ok(resume) => {
                // Demonstrate the wrong-model consequence on the unfixed implementation.
                thread
                    .execute_current_resume(resume, ModelStepLimit::Limited(1.try_into().unwrap()))
                    .await
                    .unwrap();
                false
            }
            Err(error) => panic!("unexpected resume error: {error}"),
        };
        let counts = session.counts();
        if !blocked {
            thread.close().await.unwrap();
            panic!(
                "started call without source parameters dispatched current configuration: {counts:?}"
            );
        }
        assert_eq!(counts, (0, 0));
        assert_eq!(validations.load(std::sync::atomic::Ordering::SeqCst), 0);
        assert_eq!(tools.load(std::sync::atomic::Ordering::SeqCst), 0);
        let after = thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap();
        assert!(
            after
                .model_call
                .as_ref()
                .unwrap()
                .prepared_parameters
                .is_none()
        );
        ThreadCurrent::from_json(&serde_json::to_vec(&after).unwrap(), "frozen-owner").unwrap();
        if matches!(phase, SavedModelPhase::ReadyToApply { .. }) {
            assert!(matches!(
                after.model_call.as_ref().unwrap().phase,
                SavedModelPhase::Applied
            ));
            assert_eq!(after.state.usage_summary.totals.inference_count, 1);
            assert!(
                thread
                    .prepare_current_resume("still-unknown".into(), |_| Ok(()))
                    .await
                    .is_err()
            );
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
        }
        assert!(matches!(
            thread
                .step(StepInput {
                    turn_id: "fresh-bypass".into(),
                    attempt_id: uuid::Uuid::new_v4().to_string(),
                    content: vec![],
                    cancellation: CancellationToken::new()
                })
                .await,
            Err(pl_core::thread::ThreadError::CurrentPaused)
        ));
        let identity = ExecutionIdentity::new(readonly.saved_runtime_epoch, "pure-api".into());
        assert!(
            matches!(readonly.prepare_after_user_resume(identity, |_| Ok(())), Err(CurrentError::Model(error)) if error.kind == ModelFailureKind::IncompatibleContext)
        );
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn replaced_claim_cannot_lend_parameters_to_fresh_same_turn_work() {
    for stop in [false, true] {
        for preparation_failure in [false, true] {
            let session = FrozenSession::new(if preparation_failure {
                FrozenReply::LocalCapacity
            } else {
                FrozenReply::Confirm
            });
            let (thread, _) = frozen_owner(
                session.clone(),
                SavedModelPhase::Streaming {
                    stream: OpaquePayload::text("old stream"),
                },
                Some(original_parameters()),
            )
            .await;
            let resume = thread
                .prepare_current_resume("same-turn".into(), |_| Ok(()))
                .await
                .unwrap();
            if stop {
                thread
                    .interrupt_execution(resume.execution_id.clone())
                    .await
                    .unwrap();
            } else {
                resume.request.cancellation.cancel();
            }
            let fresh_attempt = uuid::Uuid::new_v4().to_string();
            let result = thread
                .step(StepInput {
                    turn_id: resume.request.turn_id.clone(),
                    attempt_id: fresh_attempt.clone(),
                    content: vec![text("fresh same-turn input")],
                    cancellation: CancellationToken::new(),
                })
                .await;
            if preparation_failure {
                assert!(
                    matches!(result, Err(pl_core::thread::ThreadError::Model(error)) if error.kind == ModelFailureKind::ContextLimit)
                );
            } else {
                result.unwrap();
            }
            assert!(
                session.requests.lock().unwrap()[0]
                    .recovery_parameters
                    .is_none(),
                "fresh work inherited the revoked claim's model configuration"
            );
            if preparation_failure {
                let current = thread
                    .capture_current(CancellationToken::new())
                    .await
                    .unwrap();
                assert_eq!(
                    current.model_call.as_ref().unwrap().source_attempt_id,
                    fresh_attempt
                );
                assert!(
                    current
                        .model_call
                        .as_ref()
                        .unwrap()
                        .prepared_parameters
                        .is_none()
                );
                thread
                    .step(StepInput {
                        turn_id: resume.request.turn_id.clone(),
                        attempt_id: uuid::Uuid::new_v4().to_string(),
                        content: vec![text("fresh same-turn input")],
                        cancellation: CancellationToken::new(),
                    })
                    .await
                    .unwrap();
                assert!(
                    session.requests.lock().unwrap()[1]
                        .recovery_parameters
                        .is_none()
                );
            }
            assert!(matches!(
                thread
                    .execute_current_resume(resume, ModelStepLimit::Unlimited)
                    .await,
                Err(pl_core::thread::ThreadError::InvalidIdentity)
            ));
            thread.close().await.unwrap();
        }
    }
}
