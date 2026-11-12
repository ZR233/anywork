//! Fixed durability waits must not own the serial execution owner.
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU64, Ordering},
};
use std::time::Duration;

use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        AggregateChannel, DynModelSession, ModelError, ModelMemberSender, ModelRequest,
        ModelSession, ModelStepOutput, ObservedPartIdentity, PreparedModelCall,
    },
    thread::{
        AttemptOutcome, ModelStepLimit, ThreadError, ThreadHandle, TurnInput,
        cold::{
            ColdStore, ColdStoreError, ColdStoreHandle, StorageAdmissionBackpressure,
            StorageFaultKind, StoragePressure, ThreadWrite,
        },
        inbox::ThreadMessage,
    },
};
use tokio::sync::{mpsc, oneshot, watch};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PressureHandoff {
    Durable,
    Fault,
}

const HANDOFF_FAULT_GENERATION: u64 = 73;

#[derive(Debug)]
struct Store {
    writes: Mutex<Vec<ThreadWrite>>,
    durable: AtomicU64,
    automatic: AtomicBool,
    reject: AtomicBool,
    backpressure: AtomicBool,
    unavailable: AtomicBool,
    entered: mpsc::Sender<u64>,
    updates: watch::Sender<()>,
    handoff: Option<PressureHandoff>,
    handoff_armed: AtomicBool,
    handoff_delivered: CancellationToken,
}

impl Store {
    fn new() -> (Arc<Self>, mpsc::Receiver<u64>) {
        Self::with_handoff(None)
    }

    fn with_handoff(handoff: Option<PressureHandoff>) -> (Arc<Self>, mpsc::Receiver<u64>) {
        let (entered, calls) = mpsc::channel(16);
        let (updates, _) = watch::channel(());
        (
            Arc::new(Self {
                writes: Mutex::new(Vec::new()),
                durable: AtomicU64::new(0),
                automatic: AtomicBool::new(false),
                reject: AtomicBool::new(false),
                backpressure: AtomicBool::new(false),
                unavailable: AtomicBool::new(false),
                entered,
                updates,
                handoff,
                handoff_armed: AtomicBool::new(false),
                handoff_delivered: CancellationToken::new(),
            }),
            calls,
        )
    }

    fn save(&self, through: u64) {
        self.durable.fetch_max(through, Ordering::SeqCst);
        self.updates.send_replace(());
    }

    fn finish_saves(&self) {
        self.automatic.store(true, Ordering::SeqCst);
        self.save(self.writes.lock().unwrap().last().unwrap().effect.sequence);
    }
}

#[derive(Debug)]
struct Storage(Arc<Store>);

impl std::ops::Deref for Storage {
    type Target = Store;

    fn deref(&self) -> &Store {
        &self.0
    }
}

impl ColdStore for Storage {
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if self.reject.load(Ordering::SeqCst) {
            return Err(storage_error());
        }
        if self.backpressure.load(Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(StorageAdmissionBackpressure("controlled queue full".into())),
            });
        }
        let sequence = write.effect.sequence;
        if self.handoff.is_some()
            && write
                .effect
                .attempt
                .as_ref()
                .is_some_and(|attempt| matches!(attempt.outcome, AttemptOutcome::Running))
        {
            self.handoff_armed.store(true, Ordering::SeqCst);
        }
        self.writes.lock().unwrap().push(write);
        if self.automatic.load(Ordering::SeqCst) {
            self.save(sequence);
        }
        Ok(())
    }

    fn pressure(&self, _: &str) -> StoragePressure {
        let faulted =
            self.handoff == Some(PressureHandoff::Fault) && self.unavailable.load(Ordering::SeqCst);
        StoragePressure {
            durable_sequence: self.durable.load(Ordering::SeqCst),
            error: self
                .unavailable
                .load(Ordering::SeqCst)
                .then(|| Arc::new(storage_error())),
            fault: faulted.then_some(StorageFaultKind::WriteFailed),
            fault_generation: if self.handoff == Some(PressureHandoff::Fault) {
                HANDOFF_FAULT_GENERATION
            } else {
                0
            },
            ..Default::default()
        }
    }

    fn subscribe_pressure(&self, _: &str) -> Option<watch::Receiver<()>> {
        if self.handoff_armed.swap(false, Ordering::SeqCst) {
            // The Running effect's last pressure sample is already complete. Deliver the writer's
            // next report immediately before subscribe, so this new receiver considers it seen.
            match self.handoff {
                Some(PressureHandoff::Durable) => {
                    let through = self.writes.lock().unwrap().last().unwrap().effect.sequence;
                    self.save(through);
                }
                Some(PressureHandoff::Fault) => {
                    self.unavailable.store(true, Ordering::SeqCst);
                    self.updates.send_replace(());
                }
                None => unreachable!("only handoff tests arm delivery"),
            }
            self.handoff_delivered.cancel();
        }
        Some(self.updates.subscribe())
    }

    async fn flush(&self, _: &str, through: u64) -> Result<(), ColdStoreError> {
        let mut updates = self.updates.subscribe();
        self.entered.try_send(through).unwrap();
        loop {
            if self.unavailable.load(Ordering::SeqCst) {
                return Err(storage_error());
            }
            if self.durable.load(Ordering::SeqCst) >= through {
                return Ok(());
            }
            updates.changed().await.unwrap();
        }
    }
}

fn storage_error() -> ColdStoreError {
    ColdStoreError {
        source: Box::new(std::io::Error::other("controlled writer unavailable")),
    }
}

struct WaitingModel(Option<oneshot::Sender<ModelMemberSender>>);

impl ModelSession for WaitingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let ready = self.0.take().unwrap();
        Ok(PreparedModelCall::new(async move {
            ready.send(request.members.clone().unwrap()).unwrap();
            request.cancellation.cancelled().await;
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: Vec::new(),
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

fn turn() -> TurnInput {
    TurnInput {
        turn_id: "flush-turn".into(),
        attempt_prefix: "flush-attempt".into(),
        content: vec![ContextContent::Text {
            text: Arc::from("question"),
        }],
        max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
        cancellation: Default::default(),
    }
}

async fn within<T>(future: impl std::future::Future<Output = T>) -> T {
    tokio::time::timeout(Duration::from_secs(5), future)
        .await
        .expect("controlled stage must remain reachable")
}

#[tokio::test]
async fn blocked_flush_keeps_member_admission_and_interrupt_reachable() {
    let (store, mut calls) = Store::new();
    let (ready, receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "flush-reachability".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn()).await })
    };
    let sender = within(receiver).await.unwrap();
    let flushing = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.flush().await })
    };
    let target = within(calls.recv()).await.unwrap();
    assert!(target > 0);
    let members = tokio::spawn(async move {
        let identity = ObservedPartIdentity::Aggregate {
            channel: AggregateChannel::Text,
        };
        sender.start(0, identity.clone(), None).await.unwrap();
        sender.content_available(0, identity, None).await.unwrap();
        sender
            .submit(
                0,
                "finished".into(),
                OpaquePayload::text("retained member"),
                None,
            )
            .await
            .unwrap();
    });
    // A test-only bound diagnoses the old Owner wait. Always release and join the real work
    // before reporting the red result, so the reproduction itself leaves no orphan tasks.
    let mut members = members;
    let reachable = tokio::time::timeout(Duration::from_secs(1), &mut members).await;
    let admitted_before_save = reachable.is_ok();
    if let Ok(result) = reachable {
        result.unwrap();
    }
    assert!(!flushing.is_finished());
    if admitted_before_save {
        let writes = store.writes.lock().unwrap();
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_member_starts.len())
                .sum::<usize>(),
            1
        );
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_member_content_available.len())
                .sum::<usize>(),
            1
        );
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_members.len())
                .sum::<usize>(),
            1
        );
    }
    let execution = thread.snapshot().execution.as_ref().unwrap().id.clone();
    // On the fixed implementation, stop and real invocation join precede disk release.
    if admitted_before_save {
        assert!(matches!(
            within(thread.interrupt_execution("superseded".into())).await,
            Err(ThreadError::InvalidIdentity)
        ));
        assert!(
            within(thread.interrupt_execution(execution.clone()))
                .await
                .unwrap()
        );
    }
    let mut runner = runner;
    let settled_before_save = if admitted_before_save {
        Some(within(&mut runner).await.unwrap())
    } else {
        None
    };
    store.finish_saves();
    if !admitted_before_save {
        within(members).await.unwrap();
    }
    within(flushing).await.unwrap().unwrap();
    if !admitted_before_save {
        assert!(within(thread.interrupt_execution(execution)).await.unwrap());
    }
    let settled = match settled_before_save {
        Some(result) => result,
        None => within(runner).await.unwrap(),
    };
    assert!(matches!(settled, Err(ThreadError::Cancelled)));
    within(thread.close()).await.unwrap();
    assert!(
        admitted_before_save,
        "Owner withheld Started/ContentAvailable/Completed reply while a public flush waited"
    );
}

fn message(id: &str) -> ThreadMessage {
    ThreadMessage {
        id: id.into(),
        source_id: "test".into(),
        kind: Default::default(),
        payload: OpaquePayload::text(id),
        context: Vec::new(),
    }
}

async fn idle_thread(store: &Arc<Store>) -> ThreadHandle {
    let thread = ThreadHandle::resume_without_model("idle-flush".into(), None).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    within(thread.send_message(message("first"))).await.unwrap();
    thread
}

#[tokio::test]
async fn concurrent_flushes_fix_independent_targets_without_chasing_new_admissions() {
    let (store, mut calls) = Store::new();
    let thread = idle_thread(&store).await;
    let first = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.flush().await })
    };
    let first_target = within(calls.recv()).await.unwrap();
    within(thread.send_message(message("second")))
        .await
        .unwrap();
    let second = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.flush().await })
    };
    let second_target = within(calls.recv()).await.unwrap();
    assert!(second_target > first_target);
    within(thread.send_message(message("third"))).await.unwrap();
    store.save(first_target);
    within(first).await.unwrap().unwrap();
    assert!(!second.is_finished());
    store.save(second_target);
    within(second).await.unwrap().unwrap();
    assert!(store.writes.lock().unwrap().last().unwrap().effect.sequence > second_target);
    store.finish_saves();
    within(thread.close()).await.unwrap();
    within(thread.flush()).await.unwrap();
}

#[tokio::test]
async fn dropping_a_flush_caller_preserves_original_writer_facts_and_next_wait() {
    let (store, mut calls) = Store::new();
    let thread = idle_thread(&store).await;
    let abandoned = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.flush().await })
    };
    let target = within(calls.recv()).await.unwrap();
    let count = store.writes.lock().unwrap().len();
    abandoned.abort();
    assert!(within(abandoned).await.unwrap_err().is_cancelled());
    assert_eq!(store.writes.lock().unwrap().len(), count);
    assert!(store.durable.load(Ordering::SeqCst) < target);
    let following = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.flush().await })
    };
    assert_eq!(within(calls.recv()).await.unwrap(), target);
    store.save(target);
    within(following).await.unwrap().unwrap();
    store.finish_saves();
    within(thread.close()).await.unwrap();
}

async fn receipt_releases_window(while_running: bool) {
    let (store, _calls) = Store::new();
    let (thread, runner) = if while_running {
        let (ready, receiver) = oneshot::channel();
        let thread = ThreadHandle::start(
            "network-wait".into(),
            DynModelSession::new(WaitingModel(Some(ready))),
        )
        .unwrap();
        thread
            .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
            .await
            .unwrap();
        let runner = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.run_turn(turn()).await })
        };
        within(receiver).await.unwrap();
        (thread, Some(runner))
    } else {
        (idle_thread(&store).await, None)
    };
    let target = thread.snapshot().persistence.admitted_sequence;
    assert!(target > 0);
    assert!(thread.effect_window_start().is_some());
    let mut snapshots = thread.subscribe();
    store.save(target);
    within(async {
        loop {
            let snapshot = snapshots.next().await.unwrap();
            if snapshot.persistence.durable_sequence >= target {
                break;
            }
        }
    })
    .await;
    assert_eq!(thread.effect_window_start(), Some(target + 1));
    assert!(
        within(thread.effect_page(target, 8.try_into().unwrap()))
            .await
            .unwrap()
            .is_empty()
    );
    if let Some(runner) = runner {
        within(thread.interrupt_turn(None)).await.unwrap();
        assert!(matches!(
            within(runner).await.unwrap(),
            Err(ThreadError::Cancelled)
        ));
    }
    store.finish_saves();
    within(thread.close()).await.unwrap();
}

#[tokio::test]
async fn pressure_receipt_advances_durability_during_network_wait() {
    receipt_releases_window(true).await;
}

#[tokio::test]
async fn pressure_receipt_advances_durability_while_idle() {
    receipt_releases_window(false).await;
}

async fn report_at_subscription_handoff(handoff: PressureHandoff) {
    let (store, _calls) = Store::with_handoff(Some(handoff));
    let (ready, receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "pressure-handoff".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    within(thread.attach_storage(ColdStoreHandle::new(Storage(store.clone()))))
        .await
        .unwrap();
    let input = turn();
    let cancellation = input.cancellation.clone();
    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(input).await })
    };
    // The prepared operation's first poll is after the owner established its pressure wait.
    // No more provider events or notifications occur before this snapshot is captured.
    within(receiver).await.unwrap();
    let delivered = store.handoff_delivered.is_cancelled();
    let snapshot = thread.snapshot();
    let target = store.writes.lock().unwrap().last().unwrap().effect.sequence;
    let backend_durable = store.durable.load(Ordering::SeqCst);
    let window_start = thread.effect_window_start();
    println!(
        "handoff={handoff:?}; backend durable={backend_durable}; owner durable={}; fault={:?}; generation={}; resume_required={}",
        snapshot.persistence.durable_sequence,
        snapshot.persistence.fault,
        snapshot.persistence.fault_generation,
        snapshot.persistence.resume_required,
    );

    // A genuinely recovered report must not silently release an already observed fault generation.
    let recovery_still_requires_resume = if handoff == PressureHandoff::Fault {
        let mut snapshots = thread.subscribe();
        store.unavailable.store(false, Ordering::SeqCst);
        store.save(target);
        within(async {
            loop {
                let recovered = snapshots.next().await.unwrap();
                if recovered.persistence.durable_sequence >= target
                    && recovered.persistence.error.is_none()
                {
                    break recovered.persistence.resume_required
                        && recovered.persistence.fault_generation == HANDOFF_FAULT_GENERATION
                        && !recovered.persistence.resume_ready;
                }
            }
        })
        .await
    } else {
        true
    };
    // Always join original work before asserting the observation, including the red implementation.
    cancellation.cancel();
    let settled = within(runner).await.unwrap();
    store.finish_saves();
    within(thread.close()).await.unwrap();

    assert!(
        delivered,
        "the controlled subscription handoff must be exercised"
    );
    assert!(target > 0);
    assert!(matches!(settled, Err(ThreadError::Cancelled)));
    match handoff {
        PressureHandoff::Durable => {
            assert_eq!(backend_durable, target);
            assert_eq!(
                snapshot.persistence.durable_sequence, target,
                "a durable report at subscribe must fold without a redundant notification"
            );
            assert_eq!(window_start, Some(target + 1));
        }
        PressureHandoff::Fault => {
            assert_eq!(
                snapshot.persistence.fault,
                Some(StorageFaultKind::WriteFailed),
                "a fault report at subscribe must fold before entering the network wait"
            );
            assert!(snapshot.persistence.error.is_some());
            assert_eq!(
                snapshot.persistence.fault_generation,
                HANDOFF_FAULT_GENERATION
            );
            assert!(snapshot.persistence.resume_required);
            assert!(!snapshot.persistence.resume_ready);
            assert!(recovery_still_requires_resume);
        }
    }
}

#[tokio::test]
async fn durable_report_at_subscription_handoff_folds_before_network_wait() {
    report_at_subscription_handoff(PressureHandoff::Durable).await;
}

#[tokio::test]
async fn fault_report_at_subscription_handoff_latches_before_network_wait() {
    report_at_subscription_handoff(PressureHandoff::Fault).await;
}

#[tokio::test]
async fn flush_rejects_unhanded_tail_and_writer_failure_without_claiming_a_smaller_prefix() {
    let (store, mut calls) = Store::new();
    let thread = idle_thread(&store).await;
    let previous = thread.snapshot().persistence.admitted_sequence;
    store.save(previous);
    store.reject.store(true, Ordering::SeqCst);
    within(thread.send_message(message("unhanded")))
        .await
        .unwrap();
    assert!(thread.snapshot().commit_sequence > previous);
    assert!(matches!(
        within(thread.flush()).await,
        Err(ThreadError::Storage(_))
    ));
    assert!(
        calls.try_recv().is_err(),
        "no success ticket for a smaller prefix"
    );
    store.reject.store(false, Ordering::SeqCst);
    store.unavailable.store(true, Ordering::SeqCst);
    store.updates.send_replace(());
    assert!(matches!(
        within(thread.flush()).await,
        Err(ThreadError::Storage(_))
    ));
    store.unavailable.store(false, Ordering::SeqCst);
    store.finish_saves();
    within(thread.close()).await.unwrap();
}

#[tokio::test]
async fn close_joins_invocation_but_reports_unsaved_tail_and_can_retry_preservation() {
    let (store, mut calls) = Store::new();
    let (ready, receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "close-unsaved-tail".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn()).await })
    };
    let sender = within(receiver).await.unwrap();
    within(sender.submit(
        0,
        "finished".into(),
        OpaquePayload::text("saved later"),
        None,
    ))
    .await
    .unwrap();
    let flushing = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.flush().await })
    };
    let public_target = within(calls.recv()).await.unwrap();
    let closing = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.close().await })
    };
    let final_target = within(calls.recv()).await.unwrap();
    assert!(final_target > public_target);
    assert!(matches!(
        within(runner).await.unwrap(),
        Err(ThreadError::Cancelled)
    ));
    assert!(
        !closing.is_finished(),
        "execution join is not a durability proof"
    );
    assert!(matches!(
        within(sender.submit(0, "late".into(), OpaquePayload::text("late"), None)).await,
        Err(pl_core::model::ModelMemberError::Closed)
    ));
    store.unavailable.store(true, Ordering::SeqCst);
    store.updates.send_replace(());
    assert!(matches!(
        within(flushing).await.unwrap(),
        Err(ThreadError::Storage(_))
    ));
    assert!(matches!(
        within(closing).await.unwrap(),
        Err(ThreadError::Storage(_))
    ));
    assert_ne!(
        thread.snapshot().lifecycle,
        pl_core::thread::ThreadLifecycle::Closed
    );
    assert!(
        store
            .writes
            .lock()
            .unwrap()
            .iter()
            .any(|write| !write.effect.model_members.is_empty())
    );
    store.unavailable.store(false, Ordering::SeqCst);
    store.finish_saves();
    within(thread.close()).await.unwrap();
    within(thread.flush()).await.unwrap();
}

#[tokio::test]
async fn capacity_backpressure_preserves_close_without_latching_a_failed_save() {
    let (store, mut calls) = Store::new();
    let thread = idle_thread(&store).await;
    let before = thread.snapshot().persistence.admitted_sequence;
    store.save(before);
    store.backpressure.store(true, Ordering::SeqCst);
    within(thread.send_message(message("retained-tail")))
        .await
        .unwrap();
    let error = within(thread.flush()).await.unwrap_err();
    assert!(matches!(error, ThreadError::Storage(ref source)
        if source.source.is::<StorageAdmissionBackpressure>()));
    assert!(
        calls.try_recv().is_err(),
        "never certify a smaller admitted prefix"
    );
    let snapshot = thread.snapshot();
    assert!(snapshot.commit_sequence > before);
    assert!(snapshot.persistence.pressure_paused);
    assert!(snapshot.persistence.error.is_none());
    assert!(!snapshot.persistence.resume_required);

    let mut snapshots = thread.subscribe();
    let closing = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.close().await })
    };
    within(async {
        while snapshots.next().await.unwrap().lifecycle != pl_core::thread::ThreadLifecycle::Closing
        {
        }
    })
    .await;
    // The public mailbox stays reachable even while close owes an unadmitted final fact.
    assert!(matches!(
        within(thread.flush()).await,
        Err(ThreadError::Storage(_))
    ));
    assert!(!closing.is_finished());
    store.automatic.store(true, Ordering::SeqCst);
    store.backpressure.store(false, Ordering::SeqCst);
    store.updates.send_replace(());
    within(closing).await.unwrap().unwrap();
    let snapshot = thread.snapshot();
    assert_eq!(
        snapshot.persistence.durable_sequence,
        snapshot.commit_sequence
    );
    assert!(!snapshot.persistence.resume_required);
    assert!(snapshot.persistence.error.is_none());
    let writes = store.writes.lock().unwrap();
    assert!(
        writes
            .windows(2)
            .all(|pair| pair[0].effect.sequence + 1 == pair[1].effect.sequence)
    );
    assert_eq!(
        writes.last().unwrap().effect.sequence,
        snapshot.commit_sequence
    );
}

#[tokio::test]
async fn capacity_backpressure_holds_model_admission_then_resumes_on_actual_progress() {
    let (store, _calls) = Store::new();
    store.backpressure.store(true, Ordering::SeqCst);
    let (ready, mut receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "backpressure-admission".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    within(thread.attach_storage(ColdStoreHandle::new(Storage(store.clone()))))
        .await
        .unwrap();
    let mut snapshots = thread.subscribe();
    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(turn()).await })
    };
    let snapshot = within(async {
        loop {
            let snapshot = snapshots.next().await.unwrap();
            if snapshot.persistence.execution_phase
                == pl_core::thread::cold::StorageExecutionPhase::PausedForStorage
            {
                break snapshot;
            }
        }
    })
    .await;
    assert!(snapshot.persistence.pressure_paused);
    assert!(snapshot.persistence.error.is_none());
    assert!(!snapshot.persistence.resume_required);
    assert!(matches!(
        receiver.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    ));
    store.automatic.store(true, Ordering::SeqCst);
    store.backpressure.store(false, Ordering::SeqCst);
    store.updates.send_replace(());
    within(receiver).await.unwrap();
    assert!(!thread.snapshot().persistence.resume_required);
    within(thread.interrupt_turn(None)).await.unwrap();
    assert!(matches!(
        within(runner).await.unwrap(),
        Err(ThreadError::Cancelled)
    ));
    within(thread.close()).await.unwrap();
}
