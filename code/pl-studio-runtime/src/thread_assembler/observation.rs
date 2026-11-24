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
pub(super) struct AssemblyObservation(
    Arc<Observe>,
    Arc<Drain>,
    Option<Arc<CurrentTurnLookup>>,
    Arc<BeforeClose>,
    Arc<Synchronize>,
);
impl std::fmt::Debug for AssemblyObservation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AssemblyObservation")
    }
}
impl SessionRuntime {
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
        if state.closing
            || !state.entries.is_empty()
            || !state.creating.is_empty()
            || state.observation.is_some()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        state.observation = Some(AssemblyObservation(
            Arc::new(observe),
            Arc::new(drain),
            current_turn,
            Arc::new(before_close),
            Arc::new(synchronize),
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
            (observer.0)(id.to_owned(), thread.clone(), resources);
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
            let result = (observer.1)(id.to_owned(), purpose).await;
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
        (observer.4)(id.to_owned()).await
    }

    fn execution_observation_was_not_installed(&self, id: &str) -> bool {
        let state = self.0.state();
        matches!(
            state
                .entries
                .get(id)
                .and_then(|entry| entry.native().ok()?.close_storage.as_ref()),
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
        let observed =
            observer.map(|observer| (observer.3)(id.to_owned(), thread.clone(), purpose));
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
        let lookup = self.0.state().observation.as_ref()?.2.clone()?;
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
            if state.closing {
                return Ok(ParentMessageDelivery::Skipped(ParentMessageSkip::Closing));
            }
            Some(
                state
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

#[cfg(test)]
mod storage_fault_tests {

    use super::*;
    use crate::studio::storage_fault_test_support::{
        HistoryChannel, ThreadStorageSink, register_test_thread, spawn_live_projection_for_thread,
    };
    use crate::studio::{StudioStore, ThreadStorageBinding};
    use anyhow::Result;
    use pl_core::{
        context::{AgentMessageKind, ContextContent, OpaquePayload},
        thread::{TurnOutcome, TurnRecord, TurnState, history_sink::HistorySinkHandle},
    };
    use pl_tool::collaboration::thread::WorkspaceRelease;
    use std::{
        collections::BTreeMap,
        sync::{
            Arc, Mutex,
            atomic::{AtomicBool, Ordering},
        },
    };

    struct SavedMessageIdentity {
        sequence: u64,
        digest: String,
    }
    async fn current_message_identity(
        store: &StudioStore,
        thread: &str,
        message: &str,
    ) -> Result<Option<SavedMessageIdentity>> {
        let paths = store.registered_session_paths(thread)?;
        let Some(current) = store
            .state_for(paths.workspace_id(), thread)?
            .load_current()
            .await?
        else {
            return Ok(None);
        };
        Ok(current
            .state
            .inbox
            .iter()
            .find(|record| record.message.id == message)
            .map(|record| SavedMessageIdentity {
                sequence: record.sequence,
                digest: record.message.digest(),
            })
            .or_else(|| {
                current
                    .state
                    .consumed_message_identities
                    .iter()
                    .find(|identity| identity.id == message)
                    .map(|identity| SavedMessageIdentity {
                        sequence: identity.sequence,
                        digest: identity.digest.clone(),
                    })
            }))
    }
    async fn history_parent_report(
        history: &crate::history::HistoryStore,
        thread: &str,
        terminal: u64,
    ) -> Result<Option<pl_core::thread::inbox::ThreadMessage>> {
        let reader = history.reader();
        let id = crate::studio::agent_close::terminal_report_id(thread, terminal);
        let event = match reader
            .read_event(
                format!("parent_report:{id}"),
                crate::history::HistoryDemand {
                    max_rows: 1,
                    max_bytes: 64 * 1024,
                },
            )
            .await
        {
            Ok(event) => event,
            Err(crate::history::HistoryError::NotFound(_)) => {
                reader.close().await;
                return Ok(None);
            }
            Err(error) => {
                reader.close().await;
                return Err(error.into());
            }
        };
        let bytes = crate::history::read_event_body_bytes(&reader, &event, "business_fact", None)
            .await?
            .context("original report payload")?;
        reader.close().await;
        let payload: OpaquePayload = serde_json::from_slice(&bytes)?;
        Ok(Some(serde_json::from_str(payload.content())?))
    }

    #[derive(Clone)]
    struct ObservedOwner {
        thread: ThreadHandle,
        channel: Arc<HistoryChannel>,
        projection: Arc<tokio::sync::Mutex<ProjectionTask>>,
    }
    struct ProjectionTask {
        task: Option<tokio::task::JoinHandle<()>>,
        failure: Option<Arc<tokio::task::JoinError>>,
    }
    type LiveOwners = Arc<Mutex<BTreeMap<String, ObservedOwner>>>;

    fn storage_error(error: impl Into<anyhow::Error>) -> ThreadAssemblyError {
        ThreadAssemblyError::Resource {
            operation: "storage fault fixture barrier",
            source: error.into().into_boxed_dyn_error(),
        }
    }

    fn barrier(
        owners: LiveOwners,
        id: String,
    ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>> {
        Box::pin(async move {
            let owner = owners
                .lock()
                .unwrap()
                .get(&id)
                .cloned()
                .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
            let through = owner.thread.snapshot().commit_sequence;
            let mut status = owner.channel.subscribe();
            loop {
                let current = status.borrow_and_update().clone();
                if current.committed_sequence >= through {
                    return Ok(());
                }
                if let Some(error) = current.error {
                    return Err(storage_error(anyhow::anyhow!(error)));
                }
                status.changed().await.map_err(storage_error)?;
            }
        })
    }

    async fn drain(
        owners: LiveOwners,
        id: String,
        fail_after_writer: bool,
    ) -> Result<(), ThreadAssemblyError> {
        let owner = owners
            .lock()
            .unwrap()
            .get(&id)
            .cloned()
            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
        assert_eq!(owner.thread.snapshot().lifecycle, ThreadLifecycle::Closed);
        barrier(owners.clone(), id.clone()).await?;
        owner.channel.stop_and_join().await.map_err(storage_error)?;
        let mut projection = owner.projection.lock().await;
        if let Some(task) = projection.task.as_mut() {
            let result = task.await;
            projection.task = None;
            if let Err(error) = result {
                projection.failure = Some(Arc::new(error));
            }
        }
        if let Some(error) = projection.failure.clone() {
            return Err(storage_error(anyhow::Error::new(error)));
        }
        drop(projection);
        if fail_after_writer {
            return Err(storage_error(anyhow::anyhow!(
                "injected drain failure after writer detach"
            )));
        }
        let mut owners = owners.lock().unwrap();
        if owners
            .get(&id)
            .is_some_and(|current| Arc::ptr_eq(&current.projection, &owner.projection))
        {
            owners.remove(&id);
        }
        Ok(())
    }

    #[derive(Debug)]
    struct ResourceIo(Arc<Mutex<Vec<(String, WorkspaceRelease)>>>);
    impl StudioChildFactory for ResourceIo {
        type Admission = ();

        async fn admit(
            &self,
            _: &str,
            _: crate::DelegationSettings,
            _: Option<crate::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }

        async fn prepare(
            &self,
            _: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            Err(ThreadAssemblyError::Identity(
                "storage fixture does not prepare workspaces".into(),
            ))
        }
        async fn close_published(
            &self,
            id: &str,
            disposition: WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            self.0.lock().unwrap().push((id.into(), disposition));
            Ok(())
        }
        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&WorkspaceUsageLease>,
            _: WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }
    }

    struct Fixture {
        owner: SessionRuntime,
        store: StudioStore,
        live: LiveOwners,
        closes: Arc<Mutex<Vec<(String, WorkspaceRelease)>>>,
        fail_drain: Arc<AtomicBool>,
        fail_drain_after_writer: Arc<AtomicBool>,
    }
    impl Fixture {
        fn new(store: StudioStore) -> Result<Self> {
            let owner = SessionRuntime::open(crate::SessionId::new("parent")?);
            let live = LiveOwners::default();
            let draining = live.clone();
            let syncing = live.clone();
            let observed = live.clone();
            let observing = store.clone();
            let closes = Arc::new(Mutex::new(Vec::new()));
            let fail_drain = Arc::new(AtomicBool::new(false));
            let drain_fault = fail_drain.clone();
            let fail_drain_after_writer = Arc::new(AtomicBool::new(false));
            let late_drain_fault = fail_drain_after_writer.clone();
            owner.set_child_factory(ResourceIo(closes.clone()))?;
            owner.observe_assembly(
                move |id, thread, _| {
                    let projection = spawn_live_projection_for_thread(observing.clone(), &id);
                    let channel = observing.thread_persistence().history_channel(&id);
                    observed.lock().unwrap().insert(
                        id,
                        ObservedOwner {
                            thread,
                            channel,
                            projection: Arc::new(tokio::sync::Mutex::new(ProjectionTask {
                                task: Some(projection),
                                failure: None,
                            })),
                        },
                    );
                },
                move |id, _purpose| {
                    let owners = draining.clone();
                    let fault = drain_fault.clone();
                    let late_fault = late_drain_fault.clone();
                    Box::pin(async move {
                        if id == "parent" && fault.load(Ordering::SeqCst) {
                            return Err(storage_error(anyhow::anyhow!(
                                "injected receiver drain failure"
                            )));
                        }
                        let fail_after_writer = id == "parent" && late_fault.load(Ordering::SeqCst);
                        drain(owners, id, fail_after_writer).await
                    })
                },
                None,
                |_, _, _| Box::pin(async { Ok(()) }),
                move |id| {
                    let owners = syncing.clone();
                    Box::pin(async move { barrier(owners, id).await })
                },
            )?;
            Ok(Self {
                owner,
                store,
                live,
                closes,
                fail_drain,
                fail_drain_after_writer,
            })
        }

        fn protocol(id: &str, parent: Option<&str>) -> crate::Thread {
            let mut thread = crate::Thread::placeholder(id);
            thread.workspace_id = "project-test".into();
            thread.agent_path = id.into();
            thread.parent_thread_id = parent.map(str::to_owned);
            thread.root_thread_id = parent.unwrap_or(id).into();
            thread
        }

        fn activation(&self, id: &str, parent: Option<&str>) -> ThreadActivation {
            let mut activation = ThreadActivation::native_test(id, parent);
            activation.agent.session_id = self.owner.id().clone();
            activation
        }

        async fn add(&self, id: &str, parent: Option<&str>) -> Result<ThreadHandle> {
            self.add_with_workspace(id, parent, None).await
        }

        async fn add_with_workspace(
            &self,
            id: &str,
            parent: Option<&str>,
            workspace: Option<&std::path::Path>,
        ) -> Result<ThreadHandle> {
            let mut protocol = Self::protocol(id, parent);
            if let Some(workspace) = workspace {
                protocol.workspace_path = workspace.to_string_lossy().into_owned();
            }
            register_test_thread(&self.store, &protocol).await?;
            let sink = ThreadStorageSink::new(self.store.clone(), protocol.clone()).await?;
            let thread = ThreadHandle::start_current(id.into(), None)?;
            thread
                .attach_history(HistorySinkHandle::new(sink.clone()))
                .await?;
            let channel = self.store.thread_persistence().history_channel(id);
            let conversation = self
                .store
                .conversation_store_for(&protocol.workspace_id, id)
                .await?;
            conversation.attach_current(thread.clone()).await?;
            let binding = Arc::new(ThreadStorageBinding::new(sink, channel, conversation));
            let activation = self.activation(id, parent);
            self.owner.0.state().insert_entry(
                id.into(),
                crate::session::AgentInstance {
                    identity: activation.agent,
                    binding: activation.binding,
                    runtime: crate::session::AgentRuntime::Native(Box::new(
                        crate::session::NativeThreadRuntime {
                            resources: Arc::new(crate::session::NativeResources::default()),
                            purpose: super::super::EntryPurpose::Execution,
                            workspace_usage: None,
                            thread: thread.clone(),
                            parent_id: parent.map(str::to_owned),
                            ready: true,
                            incarnation: Arc::new(()),
                            execution: pl_core::thread::input::InputDriverOptions {
                                max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                                    std::num::NonZeroU32::new(1).unwrap(),
                                ),
                            },
                            cleanup: Default::default(),
                            close_storage: Some(CloseStorage::Attached(binding)),
                            published_resources_closed: false,
                            workspace_disposition: None,
                        },
                    )),
                },
            );
            self.owner.publish_observation(id, &thread);
            Ok(thread)
        }

        async fn stop_writers(&self) -> Result<()> {
            let owners = self
                .live
                .lock()
                .unwrap()
                .iter()
                .map(|(id, owner)| (id.clone(), owner.clone()))
                .collect::<Vec<_>>();
            for (id, owner) in owners {
                let through = owner.channel.handoff_ticket();
                owner.channel.await_handoff_durable(&id, through).await?;
                owner.channel.stop_and_join().await?;
                let mut projection = owner.projection.lock().await;
                if let Some(task) = projection.task.as_mut() {
                    let result = task.await;
                    projection.task = None;
                    result?;
                }
                if let Some(error) = projection.failure.clone() {
                    return Err(anyhow::Error::new(error));
                }
                drop(projection);
                let mut owners = self.live.lock().unwrap();
                if owners
                    .get(&id)
                    .is_some_and(|current| Arc::ptr_eq(&current.projection, &owner.projection))
                {
                    owners.remove(&id);
                }
            }
            Ok(())
        }
    }

    /// Real current publication rejection leaves the close owner registered; retry must use the same
    /// request authorization while an ordinary close still cannot consume explicit Cleanup.
    #[tokio::test]
    async fn cancelled_unpublished_cleanup_keeps_the_real_preparer_until_disposal_joins()
    -> Result<()> {
        #[derive(Debug)]
        struct DelayedDisposal {
            factory: crate::studio::StudioThreadFactory,
            entered: tokio::sync::watch::Sender<bool>,
            release: Arc<tokio::sync::Semaphore>,
        }
        impl StudioChildFactory for DelayedDisposal {
            type Admission = ();

            async fn admit(
                &self,
                _: &str,
                _: crate::DelegationSettings,
                _: Option<crate::NewThreadModelRoute>,
            ) -> Result<(), ThreadAssemblyError> {
                Ok(())
            }

            async fn prepare(
                &self,
                _: ChildThreadRequest,
                _: (),
            ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
                Err(ThreadAssemblyError::Closed)
            }
            async fn discard_unpublished(
                &self,
                id: &str,
                usage: Option<&WorkspaceUsageLease>,
                disposition: WorkspaceRelease,
            ) -> Result<(), ThreadAssemblyError> {
                self.entered.send_replace(true);
                let _permit = self.release.acquire().await.map_err(storage_error)?;
                super::super::StudioChildResources::discard_unpublished(
                    &self.factory,
                    id,
                    usage,
                    disposition,
                )
                .await
            }
        }
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let resources = crate::studio::storage_fault_test_support::close_factory(&store)?;
        let root = temp.path().join("shared-root");
        tokio::fs::create_dir_all(&root).await?;
        let preparation = resources
            .unpublished_workspace("unpublished-directory", &root)
            .await?;
        let owner = SessionRuntime::default();
        let (entered, mut observed) = tokio::sync::watch::channel(false);
        let release = Arc::new(tokio::sync::Semaphore::new(0));
        owner.0.state().unpublished_children.insert(
            "unpublished-directory".into(),
            super::super::child_resources::UnpublishedChild {
                retirement: Default::default(),
                workspace: preparation,
                disposal: Default::default(),
                parent: "parent".into(),
                cleanup: Default::default(),
                factory: super::super::children::ChildFactory::new(DelayedDisposal {
                    factory: resources.factory.clone(),
                    entered,
                    release: release.clone(),
                }),
            },
        );
        let caller_owner = owner.clone();
        let caller = tokio::spawn(async move {
            caller_owner
                .discard_unpublished_child("unpublished-directory")
                .await
        });
        while !*observed.borrow_and_update() {
            observed.changed().await?;
        }
        caller.abort();
        assert!(caller.await.unwrap_err().is_cancelled());
        let files =
            root.join(pl_tool::workspace::SessionFiles::new("unpublished-directory").root());
        assert!(resources.workspace_is_busy("unpublished-directory"));
        assert!(tokio::fs::try_exists(files.join("scratch/prepared")).await?);
        assert!(
            owner
                .0
                .state()
                .unpublished_children
                .contains_key("unpublished-directory")
        );
        release.add_permits(1);
        owner
            .discard_unpublished_child("unpublished-directory")
            .await?;
        assert!(!resources.workspace_is_busy("unpublished-directory"));
        assert!(
            !owner
                .0
                .state()
                .unpublished_children
                .contains_key("unpublished-directory")
        );
        assert!(!tokio::fs::try_exists(&files).await?);
        assert!(
            tokio::fs::try_exists(&root).await?,
            "shared root is never the removal target"
        );
        resources.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn sealed_cleanup_cannot_consume_the_preserve_disposition() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let fixture = Fixture::new(store.clone())?;
        fixture.add("parent", None).await?;
        let child = fixture.add("child", Some("parent")).await?;
        crate::studio::agent_close::commit(&child).await?;
        fixture
            .owner
            .freeze_agent_close_disposition("child", WorkspaceRelease::Preserve)?;
        let targets = vec![(1, "child".to_owned())];
        let seal = fixture
            .owner
            .seal_agent_close(&targets, WorkspaceRelease::Preserve)
            .await?;
        assert!(
            fixture
                .owner
                .seal_agent_close(&targets, WorkspaceRelease::Cleanup)
                .await
                .is_err()
        );
        drop(seal);
        fixture.owner.close("child").await?;
        assert_eq!(
            *fixture.closes.lock().unwrap(),
            vec![("child".into(), WorkspaceRelease::Preserve)]
        );
        assert!(fixture.owner.close_session().await.is_empty());
        fixture.stop_writers().await?;
        Ok(())
    }

    mod archive_scope {
        //! The new archive scope still consumes the real core/writer/projection close barriers.
        use super::*;

        #[tokio::test]
        async fn archive_scope_keeps_the_published_owner_until_writer_and_observation_ack()
        -> Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let fixture = Fixture::new(store.clone())?;
            fixture.add("parent", None).await?;
            fixture.add("child", Some("parent")).await?;
            let scope = fixture.owner.seal_archive_scope(&["parent".into()])?;
            fixture.owner.drain_archive_preparations(&scope).await?;
            assert!(
                fixture.owner.observed_thread("child").is_some(),
                "draining preparation is not a published-resource close ACK"
            );
            fixture
                .fail_drain_after_writer
                .store(true, Ordering::SeqCst);
            assert!(fixture.owner.close_tree("parent", &[]).await.is_err());
            assert!(fixture.owner.observed_thread("parent").is_some());
            assert!(
                fixture
                    .closes
                    .lock()
                    .unwrap()
                    .iter()
                    .all(|(_, release)| *release == WorkspaceRelease::Preserve)
            );
            fixture
                .fail_drain_after_writer
                .store(false, Ordering::SeqCst);
            fixture.owner.close_tree("parent", &[]).await?;
            assert!(fixture.owner.observed_thread("parent").is_none());
            assert!(fixture.owner.observed_thread("child").is_none());
            let current = store
                .state_for("project-test", "parent")?
                .load_current()
                .await?
                .context("durable closed current after observation ACK retry")?;
            assert_eq!(current.state.lifecycle, ThreadLifecycle::Closed);
            fixture.stop_writers().await?;
            Ok(())
        }
    }

    mod cold_parent_report {
        //! Recovery starts with a genuinely cold parent, not a pre-added executable fixture Entry.
        use super::*;
        use crate::studio::storage_fault_test_support::{close_factory, save_terminal_report};
        use crate::thread_assembler::EntryPurpose;
        use crate::thread_assembler::close_storage::{AttachmentAckGate, CloseStorage};

        /// A fixed, contract-valid terminal report, frozen once for both payload and context. Its Turn
        /// matches save_terminal_report; later checkpoints must never rebuild this original evidence.
        fn frozen_report_body(
            child: &crate::Thread,
            sequence: u64,
            evidence: &str,
        ) -> Result<String> {
            let turn = TurnRecord {
                turn_id: "original-terminal-turn".into(),
                input_id: None,
                state: TurnState::Finished(TurnOutcome::Completed),
                model_steps: 0,
                elapsed_ms: None,
            };
            Ok(serde_json::to_string(&serde_json::json!({
                "childId": child.id,
                "commitSequence": sequence,
                "turn": turn,
                "message": evidence,
                "messages": [],
                "runningTasks": [],
                "pendingInteractions": [],
                "permissions": [],
            }))?)
        }

        /// Only the environment is synthetic: activation opens the real model session, attaches the real
        /// history sink and publishes through the ordinary assembler, not Fixture::add.
        struct ReactivationFactory(StudioStore);
        impl std::fmt::Debug for ReactivationFactory {
            fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("ReactivationFactory")
            }
        }
        impl StudioActivationFactory for ReactivationFactory {
            async fn prepare_root(
                &self,
                identity: &ThreadActivation,
            ) -> Result<
                (
                    crate::DelegationSettings,
                    Option<pl_core::thread::current::ThreadCurrent>,
                ),
                ThreadAssemblyError,
            > {
                let paths = self
                    .0
                    .registered_session_paths(identity.id())
                    .map_err(storage_error)?;
                let current = self
                    .0
                    .state_for(paths.workspace_id(), identity.id())
                    .map_err(storage_error)?
                    .load_current()
                    .await
                    .map_err(storage_error)?
                    .ok_or_else(|| ThreadAssemblyError::Identity(identity.id().to_owned()))?;
                let delegation =
                    crate::studio::delegation::saved(&current.state.to_paused_snapshot())
                        .map_err(storage_error)?
                        .ok_or_else(|| ThreadAssemblyError::Identity(identity.id().to_owned()))?;
                Ok((delegation, Some(current)))
            }

            async fn prepare(
                &self,
                request: ThreadPreparation,
            ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
                let id = request.identity.id().to_owned();
                let protocol = Fixture::protocol(&id, None);
                let current = request.root_current;
                let sink = ThreadStorageSink::new(self.0.clone(), protocol)
                    .await
                    .map_err(storage_error)?;
                let model_info = pl_model::model::ModelDefinition::compatible("reactivated-model");
                let route = pl_model::config::ResolvedModelRoute {
                    pricing_mode: Default::default(),
                    role: crate::config::root_agent_route_id(),
                    account_id: pl_model::config::AccountId::new("reactivation-account")
                        .map_err(storage_error)?,
                    endpoint: pl_model::protocol::providers::openai::compatible_endpoint(
                        "storage fixture",
                        "http://127.0.0.1:0",
                    ),
                    context: model_info
                        .resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled),
                    model: model_info,
                    effort: None,
                    service_tier: None,
                };
                let model = pl_model::runtime::ThreadModel::new(
                    pl_model::runtime::from_route(&route)?,
                    None,
                );
                Ok(StudioThreadSpec {
                    workspace_usage: None,
                    preparation_guard: None,
                    agent_controls: request.agent_controls,
                    execution: pl_core::thread::input::InputDriverOptions {
                        max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
                    },
                    id: id.clone(),
                    parent_id: None,
                    model: Some(pl_core::thread::RuntimeModel::new(
                        route.model.base.slug.clone(),
                        pl_core::model::ModelFactory::new(model),
                        None,
                    )),
                    route,
                    current,
                    initial_context: Vec::new(),
                    initial_runtime_facts: Vec::new(),
                    initial_extensions: BTreeMap::new(),
                    tools: Vec::new(),
                    resources: pl_core::context::ResourceAccess::new(
                        crate::resource_store::FileResourceStore::new(
                            self.0.session_resources_dir(&id).map_err(storage_error)?,
                        ),
                    ),
                    capacity: Default::default(),
                    history_sink: Some(sink),
                })
            }
        }

        async fn save_cold_thread(store: &StudioStore, protocol: &crate::Thread) -> Result<()> {
            register_test_thread(store, protocol).await?;
            let sink = ThreadStorageSink::new(store.clone(), protocol.clone()).await?;
            let projection = spawn_live_projection_for_thread(store.clone(), &protocol.id);
            let channel = store.thread_persistence().history_channel(&protocol.id);
            let thread = ThreadHandle::start_current(protocol.id.clone(), None)?;
            thread.attach_history(HistorySinkHandle::new(sink)).await?;
            let epoch = thread.runtime_epoch();
            let mut current_store = store.state_for(&protocol.workspace_id, &protocol.id)?;
            current_store
                .attach_current(
                    store.thread_persistence().clone(),
                    None,
                    epoch,
                    crate::studio::storage::current_writer::CurrentSource::from_thread(
                        thread.clone(),
                    ),
                )
                .await?;
            let assignment = crate::AgentWorkspaceAssignmentSnapshot {
                mode: crate::AgentWorkspaceMode::Directory,
                project_root: store.paths().home().to_string_lossy().into_owned(),
                root: store.paths().home().to_string_lossy().into_owned(),
                writable_paths: None,
                review_target: None,
                worktree: None,
            };
            thread
                .mutate_extensions(vec![
                    pl_core::thread::extensions::ExtensionMutation::Put {
                        id: crate::studio::workspace_receipt::EXTENSION.into(),
                        expected_revision: None,
                        payload: crate::studio::workspace_receipt::to_payload(&assignment)
                            .map_err(anyhow::Error::msg)?,
                    },
                    pl_core::thread::extensions::ExtensionMutation::Put {
                        id: crate::studio::delegation::EXTENSION.into(),
                        expected_revision: None,
                        payload: crate::studio::delegation::encode(Default::default())?,
                    },
                ])
                .await?;
            current_store
                .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await?;
            let through = channel.handoff_ticket();
            channel.await_handoff_durable(&protocol.id, through).await?;
            channel.stop_and_join().await?;
            projection.await?;
            Ok(())
        }

        /// Seed the explicit Current obligation left before recipient admission. History's
        /// immutable report alone does not authorize recovery to infer or re-send a delivery.
        async fn save_pending_report(
            store: &StudioStore,
            parent: &crate::Thread,
            message: &pl_core::thread::inbox::ThreadMessage,
        ) -> Result<()> {
            let mut state = store.state_for(&parent.workspace_id, &parent.id)?;
            let saved = state
                .load_current()
                .await?
                .context("saved parent Current")?;
            let owner = ThreadHandle::restore_current(saved, None)?;
            let epoch = owner.runtime_epoch();
            state
                .attach_current(
                    store.thread_persistence().clone(),
                    None,
                    epoch,
                    crate::studio::storage::current_writer::CurrentSource::from_thread(
                        owner.clone(),
                    ),
                )
                .await?;
            let pending = crate::thread_assembler::pending_delivery::PendingNativeDelivery::from_terminal_message(message.clone(), false)?;
            owner
                .mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
                    id: pending.extension_id(),
                    expected_revision: None,
                    payload: pending.encode()?,
                }])
                .await?;
            state
                .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await
        }

        #[derive(Clone, Copy)]
        enum RecoveryPath {
            Uninterrupted,
            RetryClose,
            ActivateParent,
        }

        async fn activate_parent(fixture: &Fixture) -> Result<ThreadHandle> {
            Ok(tokio::time::timeout(
                std::time::Duration::from_secs(10),
                fixture.owner.activate(
                    fixture.activation("parent", None),
                    ReactivationFactory(fixture.store.clone()),
                ),
            )
            .await??)
        }

        #[tokio::test]
        async fn closing_execution_accepts_only_the_original_storage_report_without_resuming()
        -> Result<()> {
            for global_close in [false, true] {
                let temp = tempfile::tempdir()?;
                let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
                let saved = save_pending_close(&store).await?;
                let resources = crate::studio::storage_fault_test_support::close_factory(&store)?;
                let fixture = Fixture::new(store.clone())?;
                resources.install(&fixture.owner)?;
                let active = activate_parent(&fixture).await?;
                let before = active.snapshot();
                fixture
                    .owner
                    .0
                    .state()
                    .entries
                    .get_mut("parent")
                    .unwrap()
                    .native_mut()
                    .unwrap()
                    .ready = false;
                let services = fixture
                    .owner
                    .0
                    .state()
                    .agent_services
                    .clone()
                    .context("real report services")?;
                let error = services
                    .redeliver_parent_report(&fixture.owner, "parent", saved.message.clone())
                    .await
                    .unwrap_err();
                assert!(matches!(
                    error.downcast_ref::<ThreadAssemblyError>(),
                    Some(ThreadAssemblyError::Unpublished(_))
                ));
                assert!(
                    current_message_identity(&store, "parent", &saved.message.id)
                        .await?
                        .is_none()
                );
                let seal = if global_close {
                    fixture.owner.0.state().closing = true;
                    None
                } else {
                    Some(fixture.owner.seal_agent_operation("parent"))
                };
                fixture.owner.admit_thread_close("parent")?;
                services
                    .redeliver_parent_report(&fixture.owner, "parent", saved.message.clone())
                    .await?;
                let SavedMessageIdentity {
                    sequence: receipt_sequence,
                    digest: receipt_digest,
                } = current_message_identity(&store, "parent", &saved.message.id)
                    .await?
                    .context("original report durable receipt")?;
                assert_eq!(receipt_digest, saved.message.digest());
                services
                    .redeliver_parent_report(&fixture.owner, "parent", saved.message.clone())
                    .await?;
                let SavedMessageIdentity {
                    sequence: repeated_sequence,
                    digest: repeated_digest,
                } = current_message_identity(&store, "parent", &saved.message.id)
                    .await?
                    .context("idempotent original report receipt")?;
                assert_eq!(repeated_sequence, receipt_sequence);
                assert_eq!(repeated_digest, receipt_digest);
                {
                    let state = fixture.owner.0.state();
                    let entry = &state.entries["parent"];
                    assert_eq!(
                        entry.native().unwrap().purpose,
                        super::super::super::EntryPurpose::Execution
                    );
                    assert!(!entry.native().unwrap().ready);
                    assert!(entry.native().unwrap().thread.same_instance(&active));
                }
                let after = active.snapshot();
                assert_eq!(after.execution_sequence, before.execution_sequence);
                assert!(before.attempts.is_empty() && after.attempts.is_empty());
                assert_eq!(after.execution, before.execution);
                assert_eq!(
                    after
                        .inbox
                        .iter()
                        .filter(|entry| entry.message.id == saved.message.id)
                        .count(),
                    1
                );
                drop(seal);
                assert!(fixture.owner.close_session().await.is_empty());
                fixture.stop_writers().await?;
                resources.shutdown().await?;
            }
            Ok(())
        }

        #[tokio::test]
        async fn cold_parent_close_recovery_releases_receiver_and_preserves_original_ack_after_failure()
        -> Result<()> {
            for path in [
                RecoveryPath::Uninterrupted,
                RecoveryPath::RetryClose,
                RecoveryPath::ActivateParent,
            ] {
                let inject_failure = !matches!(path, RecoveryPath::Uninterrupted);
                let mut active = None;
                let temp = tempfile::tempdir()?;
                let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
                let parent = Fixture::protocol("parent", None);
                let child = Fixture::protocol("child", Some("parent"));
                // These original storage owners are fully stopped before the new coordinator exists.
                // Never add a parent Entry to the coordinator recovering the saved close.
                save_cold_thread(&store, &parent).await?;
                save_cold_thread(&store, &child).await?;
                let sequence = 1;
                let content = frozen_report_body(
                    &child,
                    sequence,
                    "original terminal body and permission evidence\n\noriginal frozen evidence",
                )?;
                let message = pl_core::thread::inbox::ThreadMessage {
                    kind: AgentMessageKind::Report,
                    id: crate::studio::agent_close::terminal_report_id("child", sequence),
                    source_id: "studio.child:child".into(),
                    payload: OpaquePayload::new("pl.studio.turn-report", 3, content.clone())?,
                    context: vec![ContextContent::Text {
                        text: content.into(),
                    }],
                };
                save_terminal_report(&store, &child, message.clone()).await?;
                save_pending_report(&store, &parent, &message).await?;
                let resources = close_factory(&store)?;
                let current = store
                    .state_for("project-test", "child")?
                    .load_current()
                    .await?
                    .context("terminal child current")?;
                let current_snapshot = current.state.to_paused_snapshot();
                resources
                    .factory
                    .begin_child_close(&child, Some(&current_snapshot), false)
                    .await?;
                let fixture = Fixture::new(store.clone())?;
                resources.install(&fixture.owner)?;
                assert!(fixture.owner.0.state().entries.is_empty());
                assert!(
                    current_message_identity(&store, "parent", &message.id)
                        .await?
                        .is_none()
                );
                fixture.fail_drain.store(inject_failure, Ordering::SeqCst);
                let first = tokio::time::timeout(
                    std::time::Duration::from_secs(10),
                    fixture.owner.resume_agent_closes(),
                )
                .await?;
                let SavedMessageIdentity {
                    sequence: first_sequence,
                    digest: first_digest,
                } = current_message_identity(&store, "parent", &message.id)
                    .await?
                    .context("original report was durably received even when cleanup failed")?;
                assert_eq!(first_digest, message.digest());
                if inject_failure {
                    let failure = first
                        .expect_err("receiver drain fails after the real Current delivery ACK");
                    let diagnostic = format!("{failure:#}");
                    assert!(diagnostic.contains("injected receiver drain failure"));
                    assert!(
                        !store
                            .agent_close("child")
                            .await?
                            .context("pending close")?
                            .execution_closed
                    );
                    assert!(
                        fixture
                            .owner
                            .0
                            .state()
                            .entries
                            .get("parent")
                            .is_some_and(|entry| {
                                entry.native().is_ok_and(|native| {
                                    native.purpose == EntryPurpose::ReportReceiver
                                })
                            })
                    );
                    assert!(
                        !fixture.owner.0.state().entries["parent"]
                            .native()
                            .unwrap()
                            .ready
                    );
                    fixture.fail_drain.store(false, Ordering::SeqCst);
                    if matches!(path, RecoveryPath::ActivateParent) {
                        // Normal activation itself must release the retained receiver, never return the
                        // no-model handle as ready or fail forever with Unpublished.
                        active = Some(activate_parent(&fixture).await?);
                    }
                    tokio::time::timeout(
                        std::time::Duration::from_secs(10),
                        fixture.owner.resume_agent_closes(),
                    )
                    .await??;
                } else {
                    first?;
                }
                assert_eq!(
                    fixture.owner.0.state().entries.contains_key("parent"),
                    active.is_some()
                );
                assert!(!fixture.owner.0.state().sealed_agents.contains_key("parent"));
                assert!(store.agent_close("parent").await?.is_none());
                assert!(
                    store
                        .agent_close("child")
                        .await?
                        .context("finished close")?
                        .execution_closed
                );
                assert_eq!(
                    *fixture.closes.lock().unwrap(),
                    vec![("child".into(), WorkspaceRelease::Preserve)]
                );
                assert_eq!(
                    fixture.owner.acknowledge_parent_reports(&child).await?,
                    ParentReportAcknowledgement::Absent
                );
                let SavedMessageIdentity {
                    sequence: receipt_sequence,
                    digest: receipt_digest,
                } = current_message_identity(&store, "parent", &message.id)
                    .await?
                    .context("same durable parent ACK")?;
                assert_eq!(receipt_sequence, first_sequence);
                assert_eq!(receipt_digest, first_digest);
                assert_eq!(
                    history_parent_report(&store.history("child").await?, "child", sequence)
                        .await?
                        .context("unchanged original report")?
                        .digest(),
                    message.digest()
                );

                let active = match active {
                    Some(active) => active,
                    None => activate_parent(&fixture).await?,
                };
                assert!(fixture.owner.thread("parent").is_some());
                assert_eq!(
                    fixture.owner.0.state().entries["parent"]
                        .native()
                        .unwrap()
                        .purpose,
                    EntryPurpose::Execution
                );
                let mut followup = message.clone();
                followup.id = "after-recovery".into();
                active.send_message(followup).await?;
                fixture.owner.synchronize_observation("parent").await?;
                store
                    .conversation_store("parent")
                    .await?
                    .flush_current(active.runtime_epoch())
                    .await?;
                assert!(
                    current_message_identity(&store, "parent", "after-recovery")
                        .await?
                        .is_some()
                );
                assert!(fixture.owner.close_session().await.is_empty());
                fixture.stop_writers().await?;
                resources.shutdown().await?;
            }
            Ok(())
        }

        struct SavedClose {
            child: crate::Thread,
            message: pl_core::thread::inbox::ThreadMessage,
            sequence: u64,
        }

        async fn save_pending_close(store: &StudioStore) -> Result<SavedClose> {
            let parent = Fixture::protocol("parent", None);
            let child = Fixture::protocol("child", Some("parent"));
            save_cold_thread(store, &parent).await?;
            save_cold_thread(store, &child).await?;
            let sequence = 1;
            let content = frozen_report_body(
                &child,
                sequence,
                "original body before receiver cancellation or detach\n\noriginal permission evidence",
            )?;
            let message = pl_core::thread::inbox::ThreadMessage {
                kind: AgentMessageKind::Report,
                id: crate::studio::agent_close::terminal_report_id("child", sequence),
                source_id: "studio.child:child".into(),
                payload: OpaquePayload::new("pl.studio.turn-report", 3, content.clone())?,
                context: vec![ContextContent::Text {
                    text: content.into(),
                }],
            };
            save_terminal_report(store, &child, message.clone()).await?;
            save_pending_report(store, &parent, &message).await?;
            Ok(SavedClose {
                child,
                message,
                sequence,
            })
        }

        async fn prove_report_and_reactivate(fixture: &Fixture, saved: &SavedClose) -> Result<()> {
            let store = &fixture.store;
            assert_eq!(
                fixture
                    .owner
                    .acknowledge_parent_reports(&saved.child)
                    .await?,
                ParentReportAcknowledgement::Absent
            );
            let child_history = store.history("child").await?;
            assert_eq!(
                history_parent_report(&child_history, "child", saved.sequence)
                    .await?
                    .context("unchanged original body")?
                    .digest(),
                saved.message.digest()
            );
            let SavedMessageIdentity { digest, .. } =
                current_message_identity(store, "parent", &saved.message.id)
                    .await?
                    .context("durable original ID")?;
            assert_eq!(digest, saved.message.digest());
            assert!(
                store
                    .agent_close("child")
                    .await?
                    .context("completed child close")?
                    .execution_closed
            );
            assert!(store.agent_close("parent").await?.is_none());
            assert!(!fixture.owner.0.state().sealed_agents.contains_key("parent"));
            assert!(!fixture.owner.0.state().entries.contains_key("parent"));
            // This inspection cannot create a channel; successful release must not leave a new empty
            // stopping channel behind the original writer that already detached.
            assert!(
                store
                    .thread_persistence()
                    .retained_history_channel("parent")
                    .is_none()
            );
            let active = activate_parent(fixture).await?;
            let current = store
                .thread_persistence()
                .retained_history_channel("parent")
                .context("new active writer")?;
            assert!(!current.is_stopping());
            let mut followup = saved.message.clone();
            followup.id = "after-retained-storage-recovery".into();
            active.send_message(followup.clone()).await?;
            fixture.owner.synchronize_observation("parent").await?;
            store
                .conversation_store("parent")
                .await?
                .flush_current(active.runtime_epoch())
                .await?;
            let SavedMessageIdentity { digest, .. } =
                current_message_identity(store, "parent", &followup.id)
                    .await?
                    .context("real followup history write")?;
            assert_eq!(digest, followup.digest());
            assert!(fixture.owner.close_session().await.is_empty());
            fixture.stop_writers().await
        }

        #[tokio::test]
        async fn detached_receiver_writer_retry_joins_only_the_original_binding() -> Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let saved = save_pending_close(&store).await?;
            let resources = close_factory(&store)?;
            let current = store
                .state_for("project-test", "child")?
                .load_current()
                .await?
                .context("saved terminal child")?;
            let current_snapshot = current.state.to_paused_snapshot();
            resources
                .factory
                .begin_child_close(&saved.child, Some(&current_snapshot), false)
                .await?;
            let fixture = Fixture::new(store.clone())?;
            resources.install(&fixture.owner)?;
            assert!(fixture.owner.0.state().entries.is_empty());
            fixture
                .fail_drain_after_writer
                .store(true, Ordering::SeqCst);
            let failed = tokio::time::timeout(
                std::time::Duration::from_secs(10),
                fixture.owner.resume_agent_closes(),
            )
            .await?;
            let error =
                failed.expect_err("drain fails only after all physical writer workers joined");
            assert!(format!("{error:#}").contains("injected drain failure after writer detach"));
            let binding = fixture
                .owner
                .close_storage_binding("parent")?
                .context("retained exact binding after attachment and close")?;
            assert!(binding.channel.is_stopping());
            if let Some(retained) = store
                .thread_persistence()
                .retained_history_channel("parent")
            {
                assert!(
                    Arc::ptr_eq(&retained, &binding.channel),
                    "cleanup changed writer ownership"
                );
            }
            assert!(
                fixture
                    .owner
                    .0
                    .state()
                    .entries
                    .get("parent")
                    .is_some_and(|entry| entry
                        .native()
                        .is_ok_and(|native| native.purpose == EntryPurpose::ReportReceiver))
            );
            let SavedMessageIdentity {
                sequence: first_sequence,
                digest: first_digest,
            } = current_message_identity(&store, "parent", &saved.message.id)
                .await?
                .context("original durable receipt before cleanup retry")?;
            fixture
                .fail_drain_after_writer
                .store(false, Ordering::SeqCst);
            tokio::time::timeout(
                std::time::Duration::from_secs(10),
                fixture.owner.resume_agent_closes(),
            )
            .await??;
            let SavedMessageIdentity {
                sequence: receipt_sequence,
                digest: receipt_digest,
            } = current_message_identity(&store, "parent", &saved.message.id)
                .await?
                .context("same receipt after exact-binding cleanup")?;
            assert_eq!(receipt_sequence, first_sequence);
            assert_eq!(receipt_digest, first_digest);
            assert!(
                store
                    .thread_persistence()
                    .retained_history_channel("parent")
                    .is_none()
            );
            prove_report_and_reactivate(&fixture, &saved).await?;
            resources.shutdown().await
        }

        #[tokio::test]
        async fn cancelled_activation_resumes_the_one_already_effective_attach() -> Result<()> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            let saved = save_pending_close(&store).await?;
            let resources = close_factory(&store)?;
            let current = store
                .state_for("project-test", "child")?
                .load_current()
                .await?
                .context("saved terminal child")?;
            let current_snapshot = current.state.to_paused_snapshot();
            resources
                .factory
                .begin_child_close(&saved.child, Some(&current_snapshot), false)
                .await?;
            let fixture = Fixture::new(store.clone())?;
            resources.install(&fixture.owner)?;
            assert!(fixture.owner.0.state().entries.is_empty());
            // Install only the production cold receiver's retained Pending responsibility. It is not an
            // executable Fixture::add owner; normal activation must settle this very same pending owner.
            {
                let _operation = fixture.owner.agent_operation("parent").await;
                let services = fixture
                    .owner
                    .0
                    .state()
                    .agent_services
                    .clone()
                    .context("close services")?;
                let current = store
                    .state_for("project-test", "parent")?
                    .load_current()
                    .await?
                    .context("cold original parent")?;
                services.install_storage_owner(
                    &fixture.owner,
                    &Fixture::protocol("parent", None),
                    current,
                    EntryPurpose::ReportReceiver,
                )?;
            }
            assert!(matches!(
                fixture.owner.0.state().entries["parent"]
                    .native()
                    .unwrap()
                    .close_storage,
                Some(CloseStorage::Pending { .. })
            ));
            let (attached, attachment_ack) = tokio::sync::oneshot::channel();
            let (release, released) = tokio::sync::oneshot::channel();
            fixture.owner.0.state().storage_attachment_gate = Some(AttachmentAckGate {
                thread_id: "parent".into(),
                attached,
                release: released,
            });
            let owner = fixture.owner.clone();
            let activation = fixture.activation("parent", None);
            let activating_store = store.clone();
            let activating = tokio::spawn(async move {
                owner
                    .activate(activation, ReactivationFactory(activating_store))
                    .await
            });
            tokio::time::timeout(std::time::Duration::from_secs(10), attachment_ack).await??;
            let binding = {
                let state = fixture.owner.0.state();
                let entry = &state.entries["parent"];
                assert!(!entry.native().unwrap().ready);
                assert!(
                    entry
                        .native()
                        .unwrap()
                        .thread
                        .snapshot()
                        .persistence
                        .attached
                );
                let Some(CloseStorage::Attaching {
                    binding,
                    completion,
                }) = &entry.native().unwrap().close_storage
                else {
                    anyhow::bail!(
                        "effective attachment must retain its original shared completion"
                    );
                };
                assert!(completion.peek().is_none());
                binding.clone()
            };
            activating.abort();
            assert!(activating.await.unwrap_err().is_cancelled());
            assert!(matches!(
                fixture.owner.0.state().entries["parent"]
                    .native()
                    .unwrap()
                    .close_storage,
                Some(CloseStorage::Attaching { .. })
            ));
            release
                .send(())
                .map_err(|_| anyhow::anyhow!("cancelled waiter lost the attachment future"))?;
            // Existing ACK/close recovery re-waits that completion. A second AttachCold would now produce
            // InvalidIdentity from the unchanged core and fail this actual recovery path.
            tokio::time::timeout(
                std::time::Duration::from_secs(10),
                fixture.owner.resume_agent_closes(),
            )
            .await??;
            assert!(binding.channel.is_stopping());
            prove_report_and_reactivate(&fixture, &saved).await?;
            resources.shutdown().await
        }
    }
}
