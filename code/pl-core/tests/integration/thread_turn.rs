use crate::support;
use crate::tool_support;

use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

use pl_core::context::{ContextContent, ContextSource, OpaquePayload};
use pl_core::model::DynModelSession;
use pl_core::thread::{
    ModelStepLimit, ThreadError, ThreadHandle, TurnOutcome, TurnState, inbox::ThreadMessage,
    input::InputDriverOptions,
};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};

use support::{ScriptedModel, turn};
use tool_support::tool;

#[derive(Debug)]
struct RetiringTool(tokio::sync::mpsc::UnboundedSender<&'static str>);

impl pl_agent_tool::Tool for RetiringTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "RetiringTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        Ok(ToolOutput::new(input, vec![]))
    }
    async fn close(&self) -> Result<(), ToolError> {
        let _ = self.0.send("closed");
        Ok(())
    }
}

impl Drop for RetiringTool {
    fn drop(&mut self) {
        let _ = self.0.send("dropped");
    }
}

#[tokio::test]
async fn empty_identity_preparation_keeps_resources_available_for_valid_registration() {
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let tool = RetiringTool(events);
    assert!(matches!(
        Registration::prepare(String::new(), OpaquePayload::text("retiring")),
        Err(pl_core::tool::opaque::RegistryError::EmptyIdentity)
    ));
    assert!(
        received.try_recv().is_err(),
        "preparation consumed resources"
    );

    let prepared =
        Registration::prepare("retiring".into(), OpaquePayload::text("retiring")).unwrap();
    let (model, _) = ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("prepare-resource".into(), DynModelSession::new(model)).unwrap();
    thread
        .register_tools(vec![
            prepared.attach(pl_core::tool::opaque::RuntimeTool::new(tool)),
        ])
        .await
        .unwrap();
    thread.close().await.unwrap();
    assert_eq!(received.recv().await, Some("closed"));
    assert_eq!(received.recv().await, Some("dropped"));
    assert_eq!(received.recv().await, None);
}

#[tokio::test]
async fn replaced_tool_resources_are_closed_and_released_before_thread_close() {
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("retirement".into(), DynModelSession::new(model)).unwrap();
    for _ in 0..50 {
        let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
        thread
            .register_tools(vec![
                Registration::prepare("retiring".into(), OpaquePayload::text("retiring"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(RetiringTool(
                        events,
                    ))),
            ])
            .await
            .unwrap();
        thread.register_tools(Vec::new()).await.unwrap();
        let closed = tokio::time::timeout(std::time::Duration::from_secs(2), received.recv())
            .await
            .expect("replaced executor was retained until thread close");
        assert_eq!(closed, Some("closed"));
        assert_eq!(received.recv().await, Some("dropped"));
        assert_eq!(received.recv().await, None);
    }
    let mut rejected_events = Vec::new();
    let candidates = (0..2)
        .map(|_| {
            let (events, received) = tokio::sync::mpsc::unbounded_channel();
            rejected_events.push(received);
            Registration::prepare("duplicate".into(), OpaquePayload::text("duplicate"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(RetiringTool(
                    events,
                )))
        })
        .collect();
    assert!(thread.register_tools(candidates).await.is_err());
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        for mut received in rejected_events {
            assert_eq!(received.recv().await, Some("closed"));
            assert_eq!(received.recv().await, Some("dropped"));
            assert_eq!(received.recv().await, None);
        }
    })
    .await
    .expect("duplicate batch lost rejected candidates");

    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let authorization = pl_core::tool::opaque::ToolAuthorization::unique();
    authorization.revoke();
    let rejected_tool = Registration::prepare("rejected".into(), OpaquePayload::text("rejected"))
        .unwrap()
        .attach(pl_core::tool::opaque::RuntimeTool::new(RetiringTool(
            events,
        )))
        .with_authorization(authorization);
    let mut rejected = Box::pin(thread.register_tools(vec![rejected_tool]));
    assert!(futures::poll!(&mut rejected).is_pending());
    drop(rejected);
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        assert_eq!(received.recv().await, Some("closed"));
        assert_eq!(received.recv().await, Some("dropped"));
    })
    .await
    .expect("cancelled transfer lost rejected candidates");
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct FenceTool(Arc<Mutex<Vec<u64>>>);

#[tokio::test]
async fn revoked_late_registration_is_rejected_and_closed_by_original_owner() {
    use pl_core::tool::opaque::ToolAuthorization;
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("late-revoked".into(), DynModelSession::new(model)).unwrap();
    let authorization = ToolAuthorization::unique();
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let candidate = Registration::prepare("late".into(), OpaquePayload::text("late"))
        .unwrap()
        .attach(pl_core::tool::opaque::RuntimeTool::new(RetiringTool(
            events,
        )))
        .with_authorization(authorization.clone());
    authorization.revoke();
    assert!(matches!(
        thread.register_tools(vec![candidate]).await,
        Err(ThreadError::ToolPermissionRevoked)
    ));
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        assert_eq!(received.recv().await, Some("closed"));
        assert_eq!(received.recv().await, Some("dropped"));
    })
    .await
    .expect("revoked candidate lost its cleanup owner");
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct FailingClose {
    first: AtomicBool,
    panic_on_first: bool,
    events: tokio::sync::mpsc::UnboundedSender<&'static str>,
}
impl pl_agent_tool::Tool for FailingClose {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "FailingClose",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        Ok(ToolOutput::new(input, vec![]))
    }
    fn close(&self) -> impl Future<Output = Result<(), ToolError>> + Send {
        let failed = self.first.swap(false, Ordering::SeqCst);
        if failed && self.panic_on_first {
            panic!("synthetic close construction failure");
        }
        let result = if failed {
            Err(ToolError::new(std::io::Error::other(
                "synthetic close failure",
            )))
        } else {
            let _ = self.events.send("closed");
            Ok(())
        };
        std::future::ready(result)
    }
}
impl Drop for FailingClose {
    fn drop(&mut self) {
        let _ = self.events.send("dropped");
    }
}

#[tokio::test]
async fn tool_cleanup_retains_original_failure_and_retries_only_unfinished_instances() {
    for panic_on_first in [false, true] {
        let (model, _) = ScriptedModel::new(&[]);
        let thread =
            ThreadHandle::start("cleanup-failure".into(), DynModelSession::new(model)).unwrap();
        let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
        thread
            .register_tools(vec![
                Registration::prepare("failed".into(), OpaquePayload::text("failed"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(FailingClose {
                        first: AtomicBool::new(true),
                        panic_on_first,
                        events: events.clone(),
                    })),
                Registration::prepare("successful".into(), OpaquePayload::text("successful"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(RetiringTool(
                        events,
                    ))),
            ])
            .await
            .unwrap();
        assert!(thread.close().await.is_err());
        let snapshot = thread.snapshot();
        assert_eq!(snapshot.tool_cleanup.pending, 1);
        assert_eq!(snapshot.tool_cleanup.failures.len(), 1);
        assert_eq!(snapshot.tool_cleanup.failures[0].tool_id, "failed");
        let error = snapshot.tool_cleanup.failures[0].error.to_string();
        assert!(
            error.contains("synthetic close"),
            "original failure was lost: {error}"
        );
        assert_eq!(received.recv().await, Some("closed"));
        assert_eq!(received.recv().await, Some("dropped"));
        thread.close().await.unwrap();
        assert_eq!(received.recv().await, Some("closed"));
        assert_eq!(received.recv().await, Some("dropped"));
        assert_eq!(received.recv().await, None);
        assert_eq!(thread.snapshot().tool_cleanup.pending, 0);
    }
}

#[derive(Debug)]
struct InFlightTool {
    events: tokio::sync::mpsc::UnboundedSender<&'static str>,
    release: Arc<tokio::sync::Notify>,
}
impl pl_agent_tool::Tool for InFlightTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "InFlightTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        self.events.send("executing").unwrap();
        self.release.notified().await;
        Ok(ToolOutput::new(input, vec![]))
    }
    async fn close(&self) -> Result<(), ToolError> {
        let _ = self.events.send("closed");
        Ok(())
    }
}
impl Drop for InFlightTool {
    fn drop(&mut self) {
        let _ = self.events.send("dropped");
    }
}

#[tokio::test(start_paused = true)]
async fn ordinary_tool_segment_starts_together_before_its_shared_deadline() {
    let (model, _) = ScriptedModel::new(&["first", "second"]);
    let thread =
        ThreadHandle::start("concurrent-segment".into(), DynModelSession::new(model)).unwrap();
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let release = Arc::new(tokio::sync::Notify::new());
    thread
        .register_tools(
            ["first", "second"]
                .into_iter()
                .map(|id| {
                    Registration::prepare(id.into(), OpaquePayload::text(id))
                        .unwrap()
                        .attach(pl_core::tool::opaque::RuntimeTool::new(InFlightTool {
                            events: events.clone(),
                            release: release.clone(),
                        }))
                })
                .collect(),
        )
        .await
        .unwrap();
    let started_at = tokio::time::Instant::now();
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("concurrent")).await })
    };
    assert_eq!(received.recv().await, Some("executing"));
    assert_eq!(received.recv().await, Some("executing"));
    let spread = started_at.elapsed();
    release.notify_waiters();
    let result = running.await.unwrap();
    thread.close().await.unwrap();
    assert!(result.is_ok(), "{result:?}");
    assert!(
        spread < std::time::Duration::from_secs(1),
        "second task only started after {spread:?}"
    );
}

#[tokio::test(start_paused = true)]
async fn mixed_batch_receipts_distinguish_running_calls_from_an_instant_result() {
    let (model, requests) = ScriptedModel::new(&["slow-first", "quick", "slow-last"]);
    let thread = ThreadHandle::start("mixed-receipts".into(), DynModelSession::new(model)).unwrap();
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let release = Arc::new(tokio::sync::Notify::new());
    let mut registrations = ["slow-first", "slow-last"]
        .map(|id| {
            Registration::prepare(id.into(), OpaquePayload::text(id))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(InFlightTool {
                    events: events.clone(),
                    release: release.clone(),
                }))
        })
        .into_iter()
        .collect::<Vec<_>>();
    registrations.push(
        Registration::prepare("quick".into(), OpaquePayload::text("quick"))
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(RetiringTool(
                events,
            ))),
    );
    thread.register_tools(registrations).await.unwrap();
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("receipt-order")).await })
    };
    assert_eq!(received.recv().await, Some("executing"));
    assert_eq!(received.recv().await, Some("executing"));
    let result = running.await.unwrap();
    let snapshot = thread.snapshot();
    thread.interrupt();
    release.notify_waiters();
    thread.close().await.unwrap();
    result.unwrap();
    let requests = requests.lock().unwrap();
    assert_eq!(requests.len(), 2);
    let records = requests[1]
        .records
        .iter()
        .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
        .collect::<Vec<_>>();
    let order = records
        .iter()
        .map(|record| match &record.source {
            ContextSource::ToolResult { tool_id, .. } => tool_id.as_str(),
            _ => unreachable!(),
        })
        .collect::<Vec<_>>();
    assert_eq!(order, ["slow-first", "quick", "slow-last"]);
    for record in [records[0], records[2]] {
        let ContextSource::ToolResult { call_id, tool_id } = &record.source else {
            unreachable!();
        };
        let [ContextContent::Text { text }] = record.content.as_slice() else {
            panic!("running receipt must be readable model context");
        };
        let receipt: serde_json::Value = serde_json::from_str(text)
            .expect("a running receipt must state its identity and status structurally");
        let task = &snapshot.tasks[&format!("task:{call_id}")];
        assert_eq!(receipt["status"], "running");
        assert_eq!(receipt["taskId"], task.id);
        assert_eq!(receipt["toolName"], *tool_id);
    }
}

#[derive(Debug)]
struct SideEffectTool(Arc<AtomicBool>);

impl pl_agent_tool::Tool for SideEffectTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "SideEffectTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        _context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.0.store(true, Ordering::SeqCst);
        Ok(ToolOutput::new(input, vec![]))
    }
}

#[tokio::test]
async fn stopping_at_a_foreground_barrier_keeps_unstarted_results_in_call_order() {
    let (model, _) = ScriptedModel::new(&["gate", "z-later", "a-later"]);
    let thread = ThreadHandle::start("cancel-order".into(), DynModelSession::new(model)).unwrap();
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let release = Arc::new(tokio::sync::Notify::new());
    let later_started = Arc::new(AtomicBool::new(false));
    let mut registrations = vec![
        Registration::prepare("gate".into(), OpaquePayload::text("gate"))
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(InFlightTool {
                events,
                release: release.clone(),
            }))
            .foreground_coexisting(),
    ];
    registrations.extend(["z-later", "a-later"].map(|id| {
        Registration::prepare(id.into(), OpaquePayload::text(id))
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(SideEffectTool(
                later_started.clone(),
            )))
    }));
    thread.register_tools(registrations).await.unwrap();
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("ordered-stop")).await })
    };
    assert_eq!(received.recv().await, Some("executing"));
    let execution = thread.snapshot().execution.as_ref().unwrap().id.clone();
    assert!(thread.interrupt_execution(execution).await.unwrap());
    release.notify_one();
    let result = running.await.unwrap();
    let snapshot = thread.snapshot();
    thread.close().await.unwrap();
    assert!(matches!(result, Err(ThreadError::Cancelled)));
    assert!(!later_started.load(Ordering::SeqCst));
    assert!(
        snapshot.tasks.values().all(|task| task.tool_id == "gate"),
        "unstarted calls must have no task"
    );
    let results = snapshot
        .context
        .records
        .iter()
        .filter_map(|record| match &record.source {
            ContextSource::ToolResult { tool_id, .. } => Some(tool_id.as_str()),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(results, ["gate", "z-later", "a-later"]);
}

#[tokio::test]
async fn a_replaced_executor_lives_until_its_in_flight_result_is_committed() {
    replaced_executor_result_is_committed(false).await;
}

#[tokio::test]
async fn an_accepted_result_survives_authority_revocation() {
    replaced_executor_result_is_committed(true).await;
}

async fn replaced_executor_result_is_committed(revoke: bool) {
    let authority = pl_core::tool::opaque::ToolAuthorization::unique();
    let (model, _) = ScriptedModel::new(&["leased"]);
    let thread = ThreadHandle::start("frozen-tool".into(), DynModelSession::new(model)).unwrap();
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let release = Arc::new(tokio::sync::Notify::new());
    thread
        .register_tools(vec![
            Registration::prepare("leased".into(), OpaquePayload::text("leased"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(InFlightTool {
                    events,
                    release: release.clone(),
                }))
                .with_authorization(authority.clone())
                .foreground_coexisting(),
        ])
        .await
        .unwrap();
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("lease")).await })
    };
    assert_eq!(received.recv().await, Some("executing"));
    if revoke {
        authority.revoke();
    }
    thread.register_tools(Vec::new()).await.unwrap();
    assert!(
        received.try_recv().is_err(),
        "retirement closed a running executor"
    );
    release.notify_one();
    running.await.unwrap().unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        assert_eq!(received.recv().await, Some("closed"));
        assert_eq!(received.recv().await, Some("dropped"));
    })
    .await
    .unwrap();
    thread.close().await.unwrap();
}

impl pl_agent_tool::Tool for FenceTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("FenceTool", "Text tool for core runtime tests")
                    .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.0.lock().unwrap().push(context.history_fence);
        Ok(ToolOutput::new(input, vec![]))
    }
}

#[tokio::test]
async fn tool_receives_the_committed_start_fact_as_its_history_fence() {
    let (model, _) = ScriptedModel::new(&["fenced"]);
    let thread = ThreadHandle::start("fence".into(), DynModelSession::new(model)).unwrap();
    let fences = Arc::new(Mutex::new(Vec::new()));
    thread
        .register_tools(vec![
            Registration::prepare("fenced".into(), OpaquePayload::text("fenced tool"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(FenceTool(
                    fences.clone(),
                )))
                .foreground_coexisting(),
        ])
        .await
        .unwrap();
    thread.run_turn(turn("fenced-turn")).await.unwrap();

    let started = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .find(|effect| {
            effect
                .tasks
                .iter()
                .any(|task| task.tool_id == "fenced" && task.started_sequence.is_some())
        })
        .map(|effect| effect.sequence)
        .unwrap();
    assert_eq!(*fences.lock().unwrap(), vec![started]);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_turn_commits_user_model_and_tool_facts_in_call_order() {
    let (model, requests) = ScriptedModel::new(&["first", "second"]);
    let thread = ThreadHandle::start("conversation".into(), DynModelSession::new(model)).unwrap();
    let log = Arc::new(Mutex::new(Vec::new()));
    thread
        .register_tools(vec![tool("first", &log), tool("second", &log)])
        .await
        .unwrap();

    let completion = thread.run_turn(turn("question")).await.unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    assert_eq!(completion.model_steps, 2);
    assert_eq!(
        *log.lock().unwrap(),
        ["question-first".to_string(), "question-second".to_string()]
    );
    {
        let seen = requests.lock().unwrap();
        assert_eq!(seen.len(), 2);
        let results: Vec<_> = seen[1]
            .records
            .iter()
            .filter_map(|record| match &record.source {
                ContextSource::ToolResult { call_id, .. } => Some(call_id.as_str()),
                _ => None,
            })
            .collect();
        assert_eq!(results, ["question-first", "question-second"]);
        let calls: Vec<_> = seen[1]
            .records
            .iter()
            .flat_map(|record| record.tool_calls.iter())
            .map(|call| call.arguments.content())
            .collect();
        assert_eq!(calls, ["  raw first\n", "  raw second\n"]);
    }

    let deliveries: Vec<_> = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .flat_map(|effect| effect.deliveries.to_vec())
        .collect();
    assert_eq!(deliveries.len(), 2);
    assert_eq!(deliveries[0].output.payload().content(), "  raw first\n");
    assert_eq!(deliveries[1].output.payload().content(), "  raw second\n");
    assert!(thread.snapshot().context.records.iter().any(|record| {
        record.source == ContextSource::Assistant
            && record.content.contains(&ContextContent::Text {
                text: Arc::from("Answer completed"),
            })
    }));
    assert!(thread.effects().await.unwrap().iter().any(|effect| {
        effect.turn.as_ref().is_some_and(|turn| {
            turn.turn_id == "question" && turn.state == TurnState::Finished(TurnOutcome::Completed)
        })
    }));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_durable_message_receipt_wakes_only_its_unconsumed_message() {
    let (model, requests) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("parent".into(), DynModelSession::new(model)).unwrap();
    let message = ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: "child-report".into(),
        source_id: "child".into(),
        payload: OpaquePayload::text("finished"),
        context: vec![support::text("finished")],
    };
    let sequence = thread.send_message(message).await.unwrap();
    let options = InputDriverOptions {
        max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
    };
    assert!(matches!(
        thread
            .wake_accepted_message("other", sequence, options)
            .await,
        Err(ThreadError::InvalidIdentity)
    ));
    assert_eq!(thread.snapshot().inbox.len(), 1);
    assert!(
        thread
            .wake_accepted_message("child-report", sequence, options)
            .await
            .unwrap()
    );
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while thread.snapshot().consumed_messages < sequence {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(
        !thread
            .wake_accepted_message("child-report", sequence, options)
            .await
            .unwrap()
    );
    assert_eq!(thread.snapshot().inbox_sequence, sequence);
    {
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert!(requests[0].records.iter().any(|record| {
            record.source
                == ContextSource::AgentMessage {
                    source_id: "child".into(),
                    purpose: pl_core::context::AgentMessageKind::Report,
                }
        }));
    }
    thread.close().await.unwrap();
}
