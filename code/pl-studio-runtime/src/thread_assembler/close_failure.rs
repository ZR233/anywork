//! Original Thread close phases, retained by their existing cleanup gate.
use std::sync::{Arc, Mutex, Weak};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_core::thread::{ThreadError, ThreadHandle};
use pl_tool::collaboration::thread::AgentWorkspaceDisposition;

use super::child_resources::{CleanupGate, UnpublishedChild};
use super::children::ChildFactory;
use super::{Registry, StudioThreadAssembler, ThreadAssemblyError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ThreadClosePhase {
    AttachStorage,
    PrepareCandidates,
    CoreClose,
    Observation,
    PublishedResources,
    RemoveEntry,
    UnpublishedThread,
    UnpublishedFactory,
    RemoveUnpublished,
    Done,
}

type PhaseWait = Shared<BoxFuture<'static, Result<(), Arc<ThreadAssemblyError>>>>;
type CloseGrant = Option<(ThreadClosePhase, Arc<ThreadAssemblyError>)>;
type EntryCloseIdentity = (Arc<()>, ThreadHandle, Arc<CleanupGate>);

#[derive(Clone)]
pub(super) struct EntryCloseOwner {
    pub(super) incarnation: Arc<()>,
    pub(super) thread: ThreadHandle,
    pub(super) cleanup: Weak<CleanupGate>,
    pub(super) storage: Option<pl_core::thread::cold::ColdStoreHandle>,
    pub(super) factory: Option<ChildFactory>,
    pub(super) disposition: Option<AgentWorkspaceDisposition>,
    pub(super) published: bool,
}
#[derive(Clone)]
enum CloseOwner {
    Entry(EntryCloseOwner),
    Unpublished {
        factory: ChildFactory,
        cleanup: Weak<CleanupGate>,
        entry: Option<Arc<ThreadCloseRun>>,
    },
}
struct Progress {
    phase: ThreadClosePhase,
    wait: Option<PhaseWait>,
}

pub(super) struct ThreadCloseRun {
    id: String,
    registry: Weak<Registry>,
    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    operation: Arc<tokio::sync::Mutex<()>>,
    owner: CloseOwner,
    progress: Mutex<Progress>,
}
impl std::fmt::Debug for ThreadCloseRun {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ThreadCloseRun")
            .field("id", &self.id)
            .finish_non_exhaustive()
    }
}

/// Concrete Resource source. It never obtains a newer instance through close(id).
#[derive(Clone)]
pub(crate) struct ThreadCloseFailure {
    pub(crate) thread_id: String,
    pub(crate) phase: ThreadClosePhase,
    pub(crate) cause: Arc<ThreadAssemblyError>,
    pub(crate) identity_lost: bool,
    run: Arc<ThreadCloseRun>,
}
impl std::fmt::Debug for ThreadCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ThreadCloseFailure")
            .field("thread_id", &self.thread_id)
            .field("phase", &self.phase)
            .field("cause", &self.cause)
            .field("identity_lost", &self.identity_lost)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Display for ThreadCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Thread {} original {:?} close remains unresolved",
            self.thread_id, self.phase
        )
    }
}
impl std::error::Error for ThreadCloseFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(self.cause.as_ref())
    }
}

impl ThreadCloseFailure {
    pub(crate) fn original_is_complete(&self) -> bool {
        self.run.phase() == ThreadClosePhase::Done
    }

    pub(crate) fn can_resume_original(&self) -> bool {
        if self.identity_lost || !self.run.valid_identity() {
            return false;
        }
        let progress = self
            .run
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.phase == ThreadClosePhase::Done {
            return false;
        }
        match progress.wait.as_ref().and_then(Shared::peek) {
            None | Some(Ok(())) => true,
            Some(Err(error)) => self.run.can_resume_source(progress.phase, error),
        }
    }

    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    pub(crate) async fn resume_original(&self) -> Result<(), Self> {
        if self.original_is_complete() {
            return Ok(());
        }
        let grant = self.run.grant();
        let _operation = self.run.operation.clone().lock_owned().await;
        if !self.run.valid_identity() {
            let mut failure = self.clone();
            failure.identity_lost = true;
            return Err(failure);
        }
        self.run.drive(grant).await
    }

    pub(super) fn into_resource(self) -> ThreadAssemblyError {
        ThreadAssemblyError::Resource {
            operation: "close original Thread resources",
            source: Box::new(self),
        }
    }
}

pub(super) fn source<'a, T: std::error::Error + 'static>(
    mut error: &'a (dyn std::error::Error + 'static),
) -> Option<&'a T> {
    loop {
        if let Some(found) = error.downcast_ref::<T>() {
            return Some(found);
        }
        error = error.source()?;
    }
}

impl StudioThreadAssembler {
    /// Shared dependency prefix for both published and unpublished original close owners.
    /// The caller holds the identity's operation permit; the original close_all DAG is unchanged.
    pub(super) async fn prepare_entry_close(
        &self,
        id: &str,
    ) -> Result<Option<EntryCloseIdentity>, ThreadAssemblyError> {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let preparing = {
                let mut state = self.0.state();
                if let Some(entry) = state.entries.get_mut(id) {
                    entry.ready = false;
                }
                state
                    .preparing_children
                    .values()
                    .filter(|child| child.parent == id)
                    .map(|child| child.cancellation.clone())
                    .collect::<Vec<_>>()
            };
            if preparing.is_empty() {
                break;
            }
            for cancellation in preparing {
                cancellation.cancel();
            }
            changed.await;
        }
        let mut state = self.0.state();
        if let Some((child, _)) = state
            .unpublished_children
            .iter()
            .find(|(_, child)| child.parent == id)
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        if state.creating.contains_key(id) {
            return Err(ThreadAssemblyError::Preparing(id.to_owned()));
        }
        if let Some((child, _)) = state
            .preparing_children
            .iter()
            .find(|(_, preparing)| preparing.parent == id)
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        if let Some((child, _)) = state
            .entries
            .iter()
            .find(|(_, entry)| entry.parent_id.as_deref() == Some(id))
        {
            return Err(ThreadAssemblyError::Descendant(child.clone()));
        }
        if let Some((child, _)) = state
            .creating
            .iter()
            .find(|(_, preparation)| preparation.parent_id.as_deref() == Some(id))
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        Ok(state.entries.get_mut(id).map(|entry| {
            entry.ready = false;
            (
                entry.incarnation.clone(),
                entry.thread.clone(),
                entry.cleanup.clone(),
            )
        }))
    }

    /// The existing operation-gate table remains the sole gate source. The root hook makes the
    /// ordinary agent_operation entry use this same short acquisition helper.
    pub(super) fn close_operation_gate(&self, id: &str) -> Arc<tokio::sync::Mutex<()>> {
        let mut state = self.0.state();
        if let Some(gate) = state.operation_gates.get(id).and_then(Weak::upgrade) {
            return gate;
        }
        state
            .operation_gates
            .retain(|_, gate| gate.strong_count() > 0);
        let gate = Arc::new(tokio::sync::Mutex::new(()));
        state
            .operation_gates
            .insert(id.to_owned(), Arc::downgrade(&gate));
        gate
    }

    pub(super) fn capture_entry_close(
        &self,
        id: &str,
        incarnation: &Arc<()>,
        thread: &ThreadHandle,
        cleanup: &Arc<CleanupGate>,
    ) -> Result<Arc<ThreadCloseRun>, ThreadAssemblyError> {
        let operation = self.close_operation_gate(id);
        let owner = {
            let state = self.0.state();
            let entry = state
                .entries
                .get(id)
                .filter(|entry| {
                    Arc::ptr_eq(&entry.incarnation, incarnation)
                        && entry.thread.same_instance(thread)
                        && Arc::ptr_eq(&entry.cleanup, cleanup)
                })
                .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
            EntryCloseOwner {
                incarnation: incarnation.clone(),
                thread: thread.clone(),
                cleanup: Arc::downgrade(cleanup),
                storage: entry.close_storage.clone(),
                factory: state.child_factory.clone(),
                disposition: entry.workspace_disposition,
                published: entry.parent_id.is_some()
                    && !state.unpublished_children.contains_key(id),
            }
        };
        let mut slot = cleanup
            .close
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(run) = &*slot {
            return Ok(run.clone());
        }
        let run = Arc::new(ThreadCloseRun {
            id: id.to_owned(),
            registry: Arc::downgrade(&self.0),
            operation,
            owner: CloseOwner::Entry(owner),
            progress: Mutex::new(Progress {
                phase: ThreadClosePhase::AttachStorage,
                wait: None,
            }),
        });
        *slot = Some(run.clone());
        Ok(run)
    }

    /// Caller already owns the original identity's operation permit.
    pub(super) async fn close_entry_original(
        &self,
        id: &str,
        incarnation: Arc<()>,
        thread: ThreadHandle,
        cleanup: Arc<CleanupGate>,
    ) -> Result<(), ThreadAssemblyError> {
        let run = self.capture_entry_close(id, &incarnation, &thread, &cleanup)?;
        run.drive(run.grant())
            .await
            .map_err(ThreadCloseFailure::into_resource)
    }

    /// Caller already owns the operation permit. Unpublished cleanup remains valid after its
    /// original entry is removed; the pending cleanup gate is that registration's identity.
    pub(super) async fn close_unpublished_original(
        &self,
        id: &str,
        pending: UnpublishedChild,
    ) -> Result<(), ThreadAssemblyError> {
        let existing = pending
            .cleanup
            .close
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(run) = existing {
            return run
                .drive(run.grant())
                .await
                .map_err(ThreadCloseFailure::into_resource);
        }
        let operation = self.close_operation_gate(id);
        {
            let state = self.0.state();
            if !state
                .unpublished_children
                .get(id)
                .is_some_and(|current| Arc::ptr_eq(&current.cleanup, &pending.cleanup))
            {
                return Err(ThreadAssemblyError::Identity(id.to_owned()));
            }
        }
        // Use exactly the same dependency prefix as ordinary close. An unpublished child is not
        // exempt from preparing/descendant protection, including standalone custom factories.
        let entry = self.prepare_entry_close(id).await?;
        let entry = entry
            .map(|(incarnation, thread, cleanup)| {
                self.capture_entry_close(id, &incarnation, &thread, &cleanup)
            })
            .transpose()?;
        let run = {
            let mut slot = pending
                .cleanup
                .close
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(run) = &*slot {
                run.clone()
            } else {
                let run = Arc::new(ThreadCloseRun {
                    id: id.to_owned(),
                    registry: Arc::downgrade(&self.0),
                    operation,
                    owner: CloseOwner::Unpublished {
                        factory: pending.factory,
                        cleanup: Arc::downgrade(&pending.cleanup),
                        entry,
                    },
                    progress: Mutex::new(Progress {
                        phase: ThreadClosePhase::UnpublishedThread,
                        wait: None,
                    }),
                });
                *slot = Some(run.clone());
                run
            }
        };
        run.drive(run.grant())
            .await
            .map_err(ThreadCloseFailure::into_resource)
    }
}

impl ThreadCloseRun {
    fn grant(&self) -> CloseGrant {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress
            .wait
            .as_ref()
            .and_then(Shared::peek)
            .and_then(|result| result.as_ref().err())
            .filter(|error| self.can_resume_source(progress.phase, error))
            .map(|error| (progress.phase, error.clone()))
    }

    fn phase(&self) -> ThreadClosePhase {
        self.progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .phase
    }

    fn valid_identity(&self) -> bool {
        if self.phase() == ThreadClosePhase::Done {
            return true;
        }
        let Some(registry) = self.registry.upgrade() else {
            return false;
        };
        let state = registry.state();
        match &self.owner {
            CloseOwner::Entry(owner) => state.entries.get(&self.id).is_some_and(|entry| {
                Arc::ptr_eq(&entry.incarnation, &owner.incarnation)
                    && entry.thread.same_instance(&owner.thread)
                    && owner
                        .cleanup
                        .upgrade()
                        .is_some_and(|gate| Arc::ptr_eq(&entry.cleanup, &gate))
                    && entry.workspace_disposition == owner.disposition
            }),
            CloseOwner::Unpublished { cleanup, .. } => state
                .unpublished_children
                .get(&self.id)
                .is_some_and(|pending| {
                    cleanup
                        .upgrade()
                        .is_some_and(|gate| Arc::ptr_eq(&pending.cleanup, &gate))
                }),
        }
    }

    fn failure(
        self: &Arc<Self>,
        phase: ThreadClosePhase,
        cause: Arc<ThreadAssemblyError>,
    ) -> ThreadCloseFailure {
        ThreadCloseFailure {
            thread_id: self.id.clone(),
            phase,
            cause,
            identity_lost: !self.valid_identity(),
            run: self.clone(),
        }
    }

    fn can_resume_source(&self, phase: ThreadClosePhase, error: &ThreadAssemblyError) -> bool {
        use ThreadClosePhase::*;
        match phase {
            PrepareCandidates => source::<crate::studio::RejectedToolsCloseFailure>(error).is_some_and(|failure|
                matches!(&self.owner, CloseOwner::Entry(owner) if failure.matches_thread(&owner.thread))
                    && (failure.can_resume_original() || failure.original_is_complete())),
            Observation => source::<crate::studio::ObservationCloseFailure>(error)
                .is_some_and(crate::studio::ObservationCloseFailure::can_resume_original),
            PublishedResources | UnpublishedFactory => source::<crate::studio::thread_factory::FactoryCloseFailure>(error)
                .is_some_and(|failure| failure.can_resume_original() || failure.original_is_complete()),
            UnpublishedThread => source::<ThreadCloseFailure>(error)
                .is_some_and(|failure| failure.can_resume_original() || failure.original_is_complete()),
            // Only this actual Core close point has Tool::close's retry-safe contract. Storage
            // without an original channel witness stays Unknown/terminal, never generic retry.
            CoreClose => matches!(error, ThreadAssemblyError::Thread(ThreadError::Tool(_))),
            AttachStorage | RemoveEntry | RemoveUnpublished | Done => false,
        }
    }

    async fn resume_source(
        owner: CloseOwner,
        registry: Weak<Registry>,
        id: String,
        phase: ThreadClosePhase,
        error: Arc<ThreadAssemblyError>,
    ) -> Result<(), Arc<ThreadAssemblyError>> {
        let valid = {
            let registry = registry
                .upgrade()
                .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
            let state = registry.state();
            match &owner {
                CloseOwner::Entry(owner) => state.entries.get(&id).is_some_and(|entry| {
                    Arc::ptr_eq(&entry.incarnation, &owner.incarnation)
                        && entry.thread.same_instance(&owner.thread)
                        && owner
                            .cleanup
                            .upgrade()
                            .is_some_and(|cleanup| Arc::ptr_eq(&entry.cleanup, &cleanup))
                        && entry.workspace_disposition == owner.disposition
                }),
                CloseOwner::Unpublished { cleanup, .. } => {
                    state.unpublished_children.get(&id).is_some_and(|pending| {
                        cleanup
                            .upgrade()
                            .is_some_and(|cleanup| Arc::ptr_eq(&pending.cleanup, &cleanup))
                    })
                }
            }
        };
        if !valid {
            return Err(Arc::new(ThreadAssemblyError::Identity(id)));
        }
        if phase == ThreadClosePhase::PrepareCandidates
            && let Some(failure) =
                source::<crate::studio::RejectedToolsCloseFailure>(error.as_ref())
        {
            return failure.resume_original().await.map_err(|failure| {
                Arc::new(ThreadAssemblyError::Resource {
                    operation: "resume original rejected tool cleanup",
                    source: Box::new(failure),
                })
            });
        }
        if phase == ThreadClosePhase::Observation
            && let Some(failure) = source::<crate::studio::ObservationCloseFailure>(error.as_ref())
        {
            failure.resume_original().await.map_err(|failure| {
                Arc::new(ThreadAssemblyError::Resource {
                    operation: "resume original observation close",
                    source: Box::new(failure),
                })
            })?;
            failure.finish_original_drain(&id);
            return Ok(());
        }
        if matches!(
            phase,
            ThreadClosePhase::PublishedResources | ThreadClosePhase::UnpublishedFactory
        ) && let Some(failure) =
            source::<crate::studio::thread_factory::FactoryCloseFailure>(error.as_ref())
        {
            return failure.resume_original().await.map_err(|failure| {
                Arc::new(ThreadAssemblyError::Resource {
                    operation: "resume original factory close",
                    source: Box::new(failure),
                })
            });
        }
        if phase == ThreadClosePhase::UnpublishedThread
            && let Some(failure) = source::<ThreadCloseFailure>(error.as_ref())
        {
            // The enclosing unpublished request already owns this same operation permit.
            return failure
                .run
                .drive(failure.run.grant())
                .await
                .map_err(|failure| Arc::new(failure.into_resource()));
        }
        if phase == ThreadClosePhase::CoreClose
            && let CloseOwner::Entry(owner) = &owner
        {
            return owner
                .thread
                .close()
                .await
                .map_err(|error| Arc::new(error.into()));
        }
        Err(error)
    }

    fn next(&self, phase: ThreadClosePhase) -> ThreadClosePhase {
        use ThreadClosePhase::*;
        match phase {
            AttachStorage => PrepareCandidates,
            PrepareCandidates => CoreClose,
            CoreClose => Observation,
            Observation => PublishedResources,
            PublishedResources => RemoveEntry,
            RemoveEntry | RemoveUnpublished | Done => Done,
            UnpublishedThread => UnpublishedFactory,
            UnpublishedFactory => RemoveUnpublished,
        }
    }

    fn initial(
        self: &Arc<Self>,
        phase: ThreadClosePhase,
    ) -> BoxFuture<'static, Result<(), ThreadAssemblyError>> {
        let registry = self.registry.clone();
        let id = self.id.clone();
        let owner = self.owner.clone();
        async move {
            match (phase, owner) {
                (ThreadClosePhase::AttachStorage, CloseOwner::Entry(owner)) => {
                    if let Some(storage) = owner.storage {
                        owner.thread.attach_storage(storage).await?;
                    }
                    Ok(())
                }
                (ThreadClosePhase::PrepareCandidates, CloseOwner::Entry(owner)) => {
                    let future = {
                        let registry = registry
                            .upgrade()
                            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                        StudioThreadAssembler(registry).prepare_close(&id, &owner.thread)
                    };
                    future.await
                }
                (ThreadClosePhase::CoreClose, CloseOwner::Entry(owner)) => {
                    if owner.thread.snapshot().lifecycle == pl_core::thread::ThreadLifecycle::Closed
                    {
                        return Ok(());
                    }
                    owner.thread.close().await.map_err(Into::into)
                }
                (ThreadClosePhase::Observation, CloseOwner::Entry(_)) => {
                    let future = {
                        let registry = registry
                            .upgrade()
                            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                        StudioThreadAssembler(registry).drain_observation(&id)
                    };
                    future.await
                }
                (ThreadClosePhase::PublishedResources, CloseOwner::Entry(owner)) => {
                    StudioThreadAssembler::close_published_resources(registry, id, owner).await
                }
                (ThreadClosePhase::UnpublishedThread, CloseOwner::Unpublished { entry, .. }) => {
                    if let Some(entry) = entry {
                        entry
                            .drive(entry.grant())
                            .await
                            .map_err(ThreadCloseFailure::into_resource)?;
                    }
                    Ok(())
                }
                (
                    ThreadClosePhase::UnpublishedFactory,
                    CloseOwner::Unpublished {
                        factory, cleanup, ..
                    },
                ) => {
                    let valid = {
                        let registry = registry
                            .upgrade()
                            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                        let state = registry.state();
                        state.unpublished_children.get(&id).is_some_and(|pending| {
                            cleanup
                                .upgrade()
                                .is_some_and(|cleanup| Arc::ptr_eq(&pending.cleanup, &cleanup))
                        })
                    };
                    if !valid {
                        return Err(ThreadAssemblyError::Identity(id));
                    }
                    factory.discard_unpublished(&id).await
                }
                (ThreadClosePhase::RemoveEntry, CloseOwner::Entry(owner)) => {
                    let retired = {
                        let registry = registry
                            .upgrade()
                            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                        let mut state = registry.state();
                        if !state.entries.get(&id).is_some_and(|entry| {
                            Arc::ptr_eq(&entry.incarnation, &owner.incarnation)
                                && entry.thread.same_instance(&owner.thread)
                        }) {
                            return Err(ThreadAssemblyError::Identity(id));
                        }
                        state.entries.remove(&id)
                    };
                    drop(retired);
                    Ok(())
                }
                (ThreadClosePhase::RemoveUnpublished, CloseOwner::Unpublished { cleanup, .. }) => {
                    let retired = {
                        let registry = registry
                            .upgrade()
                            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                        let mut state = registry.state();
                        if !state.unpublished_children.get(&id).is_some_and(|pending| {
                            cleanup
                                .upgrade()
                                .is_some_and(|gate| Arc::ptr_eq(&pending.cleanup, &gate))
                        }) {
                            return Err(ThreadAssemblyError::Identity(id));
                        }
                        state.unpublished_children.remove(&id)
                    };
                    drop(retired);
                    Ok(())
                }
                _ => Err(ThreadAssemblyError::Identity(id)),
            }
        }
        .boxed()
    }

    /// One original phase future remains in the original cleanup slot across cancellation.
    fn drive(self: &Arc<Self>, grant: CloseGrant) -> BoxFuture<'_, Result<(), ThreadCloseFailure>> {
        async move {
            loop {
                let phase = self.phase();
                if phase == ThreadClosePhase::Done {
                    return Ok(());
                }
                // The driving call owns this permit, not the phase future stored back in the
                // gate. Cancelling observation drops the permit but retains the original wait.
                let cleanup = match &self.owner {
                    CloseOwner::Entry(owner) => owner.cleanup.upgrade(),
                    CloseOwner::Unpublished { cleanup, .. } => cleanup.upgrade(),
                };
                let Some(cleanup) = cleanup else {
                    return Err(self.failure(
                        phase,
                        Arc::new(ThreadAssemblyError::Identity(self.id.clone())),
                    ));
                };
                let _cleanup = cleanup.acquire().await;
                if !self.valid_identity() {
                    return Err(self.failure(
                        phase,
                        Arc::new(ThreadAssemblyError::Identity(self.id.clone())),
                    ));
                }
                let previous = {
                    self.progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .wait
                        .as_ref()
                        .and_then(Shared::peek)
                        .and_then(|result| result.as_ref().err())
                        .cloned()
                };
                if let Some(error) = &previous {
                    let granted = grant.as_ref().is_some_and(|(original_phase, original)| {
                        *original_phase == phase && Arc::ptr_eq(original, error)
                    });
                    if !granted || !self.can_resume_source(phase, error) {
                        return Err(self.failure(phase, error.clone()));
                    }
                }
                let candidate = if let Some(error) = previous {
                    let owner = self.owner.clone();
                    let registry = self.registry.clone();
                    let id = self.id.clone();
                    async move { Self::resume_source(owner, registry, id, phase, error).await }
                        .boxed()
                } else {
                    self.initial(phase)
                        .map(|result| result.map_err(Arc::new))
                        .boxed()
                };
                let (wait, retired) = {
                    let mut progress = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    let replace = progress
                        .wait
                        .as_ref()
                        .is_none_or(|wait| matches!(wait.peek(), Some(Err(_))));
                    let retired = if replace {
                        let future = std::panic::AssertUnwindSafe(candidate)
                            .catch_unwind()
                            .map(|result| match result {
                                Ok(result) => result,
                                Err(payload) => Err(Arc::new(ThreadAssemblyError::Resource {
                                    operation: "original Thread close phase panicked",
                                    source: Box::new(ClosePanicked(Mutex::new(payload))),
                                })),
                            })
                            .boxed()
                            .shared();
                        progress.wait.replace(future)
                    } else {
                        None
                    };
                    (
                        progress
                            .wait
                            .as_ref()
                            .expect("original close phase installed")
                            .clone(),
                        retired,
                    )
                };
                drop(retired);
                match wait.await {
                    Err(error) => return Err(self.failure(phase, error)),
                    Ok(()) => {
                        if phase == ThreadClosePhase::AttachStorage
                            && let CloseOwner::Entry(owner) = &self.owner
                            && let Some(registry) = self.registry.upgrade()
                        {
                            let retired = {
                                let mut state = registry.state();
                                state
                                    .entries
                                    .get_mut(&self.id)
                                    .filter(|entry| {
                                        Arc::ptr_eq(&entry.incarnation, &owner.incarnation)
                                            && entry.thread.same_instance(&owner.thread)
                                    })
                                    .and_then(|entry| entry.close_storage.take())
                            };
                            drop(retired);
                        }
                        let retired = {
                            let mut progress = self
                                .progress
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner);
                            if progress.phase == phase {
                                progress.phase = self.next(phase);
                                progress.wait.take()
                            } else {
                                None
                            }
                        };
                        drop(retired);
                    }
                }
            }
        }
        .boxed()
    }
}

struct ClosePanicked(Mutex<Box<dyn std::any::Any + Send>>);
impl std::fmt::Debug for ClosePanicked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let payload = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        f.debug_struct("ClosePanicked")
            .field("payload_type", &payload.as_ref().type_id())
            .finish()
    }
}
impl std::fmt::Display for ClosePanicked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original Thread close phase panicked")
    }
}
impl std::error::Error for ClosePanicked {}
