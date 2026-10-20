//! Public-API coverage of unified task/message waiting.
//!
//! Wait reports one coherent observation: selected task records, whether unconsumed
//! messages are ready, and whether the fixed deadline was reached without readiness.
//! Complete payloads stay unconsumed for later model admission.
#[allow(dead_code)]
mod support;

use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex},
    time::Duration,
};

use pl_core::context::OpaquePayload;
use pl_core::model::{
    DynModelSession, ModelError, ModelRequest, ModelSession, ModelToolCall, PreparedModelCall,
    ToolProgressUpdate,
};
use pl_core::thread::{
    StepInput, TaskAccess, ThreadError, ThreadHandle, ToolDispatch,
    inbox::ThreadMessage,
    task::{TaskRecord, TaskStatus},
};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, Tool, ToolError},
};
use pretty_assertions::assert_eq;
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

use support::{response, text};

#[derive(Debug)]
struct HeldTool(Arc<Notify>);

impl Tool for HeldTool {
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
        Ok(ToolOutput::new(input, vec![text("held finished")]))
    }
}

#[derive(Debug)]
struct FastTool;

impl Tool for FastTool {
    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        Ok(ToolOutput::new(input, vec![text("fast finished")]))
    }
}

#[derive(Debug)]
struct AccessTool {
    started: mpsc::UnboundedSender<TaskAccess>,
    release: Arc<Notify>,
}

impl Tool for AccessTool {
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
        Ok(ToolOutput::new(input, vec![text("waiter finished")]))
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
        thread
            .register_tools(vec![
                Registration::new(
                    "held".into(),
                    OpaquePayload::text("held"),
                    HeldTool(held.clone()),
                )
                .unwrap(),
                Registration::new(
                    "held-b".into(),
                    OpaquePayload::text("held-b"),
                    HeldTool(held.clone()),
                )
                .unwrap(),
                Registration::new("fast".into(), OpaquePayload::text("fast"), FastTool).unwrap(),
            ])
            .await
            .unwrap();
        Self {
            thread,
            tools,
            held,
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
            ToolDispatch::Running(task) => task,
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
        let (started, mut ready) = mpsc::unbounded_channel();
        let release = Arc::new(Notify::new());
        let registration = Registration::new(
            "waiter".into(),
            OpaquePayload::text("waiter"),
            AccessTool {
                started,
                release: release.clone(),
            },
        )
        .unwrap();
        let registration = if waiting {
            registration.with_task_waiting()
        } else {
            registration.foreground_coexisting()
        };
        self.thread
            .register_tools(vec![
                Registration::new(
                    "held".into(),
                    OpaquePayload::text("held"),
                    HeldTool(self.held.clone()),
                )
                .unwrap(),
                Registration::new(
                    "held-b".into(),
                    OpaquePayload::text("held-b"),
                    HeldTool(self.held.clone()),
                )
                .unwrap(),
                Registration::new("fast".into(), OpaquePayload::text("fast"), FastTool).unwrap(),
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
async fn wait_returns_when_any_selected_task_finishes_while_another_is_running() {
    let harness = Harness::start("any-task").await;
    let first = harness.running_task("first", "held").await;
    let second = harness.running_task("second", "held-b").await;
    let (access, release, runner) = harness.retain_access("wait", true).await;
    let consumed = harness.thread.snapshot().consumed_messages;
    let ids = [first.id.clone(), second.id.clone()];
    let waiting = access.wait(&ids, Duration::from_secs(5), CancellationToken::new());
    tokio::pin!(waiting);
    assert_pending(&mut waiting).await;
    harness.held.notify_one();
    let observed = waiting.await.unwrap();
    assert!(!observed.timed_out);
    assert_eq!(observed.tasks.len(), 2);
    let finished = observed
        .tasks
        .iter()
        .filter(|task| task.status != TaskStatus::Running)
        .count();
    let running = observed
        .tasks
        .iter()
        .filter(|task| task.status == TaskStatus::Running)
        .count();
    assert_eq!(finished, 1);
    assert_eq!(running, 1);
    assert_eq!(harness.thread.snapshot().consumed_messages, consumed);
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
            Registration::new("fast".into(), OpaquePayload::text("fast"), FastTool).unwrap(),
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

#[cfg(feature = "sqlite")]
#[tokio::test]
async fn wait_reads_durable_terminal_state_after_the_resident_ledger_evicts_it() {
    use pl_core::persistence::SqliteSessionStore;
    use pl_core::thread::cold::ColdStoreHandle;

    let harness = Harness::start("durable-evict").await;
    let store = SqliteSessionStore::open_memory().await.unwrap();
    harness
        .thread
        .attach_storage(ColdStoreHandle::new(store))
        .await
        .unwrap();
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
    harness.thread.flush().await.unwrap();
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
