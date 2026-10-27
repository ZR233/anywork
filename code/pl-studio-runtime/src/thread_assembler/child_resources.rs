//! Retained unpublished product resources and serialized cleanup outside registry locks.
use super::{ThreadAssemblyError, children::ChildFactory};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

/// The actual preparation/unpublished owner retains its physical use independently of a caller
/// waiting for preparation. A published Entry takes over before this owner is released.
#[derive(Debug, Clone, Default)]
pub struct WorkspacePreparationOwner(Arc<std::sync::Mutex<Option<super::WorkspaceUsageLease>>>);
impl WorkspacePreparationOwner {
    pub(crate) fn retain(&self, usage: &super::WorkspaceUsageLease) {
        let previous = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .replace(usage.clone());
        drop(previous);
    }
    pub(super) fn take(&self) -> Option<super::WorkspaceUsageLease> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
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
        self.close_thread(id).await?;
        let usage = pending.workspace.take();
        if let Err(error) = pending
            .factory
            .discard_unpublished(id, usage.as_ref())
            .await
        {
            if let Some(usage) = &usage {
                pending.workspace.retain(usage);
            }
            return Err(error);
        }
        let removed = { self.0.state().unpublished_children.remove(id) };
        drop(removed);
        Ok(())
    }
}
