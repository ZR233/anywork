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
    pub id: String,
    pub parent_id: Option<String>,
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

impl StudioThreadAssembler {
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
        let is_restricted = restricted.is_some();
        let purpose = if is_restricted {
            ActivationPurpose::VerifiedReview
        } else {
            ActivationPurpose::Explicit
        };
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let waiting = {
                let state = self.0.state();
                if state.closing {
                    return Err(ThreadAssemblyError::Closed);
                }
                if let Some(entry) = state.entries.get(&identity.id) {
                    if is_restricted {
                        return Err(ThreadAssemblyError::Preparing(identity.id.clone()));
                    }
                    if entry.parent_id != identity.parent_id {
                        return Err(ThreadAssemblyError::Identity(identity.id));
                    }
                    if entry.purpose != super::EntryPurpose::ReportReceiver
                        && entry.ready
                        && entry.thread.snapshot().lifecycle == ThreadLifecycle::Open
                    {
                        return Ok(entry.thread.clone());
                    }
                    if entry.purpose != super::EntryPurpose::ReportReceiver
                        && !state.creating.contains_key(&identity.id)
                    {
                        return Err(ThreadAssemblyError::Unpublished(identity.id));
                    }
                }
                let preparation = match state.creating.get(&identity.id) {
                    Some(preparation)
                        if is_restricted
                            || preparation.purpose.is_some_and(|mode| mode != purpose) =>
                    {
                        return Err(ThreadAssemblyError::Preparing(identity.id.clone()));
                    }
                    Some(preparation) if preparation.parent_id == identity.parent_id => {
                        Some(preparation.result.clone())
                    }
                    Some(_) => return Err(ThreadAssemblyError::Identity(identity.id)),
                    None => None,
                };
                (
                    state
                        .entries
                        .get(&identity.id)
                        .is_some_and(|entry| entry.purpose == super::EntryPurpose::ReportReceiver),
                    preparation,
                )
            };
            if waiting.0 {
                self.finish_report_receiver(&identity.id).await?;
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
            let reservation = match self.reserve(&identity.id, identity.parent_id.as_deref()) {
                Ok(reservation) => reservation,
                Err(ThreadAssemblyError::Identity(_))
                    if {
                        let state = self.0.state();
                        state.creating.contains_key(&identity.id)
                            || state.entries.contains_key(&identity.id)
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
                    .get_mut(&identity.id)
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
                        None => owner.agent_operation(&identity.id).await,
                    };
                    if owner.0.state().sealed_agents.contains_key(&identity.id) {
                        return Err(ThreadAssemblyError::Closed);
                    }
                    let delegation = if identity.parent_id.is_none() {
                        Some(factory.root_delegation(&identity).await?)
                    } else {
                        None
                    };
                    let agent_controls = match delegation {
                        Some(selection) => {
                            let profiles = owner.agent_profiles_snapshot()?;
                            owner.agent_control_tools(&profiles, selection)?
                        }
                        None => Vec::new(),
                    };
                    workspace_owner.bind_admission(&owner, &identity.id, &cancellation)?;
                    let spec = factory
                        .prepare(ThreadPreparation {
                            workspace_owner: workspace_owner.clone(),
                            identity: identity.clone(),
                            cancellation: cancellation.clone(),
                            agent_controls,
                            delegation,
                        })
                        .await?;
                    if spec.id != identity.id || spec.parent_id != identity.parent_id {
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
                    owner.assemble_reserved(spec, &reservation).await
                })
                .catch_unwind()
                .await;
                let panicked = operation.is_err();
                let mut outcome = operation.unwrap_or(Err(ThreadAssemblyError::ActivationPanicked));
                drop(reservation);
                if !panicked
                    && outcome.is_err()
                    && let Err(cleanup) = owner.settle_failed_activation(&identity.id).await
                {
                    outcome = Err(ThreadAssemblyError::Cleanup {
                        id: identity.id.clone(),
                        setup: Box::new(outcome.err().unwrap()),
                        cleanup: Box::new(cleanup),
                    });
                }
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
