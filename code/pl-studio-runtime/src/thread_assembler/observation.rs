//! Product observation registration; callbacks execute outside the registry lock.
use super::*;

type Observe = dyn Fn(String, ThreadHandle) + Send + Sync;
type BeforeClose = dyn Fn(String, ThreadHandle) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
    + Send
    + Sync;
type Drain = dyn Fn(String) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
    + Send
    + Sync;
/// Durable record of one accepted message identity inside a Thread's history.
///
/// The index is the authority a delivery uses once it left core's bounded resident window. A
/// migrated row may prove that the identity was accepted without proving the body, which must never
/// be re-delivered as new work.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum DurableMessageIdentity {
    /// The accepted body digest and its original admission sequence.
    Proven { sequence: u64, digest: String },
    /// The identity is recorded but its accepted body cannot be verified.
    Unverifiable,
}

/// Admission is not durability. Only the parent's existing history index proves final delivery.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ParentMessageDelivery {
    Accepted { message_id: String, sequence: u64 },
    ProvenExisting { message_id: String, sequence: u64 },
    Skipped(ParentMessageSkip),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ParentMessageSkip {
    Closing,
    TargetUnavailable,
    UnverifiableHistory,
    ClosedDuringAdmission,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ParentReportAcknowledgement {
    Absent,
    Proven,
}

/// Durable lookup of one `(target thread, message id)` identity.
///
/// A named alias keeps the install signature readable; the callback runs outside the registry lock
/// and its future must stay `Send` because the observation worker is a spawned task. `None` answers
/// "this Thread never accepted that identity"; a failure must be propagated so the caller fails
/// closed instead of admitting a possible duplicate.
pub(crate) type MessageQuery = futures::future::BoxFuture<
    'static,
    Result<Option<DurableMessageIdentity>, ThreadAssemblyError>,
>;
pub(crate) type MessageIdentityLookup = dyn Fn(String, String) -> MessageQuery + Send + Sync;

/// Outcome of adjudicating one delivery against the durable message identity index.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum DeliveryDisposition {
    /// The identity is already accepted with an identical body: answer with this original receipt.
    Receipt(u64),
    /// The same identity is accepted with a provably different body.
    Conflict,
    /// The identity is recorded but its accepted body cannot be verified (migrated row).
    Unverifiable,
    /// The Thread never accepted this identity: a normal admission may proceed.
    New,
}
#[derive(Clone)]
pub(super) struct AssemblyObservation(
    Arc<Observe>,
    Arc<Drain>,
    Option<Arc<MessageIdentityLookup>>,
    Arc<BeforeClose>,
    Arc<Drain>,
);
impl std::fmt::Debug for AssemblyObservation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AssemblyObservation")
    }
}
impl StudioThreadAssembler {
    pub(crate) fn observe_assembly(
        &self,
        observe: impl Fn(String, ThreadHandle) + Send + Sync + 'static,
        drain: impl Fn(String) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>>
        + Send
        + Sync
        + 'static,
        messages: Option<Arc<MessageIdentityLookup>>,
        before_close: impl Fn(
            String,
            ThreadHandle,
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
            messages,
            Arc::new(before_close),
            Arc::new(synchronize),
        ));
        Ok(())
    }
    pub(super) fn publish_observation(&self, id: &str, thread: &ThreadHandle) {
        let observer = self.0.state().observation.clone();
        if let Some(observer) = observer {
            (observer.0)(id.to_owned(), thread.clone());
        }
    }
    pub(super) async fn drain_observation(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let observer = self.0.state().observation.clone();
        if let Some(observer) = observer {
            let result = (observer.1)(id.to_owned()).await;
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
        let observer = self
            .0
            .state()
            .observation
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        (observer.4)(id.to_owned()).await
    }

    /// Bind close completion to each actual terminal effect's original report ID and the
    /// parent's accepted/durable sequence. A skipped publication can never be a successful ACK.
    pub(crate) async fn acknowledge_parent_reports(
        &self,
        store: &crate::studio::StudioStore,
        child: &pl_protocol::Thread,
    ) -> Result<ParentReportAcknowledgement, ThreadAssemblyError> {
        let failure = |source: anyhow::Error| ThreadAssemblyError::Resource {
            operation: "acknowledge terminal parent reports",
            source: source.into_boxed_dyn_error(),
        };
        let history = store.history(&child.id).await.map_err(failure)?;
        Box::pin(self.recover_saved_review_deliveries(child))
            .await
            .map_err(failure)?;
        self.join_review_delivery(&child.id)
            .await
            .map_err(failure)?;
        let mut after = 0;
        let mut acknowledged = false;
        let mut synchronized = false;
        loop {
            let sequences = history
                .terminal_report_sequences(after)
                .await
                .map_err(failure)?;
            if sequences.is_empty() {
                let mut cursor = String::new();
                loop {
                    let facts = history
                        .review_delivery_exceptions(&cursor)
                        .await
                        .map_err(failure)?;
                    if facts.is_empty() {
                        break;
                    }
                    for fact in facts {
                        let parent = child.parent_thread_id.as_deref().ok_or_else(|| {
                            failure(anyhow::anyhow!("review delivery exception has no parent"))
                        })?;
                        cursor = fact.message.id.clone();
                        self.acknowledge_review_exception(parent, fact.message, false)
                            .await
                            .map_err(failure)?;
                        acknowledged = true;
                    }
                }
                return Ok(if acknowledged {
                    ParentReportAcknowledgement::Proven
                } else {
                    ParentReportAcknowledgement::Absent
                });
            }
            for sequence in sequences {
                let parent = child
                    .parent_thread_id
                    .as_deref()
                    .ok_or_else(|| failure(anyhow::anyhow!("terminal child has no parent")))?;
                let message_id =
                    crate::studio::agent_close::terminal_report_id(&child.id, sequence);
                let original = history.parent_report(sequence).await.map_err(failure)?;
                // An earlier delivery can already be durable while receiver cleanup failed or its
                // waiter was cancelled. Do not skip the remaining owner just because its ACK exists.
                self.finish_report_receiver(parent).await?;
                let mut receipt = self.durable_message_identity(parent, &message_id).await?;
                if receipt.is_none() && !synchronized && self.observed_thread(parent).is_some() {
                    // This is only a fixed handoff wait, never a substitute for the identity check.
                    self.synchronize_observation(parent).await?;
                    synchronized = true;
                    receipt = self.durable_message_identity(parent, &message_id).await?;
                }
                if receipt.is_none() {
                    let message = original.clone().ok_or_else(|| failure(anyhow::anyhow!(
                        "parent report {message_id} lacks its original durable body; later checkpoints cannot reconstruct original permissions or messages"
                    )))?;
                    let services = self
                        .0
                        .state()
                        .agent_services
                        .clone()
                        .ok_or(ThreadAssemblyError::Closed)?;
                    services
                        .redeliver_parent_report(self, parent, message)
                        .await
                        .map_err(failure)?;
                    receipt = self.durable_message_identity(parent, &message_id).await?;
                }
                match receipt {
                    Some(DurableMessageIdentity::Proven {
                        sequence: accepted,
                        digest,
                    }) => {
                        if let Some(original) = original
                            && original.digest() != digest
                        {
                            return Err(failure(anyhow::anyhow!(
                                "parent report {message_id} durable body differs from its original handoff"
                            )));
                        }
                        tracing::trace!(child_id = child.id, %message_id, parent_sequence = accepted, "terminal report durable receipt verified");
                    }
                    Some(DurableMessageIdentity::Unverifiable) => {
                        return Err(failure(anyhow::anyhow!(
                            "parent report {message_id} has no verifiable durable receipt"
                        )));
                    }
                    None => {
                        return Err(failure(anyhow::anyhow!(
                            "parent report {message_id} was not durably delivered; child history is retained"
                        )));
                    }
                }
                acknowledged = true;
                after = sequence;
            }
        }
    }
    pub(super) fn prepare_close(
        &self,
        id: &str,
        thread: &ThreadHandle,
    ) -> futures::future::BoxFuture<'static, Result<(), ThreadAssemblyError>> {
        let observer = self.0.state().observation.clone();
        match observer {
            Some(observer) => (observer.3)(id.to_owned(), thread.clone()),
            None => Box::pin(async { Ok(()) }),
        }
    }

    /// Adjudicates one message delivery against the target Thread's durable identity index.
    ///
    /// Every admission site must run this before it accepts a message as new work, because a delivery
    /// whose resident copy is gone would otherwise be admitted a second time. The result is the
    /// original admission receipt for an identical repeat, `New` for an identity this Thread never
    /// accepted, and an explicit conflict/unverifiable disposition for the same identity carrying a
    /// body the durable index cannot match. A storage failure is propagated so the caller fails
    /// closed instead of admitting a possible duplicate.
    ///
    /// An assembler without an installed Studio host has no durable index; that host always installs
    /// one, and the bounded resident dedup in core still covers the live window in the meantime.
    pub(super) async fn adjudicate_message(
        &self,
        thread_id: &str,
        message: &pl_core::thread::inbox::ThreadMessage,
    ) -> Result<DeliveryDisposition, ThreadAssemblyError> {
        match self
            .durable_message_identity(thread_id, &message.id)
            .await?
        {
            None => Ok(DeliveryDisposition::New),
            Some(DurableMessageIdentity::Proven { sequence, digest })
                if digest == message.digest() =>
            {
                Ok(DeliveryDisposition::Receipt(sequence))
            }
            Some(DurableMessageIdentity::Proven { .. }) => Ok(DeliveryDisposition::Conflict),
            Some(DurableMessageIdentity::Unverifiable) => Ok(DeliveryDisposition::Unverifiable),
        }
    }

    pub(super) async fn durable_message_identity(
        &self,
        thread_id: &str,
        message_id: &str,
    ) -> Result<Option<DurableMessageIdentity>, ThreadAssemblyError> {
        // Resolve the callback before awaiting: the registry lock only guards the synchronous state
        // read, so no `MutexGuard` is ever held across the durable query (this may run on a spawned
        // `Send` future).
        let lookup = self
            .0
            .state()
            .observation
            .as_ref()
            .and_then(|observation| observation.2.clone());
        let Some(lookup) = lookup else {
            return Ok(None);
        };
        lookup(thread_id.to_owned(), message_id.to_owned()).await
    }
    pub(crate) async fn notify_parent(
        &self,
        id: &str,
        message: pl_core::thread::inbox::ThreadMessage,
        wake: bool,
    ) -> Result<ParentMessageDelivery, ThreadAssemblyError> {
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
                entry.ready && entry.thread.snapshot().lifecycle == ThreadLifecycle::Open
            })
            .map(|entry| (entry.thread.clone(), entry.execution))
        };
        let Some((thread, execution)) = target else {
            return Ok(ParentMessageDelivery::Skipped(
                ParentMessageSkip::TargetUnavailable,
            ));
        };
        // A terminal event's child write sequence is its identity. Its report includes observation-
        // time fields, so regenerating it after a restart need not reproduce the first accepted
        // body. The parent's durable receipt owns that body; a repeated event only wakes its still
        // pending message. Ordinary authored messages retain strict body-digest adjudication.
        match self.durable_message_identity(id, &message.id).await? {
            Some(DurableMessageIdentity::Proven { sequence, .. }) => {
                if wake {
                    thread
                        .wake_accepted_message(&message.id, sequence, execution)
                        .await?;
                }
                return Ok(ParentMessageDelivery::ProvenExisting {
                    message_id: message.id,
                    sequence,
                });
            }
            // Older history proves acceptance without a receipt. Never admit a second copy.
            Some(DurableMessageIdentity::Unverifiable) => {
                return Ok(ParentMessageDelivery::Skipped(
                    ParentMessageSkip::UnverifiableHistory,
                ));
            }
            None => {}
        }
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
}

#[cfg(test)]
mod storage_fault_tests {
    mod archive_scope;
    mod cold_parent_report;

    use super::*;
    use crate::studio::StudioStore;
    use crate::studio::storage_fault_test_support::{
        HistoryChannel, ThreadStorageSink, register_test_thread, spawn_live_projection,
        spawn_live_projection_for_thread, ticket,
    };
    use anyhow::{Context, Result};
    use pl_core::{
        context::{AgentMessageKind, ContextContent, OpaquePayload},
        thread::{
            TurnOutcome, TurnRecord, TurnState,
            cold::{ColdStore, ColdStoreHandle},
        },
    };
    use pl_tool::collaboration::thread::WorkspaceRelease;
    use sea_orm::ConnectionTrait;
    use std::{
        collections::BTreeMap,
        sync::{
            Arc, Mutex,
            atomic::{AtomicBool, Ordering},
        },
    };

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
    struct ResourceIo(Arc<Mutex<Vec<WorkspaceRelease>>>);
    impl StudioChildFactory for ResourceIo {
        async fn prepare(
            &self,
            _: ChildThreadRequest,
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            Err(ThreadAssemblyError::Identity(
                "storage fixture does not prepare workspaces".into(),
            ))
        }
        async fn close_published(
            &self,
            _: &str,
            disposition: WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            self.0.lock().unwrap().push(disposition);
            Ok(())
        }
        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&WorkspaceUsageLease>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }
    }

    struct Fixture {
        owner: StudioThreadAssembler,
        store: StudioStore,
        live: LiveOwners,
        closes: Arc<Mutex<Vec<WorkspaceRelease>>>,
        fail_sync: Arc<AtomicBool>,
        fail_drain: Arc<AtomicBool>,
        fail_drain_after_writer: Arc<AtomicBool>,
    }
    impl Fixture {
        fn new(store: StudioStore) -> Result<Self> {
            let owner = StudioThreadAssembler::default();
            let live = LiveOwners::default();
            let draining = live.clone();
            let syncing = live.clone();
            let observed = live.clone();
            let observing = store.clone();
            let messages = store.clone();
            let closes = Arc::new(Mutex::new(Vec::new()));
            let fail_sync = Arc::new(AtomicBool::new(false));
            let sync_fault = fail_sync.clone();
            let fail_drain = Arc::new(AtomicBool::new(false));
            let drain_fault = fail_drain.clone();
            let fail_drain_after_writer = Arc::new(AtomicBool::new(false));
            let late_drain_fault = fail_drain_after_writer.clone();
            owner.set_child_factory(ResourceIo(closes.clone()))?;
            owner.observe_assembly(
                move |id, thread| {
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
                move |id| {
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
                Some(Arc::new(move |id, message| {
                    let store = messages.clone();
                    Box::pin(async move {
                        Ok(store
                            .history(&id)
                            .await
                            .map_err(storage_error)?
                            .message_identity(&message)
                            .await
                            .map_err(storage_error)?
                            .map(|receipt| match receipt.digest {
                                Some(digest) => DurableMessageIdentity::Proven {
                                    sequence: receipt.sequence,
                                    digest,
                                },
                                None => DurableMessageIdentity::Unverifiable,
                            }))
                    })
                })),
                |_, _| Box::pin(async { Ok(()) }),
                move |id| {
                    let owners = syncing.clone();
                    let fault = sync_fault.clone();
                    Box::pin(async move {
                        if id == "parent" && fault.load(Ordering::SeqCst) {
                            return Err(storage_error(anyhow::anyhow!(
                                "injected report ACK failure"
                            )));
                        }
                        barrier(owners, id).await
                    })
                },
            )?;
            Ok(Self {
                owner,
                store,
                live,
                closes,
                fail_sync,
                fail_drain,
                fail_drain_after_writer,
            })
        }

        fn protocol(id: &str, parent: Option<&str>) -> pl_protocol::Thread {
            let mut thread = pl_protocol::Thread::placeholder(id);
            thread.workspace_id = "project-test".into();
            thread.agent_path = id.into();
            thread.parent_thread_id = parent.map(str::to_owned);
            thread.root_thread_id = parent.unwrap_or(id).into();
            thread
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
            let checkpoint = self.store.history(id).await?.checkpoint().await?;
            let sink =
                ThreadStorageSink::new(self.store.clone(), protocol, checkpoint.as_ref()).await?;
            let thread = ThreadHandle::resume_without_model(id.into(), checkpoint)?;
            thread
                .attach_storage(ColdStoreHandle::new(sink.clone()))
                .await?;
            self.owner.0.state().entries.insert(
                id.into(),
                Entry {
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
                    close_storage: None,
                    published_resources_closed: false,
                    workspace_disposition: None,
                },
            );
            self.owner.publish_observation(id, &thread);
            Ok(thread)
        }

        async fn stop_writers(&self) -> Result<()> {
            let channels = self
                .live
                .lock()
                .unwrap()
                .values()
                .map(|owner| owner.channel.clone())
                .collect::<Vec<_>>();
            for channel in channels {
                channel.stop_and_join().await?;
            }
            Ok(())
        }
    }

    /// Real checkpoint rejection leaves the close owner registered; retry must use the same
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
            async fn prepare(
                &self,
                _: ChildThreadRequest,
            ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
                Err(ThreadAssemblyError::Closed)
            }
            async fn discard_unpublished(
                &self,
                id: &str,
                usage: Option<&WorkspaceUsageLease>,
            ) -> Result<(), ThreadAssemblyError> {
                self.entered.send_replace(true);
                let _permit = self.release.acquire().await.map_err(storage_error)?;
                super::super::StudioChildResources::discard_unpublished(&self.factory, id, usage)
                    .await
            }
        }
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let resources = crate::studio::storage_fault_test_support::close_factory(&store)?;
        let root = temp.path().join("shared-root");
        tokio::fs::create_dir_all(&root).await?;
        let preparation = resources
            .unpublished_workspace("unpublished-directory", &root)
            .await?;
        let owner = StudioThreadAssembler::default();
        let (entered, mut observed) = tokio::sync::watch::channel(false);
        let release = Arc::new(tokio::sync::Semaphore::new(0));
        owner.0.state().unpublished_children.insert(
            "unpublished-directory".into(),
            super::super::child_resources::UnpublishedChild {
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
    async fn rejected_close_checkpoint_keeps_cleanup_request_retryable_without_early_cleanup()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let fixture = Fixture::new(store.clone())?;
        fixture.add("parent", None).await?;
        let child = fixture.add("child", Some("parent")).await?;
        crate::studio::agent_close::commit(&child).await?;
        fixture
            .owner
            .freeze_agent_close_disposition("child", WorkspaceRelease::Preserve)?;
        let history = store.history("child").await?;
        let before = history
            .checkpoint()
            .await?
            .context("durable close intent")?;
        let db = sea_orm::Database::connect(
            crate::studio::paths::sqlite_file_options(
                &store
                    .session_paths("project-test", "child")?
                    .history_database(),
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared("CREATE TRIGGER reject_closed_checkpoint BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'controlled closed checkpoint rejection'); END").await?;
        assert!(fixture.owner.close("child").await.is_err());
        assert!(fixture.owner.0.state().entries.contains_key("child"));
        assert!(fixture.closes.lock().unwrap().is_empty());
        assert_eq!(
            history.checkpoint().await?.unwrap().history_fence,
            before.history_fence
        );
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
        let generation = store
            .thread_persistence()
            .history_channel("child")
            .subscribe()
            .borrow()
            .fault_generation;
        db.execute_unprepared("DROP TRIGGER reject_closed_checkpoint")
            .await?;
        store
            .thread_persistence()
            .retry_history("child", generation)
            .await?;
        fixture.owner.close("child").await?;
        assert_eq!(
            *fixture.closes.lock().unwrap(),
            vec![WorkspaceRelease::Preserve]
        );
        assert_eq!(
            history.checkpoint().await?.unwrap().state.lifecycle,
            ThreadLifecycle::Closed
        );
        assert!(fixture.owner.close_all().await.is_empty());
        fixture.stop_writers().await?;
        Ok(())
    }

    /// Component integration in two phases: global Closing rejects live publication without an
    /// ACK while the parent gate is held. After that gate and shutdown finish, a fresh owner runs
    /// explicit recovery and proves the saved original ID/body durably and idempotently.
    #[tokio::test]
    async fn global_seal_skips_report_without_ack_and_retry_proves_the_original_terminal_id()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let resources = crate::studio::storage_fault_test_support::close_factory(&store)?;
        let fixture = Fixture::new(store.clone())?;
        resources.install(&fixture.owner)?;
        let parent = fixture.add("parent", None).await?;
        let child = Fixture::protocol("child", Some("parent"));
        register_test_thread(&store, &child).await?;
        let message_id = crate::studio::agent_close::terminal_report_id("child", 1);
        let terminal_turn = TurnRecord {
            turn_id: "original-terminal-turn".into(),
            input_id: None,
            state: TurnState::Finished(TurnOutcome::Completed),
            model_steps: 0,
            elapsed_ms: None,
        };
        let body = serde_json::to_string(&serde_json::json!({
            "childId": child.id,
            "commitSequence": 1,
            "turn": terminal_turn,
            "turnId": terminal_turn.turn_id,
            "inputId": terminal_turn.input_id,
            "message": "actual terminal fixture",
            "messages": [],
            "runningTasks": [],
            "pendingInteractions": [],
            "permissions": [],
        }))?;
        let message = pl_core::thread::inbox::ThreadMessage {
            kind: AgentMessageKind::Report,
            id: message_id.clone(),
            source_id: "studio.child:child".into(),
            payload: OpaquePayload::new("pl.studio.turn-report", 3, body.clone())?,
            context: vec![ContextContent::Text { text: body.into() }],
        };
        // Save the original body with its terminal effect through the real writer. A ticket
        // without this handoff cannot authorize recovery to reconstruct a report from later state.
        crate::studio::storage_fault_test_support::save_terminal_report(
            &store,
            &child,
            message.clone(),
        )
        .await?;
        let checkpoint = store.history("child").await?.checkpoint().await?;
        let child_sink =
            ThreadStorageSink::new(store.clone(), child.clone(), checkpoint.as_ref()).await?;
        spawn_live_projection(&child_sink);
        let mut closed = ticket("child", 2);
        closed.checkpoint.state.lifecycle = ThreadLifecycle::Closed;
        child_sink.admit("child", closed)?;
        child_sink.flush("child", 2).await?;
        store
            .thread_persistence()
            .history_channel("child")
            .stop_and_join()
            .await?;
        assert_eq!(
            store
                .history("child")
                .await?
                .terminal_report_sequences(0)
                .await?,
            vec![1]
        );
        assert_eq!(
            store
                .history("child")
                .await?
                .terminal_report_sequence("original-terminal-turn")
                .await?,
            Some(1)
        );
        // Recovery must retry the projection's original saved bytes, never a second body with
        // the same terminal ID. The real services below also own cold delivery reconciliation.
        let original = store
            .history("child")
            .await?
            .parent_report(1)
            .await?
            .context("original durable terminal report")?;
        assert_eq!(original, message);
        let root_gate = fixture.owner.agent_operation("parent").await;
        let (entered, registered) = tokio::sync::oneshot::channel();
        let (release, publish) = tokio::sync::oneshot::channel();
        let owner = fixture.owner.clone();
        let source = store.clone();
        let target = child.clone();
        let first_message = message.clone();
        let operations = super::super::agent_operations::AgentOperations::default();
        let job = tokio::spawn(async move {
            operations
                .run(
                    "parent".into(),
                    "report-ack-fixture".into(),
                    || Ok(()),
                    async move {
                        let _parent_resources = root_gate;
                        entered
                            .send(())
                            .map_err(|_| anyhow::anyhow!("registration gate closed"))?;
                        publish.await?;
                        assert_eq!(
                            owner
                                .notify_parent("parent", first_message.clone(), false)
                                .await?,
                            ParentMessageDelivery::Skipped(ParentMessageSkip::Closing)
                        );
                        // Observe the negative live-send result before any explicit recovery.
                        // Full ACK recovery may take this same gate and belongs to phase B.
                        assert!(
                            source
                                .history("parent")
                                .await?
                                .message_identity(&first_message.id)
                                .await?
                                .is_none()
                        );
                        let history = source.history(&target.id).await?;
                        assert_eq!(history.terminal_report_sequences(0).await?, vec![1]);
                        assert_eq!(history.parent_report(1).await?, Some(first_message));
                        assert!(history.checkpoint().await?.is_some());
                        assert!(source.agent_close(&target.id).await?.is_none());
                        drop(_parent_resources);
                        Ok(())
                    },
                )
                .await
        });
        registered.await?;
        let mut shutdown = Box::pin(fixture.owner.close_all());
        assert!(futures::poll!(shutdown.as_mut()).is_pending());
        assert!(fixture.owner.0.state().closing);
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("publication gate closed"))?;
        job.await??;
        assert!(
            store
                .history("parent")
                .await?
                .message_identity(&message_id)
                .await?
                .is_none()
        );
        assert!(store.agent_close("child").await?.is_none());
        assert!(store.history("child").await?.checkpoint().await?.is_some());
        assert!(shutdown.await.is_empty());
        fixture.stop_writers().await?;
        drop(parent);
        drop(fixture);
        let restarted = Fixture::new(store.clone())?;
        resources.install(&restarted.owner)?;
        let parent = restarted.add("parent", None).await?;
        let accepted = restarted
            .owner
            .notify_parent("parent", message.clone(), false)
            .await?;
        let sequence = match accepted {
            ParentMessageDelivery::Accepted { sequence, .. } => sequence,
            other => anyhow::bail!("unexpected retry delivery: {other:?}"),
        };
        assert_eq!(
            restarted
                .owner
                .acknowledge_parent_reports(&store, &child)
                .await?,
            ParentReportAcknowledgement::Proven
        );
        assert_eq!(
            restarted
                .owner
                .notify_parent("parent", message, false)
                .await?,
            ParentMessageDelivery::ProvenExisting {
                message_id: message_id.clone(),
                sequence
            }
        );
        let receipt = store
            .history("parent")
            .await?
            .message_identity(&message_id)
            .await?
            .context("exact durable parent report")?;
        assert_eq!(receipt.sequence, sequence);
        assert_eq!(receipt.digest.as_deref(), Some(original.digest().as_str()));
        assert_eq!(
            store.history("child").await?.parent_report(1).await?,
            Some(original)
        );
        assert_eq!(
            parent
                .snapshot()
                .inbox
                .iter()
                .filter(|entry| entry.message.id == message_id)
                .count(),
            1
        );
        assert!(
            store
                .history("parent")
                .await?
                .message_identity(&crate::studio::agent_close::terminal_report_id("child", 2))
                .await?
                .is_none()
        );
        let absent = Fixture::protocol("no-terminal", Some("parent"));
        register_test_thread(&store, &absent).await?;
        assert_eq!(
            restarted
                .owner
                .acknowledge_parent_reports(&store, &absent)
                .await?,
            ParentReportAcknowledgement::Absent
        );
        assert!(restarted.owner.close_all().await.is_empty());
        restarted.stop_writers().await?;
        resources.shutdown().await?;
        Ok(())
    }
}
