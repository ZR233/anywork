//! Shared real storage and observation fixture for lifecycle regressions.
pub(crate) use super::*;
pub(crate) use crate::studio::{StudioStore, ThreadStorageBinding};
pub(crate) use crate::test_support::storage::{
    HistoryChannel, ThreadStorageSink, register_test_thread, spawn_live_projection_for_thread,
};
use anyhow::Context as _;
pub(crate) use anyhow::Result;
pub(crate) use pl_core::{
    context::{AgentMessageKind, ContextContent, OpaquePayload},
    thread::{TurnOutcome, TurnRecord, TurnState, history_sink::HistorySinkHandle},
};
pub(crate) use pl_tool::collaboration::thread::WorkspaceRelease;
pub(crate) use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

pub(crate) struct SavedMessageIdentity {
    pub(crate) sequence: u64,
    pub(crate) digest: String,
}
pub(crate) async fn current_message_identity(
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
pub(crate) async fn history_parent_report(
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
pub(crate) struct ObservedOwner {
    pub(crate) thread: ThreadHandle,
    pub(crate) channel: Arc<HistoryChannel>,
    pub(crate) projection: Arc<tokio::sync::Mutex<ProjectionTask>>,
}
pub(crate) struct ProjectionTask {
    pub(crate) task: Option<tokio::task::JoinHandle<()>>,
    pub(crate) failure: Option<Arc<tokio::task::JoinError>>,
}
pub(crate) type LiveOwners = Arc<Mutex<BTreeMap<String, ObservedOwner>>>;

pub(crate) fn storage_error(error: impl Into<anyhow::Error>) -> ThreadAssemblyError {
    ThreadAssemblyError::Resource {
        operation: "storage fault fixture barrier",
        source: error.into().into_boxed_dyn_error(),
    }
}

pub(crate) fn barrier(
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

pub(crate) async fn drain(
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
pub(crate) struct ResourceIo(Arc<Mutex<Vec<(String, WorkspaceRelease)>>>);
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

pub(crate) struct Fixture {
    pub(crate) owner: SessionRuntime,
    pub(crate) store: StudioStore,
    pub(crate) live: LiveOwners,
    pub(crate) closes: Arc<Mutex<Vec<(String, WorkspaceRelease)>>>,
    pub(crate) fail_drain: Arc<AtomicBool>,
    pub(crate) fail_drain_after_writer: Arc<AtomicBool>,
}
impl Fixture {
    pub(crate) fn new(store: StudioStore) -> Result<Self> {
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

    pub(crate) fn protocol(id: &str, parent: Option<&str>) -> crate::Thread {
        let mut thread = crate::Thread::placeholder(id);
        thread.workspace_id = "project-test".into();
        thread.agent_path = id.into();
        thread.parent_thread_id = parent.map(str::to_owned);
        thread.root_thread_id = parent.unwrap_or(id).into();
        thread
    }

    pub(crate) fn activation(&self, id: &str, parent: Option<&str>) -> ThreadActivation {
        let mut activation = ThreadActivation::native_test(id, parent);
        activation.agent.session_id = self.owner.id().clone();
        activation
    }

    pub(crate) async fn add(&self, id: &str, parent: Option<&str>) -> Result<ThreadHandle> {
        self.add_with_workspace(id, parent, None).await
    }

    pub(crate) async fn add_with_workspace(
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
        self.owner.0.state().members.insert_entry(
            id.into(),
            crate::session::AgentInstance {
                identity: activation.agent,
                binding: activation.binding,
                runtime: crate::session::AgentRuntime::Native(Box::new(
                    crate::session::NativeThreadRuntime {
                        resources: Arc::new(crate::session::NativeResources::default()),
                        purpose: EntryPurpose::Execution,
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

    pub(crate) async fn stop_writers(&self) -> Result<()> {
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

pub(crate) use crate::test_support::storage::CloseFactoryFixture;
