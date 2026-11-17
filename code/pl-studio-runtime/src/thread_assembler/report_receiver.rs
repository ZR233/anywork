//! Temporary, storage-only report reception shares the ordinary identity/Entry owner.
use super::{
    EntryPurpose, SessionRuntime, ThreadAssemblyError, agent_services::AgentServices,
    pending_delivery::PendingNativeDelivery,
};
use anyhow::{Context, Result};
use pl_core::thread::{ThreadHandle, ThreadLifecycle, inbox::ThreadMessage};
use std::sync::Arc;

enum Recipient {
    Preparing,
    Cold(EntryPurpose),
    Borrowed { thread: ThreadHandle, wake: bool },
    Temporary(ThreadHandle, Arc<()>),
    Release(Arc<()>),
}

enum StorageWrite {
    Pending(PendingNativeDelivery),
    PendingSource(PendingNativeDelivery),
    ClearPendingSource(PendingNativeDelivery),
    ReviewDelivery(super::review_delivery::ReviewDeliveryFact),
}

#[derive(Debug, thiserror::Error)]
#[error("Native delivery failed: {delivery:#}; temporary receiver cleanup failed: {cleanup:#}")]
struct ReportReceiverFailure {
    #[source]
    delivery: anyhow::Error,
    cleanup: anyhow::Error,
}

impl SessionRuntime {
    /// A saved receipt does not discharge a cancelled/failed receiver cleanup. Both ACK recovery
    /// and normal activation retry this responsibility; neither may return the receiver as ready.
    pub(super) async fn finish_report_receiver(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let incarnation = self.0.state().entries.get(id).and_then(|entry| {
            (entry.native().ok()?.purpose == EntryPurpose::ReportReceiver)
                .then_some(entry.native().ok()?.incarnation.clone())
        });
        if let Some(incarnation) = incarnation {
            let _operation = self.agent_operation(id).await;
            self.release_report_receiver(id, &incarnation).await?;
        }
        Ok(())
    }

    /// Called with the parent's operation permit. This is NOT a final close: do not seal the
    /// identity, traverse children, stop tool bindings, or join the recovery job delivering here.
    pub(super) async fn release_report_receiver(
        &self,
        id: &str,
        incarnation: &Arc<()>,
    ) -> Result<(), ThreadAssemblyError> {
        let retained = self.0.state().entries.get(id).is_some_and(|entry| {
            entry.native().is_ok_and(|native| {
                native.purpose == EntryPurpose::ReportReceiver
                    && Arc::ptr_eq(&native.incarnation, incarnation)
            })
        });
        if !retained {
            return Ok(());
        }
        // Initialization/attachment stays retained across cancellation. Closing a core before
        // attachment succeeded would strand the pending sink on an unattachable, closed core.
        let binding = self.close_storage_core(id).await?;
        self.drain_observation(id).await?;
        binding
            .channel
            .stop_and_join()
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join temporary report receiver history",
                source: source.into_boxed_dyn_error(),
            })?;
        let removed = {
            let mut state = self.0.state();
            if state.entries.get(id).is_some_and(|entry| {
                entry.native().is_ok_and(|native| {
                    native.purpose == EntryPurpose::ReportReceiver
                        && Arc::ptr_eq(&native.incarnation, incarnation)
                })
            }) {
                state.remove_entry(id)
            } else {
                None
            }
        };
        if removed.is_some() {
            drop(removed);
            self.0.changed.notify_waiters();
        }
        Ok(())
    }
}

impl AgentServices {
    /// Deliver only the original ID/body and wait for the marker + Current inbox ACK. A normal
    /// or close-storage owner is borrowed; a cold recipient gets a separately identified temporary
    /// purpose in that same Entry registry, never an executable owner or a new permanent seal.
    pub(super) async fn redeliver_parent_report(
        &self,
        owner: &SessionRuntime,
        parent: &str,
        message: ThreadMessage,
    ) -> Result<()> {
        anyhow::ensure!(
            !self
                .events
                .agent_execution_identity(parent)
                .is_some_and(|(_, binding, _)| matches!(binding, crate::AgentBinding::Acp(_)))
                && !owner.0.state().entries.get(parent).is_some_and(|entry| {
                    matches!(entry.runtime, crate::session::AgentRuntime::Acp(_))
                }),
            "Native report inbox requires a Native recipient"
        );
        self.deliver_pending_native(
            owner,
            parent,
            PendingNativeDelivery::from_terminal_message(message, false)?,
        )
        .await
    }

    pub(super) async fn deliver_pending_native(
        &self,
        owner: &SessionRuntime,
        parent: &str,
        pending: PendingNativeDelivery,
    ) -> Result<()> {
        self.write_storage_message(owner, parent, StorageWrite::Pending(pending))
            .await
    }

    pub(super) async fn persist_review_delivery(
        &self,
        owner: &SessionRuntime,
        source: &str,
        fact: super::review_delivery::ReviewDeliveryFact,
    ) -> Result<super::review_delivery::ReviewDeliveryFact> {
        let saved = fact.clone();
        self.write_storage_message(owner, source, StorageWrite::ReviewDelivery(fact))
            .await?;
        Ok(saved)
    }

    pub(super) async fn persist_pending_native_source(
        &self,
        owner: &SessionRuntime,
        source: &str,
        pending: PendingNativeDelivery,
    ) -> Result<()> {
        self.write_storage_message(owner, source, StorageWrite::PendingSource(pending))
            .await
    }

    pub(super) async fn clear_pending_native_source(
        &self,
        owner: &SessionRuntime,
        source: &str,
        pending: PendingNativeDelivery,
    ) -> Result<()> {
        self.write_storage_message(owner, source, StorageWrite::ClearPendingSource(pending))
            .await
    }

    /// All operations use the same installation, attachment and cleanup owner. Recipient and
    /// source-owned markers commit through Current; the review receipt carrier remains source-owned.
    /// The caller must not hold the source/recipient identity gate while joining this.
    async fn write_storage_message(
        &self,
        owner: &SessionRuntime,
        parent: &str,
        write: StorageWrite,
    ) -> Result<()> {
        loop {
            let changed = owner.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let operation = owner.agent_operation(parent).await;
            let recipient = {
                let state = owner.0.state();
                // Final close rejects new execution but still owns the original
                // admitted report. This private storage write never resumes it.
                let closing_inbox = matches!(write, StorageWrite::Pending(_))
                    && (state.sealed_agents.contains_key(parent) || state.closing)
                    && !state.unpublished_children.contains_key(parent)
                    && !state.preparing_children.contains_key(parent);
                let source_write = !matches!(write, StorageWrite::Pending(_));
                if state
                    .creating
                    .get(parent)
                    .is_some_and(|preparation| preparation.settlement.is_none())
                {
                    Recipient::Preparing
                } else {
                    match state.entries.get(parent) {
                        None => Recipient::Cold(EntryPurpose::ReportReceiver),
                        Some(entry) => match entry.native()?.purpose {
                            EntryPurpose::ReportReceiver => {
                                if entry.native()?.thread.snapshot().lifecycle
                                    == ThreadLifecycle::Open
                                {
                                    Recipient::Temporary(
                                        entry.native()?.thread.clone(),
                                        entry.native()?.incarnation.clone(),
                                    )
                                } else {
                                    Recipient::Release(entry.native()?.incarnation.clone())
                                }
                            }
                            EntryPurpose::CloseStorage => {
                                if entry.native()?.thread.snapshot().lifecycle
                                    == ThreadLifecycle::Closed
                                {
                                    Recipient::Cold(EntryPurpose::CloseStorage)
                                } else {
                                    Recipient::Borrowed {
                                        thread: entry.native()?.thread.clone(),
                                        wake: false,
                                    }
                                }
                            }
                            EntryPurpose::Execution
                                if (entry.native()?.ready || closing_inbox || source_write)
                                    && entry.native()?.thread.snapshot().lifecycle
                                        == ThreadLifecycle::Open =>
                            {
                                Recipient::Borrowed {
                                    thread: entry.native()?.thread.clone(),
                                    wake: entry.native()?.ready && !closing_inbox,
                                }
                            }
                            EntryPurpose::Execution
                                if source_write
                                    && entry.native()?.thread.snapshot().lifecycle
                                        == ThreadLifecycle::Closed =>
                            {
                                Recipient::Cold(EntryPurpose::CloseStorage)
                            }
                            EntryPurpose::Execution => {
                                return Err(ThreadAssemblyError::Unpublished(parent.into()).into());
                            }
                        },
                    }
                }
            };
            let (thread, temporary, allow_wake) = match recipient {
                Recipient::Preparing => {
                    // reserve() precedes the activation worker's identity permit. Waiting with
                    // that permit held would prevent the worker from ever publishing its result.
                    drop(operation);
                    changed.await;
                    continue;
                }
                Recipient::Release(incarnation) => {
                    owner.release_report_receiver(parent, &incarnation).await?;
                    continue;
                }
                Recipient::Borrowed { thread, wake } => (thread, None, wake),
                Recipient::Temporary(thread, incarnation) => (thread, Some(incarnation), false),
                Recipient::Cold(purpose) => {
                    if purpose == EntryPurpose::CloseStorage {
                        // Replacing an ended final-close core must first join its retained binding.
                        // A cancelled replacement leaves that same binding available for retry.
                        if owner.close_storage_binding(parent)?.is_some() {
                            owner.close_storage_core(parent).await?;
                        }
                        owner.drain_observation(parent).await?;
                        owner.join_close_storage(parent).await?;
                    }
                    let record = self.record(parent).await?;
                    let current =
                        crate::studio::thread_factory::recovery::load_current_for_recovery(
                            &self.store,
                            &record,
                        )
                        .await?
                        .context("report recipient has no saved current")?;
                    let thread = match self.install_storage_owner(owner, &record, current, purpose)
                    {
                        Ok(thread) => thread,
                        Err(ThreadAssemblyError::Preparing(_)) => {
                            drop(operation);
                            changed.await;
                            continue;
                        }
                        Err(error) => return Err(error.into()),
                    };
                    let incarnation = (purpose == EntryPurpose::ReportReceiver).then_some(
                        owner.0.state().entries[parent]
                            .native()?
                            .incarnation
                            .clone(),
                    );
                    (thread, incarnation, false)
                }
            };
            let delivery = async {
                owner.attach_close_storage(parent).await?;
                match &write {
                    StorageWrite::Pending(pending) => {
                        super::pending_delivery::complete_pending_native_delivery(
                            self,
                            owner,
                            parent,
                            &thread,
                            pending.clone(),
                            allow_wake,
                        )
                        .await?;
                    }
                    StorageWrite::PendingSource(pending) => {
                        super::pending_delivery::persist_pending_marker(&thread, pending).await?;
                        self.store
                            .conversation_store(parent)
                            .await?
                            .flush_current(thread.runtime_epoch())
                            .await?;
                    }
                    StorageWrite::ClearPendingSource(pending) => {
                        super::pending_delivery::clear_pending_marker(&thread, pending).await?;
                        self.store
                            .conversation_store(parent)
                            .await?
                            .flush_current(thread.runtime_epoch())
                            .await?;
                    }
                    StorageWrite::ReviewDelivery(fact) => {
                        use pl_core::thread::extensions::ExtensionMutation;
                        let extension_id = fact.extension_id();
                        if !thread.snapshot().extensions.contains_key(&extension_id) {
                            thread
                                .mutate_extensions(vec![ExtensionMutation::Put {
                                    id: extension_id.clone(),
                                    expected_revision: None,
                                    payload: fact.encode()?,
                                }])
                                .await?;
                        }
                        let saved = thread
                            .snapshot()
                            .extensions
                            .get(&extension_id)
                            .map(|record| {
                                super::review_delivery::ReviewDeliveryFact::decode(&record.payload)
                            })
                            .transpose()?
                            .context("review delivery CAS has no current carrier")?;
                        anyhow::ensure!(
                            saved.message.digest() == fact.message.digest(),
                            "review delivery identity conflicts with its current carrier"
                        );
                        if let Some(record) = thread.snapshot().extensions.get(&extension_id) {
                            let carrier = super::review_delivery::ReviewDeliveryFact::decode(
                                &record.payload,
                            )?;
                            anyhow::ensure!(
                                carrier.message.digest() == saved.message.digest(),
                                "review delivery carrier conflicts with durable original"
                            );
                            thread
                                .mutate_extensions(vec![ExtensionMutation::Delete {
                                    id: extension_id,
                                    expected_revision: record.revision,
                                }])
                                .await?;
                        }
                        self.store
                            .conversation_store(parent)
                            .await?
                            .flush_current(thread.runtime_epoch())
                            .await?;
                    }
                }
                Ok::<_, anyhow::Error>(())
            }
            .await;
            let cleanup = match temporary {
                Some(incarnation) => owner
                    .release_report_receiver(parent, &incarnation)
                    .await
                    .map_err(anyhow::Error::from),
                None => Ok(()),
            };
            return match (delivery, cleanup) {
                (Ok(()), Ok(())) => Ok(()),
                (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
                (Err(delivery), Err(cleanup)) => {
                    Err(ReportReceiverFailure { delivery, cleanup }.into())
                }
            };
        }
    }
}
