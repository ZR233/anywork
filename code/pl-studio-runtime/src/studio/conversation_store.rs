//! Per-Thread execution, Current publication and archive-admission lifetime.
//! Current has no history cursor or completion publication allocator.
use super::runtime::thread_observation::{
    RetainedProjection, publication::ConversationPublication,
};
use super::storage::{
    state::StateStore,
    thread_writer::{HistoryChannel, ThreadStorageBinding},
};
use super::thread_projection::PreparedEffect;
use crate::history::HistoryStore;
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use std::sync::{Arc, Mutex};

type Initialization = Shared<BoxFuture<'static, Result<(), Arc<anyhow::Error>>>>;
type Initializer =
    Arc<dyn Fn() -> BoxFuture<'static, anyhow::Result<RetainedProjection>> + Send + Sync>;
enum Mode {
    Cold,
    Initializing { operation: Initialization },
    Ready,
    Faulted { factory: Initializer },
}

pub(crate) struct ConversationStore {
    lifecycle: tokio::sync::Mutex<()>,
    mode: Mutex<Mode>,
    driver_taken: std::sync::atomic::AtomicBool,
    history: HistoryStore,
    state: tokio::sync::Mutex<StateStore>,
    persistence: super::storage::coordinator::ThreadPersistenceCoordinator,
    pub(in crate::studio) publication: Arc<ConversationPublication>,
    retained: Mutex<Option<RetainedProjection>>,
    mutation: Mutex<()>,
    database_id: std::sync::OnceLock<String>,
    execution: Mutex<(usize, Option<usize>)>,
    channel: Mutex<std::sync::Weak<HistoryChannel>>,
}

impl std::fmt::Debug for ConversationStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationStore").finish_non_exhaustive()
    }
}

impl ConversationStore {
    /// 初始化操作归 Store 保留；取消一个等待者不会取消原恢复操作。
    pub(in crate::studio) async fn initialize_projection(
        self: &Arc<Self>,
        factory: Initializer,
    ) -> anyhow::Result<()> {
        let operation = {
            let _gate = self.lifecycle.lock().await;
            let mut mode = self
                .mode
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Mode::Ready = &*mode {
                return Ok(());
            }
            if let Mode::Initializing { operation, .. } = &*mode {
                operation.clone()
            } else {
                let factory = match &*mode {
                    Mode::Faulted { factory, .. } => factory.clone(),
                    Mode::Cold => factory,
                    Mode::Ready | Mode::Initializing { .. } => {
                        unreachable!("handled initialized modes")
                    }
                };
                let weak = Arc::downgrade(self);
                let retry = factory.clone();
                let initializer = factory.clone();
                let operation = async move {
                    let result = initializer().await;
                    let store = weak.upgrade().ok_or_else(|| {
                        Arc::new(anyhow::anyhow!("conversation closed during initialization"))
                    })?;
                    let _gate = store.lifecycle.lock().await;
                    let result = result.and_then(|mut retained| {
                        let baseline = retained
                            .baseline
                            .take()
                            .map(|current| store.publication.prepare(current))
                            .transpose()?;
                        Ok((retained, baseline))
                    });
                    match result {
                        Ok((retained, baseline)) => {
                            if let Some(baseline) = baseline {
                                store.publication.apply(baseline);
                            }
                            *store
                                .retained
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner) =
                                Some(retained);
                            *store
                                .mode
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner) = Mode::Ready;
                            Ok(())
                        }
                        Err(error) => {
                            let error = Arc::new(error);
                            *store
                                .mode
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner) =
                                Mode::Faulted { factory: retry };
                            Err(error)
                        }
                    }
                }
                .boxed()
                .shared();
                *mode = Mode::Initializing {
                    operation: operation.clone(),
                };
                operation
            }
        };
        operation
            .await
            .map_err(crate::error_mapping::shared_runtime_error)
    }

    pub(crate) fn new(
        history: HistoryStore,
        state: StateStore,
        persistence: super::storage::coordinator::ThreadPersistenceCoordinator,
    ) -> anyhow::Result<Arc<Self>> {
        Ok(Arc::new(Self {
            lifecycle: tokio::sync::Mutex::new(()),
            mode: Mutex::new(Mode::Cold),
            driver_taken: std::sync::atomic::AtomicBool::new(false),
            history,
            state: tokio::sync::Mutex::new(state),
            persistence,
            publication: Arc::new(ConversationPublication::new()),
            retained: Mutex::new(None),
            mutation: Mutex::new(()),
            database_id: std::sync::OnceLock::new(),
            execution: Mutex::new((0, None)),
            channel: Mutex::new(std::sync::Weak::new()),
        }))
    }

    /// Registers the live Core owner as the independent current JSON source.
    ///
    /// This path never opens or waits for history. The writer observes the owner's small dirty
    /// watch and periodically captures current; close consumes the owner's final handoff.
    pub(crate) async fn attach_current(
        &self,
        handle: pl_core::thread::ThreadHandle,
    ) -> anyhow::Result<()> {
        let epoch = handle.runtime_epoch();
        let mut state = self.state.lock().await;
        let current = state.current_save_state().ok();
        if current.as_ref().is_some_and(|current| {
            current.runtime_epoch == Some(epoch)
                && current.lifecycle == super::storage::current_writer::CurrentLifecycle::Open
        }) {
            return Ok(());
        }
        if current
            .as_ref()
            .is_some_and(|current| current.runtime_epoch != Some(epoch))
        {
            let _gate = self.lifecycle.lock().await;
            anyhow::ensure!(
                !self.driver_taken.load(std::sync::atomic::Ordering::Acquire),
                "previous Current projection owner has not joined"
            );
            let mut mode = self
                .mode
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            anyhow::ensure!(
                !matches!(*mode, Mode::Initializing { .. }),
                "previous Current projection initialization has not joined"
            );
            let mut retained = self
                .retained
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            anyhow::ensure!(
                retained
                    .as_ref()
                    .is_none_or(|value| value.pending.is_none()),
                "previous projection still owns an unhanded reliable fact"
            );
            // A successor starts its own Current and classifier. Archive facts already handed to
            // the old reliable channel keep their original run identity and lifetime there.
            *retained = None;
            *mode = Mode::Cold;
        }
        let previous = match current.as_ref() {
            Some(current)
                if current.lifecycle == super::storage::current_writer::CurrentLifecycle::Open =>
            {
                current.runtime_epoch
            }
            Some(current)
                if current.lifecycle
                    == super::storage::current_writer::CurrentLifecycle::Closing =>
            {
                anyhow::bail!("current writer is still closing its registered owner");
            }
            Some(_) | None => None,
        };
        state
            .attach_current(
                self.persistence.clone(),
                previous,
                epoch,
                super::storage::current_writer::CurrentSource::from_thread(handle),
            )
            .await
    }

    pub(in crate::studio) async fn close_current(
        &self,
        handle: &pl_core::thread::ThreadHandle,
    ) -> anyhow::Result<()> {
        self.state
            .lock()
            .await
            .close_current(handle.runtime_epoch())
            .await
    }

    pub(crate) async fn flush_current(
        &self,
        epoch: pl_core::thread::current::RuntimeEpoch,
    ) -> anyhow::Result<()> {
        self.state.lock().await.flush_current(epoch).await?;
        Ok(())
    }

    pub(in crate::studio) fn take_projection(&self) -> anyhow::Result<Option<RetainedProjection>> {
        anyhow::ensure!(
            !self
                .driver_taken
                .swap(true, std::sync::atomic::Ordering::AcqRel),
            "conversation already has an execution driver"
        );
        Ok(self
            .retained
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take())
    }

    pub(in crate::studio) fn retain_projection(&self, retained: Option<RetainedProjection>) {
        let mut slot = self
            .retained
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        assert!(
            slot.is_none(),
            "conversation already has a projection owner"
        );
        *slot = retained;
        self.driver_taken
            .store(false, std::sync::atomic::Ordering::Release);
    }

    pub(in crate::studio) fn admit_prepared(
        &self,
        binding: &ThreadStorageBinding,
        channel: &HistoryChannel,
        retained: &mut RetainedProjection,
    ) -> anyhow::Result<Arc<PreparedEffect>> {
        let admission_started = std::time::Instant::now();
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let locked = std::time::Instant::now();
        anyhow::ensure!(
            matches!(
                *self
                    .mode
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner),
                Mode::Ready
            ),
            "conversation is not ready for admission"
        );
        anyhow::ensure!(
            std::ptr::eq(self, binding.conversation.as_ref())
                && std::ptr::eq(channel, binding.channel.as_ref())
                && self
                    .execution
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .1
                    == Some(binding.incarnation),
            "stale conversation execution binding"
        );
        let pending = retained
            .pending
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("no retained handoff"))?;
        anyhow::ensure!(
            pending.write.effect.thread_id == self.history.thread_id()
                && pending.prepared.sequence == pending.write.effect.sequence
                && pending.prepared.accounting.thread_id == self.history.thread_id(),
            "prepared effect does not match the accepted original"
        );
        if pending.admitted {
            return Ok(pending.prepared.clone());
        }
        let prepared = pending.prepared.clone();
        let previous_retention = super::storage::thread_writer::ProjectionRetention {
            resident_bytes: retained
                .projection
                .retained_bytes()
                .saturating_add(pending.extra_retained_bytes()),
            pending: Some(super::storage::thread_writer::PendingProjectionRetention {
                sequence: pending.prepared.sequence,
                prepared_bytes: pending.prepared.retained_bytes(),
            }),
        };
        let handoff = (|| {
            channel.set_projection_retention(
                super::storage::thread_writer::ProjectionRetention {
                    resident_bytes: retained
                        .projection
                        .retained_bytes()
                        .saturating_add(pending.extra_retained_bytes()),
                    pending: Some(super::storage::thread_writer::PendingProjectionRetention {
                        sequence: prepared.sequence,
                        prepared_bytes: prepared.retained_bytes(),
                    }),
                },
            )?;
            channel.accept_prepared(Some(&pending.write), prepared.clone())
        })();
        if let Err(error) = handoff {
            // The independent Current publication is already visible. Only this archive
            // admission failed; retain its exact original and restore the archive charge.
            return match channel.set_projection_retention(previous_retention) {
                Ok(()) => Err(error),
                Err(retention) => {
                    Err(error.context(format!("restoring retained projection budget: {retention}")))
                }
            };
        }
        for change in prepared
            .history_changes
            .iter()
            .filter(|change| change.event.header.original.is_some())
        {
            channel
                .order_index()
                .mark_completion(&change.event.header.event_id, true);
        }
        pending.prepared = prepared.clone();
        pending.admitted = true;
        tracing::debug!(target: "conversation_work", current_revision = prepared.sequence,
            admission_wait_us = locked.duration_since(admission_started).as_micros() as u64,
            admission_locked_us = locked.elapsed().as_micros() as u64,
            history_changes = prepared.history_changes.len(),
            prepared_bytes = prepared.retained_bytes(),
            queued_bytes = channel.subscribe().borrow().queued_bytes,
            "conversation memory admission");
        Ok(prepared)
    }

    pub(crate) async fn attach_execution(
        &self,
        binding: &ThreadStorageBinding,
    ) -> anyhow::Result<()> {
        anyhow::ensure!(
            std::ptr::eq(self, binding.conversation.as_ref()),
            "binding belongs to another conversation"
        );
        let database = self.history.database_id().to_owned();
        anyhow::ensure!(
            self.database_id
                .get()
                .is_none_or(|current| current == &database),
            pl_core::chat::ChatError::StaleContent
        );
        self.database_id.get_or_init(|| database);
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut execution = self
            .execution
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        anyhow::ensure!(
            execution.1 == Some(binding.incarnation)
                || (execution.1.is_none() && binding.incarnation > execution.0),
            "execution binding is stale or another execution is attached"
        );
        *execution = (binding.incarnation, Some(binding.incarnation));
        *self
            .channel
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Arc::downgrade(&binding.channel);
        Ok(())
    }

    pub(crate) fn detach_execution(&self, binding: &ThreadStorageBinding) {
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut execution = self
            .execution
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if execution.1 == Some(binding.incarnation) {
            execution.1 = None;
            self.publication.retire_execution();
        }
    }

    pub(in crate::studio) fn confirm_committed(
        &self,
        committed: &super::storage::thread_writer::CommittedBatch,
    ) -> anyhow::Result<()> {
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        anyhow::ensure!(
            self.database_id
                .get()
                .is_none_or(|database| database == committed.database_id()),
            "committed database identity differs"
        );
        self.database_id
            .get_or_init(|| committed.database_id().to_owned());
        Ok(())
    }
}

impl Drop for ConversationStore {
    fn drop(&mut self) {
        // 先释放投影引用的身份索引，再发布最终预算，避免残留已释放索引的旧计数。
        drop(
            self.retained
                .get_mut()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take(),
        );
        if let Some(channel) = self
            .channel
            .get_mut()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .upgrade()
        {
            channel.release_projection_retention();
        }
    }
}
