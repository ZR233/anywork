//! Preparation settlement and session cancellation ordering.
use super::*;
use crate::session::{AgentInstance, NativeResources, NativeThreadRuntime, SessionPhase};
use pl_core::{
    context::ContextContent,
    model::{DynModelSession, ModelError, ModelRequest, ModelSession, PreparedModelCall},
    thread::{ModelStepLimit, ThreadLifecycle, TurnInput},
};
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

impl SessionRuntime {
    pub(crate) fn s2_has_failed_preparation(&self, id: &str) -> bool {
        self.0
            .state()
            .activation
            .failed_preparations
            .contains_key(id)
    }
}

/// Controls the actual observation-close obligation, not the settlement algorithm.
#[derive(Debug)]
struct CloseControl {
    id: String,
    barrier: tokio::sync::Mutex<Option<(oneshot::Sender<()>, oneshot::Receiver<()>)>>,
    fail: AtomicBool,
}
impl CloseControl {
    fn install(owner: &SessionRuntime, id: &str, fail: bool) -> Arc<Self> {
        let control = Arc::new(Self {
            id: id.into(),
            barrier: Default::default(),
            fail: AtomicBool::new(fail),
        });
        let close = control.clone();
        owner
            .observe_assembly(
                |_, _, _| {},
                |_, _| Box::pin(async { Ok(()) }),
                None,
                move |id, _, _| {
                    let close = close.clone();
                    Box::pin(async move {
                        if id != close.id {
                            return Ok(());
                        }
                        if let Some((entered, release)) = close.barrier.lock().await.take() {
                            let _ = entered.send(());
                            release.await.expect("test retains the observation release");
                        }
                        if close.fail.load(Ordering::SeqCst) {
                            return Err(ThreadAssemblyError::Resource {
                                operation: "close member observation",
                                source: Box::new(std::io::Error::other(
                                    "controlled observation close failure",
                                )),
                            });
                        }
                        Ok(())
                    })
                },
                |_| Box::pin(async { Ok(()) }),
            )
            .unwrap();
        control
    }
    async fn pause(&self) -> (oneshot::Receiver<()>, oneshot::Sender<()>) {
        let (entered, paused) = oneshot::channel();
        let (release, resume) = oneshot::channel();
        *self.barrier.lock().await = Some((entered, resume));
        (paused, release)
    }
}

#[derive(Debug)]
struct RefusedFactory {
    owner: SessionRuntime,
    panic: bool,
}
impl StudioActivationFactory for RefusedFactory {
    async fn prepare_root(
        &self,
        identity: &ThreadActivation,
    ) -> Result<(crate::DelegationSettings, Option<ThreadCurrent>), ThreadAssemblyError> {
        register_member(
            &self.owner,
            identity.id(),
            None,
            ThreadHandle::start_current(identity.id().into(), None).unwrap(),
        );
        {
            let mut state = self.owner.0.state();
            let mut entry = state.members.remove_entry(identity.id()).unwrap();
            entry.identity = identity.agent.clone();
            entry.native_mut()?.ready = false;
            state.members.insert_entry(identity.id().into(), entry);
        }
        assert!(
            !self.panic,
            "factory unwind after taking ownership of an unpublished core"
        );
        Err(ThreadAssemblyError::Identity(
            "factory refused preparation".into(),
        ))
    }
    async fn prepare(&self, _: ThreadPreparation) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        unreachable!("root delegation refuses before physical tool preparation")
    }
}

async fn settlement_blocks_close(panic: bool) {
    let owner = SessionRuntime::default();
    let control = CloseControl::install(&owner, "settling-root", false);
    let (paused, release) = control.pause().await;
    let activation = {
        let owner = owner.clone();
        tokio::spawn(async move {
            owner
                .activate(
                    ThreadActivation::native_test("settling-root", None),
                    RefusedFactory {
                        owner: owner.clone(),
                        panic,
                    },
                )
                .await
        })
    };
    paused.await.unwrap();
    assert!(
        owner.0.state().activation.creating["settling-root"]
            .settlement
            .is_some()
    );
    let (started, running) = oneshot::channel();
    let witness = ThreadHandle::start(
        "broadcast-witness".into(),
        DynModelSession::new(WaitingModel {
            started: Some(started),
        }),
    )
    .unwrap();
    register_member(&owner, "broadcast-witness", None, witness.clone());
    let witness_turn = start_turn(witness);
    let cancellation = running.await.unwrap();
    let close = owner.close_session();
    tokio::pin!(close);
    tokio::select! {
        result = &mut close => panic!("close escaped retained settlement: {result:?}"),
        () = cancellation.cancelled() => {},
    }
    assert_eq!(owner.phase(), SessionPhase::Closing);
    assert!(futures::poll!(&mut close).is_pending());
    release.send(()).unwrap();
    assert!(activation.await.unwrap().is_err());
    let report = close.await;
    assert!(report.is_empty(), "{report:?}");
    assert!(witness_turn.await.unwrap().is_err());
    assert_eq!(owner.phase(), SessionPhase::Closed);
    assert!(owner.0.state().activation.creating.is_empty());
    assert!(owner.0.state().activation.failed_preparations.is_empty());
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
    let id = "failed-settlement";
    let control = CloseControl::install(&owner, id, true);
    assert!(
        owner
            .activate(
                ThreadActivation::native_test(id, None),
                RefusedFactory {
                    owner: owner.clone(),
                    panic: false
                }
            )
            .await
            .is_err()
    );
    let core = owner
        .observed_thread(id)
        .expect("failed close retains the original core");
    {
        let state = owner.0.state();
        let failed = &state.activation.failed_preparations[id];
        assert!(failed.settlement.is_some());
        assert!(
            !failed.resources.has_obligations(),
            "settlement must not depend on Native resource occupancy"
        );
    }
    let failed = owner.close_session().await;
    assert!(!failed.is_empty());
    assert_eq!(owner.phase(), SessionPhase::Closing);
    assert!(owner.s2_has_failed_preparation(id));
    assert_ne!(core.snapshot().lifecycle, ThreadLifecycle::Closed);
    control.fail.store(false, Ordering::SeqCst);
    assert!(owner.close_session().await.is_empty());
    assert_eq!(core.snapshot().lifecycle, ThreadLifecycle::Closed);
    assert!(owner.0.state().activation.failed_preparations.is_empty());
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
        let control = CloseControl::install(&owner, id, true);
        let mut activation = ThreadActivation::native_test(id, None);
        activation.agent.agent_id = crate::AgentId::new(format!("agent-{id}")).unwrap();
        assert!(
            owner
                .activate(
                    activation,
                    RefusedFactory {
                        owner: owner.clone(),
                        panic: false
                    }
                )
                .await
                .is_err()
        );
        let old = owner.0.state().activation.failed_preparations[id].clone();
        let old_core = owner.observed_thread(id).unwrap();
        control.fail.store(false, Ordering::SeqCst);
        let (paused, release) = control.pause().await;
        let first = {
            let owner = owner.clone();
            tokio::spawn(async move { owner.close_failed_preparation(id).await })
        };
        paused.await.unwrap();
        assert!(
            owner.reserve(id, None).is_err(),
            "qualified cleanup must block reuse"
        );
        assert!(Arc::ptr_eq(
            &old,
            &owner.0.state().activation.failed_preparations[id]
        ));
        release.send(()).unwrap();
        first.await.unwrap().unwrap();
        assert!(!owner.s2_has_failed_preparation(id));
        assert_eq!(old_core.snapshot().lifecycle, ThreadLifecycle::Closed);
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
        // The retained phase can resume after lookup even when a later cleanup has retired it.
        owner
            .settle_retained_failed_preparation(id, old)
            .await
            .unwrap();
        assert!(
            owner.0.state().members.entries[id]
                .native()
                .unwrap()
                .thread
                .same_instance(&thread)
        );
        assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Open);
        assert!(!cancellation.is_cancelled());
        assert!(owner.close_session().await.is_empty());
        assert!(turn.await.unwrap().is_err());
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
                context_recovery: None,
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

fn register_member(owner: &SessionRuntime, id: &str, parent: Option<&str>, thread: ThreadHandle) {
    owner.0.state().members.insert_entry(
        id.into(),
        AgentInstance {
            identity: crate::AgentThreadIdentity {
                session_id: owner.id().clone(),
                agent_id: crate::AgentId::new(format!("agent-{id}")).unwrap(),
                parent_agent_id: parent
                    .map(|id| crate::AgentId::new(format!("agent-{id}")).unwrap()),
                thread_id: crate::ThreadId::new(id).unwrap(),
            },
            binding: crate::AgentBinding::Native(crate::NativeAgentConfig {
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
async fn s2_close_cancels_parent_before_child_shutdown_and_preserves_other_session() {
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        let owner = SessionRuntime::open(crate::SessionId::new("session-a").unwrap());
        let other = SessionRuntime::open(crate::SessionId::new("session-b").unwrap());
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
        let child = ThreadHandle::start_current("child-thread".into(), None).unwrap();
        register_member(&owner, "child-thread", Some("parent-thread"), child);
        let report = owner.close_session().await;
        assert!(
            parent_cancel.is_cancelled(),
            "closing Session A must cancel its parent execution"
        );
        assert!(
            !unrelated_cancel.is_cancelled(),
            "Session A cannot cancel Session B"
        );
        assert!(report.is_empty(), "{report:?}");
        assert!(parent_run.await.unwrap().is_err());
        assert!(!unrelated_cancel.is_cancelled());
        assert!(other.close_session().await.is_empty());
        assert!(unrelated_run.await.unwrap().is_err());
    })
    .await
    .unwrap();
}
