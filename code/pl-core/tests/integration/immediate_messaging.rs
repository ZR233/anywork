use crate::{preparation, support};

use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use pl_agent_tool::Tool;
use pl_core::{
    context::{ContextSnapshot, ContextSource, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelFailureKind, ModelProgress, ModelRequest, ModelSession,
        ModelStepOutput, ModelTextChannel, ModelToolCall, ObservedItemKind, ObservedPart,
        ObservedPartIdentity, ObservedPartKind, PreparedModelCall, ProviderPartIdentity,
    },
    thread::{
        ContinuationReason, CoreEvent, CoreEventSink, CoreLiveEvent, ExecutionPhase,
        ModelStepLimit, PreemptedStepPhase, ResumeRequest, ThreadError, ThreadHandle, TurnOutcome,
        TurnState,
        context_preparation::{
            ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
        },
        current::{RuntimeEpoch, ThreadCurrent},
        input::{
            InputChange, InputDriverOptions, InputExecution, InputPurpose, InputState, ThreadInput,
        },
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

use support::{response, text};

fn msg(id: &str, body: &str) -> ThreadInput {
    ThreadInput {
        id: id.into(),
        purpose: InputPurpose::Message,
        payload: OpaquePayload::text(body),
        context: vec![text(body)],
    }
}

fn driver() -> InputDriverOptions {
    InputDriverOptions {
        max_model_steps: ModelStepLimit::Limited(8.try_into().unwrap()),
    }
}

fn provider_output_text(item_id: &str, text_chunk: &str) -> ObservedPart {
    let identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
        item_id: Arc::from(item_id),
        output_index: Some(0),
        item_kind: ObservedItemKind::Text(ModelTextChannel::Commentary),
        part: ObservedPartKind::OutputText,
        content_index: 0,
    });
    ObservedPart::new(identity).appended(text_chunk)
}

async fn wait_for(thread: &ThreadHandle, pred: impl Fn(&pl_core::thread::ThreadSnapshot) -> bool) {
    if pred(&thread.snapshot()) {
        return;
    }
    let mut updates = thread.subscribe();
    tokio::time::timeout(Duration::from_secs(5), async {
        while let Some(snapshot) = updates.next().await {
            if pred(&snapshot) {
                return;
            }
        }
        panic!("thread closed before condition became true");
    })
    .await
    .expect("timed out waiting for snapshot condition");
}

#[tokio::test]
async fn streaming_soft_preemption_preserves_partial_text_and_keeps_same_turn() {
    struct StreamingPreemptModel {
        requests: Arc<Mutex<Vec<ContextSnapshot>>>,
        streaming_started: Arc<Notify>,
        calls: std::sync::atomic::AtomicUsize,
    }

    impl ModelSession for StreamingPreemptModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            self.requests.lock().unwrap().push(request.context.clone());
            let idx = self.calls.fetch_add(1, Ordering::SeqCst);
            let started = self.streaming_started.clone();
            Ok(PreparedModelCall::new(async move {
                if idx == 0 {
                    if let Some(progress) = &request.progress {
                        progress.publish(ModelProgress::new(
                            1,
                            vec![provider_output_text("item-stream-0", "First half...")],
                        ));
                    }
                    started.notify_one();
                    request.cancellation.cancelled().await;
                    return Err(ModelError {
                        context_recovery: None,
                        details: None,
                        kind: ModelFailureKind::Cancelled,
                        usage: Default::default(),
                        source: None,
                    });
                }
                Ok(response(&request, Vec::new()))
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    let requests = Arc::new(Mutex::new(Vec::new()));
    let streaming_started = Arc::new(Notify::new());
    let thread = ThreadHandle::start(
        "stream-preempt".into(),
        DynModelSession::new(StreamingPreemptModel {
            requests: requests.clone(),
            streaming_started: streaming_started.clone(),
            calls: Default::default(),
        }),
    )
    .unwrap();

    thread
        .submit_input(msg("m1", "Tell a long story"), Some(driver()))
        .await
        .unwrap();
    streaming_started.notified().await;
    thread
        .submit_input(msg("m2", "Pivot immediately"), Some(driver()))
        .await
        .unwrap();

    wait_for(&thread, |s| s.execution.is_none() && s.inputs.is_empty()).await;
    let snapshot = thread.snapshot();
    assert!(snapshot.continuation.is_none());

    let effects = thread.effects().await.unwrap();
    let turns: Vec<_> = effects.iter().filter_map(|e| e.turn.as_ref()).collect();
    assert!(
        turns.iter().all(|t| t.turn_id == turns[0].turn_id),
        "soft preemption must stay in one Turn"
    );
    assert_eq!(
        turns.last().unwrap().state,
        TurnState::Finished(TurnOutcome::Completed)
    );
    let preemptions: Vec<_> = effects
        .iter()
        .flat_map(|e| e.step_preemptions.iter().cloned())
        .collect();
    assert_eq!(preemptions.len(), 1);
    assert_eq!(preemptions[0].phase, PreemptedStepPhase::Streaming);
    assert_eq!(preemptions[0].trigger_input_ids, vec!["m2".to_string()]);
    assert!(
        preemptions[0]
            .partial_record_id
            .as_deref()
            .is_some_and(|id| id.ends_with(":partial"))
    );

    let m2_injected = effects.iter().flat_map(|e| e.inputs.iter()).any(|change| {
        matches!(
            change,
            InputChange::Transition {
                id,
                injected_mid_turn: true,
                context_record_id: Some(rec_id),
                state: InputState::Consumed { .. },
                ..
            } if id == "m2" && rec_id == "input:m2"
        )
    });
    assert!(
        m2_injected,
        "m2 consumption must mark injected_mid_turn = true"
    );

    {
        let locked = requests.lock().unwrap();
        let second_req = &locked[1];
        let roles: Vec<_> = second_req
            .records
            .iter()
            .map(|r| (&r.id, &r.source, r.tool_calls.is_empty()))
            .collect();
        assert_eq!(roles.len(), 3);
        assert!(second_req.records[0].id == "input:m1");
        assert!(matches!(
            second_req.records[1].source,
            ContextSource::Assistant
        ));
        assert!(second_req.records[1].tool_calls.is_empty());
        assert_eq!(second_req.records[1].content, vec![text("First half...")]);
        assert!(second_req.records[2].id == "input:m2");
    }
    thread.close().await.unwrap();
}

#[tokio::test]
async fn preparing_soft_preemption_emits_preparing_event_and_merges_fifo_without_empty_partial() {
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("prep-preempt".into(), DynModelSession::new(model)).unwrap();
    let hold = preparation::HoldPreparation::install(&thread).await;

    thread
        .submit_input(msg("m1", "First message"), Some(driver()))
        .await
        .unwrap();
    hold.entered().await;
    thread
        .submit_input(msg("m2", "Second message"), Some(driver()))
        .await
        .unwrap();

    wait_for(&thread, |s| s.execution.is_none() && s.inputs.is_empty()).await;
    let effects = thread.effects().await.unwrap();
    let preemptions: Vec<_> = effects
        .iter()
        .flat_map(|e| e.step_preemptions.iter().cloned())
        .collect();
    assert_eq!(preemptions.len(), 1);
    assert_eq!(preemptions[0].phase, PreemptedStepPhase::Preparing);
    assert_eq!(preemptions[0].trigger_input_ids, vec!["m2".to_string()]);
    assert!(preemptions[0].partial_record_id.is_none());

    {
        let reqs = requests.lock().unwrap();
        assert_eq!(reqs.len(), 1);
        let user_records: Vec<_> = reqs[0]
            .records
            .iter()
            .filter(|r| matches!(r.source, ContextSource::User))
            .collect();
        assert_eq!(user_records.len(), 2);
        assert_eq!(user_records[0].id, "input:m1");
        assert_eq!(user_records[0].content, vec![text("First message")]);
        assert_eq!(user_records[1].id, "input:m2");
        assert_eq!(user_records[1].content, vec![text("Second message")]);
        assert!(!reqs[0].records.iter().any(|r| r.id.ends_with(":partial")));
    }
    thread.close().await.unwrap();
}

#[tokio::test]
async fn tool_batch_injection_does_not_cancel_running_tool_and_continues_same_turn() {
    struct SlowTool {
        started: Arc<Notify>,
        release: Arc<Notify>,
        was_cancelled: Arc<AtomicBool>,
    }

    impl Tool for SlowTool {
        type Input = OpaquePayload;
        type Context = CallContext;
        type Output = ToolOutput;
        type Error = ToolError;

        fn definition(&self) -> &pl_agent_tool::ToolDefinition {
            static DEF: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
                std::sync::LazyLock::new(|| {
                    pl_agent_tool::ToolDefinition::text("slow", "slow tool").unwrap()
                });
            &DEF
        }

        async fn execute(
            &self,
            _: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            self.started.notify_one();
            tokio::select! {
                _ = self.release.notified() => {}
                _ = context.cancellation.cancelled() => {
                    self.was_cancelled.store(true, Ordering::SeqCst);
                    return Err(ToolError::new(ThreadError::Cancelled));
                }
            }
            Ok(ToolOutput::new(
                OpaquePayload::text("ok"),
                vec![text("slow completed cleanly")],
            ))
        }
    }

    let (model, requests) = support::ScriptedModel::new(&["slow"]);
    let started = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let was_cancelled = Arc::new(AtomicBool::new(false));
    let thread = ThreadHandle::start("tool-inject".into(), DynModelSession::new(model)).unwrap();
    thread
        .register_tools(vec![
            Registration::prepare("slow".into(), OpaquePayload::text("slow"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(SlowTool {
                    started: started.clone(),
                    release: release.clone(),
                    was_cancelled: was_cancelled.clone(),
                })),
        ])
        .await
        .unwrap();

    thread
        .submit_input(msg("m1", "Run slow tool"), Some(driver()))
        .await
        .unwrap();
    started.notified().await;
    thread
        .submit_input(msg("m2", "Use slow output too"), Some(driver()))
        .await
        .unwrap();
    tokio::task::yield_now().await;
    assert!(
        !was_cancelled.load(Ordering::SeqCst),
        "immediate input during ToolBatch must not cancel regular tools"
    );

    release.notify_one();
    wait_for(&thread, |s| s.execution.is_none() && s.inputs.is_empty()).await;
    assert!(!was_cancelled.load(Ordering::SeqCst));
    let effects = thread.effects().await.unwrap();
    let turns: Vec<_> = effects.iter().filter_map(|e| e.turn.as_ref()).collect();
    assert!(turns.iter().all(|t| t.turn_id == turns[0].turn_id));
    assert_eq!(
        turns.last().unwrap().state,
        TurnState::Finished(TurnOutcome::Completed)
    );

    {
        let reqs = requests.lock().unwrap();
        assert_eq!(reqs.len(), 2);
        let second = &reqs[1].records;
        assert!(second.iter().any(|r| r.id == "input:m2"));
        assert!(
            second
                .iter()
                .any(|r| matches!(r.source, ContextSource::ToolResult { .. }))
        );
    }
    thread.close().await.unwrap();
}

#[tokio::test]
async fn wait_tool_wakes_immediately_on_pending_immediate_input() {
    struct HeldBgTool(Arc<Notify>);
    impl Tool for HeldBgTool {
        type Input = OpaquePayload;
        type Context = CallContext;
        type Output = ToolOutput;
        type Error = ToolError;
        fn definition(&self) -> &pl_agent_tool::ToolDefinition {
            static DEF: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
                std::sync::LazyLock::new(|| {
                    pl_agent_tool::ToolDefinition::text("HeldBgTool", "held").unwrap()
                });
            &DEF
        }
        async fn execute(
            &self,
            input: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            tokio::select! {
                _ = self.0.notified() => {}
                _ = context.cancellation.cancelled() => {
                    return Err(ToolError::new(ThreadError::Cancelled));
                }
            }
            Ok(ToolOutput::new(input, vec![text("bg done")]))
        }
    }

    struct AccessTool {
        started: mpsc::UnboundedSender<pl_core::thread::TaskAccess>,
        release: Arc<Notify>,
    }
    impl Tool for AccessTool {
        type Input = OpaquePayload;
        type Context = CallContext;
        type Output = ToolOutput;
        type Error = ToolError;
        fn definition(&self) -> &pl_agent_tool::ToolDefinition {
            static DEF: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
                std::sync::LazyLock::new(|| {
                    pl_agent_tool::ToolDefinition::text("AccessTool", "access").unwrap()
                });
            &DEF
        }
        async fn execute(
            &self,
            input: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            self.started.send(context.tasks.clone().unwrap()).unwrap();
            tokio::select! {
                _ = self.release.notified() => {}
                _ = context.cancellation.cancelled() => {
                    return Err(ToolError::new(ThreadError::Cancelled));
                }
            }
            Ok(ToolOutput::new(input, vec![text("access done")]))
        }
    }

    // Step 0 emits HeldBgTool (runs > 1s and becomes an async TaskRecord); Step 1 emits AccessTool.
    struct TwoCallModel(std::sync::atomic::AtomicUsize);
    impl ModelSession for TwoCallModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let calls = match self.0.fetch_add(1, Ordering::SeqCst) {
                0 => vec![ModelToolCall {
                    presentation_contract: None,
                    rejection: None,
                    call_id: "bg-1".into(),
                    tool_id: "HeldBgTool".into(),
                    arguments: OpaquePayload::text("bg"),
                }],
                1 => vec![ModelToolCall {
                    presentation_contract: None,
                    rejection: None,
                    call_id: "acc-1".into(),
                    tool_id: "AccessTool".into(),
                    arguments: OpaquePayload::text("acc"),
                }],
                _ => vec![],
            };
            Ok(PreparedModelCall::new(async move {
                Ok(response(&request, calls))
            }))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    let bg_release = Arc::new(Notify::new());
    let access_release = Arc::new(Notify::new());
    let (tx, mut rx) = mpsc::unbounded_channel();
    let thread = ThreadHandle::start(
        "wait-wakeup-2".into(),
        DynModelSession::new(TwoCallModel(std::sync::atomic::AtomicUsize::new(0))),
    )
    .unwrap();
    thread
        .register_tools(vec![
            Registration::prepare("HeldBgTool".into(), OpaquePayload::text("bg"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(HeldBgTool(
                    bg_release.clone(),
                ))),
            Registration::prepare("AccessTool".into(), OpaquePayload::text("access"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(AccessTool {
                    started: tx,
                    release: access_release.clone(),
                }))
                .with_task_waiting(),
        ])
        .await
        .unwrap();
    thread
        .submit_input(msg("m1", "Wait on task"), Some(driver()))
        .await
        .unwrap();
    let access = rx.recv().await.unwrap();
    let task_id = thread
        .snapshot()
        .tasks
        .values()
        .find(|t| t.call_id == "bg-1")
        .unwrap()
        .id
        .clone();
    let waiter = tokio::spawn(async move {
        access
            .wait(
                &[task_id],
                Duration::from_secs(30),
                CancellationToken::new(),
            )
            .await
            .unwrap()
    });
    tokio::task::yield_now().await;
    thread
        .submit_input(msg("m2", "Wake wait tool now"), Some(driver()))
        .await
        .unwrap();
    let waited = tokio::time::timeout(Duration::from_secs(2), waiter)
        .await
        .expect("wait must wake immediately on pending immediate input")
        .unwrap();
    assert!(waited.user_inputs_ready);
    assert!(!waited.timed_out);
    access_release.notify_one();
    bg_release.notify_one();
    wait_for(&thread, |s| s.execution.is_none() && s.inputs.is_empty()).await;
    thread.close().await.unwrap();
}

#[tokio::test]
async fn rapid_multi_message_preserves_strict_fifo_distinct_context_records() {
    #[derive(Debug)]
    struct GatePrep {
        entered: Arc<Notify>,
        release: Arc<Notify>,
        used: AtomicBool,
    }
    impl ContextPreparationHook for GatePrep {
        async fn before_step(&self, _: ContextPreparationRequest) -> ContextPreparation {
            if !self.used.swap(true, Ordering::SeqCst) {
                self.entered.notify_one();
                self.release.notified().await;
            }
            ContextPreparation::Unchanged
        }
    }

    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("fifo-multi".into(), DynModelSession::new(model)).unwrap();
    let entered = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    thread
        .set_context_preparation(Some(ContextPreparer::new(GatePrep {
            entered: entered.clone(),
            release: release.clone(),
            used: AtomicBool::new(false),
        })))
        .await
        .unwrap();

    thread
        .submit_input(msg("m1", "first"), Some(driver()))
        .await
        .unwrap();
    entered.notified().await;
    thread
        .submit_input(msg("m2", "second"), Some(driver()))
        .await
        .unwrap();
    thread
        .submit_input(msg("m3", "third"), Some(driver()))
        .await
        .unwrap();
    release.notify_one();

    wait_for(&thread, |s| s.execution.is_none() && s.inputs.is_empty()).await;
    {
        let reqs = requests.lock().unwrap();
        assert_eq!(reqs.len(), 1);
        let users: Vec<_> = reqs[0]
            .records
            .iter()
            .filter(|r| matches!(r.source, ContextSource::User))
            .collect();
        assert_eq!(
            users.len(),
            3,
            "three rapid inputs must remain 3 distinct records"
        );
        assert_eq!(users[0].id, "input:m1");
        assert_eq!(users[0].content, vec![text("first")]);
        assert_eq!(users[1].id, "input:m2");
        assert_eq!(users[1].content, vec![text("second")]);
        assert_eq!(users[2].id, "input:m3");
        assert_eq!(users[2].content, vec![text("third")]);
    }
    thread.close().await.unwrap();
}

#[tokio::test]
async fn concurrent_input_near_turn_completion_continues_same_turn() {
    struct GateModel {
        requests: Arc<Mutex<Vec<ContextSnapshot>>>,
        entered: Arc<Notify>,
        release: Arc<Notify>,
        calls: std::sync::atomic::AtomicUsize,
    }
    impl ModelSession for GateModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            self.requests.lock().unwrap().push(request.context.clone());
            let idx = self.calls.fetch_add(1, Ordering::SeqCst);
            let entered = self.entered.clone();
            let release = self.release.clone();
            Ok(PreparedModelCall::new(async move {
                if idx == 0 {
                    entered.notify_one();
                    release.notified().await;
                }
                Ok(response(&request, Vec::new()))
            }))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    let requests = Arc::new(Mutex::new(Vec::new()));
    let entered = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let thread = ThreadHandle::start(
        "finish-race".into(),
        DynModelSession::new(GateModel {
            requests: requests.clone(),
            entered: entered.clone(),
            release: release.clone(),
            calls: Default::default(),
        }),
    )
    .unwrap();

    thread
        .submit_input(msg("m1", "initial"), Some(driver()))
        .await
        .unwrap();
    entered.notified().await;
    // Submit m2 and immediately release m1 completion without cancelling (no preempt wait needed).
    thread
        .submit_input(msg("m2", "right at finish"), Some(driver()))
        .await
        .unwrap();
    release.notify_one();

    wait_for(&thread, |s| s.execution.is_none() && s.inputs.is_empty()).await;
    let effects = thread.effects().await.unwrap();
    let turns: Vec<_> = effects.iter().filter_map(|e| e.turn.as_ref()).collect();
    assert!(turns.iter().all(|t| t.turn_id == turns[0].turn_id));
    assert_eq!(
        turns.last().unwrap().state,
        TurnState::Finished(TurnOutcome::Completed)
    );
    {
        let reqs = requests.lock().unwrap();
        assert_eq!(reqs.len(), 2);
        assert!(reqs[1].records.iter().any(|r| r.id == "input:m2"));
    }
    thread.close().await.unwrap();
}

#[tokio::test]
async fn explicit_stop_sets_interrupted_and_resume_continues() {
    struct HeldModel {
        entered: Arc<Notify>,
        calls: std::sync::atomic::AtomicUsize,
    }
    impl ModelSession for HeldModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let idx = self.calls.fetch_add(1, Ordering::SeqCst);
            let entered = self.entered.clone();
            Ok(PreparedModelCall::new(async move {
                if idx == 0 {
                    entered.notify_one();
                    request.cancellation.cancelled().await;
                    return Err(ModelError {
                        context_recovery: None,
                        details: None,
                        kind: ModelFailureKind::Cancelled,
                        usage: Default::default(),
                        source: None,
                    });
                }
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![text("resumed ok")],
                    tool_calls: Vec::new(),
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[derive(Debug, Default)]
    struct StopEventLog(Mutex<Vec<CoreLiveEvent>>);
    impl CoreEventSink for StopEventLog {
        fn emit(&self, event: CoreEvent) {
            if let CoreEvent::Live(live) = event {
                self.0.lock().unwrap().push(live);
            }
        }
    }

    let entered = Arc::new(Notify::new());
    let thread = ThreadHandle::start(
        "explicit-stop".into(),
        DynModelSession::new(HeldModel {
            entered: entered.clone(),
            calls: Default::default(),
        }),
    )
    .unwrap();
    let live_log = Arc::new(StopEventLog::default());
    thread.attach_event_sink(live_log.clone()).await.unwrap();
    thread
        .submit_input(msg("m1", "stop me"), Some(driver()))
        .await
        .unwrap();
    entered.notified().await;
    let exec_id = thread.snapshot().execution.unwrap().id;
    assert!(thread.interrupt_execution(exec_id.clone()).await.unwrap());
    wait_for(&thread, |s| {
        s.execution.is_none() && matches!(s.input_execution, InputExecution::Paused)
    })
    .await;
    assert!(
        live_log.0.lock().unwrap().iter().any(|ev| matches!(
            ev,
            CoreLiveEvent::RunActivity {
                execution: Some(exec)
            } if exec.id == exec_id && exec.phase == ExecutionPhase::Stopping
        )),
        "explicit stop must emit CoreLiveEvent::RunActivity(ExecutionPhase::Stopping)"
    );
    let snap = thread.snapshot();
    let effects = thread.effects().await.unwrap();
    assert!(
        effects.iter().any(|e| {
            e.turn
                .as_ref()
                .is_some_and(|t| t.state == TurnState::Interrupted)
        }),
        "explicit stop must commit TurnState::Interrupted"
    );
    let point = snap.continuation.expect("user stop continuation point");
    assert_eq!(point.reason, Some(ContinuationReason::UserStop));

    thread
        .resume_execution(
            ResumeRequest {
                operation_id: "op-resume-stop".into(),
                expected_continuation_token: point.id,
                request_digest: None,
            },
            driver(),
        )
        .await
        .unwrap();
    wait_for(&thread, |s| {
        s.execution.is_none() && s.continuation.is_none()
    })
    .await;
    let effects = thread.effects().await.unwrap();
    let completed = effects
        .iter()
        .filter_map(|e| e.turn.as_ref())
        .next_back()
        .unwrap();
    assert_eq!(completed.state, TurnState::Finished(TurnOutcome::Completed));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn legacy_current_json_with_delivery_field_deserializes_cleanly() {
    let mut legacy_json = serde_json::to_value(ThreadCurrent::new(
        "legacy-thread".into(),
        RuntimeEpoch::new(),
    ))
    .unwrap();
    legacy_json["state"]["inputs"] = serde_json::json!([
        {
            "delivery": { "kind": "nextTurn" },
            "input": {
                "id": "legacy-m1",
                "purpose": "message",
                "payload": { "format": "text/plain", "version": 1, "content": "hi" },
                "context": [{ "kind": "text", "text": "hi" }]
            },
            "ordinal": 1,
            "revision": 1,
            "state": { "kind": "pending" }
        }
    ]);
    legacy_json["state"]["terminalInputs"] = serde_json::json!([
        {
            "digest": "sha256:00",
            "delivery": { "kind": "currentTurn", "value": { "turnId": "t0" } },
            "id": "legacy-m0",
            "ordinal": 0,
            "purpose": "message",
            "revision": 2,
            "state": { "kind": "consumed", "turnId": "t0", "attemptId": "a0" }
        }
    ]);
    legacy_json["state"]["inputOrdinal"] = serde_json::json!(1);
    let parsed: ThreadCurrent = serde_json::from_value(legacy_json)
        .expect("legacy current.json must ignore removed delivery field");
    assert_eq!(parsed.state.inputs.len(), 1);
    assert_eq!(parsed.state.terminal_inputs.len(), 1);
    let thread = ThreadHandle::restore_current(parsed, None).unwrap();
    assert_eq!(thread.snapshot().inputs.len(), 1);
    thread.close().await.unwrap();
}
