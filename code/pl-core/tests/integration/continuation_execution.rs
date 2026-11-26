//! Production control, recovery, input delivery and physical cancellation contracts.
use crate::preparation;
use crate::support;
use crate::tool_support;

use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU64, Ordering},
};

use pl_core::context::{AgentMessageKind, ContextSnapshot, ContextSource, OpaquePayload};
use pl_core::model::{
    DynModelSession, ModelError, ModelFailureKind, ModelRequest, ModelSession, ModelToolCall,
    PreparedModelCall,
};
use pl_core::thread::{
    ContinuationReason, HistoryExport, ModelStepLimit, StepInput, ThreadEffectBatch, ThreadError,
    ThreadHandle, ThreadLifecycle, ThreadSnapshot, TurnOutcome, TurnState, UsageSummary,
    cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
    current::{RuntimeEpoch, ThreadCurrent, ThreadCurrentState},
    history_sink::{HistorySink, HistorySinkHandle},
    inbox::ThreadMessage,
    input::{InputDriverOptions, InputExecution, InputPurpose, InputState, ThreadInput},
};
use tokio::sync::{oneshot, watch};
use tokio_util::sync::CancellationToken;

use support::{response, text, turn};
use tool_support::tool;

async fn resume_named(
    thread: &ThreadHandle,
    operation_id: &str,
) -> Result<pl_core::thread::ContinuationOperation, ThreadError> {
    let expected_continuation_token = thread
        .snapshot()
        .continuation
        .as_ref()
        .map(|point| point.id.clone())
        .unwrap_or_else(|| "missing".into());
    thread
        .resume_execution(
            pl_core::thread::ResumeRequest {
                operation_id: operation_id.into(),
                expected_continuation_token,
                request_digest: None,
            },
            options(),
        )
        .await
}

fn options() -> InputDriverOptions {
    InputDriverOptions {
        max_model_steps: ModelStepLimit::Limited(3.try_into().expect("nonzero limit")),
    }
}

fn message_input(id: &str, body: &str) -> ThreadInput {
    ThreadInput {
        id: id.into(),
        purpose: InputPurpose::Message,
        payload: OpaquePayload::text(body),
        context: vec![text(body)],
    }
}

/// Waits for a condition on the live owner to hold; the timeout only bounds a hung test.
async fn wait_until(condition: impl Fn() -> bool) {
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while !condition() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("the owner must reach the expected state");
}

fn input_state(thread: &ThreadHandle, id: &str) -> Option<InputState> {
    thread
        .snapshot()
        .inputs
        .iter()
        .find(|record| record.input.id == id)
        .map(|record| record.state.clone())
        .or_else(|| {
            thread
                .snapshot()
                .terminal_inputs
                .iter()
                .find(|identity| identity.id == id)
                .map(|identity| identity.state.clone())
        })
}

fn paused(thread: &ThreadHandle) -> bool {
    matches!(thread.snapshot().input_execution, InputExecution::Paused)
}

/// A model whose provider call records its request and can be held until the test releases it.
///
/// Cancellation ends the held call without inventing a result, which is what lets a stop interrupt a
/// Turn that is genuinely in flight instead of one that already finished.
struct HeldModel {
    requests: Arc<Mutex<Vec<ContextSnapshot>>>,
    entered: Option<oneshot::Sender<()>>,
    release: Option<oneshot::Receiver<()>>,
}

impl ModelSession for HeldModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests
            .lock()
            .expect("request log")
            .push(request.context.clone());
        let entered = self.entered.take();
        let release = self.release.take();
        // The hold is inside the prepared call, not the preparation: the request is really admitted
        // — its input consumed and its facts committed — before the test can stop it.
        Ok(PreparedModelCall::new(async move {
            if let Some(entered) = entered {
                let _ = entered.send(());
            }
            if let Some(release) = release {
                tokio::select! {
                    _ = release => {}
                    () = request.cancellation.cancelled() => {
                        return Err(ModelError {
                            context_recovery: None,
                            details: None,
                            kind: ModelFailureKind::Cancelled,
                            usage: Default::default(),
                            source: None,
                        });
                    }
                }
            }
            Ok(response(&request, Vec::new()))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

/// A model that asks for one tool on its first call and never again.
///
/// It is what makes "the interrupted call is not re-executed" observable: the restored Thread starts
/// exactly one new request, and that request declares no tool at all.
struct OneToolCall {
    requests: Arc<Mutex<Vec<ContextSnapshot>>>,
    tool_id: String,
    answered: bool,
}

impl ModelSession for OneToolCall {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests
            .lock()
            .expect("request log")
            .push(request.context.clone());
        let calls = if self.answered {
            Vec::new()
        } else {
            self.answered = true;
            vec![ModelToolCall {
                presentation_contract: None,
                rejection: None,
                call_id: format!("{}-{}", request.turn_id, self.tool_id),
                tool_id: self.tool_id.clone(),
                arguments: OpaquePayload::text("arguments"),
            }]
        };
        Ok(PreparedModelCall::new(async move {
            Ok(response(&request, calls))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

/// A backend whose durable watermark only moves when the test says so.
///
/// Admission is synchronous and durability is a separate receipt, exactly like a real writer, so a
/// claim can be observed before its commit is durable.
#[derive(Debug, Clone)]
struct ManualStore {
    admitted: Arc<AtomicU64>,
    durable: Arc<AtomicU64>,
    auto_durable: Arc<AtomicBool>,
    retained: Arc<AtomicU64>,
    reclaimable: Arc<AtomicU64>,
    unfinished: Arc<AtomicBool>,
    changed: watch::Sender<()>,
}

impl ManualStore {
    fn new() -> Self {
        let (changed, _) = watch::channel(());
        Self {
            admitted: Arc::new(AtomicU64::new(0)),
            durable: Arc::new(AtomicU64::new(0)),
            auto_durable: Arc::new(AtomicBool::new(false)),
            retained: Arc::new(AtomicU64::new(0)),
            reclaimable: Arc::new(AtomicU64::new(0)),
            unfinished: Arc::new(AtomicBool::new(false)),
            changed,
        }
    }

    /// Makes every accepted batch durable and wakes the owner's storage wait.
    fn commit_durable(&self) {
        let admitted = self.admitted.load(Ordering::SeqCst);
        self.durable.fetch_max(admitted, Ordering::SeqCst);
        let _ = self.changed.send(());
    }
}

impl HistorySink for ManualStore {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &ThreadEffectBatch) {
        let _ = (summary, effect);
    }

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

    fn admit(&self, _thread_id: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        self.admitted
            .fetch_max(write.effect.sequence, Ordering::SeqCst);
        if self.auto_durable.load(Ordering::SeqCst) {
            self.durable
                .fetch_max(write.effect.sequence, Ordering::SeqCst);
            let _ = self.changed.send(());
        }
        Ok(())
    }

    fn pressure(&self, _thread_id: &str) -> StoragePressure {
        StoragePressure {
            thread_bytes: self.retained.load(Ordering::SeqCst),
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: (!self.unfinished.load(Ordering::SeqCst))
                .then(|| self.reclaimable.load(Ordering::SeqCst)),
        }
    }

    fn subscribe_pressure(&self, _thread_id: &str) -> Option<watch::Receiver<()>> {
        Some(self.changed.subscribe())
    }
}

#[tokio::test]
async fn idle_close_requires_durable_facts_and_only_reclaims_proven_residents() {
    use pl_core::thread::extensions::ExtensionMutation;

    let store = ManualStore::new();
    let (model, _) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("idle-retention".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_history(HistorySinkHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: "durable-fact".into(),
            expected_revision: None,
            payload: OpaquePayload::text("preserve this fact"),
        }])
        .await
        .unwrap();
    let committed = thread.snapshot().commit_sequence;
    store.retained.store(128, Ordering::SeqCst);
    store.reclaimable.store(128, Ordering::SeqCst);
    assert!(
        !thread.close_if_idle().await.unwrap(),
        "undurable facts must block eviction"
    );
    store.commit_durable();
    assert!(store.durable.load(Ordering::SeqCst) >= committed);
    store.retained.store(0, Ordering::SeqCst);
    store.unfinished.store(true, Ordering::SeqCst);
    assert!(
        !thread.close_if_idle().await.unwrap(),
        "a zero-byte in-flight obligation must block eviction"
    );
    store.unfinished.store(false, Ordering::SeqCst);
    store.retained.store(128, Ordering::SeqCst);
    store.reclaimable.store(0, Ordering::SeqCst);
    assert!(
        !thread.close_if_idle().await.unwrap(),
        "unsettled retained bytes must block eviction"
    );
    store.reclaimable.store(129, Ordering::SeqCst);
    assert!(
        !thread.close_if_idle().await.unwrap(),
        "an invalid reclaimable count must fail closed"
    );
    store.reclaimable.store(128, Ordering::SeqCst);
    store.auto_durable.store(true, Ordering::SeqCst);
    store
        .durable
        .fetch_max(thread.snapshot().commit_sequence, Ordering::SeqCst);
    let _ = store.changed.send(());
    assert!(
        thread.close_if_idle().await.unwrap(),
        "durable reconstructible residents may be released"
    );
    assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
    assert!(store.durable.load(Ordering::SeqCst) >= thread.snapshot().commit_sequence);
}

/// Starts a Turn, stops it with the exact execution identity and returns the formed point.
///
/// The Turn is genuinely in flight when the stop arrives, so the input is already consumed and the
/// stop happens for work that really existed.

#[tokio::test]
async fn stopping_a_preparing_execution_forms_a_point_and_a_stale_identity_stops_nothing() {
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("preparing".into(), DynModelSession::new(model)).unwrap();
    let hold = preparation::HoldPreparation::install(&thread).await;
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    hold.entered().await;
    let preparing = thread.snapshot().execution.clone().unwrap();

    assert!(
        thread
            .interrupt_execution(preparing.id.clone())
            .await
            .unwrap()
    );
    let point = thread
        .snapshot()
        .continuation
        .clone()
        .expect("the stop leaves a point");
    assert_eq!(point.reason, Some(ContinuationReason::UserStop));
    assert_eq!(point.source_turn_id, preparing.turn_id);
    wait_until(|| thread.snapshot().execution.is_none() && paused(&thread)).await;
    assert!(requests.lock().unwrap().is_empty());
    // The stop never consumed the input it interrupted.
    assert_eq!(input_state(&thread, "asked"), Some(InputState::Pending));

    // The outdated identity cannot stop a later execution, and it is refused instead of silently
    // stopping whatever runs now.
    assert!(matches!(
        thread.interrupt_execution(preparing.id.clone()).await,
        Err(ThreadError::InvalidIdentity)
    ));

    // Only an explicit continuation starts the input that was never consumed.
    thread.resume_inputs(options()).await.unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "asked"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    assert!(matches!(
        thread.interrupt_execution(preparing.id).await,
        Err(ThreadError::InvalidIdentity)
    ));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn recovery_offers_a_continuation_without_running_or_repeating_anything() {
    let log = Arc::new(Mutex::new(Vec::new()));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "restart".into(),
        DynModelSession::new(OneToolCall {
            requests: requests.clone(),
            tool_id: "write".into(),
            answered: false,
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![tool("write", &log)])
        .await
        .unwrap();
    thread
        .submit_input(message_input("owed", "Please handle this request"))
        .await
        .unwrap();
    let output = thread
        .step(StepInput {
            turn_id: "interrupted-turn".into(),
            attempt_id: "interrupted-attempt".into(),
            content: vec![text("Use the write tool")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    assert_eq!(output.tool_calls.len(), 1);
    assert!(log.lock().unwrap().is_empty());
    let current = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    let serialized = serde_json::to_vec(&current).unwrap();
    thread.close().await.unwrap();

    let restored_requests = Arc::new(Mutex::new(Vec::new()));
    let restored = ThreadHandle::restore_current(
        serde_json::from_slice(&serialized).unwrap(),
        Some(DynModelSession::new(OneToolCall {
            requests: restored_requests.clone(),
            tool_id: "write".into(),
            answered: true,
        })),
    )
    .unwrap();
    let snapshot = restored.snapshot();
    let point = snapshot
        .continuation
        .clone()
        .expect("recovered work forms a point");
    assert_eq!(point.reason, Some(ContinuationReason::ProcessInterrupted));
    // Loading is not executing: nothing is enabled and nothing runs.
    assert!(paused(&restored));
    assert!(restored_requests.lock().unwrap().is_empty());
    assert!(log.lock().unwrap().is_empty());
    // The interrupted call stays unpaired before explicit continuation (nothing replayed on restore).
    assert!(restored.snapshot().context.records.iter().any(|record| {
        record
            .tool_calls
            .iter()
            .any(|call| call.call_id == "interrupted-turn-write")
    }));

    let receipt = resume_named(&restored, "after-restart").await.unwrap();
    assert_eq!(receipt.request.expected_continuation_token, point.id);
    wait_until(|| {
        matches!(
            input_state(&restored, "owed"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| restored.snapshot().continuation.is_none()).await;
    assert_eq!(restored_requests.lock().unwrap().len(), 1);
    assert!(
        log.lock().unwrap().is_empty(),
        "the interrupted tool call must never be re-executed"
    );
    // The original message is delivered exactly once, by the continuation Turn.
    let delivered = restored_requests.lock().unwrap()[0].clone();
    assert_eq!(
        delivered
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Please handle this request")])
            .count(),
        1
    );
    restored.close().await.unwrap();
}

#[tokio::test]
async fn a_direct_turn_owns_a_stoppable_execution_identity() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "direct".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("direct-turn")).await }
    });
    observed
        .await
        .expect("the direct Turn reaches the provider");
    // A Turn that did not come from the queue driver owns an identity just the same, so a product
    // never has to fall back to "stop whatever runs now".
    let execution = thread
        .snapshot()
        .execution
        .clone()
        .expect("a direct Turn owns an execution identity");
    assert_eq!(execution.turn_id.as_deref(), Some("direct-turn"));
    assert!(thread.interrupt_execution(execution.id).await.unwrap());
    assert!(matches!(runner.await.unwrap(), Err(ThreadError::Cancelled)));
    let point = thread
        .snapshot()
        .continuation
        .clone()
        .expect("the stop leaves a point");
    assert_eq!(point.reason, Some(ContinuationReason::UserStop));
    assert_eq!(point.source_turn_id.as_deref(), Some("direct-turn"));
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_step_limited_turn_stays_continuable_without_replaying_inputs_or_tools() {
    let log = Arc::new(Mutex::new(Vec::new()));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "step-limit".into(),
        DynModelSession::new(OneToolCall {
            requests: requests.clone(),
            tool_id: "write".into(),
            answered: false,
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![tool("write", &log)])
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            InputDriverOptions {
                max_model_steps: ModelStepLimit::Limited(1.try_into().expect("nonzero limit")),
            },
        )
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .continuation
            .as_ref()
            .is_some_and(|point| point.reason == Some(ContinuationReason::StepLimit))
    })
    .await;
    let point = thread.snapshot().continuation.clone().unwrap();
    assert!(paused(&thread));
    assert_eq!(log.lock().unwrap().len(), 1);
    assert!(thread.effects().await.unwrap().iter().any(|effect| {
        effect.turn.as_ref().is_some_and(|turn| {
            turn.turn_id == point.source_turn_id.clone().unwrap_or_default()
                && turn.state == TurnState::Finished(TurnOutcome::StepLimit)
        })
    }));

    // An explicit body-less continuation opens exactly one more Turn.
    resume_named(&thread, "after-step-limit").await.unwrap();
    wait_until(|| thread.snapshot().execution.is_none()).await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert_eq!(
        log.lock().unwrap().len(),
        1,
        "the earlier tool call is never re-executed"
    );
    let second = requests.lock().unwrap()[1].clone();
    assert_eq!(
        second
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Please handle this request")])
            .count(),
        1,
        "the continued Turn must not repeat the consumed request"
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn only_an_unavailable_model_failure_stays_continuable() {
    // Categories where continuing the same task cannot help: no point may be formed. `ContextLimit` is
    // deliberately not here — `ContextLimit` and `UnsupportedContent` are covered by the binding-swap
    // cases below, where an explicit continuation can still finish the owed work.
    for kind in [
        ModelFailureKind::InvalidResponse,
        ModelFailureKind::ImplementationPanicked,
        ModelFailureKind::IncompatibleContext,
    ] {
        let thread = ThreadHandle::start(
            format!("failed-{kind:?}"),
            DynModelSession::new(FailingModel(kind)),
        )
        .unwrap();
        thread
            .submit_input_and_run(
                message_input("asked", "Please handle this request"),
                options(),
            )
            .await
            .unwrap();
        wait_until(|| {
            matches!(
                thread.snapshot().input_execution,
                InputExecution::Failed { .. }
            )
        })
        .await;
        assert!(
            thread.snapshot().continuation.is_none(),
            "{kind:?} must not be presented as continuable"
        );
        assert!(matches!(
            resume_named(&thread, "after-failure").await,
            Err(ThreadError::StaleContinuation)
        ));
        assert!(thread.effects().await.unwrap().iter().any(|effect| {
            effect
                .turn
                .as_ref()
                .is_some_and(|turn| matches!(turn.state, TurnState::Failed { .. }))
        }));
        thread.close().await.unwrap();
    }

    // An unavailable provider is the one category an explicit retry can still change.
    let thread = ThreadHandle::start(
        "failed-unavailable".into(),
        DynModelSession::new(FailingModel(ModelFailureKind::Unavailable)),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .continuation
            .as_ref()
            .is_some_and(|point| point.reason == Some(ContinuationReason::ExecutionFailed))
    })
    .await;
    thread.close().await.unwrap();
}

#[tokio::test]
async fn closing_with_live_work_keeps_it_as_a_host_shutdown_point() {
    let store = RecordingStore::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "shutdown".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .attach_history(HistorySinkHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed
        .await
        .expect("the request is admitted and in flight");
    assert!(matches!(
        input_state(&thread, "asked"),
        Some(InputState::Consumed { .. })
    ));

    // Dropping every handle is what a shutdown does: it cancels the live generation and closes.
    drop(thread);
    wait_until(|| {
        store
            .latest_state()
            .is_some_and(|state| state.lifecycle == ThreadLifecycle::Closed)
    })
    .await;
    let shutdown_state = store
        .latest_state()
        .expect("the close exported final snapshot");
    let point = shutdown_state
        .continuation
        .clone()
        .expect("a shutdown that cut live work leaves a point");
    assert_eq!(point.reason, Some(ContinuationReason::HostShutdown));
    assert!(
        shutdown_state
            .turns
            .iter()
            .all(|turn| turn.state != TurnState::Running),
        "the cancelled Turn is settled, not left running"
    );
    let requests_after_shutdown = requests.lock().unwrap().len();

    // Restoring runs nothing; only an explicit continuation resumes the owed work.
    let epoch = RuntimeEpoch::new();
    let mut restored_current = ThreadCurrent::new("shutdown".into(), epoch);
    restored_current.state = ThreadCurrentState::from_snapshot(&shutdown_state, epoch).unwrap();
    let resumed_requests = Arc::new(Mutex::new(Vec::new()));
    let resumed = ThreadHandle::restore_current(
        restored_current,
        Some(DynModelSession::new(HeldModel {
            requests: resumed_requests.clone(),
            entered: None,
            release: None,
        })),
    )
    .unwrap();
    assert!(paused(&resumed));
    assert!(resumed.snapshot().continuation.is_some());
    assert_eq!(requests.lock().unwrap().len(), requests_after_shutdown);
    assert!(resumed_requests.lock().unwrap().is_empty());
    resume_named(&resumed, "after-shutdown").await.unwrap();
    wait_until(|| resumed_requests.lock().unwrap().len() == 1).await;
    wait_until(|| resumed.snapshot().continuation.is_none()).await;
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn a_stopped_preparing_execution_never_hands_its_identity_to_a_later_turn() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "identity".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    let hold = preparation::HoldPreparation::install(&thread).await;
    let first = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("repeated")).await }
    });
    hold.entered().await;
    let stopped = thread.snapshot().execution.clone().unwrap();
    assert!(
        thread
            .interrupt_execution(stopped.id.clone())
            .await
            .unwrap()
    );
    assert!(matches!(first.await.unwrap(), Err(ThreadError::Cancelled)));
    wait_until(|| thread.snapshot().execution.is_none()).await;
    assert!(requests.lock().unwrap().is_empty());

    let second = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("second")).await }
    });
    observed.await.unwrap();
    let running = thread.snapshot().execution.clone().unwrap();
    assert_ne!(
        running.id, stopped.id,
        "an execution identity is never reused"
    );
    // The old identity names nothing any more, so it cannot stop the newer execution.
    assert!(matches!(
        thread.interrupt_execution(stopped.id.clone()).await,
        Err(ThreadError::InvalidIdentity)
    ));
    drop(release);
    let completion = second.await.unwrap().unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn ordinary_content_may_not_claim_the_control_format() {
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("reserved-format".into(), DynModelSession::new(model)).unwrap();
    let control_payload = || {
        OpaquePayload::new(
            pl_core::thread::input::CONTINUATION_PAYLOAD_FORMAT,
            pl_core::thread::input::CONTINUATION_PAYLOAD_VERSION,
            String::from(r#"{"pointId":"point-1","sourceTurnId":null}"#),
        )
        .unwrap()
    };
    let message = || ThreadInput {
        id: "reserved-input".into(),
        purpose: InputPurpose::Message,
        payload: control_payload(),
        context: Vec::new(),
    };
    assert!(matches!(
        thread.submit_input(message()).await,
        Err(ThreadError::InvalidControlInput)
    ));
    assert!(thread.snapshot().inputs.is_empty());
    // 父消息是另一种历史来源，同样不得借保留格式进入历史。
    let parent_message = ThreadMessage {
        id: "reserved-parent-message".into(),
        source_id: "parent".into(),
        kind: AgentMessageKind::default(),
        payload: control_payload(),
        context: Vec::new(),
    };
    assert!(matches!(
        thread.send_message(parent_message).await,
        Err(ThreadError::InvalidControlInput)
    ));
    assert!(thread.snapshot().inbox.is_empty());
    assert!(requests.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}

#[tokio::test]
async fn an_idle_close_does_not_make_the_thread_continuable() {
    let store = RecordingStore::new();
    let (model, _) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("idle-close".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_history(HistorySinkHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "asked"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    thread.close().await.unwrap();
    let closed_state = store
        .latest_state()
        .expect("the close exported final snapshot");
    assert_eq!(closed_state.lifecycle, ThreadLifecycle::Closed);
    assert!(
        closed_state.continuation.is_none(),
        "a normally finished Thread does not become continuable just because it closed"
    );
}

struct FailingModel(ModelFailureKind);

impl ModelSession for FailingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let kind = self.0;
        Ok(PreparedModelCall::new(async move {
            let _ = request;
            Err(ModelError {
                context_recovery: None,
                details: None,
                kind,
                usage: Default::default(),
                source: None,
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

struct OneSession(Arc<Mutex<Option<support::ScriptedModel>>>);

impl OneSession {
    fn new(model: support::ScriptedModel) -> Self {
        Self(Arc::new(Mutex::new(Some(model))))
    }
}

impl pl_core::model::Model for OneSession {
    async fn open_session(&self) -> Result<DynModelSession, ModelError> {
        let session = self.0.lock().expect("factory session").take();
        session.map(DynModelSession::new).ok_or_else(|| ModelError {
            context_recovery: None,
            details: None,
            kind: ModelFailureKind::Unavailable,
            usage: Default::default(),
            source: None,
        })
    }
}

/// A model that asks for one tool, then reports the given recoverable failure.
///
/// The failure comes from `prepare`, which is what makes the Thread run its one automatic compaction
/// before giving up, exactly like a real provider refusing an oversized request.
struct ToolThenFailure {
    requests: Arc<Mutex<Vec<ContextSnapshot>>>,
    tool_id: String,
    kind: ModelFailureKind,
    answered: bool,
}

impl ModelSession for ToolThenFailure {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests
            .lock()
            .expect("request log")
            .push(request.context.clone());
        if self.answered {
            return Err(ModelError {
                context_recovery: None,
                details: None,
                kind: self.kind,
                usage: Default::default(),
                source: None,
            });
        }
        self.answered = true;
        let call = ModelToolCall {
            presentation_contract: None,
            rejection: None,
            call_id: format!("{}-{}", request.turn_id, self.tool_id),
            tool_id: self.tool_id.clone(),
            arguments: OpaquePayload::text("arguments"),
        };
        Ok(PreparedModelCall::new(async move {
            Ok(response(&request, vec![call]))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

async fn a_tool_then_failure_stays_continuable_after_a_binding_swap(
    kind: ModelFailureKind,
    thread_id: &str,
) {
    let log = Arc::new(Mutex::new(Vec::new()));
    let failed_requests = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        thread_id.to_owned(),
        DynModelSession::new(ToolThenFailure {
            requests: failed_requests.clone(),
            tool_id: "write".into(),
            kind,
            answered: false,
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![tool("write", &log)])
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .continuation
            .as_ref()
            .is_some_and(|point| point.reason == Some(ContinuationReason::ExecutionFailed))
    })
    .await;
    // The request was admitted before the provider refused it, so its input is already consumed and only
    // an explicit continuation can run it again.
    assert!(matches!(
        input_state(&thread, "asked"),
        Some(InputState::Consumed { .. })
    ));
    assert_eq!(log.lock().unwrap().len(), 1);

    // Swapping the binding keeps the point: the owed work is unchanged, only its model is.
    let (model, requests) = support::ScriptedModel::new(&[]);
    thread
        .replace_model(pl_core::model::ModelFactory::new(OneSession::new(model)))
        .await
        .unwrap();
    assert!(
        thread.snapshot().continuation.is_some(),
        "replacing the model must not delete the continuation"
    );
    // The failed execution keeps its own state; it is not a manual pause.
    assert!(matches!(
        thread.snapshot().input_execution,
        InputExecution::Failed { .. }
    ));

    resume_named(&thread, "after-failure").await.unwrap();
    wait_until(|| requests.lock().unwrap().len() == 1).await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 1);
    assert_eq!(
        log.lock().unwrap().len(),
        1,
        "the earlier tool call is never re-executed"
    );
    assert_eq!(
        requests.lock().unwrap()[0]
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Please handle this request")])
            .count(),
        1,
        "the consumed request is delivered once, as history"
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_context_limit_failure_stays_continuable_after_a_binding_swap() {
    a_tool_then_failure_stays_continuable_after_a_binding_swap(
        ModelFailureKind::ContextLimit,
        "context-limit",
    )
    .await;
}

#[tokio::test]
async fn an_unsupported_content_failure_stays_continuable_after_a_binding_swap() {
    a_tool_then_failure_stays_continuable_after_a_binding_swap(
        ModelFailureKind::UnsupportedContent,
        "unsupported-content",
    )
    .await;
}

struct IgnoringCancellation {
    requests: Arc<Mutex<Vec<ContextSnapshot>>>,
    entered: Option<oneshot::Sender<()>>,
    release: Option<oneshot::Receiver<()>>,
}

impl ModelSession for IgnoringCancellation {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests
            .lock()
            .expect("request log")
            .push(request.context.clone());
        let entered = self.entered.take();
        let release = self.release.take();
        Ok(PreparedModelCall::new(async move {
            if let Some(entered) = entered {
                let _ = entered.send(());
            }
            if let Some(release) = release {
                let _ = release.await;
            }
            Ok(response(&request, Vec::new()))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn an_external_stop_before_the_cancellation_settles_keeps_the_queue_stopped() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "takeover-then-stop".into(),
        DynModelSession::new(IgnoringCancellation {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("first", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed
        .await
        .expect("the first request is admitted and in flight");
    assert!(matches!(
        input_state(&thread, "first"),
        Some(InputState::Consumed { .. })
    ));

    // A content takeover while the Turn is Running: it cancels that generation and deliberately keeps the
    // queue enabled so the continuation itself can run.
    thread
        .submit_input_and_continue(message_input("real", "Also check the logs"), options())
        .await
        .unwrap();
    // The owner is still parked inside the call that ignores cancellation, so this external stop is
    // provably later than the takeover's own cancellation and must win.
    thread.interrupt();
    drop(release);

    thread.flush().await.unwrap();
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "an external stop must not be turned into a fresh request by the takeover"
    );
    assert!(
        !matches!(thread.snapshot().input_execution, InputExecution::Ready),
        "the queue stays stopped until an explicit continuation"
    );
    assert_eq!(
        input_state(&thread, "real"),
        Some(InputState::Pending),
        "the replacement content is kept, not consumed"
    );

    // Only an explicit continuation resumes it, and it carries that content.
    thread.resume_inputs(options()).await.unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "real"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert_eq!(
        requests.lock().unwrap()[1]
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Also check the logs")])
            .count(),
        1
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_content_takeover_of_a_running_turn_continues_without_an_extra_stop() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "takeover-continues".into(),
        DynModelSession::new(IgnoringCancellation {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("first", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed
        .await
        .expect("the first request is admitted and in flight");
    // No stop is issued: the takeover's own cancellation is what has to keep the queue running.
    thread
        .submit_input_and_continue(message_input("real", "Also check the logs"), options())
        .await
        .unwrap();
    drop(release);
    wait_until(|| {
        matches!(
            input_state(&thread, "real"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert_eq!(
        requests.lock().unwrap()[1]
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Also check the logs")])
            .count(),
        1
    );
    assert!(!matches!(
        thread.snapshot().input_execution,
        InputExecution::Paused
    ));
    thread.close().await.unwrap();
}

#[derive(Debug, Clone)]
struct RecordingStore {
    admitted: Arc<AtomicU64>,
    durable: Arc<AtomicU64>,
    changed: watch::Sender<()>,
    last: Arc<Mutex<Option<Arc<HistoryExport>>>>,
}

impl RecordingStore {
    fn new() -> Self {
        let (changed, _) = watch::channel(());
        Self {
            admitted: Arc::new(AtomicU64::new(0)),
            durable: Arc::new(AtomicU64::new(0)),
            changed,
            last: Arc::new(Mutex::new(None)),
        }
    }

    /// The newest exported snapshot the backend received, cloned out of the recorded batch.
    fn latest_state(&self) -> Option<ThreadSnapshot> {
        self.last
            .lock()
            .expect("recorded write")
            .as_ref()
            .map(|write| write.state.clone())
    }
}

impl HistorySink for RecordingStore {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &ThreadEffectBatch) {
        let _ = (summary, effect);
    }

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

    fn admit(&self, _thread_id: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        self.admitted
            .fetch_max(write.effect.sequence, Ordering::SeqCst);
        *self.last.lock().expect("recorded write") = Some(write);
        Ok(())
    }

    fn pressure(&self, _thread_id: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: None,
        }
    }

    fn subscribe_pressure(&self, _thread_id: &str) -> Option<watch::Receiver<()>> {
        Some(self.changed.subscribe())
    }
}
