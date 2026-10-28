//! Original Thread close phases, retained by their existing cleanup gate.
use std::sync::{Arc, Mutex, Weak};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_core::thread::{ThreadError, ThreadHandle};
use pl_tool::collaboration::thread::AgentWorkspaceDisposition;

use super::child_resources::{CleanupGate, UnpublishedChild};
use super::children::ChildFactory;
use super::published_resources::{DirectoryProjection, DirectoryProjectionFailure};
use super::{PublishedWorkspaceRetirement, Registry, StudioThreadAssembler, ThreadAssemblyError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ThreadClosePhase {
    AttachStorage,
    PrepareCandidates,
    CoreClose,
    Observation,
    PublishedResources,
    DirectoryProjection,
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
    pub(super) published: bool,
}
impl EntryCloseOwner {
    pub(super) fn matches_entry(&self, entry: &super::Entry) -> bool {
        Arc::ptr_eq(&entry.incarnation, &self.incarnation)
            && entry.thread.same_instance(&self.thread)
            && self
                .cleanup
                .upgrade()
                .is_some_and(|gate| Arc::ptr_eq(&entry.cleanup, &gate))
    }
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
    disposition: Option<AgentWorkspaceDisposition>,
    projection: Option<Arc<DirectoryProjection>>,
}

struct ExplicitCloseResponsibilities {
    frozen: bool,
    disposition: Option<AgentWorkspaceDisposition>,
    projection: Option<Arc<DirectoryProjection>>,
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
    workspace: PublishedWorkspaceRetirement,
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
        if self.identity_lost
            || !self.run.valid_identity()
            || !self.run.can_drive_retained_phase(self.workspace)
        {
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
        let grant = self.run.grant(self.workspace);
        let _operation = self.run.operation.clone().lock_owned().await;
        if !self.run.valid_identity() {
            let mut failure = self.clone();
            failure.identity_lost = true;
            return Err(failure);
        }
        self.run.drive(grant, self.workspace).await
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
                published: entry.parent_id.is_some()
                    && !state.unpublished_children.contains_key(id),
            }
        };
        let mut slot = cleanup
            .close
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(run) = &*slot {
            if run.phase() == ThreadClosePhase::Done
                || !matches!(&run.owner, CloseOwner::Entry(original)
                    if Arc::ptr_eq(&original.incarnation, &owner.incarnation)
                        && original.thread.same_instance(&owner.thread)
                        && Weak::ptr_eq(&original.cleanup, &owner.cleanup))
            {
                return Err(ThreadAssemblyError::Identity(id.to_owned()));
            }
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
                disposition: None,
                projection: None,
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
        workspace: super::PublishedWorkspaceRetirement,
    ) -> Result<(), ThreadAssemblyError> {
        let run = self.capture_entry_close(id, &incarnation, &thread, &cleanup)?;
        run.drive(run.grant(workspace), workspace)
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
                .drive(
                    run.grant(PublishedWorkspaceRetirement::Retain),
                    PublishedWorkspaceRetirement::Retain,
                )
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
                        disposition: None,
                        projection: None,
                    }),
                });
                *slot = Some(run.clone());
                run
            }
        };
        run.drive(
            run.grant(PublishedWorkspaceRetirement::Retain),
            PublishedWorkspaceRetirement::Retain,
        )
        .await
        .map_err(ThreadCloseFailure::into_resource)
    }
}

impl ThreadCloseRun {
    /// Only unfinished responsibilities from this physical Entry may be claimed. The cleanup
    /// permit serializes this snapshot with policy publication; neither state lock crosses await.
    fn explicit_responsibilities(&self) -> Option<ExplicitCloseResponsibilities> {
        let CloseOwner::Entry(owner) = &self.owner else {
            return None;
        };
        let registry = self.registry.upgrade()?;
        let state = registry.state();
        let entry = state
            .entries
            .get(&self.id)
            .filter(|entry| owner.matches_entry(entry))?;
        Some(ExplicitCloseResponsibilities {
            frozen: entry.workspace_disposition.is_some() || entry.directory_projection.is_some(),
            disposition: entry
                .workspace_disposition
                .filter(|_| owner.published && !entry.published_resources_closed),
            projection: entry
                .directory_projection
                .as_ref()
                .filter(|_| !entry.directory_projected)
                .cloned(),
        })
    }

    fn can_drive_retained_phase(&self, workspace: PublishedWorkspaceRetirement) -> bool {
        if workspace == PublishedWorkspaceRetirement::ApplyExplicitClose {
            return true;
        }
        let responsibilities = self.explicit_responsibilities();
        let (phase, admitted_wait) = {
            let progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            // A durable explicit policy freezes the whole original run, not only its resource
            // tail. Retain may join an unknown/in-flight or successful wait, but any actual
            // failure still needs the explicit operation, including Tool::close in CoreClose.
            let frozen = responsibilities.as_ref().is_some_and(|value| value.frozen)
                || progress.disposition.is_some()
                || progress.projection.is_some();
            if frozen
                && progress
                    .wait
                    .as_ref()
                    .is_some_and(|wait| matches!(wait.peek(), Some(Err(_))))
            {
                return false;
            }
            let admitted = match progress.phase {
                ThreadClosePhase::PublishedResources => progress.disposition.is_some(),
                ThreadClosePhase::DirectoryProjection => progress.projection.is_some(),
                _ => false,
            } && progress
                .wait
                .as_ref()
                .is_some_and(|wait| !matches!(wait.peek(), Some(Err(_))));
            (progress.phase, admitted)
        };
        if admitted_wait {
            return true;
        }
        let Some(ExplicitCloseResponsibilities {
            disposition,
            projection,
            ..
        }) = responsibilities
        else {
            return true;
        };
        !(disposition.is_some()
            && matches!(
                phase,
                ThreadClosePhase::PublishedResources
                    | ThreadClosePhase::DirectoryProjection
                    | ThreadClosePhase::RemoveEntry
            )
            || projection.is_some()
                && matches!(
                    phase,
                    ThreadClosePhase::DirectoryProjection | ThreadClosePhase::RemoveEntry
                ))
    }

    fn prepare_phase(
        &self,
        workspace: PublishedWorkspaceRetirement,
    ) -> Result<ThreadClosePhase, Arc<ThreadAssemblyError>> {
        let Some(ExplicitCloseResponsibilities {
            disposition,
            projection,
            ..
        }) = self.explicit_responsibilities()
        else {
            return Ok(self.phase());
        };
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Only an absent wait or a proven, side-effect-free skip can be revisited. An unknown or
        // failed future always remains the original phase/cause, including after a policy freeze.
        let skipped = match progress.phase {
            ThreadClosePhase::PublishedResources if progress.disposition.is_none() => progress
                .wait
                .as_ref()
                .is_none_or(|wait| matches!(wait.peek(), Some(Ok(())))),
            ThreadClosePhase::DirectoryProjection if progress.projection.is_none() => progress
                .wait
                .as_ref()
                .is_none_or(|wait| matches!(wait.peek(), Some(Ok(())))),
            ThreadClosePhase::RemoveEntry => progress.wait.is_none(),
            _ => false,
        };
        let mut retired = None;
        if disposition.is_some() && progress.disposition.is_none() && skipped {
            if workspace != PublishedWorkspaceRetirement::ApplyExplicitClose {
                return Err(Arc::new(explicit_close_required()));
            }
            progress.phase = ThreadClosePhase::PublishedResources;
            retired = progress.wait.take();
            progress.disposition = disposition;
        } else if projection.is_some()
            && progress.projection.is_none()
            && skipped
            && matches!(
                progress.phase,
                ThreadClosePhase::DirectoryProjection | ThreadClosePhase::RemoveEntry
            )
        {
            if workspace != PublishedWorkspaceRetirement::ApplyExplicitClose {
                return Err(Arc::new(explicit_close_required()));
            }
            progress.phase = ThreadClosePhase::DirectoryProjection;
            retired = progress.wait.take();
            progress.projection = projection;
        }
        let phase = progress.phase;
        drop(progress);
        drop(retired);
        if !self.can_drive_retained_phase(workspace) {
            // Keep an already failed explicit future's exact error rather than replacing it with
            // an authorization error. Retain may join in-flight work, but never retry it.
            let previous = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .wait
                .as_ref()
                .and_then(Shared::peek)
                .and_then(|result| result.as_ref().err())
                .cloned();
            return Err(previous.unwrap_or_else(|| Arc::new(explicit_close_required())));
        }
        Ok(phase)
    }

    fn record_success(&self, phase: ThreadClosePhase) -> Result<(), ThreadAssemblyError> {
        if !matches!(
            phase,
            ThreadClosePhase::AttachStorage
                | ThreadClosePhase::PublishedResources
                | ThreadClosePhase::DirectoryProjection
        ) {
            return Ok(());
        }
        let CloseOwner::Entry(owner) = &self.owner else {
            return Ok(());
        };
        let (disposition, projection) = {
            let progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (progress.disposition, progress.projection.clone())
        };
        let registry = self
            .registry
            .upgrade()
            .ok_or_else(|| ThreadAssemblyError::Identity(self.id.clone()))?;
        let retired = {
            let mut state = registry.state();
            let entry = state
                .entries
                .get_mut(&self.id)
                .filter(|entry| owner.matches_entry(entry))
                .ok_or_else(|| ThreadAssemblyError::Identity(self.id.clone()))?;
            match phase {
                ThreadClosePhase::AttachStorage => entry.close_storage.take(),
                ThreadClosePhase::PublishedResources => {
                    if owner.published && disposition.is_some() {
                        if entry.workspace_disposition != disposition {
                            return Err(ThreadAssemblyError::Identity(self.id.clone()));
                        }
                        entry.published_resources_closed = true;
                    }
                    None
                }
                ThreadClosePhase::DirectoryProjection => {
                    if let Some(projection) = projection {
                        if !entry
                            .directory_projection
                            .as_ref()
                            .is_some_and(|current| Arc::ptr_eq(current, &projection))
                        {
                            return Err(ThreadAssemblyError::Identity(self.id.clone()));
                        }
                        entry.directory_projected = true;
                    }
                    None
                }
                _ => None,
            }
        };
        drop(retired);
        Ok(())
    }

    fn grant(&self, workspace: PublishedWorkspaceRetirement) -> CloseGrant {
        if !self.can_drive_retained_phase(workspace) {
            return None;
        }
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
            CloseOwner::Entry(owner) => state
                .entries
                .get(&self.id)
                .is_some_and(|entry| owner.matches_entry(entry)),
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
        workspace: PublishedWorkspaceRetirement,
    ) -> ThreadCloseFailure {
        ThreadCloseFailure {
            thread_id: self.id.clone(),
            phase,
            cause,
            identity_lost: !self.valid_identity(),
            run: self.clone(),
            workspace,
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
            DirectoryProjection => source::<DirectoryProjectionFailure>(error).is_some_and(|failure| {
                let Some(registry) = self.registry.upgrade() else { return false; };
                let state = registry.state();
                matches!(&self.owner, CloseOwner::Entry(owner)
                    if state.entries.get(&self.id).is_some_and(|entry|
                        owner.matches_entry(entry)
                            && entry.directory_projection.as_ref().is_some_and(|projection|
                                Arc::ptr_eq(projection, &failure.projection))))
            }),
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
                CloseOwner::Entry(owner) => state
                    .entries
                    .get(&id)
                    .is_some_and(|entry| owner.matches_entry(entry)),
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
                .drive(
                    failure.run.grant(PublishedWorkspaceRetirement::Retain),
                    PublishedWorkspaceRetirement::Retain,
                )
                .await
                .map_err(|failure| Arc::new(failure.into_resource()));
        }
        if phase == ThreadClosePhase::DirectoryProjection
            && let CloseOwner::Entry(owner) = &owner
            && let Some(failure) = source::<DirectoryProjectionFailure>(error.as_ref())
        {
            return failure
                .projection
                .project(&owner.thread)
                .await
                .map_err(Arc::new);
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
            PublishedResources => DirectoryProjection,
            DirectoryProjection => RemoveEntry,
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
        let (disposition, projection) = {
            let progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (progress.disposition, progress.projection.clone())
        };
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
                    StudioThreadAssembler::close_published_resources(
                        registry,
                        id,
                        owner,
                        disposition,
                    )
                    .await
                }
                (ThreadClosePhase::DirectoryProjection, CloseOwner::Entry(owner)) => {
                    if let Some(projection) = projection {
                        projection.project(&owner.thread).await?;
                    }
                    Ok(())
                }
                (ThreadClosePhase::UnpublishedThread, CloseOwner::Unpublished { entry, .. }) => {
                    if let Some(entry) = entry {
                        entry
                            .drive(
                                entry.grant(PublishedWorkspaceRetirement::Retain),
                                PublishedWorkspaceRetirement::Retain,
                            )
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
                            owner.matches_entry(entry)
                                && (!owner.published
                                    || entry.workspace_disposition.is_none()
                                    || entry.published_resources_closed)
                                && (entry.directory_projection.is_none()
                                    || entry.directory_projected)
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
    fn drive(
        self: &Arc<Self>,
        grant: CloseGrant,
        workspace: PublishedWorkspaceRetirement,
    ) -> BoxFuture<'_, Result<(), ThreadCloseFailure>> {
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
                        workspace,
                    ));
                };
                let _cleanup = cleanup.acquire().await;
                if !self.valid_identity() {
                    return Err(self.failure(
                        phase,
                        Arc::new(ThreadAssemblyError::Identity(self.id.clone())),
                        workspace,
                    ));
                }
                let phase = self
                    .prepare_phase(workspace)
                    .map_err(|cause| self.failure(self.phase(), cause, workspace))?;
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
                        return Err(self.failure(phase, error.clone(), workspace));
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
                    Err(error) => return Err(self.failure(phase, error, workspace)),
                    Ok(()) => {
                        self.record_success(phase)
                            .map_err(|cause| self.failure(phase, Arc::new(cause), workspace))?;
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

#[derive(Debug, thiserror::Error)]
#[error("unfinished explicit close requires its explicit operation")]
struct ExplicitCloseRequired;

fn explicit_close_required() -> ThreadAssemblyError {
    ThreadAssemblyError::Resource {
        operation: "retain original explicit close responsibility",
        source: Box::new(ExplicitCloseRequired),
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
