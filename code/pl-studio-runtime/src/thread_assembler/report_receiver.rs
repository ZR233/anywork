//! Temporary, storage-only report reception shares the ordinary identity/Entry owner.
use super::{
    EntryPurpose, StudioThreadAssembler, ThreadAssemblyError, agent_services::AgentServices,
};
use anyhow::{Context, Result};
use pl_core::thread::{ThreadHandle, ThreadLifecycle, inbox::ThreadMessage};
use std::sync::Arc;

enum Recipient {
    Preparing,
    Cold(EntryPurpose),
    Borrowed(ThreadHandle),
    Temporary(ThreadHandle, Arc<()>),
    Release(Arc<()>),
}

enum StorageWrite {
    Inbox(ThreadMessage),
    ReviewDelivery(super::review_delivery::ReviewDeliveryFact),
}

#[derive(Debug, thiserror::Error)]
#[error(
    "parent report delivery failed: {delivery:#}; temporary receiver cleanup failed: {cleanup:#}"
)]
struct ReportReceiverFailure {
    #[source]
    delivery: anyhow::Error,
    cleanup: anyhow::Error,
}

impl StudioThreadAssembler {
    pub(crate) fn is_report_receiver(&self, id: &str) -> bool {
        self.0
            .state()
            .entries
            .get(id)
            .is_some_and(|entry| entry.purpose == EntryPurpose::ReportReceiver)
    }

    /// A saved receipt does not discharge a cancelled/failed receiver cleanup. Both ACK recovery
    /// and normal activation retry this responsibility; neither may return the receiver as ready.
    pub(super) async fn finish_report_receiver(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let incarnation = self.0.state().entries.get(id).and_then(|entry| {
            (entry.purpose == EntryPurpose::ReportReceiver).then(|| entry.incarnation.clone())
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
            entry.purpose == EntryPurpose::ReportReceiver
                && Arc::ptr_eq(&entry.incarnation, incarnation)
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
                entry.purpose == EntryPurpose::ReportReceiver
                    && Arc::ptr_eq(&entry.incarnation, incarnation)
            }) {
                state.entries.remove(id)
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
    /// Deliver only the original ID/body and wait for the existing history handoff ACK. A normal
    /// or close-storage owner is borrowed; a cold recipient gets a separately identified temporary
    /// purpose in that same Entry registry, never an executable owner or a new permanent seal.
    pub(super) async fn redeliver_parent_report(
        &self,
        owner: &StudioThreadAssembler,
        parent: &str,
        message: ThreadMessage,
    ) -> Result<()> {
        self.write_storage_message(owner, parent, StorageWrite::Inbox(message))
            .await
    }

    pub(super) async fn persist_review_delivery(
        &self,
        owner: &StudioThreadAssembler,
        source: &str,
        fact: super::review_delivery::ReviewDeliveryFact,
    ) -> Result<super::review_delivery::ReviewDeliveryFact> {
        let id = fact.message.id.clone();
        self.write_storage_message(owner, source, StorageWrite::ReviewDelivery(fact))
            .await?;
        self.store
            .history(source)
            .await?
            .review_delivery_exception(&id)
            .await?
            .context("review delivery fact has no durable original")
    }

    /// Both receive-only purposes use the same installation, attachment and cleanup owner. A
    /// recovery fact mutates only opaque application state; it cannot admit model work or unseal
    /// execution. The caller must not hold the source/recipient identity gate while joining this.
    async fn write_storage_message(
        &self,
        owner: &StudioThreadAssembler,
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
                if state.creating.contains_key(parent) {
                    Recipient::Preparing
                } else {
                    match state.entries.get(parent) {
                        None => Recipient::Cold(EntryPurpose::ReportReceiver),
                        Some(entry) => match entry.purpose {
                            EntryPurpose::ReportReceiver => {
                                if entry.thread.snapshot().lifecycle == ThreadLifecycle::Open {
                                    Recipient::Temporary(
                                        entry.thread.clone(),
                                        entry.incarnation.clone(),
                                    )
                                } else {
                                    Recipient::Release(entry.incarnation.clone())
                                }
                            }
                            EntryPurpose::CloseStorage => {
                                if entry.thread.snapshot().lifecycle == ThreadLifecycle::Closed {
                                    Recipient::Cold(EntryPurpose::CloseStorage)
                                } else {
                                    Recipient::Borrowed(entry.thread.clone())
                                }
                            }
                            EntryPurpose::Execution
                                if (entry.ready
                                    || matches!(write, StorageWrite::ReviewDelivery(_)))
                                    && entry.thread.snapshot().lifecycle
                                        == ThreadLifecycle::Open =>
                            {
                                Recipient::Borrowed(entry.thread.clone())
                            }
                            EntryPurpose::Execution
                                if matches!(write, StorageWrite::ReviewDelivery(_))
                                    && entry.thread.snapshot().lifecycle
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
            let (thread, temporary) = match recipient {
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
                Recipient::Borrowed(thread) => (thread, None),
                Recipient::Temporary(thread, incarnation) => (thread, Some(incarnation)),
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
                    let checkpoint =
                        crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                            &self.store,
                            &record,
                        )
                        .await?
                        .context("report recipient has no saved checkpoint")?;
                    let thread =
                        match self.install_storage_owner(owner, &record, checkpoint, purpose) {
                            Ok(thread) => thread,
                            Err(ThreadAssemblyError::Preparing(_)) => {
                                drop(operation);
                                changed.await;
                                continue;
                            }
                            Err(error) => return Err(error.into()),
                        };
                    let incarnation = (purpose == EntryPurpose::ReportReceiver)
                        .then(|| owner.0.state().entries[parent].incarnation.clone());
                    (thread, incarnation)
                }
            };
            let delivery = async {
                owner.attach_close_storage(parent).await?;
                match &write {
                    StorageWrite::Inbox(message) => {
                        thread.send_message(message.clone()).await?;
                    }
                    StorageWrite::ReviewDelivery(fact) => {
                        use pl_core::thread::extensions::ExtensionMutation;
                        let history = self.store.history(parent).await?;
                        let extension_id = fact.extension_id();
                        if history
                            .review_delivery_exception(&fact.message.id)
                            .await?
                            .is_none()
                            && !thread.snapshot().extensions.contains_key(&extension_id)
                        {
                            thread
                                .mutate_extensions(vec![ExtensionMutation::Put {
                                    id: extension_id.clone(),
                                    expected_revision: None,
                                    payload: fact.encode()?,
                                }])
                                .await?;
                        }
                        owner.synchronize_observation(parent).await?;
                        let saved = history
                            .review_delivery_exception(&fact.message.id)
                            .await?
                            .context("review delivery CAS has no durable receipt")?;
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
                    }
                }
                owner.synchronize_observation(parent).await?;
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
