//! Retained unpublished product resources and serialized cleanup outside registry locks.
use super::{ThreadAssemblyError, children::ChildFactory};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

/// The actual preparation/unpublished owner retains its physical use independently of a caller
/// waiting for preparation. A published Entry takes over before this owner is released.
#[derive(Debug, Default)]
struct PreparationResources {
    usage: Option<super::WorkspaceUsageLease>,
    review: Option<crate::studio::thread_factory::VerifiedLocalResume>,
}
#[derive(Debug, Clone, Default)]
pub struct WorkspacePreparationOwner(Arc<std::sync::Mutex<PreparationResources>>);
impl WorkspacePreparationOwner {
    pub(crate) fn verified_review(
        proof: crate::studio::thread_factory::VerifiedLocalResume,
    ) -> Self {
        Self(Arc::new(std::sync::Mutex::new(PreparationResources {
            usage: Some(proof.usage()),
            review: Some(proof),
        })))
    }
    pub(crate) fn take_review(&self) -> Option<crate::studio::thread_factory::VerifiedLocalResume> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .review
            .take()
    }
    pub(crate) fn retain(&self, usage: &super::WorkspaceUsageLease) {
        let previous = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .usage
            .replace(usage.clone());
        drop(previous);
    }
    pub(super) fn take(&self) -> Option<super::WorkspaceUsageLease> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .usage
            .take()
    }
}

#[derive(Debug, Default)]
pub(super) struct CleanupGate {
    busy: AtomicBool,
    changed: tokio::sync::Notify,
}

pub(super) struct CleanupPermit(Arc<CleanupGate>);
impl Drop for CleanupPermit {
    fn drop(&mut self) {
        self.0.busy.store(false, Ordering::Release);
        self.0.changed.notify_waiters();
    }
}
impl CleanupGate {
    pub(super) async fn acquire(self: &Arc<Self>) -> CleanupPermit {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self
                .busy
                .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
                .is_ok()
            {
                return CleanupPermit(self.clone());
            }
            changed.await;
        }
    }
}

type DisposalTask =
    Arc<tokio::sync::Mutex<Option<tokio::task::JoinHandle<Result<(), ThreadAssemblyError>>>>>;

#[derive(Debug, Clone)]
pub(super) struct UnpublishedChild {
    pub(super) retirement:
        Arc<std::sync::Mutex<Option<pl_tool::collaboration::thread::WorkspaceRelease>>>,
    pub(super) workspace: WorkspacePreparationOwner,
    pub(super) parent: String,
    pub(super) factory: ChildFactory,
    pub(super) cleanup: Arc<CleanupGate>,
    pub(super) disposal: DisposalTask,
}

impl super::StudioThreadAssembler {
    pub(super) fn publish_child_resources(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        if state.closing
            || state.sealed_agents.contains_key(id)
            || state
                .preparing_children
                .get(id)
                .is_some_and(|child| child.cancellation.is_cancelled())
        {
            return Err(ThreadAssemblyError::Closed);
        }
        if !state.unpublished_children.contains_key(id) {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        let entry = state
            .entries
            .get_mut(id)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?;
        if entry.thread.snapshot().lifecycle != pl_core::thread::ThreadLifecycle::Open {
            return Err(ThreadAssemblyError::Closed);
        }
        entry.ready = true;
        let unpublished = state.unpublished_children.remove(id);
        drop(state);
        drop(unpublished);
        Ok(())
    }

    /// Retries cleanup of a failed, unpublished child without rerunning its factory or tools.
    ///
    /// # Errors
    /// Returns the retained Thread close or product resource cleanup error.
    pub async fn discard_unpublished_child(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        if self.0.state().preparing_children.contains_key(id) {
            return Err(ThreadAssemblyError::Preparing(id.into()));
        }
        self.discard_child_resources(id).await
    }

    pub(super) async fn discard_child_resources(
        &self,
        id: &str,
    ) -> Result<(), ThreadAssemblyError> {
        let pending = { self.0.state().unpublished_children.get(id).cloned() };
        let Some(pending) = pending else {
            return Ok(());
        };
        let _cleanup = pending.cleanup.acquire().await;
        let mut disposal = pending.disposal.lock().await;
        if disposal.is_none() {
            let owner = self.clone();
            let id = id.to_owned();
            let resources = pending.clone();
            *disposal = Some(tokio::spawn(async move {
                owner.dispose_unpublished(&id, resources).await
            }));
        }
        let result = disposal.as_mut().unwrap().await;
        disposal.take();
        result.map_err(|source| ThreadAssemblyError::Resource {
            operation: "join unpublished workspace cleanup",
            source: Box::new(source),
        })?
    }

    async fn dispose_unpublished(
        &self,
        id: &str,
        pending: UnpublishedChild,
    ) -> Result<(), ThreadAssemblyError> {
        if !self.0.state().unpublished_children.contains_key(id) {
            return Ok(());
        }
        // This retained disposal task owns only its cleanup gate, not the identity operation
        // permit. close_thread consumes that permit and may release it while joining producers.
        let operation = self.agent_operation(id).await;
        self.close_thread(id, operation).await?;
        let services = { self.0.state().agent_services.clone() };
        if let Some(services) = &services
            && services
                .store
                .thread_preparation(id)
                .await
                .map_err(retirement_error)?
                .is_some()
        {
            services
                .store
                .confirm_preparation_stop(id)
                .await
                .map_err(retirement_error)?;
        }
        let disposition = {
            let _state = self.0.state();
            let mut retirement = pending
                .retirement
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let disposition =
                retirement.unwrap_or(pl_tool::collaboration::thread::WorkspaceRelease::Cleanup);
            *retirement = Some(disposition);
            disposition
        };
        let usage = pending.workspace.take();
        if let Err(error) = pending
            .factory
            .discard_unpublished(id, usage.as_ref(), disposition)
            .await
        {
            if let Some(usage) = &usage {
                pending.workspace.retain(usage);
            }
            if disposition == pl_tool::collaboration::thread::WorkspaceRelease::Cleanup {
                *pending
                    .retirement
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
            }
            return Err(error);
        }
        if let Some(services) = services
            && services
                .store
                .thread_preparation(id)
                .await
                .map_err(retirement_error)?
                .is_some()
        {
            services
                .store
                .confirm_preparation_retirement(id)
                .await
                .map_err(retirement_error)?;
        }
        let removed = { self.0.state().unpublished_children.remove(id) };
        drop(removed);
        Ok(())
    }
}

fn retirement_error(source: anyhow::Error) -> ThreadAssemblyError {
    ThreadAssemblyError::Resource {
        operation: "confirm private preparation retirement",
        source: source.into_boxed_dyn_error(),
    }
}
