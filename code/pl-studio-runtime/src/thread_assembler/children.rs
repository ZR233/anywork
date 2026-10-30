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
    pub model_selection: Option<pl_protocol::studio::NewThreadModelRoute>,
    pub delegation: pl_protocol::DelegationSettings,
    pub task_summary: pl_tool::collaboration::thread::AgentTaskSummary,
    pub writable_paths: Option<Vec<String>>,
    pub review_target_agent_id: Option<String>,
    pub review_feedback: Option<pl_tool::collaboration::thread::ReviewFeedback>,
    pub review_target: Option<pl_protocol::AgentReviewTargetSnapshot>,
    pub review_workspace: Option<pl_protocol::AgentWorkspaceAssignmentSnapshot>,
    pub metadata: pl_core::context::OpaquePayload,
}

/// Resolves configuration, creation permissions, limits and physical resources for one child.
pub trait StudioChildFactory: Send + Sync + std::fmt::Debug + 'static {
    /// Must reject unauthorized profiles and exceeded product limits before allocating resources.
    /// The factory owns unpublished resources and must honor cancellation during preparation.
    fn prepare(
        &self,
        request: ChildThreadRequest,
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
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        if request.cancellation.is_cancelled() {
            return Err(pl_core::thread::ThreadError::Cancelled.into());
        }
        let config = self.config.clone();
        let profile_id = request.profile_id.clone();
        let selection = request.model_selection.clone();
        let delegation = request.delegation;
        let profile = tokio::task::spawn_blocking(move || {
            config.resolve_delegated_profile(&profile_id, delegation.mode, selection)
        })
        .await??;
        if request.cancellation.is_cancelled() {
            return Err(pl_core::thread::ThreadError::Cancelled.into());
        }
        if request.writable_paths.is_some()
            && profile.profile.workspace_mode != pl_protocol::AgentWorkspaceMode::Directory
        {
            return Err(ThreadAssemblyError::WorkspaceScope(
                request.profile_id.clone(),
            ));
        }
        if request.review_feedback.is_some()
            && profile.profile.workspace_mode != pl_protocol::AgentWorkspaceMode::Review
        {
            return Err(ThreadAssemblyError::ReviewTargetScope(
                request.profile_id.clone(),
            ));
        }
        match (
            request.review_target_agent_id.as_ref(),
            profile.profile.workspace_mode,
        ) {
            (Some(_), pl_protocol::AgentWorkspaceMode::Review) => {}
            (Some(_), _) => {
                return Err(ThreadAssemblyError::ReviewTargetScope(
                    request.profile_id.clone(),
                ));
            }
            (None, pl_protocol::AgentWorkspaceMode::Review) => {
                return Err(ThreadAssemblyError::ReviewTargetMissing(
                    request.profile_id.clone(),
                ));
            }
            (None, _) => {}
        }
        let mut spec = self.resources.prepare(&request, &profile).await?;
        if spec.id != request.id
            || spec.checkpoint.is_some()
            || spec.parent_id.as_deref() != Some(request.caller.as_str())
        {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        spec.route = profile.route;
        Ok(spec)
    }
}

trait ErasedFactory: Send + Sync + std::fmt::Debug {
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
    fn prepare(
        &self,
        request: ChildThreadRequest,
    ) -> BoxFuture<'_, Result<StudioThreadSpec, ThreadAssemblyError>>;
}
impl<T: StudioChildFactory> ErasedFactory for T {
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
    fn prepare(
        &self,
        request: ChildThreadRequest,
    ) -> BoxFuture<'_, Result<StudioThreadSpec, ThreadAssemblyError>> {
        Box::pin(StudioChildFactory::prepare(self, request))
    }
}

#[derive(Debug, Clone)]
pub(super) struct ChildFactory(Arc<dyn ErasedFactory>);
impl ChildFactory {
    pub(super) async fn close_published(
        &self,
        id: &str,
        disposition: WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        self.0.close_published(id, disposition).await
    }

    pub(super) async fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&super::WorkspaceUsageLease>,
        disposition: WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        self.0.discard_unpublished(id, usage, disposition).await
    }
    pub(super) fn new(factory: impl StudioChildFactory) -> Self {
        Self(Arc::new(factory))
    }
    pub(super) async fn prepare(
        &self,
        request: ChildThreadRequest,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        self.0.prepare(request).await
    }
}

/// Preparation is a product-owned resource before the core Thread exists.
#[derive(Debug)]
pub(super) struct PreparingChild {
    pub(super) parent: String,
    pub(super) cancellation: tokio_util::sync::CancellationToken,
}

pub(super) struct ChildReservation {
    registry: Arc<super::Registry>,
    pub(super) id: String,
    pub(super) cancellation: tokio_util::sync::CancellationToken,
}

impl Drop for ChildReservation {
    fn drop(&mut self) {
        self.registry.state().preparing_children.remove(&self.id);
        self.registry.changed.notify_waiters();
    }
}

impl super::StudioThreadAssembler {
    pub(super) fn reserve_child(
        &self,
        context: &pl_core::tool::opaque::CallContext,
    ) -> Result<(ChildFactory, ChildReservation), ThreadAssemblyError> {
        const MAX_TREE_THREADS: usize = 16;
        let mut state = self.0.state();
        if state.closing
            || state.sealed_agents.contains_key(&context.thread_id)
            || context.cancellation.is_cancelled()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        let parent = state
            .entries
            .get(&context.thread_id)
            .filter(|entry| {
                entry.ready
                    && entry.thread.snapshot().lifecycle == pl_core::thread::ThreadLifecycle::Open
            })
            .ok_or_else(|| ThreadAssemblyError::Identity(context.thread_id.clone()))?;
        // Studio's current product policy permits only root agents to create children.
        if parent.parent_id.is_some() {
            return Err(ThreadAssemblyError::ChildDepth);
        }
        let factory = state
            .child_factory
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        let mut occupied = std::collections::BTreeSet::new();
        occupied.insert(context.thread_id.as_str());
        occupied.extend(
            state
                .entries
                .iter()
                .filter(|(_, entry)| entry.parent_id.as_deref() == Some(context.thread_id.as_str()))
                .map(|(id, _)| id.as_str()),
        );
        occupied.extend(
            state
                .creating
                .iter()
                .filter(|(_, preparation)| {
                    preparation.parent_id.as_deref() == Some(context.thread_id.as_str())
                })
                .map(|(id, _)| id.as_str()),
        );
        occupied.extend(
            state
                .preparing_children
                .iter()
                .filter(|(_, preparing)| preparing.parent == context.thread_id)
                .map(|(id, _)| id.as_str()),
        );
        occupied.extend(
            state
                .unpublished_children
                .iter()
                .filter(|(_, child)| child.parent == context.thread_id)
                .map(|(id, _)| id.as_str()),
        );
        if occupied.len() >= MAX_TREE_THREADS {
            return Err(ThreadAssemblyError::ChildCapacity(MAX_TREE_THREADS));
        }
        let id = crate::studio::new_id("thread");
        let cancellation = context.cancellation.child_token();
        state.unpublished_children.insert(
            id.clone(),
            UnpublishedChild {
                retirement: Default::default(),
                workspace: Default::default(),
                disposal: Default::default(),
                parent: context.thread_id.clone(),
                factory: factory.clone(),
                cleanup: Arc::new(CleanupGate::default()),
            },
        );
        state.preparing_children.insert(
            id.clone(),
            PreparingChild {
                parent: context.thread_id.clone(),
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
