//! Public-API behaviour of the Turn admission gate.
//!
//! The gate is the one point where new Turns are held back, and it is deliberately independent of
//! input admission, of the serial execution driver and of the storage safety point. These cases
//! prove that independence through the host-facing surface: a closed gate delays the next Turn
//! without consuming its input or creating a Turn record, several reasons to close are independent,
//! a Turn that already holds its permit is unaffected, and closing or cancelling a held admission
//! answers deterministically.

mod support;

use std::sync::{Arc, Mutex};

use pl_core::context::{AgentMessageKind, OpaquePayload};
use pl_core::model::{
    DynModelSession, ModelError, ModelFailureKind, ModelRequest, ModelSession, PreparedModelCall,
};
use pl_core::thread::{
    ModelStepLimit, ThreadHandle, ThreadLifecycle, TurnOutcome,
    admission::TurnAdmissionGate,
    inbox::ThreadMessage,
    input::{InputDriverOptions, InputExecution, InputState, ThreadInput},
};
use tokio::sync::oneshot;

use support::{ScriptedModel, response, text, turn};

fn queued_input(id: &str) -> ThreadInput {
    ThreadInput {
        id: id.into(),
        payload: OpaquePayload::text("queued request"),
        context: vec![text("Please handle this request")],
    }
}

fn options() -> InputDriverOptions {
    InputDriverOptions {
        max_model_steps: ModelStepLimit::Limited(1.try_into().expect("nonzero limit")),
    }
}

/// Waits for a condition on the live owner to hold.
///
/// The timeout only bounds a hung test; it is never the success criterion.
async fn wait_until(condition: impl Fn() -> bool) {
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while !condition() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("the owner must reach the expected state");
}

fn blocked(thread: &ThreadHandle) -> bool {
    matches!(thread.snapshot().input_execution, InputExecution::Blocked)
}

fn paused(thread: &ThreadHandle) -> bool {
    matches!(thread.snapshot().input_execution, InputExecution::Paused)
}

/// Whether `id` already reached the consumed state and its Turn ended.
///
/// The permit is held until the Turn ends, so pairing the consumed input with an empty permit count
/// is what proves the Turn finished instead of merely having committed its input.
fn consumed_and_finished(thread: &ThreadHandle, gate: &TurnAdmissionGate, id: &str) -> bool {
    let snapshot = thread.snapshot();
    snapshot
        .terminal_inputs
        .iter()
        .any(|identity| identity.id == id && matches!(identity.state, InputState::Consumed { .. }))
        && gate.admitted_turns() == 0
}

fn pending(thread: &ThreadHandle, id: &str) -> bool {
    thread
        .snapshot()
        .inputs
        .iter()
        .any(|record| record.input.id == id && record.state == InputState::Pending)
}

/// A model whose first provider call is held until the test releases it.
///
/// It is what makes "the Turn that already holds its permit" observable: the call cannot return
/// before the test releases it, so that Turn is provably in flight instead of merely scheduled.
struct HeldModel {
    /// Number of provider calls this session was asked to prepare.
    calls: Arc<Mutex<usize>>,
    entered: Option<oneshot::Sender<()>>,
    release: Option<oneshot::Receiver<()>>,
}

impl ModelSession for HeldModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        *self.calls.lock().expect("call log") += 1;
        if let Some(entered) = self.entered.take() {
            entered
                .send(())
                .expect("the test must observe the held call");
        }
        if let Some(release) = self.release.take() {
            tokio::select! {
                _ = release => {}
                // Cancellation ends the call without inventing a result.
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
        Ok(PreparedModelCall::new(async move {
            Ok(response(&request, Vec::new()))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[test]
fn independent_reasons_close_the_gate_and_a_permit_keeps_its_admission() {
    let gate = TurnAdmissionGate::new();
    assert!(gate.is_open());
    assert!(gate.is_clear());

    let first = gate.close();
    assert!(!gate.is_open());
    assert_eq!(gate.holds(), 1);
    let second = gate.close();
    assert_eq!(gate.holds(), 2);
    // Releasing the older reason must not reopen a gate that a newer reason still holds.
    drop(first);
    assert_eq!(gate.holds(), 1);
    assert!(!gate.is_open());
    assert!(gate.try_admit().is_none());

    drop(second);
    assert!(gate.is_open());
    assert!(gate.is_clear());

    // A Turn admitted while the gate was open keeps its admission: a reason taken afterwards only
    // holds back the next Turn.
    let permit = gate.try_admit().expect("an open gate admits");
    assert_eq!(gate.admitted_turns(), 1);
    assert!(!gate.is_clear());
    let later = gate.close();
    assert_eq!(gate.admitted_turns(), 1);
    assert!(gate.try_admit().is_none());
    drop(permit);
    assert_eq!(gate.admitted_turns(), 0);
    assert!(!gate.is_clear());
    drop(later);
    assert!(gate.is_clear());
}

#[tokio::test]
async fn a_closed_gate_holds_the_next_turn_without_consuming_its_input() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "gated".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();

    let receipt = thread
        .submit_input_and_run(queued_input("held"), options())
        .await
        .unwrap();
    assert_eq!(receipt.state, InputState::Pending);

    // The owner reaches the admission point and reports it: nothing is running, nothing was
    // consumed and no Turn record was created.
    wait_until(|| blocked(&thread)).await;
    assert!(thread.snapshot().turns.is_empty());
    assert_eq!(gate.admitted_turns(), 0);
    assert!(pending(&thread, "held"));
    assert!(requests.lock().unwrap().is_empty());
    // Control commands still settle while the next Turn is held.
    thread.flush().await.unwrap();

    drop(hold);

    // Releasing the gate admits exactly the held Turn, which consumes its input, reaches the
    // provider and ends.
    wait_until(|| consumed_and_finished(&thread, &gate, "held")).await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn an_admitted_turn_keeps_its_permit_and_only_the_next_turn_waits() {
    let gate = TurnAdmissionGate::new();
    let (entered, observed) = oneshot::channel();
    let (release, held) = oneshot::channel();
    let calls = Arc::new(Mutex::new(0));
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "permitted".into(),
        Some(DynModelSession::new(HeldModel {
            calls: calls.clone(),
            entered: Some(entered),
            release: Some(held),
        })),
        None,
        gate.clone(),
    )
    .unwrap();

    // The first Turn is admitted while the gate is open and holds its permit inside the provider
    // call.
    thread
        .submit_input_and_run(queued_input("first"), options())
        .await
        .unwrap();
    observed
        .await
        .expect("the first Turn must reach the provider");
    assert_eq!(gate.admitted_turns(), 1);

    // A reason taken now holds back the next Turn only.
    let reason = gate.close();
    assert!(!gate.is_open());
    assert_eq!(gate.admitted_turns(), 1);
    let receipt = thread
        .submit_input_and_run(queued_input("second"), options())
        .await
        .unwrap();
    assert_eq!(receipt.state, InputState::Pending);

    release.send(()).expect("the held call must be released");
    wait_until(|| consumed_and_finished(&thread, &gate, "first")).await;
    // The second input is taken out of the queue but cannot start: it is held at the gate, so the
    // provider is never called for it.
    wait_until(|| blocked(&thread)).await;
    assert_eq!(gate.admitted_turns(), 0);
    assert_eq!(*calls.lock().unwrap(), 1);
    assert!(pending(&thread, "second"));

    drop(reason);
    wait_until(|| consumed_and_finished(&thread, &gate, "second")).await;
    assert_eq!(*calls.lock().unwrap(), 2);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_direct_turn_waits_at_the_gate_before_it_starts() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "direct".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn("direct-turn")).await }
    });

    // The direct command reaches the same admission point as the queue driver: the Turn exists only
    // once the gate opens, so nothing has been committed for it yet.
    wait_until(|| blocked(&thread)).await;
    assert!(thread.snapshot().turns.is_empty());
    assert!(requests.lock().unwrap().is_empty());

    drop(hold);
    let completion = runner.await.unwrap().unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    assert_eq!(gate.admitted_turns(), 0);
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn an_inbox_wakeup_waits_at_the_gate_before_it_delivers() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "inbox".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
    let sequence = thread
        .send_message_and_resume(
            ThreadMessage {
                kind: AgentMessageKind::Report,
                id: "wake".into(),
                source_id: "child".into(),
                payload: OpaquePayload::text("finished"),
                context: vec![text("child finished")],
            },
            options(),
        )
        .await
        .unwrap();

    // An accepted message wakes the driver, and that wake-up reaches the same admission point: the
    // message is not delivered to a model while the gate is held.
    wait_until(|| blocked(&thread)).await;
    assert!(thread.snapshot().turns.is_empty());
    assert_eq!(thread.snapshot().consumed_messages, 0);
    assert!(requests.lock().unwrap().is_empty());

    drop(hold);
    wait_until(|| requests.lock().unwrap().len() == 1).await;
    assert!(thread.snapshot().consumed_messages >= sequence);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn closing_answers_deterministically_while_the_next_turn_is_held() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "closing".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
    thread
        .submit_input_and_run(queued_input("held-while-closing"), options())
        .await
        .unwrap();
    wait_until(|| blocked(&thread)).await;

    // Closing must not wait for a gate that is still held.
    thread.close().await.unwrap();
    assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
    assert!(thread.snapshot().turns.is_empty());
    assert_eq!(gate.admitted_turns(), 0);
    assert!(pending(&thread, "held-while-closing"));
    assert!(requests.lock().unwrap().is_empty());
    assert!(paused(&thread));

    // Opening the gate afterwards cannot start a Turn on a closed owner.
    drop(hold);
    tokio::task::yield_now().await;
    assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
    assert!(requests.lock().unwrap().is_empty());
}

#[tokio::test]
async fn interrupting_a_held_admission_pauses_the_queue_instead_of_starting_it() {
    let gate = TurnAdmissionGate::new();
    let (model, requests) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "interrupted".into(),
        Some(DynModelSession::new(model)),
        None,
        gate.clone(),
    )
    .unwrap();
    let hold = gate.close();
    thread
        .submit_input_and_run(queued_input("held-while-interrupted"), options())
        .await
        .unwrap();
    wait_until(|| blocked(&thread)).await;

    // Nothing was admitted, so no Turn record exists to match; the pending admission is what stops
    // and the command reports that work was stopped. The queue stays paused, so releasing the gate
    // cannot start it either.
    assert!(thread.interrupt_turn(None).await.unwrap());
    wait_until(|| paused(&thread)).await;
    assert!(thread.snapshot().turns.is_empty());

    drop(hold);
    tokio::task::yield_now().await;
    assert!(requests.lock().unwrap().is_empty());
    assert!(pending(&thread, "held-while-interrupted"));

    // An explicit resume starts the input that was never consumed.
    thread.resume_inputs(options()).await.unwrap();
    wait_until(|| consumed_and_finished(&thread, &gate, "held-while-interrupted")).await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn a_resumed_owner_cannot_run_its_recovered_input_before_the_gate_opens() {
    // Capture a checkpoint that still owes one accepted input.
    let (model, _) = ScriptedModel::new(&[]);
    let original = ThreadHandle::start("recovered".into(), DynModelSession::new(model)).unwrap();
    original
        .submit_input(queued_input("recovered"))
        .await
        .unwrap();
    let checkpoint = original
        .checkpoint(original.snapshot().commit_sequence)
        .unwrap();
    original.close().await.unwrap();

    let gate = TurnAdmissionGate::new();
    let hold = gate.close();
    let (model, requests) = ScriptedModel::new(&[]);
    // The gate belongs to the incarnation, so it exists before the recovered input can be resumed.
    let thread = ThreadHandle::resume_with_turn_admission_gate(
        "recovered".into(),
        Some(DynModelSession::new(model)),
        Some(checkpoint),
        gate.clone(),
    )
    .unwrap();

    thread.resume_inputs(options()).await.unwrap();
    wait_until(|| blocked(&thread)).await;
    assert!(requests.lock().unwrap().is_empty());
    assert!(pending(&thread, "recovered"));

    drop(hold);
    wait_until(|| consumed_and_finished(&thread, &gate, "recovered")).await;
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}
