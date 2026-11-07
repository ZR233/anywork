//! Public-API behaviour of the explicit model execution phase.
//!
//! The phase must describe the real call boundary of one attempt: preparing the request is not the
//! provider call, admission is not a provider wait, and only the running prepared call may be read
//! as "waiting for the model implementation". Every exit path (success, failure, cancellation) must
//! clear the phase so a projection never reads a phase left over from a finished step.

use std::sync::Arc;

use pl_core::context::ContextContent;
use pl_core::model::{
    DynModelSession, ModelError, ModelFailureKind, ModelRequest, ModelSession, ModelStepOutput,
    ModelToolCall, PreparedModelCall,
};
use pl_core::thread::{
    ContextCompactionEvent, ContextCompactionOutcome, ModelExecutionPhase, ModelStepLimit,
    ThreadError, ThreadHandle, TurnInput, TurnOutcome,
};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

fn text(value: &str) -> ContextContent {
    ContextContent::Text {
        text: Arc::from(value),
    }
}

fn turn(id: &str) -> TurnInput {
    TurnInput {
        turn_id: id.into(),
        attempt_prefix: format!("attempt-{id}"),
        content: vec![text("Please handle this request")],
        max_model_steps: ModelStepLimit::Limited(3.try_into().expect("nonzero limit")),
        cancellation: CancellationToken::new(),
    }
}

fn response(request: &ModelRequest, tool_calls: Vec<ModelToolCall>) -> ModelStepOutput {
    ModelStepOutput {
        turn_action: Default::default(),
        attempt_id: request.attempt_id.clone(),
        base_context_revision: request.context.revision,
        content: vec![text(if tool_calls.is_empty() {
            "Answer completed"
        } else {
            "Calling tools"
        })],
        tool_calls,
        private_context: None,
        usage: Default::default(),
    }
}

/// A session whose `prepare` and executed call are each held at an explicit gate.
///
/// The gates are one-shot: each of them can be observed and released exactly once, so the test knows
/// which boundary the driver is waiting at instead of guessing from timing.
struct GatedModel {
    prepare_entered: Option<oneshot::Sender<()>>,
    prepare_release: Option<oneshot::Receiver<()>>,
    execute_entered: Option<oneshot::Sender<()>>,
    execute_release: Option<oneshot::Receiver<()>>,
    prepare_failure: Option<ModelFailureKind>,
    execute_failure: Option<ModelFailureKind>,
}

fn model_failure(kind: ModelFailureKind) -> ModelError {
    ModelError {
        details: None,
        kind,
        usage: Default::default(),
        source: None,
    }
}

/// One gated provider call: report entry, wait for the gate (or the Turn cancellation) and then either
/// fail with the injected kind or return the scripted response.
async fn gated_call(
    entered: Option<oneshot::Sender<()>>,
    release: Option<oneshot::Receiver<()>>,
    failure_kind: Option<ModelFailureKind>,
    request: ModelRequest,
) -> Result<ModelStepOutput, ModelError> {
    if let Some(entered) = entered {
        entered
            .send(())
            .expect("execute gate owner must still exist");
    }
    if let Some(release) = release {
        // Either the owner opens the gate or the Turn is cancelled: both end this call without
        // inventing a result.
        let cancelled = tokio::select! {
            _ = release => false,
            () = request.cancellation.cancelled() => true,
        };
        if cancelled {
            return Err(model_failure(ModelFailureKind::Cancelled));
        }
    }
    match failure_kind {
        Some(kind) => Err(model_failure(kind)),
        None => Ok(response(&request, Vec::new())),
    }
}

impl ModelSession for GatedModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        if let Some(entered) = self.prepare_entered.take() {
            entered
                .send(())
                .expect("prepare gate owner must still exist");
        }
        if let Some(release) = self.prepare_release.take() {
            release.await.expect("prepare gate must be opened");
        }
        if let Some(kind) = self.prepare_failure.take() {
            return Err(model_failure(kind));
        }
        let entered = self.execute_entered.take();
        let release = self.execute_release.take();
        let failure_kind = self.execute_failure.take();
        Ok(PreparedModelCall::new(gated_call(
            entered,
            release,
            failure_kind,
            request,
        )))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

impl GatedModel {
    fn idle() -> Self {
        Self {
            prepare_entered: None,
            prepare_release: None,
            execute_entered: None,
            execute_release: None,
            prepare_failure: None,
            execute_failure: None,
        }
    }
}

#[tokio::test]
async fn preparing_the_request_is_not_reported_as_the_running_call() {
    let (prepare_entered, prepare_wait) = oneshot::channel();
    let (prepare_gate, prepare_release) = oneshot::channel();
    let (execute_entered, execute_wait) = oneshot::channel();
    let (execute_gate, execute_release) = oneshot::channel();
    let thread = ThreadHandle::start(
        "phase-thread".into(),
        DynModelSession::new(GatedModel {
            prepare_entered: Some(prepare_entered),
            prepare_release: Some(prepare_release),
            execute_entered: Some(execute_entered),
            execute_release: Some(execute_release),
            ..GatedModel::idle()
        }),
    )
    .unwrap();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("phase-turn")).await }
    });

    // The request is being prepared inside the model implementation; nothing has been dispatched yet.
    prepare_wait.await.expect("prepare must be entered");
    assert_eq!(
        thread.snapshot().model_execution,
        Some(ModelExecutionPhase::PreparingRequest)
    );
    // A mailbox commit republishes the snapshot while prepare owns the session.
    // Borrowing it for preparation must not look like a missing model binding.
    thread
        .send_message(pl_core::thread::inbox::ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Report,
            id: "during-prepare".into(),
            source_id: "observer".into(),
            payload: pl_core::context::OpaquePayload::text("status update"),
            context: Vec::new(),
        })
        .await
        .unwrap();
    assert!(thread.snapshot().model_available);

    prepare_gate.send(()).expect("prepare gate must be open");
    execute_wait.await.expect("execute must be entered");
    assert_eq!(
        thread.snapshot().model_execution,
        Some(ModelExecutionPhase::Running)
    );
    assert!(thread.snapshot().model_available);

    execute_gate.send(()).expect("execute gate must be open");
    let completion = runner.await.unwrap().unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    assert_eq!(thread.snapshot().model_execution, None);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_failed_step_clears_the_execution_phase_and_leaves_the_thread_usable() {
    let thread = ThreadHandle::start(
        "failed-thread".into(),
        DynModelSession::new(GatedModel {
            execute_failure: Some(ModelFailureKind::InvalidResponse),
            ..GatedModel::idle()
        }),
    )
    .unwrap();

    let error = thread.run_turn(turn("failed-turn")).await.unwrap_err();
    assert!(matches!(error, ThreadError::Model(_)));
    assert_eq!(thread.snapshot().model_execution, None);

    let next = thread.run_turn(turn("after-failure")).await.unwrap();
    assert_eq!(next.outcome, TurnOutcome::Completed);
    assert_eq!(thread.snapshot().model_execution, None);
    thread.close().await.unwrap();
}

/// Request preparation failing is another exit path that must not leave a phase behind: the phase
/// claimed `PreparingRequest`, and a projection reading it after the failure would report a driver
/// that is no longer waiting for anything.
#[tokio::test]
async fn a_failed_request_preparation_clears_the_execution_phase() {
    let thread = ThreadHandle::start(
        "prepare-failed-thread".into(),
        DynModelSession::new(GatedModel {
            prepare_failure: Some(ModelFailureKind::Unavailable),
            ..GatedModel::idle()
        }),
    )
    .unwrap();

    let error = thread
        .run_turn(turn("prepare-failed-turn"))
        .await
        .unwrap_err();
    assert!(matches!(error, ThreadError::Model(_)));
    assert_eq!(thread.snapshot().model_execution, None);

    let next = thread
        .run_turn(turn("after-prepare-failure"))
        .await
        .unwrap();
    assert_eq!(next.outcome, TurnOutcome::Completed);
    assert_eq!(thread.snapshot().model_execution, None);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_cancelled_execution_clears_the_execution_phase() {
    let (execute_entered, execute_wait) = oneshot::channel();
    let (execute_gate, execute_release) = oneshot::channel();
    let thread = ThreadHandle::start(
        "cancelled-phase-thread".into(),
        DynModelSession::new(GatedModel {
            execute_entered: Some(execute_entered),
            execute_release: Some(execute_release),
            ..GatedModel::idle()
        }),
    )
    .unwrap();
    let input = turn("cancel-phase-turn");
    let cancellation = input.cancellation.clone();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(input).await }
    });

    execute_wait.await.expect("execute must be entered");
    assert_eq!(
        thread.snapshot().model_execution,
        Some(ModelExecutionPhase::Running)
    );
    cancellation.cancel();

    assert!(matches!(runner.await.unwrap(), Err(ThreadError::Cancelled)));
    assert_eq!(thread.snapshot().model_execution, None);
    // The gate is still owned by the test, so the cancelled call can never be mistaken for a result.
    drop(execute_gate);

    let next = thread.run_turn(turn("after-cancel")).await.unwrap();
    assert_eq!(next.outcome, TurnOutcome::Completed);
    assert_eq!(thread.snapshot().model_execution, None);
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct GatedCompactionHook {
    entered: std::sync::Mutex<Option<oneshot::Sender<()>>>,
    start_compacting: std::sync::Mutex<Option<oneshot::Receiver<()>>>,
    finish_compacting: std::sync::Mutex<Option<oneshot::Receiver<()>>>,
}

impl pl_core::thread::context_preparation::ContextPreparationHook for GatedCompactionHook {
    async fn before_step(
        &self,
        request: pl_core::thread::context_preparation::ContextPreparationRequest,
    ) -> pl_core::thread::context_preparation::ContextPreparation {
        if let Some(entered) = self.entered.lock().unwrap().take() {
            let _ = entered.send(());
        }
        let start_rx = self.start_compacting.lock().unwrap().take();
        if let Some(rx) = start_rx {
            let _ = rx.await;
        }
        request
            .enter_compacting()
            .await
            .expect("owner admits compaction");
        let finish_rx = self.finish_compacting.lock().unwrap().take();
        if let Some(rx) = finish_rx {
            let _ = rx.await;
        }
        pl_core::thread::context_preparation::ContextPreparation::Unchanged
    }
}

#[tokio::test]
async fn context_preparation_transitions_to_compacting_context_when_compaction_enters() {
    let (entered_tx, entered_rx) = oneshot::channel();
    let (start_compact_tx, start_compact_rx) = oneshot::channel();
    let (finish_compact_tx, finish_compact_rx) = oneshot::channel();

    let thread = ThreadHandle::start(
        "compacting-phase-thread".into(),
        DynModelSession::new(GatedModel::idle()),
    )
    .unwrap();
    let store = CompactionStore::default();
    *store.thread.lock().unwrap() = Some(thread.clone());
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .set_context_preparation(Some(
            pl_core::thread::context_preparation::ContextPreparer::new(GatedCompactionHook {
                entered: std::sync::Mutex::new(Some(entered_tx)),
                start_compacting: std::sync::Mutex::new(Some(start_compact_rx)),
                finish_compacting: std::sync::Mutex::new(Some(finish_compact_rx)),
            }),
        ))
        .await
        .unwrap();

    let mut state_rx = thread.subscribe();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("compacting-turn")).await }
    });

    entered_rx.await.expect("hook must be entered");
    assert!(
        compaction_events(&thread).await.is_empty(),
        "preparing is not compaction"
    );
    assert_eq!(
        thread.snapshot().model_execution,
        Some(ModelExecutionPhase::PreparingContext)
    );

    start_compact_tx.send(()).expect("trigger compacting");
    loop {
        let snapshot = state_rx.next().await.expect("subscription must stay open");
        if snapshot.model_execution == Some(ModelExecutionPhase::CompactingContext) {
            break;
        }
    }
    assert_eq!(
        thread.snapshot().model_execution,
        Some(ModelExecutionPhase::CompactingContext)
    );
    assert!(matches!(compaction_events(&thread).await.as_slice(),
        [ContextCompactionEvent::Started { turn_id: Some(turn_id), attempt_id: None, .. }]
            if turn_id == "compacting-turn"));
    assert_eq!(
        store.events.lock().unwrap().len(),
        1,
        "the reliable start reached storage admission before the CompactingContext snapshot"
    );

    finish_compact_tx.send(()).expect("finish compacting");
    let completion = runner.await.unwrap().unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    assert_eq!(thread.snapshot().model_execution, None);
    assert_eq!(
        assert_compaction_pair(&thread).await.1,
        ContextCompactionOutcome::Unchanged
    );
    thread.close().await.unwrap();
}

#[derive(Debug, Clone, Default)]
struct CompactionStore(Arc<CompactionStoreState>);

impl std::ops::Deref for CompactionStore {
    type Target = CompactionStoreState;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

#[derive(Debug, Default)]
struct CompactionStoreState {
    thread: std::sync::Mutex<Option<ThreadHandle>>,
    events: std::sync::Mutex<Vec<ContextCompactionEvent>>,
    reject_finished: std::sync::atomic::AtomicBool,
    reject_replacement_once: std::sync::atomic::AtomicBool,
    replacement_refusals: std::sync::atomic::AtomicUsize,
    replacement_admissions: std::sync::atomic::AtomicUsize,
}

impl pl_core::thread::cold::ColdStore for CompactionStore {
    fn admit(
        &self,
        _: &str,
        write: pl_core::thread::cold::ThreadWrite,
    ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        if write.effect.replacements.iter().any(|replacement| {
            replacement.reason == pl_core::thread::ContextReplacementReason::Compaction
        }) {
            use std::sync::atomic::Ordering;
            if self.reject_replacement_once.swap(false, Ordering::SeqCst) {
                self.replacement_refusals.fetch_add(1, Ordering::SeqCst);
                return Err(pl_core::thread::cold::ColdStoreError {
                    source: Box::new(std::io::Error::other(
                        "controlled one-shot replacement save failure",
                    )),
                });
            }
            self.replacement_admissions.fetch_add(1, Ordering::SeqCst);
        }
        for event in write.effect.context_compactions.iter() {
            match event {
                ContextCompactionEvent::Started { .. } => {
                    let thread = self.thread.lock().unwrap();
                    assert_ne!(
                        thread.as_ref().unwrap().snapshot().model_execution,
                        Some(ModelExecutionPhase::CompactingContext),
                        "start must precede the replaceable phase snapshot"
                    );
                }
                ContextCompactionEvent::Finished { .. }
                    if self
                        .reject_finished
                        .load(std::sync::atomic::Ordering::SeqCst) =>
                {
                    return Err(pl_core::thread::cold::ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "controlled compaction save failure",
                        )),
                    });
                }
                _ => {}
            }
        }
        self.events
            .lock()
            .unwrap()
            .extend(write.effect.context_compactions.iter().cloned());
        Ok(())
    }

    async fn flush(&self, _: &str, _: u64) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        Ok(())
    }
}

async fn compaction_events(thread: &ThreadHandle) -> Vec<ContextCompactionEvent> {
    thread
        .effects()
        .await
        .unwrap()
        .iter()
        .flat_map(|effect| effect.context_compactions.iter().cloned())
        .collect()
}

async fn assert_compaction_pair(thread: &ThreadHandle) -> (String, ContextCompactionOutcome) {
    let events = compaction_events(thread).await;
    let [
        ContextCompactionEvent::Started { operation_id, .. },
        ContextCompactionEvent::Finished {
            operation_id: finished,
            outcome,
        },
    ] = events.as_slice()
    else {
        panic!("one actual operation must have one ordered start/end pair: {events:?}");
    };
    assert_eq!(operation_id, finished);
    assert!(!operation_id.is_empty());
    (operation_id.clone(), outcome.clone())
}

#[derive(Debug, Clone, Copy)]
enum CompactionEnd {
    NoStart,
    Unchanged,
    Changed,
    RejectedReplacement,
    Failed,
    Panic,
    Cancelled,
    Queued,
}

#[derive(Debug)]
struct LifecycleHook {
    end: CompactionEnd,
    only_force: bool,
    started: Arc<tokio::sync::Notify>,
    cleaned: Arc<std::sync::atomic::AtomicBool>,
}

impl pl_core::thread::context_preparation::ContextPreparationHook for LifecycleHook {
    async fn before_step(
        &self,
        request: pl_core::thread::context_preparation::ContextPreparationRequest,
    ) -> pl_core::thread::context_preparation::ContextPreparation {
        use pl_core::thread::context_preparation::ContextPreparation;
        if matches!(self.end, CompactionEnd::NoStart)
            || (self.only_force && !request.force_compaction)
        {
            return ContextPreparation::Unchanged;
        }
        if matches!(self.end, CompactionEnd::Queued) {
            use futures::FutureExt;
            // Even a producer returning in the same poll as an enqueued start cannot lose the fact.
            assert!(request.enter_compacting().now_or_never().is_none());
            return ContextPreparation::Unchanged;
        }
        request.enter_compacting().await.unwrap();
        request.enter_compacting().await.unwrap();
        self.started.notify_one();
        match self.end {
            CompactionEnd::Changed | CompactionEnd::RejectedReplacement => {
                ContextPreparation::Prepared {
                    expected_extension_sequence: request.extension_sequence,
                    rejected_mutations: vec![],
                    replacement: Some(pl_core::thread::ReplaceContext {
                        expected_revision: request.committed_context.revision,
                        reason: pl_core::thread::ContextReplacementReason::Compaction,
                        records: if matches!(self.end, CompactionEnd::RejectedReplacement) {
                            vec![pl_core::context::ContextRecord {
                                id: String::new(),
                                turn_id: None,
                                source: pl_core::context::ContextSource::User,
                                content: vec![text("rejected replacement")],
                                tool_calls: vec![],
                            }]
                        } else {
                            request.committed_context.records.to_vec()
                        },
                    }),
                    facts: request.current_facts.to_vec(),
                    mutations: vec![],
                    excluded_tool_ids: vec![],
                }
            }
            CompactionEnd::Failed => ContextPreparation::Failed {
                error: model_failure(ModelFailureKind::InvalidResponse),
                mutations: vec![],
            },
            CompactionEnd::Panic => panic!("controlled compaction panic"),
            CompactionEnd::Cancelled => {
                request.model.cancellation.cancelled().await;
                self.cleaned
                    .store(true, std::sync::atomic::Ordering::SeqCst);
                ContextPreparation::Unchanged
            }
            _ => ContextPreparation::Unchanged,
        }
    }
}

async fn install_lifecycle_hook(
    thread: &ThreadHandle,
    end: CompactionEnd,
    only_force: bool,
) -> (Arc<tokio::sync::Notify>, Arc<std::sync::atomic::AtomicBool>) {
    let started = Arc::new(tokio::sync::Notify::new());
    let cleaned = Arc::new(std::sync::atomic::AtomicBool::new(false));
    thread
        .set_context_preparation(Some(
            pl_core::thread::context_preparation::ContextPreparer::new(LifecycleHook {
                end,
                only_force,
                started: started.clone(),
                cleaned: cleaned.clone(),
            }),
        ))
        .await
        .unwrap();
    (started, cleaned)
}

#[tokio::test]
async fn actual_compaction_closes_fast_unchanged_changed_failed_and_panicked_operations() {
    for end in [
        CompactionEnd::NoStart,
        CompactionEnd::Unchanged,
        CompactionEnd::Changed,
        CompactionEnd::RejectedReplacement,
        CompactionEnd::Failed,
        CompactionEnd::Panic,
        CompactionEnd::Queued,
    ] {
        let thread = ThreadHandle::start(
            "compaction-results".into(),
            DynModelSession::new(GatedModel::idle()),
        )
        .unwrap();
        install_lifecycle_hook(&thread, end, false).await;
        let result = thread.run_turn(turn("compaction-result-turn")).await;
        assert_eq!(
            result.is_err(),
            matches!(
                end,
                CompactionEnd::Failed | CompactionEnd::Panic | CompactionEnd::RejectedReplacement
            )
        );
        assert_eq!(thread.snapshot().model_execution, None);
        let effects = thread.effects().await.unwrap();
        let turn_state = &effects
            .iter()
            .filter_map(|effect| effect.turn.as_ref())
            .next_back()
            .unwrap()
            .state;
        if matches!(
            end,
            CompactionEnd::Failed | CompactionEnd::Panic | CompactionEnd::RejectedReplacement
        ) {
            assert!(matches!(
                turn_state,
                pl_core::thread::TurnState::Failed { .. }
            ));
        } else {
            assert_eq!(
                turn_state,
                &pl_core::thread::TurnState::Finished(TurnOutcome::Completed)
            );
        }
        if matches!(end, CompactionEnd::NoStart) {
            assert!(compaction_events(&thread).await.is_empty());
        } else {
            let (_, outcome) = assert_compaction_pair(&thread).await;
            match end {
                CompactionEnd::Changed => {
                    let ContextCompactionOutcome::Changed { context_revision } = outcome else {
                        panic!("accepted replacement changes context");
                    };
                    assert!(thread.effects().await.unwrap().iter().any(|e| {
                        e.replacements
                            .iter()
                            .any(|r| r.current.revision == context_revision)
                    }));
                }
                CompactionEnd::Failed
                | CompactionEnd::Panic
                | CompactionEnd::RejectedReplacement => {
                    assert!(matches!(outcome, ContextCompactionOutcome::Failed { .. }))
                }
                _ => assert_eq!(outcome, ContextCompactionOutcome::Unchanged),
            }
        }
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn cancelled_compaction_finishes_producer_before_its_terminal_fact() {
    for idle in [false, true] {
        let thread = ThreadHandle::start(
            "cancel-compaction".into(),
            DynModelSession::new(GatedModel::idle()),
        )
        .unwrap();
        if idle {
            thread.run_turn(turn("old-completed-turn")).await.unwrap();
        }
        let (started, cleaned) =
            install_lifecycle_hook(&thread, CompactionEnd::Cancelled, false).await;
        let input = turn("cancel-compaction-turn");
        let cancellation = input.cancellation.clone();
        let task = {
            let thread = thread.clone();
            tokio::spawn(async move {
                if idle {
                    thread
                        .compact_context(thread.snapshot().context.revision, input.cancellation)
                        .await
                        .map(|_| ())
                } else {
                    thread.run_turn(input).await.map(|_| ())
                }
            })
        };
        tokio::time::timeout(std::time::Duration::from_secs(5), started.notified())
            .await
            .unwrap();
        cancellation.cancel();
        assert!(matches!(task.await.unwrap(), Err(ThreadError::Cancelled)));
        assert!(cleaned.load(std::sync::atomic::Ordering::SeqCst));
        assert_eq!(
            assert_compaction_pair(&thread).await.1,
            ContextCompactionOutcome::Cancelled
        );
        assert_eq!(thread.snapshot().model_execution, None);
        if idle {
            assert!(matches!(
                &compaction_events(&thread).await[0],
                ContextCompactionEvent::Started {
                    turn_id: None,
                    attempt_id: None,
                    ..
                }
            ));
            assert!(
                thread
                    .snapshot()
                    .turns
                    .iter()
                    .all(|turn| turn.state != pl_core::thread::TurnState::Running)
            );
        } else {
            let effects = thread.effects().await.unwrap();
            assert_eq!(
                &effects
                    .iter()
                    .filter_map(|effect| effect.turn.as_ref())
                    .next_back()
                    .unwrap()
                    .state,
                &pl_core::thread::TurnState::Cancelled
            );
        }
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn force_and_host_share_one_operation_and_idle_does_not_borrow_an_old_turn() {
    for during_execution in [false, true] {
        let mut model = GatedModel::idle();
        if during_execution {
            model.execute_failure = Some(ModelFailureKind::ContextLimit);
        } else {
            model.prepare_failure = Some(ModelFailureKind::ContextLimit);
        }
        let thread =
            ThreadHandle::start("forced-compaction".into(), DynModelSession::new(model)).unwrap();
        let store = CompactionStore::default();
        *store.thread.lock().unwrap() = Some(thread.clone());
        thread
            .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(store))
            .await
            .unwrap();
        install_lifecycle_hook(&thread, CompactionEnd::Changed, true).await;
        thread.run_turn(turn("force-turn")).await.unwrap();
        let (first_id, _) = assert_compaction_pair(&thread).await;
        let events = compaction_events(&thread).await;
        let ContextCompactionEvent::Started {
            turn_id,
            attempt_id,
            ..
        } = &events[0]
        else {
            unreachable!()
        };
        assert_eq!(turn_id.as_deref(), Some("force-turn"));
        if let Some(attempt_id) = attempt_id {
            assert!(
                thread
                    .effects()
                    .await
                    .unwrap()
                    .iter()
                    .filter_map(|e| e.attempt.as_ref())
                    .any(|a| &a.attempt_id == attempt_id),
                "source association references the authoritative attempt, even after hot eviction"
            );
        }
        if during_execution {
            assert!(
                attempt_id.is_some(),
                "service recovery names a real attempt"
            );
        }
        let before = thread.snapshot();
        assert!(
            before
                .context
                .records
                .iter()
                .any(|r| r.turn_id.as_deref() == Some("force-turn"))
        );
        let compacted = thread
            .compact_context(before.context.revision, CancellationToken::new())
            .await
            .unwrap();
        assert!(compacted.revision > before.context.revision);
        let events = compaction_events(&thread).await;
        assert!(matches!(&events[2], ContextCompactionEvent::Started {
            operation_id, turn_id: None, attempt_id: None,
        } if operation_id != &first_id));
        assert!(matches!(&events[3], ContextCompactionEvent::Finished {
            outcome: ContextCompactionOutcome::Changed { context_revision }, ..
        } if *context_revision == compacted.revision));
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn compaction_save_failure_keeps_the_finished_obligation_and_does_not_report_success() {
    use std::sync::atomic::Ordering;
    let thread = ThreadHandle::start(
        "save-compaction".into(),
        DynModelSession::new(GatedModel::idle()),
    )
    .unwrap();
    let store = CompactionStore::default();
    *store.thread.lock().unwrap() = Some(thread.clone());
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    install_lifecycle_hook(&thread, CompactionEnd::Unchanged, false).await;
    store.reject_finished.store(true, Ordering::SeqCst);
    assert!(thread.run_turn(turn("save-compaction-turn")).await.is_err());
    assert_eq!(
        assert_compaction_pair(&thread).await.1,
        ContextCompactionOutcome::Unchanged,
        "the pending fact records the actual no-replacement result, not a fabricated success"
    );
    assert_eq!(store.events.lock().unwrap().len(), 1);
    assert!(thread.snapshot().persistence.resume_required);
    store.reject_finished.store(false, Ordering::SeqCst);
    thread.flush().await.unwrap();
    assert_eq!(store.events.lock().unwrap().len(), 2);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn replacement_save_refusal_survives_finished_retry_without_provider_execution() {
    use std::sync::atomic::Ordering;
    let (execute_entered, mut execute_wait) = oneshot::channel();
    let thread = ThreadHandle::start(
        "one-shot-save".into(),
        DynModelSession::new(GatedModel {
            execute_entered: Some(execute_entered),
            ..GatedModel::idle()
        }),
    )
    .unwrap();
    let store = CompactionStore::default();
    *store.thread.lock().unwrap() = Some(thread.clone());
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    install_lifecycle_hook(&thread, CompactionEnd::Changed, false).await;
    store.reject_replacement_once.store(true, Ordering::SeqCst);
    let error = thread
        .run_turn(turn("one-shot-save-turn"))
        .await
        .unwrap_err();
    assert!(
        matches!(error, ThreadError::Storage(ref source)
        if source.to_string().contains("controlled one-shot replacement save failure")),
        "return the original rejection, not a later healthy retry: {error}"
    );
    assert_eq!(store.replacement_refusals.load(Ordering::SeqCst), 1);
    assert_eq!(
        store.replacement_admissions.load(Ordering::SeqCst),
        1,
        "Finished publication retries and admits the canonical replacement"
    );
    assert_eq!(store.events.lock().unwrap().len(), 2);
    assert!(
        thread.snapshot().persistence.error.is_none(),
        "the second publication cleared the transient writer error"
    );
    assert!(
        thread.snapshot().persistence.resume_required,
        "a healthy retry cannot release the explicit recovery latch"
    );
    assert!(
        matches!(
            execute_wait.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ),
        "the rejected save must prevent subsequent provider execution"
    );
    let (_, outcome) = assert_compaction_pair(&thread).await;
    assert_eq!(
        outcome,
        ContextCompactionOutcome::Changed {
            context_revision: thread.snapshot().context.revision,
        },
        "retain the actual canonical replacement outcome, not a fabricated Failed/Cancelled"
    );
    assert_eq!(thread.snapshot().model_execution, None);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn local_capacity_recovery_without_hook_has_no_compaction_operation() {
    let (prepare_entered, prepare_wait) = oneshot::channel();
    let (prepare_gate, prepare_release) = oneshot::channel();
    let (execute_entered, mut execute_wait) = oneshot::channel();
    let thread = ThreadHandle::start(
        "no-compaction-hook".into(),
        DynModelSession::new(GatedModel {
            prepare_entered: Some(prepare_entered),
            prepare_release: Some(prepare_release),
            prepare_failure: Some(ModelFailureKind::ContextLimit),
            execute_entered: Some(execute_entered),
            ..GatedModel::idle()
        }),
    )
    .unwrap();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn("no-compaction-hook-turn")).await })
    };
    prepare_wait.await.unwrap();
    assert_eq!(
        thread.snapshot().model_execution,
        Some(ModelExecutionPhase::PreparingRequest)
    );
    assert!(compaction_events(&thread).await.is_empty());
    prepare_gate.send(()).unwrap();
    assert!(
        matches!(task.await.unwrap(), Err(ThreadError::Model(ref error))
        if error.kind == ModelFailureKind::ContextLimit)
    );
    assert!(compaction_events(&thread).await.is_empty());
    assert_eq!(thread.snapshot().model_execution, None);
    assert!(matches!(
        execute_wait.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    ));
    thread.close().await.unwrap();
}
