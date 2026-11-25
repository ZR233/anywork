//! Product-selected child configuration and resource preparation.
use super::child_resources::{CleanupGate, UnpublishedChild};
use super::{StudioThreadSpec, ThreadAssemblyError};
use futures::future::BoxFuture;
use pl_tool::collaboration::thread::WorkspaceRelease;
use std::{future::Future, sync::Arc};

/// Facts passed to the product factory; caller identity is supplied by core, not model arguments.
#[derive(Debug, Clone)]
pub struct ChildThreadRequest {
    pub workspace_owner: super::WorkspacePreparationOwner,
    pub id: String,
    pub cancellation: tokio_util::sync::CancellationToken,
    pub caller: String,
    pub call_id: String,
    pub profile_id: String,
    pub model_selection: Option<crate::NewThreadModelRoute>,
    pub delegation: crate::DelegationSettings,
    pub task_summary: pl_tool::collaboration::thread::AgentTaskSummary,
    pub writable_paths: Option<Vec<String>>,
    pub review_target_agent_id: Option<String>,
    pub review_feedback: Option<pl_tool::collaboration::thread::ReviewFeedback>,
    pub review_target: Option<crate::AgentReviewTargetSnapshot>,
    pub review_workspace: Option<crate::AgentWorkspaceAssignmentSnapshot>,
    pub metadata: pl_core::context::OpaquePayload,
}

/// Resolves configuration, creation permissions, limits and physical resources for one child.
pub trait StudioChildFactory: Send + Sync + std::fmt::Debug + 'static {
    type Admission: Send;

    /// Resolves and validates one immutable Profile snapshot before core reserves an identity.
    fn admit(
        &self,
        profile_id: &str,
        delegation: crate::DelegationSettings,
        selection: Option<crate::NewThreadModelRoute>,
    ) -> impl Future<Output = Result<Self::Admission, ThreadAssemblyError>> + Send;

    /// Must reject unauthorized profiles and exceeded product limits before allocating resources.
    /// The factory owns unpublished resources and must honor cancellation during preparation.
    fn prepare(
        &self,
        request: ChildThreadRequest,
        admission: Self::Admission,
    ) -> impl Future<Output = Result<StudioThreadSpec, ThreadAssemblyError>> + Send;

    /// Finishes published physical resources after the Thread and observation barrier close.
    /// Implementations must preserve resources by default and retain failed cleanup for retry.
    ///
    /// # Errors
    /// Returns the actual product resource shutdown error without dropping its owner.
    fn close_published(
        &self,
        _id: &str,
        _disposition: WorkspaceRelease,
    ) -> impl Future<Output = Result<(), ThreadAssemblyError>> + Send {
        async { Ok(()) }
    }

    /// Idempotently releases resources allocated under this trusted identity before publication.
    /// Missing resources are already released; failures must retain the factory's resource owner.
    fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> impl Future<Output = Result<(), ThreadAssemblyError>> + Send;
}

/// Product resource preparation after resolving an enabled Profile from canonical configuration.
pub trait StudioChildResources: Send + Sync + std::fmt::Debug + 'static {
    /// Checks caller policy and limits, then prepares owned workspace/tool/storage resources.
    /// Initial instructions and their provenance must be captured from this resolved Profile/config snapshot.
    fn prepare(
        &self,
        request: &ChildThreadRequest,
        profile: &crate::config::ResolvedAgentProfile,
    ) -> impl Future<Output = Result<StudioThreadSpec, ThreadAssemblyError>> + Send;

    /// Finishes published physical resources after the Thread and observation barrier close.
    /// Implementations must preserve resources by default and retain failed cleanup for retry.
    ///
    /// # Errors
    /// Returns the actual product resource shutdown error without dropping its owner.
    fn close_published(
        &self,
        _id: &str,
        _disposition: WorkspaceRelease,
    ) -> impl Future<Output = Result<(), ThreadAssemblyError>> + Send {
        async { Ok(()) }
    }

    /// Idempotently releases resources allocated under this trusted identity before publication.
    /// Missing resources are already released; failures must retain the factory's resource owner.
    fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> impl Future<Output = Result<(), ThreadAssemblyError>> + Send;
}

/// Profile resolution shared with Studio's settings owner; it has no secondary configuration state.
pub struct ConfiguredChildFactory<R> {
    config: crate::config::ConfigRuntime,
    resources: R,
}

impl<R: std::fmt::Debug> std::fmt::Debug for ConfiguredChildFactory<R> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ConfiguredChildFactory")
            .field("resources", &self.resources)
            .finish_non_exhaustive()
    }
}

impl<R: StudioChildResources> ConfiguredChildFactory<R> {
    /// Supplies the existing settings owner and the product resource allocator.
    pub fn new(config: crate::config::ConfigRuntime, resources: R) -> Self {
        Self { config, resources }
    }
}

impl<R: StudioChildResources> StudioChildFactory for ConfiguredChildFactory<R> {
    type Admission = crate::config::ResolvedAgentProfile;

    async fn admit(
        &self,
        profile_id: &str,
        delegation: crate::DelegationSettings,
        selection: Option<crate::NewThreadModelRoute>,
    ) -> Result<Self::Admission, ThreadAssemblyError> {
        let config = self.config.clone();
        let profile_id = profile_id.to_owned();
        let profile = tokio::task::spawn_blocking(move || {
            config.resolve_delegated_profile(&profile_id, delegation.mode, selection)
        })
        .await??;
        if matches!(&profile.binding, crate::AgentBinding::Acp(_)) {
            return Err(ThreadAssemblyError::UnsupportedBackend {
                backend: crate::AgentBackendKind::Acp,
            });
        }
        Ok(profile)
    }

    fn close_published(
        &self,
        id: &str,
        disposition: WorkspaceRelease,
    ) -> impl Future<Output = Result<(), ThreadAssemblyError>> + Send {
        self.resources.close_published(id, disposition)
    }

    fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> impl Future<Output = Result<(), ThreadAssemblyError>> + Send {
        self.resources.discard_unpublished(id, usage, disposition)
    }

    async fn prepare(
        &self,
        request: ChildThreadRequest,
        profile: Self::Admission,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        if request.cancellation.is_cancelled() {
            return Err(pl_core::thread::ThreadError::Cancelled.into());
        }
        if request.writable_paths.is_some()
            && profile.profile.workspace_mode != crate::AgentWorkspaceMode::Directory
        {
            return Err(ThreadAssemblyError::WorkspaceScope(
                request.profile_id.clone(),
            ));
        }
        if request.review_feedback.is_some()
            && profile.profile.workspace_mode != crate::AgentWorkspaceMode::Review
        {
            return Err(ThreadAssemblyError::ReviewTargetScope(
                request.profile_id.clone(),
            ));
        }
        match (
            request.review_target_agent_id.as_ref(),
            profile.profile.workspace_mode,
        ) {
            (Some(_), crate::AgentWorkspaceMode::Review) => {}
            (Some(_), _) => {
                return Err(ThreadAssemblyError::ReviewTargetScope(
                    request.profile_id.clone(),
                ));
            }
            (None, crate::AgentWorkspaceMode::Review) => {
                return Err(ThreadAssemblyError::ReviewTargetMissing(
                    request.profile_id.clone(),
                ));
            }
            (None, _) => {}
        }
        let mut spec = self.resources.prepare(&request, &profile).await?;
        if spec.id != request.id
            || spec.current.is_some()
            || spec.parent_id.as_deref() != Some(request.caller.as_str())
        {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        spec.route = profile.route;
        Ok(spec)
    }
}

type ErasedAdmission<'a> = Box<
    dyn FnOnce(ChildThreadRequest) -> BoxFuture<'a, Result<StudioThreadSpec, ThreadAssemblyError>>
        + Send
        + 'a,
>;

trait ErasedFactory: Send + Sync + std::fmt::Debug {
    fn admit<'a>(
        &'a self,
        profile_id: String,
        delegation: crate::DelegationSettings,
        selection: Option<crate::NewThreadModelRoute>,
    ) -> BoxFuture<'a, Result<ErasedAdmission<'a>, ThreadAssemblyError>>;

    fn close_published<'a>(
        &'a self,
        id: &'a str,
        disposition: WorkspaceRelease,
    ) -> BoxFuture<'a, Result<(), ThreadAssemblyError>>;

    fn discard_unpublished<'a>(
        &'a self,
        id: &'a str,
        usage: Option<&'a super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> BoxFuture<'a, Result<(), ThreadAssemblyError>>;
}
impl<T: StudioChildFactory> ErasedFactory for T {
    fn admit<'a>(
        &'a self,
        profile_id: String,
        delegation: crate::DelegationSettings,
        selection: Option<crate::NewThreadModelRoute>,
    ) -> BoxFuture<'a, Result<ErasedAdmission<'a>, ThreadAssemblyError>> {
        Box::pin(async move {
            let admission =
                StudioChildFactory::admit(self, &profile_id, delegation, selection).await?;
            Ok(Box::new(move |request| {
                let future: BoxFuture<'a, Result<StudioThreadSpec, ThreadAssemblyError>> =
                    Box::pin(StudioChildFactory::prepare(self, request, admission));
                future
            }) as ErasedAdmission<'a>)
        })
    }

    fn close_published<'a>(
        &'a self,
        id: &'a str,
        disposition: WorkspaceRelease,
    ) -> BoxFuture<'a, Result<(), ThreadAssemblyError>> {
        Box::pin(StudioChildFactory::close_published(self, id, disposition))
    }

    fn discard_unpublished<'a>(
        &'a self,
        id: &'a str,
        usage: Option<&'a super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> BoxFuture<'a, Result<(), ThreadAssemblyError>> {
        Box::pin(StudioChildFactory::discard_unpublished(
            self,
            id,
            usage,
            disposition,
        ))
    }
}

#[derive(Debug, Clone)]
pub(crate) struct ChildFactory(Arc<dyn ErasedFactory>);
impl ChildFactory {
    pub(crate) async fn close_published(
        &self,
        id: &str,
        disposition: WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        self.0.close_published(id, disposition).await
    }

    pub(crate) async fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        self.0.discard_unpublished(id, usage, disposition).await
    }
    pub(crate) fn new(factory: impl StudioChildFactory) -> Self {
        Self(Arc::new(factory))
    }

    pub(crate) async fn admit(
        &self,
        profile_id: &str,
        delegation: crate::DelegationSettings,
        selection: Option<crate::NewThreadModelRoute>,
    ) -> Result<ErasedAdmission<'_>, ThreadAssemblyError> {
        self.0
            .admit(profile_id.to_owned(), delegation, selection)
            .await
    }
}

/// Preparation is a product-owned resource before the core Thread exists.
#[derive(Debug)]
pub(crate) struct PreparingChild {
    pub(crate) parent: String,
    pub(crate) cancellation: tokio_util::sync::CancellationToken,
}

pub(crate) struct ChildReservation {
    registry: Arc<super::Registry>,
    pub(crate) id: String,
    pub(crate) cancellation: tokio_util::sync::CancellationToken,
}

impl Drop for ChildReservation {
    fn drop(&mut self) {
        self.registry
            .state()
            .activation
            .preparing_children
            .remove(&self.id);
        self.registry.changed.notify_waiters();
    }
}

impl super::State {
    fn child_admission(
        &self,
        context: &pl_tool::collaboration::control::AgentCallContext,
    ) -> Result<(String, ChildFactory), ThreadAssemblyError> {
        let caller = self
            .members
            .by_agent
            .get(&context.caller)
            .ok_or(ThreadAssemblyError::Closed)?
            .clone();
        if self.close.closing
            || self.close.sealed_agents.contains_key(&caller)
            || context.cancellation.is_cancelled()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        let parent = self
            .members
            .entries
            .get(&caller)
            .filter(|entry| super::agents::member_open(entry))
            .ok_or_else(|| ThreadAssemblyError::Identity(caller.clone()))?;
        if parent.identity.parent_agent_id.is_some() {
            return Err(ThreadAssemblyError::ChildDepth);
        }
        let factory = self
            .child_factory
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        Ok((caller, factory))
    }
}

impl super::SessionRuntime {
    pub(crate) fn child_factory(
        &self,
        context: &pl_tool::collaboration::control::AgentCallContext,
    ) -> Result<ChildFactory, ThreadAssemblyError> {
        let state = self.0.state();
        state.child_admission(context).map(|(_, factory)| factory)
    }

    pub(crate) fn reserve_child(
        &self,
        context: &pl_tool::collaboration::control::AgentCallContext,
    ) -> Result<(ChildFactory, ChildReservation), ThreadAssemblyError> {
        const MAX_TREE_THREADS: usize = 16;
        let mut state = self.0.state();
        let (caller, factory) = state.child_admission(context)?;
        let mut occupied = std::collections::BTreeSet::new();
        occupied.insert(caller.as_str());
        occupied.extend(
            state
                .members
                .entries
                .iter()
                .filter(|(_, entry)| {
                    super::EntryRegistry::membership_parent(&state.members.by_agent, entry)
                        == Some(caller.as_str())
                })
                .map(|(id, _)| id.as_str()),
        );
        occupied.extend(
            state
                .activation
                .creating
                .iter()
                .filter(|(_, preparation)| {
                    preparation.parent_id.as_deref() == Some(caller.as_str())
                })
                .map(|(id, _)| id.as_str()),
        );
        occupied.extend(
            state
                .activation
                .preparing_children
                .iter()
                .filter(|(_, preparing)| preparing.parent == caller)
                .map(|(id, _)| id.as_str()),
        );
        occupied.extend(
            state
                .activation
                .unpublished_children
                .iter()
                .filter(|(_, child)| child.parent == caller)
                .map(|(id, _)| id.as_str()),
        );
        if occupied.len() >= MAX_TREE_THREADS {
            return Err(ThreadAssemblyError::ChildCapacity(MAX_TREE_THREADS));
        }
        let id = crate::studio::new_id("thread");
        // Preparation belongs to the session; a published child must not inherit call cancellation.
        let cancellation = tokio_util::sync::CancellationToken::new();
        let workspace = super::WorkspacePreparationOwner::default();
        workspace.bind_admission(self, &id, &cancellation)?;
        state.activation.unpublished_children.insert(
            id.clone(),
            UnpublishedChild {
                retirement: Default::default(),
                workspace,
                disposal: Default::default(),
                parent: caller.clone(),
                factory: factory.clone(),
                cleanup: Arc::new(CleanupGate::default()),
            },
        );
        state.activation.preparing_children.insert(
            id.clone(),
            PreparingChild {
                parent: caller.clone(),
                cancellation: cancellation.clone(),
            },
        );
        Ok((
            factory,
            ChildReservation {
                registry: self.0.clone(),
                id,
                cancellation,
            },
        ))
    }
}

#[cfg(test)]
#[derive(Debug)]
struct TestChildFactory;

#[cfg(test)]
impl StudioChildFactory for TestChildFactory {
    type Admission = ();

    async fn admit(
        &self,
        _profile_id: &str,
        _delegation: crate::DelegationSettings,
        _selection: Option<crate::NewThreadModelRoute>,
    ) -> Result<(), ThreadAssemblyError> {
        Err(ThreadAssemblyError::Closed)
    }

    async fn prepare(
        &self,
        _request: ChildThreadRequest,
        _admission: Self::Admission,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        Err(ThreadAssemblyError::Closed)
    }

    async fn discard_unpublished(
        &self,
        _id: &str,
        _usage: Option<&super::WorkspaceUsageLease>,
        _disposition: WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        Ok(())
    }
}

#[cfg(test)]
impl super::SessionAssignment {
    pub(crate) fn child_factory(factory: impl StudioChildFactory) -> Self {
        Self(super::AssignmentKind::Installation {
            services: None,
            child_factory: ChildFactory::new(factory),
        })
    }
}
