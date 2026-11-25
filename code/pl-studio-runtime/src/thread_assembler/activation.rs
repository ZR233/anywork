//! Owned, coalesced preparation before publishing a root or restored Thread.
use super::*;

#[derive(Debug, Default)]
pub(crate) struct ActivationCoordinator {
    pub(crate) creating: BTreeMap<String, Preparation>,
    pub(crate) preparing_children: BTreeMap<String, children::PreparingChild>,
    pub(crate) unpublished_children: BTreeMap<String, child_resources::UnpublishedChild>,
    pub(crate) pending_activation: BTreeMap<String, crate::thread_assembler::ThreadActivation>,
    pub(crate) failed_preparations: BTreeMap<String, Arc<FailedPreparation>>,
}

impl ActivationCoordinator {
    pub(crate) fn release_reservation(&mut self, id: &str, registered_owner: bool) {
        if let Some(preparation) = self.creating.remove(id)
            && (preparation.settlement.is_some()
                || (!registered_owner && preparation.resources.has_obligations()))
        {
            self.failed_preparations.insert(
                id.to_owned(),
                Arc::new(FailedPreparation {
                    resources: preparation.resources,
                    identity: preparation.identity,
                    settlement: preparation.settlement,
                    gate: Default::default(),
                }),
            );
        }
        self.pending_activation.remove(id);
    }
}

use futures::FutureExt;
use std::future::Future;

/// Product identity selected before allocating physical resources.
#[derive(Debug, Clone)]
pub struct ThreadActivation {
    pub agent: crate::AgentThreadIdentity,
    pub parent_thread_id: Option<crate::ThreadId>,
    pub binding: crate::AgentBinding,
}

impl ThreadActivation {
    pub fn id(&self) -> &str {
        self.agent.thread_id.as_str()
    }

    pub fn parent_id(&self) -> Option<&str> {
        self.parent_thread_id.as_ref().map(crate::ThreadId::as_str)
    }

    pub(crate) fn ensure_native(&self) -> Result<(), ThreadAssemblyError> {
        match &self.binding {
            crate::AgentBinding::Native(_) => Ok(()),
            crate::AgentBinding::Acp(_) => Err(ThreadAssemblyError::UnsupportedBackend {
                backend: crate::AgentBackendKind::Acp,
            }),
        }
    }

    #[cfg(test)]
    pub(crate) fn native_test(id: &str, parent_id: Option<&str>) -> Self {
        Self {
            agent: crate::AgentThreadIdentity {
                session_id: crate::SessionId::new("test-session").expect("valid test session"),
                agent_id: crate::AgentId::new(id).expect("valid test agent"),
                parent_agent_id: parent_id
                    .map(crate::AgentId::new)
                    .transpose()
                    .expect("valid test parent agent"),
                thread_id: crate::ThreadId::new(id).expect("valid test Thread"),
            },
            parent_thread_id: parent_id
                .map(crate::ThreadId::new)
                .transpose()
                .expect("valid test parent Thread"),
            binding: crate::AgentBinding::Native(crate::NativeAgentConfig {
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
    pub delegation: Option<crate::DelegationSettings>,
    /// The same cold document used for root tool preflight. Move it into Core on activation.
    pub root_current: Option<ThreadCurrent>,
}

/// Resolves an existing product task into fresh model/tool resources and saved facts.
pub trait StudioActivationFactory: std::fmt::Debug + Send + Sync + 'static {
    /// Reads a root's saved Current and frozen strategy before allocating physical resources.
    /// Must not inherit current global defaults for an existing Thread.
    fn prepare_root(
        &self,
        identity: &ThreadActivation,
    ) -> impl Future<
        Output = Result<(crate::DelegationSettings, Option<ThreadCurrent>), ThreadAssemblyError>,
    > + Send;

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
        identity.ensure_native()?;
        if &identity.agent.session_id != self.id() {
            return Err(ThreadAssemblyError::Identity(identity.id().to_owned()));
        }
        // A retained failed owner can carry the entire cleanup/settlement future.
        // Isolate that retry before composing the new activation's admission state.
        Box::pin(self.close_failed_preparation(identity.id())).await?;
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let waiting = {
                let state = self.0.state();
                if state.close.closing {
                    return Err(ThreadAssemblyError::Closed);
                }
                if let Some(entry) = state.members.entries.get(identity.id()) {
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
                        && !state.activation.creating.contains_key(identity.id())
                    {
                        return Err(ThreadAssemblyError::Unpublished(identity.id().to_owned()));
                    }
                }
                let preparation = match state.activation.creating.get(identity.id()) {
                    Some(preparation)
                        if preparation.parent_id.as_deref() == identity.parent_id() =>
                    {
                        Some(preparation.result.clone())
                    }
                    Some(_) => return Err(ThreadAssemblyError::Identity(identity.id().to_owned())),
                    None => None,
                };
                (
                    state
                        .members
                        .entries
                        .get(identity.id())
                        .is_some_and(|entry| {
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
                        state.activation.creating.contains_key(identity.id())
                            || state.members.entries.contains_key(identity.id())
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
                    .activation
                    .creating
                    .get_mut(identity.id())
                    .ok_or(ThreadAssemblyError::Closed)?;
                preparation.result = Some(result.clone());
                preparation.cancellation.clone()
            };
            self.0.changed.notify_waiters();
            let owner = self.clone();
            tokio::spawn(async move {
                let workspace_owner = super::WorkspacePreparationOwner::default();
                let operation = std::panic::AssertUnwindSafe(async {
                    let _operation = owner.agent_operation(identity.id()).await;
                    if owner
                        .0
                        .state()
                        .close
                        .sealed_agents
                        .contains_key(identity.id())
                    {
                        return Err(ThreadAssemblyError::Closed);
                    }
                    let (delegation, root_current) = if identity.agent.parent_agent_id.is_none() {
                        let (delegation, current) = factory.prepare_root(&identity).await?;
                        (Some(delegation), current)
                    } else {
                        (None, None)
                    };
                    let resources = owner
                        .0
                        .state()
                        .activation
                        .creating
                        .get(identity.id())
                        .ok_or(ThreadAssemblyError::Closed)?
                        .resources
                        .require_native()?
                        .clone();
                    let agent_controls = match delegation {
                        Some(selection) => {
                            let profiles = owner.agent_profiles_snapshot()?;
                            owner.agent_control_tools(
                                &identity.agent,
                                &resources,
                                &profiles,
                                selection,
                            )?
                        }
                        None => Vec::new(),
                    };
                    workspace_owner.bind_native_resources(resources);
                    workspace_owner.bind_admission(&owner, identity.id(), &cancellation)?;
                    let spec = factory
                        .prepare(ThreadPreparation {
                            workspace_owner: workspace_owner.clone(),
                            identity: identity.clone(),
                            cancellation: cancellation.clone(),
                            agent_controls,
                            delegation,
                            root_current,
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
                        .activation
                        .pending_activation
                        .insert(identity.id().to_owned(), identity.clone());
                    let assembled = owner.assemble_reserved(spec, &reservation).await;
                    owner
                        .0
                        .state()
                        .activation
                        .pending_activation
                        .remove(identity.id());
                    assembled
                })
                .catch_unwind()
                .await;
                let mut outcome = operation.unwrap_or(Err(ThreadAssemblyError::ActivationPanicked));
                if outcome.is_err() {
                    let cancellation = {
                        let mut state = owner.0.state();
                        let preparation = state
                            .activation
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
                                .activation
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
        async fn prepare_root(
            &self,
            identity: &ThreadActivation,
        ) -> Result<(crate::DelegationSettings, Option<ThreadCurrent>), ThreadAssemblyError>
        {
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
        identity.binding = crate::AgentBinding::Acp(crate::AcpAgentConfig {
            account_id: "acp-account".into(),
        });

        assert!(matches!(
            owner.activate(identity, factory.clone()).await,
            Err(ThreadAssemblyError::UnsupportedBackend {
                backend: crate::AgentBackendKind::Acp
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
        child.binding = crate::AgentBinding::Acp(crate::AcpAgentConfig {
            account_id: "acp-account".into(),
        });
        assert!(matches!(
            child_owner.activate(child, child_factory.clone()).await,
            Err(ThreadAssemblyError::UnsupportedBackend {
                backend: crate::AgentBackendKind::Acp
            })
        ));
        assert_eq!(child_delegation_reads.load(Ordering::SeqCst), 0);
        assert_eq!(child_preparations.load(Ordering::SeqCst), 0);
        let state = child_owner.0.state();
        assert!(!state.activation.creating.contains_key("acp-child"));
        assert!(!state.members.entries.contains_key("acp-child"));
    }
}
