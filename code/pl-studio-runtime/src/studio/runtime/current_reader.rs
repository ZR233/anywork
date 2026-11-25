//! Current-only observation over the existing State assembler and RAM body owners.

use std::sync::{Arc, Mutex};

use crate::{
    CURRENT_PROTOCOL_VERSION, ContentRange, ContentWindow, CurrentCollectionPage,
    CurrentCollectionRef, CurrentContentRef, CurrentFrame, CurrentRevision, CurrentView,
    ReadDemand, StudioError, StudioErrorCode, StudioErrorReason, ThreadNotification,
    ThreadSubscriptionUpdate,
};
use anyhow::{Context, Result, ensure};
use tokio::sync::{Mutex as AsyncMutex, mpsc, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use super::{StudioRuntime, conversation_state_feed::ConversationStateFeed};
use crate::studio::thread_projection::{CurrentState, current_page};

type CurrentPublicationChanges =
    watch::Receiver<Option<Arc<super::thread_observation::ConversationSource>>>;

#[derive(Clone)]
pub struct CurrentReader {
    pub(super) inner: Arc<Inner>,
}

pub(super) struct Inner {
    runtime: StudioRuntime,
    thread_id: String,
    cancel: CancellationToken,
    admission: Mutex<()>,
    tasks: TaskTracker,
}

fn stale() -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::Conflict,
        "Current reference is no longer available",
        false,
    )
    .with_reason(
        StudioErrorReason::StaleCurrentReference,
        serde_json::Value::Null,
    )
    .into()
}

fn closed() -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Current reader is closed",
        false,
    )
    .into()
}

impl StudioRuntime {
    pub async fn open_current_reader(
        &self,
        thread_id: &str,
        current_protocol_version: u32,
        demand: ReadDemand,
    ) -> Result<CurrentReader> {
        ensure!(
            current_protocol_version == CURRENT_PROTOCOL_VERSION,
            StudioError::new(
                StudioErrorCode::Protocol,
                "Unsupported current protocol version",
                false
            )
            .with_reason(
                StudioErrorReason::ProtocolVersionMismatch,
                serde_json::Value::Null
            )
        );
        demand.validate(1)?;
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let reader = CurrentReader {
            inner: Arc::new(Inner {
                runtime: self.clone(),
                thread_id: thread_id.into(),
                cancel: self.thread_observations.read_lifetime().child_token(),
                admission: Mutex::new(()),
                tasks: TaskTracker::new(),
            }),
        };
        self.thread_observations
            .observation_slot(thread_id)
            .register_current_reader(&reader);
        reader.check_open()?;
        Ok(reader)
    }
}

impl CurrentReader {
    pub fn thread_id(&self) -> &str {
        &self.inner.thread_id
    }
    pub fn cancellation_token(&self) -> CancellationToken {
        self.inner.cancel.clone()
    }

    fn spawn<T: Send + 'static>(
        &self,
        future: impl Future<Output = T> + Send + 'static,
    ) -> Result<tokio::task::JoinHandle<T>> {
        let _gate = self
            .inner
            .admission
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure!(!self.inner.cancel.is_cancelled(), closed());
        Ok(self.inner.tasks.spawn(future))
    }

    async fn run<T: Send + 'static>(
        &self,
        future: impl Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        let request_cancel = CancellationToken::new();
        let _cancel = request_cancel.clone().drop_guard();
        let owner_cancel = self.inner.cancel.clone();
        self.spawn(async move {
            tokio::select! { biased;
                _ = owner_cancel.cancelled() => Err(closed()),
                _ = request_cancel.cancelled() => Err(closed()),
                result = future => result,
            }
        })?
        .await
        .context("join current read")?
    }

    fn check_open(&self) -> Result<()> {
        ensure!(!self.inner.cancel.is_cancelled(), closed());
        Ok(())
    }

    async fn current(&self, cancellation: &CancellationToken) -> Result<Arc<CurrentState>> {
        self.check_open()?;
        let runtime = &self.inner.runtime;
        let slot = runtime
            .thread_observations
            .observation_slot(self.thread_id());
        let (position, mut changed) = slot.capture();
        if let Some(feed) = position.source.filter(|feed| !feed.is_delivery_closed()) {
            let mut registration = feed.conversation();
            loop {
                self.check_open()?;
                ensure!(!cancellation.is_cancelled(), closed());
                ensure!(slot.is_current(position.epoch), stale());
                if let Some(source) = registration.source.take() {
                    return Ok(source.current.clone());
                }
                if let Some(error) = registration.owner_progress.borrow().retained_error() {
                    return Err(crate::error_mapping::shared_runtime_error(error));
                }
                ensure!(!registration.owner_progress.borrow().is_finished(), stale());
                tokio::select! { biased;
                    _ = cancellation.cancelled() => return Err(closed()),
                    _ = self.inner.cancel.cancelled() => return Err(closed()),
                    _ = changed.changed() => return Err(stale()),
                    _ = feed.delivery_closed() => return Err(stale()),
                    result = registration.progress.changed() => {
                        ensure!(result.is_ok(), stale());
                        registration.source = registration.progress.borrow_and_update().clone();
                    },
                    result = registration.owner_progress.changed() => { ensure!(result.is_ok(), stale()); },
                }
            }
        }
        let saved = self.saved_current().await;
        ensure!(slot.is_current(position.epoch), stale());
        let saved = saved?;
        self.check_open()?;
        CurrentState::from_saved(&saved)
    }

    async fn saved_current(&self) -> Result<Arc<pl_core::thread::current::ThreadCurrent>> {
        let runtime = &self.inner.runtime;
        let thread = runtime.read_protocol_thread(self.thread_id()).await?;
        runtime.check_thread_read_access(&thread)?;
        // A cold reader may be the first entry after an upgrade. Reuse the explicit
        // maintenance boundary before declaring the old checkpoint unrecoverable.
        // An existing current file still loads independently of History.
        let saved = crate::studio::thread_factory::recovery::load_current_for_recovery(
            &runtime.store,
            &thread,
        )
        .await?;
        self.check_open()?;
        saved.map(Arc::new).ok_or_else(|| {
            StudioError::new(
                StudioErrorCode::NotFound,
                "This Thread has no recoverable current snapshot",
                false,
            )
            .into()
        })
    }

    fn metadata_revision(&self, current: &CurrentState) -> Result<u64> {
        let slot = self
            .inner
            .runtime
            .thread_observations
            .observation_slot(self.thread_id());
        let (position, _) = slot.capture();
        let revision = if let Some(feed) = position.source.filter(|feed| !feed.is_delivery_closed())
        {
            ensure!(
                feed.current_conversation()
                    .is_some_and(|source| source.current.owner_id() == current.owner_id()),
                stale()
            );
            feed.current_revision()
        } else {
            current.revision()
        };
        ensure!(
            revision != u64::MAX,
            StudioError::new(
                StudioErrorCode::Unavailable,
                "Current metadata revision exhausted",
                false
            )
        );
        Ok(revision)
    }

    async fn baseline(
        &self,
        demand: ReadDemand,
        cancellation: &CancellationToken,
    ) -> Result<(CurrentView, ConversationStateFeed)> {
        let mut reopened = false;
        loop {
            self.check_open()?;
            ensure!(!cancellation.is_cancelled(), closed());
            let slot = self
                .inner
                .runtime
                .thread_observations
                .observation_slot(self.thread_id());
            let (position, _) = slot.capture();
            // A passive baseline reads complete JSON once. Both original State assembly and
            // Current projection consume that same immutable cut, even during activation.
            let saved = if position
                .source
                .as_ref()
                .is_none_or(|source| source.is_delivery_closed())
            {
                self.saved_current().await.map(Some)
            } else {
                Ok(None)
            };
            if !slot.is_current(position.epoch) {
                continue;
            }
            let saved = saved?;
            let opened = self
                .inner
                .runtime
                .open_current_state_feed(
                    self.thread_id(),
                    cancellation.child_token(),
                    saved.clone(),
                )
                .await;
            let mut state = match opened {
                Ok(state) => state,
                Err(error)
                    if !reopened
                        && error.downcast_ref::<StudioError>().is_some_and(|error| {
                            error.reason() == Some("conversationResyncRequired")
                        }) =>
                {
                    // Rebinding the original publication closes the old registration before
                    // its first source. Reopen on that new owner; no history is replayed.
                    reopened = true;
                    continue;
                }
                Err(error) => return Err(error),
            };
            let result = async {
                let Some(ThreadSubscriptionUpdate::Snapshot { snapshot, .. }) =
                    state.recv().await?
                else {
                    anyhow::bail!("current State assembler did not return a baseline");
                };
                let current = match saved.as_ref() {
                    Some(saved) => CurrentState::from_saved(saved)?,
                    None => self.current(cancellation).await?,
                };
                ensure!(snapshot.revision == current.revision(), stale());
                // Catalog identity is independent; its asynchronously updated status must not
                // replace this Current owner's actual logical state in the same baseline.
                let mut snapshot = snapshot;
                snapshot.thread.status = current.projection().logical_status;
                let view = CurrentView {
                    revision: CurrentRevision {
                        owner_id: current.owner_id().into(),
                        revision: self.metadata_revision(&current)?,
                    },
                    state: snapshot,
                    projection: current.projection().clone(),
                };
                CurrentFrame::Reset {
                    view: Box::new(view.clone()),
                }
                .validate_demand(demand)?;
                Ok::<_, anyhow::Error>(view)
            }
            .await;
            if !slot.is_current(position.epoch) {
                state.close().await?;
                continue;
            }
            match result {
                Ok(view) => return Ok((view, state)),
                Err(error) => {
                    state.close().await?;
                    if error
                        .downcast_ref::<StudioError>()
                        .is_some_and(|error| error.reason() == Some("staleCurrentReference"))
                    {
                        continue;
                    }
                    return Err(error);
                }
            }
        }
    }

    pub async fn snapshot(&self, demand: ReadDemand) -> Result<CurrentView> {
        let reader = self.clone();
        self.run(async move { reader.snapshot_inner(demand).await })
            .await
    }

    async fn snapshot_inner(&self, demand: ReadDemand) -> Result<CurrentView> {
        let (view, mut state) = self.baseline(demand, &self.inner.cancel).await?;
        state.close().await?;
        self.check_open()?;
        Ok(view)
    }

    pub async fn page_collection(
        &self,
        reference: CurrentCollectionRef,
        continuation: Option<String>,
        demand: ReadDemand,
    ) -> Result<CurrentCollectionPage> {
        let reader = self.clone();
        self.run(async move {
            reader
                .page_collection_inner(reference, continuation, demand)
                .await
        })
        .await
    }

    async fn page_collection_inner(
        &self,
        reference: CurrentCollectionRef,
        continuation: Option<String>,
        demand: ReadDemand,
    ) -> Result<CurrentCollectionPage> {
        demand.validate(1)?;
        let after = continuation
            .map(|cursor| -> Result<String> {
                ensure!(
                    cursor.len() <= crate::CHAT_BATCH_MAX_BYTES as usize,
                    stale()
                );
                let (saved, after): (CurrentCollectionRef, String) =
                    serde_json::from_str(&cursor).map_err(|_| stale())?;
                ensure!(saved == reference, stale());
                serde_json::from_str::<(i64, String)>(&after).map_err(|_| stale())?;
                Ok(after)
            })
            .transpose()?;
        if reference.collection.starts_with("state:") {
            let resources = self.state_resources(&reference.owner_id).await?;
            let page = resources
                .page(&reference, after.as_deref(), demand, |after| {
                    Ok(serde_json::to_string(&(&reference, after))?)
                })?
                .ok_or_else(stale)?;
            self.check_open()?;
            return Ok(page);
        }
        let current = self.current(&self.inner.cancel).await?;
        ensure!(reference.owner_id == current.owner_id(), stale());
        let result = current_page(&current, &reference, after.as_deref(), demand, |after| {
            Ok(serde_json::to_string(&(&reference, after))?)
        })?;
        self.check_open()?;
        Ok(result)
    }

    async fn state_resources(
        &self,
        owner_id: &str,
    ) -> Result<super::thread_observation::state_resources::StateResources> {
        let slot = self
            .inner
            .runtime
            .thread_observations
            .observation_slot(self.thread_id());
        let (position, _) = slot.capture();
        let resources =
            if let Some(feed) = position.source.filter(|feed| !feed.is_delivery_closed()) {
                ensure!(
                    feed.current_conversation()
                        .is_some_and(|source| source.current.owner_id() == owner_id),
                    stale()
                );
                feed.state_resources()
            } else {
                let thread = self
                    .inner
                    .runtime
                    .read_protocol_thread(self.thread_id())
                    .await?;
                let saved = self
                    .inner
                    .runtime
                    .store
                    .state_for(&thread.workspace_id, self.thread_id())?
                    .load_current()
                    .await?
                    .ok_or_else(stale)?;
                ensure!(saved.saved_runtime_epoch.to_string() == owner_id, stale());
                let snapshot = saved.state.to_paused_snapshot();
                let (resources, _) =
                    super::thread_observation::state_resources::StateResources::project_cold(
                        owner_id.into(),
                        saved.snapshot_revision,
                        self.thread_id(),
                        &snapshot,
                        thread.updated_at,
                        &snapshot.usage_summary,
                    )?;
                resources
            };
        ensure!(slot.is_current(position.epoch), stale());
        self.check_open()?;
        Ok(resources)
    }

    async fn body(
        &self,
        reference: &CurrentContentRef,
        range: &ContentRange,
        cancellation: &CancellationToken,
    ) -> Result<ContentWindow> {
        ensure!(
            range.max_bytes > 0 && range.max_bytes <= crate::CONTENT_WINDOW_MAX_BYTES,
            StudioError::new(
                StudioErrorCode::InvalidArgument,
                "Invalid current body range",
                false
            )
        );
        if reference.domain.starts_with("state:")
            || reference.domain.starts_with("collection:state:")
        {
            let resources = self.state_resources(&reference.owner_id).await?;
            let bytes = resources.body(reference).ok_or_else(stale)?;
            self.check_open()?;
            let start = usize::try_from(range.offset).map_err(|_| stale())?;
            ensure!(start <= bytes.len(), stale());
            let end = start
                .saturating_add(range.max_bytes as usize)
                .min(bytes.len());
            return Ok(ContentWindow {
                offset: range.offset,
                bytes: bytes[start..end].to_vec(),
                generation: reference.generation.clone(),
                available_through: bytes.len() as u64,
                sealed: true,
            });
        }
        let current = self.current(cancellation).await?;
        ensure!(reference.owner_id == current.owner_id(), stale());
        if let Some(collection) = reference.domain.strip_prefix("collection:") {
            let collection_ref = current
                .projection()
                .collections
                .iter()
                .chain(current.projection().interactions.iter())
                .find(|head| {
                    head.collection == collection
                        && head.revision.to_string() == reference.generation
                })
                .ok_or_else(stale)?;
            ensure!(
                collection_ref.owner_id == reference.owner_id && reference.content_key == "entry",
                stale()
            );
            let entry = current
                .entries()
                .get(&(collection.into(), reference.entity_id.clone()))
                .ok_or_else(stale)?;
            let start = usize::try_from(range.offset).map_err(|_| stale())?;
            ensure!(start <= entry.payload.len(), stale());
            let end = start
                .saturating_add(range.max_bytes as usize)
                .min(entry.payload.len());
            return Ok(ContentWindow {
                offset: range.offset,
                bytes: entry.payload[start..end].to_vec(),
                generation: reference.generation.clone(),
                available_through: entry.payload.len() as u64,
                sealed: true,
            });
        }
        let content = current.content(reference).ok_or_else(stale)?;
        let bytes = content
            .content()
            .data
            .range(range.offset, range.max_bytes as usize)?
            .as_bytes()
            .to_vec();
        let sealed = !current.projection().execution_present
            || reference.domain != "entity"
            || current
                .projection()
                .atoms
                .iter()
                .find(|atom| atom.id == reference.entity_id)
                .is_some_and(|atom| {
                    matches!(atom.lifecycle, crate::ChatAtomLifecycle::Terminal { .. })
                });
        Ok(ContentWindow {
            offset: range.offset,
            bytes,
            generation: reference.generation.clone(),
            available_through: content.descriptor.byte_length,
            sealed,
        })
    }

    pub async fn read_body(
        &self,
        reference: CurrentContentRef,
        range: ContentRange,
    ) -> Result<ContentWindow> {
        let reader = self.clone();
        self.run(async move { reader.read_body_inner(reference, range).await })
            .await
    }

    async fn read_body_inner(
        &self,
        reference: CurrentContentRef,
        range: ContentRange,
    ) -> Result<ContentWindow> {
        let window = self.body(&reference, &range, &self.inner.cancel).await?;
        self.check_open()?;
        Ok(window)
    }

    fn changes(&self) -> (watch::Receiver<u64>, Option<CurrentPublicationChanges>) {
        let slot = self
            .inner
            .runtime
            .thread_observations
            .observation_slot(self.thread_id());
        let (position, changed) = slot.capture();
        (
            changed,
            position.source.map(|feed| feed.conversation().progress),
        )
    }

    pub async fn watch(
        &self,
        _after: Option<CurrentRevision>,
        demand: ReadDemand,
    ) -> Result<CurrentWatch> {
        // A new watch cannot prove an old receiver's continuity. Its baseline is always Reset;
        // continuous notifications retain the original assembler's ordered envelopes thereafter.
        let cancel = self.inner.cancel.child_token();
        let reader = self.clone();
        let preparation_cancel = cancel.clone();
        // Subscribe before preparing Reset. A publication in that interval must still wake
        // the forwarder even if it runs after the producer has already become idle.
        let changes = self.changes();
        let (view, state) = self
            .run(async move { reader.baseline(demand, &preparation_cancel).await })
            .await?;
        let (sender, receiver) = mpsc::channel(1);
        let reader = self.clone();
        let task_cancel = cancel.clone();
        let task = self.spawn(async move {
            let result = reader
                .watch_frames(view, state, demand, &sender, &task_cancel, changes)
                .await;
            if let Err(error) = result {
                tokio::select! { biased; _ = task_cancel.cancelled() => {}, _ = sender.send(Err(error)) => {} }
            }
        })?;
        Ok(CurrentWatch {
            receiver: AsyncMutex::new(receiver),
            cancel,
            task: AsyncMutex::new(Some(task)),
        })
    }

    async fn watch_frames(
        &self,
        mut view: CurrentView,
        mut state: ConversationStateFeed,
        demand: ReadDemand,
        sender: &mpsc::Sender<Result<CurrentFrame>>,
        cancel: &CancellationToken,
        changes: (watch::Receiver<u64>, Option<CurrentPublicationChanges>),
    ) -> Result<()> {
        let (mut owner_changed, mut progress) = changes;
        enum Wake {
            Notification(Box<crate::ThreadNotificationEnvelope>),
            Projection,
            Reset,
        }
        let result = async {
            let mut frame = CurrentFrame::Reset { view: Box::new(view.clone()) };
            loop {
                frame.validate_demand(demand)?;
                tokio::select! { biased;
                    _ = cancel.cancelled() => return Ok(()),
                    result = sender.send(Ok(frame)) => if result.is_err() { return Ok(()); },
                }
                loop {
                    let wake = tokio::select! { biased;
                        _ = cancel.cancelled() => return Ok(()),
                        _ = owner_changed.changed() => Wake::Reset,
                        update = state.recv() => match update {
                            Ok(Some(ThreadSubscriptionUpdate::Notification { notification }))
                                if !matches!(notification.notification, ThreadNotification::Lagged { .. }) => Wake::Notification(notification),
                            _ => Wake::Reset,
                        },
                        changed = async {
                            match progress.as_mut() {
                                Some(progress) => progress.changed().await,
                                None => std::future::pending().await,
                            }
                        } => if changed.is_ok() { Wake::Projection } else { Wake::Reset },
                    };
                    let current = if matches!(wake, Wake::Reset) { None } else {
                        match self.current(cancel).await {
                            Ok(current) => Some(current),
                            Err(error) if error.downcast_ref::<StudioError>().is_some_and(|error|
                                error.reason() == Some("staleCurrentReference")) => None,
                            Err(error) => return Err(error),
                        }
                    };
                    let qualified = match current.filter(|current| current.owner_id() == view.revision.owner_id) {
                        Some(current) => match self.metadata_revision(&current) {
                            Ok(revision) => Some((current, revision)),
                            Err(error) if error.downcast_ref::<StudioError>().is_some_and(|error| error.reason() == Some("staleCurrentReference")) => None,
                            Err(error) => return Err(error),
                        },
                        None => None,
                    };
                    if let Some((current, revision)) = qualified {
                        match wake {
                            Wake::Notification(mut notification) => {
                                if matches!(notification.notification, ThreadNotification::InteractionChanged { .. }) {
                                    notification.notification = ThreadNotification::BusinessRefsChanged { references: current.business_refs() };
                                }
                                view.revision.revision = revision;
                                frame = CurrentFrame::Notification { revision: view.revision.clone(), notification };
                            }
                            Wake::Projection => {
                                if current.projection() == &view.projection { continue; }
                                view.projection = current.projection().clone();
                                view.revision.revision = revision;
                                frame = CurrentFrame::Projection {
                                    revision: view.revision.clone(), projection: Box::new(view.projection.clone()),
                                };
                            }
                            Wake::Reset => unreachable!("Reset does not read a current cut"),
                        }
                    } else {
                        state.close().await?;
                        (owner_changed, progress) = self.changes();
                        (view, state) = self.baseline(demand, cancel).await?;
                        frame = CurrentFrame::Reset { view: Box::new(view.clone()) };
                    }
                    break;
                }
            }
        }.await;
        state.close().await?;
        result
    }

    pub async fn watch_body(
        &self,
        reference: CurrentContentRef,
        range: ContentRange,
    ) -> Result<CurrentBodyWatch> {
        let (sender, receiver) = mpsc::channel(1);
        let cancel = self.inner.cancel.child_token();
        let reader = self.clone();
        let task_cancel = cancel.clone();
        let task = self.spawn(async move {
            let (mut owner_changed, mut progress) = reader.changes();
            let mut previous = None;
            loop {
                let window = reader.body(&reference, &range, &task_cancel).await;
                let terminal = window.as_ref().is_ok_and(|window| window.sealed) || window.is_err();
                if previous.as_ref() != window.as_ref().ok() || window.is_err() {
                    previous = window.as_ref().ok().cloned();
                    tokio::select! { biased; _ = task_cancel.cancelled() => break, result = sender.send(window) => { if result.is_err() { break; } } }
                }
                if terminal {
                    break;
                }
                tokio::select! { biased;
                    _ = task_cancel.cancelled() => break,
                    _ = owner_changed.changed() => {},
                    _ = async { match progress.as_mut() { Some(progress) => { let _ = progress.changed().await; }, None => std::future::pending().await } } => {},
                }
            }
        })?;
        Ok(CurrentBodyWatch {
            receiver: AsyncMutex::new(receiver),
            cancel,
            task: AsyncMutex::new(Some(task)),
        })
    }

    pub fn request_close(&self) {
        let _gate = self
            .inner
            .admission
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.inner.cancel.cancel();
        self.inner.tasks.close();
    }

    pub async fn close(&self) -> Result<()> {
        self.request_close();
        self.inner.tasks.wait().await;
        Ok(())
    }
}

pub struct CurrentWatch<T = CurrentFrame> {
    receiver: AsyncMutex<mpsc::Receiver<Result<T>>>,
    cancel: CancellationToken,
    task: AsyncMutex<Option<tokio::task::JoinHandle<()>>>,
}
/// Body subscription name. Methods are the same latest-state watch as `CurrentWatch`.
pub type CurrentBodyWatch = CurrentWatch<ContentWindow>;
impl<T> CurrentWatch<T> {
    pub async fn next(&self) -> Result<Option<T>> {
        tokio::select! { biased;
            _ = self.cancel.cancelled() => Ok(None),
            frame = async { self.receiver.lock().await.recv().await } => frame.transpose(),
        }
    }
    pub fn request_close(&self) {
        self.cancel.cancel();
    }
    pub async fn close(&self) -> Result<()> {
        self.request_close();
        let mut task = self.task.lock().await;
        // Keep the original join handle until it resolves, including if this close waiter is
        // cancelled. A later close must still join that producer rather than report a false ACK.
        let joined = match task.as_mut() {
            Some(task) => task.await.map_err(anyhow::Error::from),
            None => Ok(()),
        };
        task.take();
        drop(task);
        let mut receiver = self.receiver.lock().await;
        receiver.close();
        while receiver.try_recv().is_ok() {}
        joined
    }
}
impl<T> Drop for CurrentWatch<T> {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime_test_support::Environment;
    use pl_core::thread::current::{RuntimeEpoch, ThreadCurrent};

    #[tokio::test]
    async fn a_new_saved_preview_cannot_replace_bytes_behind_a_sealed_cold_reference() -> Result<()>
    {
        use pl_core::thread::{
            current::{SavedToolProgress, SavedToolProgressPart},
            task::{TaskRecord, TaskStatus},
        };
        let mut env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "paused preview")
                .await?;
            let paths = env.runtime.store.registered_session_paths(&thread.id)?;
            env.runtime.shutdown_runtime().await?;
            let epoch = RuntimeEpoch::new();
            let mut current = ThreadCurrent::new(thread.id.clone(), epoch);
            current.snapshot_revision = 1;
            current.state.start_task(TaskRecord {
                id: "task:call".into(),
                parent_call_id: None,
                invocation: None,
                call_id: "call".into(),
                tool_id: "command".into(),
                turn_id: "turn".into(),
                revision: 1,
                status: TaskStatus::Running,
                cancel_requested: false,
                acknowledgement: None,
                started_sequence: None,
            })?;
            current.state.tool_previews.insert(
                "call".into(),
                SavedToolProgress {
                    source_run_id: epoch,
                    version: 1,
                    parts: vec![SavedToolProgressPart {
                        id: "stdout".into(),
                        version: 1,
                        text: "first observed bytes".into(),
                    }],
                },
            );
            tokio::fs::create_dir_all(paths.root()).await?;
            tokio::fs::write(paths.current_file(), serde_json::to_vec(&current)?).await?;
            env.restart().await?;
            let demand = ReadDemand {
                max_items: 64,
                max_bytes: 64 * 1024,
            };
            let reader = env
                .runtime
                .open_current_reader(&thread.id, CURRENT_PROTOCOL_VERSION, demand)
                .await?;
            let view = reader.snapshot(demand).await?;
            assert!(!view.projection.execution_present);
            let reference = view
                .projection
                .atoms
                .first()
                .context("saved tool observation")?
                .contents
                .first()
                .context("saved output body")?
                .reference
                .clone();
            let range = ContentRange {
                offset: 0,
                max_bytes: 1024,
            };
            let first = reader.read_body(reference.clone(), range.clone()).await?;
            assert_eq!(first.bytes, b"first observed bytes");
            assert!(first.sealed);

            current.snapshot_revision = 2;
            let progress = current.state.tool_previews.get_mut("call").unwrap();
            progress.version = 2;
            progress.parts[0].version = 2;
            progress.parts[0].text = "authoritatively replaced bytes".into();
            tokio::fs::write(paths.current_file(), serde_json::to_vec(&current)?).await?;
            let error = reader
                .read_body(reference, range.clone())
                .await
                .unwrap_err();
            assert_eq!(
                error
                    .downcast_ref::<StudioError>()
                    .and_then(StudioError::reason),
                Some("staleCurrentReference")
            );
            let latest = reader.snapshot(demand).await?;
            let reference = latest.projection.atoms[0].contents[0].reference.clone();
            assert_eq!(
                reader.read_body(reference, range).await?.bytes,
                b"authoritatively replaced bytes"
            );
            reader.close().await?;
            assert!(
                env.root_provider.recorded().is_empty(),
                "observing paused data executed a provider request"
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn cold_current_migrates_v1_stream_before_paused_projection() -> Result<()> {
        use pl_core::{
            context::OpaquePayload,
            thread::{
                UsageCost,
                current::{CurrentModelCall, SavedModelPhase},
            },
        };
        use pl_model::completion::{
            MODEL_STREAM_CURRENT_FORMAT, MODEL_STREAM_CURRENT_VERSION, ModelCallIdentity,
            ModelStreamCurrent,
        };
        use serde_json::json;

        const ATTEMPT: &str = "saved-attempt";
        const PARTIAL: &str = r#"{"path":"src/ma"#;
        let generation = |number: u32, text: &str, tokens: u64| {
            json!({
                "attemptId": ATTEMPT, "generation": number, "state": {"kind":"open"},
                "reportedModelIsTerminal": false,
                "contentParts": [{
                    "blockId": "text", "contentIndex": 0, "kind": "outputText", "text": text,
                    "identity": {"aggregate":{"channel":"text"}}
                }],
                "blocks": [], "reasoningSummaryParts": [], "rawReasoningParts": [],
                "toolInputs": [], "toolCalls": [], "toolCallCallers": {}, "callBindings": [],
                "responsesContextItems": [], "replay": {"pendingItems": [], "items": []},
                "presentationItems": [], "members": [], "presentationStates": {},
                "finalUsage": {"inputTokens":tokens,"totalTokens":tokens}, "usageIsTerminal": true
            })
        };
        let mut oldest = generation(0, "oldest body", 3);
        oldest["state"] = json!({"kind":"failed","message":"first disconnect"});
        let mut earlier = generation(1, "earlier body", 5);
        earlier["state"] = json!({"kind":"failed","message":"second disconnect"});
        earlier["previousGenerations"] = json!([oldest]);
        let mut legacy = generation(2, "paused body", 7);
        legacy["previousGenerations"] = json!([earlier]);
        let binding = ModelCallIdentity::new(ATTEMPT, "call_0", "fc_0");
        legacy["toolInputs"] = json!([{
            "itemId":"fc_0", "providerCallId":"call_0", "callId":&binding.call_id,
            "name":"read_file", "kind":"function", "input":PARTIAL, "phase":"streaming",
            "streamAliases":[], "itemAliases":[], "callAliases":[]
        }]);
        legacy["callBindings"] = json!([binding]);

        let mut env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "legacy model stream")
                .await?;
            let paths = env.runtime.store.registered_session_paths(&thread.id)?;
            env.runtime.shutdown_runtime().await?;
            let epoch = RuntimeEpoch::new();
            let mut saved = ThreadCurrent::new(thread.id.clone(), epoch);
            saved.snapshot_revision = 1;
            saved.state.usage_summary.totals.inference_count = 4;
            saved
                .state
                .usage_summary
                .pricing
                .estimated_costs
                .push(UsageCost {
                    currency: "USD".into(),
                    amount: 0.375,
                });
            saved.model_call = Some(CurrentModelCall {
                source_run_id: epoch,
                source_execution_id: "saved-execution".into(),
                source_turn_id: "saved-turn".into(),
                source_attempt_id: ATTEMPT.into(),
                tools: Arc::from([]),
                tool_call_mode: pl_core::model::ToolCallMode::Sequential,
                solo_tool_ids: Arc::from([]),
                prepared_parameters: None,
                phase: SavedModelPhase::Streaming {
                    stream: OpaquePayload::new(MODEL_STREAM_CURRENT_FORMAT, 1, legacy.to_string())?,
                },
            });
            let original = serde_json::to_vec(&saved)?;
            let broken_history = b"Current recovery must not open History";
            tokio::fs::create_dir_all(paths.root()).await?;
            tokio::fs::write(paths.current_file(), &original).await?;
            tokio::fs::write(paths.history_database(), broken_history).await?;
            env.restart().await?;

            let demand = ReadDemand {
                max_items: 64,
                max_bytes: 64 * 1024,
            };
            let reader = env
                .runtime
                .open_current_reader(&thread.id, CURRENT_PROTOCOL_VERSION, demand)
                .await?;
            let prepared = reader.saved_current().await?;
            assert_eq!(prepared.state.usage_summary, saved.state.usage_summary);
            assert!(prepared.state.tasks.is_empty() && prepared.state.deliveries.is_empty());
            let call = prepared.model_call.as_ref().context("saved model call")?;
            assert_eq!(
                (call.source_attempt_id.as_str(), call.source_run_id),
                (ATTEMPT, epoch)
            );
            let SavedModelPhase::Streaming { stream } = &call.phase else {
                anyhow::bail!("expected paused stream material")
            };
            assert_eq!(stream.version(), MODEL_STREAM_CURRENT_VERSION);
            let stream = ModelStreamCurrent::decode(stream)?;
            assert_eq!(stream.tool_inputs[0].input, PARTIAL);
            assert!(stream.tool_calls.is_empty());
            let [earlier] = stream.previous_generations.as_slice() else {
                anyhow::bail!("expected earlier generation")
            };
            let [oldest] = earlier.previous_generations.as_slice() else {
                anyhow::bail!("expected oldest generation")
            };
            for (actual, number, text, tokens) in [
                (&stream, 2, "paused body", 7),
                (earlier, 1, "earlier body", 5),
                (oldest, 0, "oldest body", 3),
            ] {
                assert_eq!(
                    (actual.attempt_id.as_str(), actual.generation),
                    (ATTEMPT, number)
                );
                assert_eq!(actual.content_parts[0].text, text);
                assert_eq!(
                    actual
                        .final_usage
                        .as_ref()
                        .and_then(|usage| usage.total_tokens),
                    Some(tokens)
                );
                assert!(!actual.usage_is_terminal && actual.settlement.is_none());
            }

            let view = reader.snapshot(demand).await?;
            assert!(!view.projection.execution_present && view.projection.active.is_none());
            let tool = view
                .projection
                .atoms
                .iter()
                .find(|atom| atom.tool.is_some())
                .context("paused tool preview")?;
            assert!(matches!(
                tool.lifecycle,
                crate::ChatAtomLifecycle::Active {
                    status: crate::ChatActiveStatus::Waiting,
                    ..
                }
            ));
            let mut bodies = Vec::new();
            for atom in &view.projection.atoms {
                for content in &atom.contents {
                    let window = reader
                        .read_body(
                            content.reference.clone(),
                            ContentRange {
                                offset: 0,
                                max_bytes: 1024,
                            },
                        )
                        .await?;
                    bodies.push(String::from_utf8(window.bytes)?);
                }
            }
            for expected in ["paused body", "earlier body", PARTIAL] {
                assert!(
                    bodies.iter().any(|body| body == expected),
                    "missing paused body {expected:?}"
                );
            }
            assert_eq!(tokio::fs::read(paths.current_file()).await?, original);

            let mut broken = legacy.clone();
            broken["previousGenerations"][0]["finalUsage"]["totalTokens"] = json!("corrupt");
            for (version, body, cause) in [
                (99, &legacy, "unsupported model stream current version"),
                (1, &broken, "invalid type"),
            ] {
                saved.model_call.as_mut().unwrap().phase = SavedModelPhase::Streaming {
                    stream: OpaquePayload::new(
                        MODEL_STREAM_CURRENT_FORMAT,
                        version,
                        body.to_string(),
                    )?,
                };
                let rejected = serde_json::to_vec(&saved)?;
                tokio::fs::write(paths.current_file(), &rejected).await?;
                let error = reader.saved_current().await.unwrap_err();
                assert!(format!("{error:#}").contains(cause), "{error:#}");
                assert!(reader.snapshot(demand).await.is_err());
                assert_eq!(tokio::fs::read(paths.current_file()).await?, rejected);
            }
            assert_eq!(
                tokio::fs::read(paths.history_database()).await?,
                broken_history
            );
            reader.close().await?;
            assert!(env.root_provider.recorded().is_empty());
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn cold_current_and_its_body_survive_broken_history_and_close_joins_metadata_watch()
    -> Result<()> {
        let mut env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "independent current")
                .await?;
            let paths = env.runtime.store.registered_session_paths(&thread.id)?;
            env.runtime.shutdown_runtime().await?;
            let mut current = ThreadCurrent::new(thread.id.clone(), RuntimeEpoch::new());
            // Keep the plan within its 64 KiB domain limit while still exceeding the 2 KiB
            // State inline threshold, so the test exercises deferred Current bodies.
            let document = format!(
                "# Approved plan\n\n{}",
                "已批准的计划正文\n".repeat(2400)
            );
            let plan = crate::plan_tool::AgentSessionPlanState::with_document(
                crate::plan_tool::PlanState::Approved,
                3,
                document.clone(),
                0,
            );
            current.state.extensions.insert(
                crate::plan_tool::PLAN_EXTENSION.into(),
                pl_core::thread::extensions::ExtensionRecord {
                    revision: 3,
                    payload: crate::plan_tool::encode_plan_state(&plan)?,
                },
            );
            let original = serde_json::to_vec(&current)?;
            tokio::fs::create_dir_all(paths.root()).await?;
            tokio::fs::write(paths.current_file(), &original).await?;
            let broken_history = b"deliberately unavailable history; current must not open this";
            tokio::fs::write(paths.history_database(), broken_history).await?;
            env.restart().await?;

            let demand = ReadDemand {
                max_items: 64,
                max_bytes: 64 * 1024,
            };
            let reader = env
                .runtime
                .open_current_reader(&thread.id, CURRENT_PROTOCOL_VERSION, demand)
                .await?;
            let view = reader.snapshot(demand).await?;
            assert!(
                serde_json::to_vec(&CurrentFrame::Reset {
                    view: Box::new(view.clone())
                })?
                .len()
                    <= demand.max_bytes as usize
            );
            let runtime = view.state.runtime.as_ref().context("saved runtime")?;
            assert!(runtime.plan.is_none());
            let deferred = runtime
                .deferred
                .iter()
                .find(|head| matches!(head, crate::CurrentStateField::Body { field, .. } if field == "plan"))
                .context("large State plan must explicitly defer its complete value")?;
            let crate::CurrentStateField::Body { reference, byte_length, .. } = deferred else { panic!("plan is a body"); };
            let mut bytes = Vec::new();
            while (bytes.len() as u64) < *byte_length {
                let window = reader
                    .read_body(
                        reference.clone(),
                        ContentRange {
                            offset: bytes.len() as u64,
                            max_bytes: 64 * 1024,
                        },
                    )
                    .await?;
                assert!(window.sealed && !window.bytes.is_empty());
                bytes.extend(window.bytes);
            }
            assert_eq!(
                serde_json::from_slice::<serde_json::Value>(&bytes)?,
                serde_json::to_value(crate::plan_tool::AgentSessionPlanRuntimeSnapshot::from(&plan))?
            );
            // Closing a temporary State baseline must not close its parent Current reader.
            assert_eq!(reader.snapshot(demand).await?.revision, view.revision);
            assert_eq!(
                view.revision.owner_id,
                current.saved_runtime_epoch.to_string()
            );
            assert!(!view.projection.execution_present);
            let reference = view
                .projection
                .plan
                .context("saved plan head")?
                .document
                .context("saved document reference")?;
            let window = reader
                .read_body(
                    reference.clone(),
                    ContentRange {
                        offset: 7,
                        max_bytes: 37,
                    },
                )
                .await?;
            assert_eq!(window.bytes, document.as_bytes()[7..44]);
            assert!(window.sealed);
            let mut wrong_owner = reference;
            wrong_owner.owner_id = RuntimeEpoch::new().to_string();
            let error = reader
                .read_body(
                    wrong_owner,
                    ContentRange {
                        offset: 0,
                        max_bytes: 1,
                    },
                )
                .await
                .unwrap_err();
            assert_eq!(
                error
                    .downcast_ref::<StudioError>()
                    .and_then(StudioError::reason),
                Some("staleCurrentReference")
            );

            let watch = reader.watch(Some(view.revision), demand).await?;
            assert!(matches!(
                watch.next().await?,
                Some(CurrentFrame::Reset { .. })
            ));
            tokio::time::timeout(std::time::Duration::from_secs(1), reader.close()).await??;
            assert!(watch.next().await?.is_none());
            watch.close().await?;
            assert_eq!(reader.inner.tasks.len(), 0);
            assert_eq!(tokio::fs::read(paths.current_file()).await?, original);
            assert_eq!(
                tokio::fs::read(paths.history_database()).await?,
                broken_history
            );
            assert!(env.root_provider.recorded().is_empty());
            Ok(())
        }
        .await;
        env.finish(result).await
    }
    #[tokio::test]
    async fn publication_after_reset_preparation_is_delivered_when_the_forwarder_starts_late()
    -> Result<()> {
        use crate::runtime_test_support::{
            self as support, current_demand, held_reply, prompt_step, reached,
        };
        let stage = pl_provider_fixture::ReplyStage::new();
        let env = Environment::new(
            vec![prompt_step(
                "late-forwarder",
                0,
                held_reply(&stage, "late-forwarder"),
            )],
            vec![],
        )
        .await?;
        let result = async {
            let started = env
                .start(crate::ThreadWorkspaceMode::Local, "late-forwarder")
                .await?;
            let id = &started.thread.id;
            reached(&stage).await?;
            let reader = env
                .runtime
                .open_current_reader(id, CURRENT_PROTOCOL_VERSION, current_demand())
                .await?;
            let cancel = reader.inner.cancel.child_token();
            let changes = reader.changes();
            let mut producer = changes
                .1
                .as_ref()
                .context("original publication watch")?
                .clone();
            let (view, state) = reader.baseline(current_demand(), &cancel).await?;
            ensure!(view.projection.execution_present);
            stage.release();
            support::completed_prompt(&env.runtime, id, "late-forwarder").await?;
            tokio::time::timeout(support::integration_test_deadline()?, async {
                loop {
                    if reader.current(&cancel).await?.projection().active.is_none() {
                        return Ok::<_, anyhow::Error>(());
                    }
                    producer.changed().await?;
                }
            })
            .await
            .context("Current producer did not become idle")??;
            // Start only after the real final publication. Its pending progress wake must survive
            // even though no more model input, output, or metadata publication will be produced.
            let (sender, mut receiver) = mpsc::channel(8);
            let forwarding_reader = reader.clone();
            let forwarding_cancel = cancel.clone();
            let forwarding = tokio::spawn(async move {
                forwarding_reader
                    .watch_frames(
                        view,
                        state,
                        current_demand(),
                        &sender,
                        &forwarding_cancel,
                        changes,
                    )
                    .await
            });
            let observed = tokio::time::timeout(support::integration_test_deadline()?, async {
                while let Some(frame) = receiver.recv().await {
                    if let CurrentFrame::Projection { projection, .. } = frame?
                        && projection.active.is_none()
                    {
                        return Ok::<_, anyhow::Error>(());
                    }
                }
                anyhow::bail!("Current forwarder ended before delivering the final projection")
            })
            .await
            .context("final Current projection wake was lost");
            cancel.cancel();
            let joined = forwarding.await.context("join delayed Current forwarder")?;
            reader.close().await?;
            observed??;
            joined?;
            Ok(())
        }
        .await;
        stage.release();
        env.finish(result).await
    }
}
