//! Incremental S2 regressions for preparation settlement and Session cancellation ordering.
use super::*;
use crate::session::{AgentInstance, NativeResources, NativeThreadRuntime, SessionPhase};
use pl_core::{
    context::ContextContent,
    model::{DynModelSession, ModelError, ModelRequest, ModelSession, PreparedModelCall},
    thread::{
        ModelStepLimit, ThreadLifecycle, TurnInput,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
    },
};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use tokio::sync::{Semaphore, oneshot};
use tokio_util::sync::CancellationToken;

#[derive(Debug)]
pub(super) struct SettlementProbe {
    id: String,
    barrier: tokio::sync::Mutex<Option<(oneshot::Sender<()>, oneshot::Receiver<()>)>>,
    fail: AtomicBool,
    attempts: AtomicUsize,
}

#[derive(Debug)]
pub(super) struct FailedRetryProbe {
    id: String,
    captured: oneshot::Sender<()>,
    resume: oneshot::Receiver<()>,
}

impl SessionRuntime {
    pub(crate) fn s2_has_failed_preparation(&self, id: &str) -> bool {
        self.0.state().failed_preparations.contains_key(id)
    }

    pub(super) async fn s2_failed_retry_checkpoint(&self, id: &str) {
        let probe = {
            let mut state = self.0.state();
            if state
                .s2_failed_retry_probe
                .as_ref()
                .is_some_and(|probe| probe.id == id)
            {
                state.s2_failed_retry_probe.take()
            } else {
                None
            }
        };
        if let Some(probe) = probe {
            let _ = probe.captured.send(());
            probe.resume.await.unwrap();
        }
    }

    pub(super) async fn s2_activation_settlement_checkpoint(
        &self,
        id: &str,
    ) -> Result<(), ThreadAssemblyError> {
        let probe = self.0.state().s2_settlement_probe.clone();
        let Some(probe) = probe.filter(|probe| probe.id == id) else {
            return Ok(());
        };
        probe.attempts.fetch_add(1, Ordering::SeqCst);
        let barrier = probe.barrier.lock().await.take();
        if let Some((entered, release)) = barrier {
            let _ = entered.send(());
            release.await.expect("test retains the settlement release");
        }
        if probe.fail.load(Ordering::SeqCst) {
            return Err(ThreadAssemblyError::Resource {
                operation: "settle original activation preparation",
                source: Box::new(std::io::Error::other("injected settlement failure")),
            });
        }
        Ok(())
    }
}

#[derive(Debug)]
struct RefusedFactory {
    panic: bool,
}
impl StudioActivationFactory for RefusedFactory {
    async fn root_delegation(
        &self,
        _: &ThreadActivation,
    ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
        assert!(!self.panic, "factory unwind before resource publication");
        Err(ThreadAssemblyError::Identity(
            "factory refused preparation".into(),
        ))
    }
    async fn prepare(&self, _: ThreadPreparation) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        unreachable!("root delegation refuses before resource preparation")
    }
}

async fn settlement_blocks_close(panic: bool) {
    let owner = SessionRuntime::default();
    let (entered, paused) = oneshot::channel();
    let (release, resume) = oneshot::channel();
    let probe = Arc::new(SettlementProbe {
        id: "settling-root".into(),
        barrier: tokio::sync::Mutex::new(Some((entered, resume))),
        fail: AtomicBool::new(false),
        attempts: AtomicUsize::new(0),
    });
    owner.0.state().s2_settlement_probe = Some(probe);
    let activation = {
        let owner = owner.clone();
        tokio::spawn(async move {
            owner
                .activate(
                    ThreadActivation::native_test("settling-root", None),
                    RefusedFactory { panic },
                )
                .await
        })
    };
    paused.await.unwrap();
    // A failed assembly can already own a concrete core. Settlement must close it while
    // retaining its preparation registration, without waiting on that same registration.
    register_member(
        &owner,
        "settling-root",
        None,
        ThreadHandle::resume_without_model("settling-root".into(), None).unwrap(),
    );
    assert!(
        owner.0.state().creating["settling-root"]
            .settlement
            .is_some()
    );
    let (broadcast, observed) = oneshot::channel();
    owner.0.state().s2_close_broadcast = Some(broadcast);
    let close = owner.close_session();
    tokio::pin!(close);
    tokio::select! {
        result = &mut close => panic!("close escaped retained settlement: {result:?}"),
        result = observed => result.unwrap(),
    }
    assert_eq!(owner.phase(), SessionPhase::Closing);
    assert!(futures::poll!(&mut close).is_pending());
    release.send(()).unwrap();
    assert!(activation.await.unwrap().is_err());
    let report = close.await;
    assert!(report.is_empty(), "{report:?}");
    assert_eq!(owner.phase(), SessionPhase::Closed);
    assert!(owner.0.state().creating.is_empty());
    assert!(owner.0.state().failed_preparations.is_empty());
}

#[tokio::test]
async fn s2_close_waits_for_original_failed_activation_settlement() {
    tokio::time::timeout(
        std::time::Duration::from_secs(5),
        settlement_blocks_close(false),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn s2_close_waits_for_original_panicked_factory_settlement() {
    tokio::time::timeout(
        std::time::Duration::from_secs(5),
        settlement_blocks_close(true),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn s2_failed_settlement_survives_empty_native_resources_and_retries() {
    let owner = SessionRuntime::default();
    let probe = Arc::new(SettlementProbe {
        id: "failed-settlement".into(),
        barrier: Default::default(),
        fail: AtomicBool::new(true),
        attempts: AtomicUsize::new(0),
    });
    owner.0.state().s2_settlement_probe = Some(probe.clone());
    assert!(
        owner
            .activate(
                ThreadActivation::native_test(&probe.id, None),
                RefusedFactory { panic: false }
            )
            .await
            .is_err()
    );
    {
        let state = owner.0.state();
        let failed = &state.failed_preparations[&probe.id];
        assert!(failed.settlement.is_some());
        assert!(
            !failed.resources.has_obligations(),
            "settlement must not depend on Native resource occupancy"
        );
    }
    let failed = owner.close_session().await;
    assert!(!failed.is_empty());
    assert_eq!(owner.phase(), SessionPhase::Closing);
    assert!(owner.0.state().failed_preparations.contains_key(&probe.id));
    probe.fail.store(false, Ordering::SeqCst);
    assert!(owner.close_session().await.is_empty());
    assert!(probe.attempts.load(Ordering::SeqCst) >= 3);
    assert!(owner.0.state().failed_preparations.is_empty());
    assert_eq!(owner.phase(), SessionPhase::Closed);
}

struct WaitingModel {
    started: Option<oneshot::Sender<CancellationToken>>,
}

#[tokio::test]
async fn s2_stale_failed_retry_cannot_close_replacement_owner() {
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        let owner = SessionRuntime::default();
        let id = "retry-incarnation";
        let probe = Arc::new(SettlementProbe {
            id: id.into(),
            barrier: Default::default(),
            fail: AtomicBool::new(true),
            attempts: AtomicUsize::new(0),
        });
        owner.0.state().s2_settlement_probe = Some(probe.clone());
        let mut activation = ThreadActivation::native_test(id, None);
        activation.agent.agent_id = pl_protocol::AgentId::new(format!("agent-{id}")).unwrap();
        assert!(
            owner
                .activate(activation, RefusedFactory { panic: false })
                .await
                .is_err()
        );
        assert!(owner.s2_has_failed_preparation(id));
        let old = owner.0.state().failed_preparations[id].clone();
        probe.fail.store(false, Ordering::SeqCst);
        let (entered, paused) = oneshot::channel();
        let (release, resume) = oneshot::channel();
        *probe.barrier.lock().await = Some((entered, resume));
        let first = {
            let owner = owner.clone();
            tokio::spawn(async move { owner.close_failed_preparation(id).await })
        };
        paused.await.unwrap();
        assert!(
            owner.reserve(id, None).is_err(),
            "qualified cleanup must block reuse"
        );
        let (captured, capture) = oneshot::channel();
        let (resume, paused) = oneshot::channel();
        owner.0.state().s2_failed_retry_probe = Some(FailedRetryProbe {
            id: id.into(),
            captured,
            resume: paused,
        });
        let stale = {
            let owner = owner.clone();
            tokio::spawn(async move { owner.close_failed_preparation(id).await })
        };
        capture.await.unwrap();
        assert!(Arc::ptr_eq(&old, &owner.0.state().failed_preparations[id]));
        release.send(()).unwrap();
        first.await.unwrap().unwrap();
        assert!(!owner.s2_has_failed_preparation(id));
        let (started, running) = oneshot::channel();
        let thread = ThreadHandle::start(
            id.into(),
            DynModelSession::new(WaitingModel {
                started: Some(started),
            }),
        )
        .unwrap();
        register_member(&owner, id, None, thread.clone());
        let turn = start_turn(thread.clone());
        let cancellation = running.await.unwrap();
        let attempts = probe.attempts.load(Ordering::SeqCst);
        resume.send(()).unwrap();
        stale.await.unwrap().unwrap();
        assert_eq!(probe.attempts.load(Ordering::SeqCst), attempts);
        assert!(
            owner.0.state().entries[id]
                .native()
                .unwrap()
                .thread
                .same_instance(&thread)
        );
        assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Open);
        assert!(!cancellation.is_cancelled());
        assert!(owner.close_session().await.is_empty());
        let _ = turn.await.unwrap();
    })
    .await
    .unwrap();
}
impl ModelSession for WaitingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        if let Some(started) = self.started.take() {
            let _ = started.send(request.cancellation.clone());
        }
        Ok(PreparedModelCall::new(async move {
            request.cancellation.cancelled().await;
            Err(ModelError {
                details: None,
                kind: pl_core::model::ModelFailureKind::Cancelled,
                usage: Default::default(),
                source: None,
            })
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[derive(Debug, Clone)]
struct GatedFinalSave {
    closing: Arc<AtomicBool>,
    entered: Arc<Mutex<Option<oneshot::Sender<()>>>>,
    release: Arc<Semaphore>,
}
impl ColdStore for GatedFinalSave {
    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure::default()
    }
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if write.checkpoint.state.lifecycle == ThreadLifecycle::Closed {
            self.closing.store(true, Ordering::SeqCst);
        }
        Ok(())
    }
    async fn flush(&self, _: &str, _: u64) -> Result<(), ColdStoreError> {
        if self.closing.load(Ordering::SeqCst) {
            if let Some(entered) = self.entered.lock().unwrap().take() {
                let _ = entered.send(());
            }
            self.release.acquire().await.unwrap().forget();
        }
        Ok(())
    }
}

fn register_member(owner: &SessionRuntime, id: &str, parent: Option<&str>, thread: ThreadHandle) {
    owner.0.state().insert_entry(
        id.into(),
        AgentInstance {
            identity: pl_protocol::AgentThreadIdentity {
                session_id: owner.id().clone(),
                agent_id: pl_protocol::AgentId::new(format!("agent-{id}")).unwrap(),
                parent_agent_id: parent
                    .map(|id| pl_protocol::AgentId::new(format!("agent-{id}")).unwrap()),
                thread_id: pl_protocol::ThreadId::new(id).unwrap(),
            },
            binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                route: None,
                system_instructions: None,
            }),
            runtime: crate::session::AgentRuntime::Native(Box::new(NativeThreadRuntime {
                resources: Arc::new(NativeResources::default()),
                purpose: EntryPurpose::Execution,
                workspace_usage: None,
                close_storage: None,
                published_resources_closed: false,
                workspace_disposition: None,
                cleanup: Default::default(),
                execution: pl_core::thread::input::InputDriverOptions {
                    max_model_steps: ModelStepLimit::Unlimited,
                },
                incarnation: Arc::new(()),
                parent_id: parent.map(str::to_owned),
                ready: true,
                thread,
            })),
        },
    );
}

fn start_turn(
    thread: ThreadHandle,
) -> tokio::task::JoinHandle<Result<pl_core::thread::TurnCompletion, ThreadError>> {
    tokio::spawn(async move {
        thread
            .run_turn(TurnInput {
                turn_id: "running-turn".into(),
                attempt_prefix: "waiting-model".into(),
                content: vec![ContextContent::Text {
                    text: "run until cancelled".into(),
                }],
                max_model_steps: ModelStepLimit::Unlimited,
                cancellation: CancellationToken::new(),
            })
            .await
    })
}

#[tokio::test]
async fn s2_close_cancels_parent_before_blocked_child_and_preserves_other_session() {
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        let owner = SessionRuntime::open(pl_protocol::SessionId::new("session-a").unwrap());
        let other = SessionRuntime::open(pl_protocol::SessionId::new("session-b").unwrap());
        let (started, model_started) = oneshot::channel();
        let parent = ThreadHandle::start(
            "parent-thread".into(),
            DynModelSession::new(WaitingModel {
                started: Some(started),
            }),
        )
        .unwrap();
        register_member(&owner, "parent-thread", None, parent.clone());
        let parent_run = start_turn(parent.clone());
        let parent_cancel = model_started.await.unwrap();
        let (started, model_started) = oneshot::channel();
        let unrelated = ThreadHandle::start(
            "unrelated-thread".into(),
            DynModelSession::new(WaitingModel {
                started: Some(started),
            }),
        )
        .unwrap();
        register_member(&other, "unrelated-thread", None, unrelated.clone());
        let unrelated_run = start_turn(unrelated);
        let unrelated_cancel = model_started.await.unwrap();
        let child = ThreadHandle::resume_without_model("child-thread".into(), None).unwrap();
        let (entered, child_waiting) = oneshot::channel();
        let store = GatedFinalSave {
            closing: Arc::new(AtomicBool::new(false)),
            entered: Arc::new(Mutex::new(Some(entered))),
            release: Arc::new(Semaphore::new(0)),
        };
        child
            .attach_storage(ColdStoreHandle::new(store.clone()))
            .await
            .unwrap();
        register_member(&owner, "child-thread", Some("parent-thread"), child);
        let close = owner.close_session();
        tokio::pin!(close);
        tokio::select! {
            result = &mut close => panic!("child save barrier was skipped: {result:?}"),
            result = child_waiting => result.unwrap(),
        }
        assert!(
            parent_cancel.is_cancelled(),
            "parent execution must be cancelled before waiting for child save"
        );
        assert!(
            !unrelated_cancel.is_cancelled(),
            "Session A cannot cancel Session B"
        );
        assert!(futures::poll!(&mut close).is_pending());
        store.release.add_permits(8);
        let report = close.await;
        assert!(report.is_empty(), "{report:?}");
        assert!(parent_run.await.unwrap().is_err());
        assert!(!unrelated_cancel.is_cancelled());
        assert!(other.close_session().await.is_empty());
        assert!(unrelated_run.await.unwrap().is_err());
    })
    .await
    .unwrap();
}
