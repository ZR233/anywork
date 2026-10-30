//! Public-API behaviour of continuation points, execution identity and body-less continuation.
//!
//! These cases prove the contract a product's "continue" button depends on: a stop names exactly one
//! execution and leaves one durable point, a body-less continuation runs exactly one Turn without
//! inventing user content, a repeated operation is only ever a receipt, two operations cannot both
//! claim the same point, recovery never executes anything by itself and never repeats a tool, and a
//! claimed continuation only authorizes a model request once its own commit is durable.

#[path = "support/legacy_usage.rs"]
mod legacy_usage;
mod support;
#[path = "support/tool.rs"]
mod tool_support;

use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};

use pl_core::context::{AgentMessageKind, ContextSnapshot, ContextSource, OpaquePayload};
use pl_core::model::{
    DynModelSession, ModelError, ModelFailureKind, ModelRequest, ModelSession, ModelToolCall,
    PreparedModelCall,
};
use pl_core::thread::{
    ContinuationReason, ExecutionPhase, ModelStepLimit, StepInput, ThreadCheckpoint, ThreadError,
    ThreadHandle, ThreadLifecycle, ToolOutcome, TurnOutcome, TurnState,
    admission::TurnAdmissionGate,
    cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
    inbox::ThreadMessage,
    input::{InputDriverOptions, InputExecution, InputPurpose, InputState, ThreadInput},
};
use tokio::sync::{oneshot, watch};
use tokio_util::sync::CancellationToken;

use support::{response, text, turn};
use tool_support::tool;

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

fn user_record_count(context: &ContextSnapshot) -> usize {
    context
        .records
        .iter()
        .filter(|record| record.source == ContextSource::User)
        .count()
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
    changed: watch::Sender<()>,
}

impl ManualStore {
    fn new() -> Self {
        let (changed, _) = watch::channel(());
        Self {
            admitted: Arc::new(AtomicU64::new(0)),
            durable: Arc::new(AtomicU64::new(0)),
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

impl ColdStore for ManualStore {
    fn admit(&self, _thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.admitted
            .fetch_max(write.effect.sequence, Ordering::SeqCst);
        Ok(())
    }

    fn pressure(&self, _thread_id: &str) -> StoragePressure {
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            ..Default::default()
        }
    }

    fn subscribe_pressure(&self, _thread_id: &str) -> Option<watch::Receiver<()>> {
        Some(self.changed.subscribe())
    }

    async fn flush(&self, _thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        self.durable.fetch_max(sequence, Ordering::SeqCst);
        let _ = self.changed.send(());
        Ok(())
    }
}

/// Starts a Turn, stops it with the exact execution identity and returns the formed point.
///
/// The Turn is genuinely in flight when the stop arrives, so the input is already consumed and the
/// stop happens for work that really existed.
async fn stop_a_running_turn(thread: &ThreadHandle) -> (pl_core::thread::ContinuationPoint, u64) {
    let running = thread
        .snapshot()
        .execution
        .clone()
        .expect("the selected work owns an execution identity");
    assert!(running.turn_id.is_some());
    assert!(
        thread
            .interrupt_execution(running.id.clone())
            .await
            .unwrap()
    );
    wait_until(|| {
        thread.snapshot().execution.is_none()
            && matches!(thread.snapshot().input_execution, InputExecution::Paused)
    })
    .await;
    let point = thread
        .snapshot()
        .continuation
        .clone()
        .expect("an accepted stop leaves one point");
    assert_eq!(point.reason, Some(ContinuationReason::UserStop));
    assert_eq!(point.claim, None);
    assert_eq!(point.source_turn_id, running.turn_id);
    (point, thread.snapshot().commit_sequence)
}

#[tokio::test]
async fn stopping_a_preparing_execution_forms_a_point_and_a_stale_identity_stops_nothing() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "preparing".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
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
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;
    let preparing = thread.snapshot().execution.clone().unwrap();
    // No Turn exists yet, so the identity is the only way to name this work at all.
    assert!(preparing.turn_id.is_none());
    assert!(thread.snapshot().turns.is_empty());

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
    assert_eq!(point.source_turn_id, None);
    wait_until(|| thread.snapshot().execution.is_none() && paused(&thread)).await;
    assert!(requests.lock().unwrap().is_empty());
    // The stop never consumed the input it interrupted.
    assert_eq!(input_state(&thread, "asked"), Some(InputState::Pending));
    assert!(thread.snapshot().turns.is_empty());

    // The outdated identity cannot stop a later execution, and it is refused instead of silently
    // stopping whatever runs now.
    assert!(matches!(
        thread.interrupt_execution(preparing.id.clone()).await,
        Err(ThreadError::InvalidIdentity)
    ));

    // Only an explicit continuation starts the input that was never consumed.
    drop(hold);
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
async fn a_body_less_continuation_runs_one_turn_without_new_user_content() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "continue-once".into(),
        DynModelSession::new(HeldModel {
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
    observed.await.expect("the first Turn reaches the provider");
    let (point, _) = stop_a_running_turn(&thread).await;
    // The interrupted Turn already admitted its input; the continuation must not repeat it.
    assert!(matches!(
        input_state(&thread, "first"),
        Some(InputState::Consumed { .. })
    ));
    assert_eq!(requests.lock().unwrap().len(), 1);
    let user_records_before = user_record_count(&thread.snapshot().context);

    let receipt = thread
        .continue_thread("continuing".into(), options())
        .await
        .unwrap();
    assert_eq!(receipt.input.purpose, InputPurpose::Continuation);
    assert!(
        receipt.input.context.is_empty(),
        "a control input never carries user content"
    );
    assert_eq!(
        receipt
            .continuation
            .as_ref()
            .map(|continuation| continuation.point_id.clone()),
        Some(point.id.clone())
    );
    assert_eq!(receipt.state, InputState::Pending);

    wait_until(|| requests.lock().unwrap().len() == 2).await;
    wait_until(|| {
        matches!(
            input_state(&thread, "continuing"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    let snapshot = thread.snapshot();
    // The point is cleared by the commit that admitted the request it authorized.
    assert!(snapshot.continuation.is_none());
    assert_eq!(
        user_record_count(&snapshot.context),
        user_records_before,
        "a body-less continuation must not add user content"
    );
    // The continuation opened exactly one further Turn, and that Turn belonged to the control input.
    let turns = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .filter_map(|effect| effect.turn.clone())
        .collect::<Vec<_>>();
    let distinct = turns
        .iter()
        .map(|turn| turn.turn_id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(distinct.len(), 2);
    assert_eq!(
        turns.last().and_then(|turn| turn.input_id.clone()),
        Some("continuing".to_string())
    );
    // The continuation Turn's own request carries no user content of its own; the earlier request is
    // delivered once, as history, instead of being repeated as new input.
    let continuing_turn = turns.last().expect("the continuation Turn").turn_id.clone();
    let second_request = requests.lock().unwrap()[1].clone();
    assert_eq!(
        second_request
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.turn_id.as_deref() == Some(continuing_turn.as_str()))
            .count(),
        0,
        "a body-less continuation has no user record of its own"
    );
    assert_eq!(
        second_request
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Please handle this request")])
            .count(),
        1,
        "the consumed request is delivered once, not replayed"
    );
    // A round trip through the owner proves the settled state opens no further Turn.
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);

    // The same operation identity only ever answers its original receipt.
    let repeated = thread
        .continue_thread("continuing".into(), options())
        .await
        .unwrap();
    // The repeat names the same operation: same queue position, same association, and the identity
    // it was answered from already says the control was consumed.
    assert_eq!(repeated.ordinal, receipt.ordinal);
    assert_eq!(repeated.continuation, receipt.continuation);
    assert!(matches!(repeated.state, InputState::Consumed { .. }));
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn only_one_operation_carries_the_claim_at_a_time() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let store = ManualStore::new();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "one-claim".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let (point, _) = stop_a_running_turn(&thread).await;

    // The first operation claims the point and its Turn is held before admission.
    let hold = gate.close();
    let first = thread
        .continue_thread("claim-a".into(), options())
        .await
        .unwrap();
    assert_eq!(first.state, InputState::Pending);
    wait_until(|| {
        thread
            .snapshot()
            .continuation
            .as_ref()
            .is_some_and(|point| {
                point.claim
                    == Some(pl_core::thread::ContinuationClaim::Input {
                        input_id: "claim-a".into(),
                    })
            })
    })
    .await;

    // A second explicit continuation replaces it: the claim moves, the older control is voided in the
    // same commit, and the point keeps its identity.
    let second = thread
        .continue_thread("claim-b".into(), options())
        .await
        .unwrap();
    assert_eq!(second.state, InputState::Pending);
    let current = thread.snapshot().continuation.clone().unwrap();
    assert_eq!(current.id, point.id, "the point keeps its identity");
    assert_eq!(
        current.claim,
        Some(pl_core::thread::ContinuationClaim::Input {
            input_id: "claim-b".into(),
        })
    );
    assert_eq!(input_state(&thread, "claim-a"), Some(InputState::Discarded));
    assert_eq!(input_state(&thread, "claim-b"), Some(InputState::Pending));
    assert_eq!(
        thread
            .snapshot()
            .inputs
            .iter()
            .filter(|record| record.input.purpose == InputPurpose::Continuation)
            .count(),
        1,
        "only the newest control is still queued"
    );

    // The replaced operation still answers its own receipt, without authorizing anything again.
    let receipt = thread
        .continue_thread("claim-a".into(), options())
        .await
        .unwrap();
    assert_eq!(receipt.input.id, "claim-a");
    assert_eq!(input_state(&thread, "claim-a"), Some(InputState::Discarded));
    assert_eq!(
        thread.snapshot().continuation.unwrap().claim,
        Some(pl_core::thread::ContinuationClaim::Input {
            input_id: "claim-b".into(),
        })
    );

    // The replaced authorization owes no request of its own: only the newer control's commit has to
    // be durable before this execution may reach the provider.
    drop(hold);
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingStorage)
    })
    .await;
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "the replaced authorization must not start a request of its own"
    );
    store.commit_durable();
    wait_until(|| {
        matches!(
            input_state(&thread, "claim-b"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    thread.flush().await.unwrap();
    // The replaced batch produced no extra Turn: exactly the stopped Turn plus this continuation, and
    // nothing is left queued that could open a third one.
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert!(
        thread.snapshot().inputs.is_empty(),
        "no continuation control is left queued"
    );
    assert!(thread.snapshot().continuation.is_none());
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
    let checkpoint = thread
        .checkpoint(thread.snapshot().commit_sequence)
        .unwrap();
    let serialized = serde_json::to_vec(&checkpoint).unwrap();
    thread.close().await.unwrap();

    let restored_requests = Arc::new(Mutex::new(Vec::new()));
    let restored = ThreadHandle::resume(
        "restart".into(),
        DynModelSession::new(OneToolCall {
            requests: restored_requests.clone(),
            tool_id: "write".into(),
            answered: true,
        }),
        Some(serde_json::from_slice(&serialized).unwrap()),
    )
    .unwrap();
    let snapshot = restored.snapshot();
    let point = snapshot
        .continuation
        .clone()
        .expect("recovered work forms a point");
    assert_eq!(point.reason, Some(ContinuationReason::ProcessInterrupted));
    assert_eq!(point.claim, None, "an old claim can never be reused");
    // Loading is not executing: nothing is enabled and nothing runs.
    assert!(paused(&restored));
    assert!(restored_requests.lock().unwrap().is_empty());
    assert!(log.lock().unwrap().is_empty());
    // The interrupted call keeps its interrupted result instead of being replayed.
    assert!(restored.effects().await.unwrap().iter().any(|effect| {
        effect.deliveries.iter().any(|delivery| {
            delivery.call_id == "interrupted-turn-write"
                && matches!(delivery.outcome, ToolOutcome::Interrupted)
        })
    }));

    let receipt = restored
        .continue_thread("after-restart".into(), options())
        .await
        .unwrap();
    assert_eq!(
        receipt
            .continuation
            .as_ref()
            .map(|continuation| continuation.point_id.clone()),
        Some(point.id)
    );
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
async fn a_new_message_replaces_the_unconsumed_control_and_keeps_real_input() {
    // A recovered owner holds an accepted control input it never consumed.
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "supersede".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;
    let _hold = gate.close();
    thread
        .continue_thread("old-control".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .inputs
            .iter()
            .any(|record| record.input.id == "old-control")
    })
    .await;
    let checkpoint = thread
        .checkpoint(thread.snapshot().commit_sequence)
        .unwrap();
    let serialized = serde_json::to_vec(&checkpoint).unwrap();
    thread.close().await.unwrap();

    let (model, _) = support::ScriptedModel::new(&[]);
    let resumed = ThreadHandle::resume(
        "supersede".into(),
        DynModelSession::new(model),
        Some(serde_json::from_slice(&serialized).unwrap()),
    )
    .unwrap();
    // Recovery keeps the real content and never re-uses the old authorization.
    assert_eq!(
        input_state(&resumed, "old-control"),
        Some(InputState::Pending)
    );
    let point = resumed
        .snapshot()
        .continuation
        .clone()
        .expect("the unconsumed work still owes a point");
    assert_eq!(point.claim, None);

    let receipt = resumed
        .submit_input_and_continue(message_input("real", "Also check the logs"), options())
        .await
        .unwrap();
    assert_eq!(receipt.input.purpose, InputPurpose::Message);
    wait_until(|| {
        matches!(
            input_state(&resumed, "real"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    // Only the body-less control is dropped; the real message keeps its own admitted fact.
    assert_eq!(
        input_state(&resumed, "old-control"),
        Some(InputState::Discarded)
    );
    assert!(resumed.snapshot().continuation.is_none());
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn one_turn_carries_both_the_control_and_the_wake_message() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "shared-batch".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    let sequence = thread
        .send_message_and_resume(
            ThreadMessage {
                kind: AgentMessageKind::Report,
                id: "child-report".into(),
                source_id: "child".into(),
                payload: OpaquePayload::text("finished"),
                context: vec![text("child finished")],
            },
            options(),
        )
        .await
        .unwrap();
    // A wake alone does not restart a paused owner.
    assert!(paused(&thread));
    assert_eq!(thread.snapshot().consumed_messages, 0);
    assert_eq!(requests.lock().unwrap().len(), 1);

    let hold = gate.close();
    thread
        .continue_thread("batch-control".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .continuation
            .as_ref()
            .is_some_and(|point| point.claim.is_some())
    })
    .await;
    drop(hold);
    wait_until(|| thread.snapshot().consumed_messages >= sequence).await;
    wait_until(|| {
        matches!(
            input_state(&thread, "batch-control"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    let snapshot = thread.snapshot();
    // One Turn carried the control input and the message, so the wake marker cannot open another.
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert!(snapshot.wake_messages_through <= snapshot.consumed_messages);
    assert!(snapshot.continuation.is_none());
    assert_eq!(
        requests.lock().unwrap()[1]
            .records
            .iter()
            .filter(|record| record.source
                == ContextSource::AgentMessage {
                    source_id: "child".into(),
                    purpose: AgentMessageKind::Report,
                })
            .count(),
        1
    );
    // Exactly two Turns exist, and a round trip through the owner starts no third one.
    let turns = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .filter_map(|effect| effect.turn.clone())
        .map(|turn| turn.turn_id)
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(turns.len(), 2);
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert_eq!(thread.snapshot().consumed_messages, sequence);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_claimed_continuation_waits_for_its_own_durable_commit() {
    let store = ManualStore::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "durable-claim".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let (point, _) = stop_a_running_turn(&thread).await;

    thread
        .continue_thread("durable".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingStorage)
    })
    .await;
    let required = thread
        .snapshot()
        .required_durable_sequence
        .expect("a claimed continuation owes its own commit");
    assert!(
        thread.snapshot().persistence.durable_sequence < required,
        "the claim must not be treated as durable before its commit is"
    );
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "no model request may start before the claim is durable"
    );

    store.commit_durable();
    wait_until(|| thread.snapshot().required_durable_sequence.is_none()).await;
    wait_until(|| requests.lock().unwrap().len() == 2).await;
    assert!(thread.snapshot().continuation.is_none());
    assert!(point.id.starts_with("continuation:"));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn stopping_the_durable_wait_consumes_no_input() {
    let store = ManualStore::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "durable-stop".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    thread
        .continue_thread("waiting".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingStorage)
    })
    .await;
    let waiting = thread.snapshot().execution.clone().unwrap();
    assert!(thread.interrupt_execution(waiting.id).await.unwrap());
    wait_until(|| thread.snapshot().execution.is_none() && paused(&thread)).await;
    // The stop settled without consuming the control input or reaching the provider: the control the
    // stop voided is discarded by the settlement of its own batch instead of lingering as phantom
    // owed work.
    assert_eq!(input_state(&thread, "waiting"), Some(InputState::Discarded));
    assert_eq!(requests.lock().unwrap().len(), 1);
    let point = thread
        .snapshot()
        .continuation
        .clone()
        .expect("the new stop forms a point");
    assert_eq!(point.reason, Some(ContinuationReason::UserStop));
    assert_eq!(point.claim, None);
    // The voided control cannot start a Turn on its own, and the fresh point stays claimable.
    store.commit_durable();
    tokio::task::yield_now().await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    assert_eq!(input_state(&thread, "waiting"), Some(InputState::Discarded));
    assert!(
        thread
            .snapshot()
            .continuation
            .as_ref()
            .is_some_and(|point| point.claim.is_none())
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_pending_interaction_refuses_the_continuation_without_claiming_it() {
    use pl_core::thread::interactions::InteractionRequest;

    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("interaction".into(), DynModelSession::new(model)).unwrap();
    thread
        .submit_input_and_continue(
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
    thread
        .request_interaction(InteractionRequest {
            id: "plan-1".into(),
            turn_id: "asked-turn".into(),
            payload: OpaquePayload::text("approve the plan"),
        })
        .await
        .unwrap();
    let before = requests.lock().unwrap().len();
    assert!(matches!(
        thread.continue_thread("blocked".into(), options()).await,
        Err(ThreadError::PendingInteraction)
    ));
    assert_eq!(
        thread
            .snapshot()
            .inputs
            .iter()
            .filter(|record| record.input.purpose == InputPurpose::Continuation)
            .count(),
        0
    );
    assert_eq!(requests.lock().unwrap().len(), before);
    thread.close().await.unwrap();
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
async fn a_parent_message_carries_the_claim_of_the_work_it_continues() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "parent-dispatch".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let (point, _) = stop_a_running_turn(&thread).await;

    // The parent's own message is the authorization: no control input is manufactured next to it,
    // and holding the next Turn at the gate keeps the claim observable before it is consumed.
    let hold = gate.close();
    let sequence = thread
        .send_message_and_continue(
            ThreadMessage {
                kind: AgentMessageKind::Task,
                id: "parent-continue".into(),
                source_id: "parent".into(),
                payload: OpaquePayload::text("continue the original task"),
                context: vec![text("continue the original task")],
            },
            options(),
        )
        .await
        .unwrap();
    assert!(matches!(
        thread.snapshot().continuation.as_ref().map(|point| point.claim.clone()),
        Some(Some(pl_core::thread::ContinuationClaim::InboxMessage { sequence: claimed, .. })) if claimed == sequence
    ));
    wait_until(|| matches!(thread.snapshot().input_execution, InputExecution::Blocked)).await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    assert_eq!(
        thread
            .snapshot()
            .inputs
            .iter()
            .filter(|record| record.input.purpose == InputPurpose::Continuation)
            .count(),
        0
    );

    drop(hold);
    wait_until(|| thread.snapshot().consumed_messages >= sequence).await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert!(point.id.starts_with("continuation:"));
    thread.close().await.unwrap();
}

/// A backend that keeps the exact batch it was handed, so a test can read the final checkpoint.
#[derive(Debug, Clone)]
struct RecordingStore {
    admitted: Arc<AtomicU64>,
    durable: Arc<AtomicU64>,
    changed: watch::Sender<()>,
    last: Arc<Mutex<Option<ThreadWrite>>>,
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

    /// The newest checkpoint the backend received, cloned out of the recorded batch.
    fn latest_checkpoint(&self) -> Option<ThreadCheckpoint> {
        self.last
            .lock()
            .expect("recorded write")
            .as_ref()
            .map(|write| write.checkpoint.clone())
    }
}

impl ColdStore for RecordingStore {
    fn admit(&self, _thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
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

    fn subscribe_pressure(&self, _thread_id: &str) -> Option<watch::Receiver<()>> {
        Some(self.changed.subscribe())
    }

    async fn flush(&self, _thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        self.durable.fetch_max(sequence, Ordering::SeqCst);
        let _ = self.changed.send(());
        Ok(())
    }
}

#[tokio::test]
async fn a_content_continuation_waits_for_its_own_durable_commit() {
    let store = ManualStore::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "durable-content".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    // Real user content carries the claim too, so it owes exactly the same durability.
    thread
        .submit_input_and_continue(message_input("also", "Also check the logs"), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingStorage)
    })
    .await;
    let required = thread
        .snapshot()
        .required_durable_sequence
        .expect("a content continuation owes the commit that carries its claim");
    assert!(thread.snapshot().persistence.durable_sequence < required);
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "no model request may start before the claim is durable"
    );

    store.commit_durable();
    wait_until(|| thread.snapshot().required_durable_sequence.is_none()).await;
    wait_until(|| requests.lock().unwrap().len() == 2).await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    assert!(matches!(
        input_state(&thread, "also"),
        Some(InputState::Consumed { .. })
    ));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_parent_message_continuation_waits_for_its_own_durable_commit() {
    let store = ManualStore::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "durable-message".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    let sequence = thread
        .send_message_and_continue(
            ThreadMessage {
                kind: AgentMessageKind::Task,
                id: "parent-continue".into(),
                source_id: "parent".into(),
                payload: OpaquePayload::text("continue the original task"),
                context: vec![text("continue the original task")],
            },
            options(),
        )
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingStorage)
    })
    .await;
    let required = thread
        .snapshot()
        .required_durable_sequence
        .expect("a parent dispatch owes the commit that admits its message");
    assert!(thread.snapshot().persistence.durable_sequence < required);
    assert_eq!(requests.lock().unwrap().len(), 1);

    store.commit_durable();
    wait_until(|| thread.snapshot().required_durable_sequence.is_none()).await;
    wait_until(|| requests.lock().unwrap().len() == 2).await;
    wait_until(|| thread.snapshot().consumed_messages >= sequence).await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
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
    assert_eq!(point.claim, None);
    assert!(paused(&thread));
    assert_eq!(log.lock().unwrap().len(), 1);
    assert!(thread.effects().await.unwrap().iter().any(|effect| {
        effect.turn.as_ref().is_some_and(|turn| {
            turn.turn_id == point.source_turn_id.clone().unwrap_or_default()
                && turn.state == TurnState::Finished(TurnOutcome::StepLimit)
        })
    }));

    // An explicit body-less continuation opens exactly one more Turn.
    thread
        .continue_thread("after-step-limit".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "after-step-limit"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
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

/// A model whose provider call fails with the given category.
struct FailingModel(ModelFailureKind);

impl ModelSession for FailingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let kind = self.0;
        Ok(PreparedModelCall::new(async move {
            let _ = request;
            Err(ModelError {
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
            thread
                .continue_thread("after-failure".into(), options())
                .await,
            Err(ThreadError::NoContinuation)
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
    let point = thread.snapshot().continuation.clone().unwrap();
    assert_eq!(point.claim, None);
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
        .attach_storage(ColdStoreHandle::new(store.clone()))
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
            .latest_checkpoint()
            .is_some_and(|checkpoint| checkpoint.state.lifecycle == ThreadLifecycle::Closed)
    })
    .await;
    let checkpoint = store
        .latest_checkpoint()
        .expect("the close saved a checkpoint");
    let point = checkpoint
        .state
        .continuation
        .clone()
        .expect("a shutdown that cut live work leaves a point");
    assert_eq!(point.reason, Some(ContinuationReason::HostShutdown));
    assert!(
        checkpoint
            .state
            .turns
            .iter()
            .all(|turn| turn.state != TurnState::Running),
        "the cancelled Turn is settled, not left running"
    );
    let requests_after_shutdown = requests.lock().unwrap().len();

    // Restoring runs nothing; only an explicit continuation resumes the owed work.
    let resumed_requests = Arc::new(Mutex::new(Vec::new()));
    let resumed = ThreadHandle::resume(
        "shutdown".into(),
        DynModelSession::new(HeldModel {
            requests: resumed_requests.clone(),
            entered: None,
            release: None,
        }),
        Some(checkpoint),
    )
    .unwrap();
    assert!(paused(&resumed));
    assert!(resumed.snapshot().continuation.is_some());
    assert_eq!(requests.lock().unwrap().len(), requests_after_shutdown);
    assert!(resumed_requests.lock().unwrap().is_empty());
    resumed
        .continue_thread("after-shutdown".into(), options())
        .await
        .unwrap();
    wait_until(|| resumed_requests.lock().unwrap().len() == 1).await;
    wait_until(|| resumed.snapshot().continuation.is_none()).await;
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn a_stopped_preparing_execution_never_hands_its_identity_to_a_later_turn() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, _observed) = oneshot::channel();
    let (release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "identity".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
    let first = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("repeated")).await }
    });
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;
    let stopped = thread.snapshot().execution.clone().unwrap();
    assert!(stopped.turn_id.is_none());
    assert!(
        thread
            .interrupt_execution(stopped.id.clone())
            .await
            .unwrap()
    );
    assert!(matches!(first.await.unwrap(), Err(ThreadError::Cancelled)));
    wait_until(|| thread.snapshot().execution.is_none()).await;
    assert!(thread.snapshot().turns.is_empty());

    // The very same Turn identity is requested again, which is legitimate: it never got a record.
    drop(hold);
    let second = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("repeated")).await }
    });
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.turn_id.as_deref() == Some("repeated"))
    })
    .await;
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
async fn a_control_operation_identity_cannot_be_answered_by_an_ordinary_message() {
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("collision".into(), DynModelSession::new(model)).unwrap();
    thread
        .submit_input(message_input("collision", "Please handle this request"))
        .await
        .unwrap();
    assert!(matches!(
        thread.continue_thread("collision".into(), options()).await,
        Err(ThreadError::InvalidIdentity)
    ));
    assert_eq!(
        input_state(&thread, "collision"),
        Some(InputState::Pending),
        "the ordinary message is untouched"
    );
    assert!(requests.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_hand_written_control_input_is_refused_at_admission() {
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("forged".into(), DynModelSession::new(model)).unwrap();
    let forged = || ThreadInput {
        id: "forged".into(),
        purpose: InputPurpose::Continuation,
        payload: OpaquePayload::text("forged control"),
        context: Vec::new(),
    };
    // Framework control is only ever the canonical operation body for its own association, so a
    // hand-written one is never admitted under that purpose.
    assert!(matches!(
        thread.submit_input(forged()).await,
        Err(ThreadError::InvalidControlInput)
    ));
    assert!(matches!(
        thread.submit_input_and_continue(forged(), options()).await,
        Err(ThreadError::InvalidControlInput)
    ));
    assert!(thread.snapshot().inputs.is_empty());
    assert!(matches!(
        thread.continue_thread("forged".into(), options()).await,
        Err(ThreadError::NoContinuation)
    ));
    assert!(requests.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}

/// 保留给框架控制的格式不能被普通内容占用。
///
/// 该格式是类型化控制的编码，不是普通内容可借用的载体：一旦普通输入或父消息能占用它，保留格式
/// 就不再能说明来源，历史里的载荷也就失去了它原本对应的控制含义。
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
async fn a_terminal_control_receipt_rejects_a_foreign_body() {
    let (model, _) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("foreign-body".into(), DynModelSession::new(model)).unwrap();
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
    let checkpoint = thread
        .checkpoint(thread.snapshot().commit_sequence)
        .unwrap();
    thread.close().await.unwrap();

    // A stored identity that claims to be a control operation of a point it never ran: its recorded
    // digest belongs to the original message body, so no canonical control body can match it.
    let mut value = serde_json::to_value(&checkpoint).unwrap();
    {
        let state = value["state"].as_object_mut().expect("state object");

        let identities = state["terminalInputs"]
            .as_array_mut()
            .expect("terminal identities");
        let mut doctored = false;
        for identity in identities {
            let identity = identity.as_object_mut().expect("identity object");
            if identity.get("id").and_then(serde_json::Value::as_str) == Some("asked") {
                identity.insert("purpose".to_owned(), serde_json::json!("continuation"));
                identity.insert(
                    "continuation".to_owned(),
                    serde_json::json!({
                        "pointId": "continuation:0:forged",
                        "sourceTurnId": null,
                    }),
                );
                doctored = true;
            }
        }
        assert!(doctored, "the fixture must carry the identity it doctors");
    }
    let checkpoint: ThreadCheckpoint = serde_json::from_value(value).unwrap();
    let (model, requests) = support::ScriptedModel::new(&[]);
    let resumed = ThreadHandle::resume(
        "foreign-body".into(),
        DynModelSession::new(model),
        Some(checkpoint),
    )
    .unwrap();
    assert!(matches!(
        resumed.continue_thread("asked".into(), options()).await,
        Err(ThreadError::InvalidIdentity)
    ));
    assert!(requests.lock().unwrap().is_empty());
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn a_schema_4_checkpoint_defaults_the_new_fields_and_invents_no_continuation() {
    let (model, _) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("legacy-v4".into(), DynModelSession::new(model)).unwrap();
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
    let checkpoint = thread
        .checkpoint(thread.snapshot().commit_sequence)
        .unwrap();
    thread.close().await.unwrap();

    // Rewrite the envelope into the schema-4 shape: every field this schema never had is absent.
    let mut value = serde_json::to_value(&checkpoint).unwrap();
    value["schemaVersion"] = serde_json::json!(4);
    legacy_usage::flatten(&mut value);
    {
        let state = value["state"].as_object_mut().expect("state object");
        state.remove("continuation");
        state.remove("execution");
        state.remove("executionSequence");
        state.remove("requiredDurableSequence");
        for key in ["inputs", "terminalInputs"] {
            if let Some(records) = state.get_mut(key).and_then(serde_json::Value::as_array_mut) {
                for record in records {
                    let record = record.as_object_mut().expect("input object");
                    record.remove("purpose");
                    record.remove("continuation");
                }
            }
        }
    }
    let envelope = serde_json::to_string(&value).unwrap();
    assert!(ThreadCheckpoint::is_legacy_schema(4));
    let decoded = ThreadCheckpoint::decode_legacy(&envelope).unwrap();
    assert_eq!(decoded.schema_version, ThreadCheckpoint::SCHEMA_VERSION);
    assert!(decoded.state.continuation.is_none());
    assert!(decoded.state.execution.is_none());
    assert_eq!(decoded.state.execution_sequence, 0);
    assert_eq!(decoded.state.required_durable_sequence, None);
    assert!(
        decoded
            .state
            .inputs
            .iter()
            .all(|record| record.input.purpose == InputPurpose::Message)
    );
    assert!(decoded.state.terminal_inputs.iter().all(|identity| {
        identity.purpose == InputPurpose::Message && identity.continuation.is_none()
    }));
    assert!(
        !decoded.state.terminal_inputs.is_empty(),
        "the fixture must really carry the consumed input it strips"
    );

    // Settling the same facts invents no continuation: this Thread finished its work normally.
    let (model, _) = support::ScriptedModel::new(&[]);
    let resumed = ThreadHandle::resume(
        "legacy-v4".into(),
        DynModelSession::new(model),
        Some(decoded),
    )
    .unwrap();
    assert!(resumed.snapshot().continuation.is_none());
    assert!(paused(&resumed));
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn a_replaced_control_in_a_frozen_batch_is_settled_by_its_own_turn() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "frozen-replacement".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    // The control is accepted and frozen into the next batch, which is held at the gate.
    let hold = gate.close();
    thread
        .continue_thread("control".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;
    assert!(matches!(
        thread.snapshot().continuation.as_ref().map(|point| point.claim.clone()),
        Some(Some(pl_core::thread::ContinuationClaim::Input { input_id })) if input_id == "control"
    ));

    // A real message replaces that authorization while the control is still frozen in the batch.
    thread
        .submit_input_and_continue(message_input("real", "Also check the logs"), options())
        .await
        .unwrap();
    assert!(matches!(
        thread.snapshot().continuation.as_ref().map(|point| point.claim.clone()),
        Some(Some(pl_core::thread::ContinuationClaim::Input { input_id })) if input_id == "real"
    ));
    // The replaced control is voided in the same commit, even though its batch was still preparing.
    assert_eq!(input_state(&thread, "control"), Some(InputState::Discarded));

    // Stopping exactly that execution settles the batch: the replaced control is voided there.
    let waiting = thread.snapshot().execution.clone().unwrap();
    assert!(thread.interrupt_execution(waiting.id).await.unwrap());
    wait_until(|| thread.snapshot().execution.is_none() && paused(&thread)).await;
    assert_eq!(input_state(&thread, "control"), Some(InputState::Discarded));
    assert_eq!(
        input_state(&thread, "real"),
        Some(InputState::Pending),
        "real input is never deleted by a continuation"
    );
    let point = thread.snapshot().continuation.clone().unwrap();
    assert_eq!(point.claim, None);
    assert_eq!(point.reason, Some(ContinuationReason::UserStop));
    assert_eq!(requests.lock().unwrap().len(), 1);

    // One explicit continuation then carries the real message into exactly one Turn.
    drop(hold);
    thread
        .continue_thread("after-stop".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "real"),
            Some(InputState::Consumed { .. })
        ) && matches!(
            input_state(&thread, "after-stop"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    let turns = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .filter_map(|effect| effect.turn.clone())
        .map(|turn| turn.turn_id)
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(
        turns.len(),
        2,
        "one further Turn, not one per authorization"
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn an_idle_close_does_not_make_the_thread_continuable() {
    let store = RecordingStore::new();
    let (model, _) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("idle-close".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
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
    let checkpoint = store
        .latest_checkpoint()
        .expect("the close saved a checkpoint");
    assert_eq!(checkpoint.state.lifecycle, ThreadLifecycle::Closed);
    assert!(
        checkpoint.state.continuation.is_none(),
        "a normally finished Thread does not become continuable just because it closed"
    );
}

#[tokio::test]
async fn a_parent_message_takes_over_the_claim_of_a_waiting_control() {
    let store = ManualStore::new();
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "message-takeover".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    // A control holds the claim while its Turn waits at the admission gate.
    let hold = gate.close();
    thread
        .continue_thread("control".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;

    // The parent message takes the claim over instead of being admitted without one.
    let parent = ThreadMessage {
        kind: AgentMessageKind::Task,
        id: "parent-takeover".into(),
        source_id: "parent".into(),
        payload: OpaquePayload::text("continue the original task"),
        context: vec![text("continue the original task")],
    };
    let sequence = thread
        .send_message_and_continue(parent.clone(), options())
        .await
        .unwrap();
    assert_eq!(
        thread
            .snapshot()
            .inbox
            .iter()
            .find(|record| record.sequence == sequence)
            .map(|record| record.message.clone()),
        Some(parent.clone()),
        "the taking-over message keeps its own accepted body"
    );
    assert!(matches!(
        thread.snapshot().continuation.as_ref().map(|point| point.claim.clone()),
        Some(Some(pl_core::thread::ContinuationClaim::InboxMessage { sequence: claimed, .. }))
            if claimed == sequence
    ));
    // The message's own admission owes its durability: opening the gate is not enough.
    drop(hold);
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingStorage)
    })
    .await;
    let required = thread
        .snapshot()
        .required_durable_sequence
        .expect("the taking-over message owes its own commit");
    assert!(thread.snapshot().persistence.durable_sequence < required);
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "no request may start before the message that carries the claim is durable"
    );

    store.commit_durable();
    wait_until(|| requests.lock().unwrap().len() == 2).await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    // The control the message replaced is voided in the message's own admission commit, so it can never
    // be consumed afterwards under an authorization that no longer exists.
    assert_eq!(input_state(&thread, "control"), Some(InputState::Discarded));
    assert_eq!(thread.snapshot().required_durable_sequence, None);
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    // The parent message body really reached the request, exactly once, from its own source.
    let delivered = requests.lock().unwrap()[1].clone();
    assert_eq!(
        delivered
            .records
            .iter()
            .filter(|record| record.source
                == ContextSource::AgentMessage {
                    source_id: "parent".into(),
                    purpose: AgentMessageKind::Task,
                }
                && record.content == parent.context)
            .count(),
        1,
        "the taking-over message is delivered once and never duplicated"
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_store_less_continuation_leaves_no_durable_obligation() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::start(
        "store-less".into(),
        DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        }),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;
    thread
        .continue_thread("continuing".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "continuing"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    // A host without a cold store cannot claim durability, so no obligation may survive the claim.
    assert_eq!(thread.snapshot().required_durable_sequence, None);
    assert_eq!(requests.lock().unwrap().len(), 2);

    // A store attached afterwards starts from its own watermark and is not blocked by that claim.
    let store = ManualStore::new();
    thread
        .attach_storage(ColdStoreHandle::new(store))
        .await
        .unwrap();
    thread
        .submit_input_and_run(message_input("next", "One more thing"), options())
        .await
        .unwrap();
    wait_until(|| requests.lock().unwrap().len() == 3).await;
    assert_eq!(thread.snapshot().required_durable_sequence, None);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_resumed_queued_input_settles_the_point_it_serves() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = support::ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "resumed-queue".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
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
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;
    let preparing = thread.snapshot().execution.clone().unwrap();
    assert!(thread.interrupt_execution(preparing.id).await.unwrap());
    wait_until(|| thread.snapshot().execution.is_none() && paused(&thread)).await;
    // A stop during preparation leaves the point unclaimed and the input still queued.
    let point = thread.snapshot().continuation.clone().unwrap();
    assert_eq!(point.claim, None);
    assert_eq!(input_state(&thread, "asked"), Some(InputState::Pending));

    // Resuming that queued work is what serves the owed work, so the point is settled with it.
    drop(hold);
    thread.resume_inputs(options()).await.unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "asked"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    // Nothing is owed any more, so no empty continuation Turn can be opened.
    assert!(matches!(
        thread.continue_thread("again".into(), options()).await,
        Err(ThreadError::NoContinuation)
    ));
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_new_control_takes_over_an_unconsumed_parent_message_claim() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "message-then-control".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    // The parent message claims the point and its own Turn is held before admission.
    let hold = gate.close();
    let sequence = thread
        .send_message_and_continue(
            ThreadMessage {
                kind: AgentMessageKind::Task,
                id: "parent-message".into(),
                source_id: "parent".into(),
                payload: OpaquePayload::text("continue the original task"),
                context: vec![text("continue the original task")],
            },
            options(),
        )
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .continuation
            .as_ref()
            .and_then(|point| point.claim.clone())
            == Some(pl_core::thread::ContinuationClaim::InboxMessage {
                message_id: "parent-message".into(),
                sequence,
            })
    })
    .await;
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;

    // A newer explicit control takes the claim over; the message keeps its own accepted fact.
    let control = thread
        .continue_thread("after-message".into(), options())
        .await
        .unwrap();
    assert_eq!(control.state, InputState::Pending);
    assert_eq!(
        thread.snapshot().continuation.as_ref().unwrap().claim,
        Some(pl_core::thread::ContinuationClaim::Input {
            input_id: "after-message".into(),
        })
    );
    assert!(
        thread
            .snapshot()
            .inbox
            .iter()
            .any(|record| record.sequence == sequence && record.message.id == "parent-message"),
        "the replaced parent message keeps its own accepted body"
    );

    // One admission carries both: the control and the message it replaced.
    drop(hold);
    wait_until(|| thread.snapshot().consumed_messages >= sequence).await;
    wait_until(|| {
        matches!(
            input_state(&thread, "after-message"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert_eq!(
        requests.lock().unwrap()[1]
            .records
            .iter()
            .filter(|record| record.source
                == ContextSource::AgentMessage {
                    source_id: "parent".into(),
                    purpose: AgentMessageKind::Task,
                })
            .count(),
        1,
        "the replaced message is delivered once, not twice"
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_replaced_frozen_batch_is_re_frozen_with_the_new_content() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "re-freeze".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    // A control claims the point and its Turn is frozen before admission.
    let hold = gate.close();
    thread
        .continue_thread("control".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;

    // Real content replaces it while that batch is frozen but never admitted.
    thread
        .submit_input_and_continue(message_input("real", "Also check the logs"), options())
        .await
        .unwrap();
    assert_eq!(input_state(&thread, "control"), Some(InputState::Discarded));
    assert_eq!(
        thread.snapshot().continuation.as_ref().unwrap().claim,
        Some(pl_core::thread::ContinuationClaim::Input {
            input_id: "real".into(),
        })
    );

    // The gate opens normally: the old frozen batch is dropped and the content really reaches the
    // request instead of being marked consumed without being sent.
    drop(hold);
    wait_until(|| {
        matches!(
            input_state(&thread, "real"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
    thread.flush().await.unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    let second = requests.lock().unwrap()[1].clone();
    assert_eq!(
        second
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Also check the logs")])
            .count(),
        1,
        "the replacement content must be in the request that consumed it"
    );
    assert_eq!(
        second
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User
                && record.content == [text("Please handle this request")])
            .count(),
        1,
        "the interrupted request is delivered once, not replayed"
    );
    let turns = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .filter_map(|effect| effect.turn.clone())
        .map(|turn| turn.turn_id)
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(
        turns.len(),
        2,
        "one stopped Turn plus one continuation Turn"
    );
    assert!(thread.snapshot().inputs.is_empty());
    thread.close().await.unwrap();
}

/// A factory that hands out exactly the one prepared session it was built with.
///
/// It is what lets a test swap a Thread's binding the way a host does, without a second session being
/// opened behind the test's back.
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
                details: None,
                kind: self.kind,
                usage: Default::default(),
                source: None,
            });
        }
        self.answered = true;
        let call = ModelToolCall {
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
    let point = thread.snapshot().continuation.clone().unwrap();
    assert_eq!(point.claim, None);
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

    thread
        .continue_thread("after-failure".into(), options())
        .await
        .unwrap();
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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_external_stop_after_a_replacement_is_never_mistaken_for_it() {
    let gate = TurnAdmissionGate::new();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (entered, observed) = oneshot::channel();
    let (_release, held) = oneshot::channel();
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "stop-versus-replacement".into(),
        Some(DynModelSession::new(HeldModel {
            requests: requests.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();
    thread
        .submit_input_and_run(
            message_input("asked", "Please handle this request"),
            options(),
        )
        .await
        .unwrap();
    observed.await.expect("the first Turn reaches the provider");
    let _ = stop_a_running_turn(&thread).await;

    let hold = gate.close();
    thread
        .continue_thread("control".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        thread
            .snapshot()
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::AwaitingAdmission)
    })
    .await;

    // A replacement, and immediately an external stop: the stop must win over the replacement it did not
    // cause, whichever side of the cancellation the owner observes first.
    thread
        .submit_input_and_continue(message_input("real", "Also check the logs"), options())
        .await
        .unwrap();
    thread.interrupt();

    drop(hold);
    thread.flush().await.unwrap();
    // flush() is the durability barrier, not a settlement barrier: the cancelled Turn may still be
    // unwinding when it returns, so the assertions wait for the settled queue instead of observing
    // the transient state between the admission wait ending and the driver pausing.
    wait_until(|| {
        thread.snapshot().execution.is_none()
            && matches!(thread.snapshot().input_execution, InputExecution::Paused)
    })
    .await;
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "an external stop must never be turned into a fresh request"
    );
    assert!(
        !matches!(thread.snapshot().input_execution, InputExecution::Ready),
        "the queue stays stopped until an explicit continuation"
    );
    assert!(
        thread.snapshot().continuation.is_some(),
        "the owed work is still owed after a stop"
    );

    // Only an explicit continuation starts it again, and it carries the replacement content.
    thread
        .continue_thread("after-stop".into(), options())
        .await
        .unwrap();
    wait_until(|| {
        matches!(
            input_state(&thread, "real"),
            Some(InputState::Consumed { .. })
        )
    })
    .await;
    wait_until(|| thread.snapshot().continuation.is_none()).await;
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

/// A model whose call ignores cancellation and only returns when the test releases it.
///
/// It turns "the takeover's cancellation was issued but has not settled yet" into a controllable stage:
/// the owner is parked inside the call, so an external stop can be issued deterministically before the
/// driver ever observes that cancellation.
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
