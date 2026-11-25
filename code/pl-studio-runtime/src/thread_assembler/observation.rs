//! Product observation registration; callbacks execute outside the registry lock.
use super::*;

type Observe = dyn Fn(String, ThreadHandle, Arc<crate::session::NativeResources>) + Send + Sync;
type BeforeClose = dyn Fn(
        String,
        ThreadHandle,
        ClosePurpose,
    ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
    + Send
    + Sync;
type Drain = dyn Fn(String, ClosePurpose) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
    + Send
    + Sync;
type Synchronize = dyn Fn(String) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
    + Send
    + Sync;
/// The current parent owner returns the actual admission result; saving is a separate obligation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ParentMessageDelivery {
    Accepted { message_id: String, sequence: u64 },
    Skipped(ParentMessageSkip),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ParentMessageSkip {
    Closing,
    TargetUnavailable,
    ClosedDuringAdmission,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ParentReportAcknowledgement {
    Absent,
    Proven,
}

/// Current terminal fact published by the existing observation owner. No storage callback.
pub(crate) type CurrentTurnLookup = dyn Fn(&str) -> Option<Arc<crate::Turn>> + Send + Sync;

/// Outcome of matching a delivery against the current owner's accepted identities.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum DeliveryDisposition {
    /// The identity is already accepted with an identical body: answer with this original receipt.
    Receipt(u64),
    /// The same identity is accepted with a provably different body.
    Conflict,
    /// The Thread never accepted this identity: a normal admission may proceed.
    New,
}
#[derive(Clone)]
pub(crate) struct AssemblyObservation {
    observe: Arc<Observe>,
    drain: Arc<Drain>,
    current_turn: Option<Arc<CurrentTurnLookup>>,
    before_close: Arc<BeforeClose>,
    synchronize: Arc<Synchronize>,
}
impl std::fmt::Debug for AssemblyObservation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AssemblyObservation")
    }
}
impl AssemblyObservation {
    pub(crate) fn from_callbacks(
        observe: impl Fn(String, ThreadHandle, Arc<crate::session::NativeResources>)
        + Send
        + Sync
        + 'static,
        drain: impl Fn(
            String,
            ClosePurpose,
        ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        current_turn: Option<Arc<CurrentTurnLookup>>,
        before_close: impl Fn(
            String,
            ThreadHandle,
            ClosePurpose,
        )
            -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        synchronize: impl Fn(
            String,
        )
            -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
    ) -> Self {
        Self {
            observe: Arc::new(observe),
            drain: Arc::new(drain),
            current_turn,
            before_close: Arc::new(before_close),
            synchronize: Arc::new(synchronize),
        }
    }
}
impl super::SessionAssignment {
    pub(crate) fn observation(
        observe: impl Fn(String, ThreadHandle, Arc<crate::session::NativeResources>)
        + Send
        + Sync
        + 'static,
        drain: impl Fn(
            String,
            ClosePurpose,
        ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        current_turn: Option<Arc<CurrentTurnLookup>>,
        before_close: impl Fn(
            String,
            ThreadHandle,
            ClosePurpose,
        )
            -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        synchronize: impl Fn(
            String,
        )
            -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
    ) -> Self {
        Self(super::AssignmentKind::Observation(
            AssemblyObservation::from_callbacks(
                observe,
                drain,
                current_turn,
                before_close,
                synchronize,
            ),
        ))
    }
}
impl SessionRuntime {
    #[cfg(test)]
    pub(crate) fn observe_assembly(
        &self,
        observe: impl Fn(String, ThreadHandle, Arc<crate::session::NativeResources>)
        + Send
        + Sync
        + 'static,
        drain: impl Fn(
            String,
            ClosePurpose,
        ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        current_turn: Option<Arc<CurrentTurnLookup>>,
        before_close: impl Fn(
            String,
            ThreadHandle,
            ClosePurpose,
        )
            -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        synchronize: impl Fn(
            String,
        )
            -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        if state.close.closing
            || !state.members.entries.is_empty()
            || !state.activation.creating.is_empty()
            || state.observation.is_some()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        state.observation = Some(AssemblyObservation::from_callbacks(
            observe,
            drain,
            current_turn,
            before_close,
            synchronize,
        ));
        Ok(())
    }
    pub(crate) fn publish_observation(&self, id: &str, thread: &ThreadHandle) {
        let observer = {
            let mut state = self.0.state();
            if let Some(super::CloseStorage::Execution {
                observation_installed,
                ..
            }) = state
                .members
                .entries
                .get_mut(id)
                .and_then(|entry| entry.native_mut().ok()?.close_storage.as_mut())
            {
                *observation_installed = true;
            }
            state.observation.clone()
        };
        if let Some(observer) = observer
            && let Ok(resources) = self.native_resources(thread)
        {
            (observer.observe)(id.to_owned(), thread.clone(), resources);
        }
    }
    pub(crate) async fn drain_observation(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        self.drain_observation_for_purpose(id, ClosePurpose::Preserve)
            .await
    }

    pub(crate) async fn drain_observation_for_purpose(
        &self,
        id: &str,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        if self.execution_observation_was_not_installed(id) {
            return Ok(());
        }
        let observer = self.0.state().observation.clone();
        if let Some(observer) = observer {
            let result = (observer.drain)(id.to_owned(), purpose).await;
            result?;
        }
        Ok(())
    }

    /// Fixed product/history handoff ACK without stopping an active parent's observation or
    /// entering its core command mailbox (the caller may itself be that parent's close tool).
    pub(crate) async fn synchronize_observation(
        &self,
        id: &str,
    ) -> Result<(), ThreadAssemblyError> {
        if self.execution_observation_was_not_installed(id) {
            return Ok(());
        }
        let observer = self
            .0
            .state()
            .observation
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        (observer.synchronize)(id.to_owned()).await
    }

    fn execution_observation_was_not_installed(&self, id: &str) -> bool {
        let state = self.0.state();
        matches!(
            state.members.entries.get(id).and_then(|entry| entry
                .native()
                .ok()?
                .close_storage
                .as_ref()),
            Some(super::CloseStorage::Execution {
                observation_installed: false,
                ..
            })
        )
    }

    /// Settle explicit pending Native delivery markers for this child and wait for the retained
    /// terminal operation. History rows that have no marker are not inferred as owed deliveries.
    pub(crate) fn prepare_close(
        &self,
        id: &str,
        thread: &ThreadHandle,
    ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>> {
        let purpose = if self.review_dispatcher().is_deleting(id) {
            ClosePurpose::Delete
        } else {
            ClosePurpose::Preserve
        };
        self.prepare_close_for_purpose(id, thread, purpose)
    }

    pub(crate) fn prepare_close_for_purpose(
        &self,
        id: &str,
        thread: &ThreadHandle,
        purpose: ClosePurpose,
    ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>> {
        let purpose = self.operation_close_purpose(id, purpose);
        let resources = self.native_resources(thread);
        let lifetime = resources.as_ref().ok().and_then(|scope| {
            scope.with_binding(|binding| binding.map(|binding| binding.lifetime.clone()))
        });
        if let Some(lifetime) = &lifetime {
            lifetime.cancel();
        }
        if purpose == ClosePurpose::Delete {
            thread.prepare_close_for_deletion();
        }
        let observer = self.0.state().observation.clone();
        let observed = observer
            .map(|observer| (observer.before_close)(id.to_owned(), thread.clone(), purpose));
        let thread = thread.clone();
        Box::pin(async move {
            let scope = resources?;
            let _guard = match &lifetime {
                Some(lifetime) => Some(lifetime.gate.lock().await),
                None => None,
            };
            scope
                .candidates
                .retry(Some(&thread))
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "close Native tool candidates",
                    source: source.into_boxed_dyn_error(),
                })?;
            if let Some(observed) = observed {
                observed.await?;
            }
            Ok(())
        })
    }

    /// Match only identities the current owner still retains. Absence is not a historical claim.
    pub(crate) fn adjudicate_message(
        &self,
        thread_id: &str,
        message: &pl_core::thread::inbox::ThreadMessage,
    ) -> DeliveryDisposition {
        let Some(thread) = self.observed_thread(thread_id) else {
            return DeliveryDisposition::New;
        };
        let snapshot = thread.snapshot();
        let known = snapshot
            .inbox
            .iter()
            .find(|record| record.message.id == message.id)
            .map(|record| (record.sequence, record.message.digest()))
            .or_else(|| {
                snapshot
                    .consumed_message_identities
                    .iter()
                    .find(|record| record.id == message.id)
                    .map(|record| (record.sequence, record.digest.clone()))
            });
        match known {
            Some((sequence, digest)) if digest == message.digest() => {
                DeliveryDisposition::Receipt(sequence)
            }
            Some(_) => DeliveryDisposition::Conflict,
            None => DeliveryDisposition::New,
        }
    }

    pub(crate) fn current_terminal_turn(&self, id: &str) -> Option<Arc<crate::Turn>> {
        let lookup = self.0.state().observation.as_ref()?.current_turn.clone()?;
        lookup(id)
    }
}
