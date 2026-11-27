//! Public-API coverage of unified task/message waiting.
//!
//! Wait reports one coherent observation: selected task records, whether unconsumed
//! messages are ready, and whether the fixed deadline was reached without readiness.
//! Complete payloads stay unconsumed for later model admission.
#[allow(dead_code)]
use crate::support;

use std::{
    future::Future,
    pin::Pin,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use pl_core::context::{ContextContent, ContextSource, OpaquePayload};
use pl_core::model::{
    DynModelSession, ModelError, ModelRequest, ModelSession, ModelToolCall, PreparedModelCall,
    ToolProgressUpdate,
};
use pl_core::thread::{
    HistoryExport, StepInput, TaskAccess, ThreadEffectBatch, ThreadError, ThreadHandle,
    ToolDelivery, ToolDispatch, ToolOutcome, UsageSummary,
    cold::{ColdStoreError, DurableToolTask, StorageIdleStatus, StoragePressure},
    history_sink::{HistorySink, HistorySinkHandle},
    inbox::ThreadMessage,
    task::{TaskCancellationReceipt, TaskRecord, TaskStatus},
};
use pl_core::tool::{
    ToolFailureKind, ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};
use pretty_assertions::assert_eq;
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

use support::{response, text};

#[derive(Debug)]
struct HeldTool(Arc<Notify>);

impl pl_agent_tool::Tool for HeldTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("HeldTool", "Text tool for core runtime tests")
                    .expect("valid definition")
            });
        &DEFINITION
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
        Ok(ToolOutput::from_data(
            serde_json::Value::String(input.content().to_owned()),
            vec![text("held finished")],
        ))
    }
}

#[derive(Debug)]
struct CleanupHeldTool {
    cancelled: Arc<Notify>,
    release: Arc<Notify>,
}

impl pl_agent_tool::Tool for CleanupHeldTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "CleanupHeldTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        context.cancellation.cancelled().await;
        self.cancelled.notify_one();
        self.release.notified().await;
        Err(ToolError::new(ThreadError::Cancelled))
    }
}

#[derive(Debug)]
struct FastTool {
    fail: bool,
}

impl pl_agent_tool::Tool for FastTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("FastTool", "Text tool for core runtime tests")
                    .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        if self.fail {
            let media = ContextContent::Media {
                payload: OpaquePayload::text("original media"),
            };
            let output = ToolOutput::from_data(serde_json::Value::Null, vec![media])
                .with_details(serde_json::json!({"diagnostic": "original material"}));
            return Err(ToolError::operation(
                std::io::Error::other("operation failed"),
                output,
            ));
        }
        Ok(ToolOutput::from_data(
            serde_json::Value::String(input.content().to_owned()),
            vec![text("fast finished")],
        ))
    }
}

#[derive(Debug)]
struct AccessTool {
    started: mpsc::UnboundedSender<TaskAccess>,
    release: Arc<Notify>,
}

impl pl_agent_tool::Tool for AccessTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "AccessTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let access = context
            .tasks
            .clone()
            .expect("a running call owns its task access");
        self.started.send(access).expect("the test observes access");
        tokio::select! {
            _ = self.release.notified() => {}
            _ = context.cancellation.cancelled() => {
                return Err(ToolError::new(ThreadError::Cancelled));
            }
        }
        Ok(ToolOutput::from_data(
            serde_json::Value::String(input.content().to_owned()),
            vec![text("waiter finished")],
        ))
    }
}

struct SwitchModel {
    tools: Arc<Mutex<Vec<String>>>,
}

impl ModelSession for SwitchModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let has_result = request.context.records.iter().any(|record| {
            matches!(
                &record.source,
                pl_core::context::ContextSource::ToolResult { .. }
            ) && record.turn_id.as_deref() == Some(request.turn_id.as_str())
        });
        let calls = if has_result {
            Vec::new()
        } else {
            self.tools
                .lock()
                .expect("tool script")
                .iter()
                .map(|tool_id| ModelToolCall {
                    presentation_contract: None,
                    rejection: None,
                    call_id: format!("{}-{tool_id}", request.turn_id),
                    tool_id: tool_id.clone(),
                    arguments: OpaquePayload::text(format!("raw {tool_id}")),
                })
                .collect()
        };
        Ok(PreparedModelCall::new(async move {
            Ok(response(&request, calls))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

struct Harness {
    thread: ThreadHandle,
    tools: Arc<Mutex<Vec<String>>>,
    held: Arc<Notify>,
    held_b: Arc<Notify>,
}

#[tokio::test(start_paused = true)]
async fn completed_result_survives_later_publication_and_effect_release() {
    let harness = Harness::start("task-result-handoff").await;
    harness.script(&["fast"]);
    harness.step("producer").await;
    let original = harness
        .thread
        .execute_tool("producer-fast".into(), CancellationToken::new())
        .await
        .unwrap();
    let ToolDispatch::Completed(original) = original else {
        panic!("fast tool must have completed");
    };
    assert_eq!(original.data(), Some(&serde_json::json!("raw fast")));

    let (access, release, caller) = harness.retain_access("reader", false).await;
    harness
        .thread
        .release_history_through(harness.thread.snapshot().commit_sequence)
        .unwrap();
    let id = "task:producer-fast";
    assert_eq!(access.get(id).unwrap().status, TaskStatus::Succeeded);
    let fact = access.durable(id).await.unwrap().expect("terminal task");
    let delivery = fact
        .delivery
        .expect("published task retains its original delivery");
    assert_eq!(delivery.call_id, "producer-fast");
    assert_eq!(delivery.tool_id, "fast");
    assert_eq!(delivery.output, original);
    release.notify_one();
    caller.await.unwrap().unwrap();
    harness.thread.close().await.unwrap();
}

/// A read-only stand-in for the host's original store. The bytes come from a real owner commit.
#[derive(Debug)]
struct SavedTaskReader {
    original: Option<(TaskRecord, Vec<u8>)>,
    gate: Option<Arc<ColdReadGate>>,
    durable: AtomicU64,
}

#[derive(Debug, Default)]
struct ColdReadGate {
    reads: AtomicUsize,
    entered: Notify,
    release: Notify,
    ready: Option<TaskRecord>,
    ready_reads: AtomicUsize,
}

impl HistorySink for SavedTaskReader {
    fn fold_usage(&self, _: &mut UsageSummary, _: &ThreadEffectBatch) {}
    fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
        Ok(())
    }
    fn reserve_operation_output(&self, _: &str, _: &str, max: u64) -> Result<u64, ColdStoreError> {
        Ok(max)
    }
    fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }
    fn release_operation_output(&self, _: &str, _: &str) {}
    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::Relaxed),
            ..Default::default()
        }
    }
    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: Some(0),
        }
    }
    fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        None
    }
    fn admit(&self, _: &str, export: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        self.durable
            .fetch_max(export.effect.sequence, Ordering::Relaxed);
        Ok(())
    }

    async fn read_saved_tool_task(
        &self,
        thread_id: &str,
        id: &str,
    ) -> Result<Option<DurableToolTask>, ColdStoreError> {
        if let Some(gate) = &self.gate {
            if let Some(task) = &gate.ready
                && id == task.id
            {
                gate.ready_reads.fetch_add(1, Ordering::Relaxed);
                return Ok(Some(DurableToolTask {
                    task: task.clone(),
                    delivery: None,
                }));
            }
            gate.reads.fetch_add(1, Ordering::Relaxed);
            gate.entered.notify_one();
            gate.release.notified().await;
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("test read fault")),
            });
        }
        assert_eq!(thread_id, "test-operation-original");
        let Some((task, delivery)) = &self.original else {
            return Ok(None);
        };
        if id != task.id && id != task.call_id {
            return Ok(None);
        }
        let delivery = serde_json::from_slice(delivery).map_err(|source| ColdStoreError {
            source: Box::new(source),
        })?;
        Ok(Some(DurableToolTask {
            task: task.clone(),
            delivery: Some(delivery),
        }))
    }
}

async fn install_cold_read_gate(
    thread: &ThreadHandle,
    ready: Option<TaskRecord>,
) -> Arc<ColdReadGate> {
    let gate = Arc::new(ColdReadGate {
        ready,
        ..Default::default()
    });
    thread
        .attach_history(HistorySinkHandle::new(SavedTaskReader {
            original: None,
            gate: Some(gate.clone()),
            durable: AtomicU64::new(0),
        }))
        .await
        .unwrap();
    gate
}

async fn pending_cold_wait(
    access: TaskAccess,
    gate: &ColdReadGate,
    timeout: Duration,
) -> tokio::task::JoinHandle<Result<pl_core::thread::TaskWaitSnapshot, ThreadError>> {
    let waiting = tokio::spawn(async move {
        access
            .wait(&["task:archived".into()], timeout, CancellationToken::new())
            .await
    });
    tokio::time::timeout(Duration::from_secs(1), gate.entered.notified())
        .await
        .expect("wait reached the blocked history reader");
    waiting
}

#[tokio::test(start_paused = true)]
async fn wait_ready_task_does_not_block_on_missing_cold_identity() {
    let harness = Harness::start("wait-ready-before-cold-read").await;
    let gate = install_cold_read_gate(&harness.thread, None).await;
    harness.script(&["fast"]);
    harness
        .thread
        .run_turn(support::turn("done"))
        .await
        .unwrap();
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let ids = ["task:archived".into(), "task:done-fast".into()];
    let observed = tokio::time::timeout(
        Duration::from_secs(1),
        access.wait(&ids, Duration::from_secs(60), CancellationToken::new()),
    )
    .await
    .expect("a known ready task wakes independently of history")
    .unwrap();
    assert_eq!(observed.tasks.len(), 1);
    assert_eq!(observed.tasks[0].id, "task:done-fast");
    assert_eq!(observed.tasks[0].status, TaskStatus::Succeeded);
    assert!(!observed.timed_out);
    assert_eq!(gate.reads.load(Ordering::Relaxed), 0);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_cold_ready_task_wakes_when_blocked_lookup_is_first() {
    any_cold_task_finishes(["task:archived", "task:archived-ready"]).await;
}

#[tokio::test(start_paused = true)]
async fn wait_cold_ready_task_wakes_when_ready_lookup_is_first() {
    any_cold_task_finishes(["task:archived-ready", "task:archived"]).await;
}

async fn any_cold_task_finishes(ids: [&str; 2]) {
    let harness = Harness::start("wait-competing-cold-reads").await;
    let ready = TaskRecord {
        id: "task:archived-ready".into(),
        parent_call_id: None,
        invocation: None,
        call_id: "archived-ready".into(),
        tool_id: "fast".into(),
        turn_id: "archived-turn".into(),
        revision: 2,
        status: TaskStatus::Succeeded,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: None,
    };
    let gate = install_cold_read_gate(&harness.thread, Some(ready.clone())).await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let observed = access
        .wait(
            &ids.map(str::to_owned),
            Duration::from_secs(3),
            CancellationToken::new(),
        )
        .await;
    finish(release, runner).await;
    harness.thread.close().await.unwrap();

    let observed = observed.unwrap();
    assert!(
        !observed.timed_out,
        "the ready archived task must wake wait for {ids:?}"
    );
    assert_eq!(observed.tasks, vec![ready]);
    assert_eq!(gate.ready_reads.load(Ordering::Relaxed), 1);
    assert!(gate.reads.load(Ordering::Relaxed) <= 1);
}

#[tokio::test(start_paused = true)]
async fn wait_message_wakes_an_in_flight_cold_read() {
    let harness = Harness::start("wait-message-during-cold-read").await;
    let gate = install_cold_read_gate(&harness.thread, None).await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let waiting = pending_cold_wait(access, &gate, Duration::from_secs(60)).await;
    harness
        .thread
        .send_message(report("during-cold-read"))
        .await
        .unwrap();
    let observed = tokio::time::timeout(Duration::from_secs(1), waiting)
        .await
        .expect("a committed message wakes independently of history")
        .unwrap()
        .unwrap();
    assert!(observed.messages_ready && !observed.timed_out);
    assert!(observed.tasks.is_empty());
    assert_eq!(gate.reads.load(Ordering::Relaxed), 1);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_cold_read_obeys_the_original_deadline() {
    let harness = Harness::start("wait-deadline-during-cold-read").await;
    let gate = install_cold_read_gate(&harness.thread, None).await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let waiting = pending_cold_wait(access, &gate, Duration::from_secs(3)).await;
    tokio::time::advance(Duration::from_secs(3)).await;
    let observed = tokio::time::timeout(Duration::from_secs(1), waiting)
        .await
        .expect("the original deadline wakes independently of history")
        .unwrap()
        .unwrap();
    assert!(observed.timed_out && !observed.messages_ready);
    assert!(observed.tasks.is_empty());
    assert_eq!(gate.reads.load(Ordering::Relaxed), 1);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_reports_a_cold_read_failure_without_fabricating_readiness() {
    let harness = Harness::start("wait-cold-read-failure").await;
    let gate = install_cold_read_gate(&harness.thread, None).await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let waiting = pending_cold_wait(access, &gate, Duration::from_secs(60)).await;
    gate.release.notify_one();
    let error = waiting.await.unwrap().unwrap_err();
    assert!(
        matches!(error, ThreadError::Storage(error) if error.source.to_string() == "test read fault")
    );
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn failed_operation_keeps_author_data_and_can_be_read_by_a_fresh_owner() {
    let harness = Harness::start("test-operation-original").await;
    harness.script(&["failure"]);
    harness.step("producer").await;
    let error = harness
        .thread
        .execute_tool("producer-failure".into(), CancellationToken::new())
        .await
        .unwrap_err();
    let ThreadError::Tool(error) = error else {
        panic!("unexpected error: {error:?}");
    };
    assert_eq!(error.kind(), ToolFailureKind::Operation);
    assert!(error.source.is::<std::io::Error>());
    let original = error.observed_output().expect("observed author result");
    assert_eq!(original.data(), Some(&serde_json::Value::Null));
    assert!(matches!(original.content(), [ContextContent::Media { .. }]));

    let snapshot = harness.thread.snapshot();
    let result = snapshot.context.records.iter().find(|record| matches!(
        &record.source,
        ContextSource::ToolResult { call_id, tool_id } if call_id == "producer-failure" && tool_id == "failure"
    )).expect("paired result");
    assert_eq!(result.tool_data.as_value(), Some(&serde_json::Value::Null));
    assert_eq!(result.content[0], original.content()[0]);
    assert!(
        matches!(&result.content[1], ContextContent::Text { text } if text.contains("operation failed"))
    );

    let export = harness
        .thread
        .history_export_page(0, std::num::NonZeroUsize::new(32).unwrap())
        .unwrap()
        .into_iter()
        .find(|export| {
            export
                .effect
                .deliveries
                .iter()
                .any(|delivery| delivery.call_id == "producer-failure")
        })
        .expect("terminal fact was exported");
    let task = export
        .effect
        .tasks
        .iter()
        .find(|task| task.call_id == "producer-failure")
        .unwrap()
        .clone();
    let saved = &export.effect.deliveries[0];
    let reader = SavedTaskReader {
        original: Some((task, serde_json::to_vec(saved).unwrap())),
        gate: None,
        durable: AtomicU64::new(0),
    };
    harness.thread.close().await.unwrap();

    let harness = Harness::start("test-operation-original").await;
    harness
        .thread
        .attach_history(HistorySinkHandle::new(reader))
        .await
        .unwrap();
    let (access, release, caller) = harness.retain_access("reader", false).await;
    let id = "task:producer-failure";
    assert!(matches!(
        access.get(id),
        Err(ThreadError::TaskNotFound { .. })
    ));
    assert!(access.durable("task:missing").await.unwrap().is_none());
    let fact = access
        .durable(id)
        .await
        .unwrap()
        .expect("committed original");
    assert_eq!(fact.task.status, TaskStatus::Failed);
    let delivery: ToolDelivery = fact.delivery.expect("committed delivery");
    assert_eq!(delivery.output, *original);
    assert_eq!(delivery.delivered_context, saved.delivered_context);
    assert!(
        matches!(delivery.outcome, ToolOutcome::Failed(error) if error.kind() == ToolFailureKind::Operation)
    );
    release.notify_one();
    caller.await.unwrap().unwrap();
    harness.thread.close().await.unwrap();
}

impl Harness {
    async fn start(name: &str) -> Self {
        let tools = Arc::new(Mutex::new(Vec::new()));
        let thread = ThreadHandle::start(
            name.into(),
            DynModelSession::new(SwitchModel {
                tools: tools.clone(),
            }),
        )
        .unwrap();
        let held = Arc::new(Notify::new());
        let held_b = Arc::new(Notify::new());
        thread
            .register_tools(vec![
                Registration::prepare("held".into(), OpaquePayload::text("held"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(HeldTool(
                        held.clone(),
                    ))),
                Registration::prepare("held-b".into(), OpaquePayload::text("held-b"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(HeldTool(
                        held_b.clone(),
                    ))),
                Registration::prepare("fast".into(), OpaquePayload::text("fast"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(FastTool {
                        fail: false,
                    })),
                Registration::prepare("failure".into(), OpaquePayload::text("failure"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(FastTool {
                        fail: true,
                    })),
            ])
            .await
            .unwrap();
        Self {
            thread,
            tools,
            held,
            held_b,
        }
    }

    fn script(&self, ids: &[&str]) {
        *self.tools.lock().expect("tool script") = ids.iter().map(|id| (*id).to_string()).collect();
    }

    async fn step(&self, turn_id: &str) {
        self.thread
            .step(StepInput {
                turn_id: turn_id.into(),
                attempt_id: format!("{turn_id}-attempt"),
                content: vec![text("run")],
                cancellation: CancellationToken::new(),
            })
            .await
            .unwrap();
    }

    async fn running_task(&self, turn_id: &str, tool_id: &str) -> TaskRecord {
        self.script(&[tool_id]);
        self.step(turn_id).await;
        let mut execute = std::pin::pin!(
            self.thread
                .execute_tool(format!("{turn_id}-{tool_id}"), CancellationToken::new(),)
        );
        for _ in 0..8 {
            assert!(
                futures::poll!(&mut execute).is_pending(),
                "a held tool must stay inside the one-second receipt window"
            );
            tokio::task::yield_now().await;
        }
        tokio::time::advance(Duration::from_secs(1)).await;
        match execute.await.unwrap() {
            ToolDispatch::Running(task) => *task,
            other => panic!("held tool must remain running, got {other:?}"),
        }
    }

    async fn retain_access(
        &self,
        turn_id: &str,
        waiting: bool,
    ) -> (
        TaskAccess,
        Arc<Notify>,
        tokio::task::JoinHandle<Result<ToolDispatch, ThreadError>>,
    ) {
        self.retain_authorized_access(turn_id, waiting, None).await
    }

    async fn retain_authorized_access(
        &self,
        turn_id: &str,
        waiting: bool,
        authority: Option<pl_core::tool::opaque::ToolAuthorization>,
    ) -> (
        TaskAccess,
        Arc<Notify>,
        tokio::task::JoinHandle<Result<ToolDispatch, ThreadError>>,
    ) {
        let (started, mut ready) = mpsc::unbounded_channel();
        let release = Arc::new(Notify::new());
        let registration = Registration::prepare("waiter".into(), OpaquePayload::text("waiter"))
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(AccessTool {
                started,
                release: release.clone(),
            }));
        let registration = if let Some(authority) = authority {
            registration
                .with_authorization(authority)
                .with_task_cancellation()
        } else {
            registration
        };
        let registration = if waiting {
            registration.with_task_waiting()
        } else {
            registration.foreground_coexisting()
        };
        self.thread
            .register_tools(vec![
                Registration::prepare("held".into(), OpaquePayload::text("held"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(HeldTool(
                        self.held.clone(),
                    ))),
                Registration::prepare("held-b".into(), OpaquePayload::text("held-b"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(HeldTool(
                        self.held_b.clone(),
                    ))),
                Registration::prepare("fast".into(), OpaquePayload::text("fast"))
                    .unwrap()
                    .attach(pl_core::tool::opaque::RuntimeTool::new(FastTool {
                        fail: false,
                    })),
                registration,
            ])
            .await
            .unwrap();
        self.script(&["waiter"]);
        self.step(turn_id).await;
        let runner = tokio::spawn({
            let thread = self.thread.clone();
            let call_id = format!("{turn_id}-waiter");
            async move { thread.execute_tool(call_id, CancellationToken::new()).await }
        });
        let access = ready
            .recv()
            .await
            .expect("the running call publishes access");
        (access, release, runner)
    }
}

async fn assert_pending<T>(future: &mut Pin<&mut impl Future<Output = T>>) {
    for _ in 0..8 {
        if futures::poll!(&mut *future).is_ready() {
            panic!("wait returned before the expected ready source");
        }
        tokio::task::yield_now().await;
    }
}

fn report(id: &str) -> ThreadMessage {
    ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: id.into(),
        source_id: "child".into(),
        payload: OpaquePayload::text("child finished"),
        context: vec![text("child finished")],
    }
}

async fn finish(
    release: Arc<Notify>,
    runner: tokio::task::JoinHandle<Result<ToolDispatch, ThreadError>>,
) {
    release.notify_waiters();
    runner.await.unwrap().unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_returns_immediately_when_a_message_is_already_ready() {
    let harness = Harness::start("pre-ready-message").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    harness
        .thread
        .send_message(report("already-ready"))
        .await
        .unwrap();
    let consumed = harness.thread.snapshot().consumed_messages;
    let observed = access
        .wait(&[], Duration::from_secs(5), CancellationToken::new())
        .await
        .unwrap();
    assert!(observed.messages_ready);
    assert!(!observed.timed_out);
    assert!(observed.tasks.is_empty());
    assert_eq!(harness.thread.snapshot().consumed_messages, consumed);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_returns_immediately_when_a_selected_task_already_finished() {
    let harness = Harness::start("pre-ready-task").await;
    harness.script(&["fast"]);
    harness
        .thread
        .run_turn(support::turn("fast-turn"))
        .await
        .unwrap();
    let finished = harness
        .thread
        .snapshot()
        .terminal_tasks
        .iter()
        .chain(harness.thread.snapshot().tasks.values())
        .find(|task| task.tool_id == "fast")
        .cloned()
        .expect("the finished fast task remains observable");
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let observed = access
        .wait(
            std::slice::from_ref(&finished.id),
            Duration::from_secs(5),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks.len(), 1);
    assert_eq!(observed.tasks[0].id, finished.id);
    assert_eq!(observed.tasks[0].status, TaskStatus::Succeeded);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_wakes_on_a_later_message_even_when_task_ids_are_selected() {
    let harness = Harness::start("later-message").await;
    let held = harness.running_task("held-turn", "held").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let consumed = harness.thread.snapshot().consumed_messages;
    let ids = [held.id.clone()];
    let waiting = access.wait(&ids, Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    harness
        .thread
        .send_message(report("later-ready"))
        .await
        .unwrap();
    let observed = waiting.await.unwrap();
    assert!(observed.messages_ready);
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks.len(), 1);
    assert_eq!(observed.tasks[0].id, held.id);
    assert_eq!(observed.tasks[0].status, TaskStatus::Running);
    assert_eq!(harness.thread.snapshot().consumed_messages, consumed);
    assert!(
        harness
            .thread
            .snapshot()
            .tasks
            .get(&held.id)
            .is_some_and(|task| task.status == TaskStatus::Running)
    );
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_returns_when_first_selected_task_finishes_while_second_is_running() {
    any_task_finishes(true).await;
}

#[tokio::test(start_paused = true)]
async fn wait_returns_when_second_selected_task_finishes_while_first_is_running() {
    any_task_finishes(false).await;
}

async fn any_task_finishes(first_finishes: bool) {
    let harness = Harness::start("any-task").await;
    let first = harness.running_task("first", "held").await;
    let second = harness.running_task("second", "held-b").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let consumed = harness.thread.snapshot().consumed_messages;
    let ids = [first.id.clone(), second.id.clone()];
    let waiting = access.wait(&ids, Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    if first_finishes {
        harness.held.notify_one();
    } else {
        harness.held_b.notify_one();
    }
    let observed = waiting.await.unwrap();
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks.len(), 2);
    for (index, original) in [first, second].iter().enumerate() {
        let task = observed
            .tasks
            .iter()
            .find(|task| task.id == original.id)
            .unwrap();
        assert_eq!(task.call_id, original.call_id);
        assert_eq!(task.turn_id, original.turn_id);
        assert_eq!(task.tool_id, original.tool_id);
        assert!(!task.cancel_requested);
        assert_eq!(
            task.status,
            if (index == 0) == first_finishes {
                TaskStatus::Succeeded
            } else {
                TaskStatus::Running
            }
        );
    }
    assert_eq!(harness.thread.snapshot().consumed_messages, consumed);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn empty_selection_ignores_progress_until_a_message_arrives() {
    let harness = Harness::start("messages-only").await;
    let held = harness.running_task("held-turn", "held").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let waiting = access.wait(&[], Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    access
        .report_output(ToolProgressUpdate::append("progress", "not a message"))
        .await
        .unwrap();
    assert_pending(&mut waiting).await;
    let consumed = harness.thread.snapshot().consumed_messages;
    harness
        .thread
        .send_message(report("later-child-report"))
        .await
        .unwrap();
    let observed = waiting.await.unwrap();
    assert!(observed.messages_ready);
    assert!(!observed.timed_out);
    assert!(observed.tasks.is_empty());
    assert_eq!(access.get(&held.id).unwrap().status, TaskStatus::Running);
    assert_eq!(harness.thread.snapshot().consumed_messages, consumed);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn delivery_markers_commit_and_clear_while_a_tool_waits_for_the_message() {
    use pl_core::thread::extensions::ExtensionMutation;

    let harness = Harness::start("delivery-marker-during-wait").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let waiting = access.wait(&[], Duration::from_secs(300), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;

    // A host must save this marker before admitting its terminal report. The waiting tool
    // cannot finish until that admission; routing the marker through the idle queue deadlocks.
    let marker = tokio::time::timeout(
        Duration::from_millis(100),
        harness
            .thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: "delivery:child-report".into(),
                expected_revision: None,
                payload: OpaquePayload::text("pending"),
            }]),
    )
    .await;
    if marker.is_err() {
        finish(release, runner).await;
        harness.thread.close().await.unwrap();
        panic!("delivery marker waited for the tool that needs its message");
    }
    let marker = marker.unwrap().unwrap()["delivery:child-report"].clone();
    assert_pending(&mut waiting).await;
    assert!(matches!(
        harness
            .thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: "delivery:child-report".into(),
                expected_revision: None,
                payload: OpaquePayload::text("conflicting"),
            }])
            .await,
        Err(ThreadError::ExtensionConflict { .. })
    ));
    assert_eq!(
        harness.thread.snapshot().extensions["delivery:child-report"],
        marker
    );
    harness
        .thread
        .send_message_with_extensions(
            report("terminal-child-report"),
            vec![ExtensionMutation::Put {
                id: "delivery:child-report".into(),
                expected_revision: Some(marker.revision),
                payload: OpaquePayload::text("accepted"),
            }],
        )
        .await
        .unwrap();
    let observed = waiting.await.unwrap();
    assert!(observed.messages_ready && !observed.timed_out);
    let accepted = harness.thread.snapshot().extensions["delivery:child-report"].clone();
    // Cleanup also runs before the enclosing tool/Turn ends.
    harness
        .thread
        .mutate_extensions(vec![ExtensionMutation::Delete {
            id: "delivery:child-report".into(),
            expected_revision: accepted.revision,
        }])
        .await
        .unwrap();
    assert!(
        !harness
            .thread
            .snapshot()
            .extensions
            .contains_key("delivery:child-report")
    );
    assert_eq!(harness.thread.snapshot().inbox.len(), 1);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn cancellation_receipt_precedes_cleanup_and_wait_observes_the_same_task_exit() {
    let harness = Harness::start("cancel-then-join").await;
    let cancelled = Arc::new(Notify::new());
    let cleanup = Arc::new(Notify::new());
    harness
        .thread
        .register_tools(vec![
            Registration::prepare("cleanup".into(), OpaquePayload::text("cleanup"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(CleanupHeldTool {
                    cancelled: cancelled.clone(),
                    release: cleanup.clone(),
                })),
        ])
        .await
        .unwrap();
    let task = harness.running_task("owned", "cleanup").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    assert_eq!(
        harness.thread.cancel_task(task.id.clone()).await.unwrap(),
        TaskCancellationReceipt::Requested
    );
    cancelled.notified().await;
    let before_join = access.get(&task.id).unwrap();
    assert_eq!(before_join.status, TaskStatus::Running);
    assert!(before_join.cancel_requested);
    assert_eq!(
        harness.thread.cancel_task(task.id.clone()).await.unwrap(),
        TaskCancellationReceipt::AlreadyRequested
    );
    let ids = [task.id.clone()];
    let waiting = access.wait(&ids, Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    cleanup.notify_one();
    let observed = waiting.await.unwrap();
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks.len(), 1);
    assert_eq!(observed.tasks[0].id, task.id);
    assert_eq!(observed.tasks[0].call_id, task.call_id);
    assert_eq!(observed.tasks[0].status, TaskStatus::Cancelled);
    assert_eq!(
        harness.thread.cancel_task(task.id).await.unwrap(),
        TaskCancellationReceipt::AlreadyFinished
    );
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_timeout_is_fixed_across_unrelated_updates() {
    let harness = Harness::start("fixed-deadline").await;
    let held = harness.running_task("held-turn", "held").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let ids = [held.id.clone()];
    let waiting = access.wait(&ids, Duration::from_millis(100), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    tokio::time::advance(Duration::from_millis(40)).await;
    access
        .report_output(ToolProgressUpdate::append("progress", "unrelated"))
        .await
        .unwrap();
    assert_pending(&mut waiting).await;
    tokio::time::advance(Duration::from_millis(40)).await;
    assert_pending(&mut waiting).await;
    tokio::time::advance(Duration::from_millis(20)).await;
    let observed = waiting.await.unwrap();
    assert!(observed.timed_out);
    assert!(!observed.messages_ready);
    assert_eq!(observed.tasks.len(), 1);
    assert_eq!(observed.tasks[0].status, TaskStatus::Running);
    assert!(
        harness
            .thread
            .snapshot()
            .tasks
            .get(&held.id)
            .is_some_and(|task| task.status == TaskStatus::Running),
        "a normal timeout must not cancel the selected task"
    );
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_reports_ready_instead_of_timeout_when_the_deadline_competes() {
    let harness = Harness::start("deadline-race").await;
    let held = harness.running_task("held-turn", "held").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let ids = [held.id.clone()];
    let waiting = access.wait(&ids, Duration::from_millis(100), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    harness.held.notify_waiters();
    tokio::time::advance(Duration::from_millis(100)).await;
    let observed = waiting.await.unwrap();
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks[0].status, TaskStatus::Succeeded);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn revoked_authority_denies_wait_and_cancel_without_replacing_the_registry() {
    let harness = Harness::start("revoked-authority").await;
    let target = harness.running_task("held-turn", "held").await;
    let authority = pl_core::tool::opaque::ToolAuthorization::unique();
    let (access, release, runner) = harness
        .retain_authorized_access("wait-turn", true, Some(authority.clone()))
        .await;
    authority.revoke();
    assert!(matches!(
        access
            .wait(&[], Duration::ZERO, CancellationToken::new())
            .await,
        Err(ThreadError::ToolPermissionRevoked)
    ));
    assert!(matches!(
        access.cancel(target.id.clone()).await,
        Err(ThreadError::ToolPermissionRevoked)
    ));
    assert_eq!(
        harness.thread.snapshot().tasks[&target.id].status,
        TaskStatus::Running
    );
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn wait_rejects_identity_authorization_and_stale_callers() {
    let harness = Harness::start("identity").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    assert!(matches!(
        access
            .wait(
                &["task:wait-waiter".into()],
                Duration::ZERO,
                CancellationToken::new()
            )
            .await,
        Err(ThreadError::TaskSelfWait)
    ));
    assert!(matches!(
        access
            .wait(
                &["task:missing".into()],
                Duration::ZERO,
                CancellationToken::new()
            )
            .await,
        Err(ThreadError::TaskNotFound { task_id }) if task_id == "task:missing"
    ));
    let other = Harness::start("other-thread").await;
    other.script(&["fast"]);
    other
        .thread
        .run_turn(support::turn("foreign"))
        .await
        .unwrap();
    let foreign = other
        .thread
        .snapshot()
        .terminal_tasks
        .iter()
        .chain(other.thread.snapshot().tasks.values())
        .find(|task| task.tool_id == "fast")
        .cloned()
        .expect("the other Thread committed a fast task");
    assert!(matches!(
        access
            .wait(
                std::slice::from_ref(&foreign.id),
                Duration::ZERO,
                CancellationToken::new()
            )
            .await,
        Err(ThreadError::TaskNotFound { task_id }) if task_id == foreign.id
    ));
    other.thread.close().await.unwrap();
    finish(release, runner).await;

    let (denied, denied_release, denied_runner) = harness.retain_access("denied-turn", false).await;
    assert!(matches!(
        denied
            .wait(&[], Duration::ZERO, CancellationToken::new())
            .await,
        Err(ThreadError::TaskAccessDenied)
    ));
    finish(denied_release, denied_runner).await;

    let (stale, stale_release, stale_runner) = harness.retain_access("stale-turn", true).await;
    finish(stale_release, stale_runner).await;
    assert!(matches!(
        stale
            .wait(&[], Duration::ZERO, CancellationToken::new())
            .await,
        Err(ThreadError::TaskAccessExpired)
    ));

    let (revoked, revoked_release, revoked_runner) =
        harness.retain_access("revoked-turn", true).await;
    let waiting = revoked.wait(&[], Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    harness
        .thread
        .register_tools(vec![
            Registration::prepare("fast".into(), OpaquePayload::text("fast"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(FastTool {
                    fail: false,
                })),
        ])
        .await
        .unwrap();
    assert!(matches!(
        waiting.await,
        Err(ThreadError::ToolPermissionRevoked)
    ));
    finish(revoked_release, revoked_runner).await;
    harness.thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn cancelling_or_closing_wait_is_not_a_timeout_or_success() {
    let harness = Harness::start("cancel-close").await;
    let held = harness.running_task("held-turn", "held").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let cancel = CancellationToken::new();
    let ids = [held.id.clone()];
    let waiting = access.wait(&ids, Duration::from_secs(5), cancel.clone());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    cancel.cancel();
    assert!(matches!(waiting.await, Err(ThreadError::Cancelled)));
    assert!(
        harness
            .thread
            .snapshot()
            .tasks
            .get(&held.id)
            .is_some_and(|task| task.status == TaskStatus::Running),
        "cancelling wait must not cancel the selected task"
    );
    finish(release, runner).await;

    let (closing_access, closing_release, closing_runner) =
        harness.retain_access("close-wait", true).await;
    let waiting = closing_access.wait(&[], Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    let closed = tokio::spawn({
        let thread = harness.thread.clone();
        async move { thread.close().await }
    });
    let wait_error = waiting.await.unwrap_err();
    assert!(
        matches!(
            wait_error,
            ThreadError::Closed | ThreadError::Cancelled | ThreadError::TaskAccessExpired
        ),
        "close must not look like a successful wait or a normal timeout: {wait_error:?}"
    );
    closing_release.notify_waiters();
    let _ = closing_runner.await;
    closed.await.unwrap().unwrap();
}

#[tokio::test]
async fn wait_reads_durable_terminal_state_after_the_resident_ledger_evicts_it() {
    let harness = Harness::start("durable-evict").await;
    harness.script(&["fast"]);
    let mut first = None;
    for index in 0..65 {
        let turn_id = format!("evict-{index}");
        harness
            .thread
            .run_turn(support::turn(&turn_id))
            .await
            .unwrap();
        if index == 0 {
            first = Some(format!("task:{turn_id}-fast"));
        }
    }
    let first = first.expect("the first finished task identity");
    let snapshot = harness.thread.snapshot();
    assert!(
        !snapshot.tasks.contains_key(&first)
            && !snapshot.terminal_tasks.iter().any(|task| task.id == first),
        "the 64-entry terminal ledger must have dropped the oldest finished task"
    );
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let observed = access
        .wait(
            std::slice::from_ref(&first),
            Duration::ZERO,
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks.len(), 1);
    assert_eq!(observed.tasks[0].id, first);
    assert_eq!(observed.tasks[0].status, TaskStatus::Succeeded);
    finish(release, runner).await;
    harness.thread.close().await.unwrap();
}
