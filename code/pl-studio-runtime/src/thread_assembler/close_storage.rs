//! A cold owner's exact storage binding and one retained AttachCold operation.
use super::{EntryPurpose, StudioThreadAssembler, ThreadAssemblyError};
use crate::studio::ThreadStorageBinding;
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_core::thread::{ThreadCheckpoint, ThreadError, ThreadLifecycle};
use std::sync::Arc;

type AttachmentCompletion = Shared<BoxFuture<'static, Result<(), Arc<ThreadError>>>>;

/// The Entry owns the binding until its real core/observation/writer joins and compare-remove.
/// In particular, attachment success does not discard the writer incarnation.
#[derive(Clone)]
pub(super) enum CloseStorage {
    /// Ordinary assembly retains AttachCold and its exact writer before extension setup can fail.
    Execution {
        completion: AttachmentCompletion,
        binding: Option<Arc<ThreadStorageBinding>>,
        observation_installed: bool,
        joined: bool,
    },
    Pending {
        record: Box<pl_protocol::Thread>,
        checkpoint: Box<ThreadCheckpoint>,
    },
    Initialized(Arc<ThreadStorageBinding>),
    Attaching {
        binding: Arc<ThreadStorageBinding>,
        completion: AttachmentCompletion,
    },
    Attached(Arc<ThreadStorageBinding>),
}

impl std::fmt::Debug for CloseStorage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Execution { .. } => "CloseStorage::Execution",
            Self::Pending { .. } => "CloseStorage::Pending",
            Self::Initialized(_) => "CloseStorage::Initialized",
            Self::Attaching { .. } => "CloseStorage::Attaching",
            Self::Attached(_) => "CloseStorage::Attached",
        })
    }
}

#[cfg(test)]
#[derive(Debug)]
pub(super) struct AttachmentAckGate {
    pub(super) thread_id: String,
    pub(super) attached: tokio::sync::oneshot::Sender<()>,
    pub(super) release: tokio::sync::oneshot::Receiver<()>,
}

impl StudioThreadAssembler {
    pub(super) async fn settle_failed_activation(
        &self,
        id: &str,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::store::thread_preparation::PreparationSave;
        let services = { self.0.state().agent_services.clone() };
        let Some(services) = services else {
            return Ok(());
        };
        let Some(record) = services
            .store
            .thread_preparation(id)
            .await
            .map_err(preparation_storage_error)?
        else {
            return Ok(());
        };
        if record.published {
            return Ok(());
        }
        if self.observed_thread(id).is_some() {
            self.close(id).await?;
        } else if record.save == PreparationSave::Unattached {
            // This call is made by the actual completed (not panicked/cancelled) factory owner,
            // before publishing its outcome. No storage/core admission has taken place.
            self.confirm_preparation_close(id, false).await?;
        } else if !record.stopped {
            return Err(ThreadAssemblyError::Identity(
                "failed activation still owns an unconfirmed checkpoint".into(),
            ));
        }
        let record = services
            .store
            .thread_preparation(id)
            .await
            .map_err(preparation_storage_error)?
            .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?;
        services.factory.retire_archive_preparation(&record).await
    }

    /// Cold archive repair is storage-only and retains the normal close binding/ACK owner.
    pub(crate) async fn ensure_archive_storage_owner(
        &self,
        record: &pl_protocol::Thread,
    ) -> Result<(), ThreadAssemblyError> {
        let _operation = self.agent_operation(&record.id).await;
        if self.observed_thread(&record.id).is_some() {
            return Ok(());
        }
        let services =
            { self.0.state().agent_services.clone() }.ok_or(ThreadAssemblyError::Closed)?;
        let checkpoint = services
            .store
            .history_for(&record.workspace_id, &record.id)
            .await
            .map_err(preparation_storage_error)?
            .checkpoint()
            .await
            .map_err(preparation_storage_error)?
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(format!(
                    "archive checkpoint is unconfirmed for {}",
                    record.id
                ))
            })?;
        services.install_storage_owner(self, record, checkpoint, EntryPurpose::CloseStorage)?;
        Ok(())
    }

    pub(super) async fn attach_execution_storage(
        &self,
        id: &str,
        storage: pl_core::thread::cold::ColdStoreHandle,
    ) -> Result<(), ThreadAssemblyError> {
        let services = { self.0.state().agent_services.clone() };
        if let Some(services) = &services
            && services
                .store
                .thread_preparation(id)
                .await
                .map_err(preparation_storage_error)?
                .is_some_and(|record| !record.published)
        {
            services
                .store
                .require_preparation_save(id)
                .await
                .map_err(preparation_storage_error)?;
        }
        let (thread, channel) = {
            let state = self.0.state();
            let entry = state
                .entries
                .get(id)
                .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?;
            (
                entry.thread.clone(),
                state
                    .agent_services
                    .as_ref()
                    .map(|services| services.store.thread_persistence().history_channel(id)),
            )
        };
        let binding = channel.map(|channel| {
            Arc::new(ThreadStorageBinding {
                storage: storage.clone(),
                channel,
            })
        });
        let completion = async move { thread.attach_storage(storage).await.map_err(Arc::new) }
            .boxed()
            .shared();
        self.0
            .state()
            .entries
            .get_mut(id)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?
            .close_storage = Some(CloseStorage::Execution {
            completion: completion.clone(),
            binding,
            observation_installed: false,
            joined: false,
        });
        completion
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "attach ordinary execution storage",
                source: Box::new(source),
            })
    }

    pub(super) async fn confirm_preparation_close(
        &self,
        id: &str,
        retired: bool,
    ) -> Result<(), ThreadAssemblyError> {
        let services = { self.0.state().agent_services.clone() };
        if let Some(services) = services
            && services
                .store
                .thread_preparation(id)
                .await
                .map_err(preparation_storage_error)?
                .is_some()
        {
            services
                .store
                .confirm_preparation_save(id)
                .await
                .map_err(preparation_storage_error)?;
            services
                .store
                .confirm_preparation_stop(id)
                .await
                .map_err(preparation_storage_error)?;
            if retired {
                services
                    .store
                    .confirm_preparation_retirement(id)
                    .await
                    .map_err(preparation_storage_error)?;
            }
        }
        Ok(())
    }

    /// The caller holds this identity's operation permit. Register the one shared operation
    /// before polling it: cancellation only drops a waiter, not AttachCold or its real result.
    pub(super) async fn attach_close_storage(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        loop {
            let owned = self.0.state().entries.get(id).map(|entry| {
                (
                    entry.incarnation.clone(),
                    entry.thread.clone(),
                    entry.close_storage.clone(),
                )
            });
            let (incarnation, thread, storage) =
                owned.ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
            match storage {
                Some(CloseStorage::Execution { completion, .. }) => {
                    completion
                        .await
                        .map_err(|source| ThreadAssemblyError::Resource {
                            operation: "confirm ordinary storage attachment",
                            source: Box::new(source),
                        })?;
                    return Ok(());
                }
                None => {
                    if self
                        .0
                        .state()
                        .entries
                        .get(id)
                        .is_some_and(|entry| entry.purpose == EntryPurpose::Execution)
                    {
                        return Ok(());
                    }
                    return Err(ThreadAssemblyError::Identity(id.to_owned()));
                }
                Some(CloseStorage::Pending { record, checkpoint }) => {
                    let services = self
                        .0
                        .state()
                        .agent_services
                        .clone()
                        .ok_or(ThreadAssemblyError::Closed)?;
                    let binding = Arc::new(
                        services
                            .factory
                            .child_close_storage(&record, &checkpoint)
                            .await?,
                    );
                    {
                        let mut state = self.0.state();
                        let entry = state
                            .entries
                            .get_mut(id)
                            .filter(|entry| Arc::ptr_eq(&entry.incarnation, &incarnation))
                            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
                        entry.close_storage = Some(CloseStorage::Initialized(binding));
                    }
                    // The initialized sink supplies this exact channel; never resolve by ID later.
                    self.publish_observation(id, &thread);
                }
                Some(CloseStorage::Initialized(binding)) => {
                    let mut state = self.0.state();
                    let entry = state
                        .entries
                        .get(id)
                        .filter(|entry| Arc::ptr_eq(&entry.incarnation, &incarnation))
                        .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
                    if !matches!(entry.close_storage.as_ref(), Some(CloseStorage::Initialized(current))
                        if Arc::ptr_eq(current, &binding))
                    {
                        continue;
                    }
                    #[cfg(test)]
                    let gate = state
                        .storage_attachment_gate
                        .take_if(|gate| gate.thread_id == id);
                    let storage = binding.storage.clone();
                    // No Registry/Entry owner is captured, so retaining this future cannot form
                    // a cycle. A completed result is retained even if no waiter remains.
                    let completion: AttachmentCompletion = async move {
                        thread.attach_storage(storage).await.map_err(Arc::new)?;
                        #[cfg(test)]
                        if let Some(gate) = gate {
                            let _ = gate.attached.send(());
                            let _ = gate.release.await;
                        }
                        Ok(())
                    }
                    .boxed()
                    .shared();
                    let entry = state
                        .entries
                        .get_mut(id)
                        .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
                    entry.close_storage = Some(CloseStorage::Attaching {
                        binding,
                        completion,
                    });
                }
                Some(CloseStorage::Attaching {
                    binding,
                    completion,
                }) => {
                    completion
                        .await
                        .map_err(|source| ThreadAssemblyError::Resource {
                            operation: "attach close-only Thread storage",
                            source: Box::new(source),
                        })?;
                    let mut state = self.0.state();
                    let entry = state
                        .entries
                        .get_mut(id)
                        .filter(|entry| Arc::ptr_eq(&entry.incarnation, &incarnation))
                        .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
                    entry.close_storage = Some(CloseStorage::Attached(binding));
                    return Ok(());
                }
                Some(CloseStorage::Attached(_)) => return Ok(()),
            }
        }
    }

    /// Only ordinary execution entries legitimately have no close-only binding. A missing or
    /// unfinished binding on either storage-only purpose cannot count as successful cleanup.
    pub(super) fn close_storage_binding(
        &self,
        id: &str,
    ) -> Result<Option<Arc<ThreadStorageBinding>>, ThreadAssemblyError> {
        let state = self.0.state();
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        match entry.close_storage.as_ref() {
            Some(CloseStorage::Execution { binding, .. }) => Ok(binding.clone()),
            Some(CloseStorage::Attached(binding)) => Ok(Some(binding.clone())),
            None if entry.purpose == EntryPurpose::Execution => Ok(None),
            _ => Err(ThreadAssemblyError::Preparing(id.to_owned())),
        }
    }

    pub(super) async fn close_storage_core(
        &self,
        id: &str,
    ) -> Result<Arc<ThreadStorageBinding>, ThreadAssemblyError> {
        self.attach_close_storage(id).await?;
        let binding = self
            .close_storage_binding(id)?
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        let thread = self
            .observed_thread(id)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        // Closed can precede a failed close flush while the core is still servicing retries.
        match thread.close().await {
            Ok(()) => {}
            Err(ThreadError::Closed) if thread.snapshot().lifecycle == ThreadLifecycle::Closed => {
                thread.flush().await?;
            }
            Err(error) => return Err(error.into()),
        }
        Ok(binding)
    }

    pub(super) async fn join_close_storage(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        if let Some(binding) = self.close_storage_binding(id)? {
            binding.channel.stop_and_join().await.map_err(|source| {
                ThreadAssemblyError::Resource {
                    operation: "join close-only Thread storage",
                    source: source.into_boxed_dyn_error(),
                }
            })?;
        }
        if let Some(CloseStorage::Execution { joined, .. }) = self
            .0
            .state()
            .entries
            .get_mut(id)
            .and_then(|entry| entry.close_storage.as_mut())
        {
            *joined = true;
        }
        Ok(())
    }
}

fn preparation_storage_error(source: anyhow::Error) -> ThreadAssemblyError {
    ThreadAssemblyError::Resource {
        operation: "retain private storage responsibility",
        source: source.into_boxed_dyn_error(),
    }
}
