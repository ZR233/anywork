//! Fixed durability waits must not own the serial execution owner.
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU64, Ordering},
};
use std::time::Duration;

use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelMemberSender, ModelRequest, ModelSession,
        ModelStepOutput, PreparedModelCall,
    },
    thread::{
        AttemptOutcome, HistoryExport, ModelStepLimit, ThreadError, ThreadHandle, TurnInput,
        UsageSummary,
        cold::{
            ColdStoreError, StorageAdmissionBackpressure, StorageFaultKind, StorageIdleStatus,
            StoragePressure,
        },
        history_sink::{HistorySink, HistorySinkHandle},
        inbox::ThreadMessage,
    },
};
use tokio::sync::{oneshot, watch};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PressureHandoff {
    Durable,
    Fault,
}

const HANDOFF_FAULT_GENERATION: u64 = 73;

#[derive(Debug)]
struct Store {
    writes: Mutex<Vec<Arc<HistoryExport>>>,
    durable: AtomicU64,
    automatic: AtomicBool,
    reject: AtomicBool,
    backpressure: AtomicBool,
    unavailable: AtomicBool,
    updates: watch::Sender<()>,
    handoff: Option<PressureHandoff>,
    handoff_delivered: CancellationToken,
}

impl Store {
    fn new() -> Arc<Self> {
        Self::with_handoff(None)
    }

    fn with_handoff(handoff: Option<PressureHandoff>) -> Arc<Self> {
        let (updates, _) = watch::channel(());
        Arc::new(Self {
            writes: Mutex::new(Vec::new()),
            durable: AtomicU64::new(0),
            automatic: AtomicBool::new(false),
            reject: AtomicBool::new(false),
            backpressure: AtomicBool::new(false),
            unavailable: AtomicBool::new(false),
            updates,
            handoff,
            handoff_delivered: CancellationToken::new(),
        })
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

impl HistorySink for Storage {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &pl_core::thread::ThreadEffectBatch) {
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
    fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        if self.reject.load(Ordering::SeqCst) {
            return Err(storage_error());
        }
        if self.backpressure.load(Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(StorageAdmissionBackpressure("controlled queue full".into())),
            });
        }
        let sequence = write.effect.sequence;
        let running_handoff = self.handoff.is_some()
            && write
                .effect
                .attempt
                .as_ref()
                .is_some_and(|attempt| matches!(attempt.outcome, AttemptOutcome::Running));
        self.writes.lock().unwrap().push(write);
        if running_handoff {
            match self.handoff {
                Some(PressureHandoff::Durable) => self.save(sequence),
                Some(PressureHandoff::Fault) => {
                    self.unavailable.store(true, Ordering::SeqCst);
                    self.updates.send_replace(());
                }
                None => unreachable!(),
            }
            self.handoff_delivered.cancel();
        }
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

    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: Some(0),
        }
    }

    fn subscribe_pressure(&self, _: &str) -> Option<watch::Receiver<()>> {
        Some(self.updates.subscribe())
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
    let thread = ThreadHandle::start_current("idle-flush".into(), None).unwrap();
    thread
        .attach_history(HistorySinkHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    within(thread.send_message(message("first"))).await.unwrap();
    thread
}

async fn receipt_releases_window(while_running: bool) {
    let store = Store::new();
    let (thread, runner) = if while_running {
        let (ready, receiver) = oneshot::channel();
        let thread = ThreadHandle::start(
            "network-wait".into(),
            DynModelSession::new(WaitingModel(Some(ready))),
        )
        .unwrap();
        thread
            .attach_history(HistorySinkHandle::new(Storage(store.clone())))
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

async fn report_at_running_handoff(handoff: PressureHandoff) {
    let store = Store::with_handoff(Some(handoff));
    let (ready, receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "pressure-handoff".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    within(thread.attach_history(HistorySinkHandle::new(Storage(store.clone()))))
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

    assert!(delivered, "the controlled writer handoff must be exercised");
    assert!(target > 0);
    assert!(matches!(settled, Err(ThreadError::Cancelled)));
    match handoff {
        PressureHandoff::Durable => {
            assert_eq!(backend_durable, target);
            assert_eq!(
                snapshot.persistence.durable_sequence, target,
                "a durable report at admission must fold without a redundant notification"
            );
            assert_eq!(window_start, Some(target + 1));
        }
        PressureHandoff::Fault => {
            assert_eq!(
                snapshot.persistence.fault,
                Some(StorageFaultKind::WriteFailed),
                "a fault report at admission must fold before entering the network wait"
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
async fn durable_report_at_running_handoff_folds_before_network_wait() {
    report_at_running_handoff(PressureHandoff::Durable).await;
}

#[tokio::test]
async fn fault_report_at_running_handoff_latches_before_network_wait() {
    report_at_running_handoff(PressureHandoff::Fault).await;
}

#[tokio::test]
async fn close_joins_invocation_but_reports_unsaved_tail_and_can_retry_preservation() {
    let store = Store::new();
    let (ready, receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "close-unsaved-tail".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    thread
        .attach_history(HistorySinkHandle::new(Storage(store.clone())))
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
    let closing = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.close().await })
    };
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
}

#[tokio::test]
async fn capacity_backpressure_preserves_close_without_latching_a_failed_save() {
    let store = Store::new();
    let thread = idle_thread(&store).await;
    let before = thread.snapshot().persistence.admitted_sequence;
    store.save(before);
    store.backpressure.store(true, Ordering::SeqCst);
    within(thread.send_message(message("retained-tail")))
        .await
        .unwrap();
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
    // The public mailbox stays reachable even while close waits under storage pressure.
    let _ = within(async { thread.snapshot() }).await;
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
    let store = Store::new();
    store.backpressure.store(true, Ordering::SeqCst);
    let (ready, mut receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "backpressure-admission".into(),
        DynModelSession::new(WaitingModel(Some(ready))),
    )
    .unwrap();
    within(thread.attach_history(HistorySinkHandle::new(Storage(store.clone()))))
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
