mod support;
#[path = "support/tool.rs"]
mod tool_support;

use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU64, Ordering},
};

use pl_core::context::{ContextContent, ContextSource, OpaquePayload};
use pl_core::model::DynModelSession;
use pl_core::thread::{
    ModelStepLimit, ThreadError, ThreadHandle, TurnOutcome, TurnState,
    cold::{
        ColdStore, ColdStoreError, ColdStoreHandle, StorageFaultKind, StoragePressure, ThreadWrite,
    },
    inbox::ThreadMessage,
    input::InputDriverOptions,
};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, Tool, ToolError},
};
use tokio::sync::watch;

use support::{ScriptedModel, turn};
use tool_support::tool;

#[derive(Debug)]
struct RetiringTool(tokio::sync::mpsc::UnboundedSender<&'static str>);

impl Tool for RetiringTool {
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
async fn replaced_tool_resources_are_closed_and_released_before_thread_close() {
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("retirement".into(), DynModelSession::new(model)).unwrap();
    for _ in 0..50 {
        let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
        thread
            .register_tools(vec![
                Registration::new(
                    "retiring".into(),
                    OpaquePayload::text("retiring"),
                    RetiringTool(events),
                )
                .unwrap(),
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
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let mut rejected = Box::pin(thread.register_tools_if_extensions(
        thread.snapshot().extension_sequence + 1,
        vec![
                Registration::new(
                    "rejected".into(),
                    OpaquePayload::text("rejected"),
                    RetiringTool(events),
                )
                .unwrap(),
            ],
    ));
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

#[derive(Debug)]
struct FailingClose {
    first: AtomicBool,
    panic_on_first: bool,
    events: tokio::sync::mpsc::UnboundedSender<&'static str>,
}
impl Tool for FailingClose {
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
                Registration::new(
                    "failed".into(),
                    OpaquePayload::text("failed"),
                    FailingClose {
                        first: AtomicBool::new(true),
                        panic_on_first,
                        events: events.clone(),
                    },
                )
                .unwrap(),
                Registration::new(
                    "successful".into(),
                    OpaquePayload::text("successful"),
                    RetiringTool(events),
                )
                .unwrap(),
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
impl Tool for InFlightTool {
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

#[tokio::test]
async fn a_replaced_executor_lives_until_its_in_flight_result_is_committed() {
    let (model, _) = ScriptedModel::new(&["leased"]);
    let thread = ThreadHandle::start("frozen-tool".into(), DynModelSession::new(model)).unwrap();
    let (events, mut received) = tokio::sync::mpsc::unbounded_channel();
    let release = Arc::new(tokio::sync::Notify::new());
    thread
        .register_tools(vec![
            Registration::new(
                "leased".into(),
                OpaquePayload::text("leased"),
                InFlightTool {
                    events,
                    release: release.clone(),
                },
            )
            .unwrap()
            .foreground_coexisting(),
        ])
        .await
        .unwrap();
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("lease")).await })
    };
    assert_eq!(received.recv().await, Some("executing"));
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

impl Tool for FenceTool {
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
            Registration::new(
                "fenced".into(),
                OpaquePayload::text("fenced tool"),
                FenceTool(fences.clone()),
            )
            .unwrap()
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
        .flat_map(|effect| effect.tasks.to_vec())
        .find_map(|task| task.started_sequence)
        .unwrap();
    assert_eq!(*fences.lock().unwrap(), vec![started]);
    thread.close().await.unwrap();
}

#[derive(Debug, Clone)]
struct FenceStore {
    entered: watch::Sender<Option<u64>>,
    released: watch::Sender<bool>,
    admitted: Arc<Mutex<Vec<ThreadWrite>>>,
    durable: Arc<AtomicU64>,
    fail_once: Arc<AtomicBool>,
}

impl ColdStore for FenceStore {
    fn admit(&self, _thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.admitted.lock().unwrap().push(write);
        Ok(())
    }

    fn pressure(&self, _thread_id: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    async fn flush(&self, _thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        self.entered.send_replace(Some(sequence));
        let mut released = self.released.subscribe();
        while !*released.borrow_and_update() {
            released.changed().await.unwrap();
        }
        assert!(
            self.admitted
                .lock()
                .unwrap()
                .iter()
                .any(|write| write.effect.sequence == sequence)
        );
        if self.fail_once.swap(false, Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("fence write failed")),
            });
        }
        self.durable.fetch_max(sequence, Ordering::SeqCst);
        Ok(())
    }
}

#[tokio::test(start_paused = true)]
async fn close_cancels_background_task_before_a_blocked_save_finishes() {
    use pl_core::thread::{ThreadLifecycle, ToolOutcome, task::TaskStatus};
    use std::time::Duration;
    use tokio_util::sync::CancellationToken;

    #[derive(Debug)]
    struct HeldUntilCancelled {
        started: tokio::sync::mpsc::UnboundedSender<CancellationToken>,
        closed: Arc<AtomicBool>,
    }

    impl Tool for HeldUntilCancelled {
        async fn execute(
            &self,
            _: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            let _ = self.started.send(context.cancellation.clone());
            context.cancellation.cancelled().await;
            Err(ToolError::new(ThreadError::Cancelled))
        }

        async fn close(&self) -> Result<(), ToolError> {
            self.closed.store(true, Ordering::SeqCst);
            Ok(())
        }
    }

    let (model, _) = ScriptedModel::new(&["held"]);
    let thread =
        ThreadHandle::start("close-save-fence".into(), DynModelSession::new(model)).unwrap();
    let (entered, mut entered_rx) = watch::channel(None);
    let (released, _) = watch::channel(true);
    let store = FenceStore {
        entered,
        released,
        admitted: Arc::new(Mutex::new(Vec::new())),
        durable: Arc::new(AtomicU64::new(0)),
        fail_once: Arc::new(AtomicBool::new(false)),
    };
    let (started, mut started_rx) = tokio::sync::mpsc::unbounded_channel();
    let tool_closed = Arc::new(AtomicBool::new(false));
    let mut saving = None;
    let mut closing = Box::pin(thread.close());
    let mut early_close = None;

    // Every observation error is deferred until the original save and close owners have joined.
    // In particular, the expected regression failure must not drop a blocked owner or its result.
    let observations: Result<_, String> = async {
        thread
            .attach_storage(ColdStoreHandle::new(store.clone()))
            .await
            .map_err(|error| error.to_string())?;
        thread
            .register_tools(vec![
                Registration::new(
                    "held".into(),
                    OpaquePayload::text("held until cancelled"),
                    HeldUntilCancelled {
                        started,
                        closed: tool_closed.clone(),
                    },
                )
                .map_err(|error| error.to_string())?,
            ])
            .await
            .map_err(|error| error.to_string())?;
        thread
            .run_turn(turn("background-before-close"))
            .await
            .map_err(|error| error.to_string())?;
        let cancellation = started_rx.recv().await.ok_or("tool never started")?;
        let task = thread
            .snapshot()
            .tasks
            .values()
            .find(|task| task.tool_id == "held")
            .cloned()
            .ok_or("running task missing")?;
        if task.status != TaskStatus::Running || task.acknowledgement.is_none() {
            return Err("the real task did not receive a running acknowledgement".into());
        }
        thread.interrupt();
        if cancellation.is_cancelled()
            || thread
                .snapshot()
                .tasks
                .get(&task.id)
                .is_none_or(|task| task.status != TaskStatus::Running)
        {
            return Err("ordinary interrupt cancelled the independent background task".into());
        }

        let durable_before = store.durable.load(Ordering::SeqCst);
        store.released.send_replace(false);
        store.entered.send_replace(None);
        saving = Some(tokio::spawn({
            let thread = thread.clone();
            async move { thread.flush().await }
        }));
        let sequence = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let Some(sequence) = *entered_rx.borrow_and_update() {
                    break Ok::<_, String>(sequence);
                }
                entered_rx
                    .changed()
                    .await
                    .map_err(|error| error.to_string())?;
            }
        })
        .await
        .map_err(|error| error.to_string())??;
        if sequence <= durable_before {
            return Err("save gate did not block an unconfirmed admitted fact".into());
        }

        // Poll the actual public close, so begin_close has sealed admission and sent its request.
        // Observe the token received by the real executor, not a test-created cancellation token.
        if let std::task::Poll::Ready(result) = futures::poll!(&mut closing) {
            early_close = Some(result);
        }
        let stopped_before_release =
            tokio::time::timeout(Duration::from_secs(5), cancellation.cancelled())
                .await
                .is_ok();
        let save_still_pending = !saving.as_ref().unwrap().is_finished()
            && store.durable.load(Ordering::SeqCst) == durable_before
            && !*store.released.borrow();
        Ok((
            task,
            stopped_before_release,
            save_still_pending,
            early_close.is_none(),
        ))
    }
    .await;

    store.released.send_replace(true);
    let saved = match saving {
        Some(saving) => Some(saving.await),
        None => None,
    };
    let closed = match early_close {
        Some(result) => result,
        None => closing.await,
    };
    // No assertion above can abandon a held save. Both original owners have now returned.
    closed.expect("original Thread owner must finish close after save release");
    if let Some(saved) = saved {
        saved
            .expect("save waiter must join")
            .expect("save must finish");
    }
    let (task, stopped_before_release, save_still_pending, close_still_pending) =
        observations.expect("regression setup must exercise a running task and a real save gate");
    let snapshot = thread.snapshot();
    assert_eq!(snapshot.lifecycle, ThreadLifecycle::Closed);
    assert!(tool_closed.load(Ordering::SeqCst));
    let terminal = snapshot
        .tasks
        .get(&task.id)
        .expect("accepted task retained");
    assert_eq!(terminal.status, TaskStatus::Cancelled);
    assert_eq!(terminal.acknowledgement, task.acknowledgement);
    let acknowledgement = task.acknowledgement.as_ref().unwrap();
    assert!(
        snapshot
            .context
            .records
            .iter()
            .any(|record| record.id == acknowledgement.record_id)
    );
    let writes = store.admitted.lock().unwrap();
    assert!(
        writes
            .windows(2)
            .all(|pair| pair[0].effect.sequence < pair[1].effect.sequence)
    );
    assert!(
        writes
            .iter()
            .any(|write| write.effect.tasks.contains(&task))
    );
    assert!(
        writes
            .iter()
            .any(|write| write.effect.tasks.contains(terminal))
    );
    assert_eq!(
        writes
            .iter()
            .flat_map(|write| write.effect.deliveries.iter())
            .filter(|delivery| delivery.call_id == task.call_id
                && matches!(delivery.outcome, ToolOutcome::Cancelled))
            .count(),
        1,
        "the same real task must have one retained terminal delivery"
    );
    assert_eq!(
        store.durable.load(Ordering::SeqCst),
        writes.last().unwrap().effect.sequence
    );
    eprintln!(
        "save_pending={save_still_pending} close_pending={close_still_pending} \
         cancelled_before_release={stopped_before_release}; save/close joined, \
         task acknowledgement and terminal delivery retained"
    );
    assert!(save_still_pending && close_still_pending);
    assert!(
        stopped_before_release,
        "global Thread close must signal the running background task before the blocked save finishes"
    );
}

#[derive(Debug)]
struct SideEffectTool(Arc<AtomicBool>);

impl Tool for SideEffectTool {
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
async fn attached_store_must_flush_the_start_fact_before_a_tool_runs() {
    let (model, _) = ScriptedModel::new(&["fenced"]);
    let thread = ThreadHandle::start("durable-fence".into(), DynModelSession::new(model)).unwrap();
    let (entered, mut observed) = watch::channel(None);
    let (released, _) = watch::channel(false);
    let executed = Arc::new(AtomicBool::new(false));
    let store = FenceStore {
        entered,
        released: released.clone(),
        admitted: Arc::new(Mutex::new(Vec::new())),
        durable: Arc::new(AtomicU64::new(0)),
        fail_once: Arc::new(AtomicBool::new(false)),
    };
    thread
        .attach_storage(ColdStoreHandle::new(store))
        .await
        .unwrap();
    thread
        .register_tools(vec![
            Registration::new(
                "fenced".into(),
                OpaquePayload::text("fenced tool"),
                SideEffectTool(executed.clone()),
            )
            .unwrap()
            .foreground_coexisting(),
        ])
        .await
        .unwrap();

    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("fenced-turn")).await }
    });
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while observed.borrow().is_none() {
            observed.changed().await.unwrap();
        }
    })
    .await
    .unwrap();
    assert!(!executed.load(Ordering::SeqCst));
    assert!(!runner.is_finished());
    released.send_replace(true);
    tokio::time::timeout(std::time::Duration::from_secs(5), runner)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(executed.load(Ordering::SeqCst));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn failed_tool_fence_blocks_the_executor_and_latches_storage_fault() {
    let (model, _) = ScriptedModel::new(&["fenced"]);
    let thread = ThreadHandle::start("failed-fence".into(), DynModelSession::new(model)).unwrap();
    let (entered, _) = watch::channel(None);
    let (released, _) = watch::channel(true);
    let executed = Arc::new(AtomicBool::new(false));
    let store = FenceStore {
        entered,
        released,
        admitted: Arc::new(Mutex::new(Vec::new())),
        durable: Arc::new(AtomicU64::new(0)),
        fail_once: Arc::new(AtomicBool::new(true)),
    };
    thread
        .attach_storage(ColdStoreHandle::new(store))
        .await
        .unwrap();
    thread
        .register_tools(vec![
            Registration::new(
                "fenced".into(),
                OpaquePayload::text("fenced tool"),
                SideEffectTool(executed.clone()),
            )
            .unwrap()
            .foreground_coexisting(),
        ])
        .await
        .unwrap();

    let mut snapshots = thread.subscribe();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("failed-turn")).await }
    });
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        loop {
            let snapshot = snapshots.next().await.unwrap();
            if snapshot.persistence.fault == Some(StorageFaultKind::WriteFailed) {
                assert!(snapshot.persistence.resume_required);
                break;
            }
        }
    })
    .await
    .unwrap();
    assert!(!executed.load(Ordering::SeqCst));
    if !runner.is_finished() {
        let _ = thread.interrupt_turn(Some("failed-turn".into())).await;
    }
    let _ = tokio::time::timeout(std::time::Duration::from_secs(5), runner)
        .await
        .unwrap();
    thread.flush().await.unwrap();
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
