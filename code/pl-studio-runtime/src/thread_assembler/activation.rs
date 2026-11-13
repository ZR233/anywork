//! Owned, coalesced preparation before publishing a root or restored Thread.
use super::*;
use futures::FutureExt;
use std::future::Future;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ActivationPurpose {
    Explicit,
    VerifiedReview,
}

/// Product identity selected before allocating physical resources.
#[derive(Debug, Clone)]
pub struct ThreadActivation {
    pub agent: pl_protocol::AgentThreadIdentity,
    pub parent_thread_id: Option<pl_protocol::ThreadId>,
    pub binding: pl_protocol::AgentBinding,
}

impl ThreadActivation {
    pub fn id(&self) -> &str {
        self.agent.thread_id.as_str()
    }

    pub fn parent_id(&self) -> Option<&str> {
        self.parent_thread_id
            .as_ref()
            .map(pl_protocol::ThreadId::as_str)
    }

    pub(super) fn ensure_native(&self) -> Result<(), ThreadAssemblyError> {
        match &self.binding {
            pl_protocol::AgentBinding::Native(_) => Ok(()),
            pl_protocol::AgentBinding::Acp(_) => Err(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Acp,
            }),
        }
    }

    #[cfg(test)]
    pub(crate) fn native_test(id: &str, parent_id: Option<&str>) -> Self {
        Self {
            agent: pl_protocol::AgentThreadIdentity {
                session_id: pl_protocol::SessionId::new("test-session")
                    .expect("valid test session"),
                agent_id: pl_protocol::AgentId::new(id).expect("valid test agent"),
                parent_agent_id: parent_id
                    .map(pl_protocol::AgentId::new)
                    .transpose()
                    .expect("valid test parent agent"),
                thread_id: pl_protocol::ThreadId::new(id).expect("valid test Thread"),
            },
            parent_thread_id: parent_id
                .map(pl_protocol::ThreadId::new)
                .transpose()
                .expect("valid test parent Thread"),
            binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                route: None,
                system_instructions: None,
            }),
        }
    }
}

/// Preparation cancellation belongs to the assembler, independently of individual waiting clients.
#[derive(Debug)]
pub struct ThreadPreparation {
    pub workspace_owner: super::WorkspacePreparationOwner,
    pub identity: ThreadActivation,
    pub cancellation: tokio_util::sync::CancellationToken,
    /// Preflighted collaboration registrations; no physical tool allocation has started yet.
    pub agent_controls: Vec<Registration>,
    /// Root-only strategy read from canonical saved/newly admitted facts before tool preflight.
    pub delegation: Option<pl_protocol::DelegationSettings>,
}

/// Resolves an existing product task into fresh model/tool resources and saved facts.
pub trait StudioActivationFactory: std::fmt::Debug + Send + Sync + 'static {
    /// Resolves a root's frozen strategy before allocating physical tools or workspace resources.
    /// Must not inherit current global defaults for an existing Thread.
    fn root_delegation(
        &self,
        identity: &ThreadActivation,
    ) -> impl Future<Output = Result<pl_protocol::DelegationSettings, ThreadAssemblyError>> + Send;

    /// Owns cleanup of allocations when preparation fails before returning a spec.
    /// Must honor cancellation and must not execute restored model calls or tool effects.
    fn prepare(
        &self,
        request: ThreadPreparation,
    ) -> impl Future<Output = Result<StudioThreadSpec, ThreadAssemblyError>> + Send;
}

impl SessionRuntime {
    /// Coalesces concurrent activation and owns preparation even if a waiting client disconnects.
    ///
    /// # Errors
    /// Rejects mismatched parent identities, closing owners, failed resources and corrupt history.
    pub async fn activate(
        &self,
        identity: ThreadActivation,
        factory: impl StudioActivationFactory,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        self.activate_owned(identity, factory, None).await
    }

    pub(crate) async fn activate_verified_review(
        &self,
        identity: ThreadActivation,
        factory: crate::studio::StudioThreadFactory,
        proof: crate::studio::thread_factory::VerifiedLocalResume,
        operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        self.activate_owned(
            identity,
            factory,
            Some((
                super::WorkspacePreparationOwner::verified_review(proof),
                operation,
            )),
        )
        .await
    }

    async fn activate_owned(
        &self,
        identity: ThreadActivation,
        factory: impl StudioActivationFactory,
        restricted: Option<(
            super::WorkspacePreparationOwner,
            tokio::sync::OwnedMutexGuard<()>,
        )>,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        identity.ensure_native()?;
        if &identity.agent.session_id != self.id() {
            return Err(ThreadAssemblyError::Identity(identity.id().to_owned()));
        }
        let is_restricted = restricted.is_some();
        let purpose = if is_restricted {
            ActivationPurpose::VerifiedReview
        } else {
            ActivationPurpose::Explicit
        };
        // A retained failed owner can carry the entire cleanup/settlement future.
        // Isolate that retry before composing the new activation's admission state.
        Box::pin(self.close_failed_preparation(identity.id())).await?;
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let waiting = {
                let state = self.0.state();
                if state.closing {
                    return Err(ThreadAssemblyError::Closed);
                }
                if let Some(entry) = state.entries.get(identity.id()) {
                    if is_restricted {
                        return Err(ThreadAssemblyError::Preparing(identity.id().to_owned()));
                    }
                    if entry.native()?.parent_id.as_deref() != identity.parent_id()
                        || entry.identity != identity.agent
                        || entry.binding != identity.binding
                    {
                        return Err(ThreadAssemblyError::Identity(identity.id().to_owned()));
                    }
                    if entry.native()?.purpose != super::EntryPurpose::ReportReceiver
                        && entry.native()?.ready
                        && entry.native()?.thread.snapshot().lifecycle == ThreadLifecycle::Open
                    {
                        return Ok(entry.native()?.thread.clone());
                    }
                    if entry.native()?.purpose != super::EntryPurpose::ReportReceiver
                        && !state.creating.contains_key(identity.id())
                    {
                        return Err(ThreadAssemblyError::Unpublished(identity.id().to_owned()));
                    }
                }
                let preparation = match state.creating.get(identity.id()) {
                    Some(preparation)
                        if is_restricted
                            || preparation.purpose.is_some_and(|mode| mode != purpose) =>
                    {
                        return Err(ThreadAssemblyError::Preparing(identity.id().to_owned()));
                    }
                    Some(preparation)
                        if preparation.parent_id.as_deref() == identity.parent_id() =>
                    {
                        Some(preparation.result.clone())
                    }
                    Some(_) => return Err(ThreadAssemblyError::Identity(identity.id().to_owned())),
                    None => None,
                };
                (
                    state.entries.get(identity.id()).is_some_and(|entry| {
                        entry.native().is_ok_and(|native| {
                            native.purpose == super::EntryPurpose::ReportReceiver
                        })
                    }),
                    preparation,
                )
            };
            if waiting.0 {
                // Receiver cleanup retains storage/transport state. Do not inline it beside
                // the activation reservation and restricted workspace proof in this waiter.
                Box::pin(self.finish_report_receiver(identity.id())).await?;
                continue;
            }
            match waiting.1 {
                Some(Some(result)) => return await_result(result).await,
                Some(None) => {
                    changed.await;
                    continue;
                }
                None => {}
            }
            let reservation = match self.reserve(identity.id(), identity.parent_id()) {
                Ok(reservation) => reservation,
                Err(ThreadAssemblyError::Identity(_))
                    if {
                        let state = self.0.state();
                        state.creating.contains_key(identity.id())
                            || state.entries.contains_key(identity.id())
                    } =>
                {
                    continue;
                }
                Err(error) => return Err(error),
            };
            let (publication, result) = tokio::sync::watch::channel(None);
            let cancellation = {
                let mut state = self.0.state();
                let preparation = state
                    .creating
                    .get_mut(identity.id())
                    .ok_or(ThreadAssemblyError::Closed)?;
                preparation.result = Some(result.clone());
                preparation.purpose = Some(purpose);
                preparation.cancellation.clone()
            };
            self.0.changed.notify_waiters();
            let owner = self.clone();
            tokio::spawn(async move {
                let (workspace_owner, operation) = match restricted {
                    Some((workspace, operation)) => (workspace, Some(operation)),
                    None => (super::WorkspacePreparationOwner::default(), None),
                };
                let operation = std::panic::AssertUnwindSafe(async {
                    let _operation = match operation {
                        Some(operation) => operation,
                        None => owner.agent_operation(identity.id()).await,
                    };
                    if owner.0.state().sealed_agents.contains_key(identity.id()) {
                        return Err(ThreadAssemblyError::Closed);
                    }
                    let delegation = if identity.agent.parent_agent_id.is_none() {
                        Some(factory.root_delegation(&identity).await?)
                    } else {
                        None
                    };
                    let agent_controls = match delegation {
                        Some(selection) => {
                            let profiles = owner.agent_profiles_snapshot()?;
                            let resources = owner
                                .0
                                .state()
                                .creating
                                .get(identity.id())
                                .ok_or(ThreadAssemblyError::Closed)?
                                .resources
                                .require_native()?
                                .clone();
                            owner.agent_control_tools(
                                &identity.agent,
                                &resources,
                                &profiles,
                                selection,
                            )?
                        }
                        None => Vec::new(),
                    };
                    let resources = owner
                        .0
                        .state()
                        .creating
                        .get(identity.id())
                        .expect("reserved preparation")
                        .resources
                        .require_native()?
                        .clone();
                    workspace_owner.bind_native_resources(resources);
                    workspace_owner.bind_admission(&owner, identity.id(), &cancellation)?;
                    let spec = factory
                        .prepare(ThreadPreparation {
                            workspace_owner: workspace_owner.clone(),
                            identity: identity.clone(),
                            cancellation: cancellation.clone(),
                            agent_controls,
                            delegation,
                        })
                        .await?;
                    if spec.id.as_str() != identity.id()
                        || spec.parent_id.as_deref() != identity.parent_id()
                    {
                        return Err(ThreadAssemblyError::Identity(spec.id));
                    }
                    if let Some(selection) = delegation
                        && spec.frozen_delegation()? != selection
                    {
                        return Err(ThreadAssemblyError::Identity(
                            "prepared root delegation differs from its preflight".into(),
                        ));
                    }
                    if cancellation.is_cancelled() {
                        return Err(ThreadAssemblyError::Closed);
                    }
                    owner
                        .0
                        .state()
                        .pending_activation
                        .insert(identity.id().to_owned(), identity.clone());
                    let assembled = owner.assemble_reserved(spec, &reservation).await;
                    owner.0.state().pending_activation.remove(identity.id());
                    assembled
                })
                .catch_unwind()
                .await;
                let mut outcome = operation.unwrap_or(Err(ThreadAssemblyError::ActivationPanicked));
                if outcome.is_err() {
                    let cancellation = {
                        let mut state = owner.0.state();
                        let preparation = state
                            .creating
                            .get_mut(identity.id())
                            .expect("settlement retains its original preparation");
                        preparation.settlement = Some(workspace_owner.clone());
                        preparation.cancellation.clone()
                    };
                    cancellation.cancel();
                    let settlement = std::panic::AssertUnwindSafe(
                        owner.settle_failed_activation(identity.id(), &workspace_owner),
                    )
                    .catch_unwind()
                    .await
                    .unwrap_or(Err(ThreadAssemblyError::ActivationPanicked));
                    match settlement {
                        Ok(()) => {
                            owner
                                .0
                                .state()
                                .creating
                                .get_mut(identity.id())
                                .expect("settlement retains its original preparation")
                                .settlement = None;
                        }
                        Err(cleanup) => {
                            outcome = Err(ThreadAssemblyError::Cleanup {
                                id: identity.id().to_owned(),
                                setup: Box::new(outcome.err().unwrap()),
                                cleanup: Box::new(cleanup),
                            });
                        }
                    }
                }
                // No async cleanup remains after releasing preparation admission.
                drop(reservation);
                publication.send_replace(Some(outcome.map_err(Arc::new)));
            });
            return await_result(result).await;
        }
    }
}

async fn await_result(
    mut result: tokio::sync::watch::Receiver<Option<ActivationOutcome>>,
) -> Result<ThreadHandle, ThreadAssemblyError> {
    loop {
        if let Some(outcome) = result.borrow_and_update().clone() {
            return outcome.map_err(ThreadAssemblyError::ActivationFailed);
        }
        result
            .changed()
            .await
            .map_err(|_| ThreadAssemblyError::Closed)?;
    }
}

#[cfg(test)]
mod backend_tests {
    use super::*;
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    #[derive(Debug, Clone)]
    struct CountingFactory {
        delegation_reads: Arc<AtomicUsize>,
        preparations: Arc<AtomicUsize>,
    }

    impl StudioActivationFactory for CountingFactory {
        async fn root_delegation(
            &self,
            identity: &ThreadActivation,
        ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
            self.delegation_reads.fetch_add(1, Ordering::SeqCst);
            Err(ThreadAssemblyError::Identity(identity.id().to_owned()))
        }

        async fn prepare(
            &self,
            request: ThreadPreparation,
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            self.preparations.fetch_add(1, Ordering::SeqCst);
            Err(ThreadAssemblyError::Identity(
                request.identity.id().to_owned(),
            ))
        }
    }

    #[tokio::test]
    async fn acp_is_rejected_before_factory_work_or_reservation() {
        let owner = SessionRuntime::default();
        let delegation_reads = Arc::new(AtomicUsize::new(0));
        let preparations = Arc::new(AtomicUsize::new(0));
        let factory = CountingFactory {
            delegation_reads: delegation_reads.clone(),
            preparations: preparations.clone(),
        };
        let mut identity = ThreadActivation::native_test("acp-root", None);
        identity.binding = pl_protocol::AgentBinding::Acp(pl_protocol::AcpAgentConfig {
            account_id: "acp-account".into(),
        });

        assert!(matches!(
            owner.activate(identity, factory.clone()).await,
            Err(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Acp
            })
        ));
        assert_eq!(delegation_reads.load(Ordering::SeqCst), 0);
        assert_eq!(preparations.load(Ordering::SeqCst), 0);

        // Reusing the same Thread identity must reach preflight, proving ACP rejection did not
        // leave an assembler reservation or private preparation owner behind.
        assert!(
            owner
                .activate(ThreadActivation::native_test("acp-root", None), factory)
                .await
                .is_err()
        );
        assert_eq!(delegation_reads.load(Ordering::SeqCst), 1);
        assert_eq!(preparations.load(Ordering::SeqCst), 0);

        let child_owner = SessionRuntime::default();
        let child_delegation_reads = Arc::new(AtomicUsize::new(0));
        let child_preparations = Arc::new(AtomicUsize::new(0));
        let child_factory = CountingFactory {
            delegation_reads: child_delegation_reads.clone(),
            preparations: child_preparations.clone(),
        };
        let mut child = ThreadActivation::native_test("acp-child", Some("native-parent"));
        child.binding = pl_protocol::AgentBinding::Acp(pl_protocol::AcpAgentConfig {
            account_id: "acp-account".into(),
        });
        assert!(matches!(
            child_owner.activate(child, child_factory.clone()).await,
            Err(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Acp
            })
        ));
        assert_eq!(child_delegation_reads.load(Ordering::SeqCst), 0);
        assert_eq!(child_preparations.load(Ordering::SeqCst), 0);
        let state = child_owner.0.state();
        assert!(!state.creating.contains_key("acp-child"));
        assert!(!state.entries.contains_key("acp-child"));
    }
}
