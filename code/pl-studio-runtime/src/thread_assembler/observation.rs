//! Product observation registration; callbacks execute outside the registry lock.
use super::*;
use anyhow::Context as _;

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
pub(super) enum DeliveryDisposition {
    /// The identity is already accepted with an identical body: answer with this original receipt.
    Receipt(u64),
    /// The same identity is accepted with a provably different body.
    Conflict,
    /// The Thread never accepted this identity: a normal admission may proceed.
    New,
}
#[derive(Clone)]
pub(super) struct AssemblyObservation {
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
    pub(super) fn from_callbacks(
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
    pub(super) fn publish_observation(&self, id: &str, thread: &ThreadHandle) {
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
    pub(super) async fn drain_observation(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        self.drain_observation_for_purpose(id, ClosePurpose::Preserve)
            .await
    }

    pub(super) async fn drain_observation_for_purpose(
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
    pub(super) async fn synchronize_observation(
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
    pub(crate) async fn acknowledge_parent_reports(
        &self,
        child: &crate::Thread,
    ) -> Result<ParentReportAcknowledgement, ThreadAssemblyError> {
        if let Some(parent) = child.parent_thread_id.as_deref()
            && self.parent_is_acp(parent)
        {
            // The child's own history is still durable. ACP has no Native inbox whose
            // acknowledgement could authorize or delay this child's retirement.
            return Ok(ParentReportAcknowledgement::Absent);
        }
        let failure = |source: anyhow::Error| ThreadAssemblyError::Resource {
            operation: "acknowledge terminal parent reports",
            source: source.into_boxed_dyn_error(),
        };
        let parent = child
            .parent_thread_id
            .as_deref()
            .context("terminal child has no parent")
            .map_err(failure)?;
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        let parent_record = services.record(parent).await.map_err(failure)?;
        let had_pending = self
            .pending_native_deliveries(&parent_record)
            .await
            .map_err(failure)?
            .iter()
            .any(|pending| {
                matches!(
                    pending.source(),
                    super::pending_delivery::PendingNativeDeliverySource::Terminal {
                        child_id,
                        ..
                    } if child_id == &child.id
                )
            });
        Box::pin(self.recover_saved_review_deliveries(child))
            .await
            .map_err(failure)?;
        self.join_review_delivery(&child.id)
            .await
            .map_err(failure)?;
        let remaining = self
            .pending_native_deliveries(&parent_record)
            .await
            .map_err(failure)?
            .into_iter()
            .filter(|pending| {
                matches!(
                    pending.source(),
                    super::pending_delivery::PendingNativeDeliverySource::Terminal {
                        child_id,
                        ..
                    } if child_id == &child.id
                )
            })
            .map(|pending| pending.message().id.clone())
            .collect::<Vec<_>>();
        if !remaining.is_empty() {
            return Err(failure(anyhow::anyhow!(
                "parent reports were not settled: {}",
                remaining.join(", ")
            )));
        }
        Ok(if had_pending {
            ParentReportAcknowledgement::Proven
        } else {
            ParentReportAcknowledgement::Absent
        })
    }
    pub(super) fn prepare_close(
        &self,
        id: &str,
        thread: &ThreadHandle,
    ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>> {
        let purpose = if self
            .0
            .state()
            .agent_services
            .as_ref()
            .is_some_and(|services| services.operations.is_deleting(id))
        {
            ClosePurpose::Delete
        } else {
            ClosePurpose::Preserve
        };
        self.prepare_close_for_purpose(id, thread, purpose)
    }

    pub(super) fn prepare_close_for_purpose(
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
    pub(super) fn adjudicate_message(
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

    pub(super) fn current_terminal_turn(&self, id: &str) -> Option<Arc<crate::Turn>> {
        let lookup = self.0.state().observation.as_ref()?.current_turn.clone()?;
        lookup(id)
    }

    pub(crate) async fn notify_parent(
        &self,
        id: &str,
        message: pl_core::thread::inbox::ThreadMessage,
        wake: bool,
    ) -> Result<ParentMessageDelivery, ThreadAssemblyError> {
        if self.parent_is_acp(id) {
            return Ok(ParentMessageDelivery::Skipped(
                ParentMessageSkip::TargetUnavailable,
            ));
        }
        let target = {
            let state = self.0.state();
            if state.close.closing {
                return Ok(ParentMessageDelivery::Skipped(ParentMessageSkip::Closing));
            }
            Some(
                state
                    .members
                    .entries
                    .get(id)
                    .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?,
            )
            .filter(|entry| {
                entry.native().is_ok_and(|native| {
                    native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
                })
            })
            .and_then(|entry| {
                let native = entry.native().ok()?;
                Some((native.thread.clone(), native.execution))
            })
        };
        let Some((thread, execution)) = target else {
            return Ok(ParentMessageDelivery::Skipped(
                ParentMessageSkip::TargetUnavailable,
            ));
        };
        // The committed inbox already owns this immutable terminal watermark. In particular,
        // replay must not resend a migrated, previously consumed notification with a new body.
        let snapshot = thread.snapshot();
        let message = match snapshot
            .inbox
            .iter()
            .find(|record| record.message.id == message.id)
        {
            Some(record) if record.sequence <= snapshot.consumed_messages => {
                return Ok(ParentMessageDelivery::Accepted {
                    message_id: message.id.clone(),
                    sequence: record.sequence,
                });
            }
            Some(record) => record.message.clone(),
            None => message,
        };
        let message_id = message.id.clone();
        let result = if wake {
            thread.send_message_and_resume(message, execution).await
        } else {
            // History projection can repair an inbox but cannot start a model call.
            thread.send_message(message).await
        };
        match result {
            Ok(sequence) => Ok(ParentMessageDelivery::Accepted {
                message_id,
                sequence,
            }),
            Err(ThreadError::Closed) if thread.snapshot().lifecycle != ThreadLifecycle::Open => Ok(
                ParentMessageDelivery::Skipped(ParentMessageSkip::ClosedDuringAdmission),
            ),
            Err(error) => Err(error.into()),
        }
    }

    pub(super) fn parent_is_acp(&self, parent: &str) -> bool {
        let state = self.0.state();
        state
            .members
            .entries
            .get(parent)
            .is_some_and(|entry| matches!(entry.runtime, crate::session::AgentRuntime::Acp(_)))
            || state.agent_services.as_ref().is_some_and(|services| {
                services
                    .events
                    .agent_execution_identity(parent)
                    .is_some_and(|(_, binding, _)| matches!(binding, crate::AgentBinding::Acp(_)))
            })
    }
}
