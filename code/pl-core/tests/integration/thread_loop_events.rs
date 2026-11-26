//! Contracts for the priority-window Thread loop and single ordered CoreEvent exit.
use crate::support;

use std::sync::{Arc, Mutex};

use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        AggregateChannel, DynModelSession, ModelError, ModelMemberError, ModelProgress,
        ModelRequest, ModelSession, ModelStepOutput, ObservedPart, ObservedPartIdentity,
        PreparedModelCall, ToolProgressUpdate,
    },
    thread::{
        AttemptOutcome, ModelStepLimit, ThreadHandle, TurnOutcome, TurnState,
        events::{CoreEvent, CoreEventSink, CoreLiveEvent},
        inbox::ThreadMessage,
        interactions::{
            InteractionRequest, InteractionResolution, InteractionResponse,
        },
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RuntimeTool, ToolError},
    },
};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use support::turn;

#[derive(Debug, Default)]
struct EventLog(Mutex<Vec<CoreEvent>>);

impl CoreEventSink for EventLog {
    fn emit(&self, event: CoreEvent) {
        self.0.lock().unwrap().push(event);
    }
}

#[derive(Debug)]
struct ProgressTool {
    started: Arc<Notify>,
    release: CancellationToken,
}

impl pl_agent_tool::Tool for ProgressTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("progress_tool", "Emits live tool progress")
                    .unwrap()
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let _ = context
            .tasks
            .as_ref()
            .unwrap()
            .report_output(ToolProgressUpdate::append("stdout", "running tool step"))
            .await;
        self.started.notify_one();
        self.release.cancelled().await;
        Ok(ToolOutput::new(
            OpaquePayload::text("tool result payload"),
            vec![support::text("tool result content")],
        ))
    }
}

struct StreamingToolAndTextModel {
    step: usize,
    tool_started: Arc<Notify>,
    tool_release: CancellationToken,
}

impl ModelSession for StreamingToolAndTextModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let step = self.step;
        self.step += 1;
        let tool_started = self.tool_started.clone();
        let tool_release = self.tool_release.clone();
        Ok(PreparedModelCall::new(async move {
            let sender = request.members.as_ref().unwrap();
            let progress = request.progress.as_ref().unwrap();
            if step == 0 {
                progress.publish(ModelProgress::new(
                    1,
                    vec![
                        ObservedPart::new(ObservedPartIdentity::Aggregate {
                            channel: AggregateChannel::Reasoning,
                        })
                        .appended("thinking first"),
                        ObservedPart::new(ObservedPartIdentity::Aggregate {
                            channel: AggregateChannel::Text,
                        })
                        .appended("calling tool"),
                    ],
                ));
                tokio::task::yield_now().await;
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("calling tool"),
                    }],
                    tool_calls: vec![pl_core::model::ModelToolCall {
                        call_id: "call-1".into(),
                        tool_id: "progress_tool".into(),
                        arguments: OpaquePayload::text("{}"),
                        presentation_contract: None,
                        rejection: None,
                    }],
                    private_context: None,
                    usage: Default::default(),
                })
            } else {
                let _ = (tool_started, tool_release, sender);
                progress.publish(ModelProgress::new(
                    1,
                    vec![
                        ObservedPart::new(ObservedPartIdentity::Aggregate {
                            channel: AggregateChannel::Text,
                        })
                        .appended("final response"),
                    ],
                ));
                tokio::task::yield_now().await;
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("final response"),
                    }],
                    tool_calls: vec![],
                    private_context: None,
                    usage: Default::default(),
                })
            }
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn user_rx_preempts_saturated_event_rx_in_priority_window() {
    let thread = ThreadHandle::start_current("priority".into(), None).unwrap();
    let log = Arc::new(EventLog::default());
    thread.attach_event_sink(log.clone()).await.unwrap();
    thread
        .request_interaction(InteractionRequest {
            id: "prio-interaction".into(),
            turn_id: "prio-turn".into(),
            payload: OpaquePayload::text("confirm"),
        })
        .await
        .unwrap();
    let baseline = log.0.lock().unwrap().len();

    let mut handles = Vec::new();
    for index in 0..40 {
        let thread = thread.clone();
        handles.push(tokio::spawn(async move {
            thread
                .send_message(ThreadMessage {
                    id: format!("msg-{index}"),
                    source_id: "test".into(),
                    kind: Default::default(),
                    payload: OpaquePayload::text(format!("msg-{index}")),
                    context: vec![],
                })
                .await
                .unwrap();
        }));
    }
    let resolver = {
        let thread = thread.clone();
        tokio::spawn(async move {
            thread
                .resolve_interaction(InteractionResolution {
                    continuation: None,
                    id: "prio-interaction".into(),
                    expected_revision: 1,
                    response: InteractionResponse {
                        payload: OpaquePayload::text("approve"),
                        context: vec![],
                    },
                    mutations: vec![],
                })
                .await
                .unwrap();
        })
    };
    resolver.await.unwrap();
    for handle in handles {
        handle.await.unwrap();
    }

    let first_after = log
        .0
        .lock()
        .unwrap()
        .iter()
        .skip(baseline)
        .find_map(|event| match event {
            CoreEvent::Durable(commit) => Some(commit.clone()),
            CoreEvent::Live(_) => None,
        })
        .expect("at least one durable commit emitted");
    assert!(
        first_after
            .export
            .effect
            .interactions
            .iter()
            .any(|interaction| interaction.request.id == "prio-interaction"),
        "Tier 1 user_rx ResolveInteraction must preempt Tier 2 event_rx SendMessage backlog"
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn core_event_stream_emits_live_and_durable_events_in_strict_order() {
    let tool_started = Arc::new(Notify::new());
    let tool_release = CancellationToken::new();
    let model = StreamingToolAndTextModel {
        step: 0,
        tool_started: tool_started.clone(),
        tool_release: tool_release.clone(),
    };
    let thread = ThreadHandle::start("ordered-events".into(), DynModelSession::new(model)).unwrap();
    let log = Arc::new(EventLog::default());
    thread.attach_event_sink(log.clone()).await.unwrap();
    let mut broadcast_rx = thread.subscribe_events();
    thread
        .register_tools(vec![
            Registration::prepare("progress_tool".into(), OpaquePayload::text("progress_tool"))
                .unwrap()
                .attach(RuntimeTool::new(ProgressTool {
                    started: tool_started.clone(),
                    release: tool_release.clone(),
                })),
        ])
        .await
        .unwrap();

    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move {
            let mut input = turn("turn-ordered");
            input.max_model_steps = ModelStepLimit::Limited(4.try_into().unwrap());
            thread.run_turn(input).await
        })
    };

    tool_started.notified().await;
    tool_release.cancel();
    let completion = runner.await.unwrap().unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);

    let events = log.0.lock().unwrap().clone();
    let run_started_pos = events
        .iter()
        .position(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::RunActivity { execution: Some(_) })))
        .expect("RunActivity(Some) emitted");
    let reasoning_pos = events
        .iter()
        .position(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::ReasoningDelta { .. })))
        .expect("ReasoningDelta emitted");
    let text_start_pos = events
        .iter()
        .position(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::TextStreamStarted { .. })))
        .expect("TextStreamStarted emitted");
    let text_delta_pos = events
        .iter()
        .position(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::TextStreamDelta { .. })))
        .expect("TextStreamDelta emitted");
    let text_end_pos = events
        .iter()
        .position(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::TextStreamEnded { .. })))
        .expect("TextStreamEnded emitted");
    let first_attempt_commit_pos = events
        .iter()
        .position(|e| {
            matches!(
                e,
                CoreEvent::Durable(commit)
                    if commit
                        .export
                        .effect
                        .attempt
                        .as_ref()
                        .is_some_and(|a| matches!(a.outcome, AttemptOutcome::Committed(_)))
            )
        })
        .expect("AttemptCommitted durable event emitted");
    let tool_progress_pos = events
        .iter()
        .position(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::ToolProgress { .. })))
        .expect("ToolProgress emitted");
    let turn_finished_pos = events
        .iter()
        .position(|e| {
            matches!(
                e,
                CoreEvent::Durable(commit)
                    if commit
                        .export
                        .effect
                        .turn
                        .as_ref()
                        .is_some_and(|t| t.state == TurnState::Finished(TurnOutcome::Completed))
            )
        })
        .expect("TurnFinished durable event emitted");
    let run_cleared_pos = events
        .iter()
        .rposition(|e| matches!(e, CoreEvent::Live(CoreLiveEvent::RunActivity { execution: None })))
        .expect("RunActivity(None) emitted");

    assert!(run_started_pos < reasoning_pos);
    assert!(reasoning_pos <= text_start_pos);
    assert!(text_start_pos < text_delta_pos);
    assert!(text_delta_pos < text_end_pos);
    assert!(
        text_end_pos < first_attempt_commit_pos,
        "TextStreamEnded must precede AttemptCommitted durable commit"
    );
    assert!(tool_progress_pos < turn_finished_pos);
    assert!(turn_finished_pos <= run_cleared_pos);

    let mut broadcast_count = 0usize;
    while broadcast_rx.try_recv().is_ok() {
        broadcast_count += 1;
    }
    assert!(broadcast_count >= 5, "broadcast subscribers receive live/durable CoreEvents");
    let _ = ModelMemberError::Closed;
    thread.close().await.unwrap();
}
