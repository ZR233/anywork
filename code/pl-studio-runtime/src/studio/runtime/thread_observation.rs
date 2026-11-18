//! Owned, retryable product projections of the Thread's committed effect stream.
//!
//! Observation consumes the Thread's reliable admission queue and is its **single realtime
//! projection owner**: it projects every admitted fact and the streaming overlay once, publishes the
//! content into the shared session and broadcasts the same typed changes on a bounded feed that
//! subscriptions only read. Billing, directory and terminal facts come from the same in-memory
//! projection, so an ordinary commit neither parks this observer behind the owner's command queue
//! nor waits for the disk. Installation seeds the projection from the current Core owner and the
//! channel's RAM identity/index; it never reads History to rebuild execution or report material.
mod billing;
mod directory;
pub(in crate::studio) mod publication;
mod reports;
mod slot;
pub(super) mod state_resources;
pub(super) use publication::{ConversationRegistration, ConversationSource};
pub(super) use slot::ObservationSlot;

use super::{ModelPerformanceOwner, StudioRuntime};
use crate::studio::{ProductEventBus, StudioStore};
use anyhow::{Context, Result, bail};
use pl_core::thread::{HistoryExport, ThreadHandle, ThreadLifecycle, ThreadSnapshot, UsageSummary};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
use tokio::{
    sync::{Notify, broadcast, watch},
    task::JoinHandle,
};

use crate::studio::storage::thread_writer::{
    HistoryChannel, PendingProjectionRetention, ProjectionRetention, ProjectionTransfer,
};
use crate::studio::thread_projection::{LiveEvent, LiveProjection, storage_state};
use crate::thread_assembler::agent_review::ReviewDeliverySource;

/// Fixed bound on the frames one subscriber may fall behind the projection owner.
///
/// Slow State receivers lose continuity at this bound; they never delay the owner.
/// Conversation progress is latest-only; immutable completions remain in Session/history.
const LIVE_FEED_FRAMES: usize = 512;

/// One output of a Thread's single realtime projection owner.
#[derive(Debug, Clone)]
pub(in crate::studio) enum ThreadLiveEvent {
    BusinessRefs {
        sequence: u64,
        references: crate::ThreadBusinessRefs,
    },
    /// Changes produced by committed effect `sequence`.
    ///
    /// The vocabulary is deliberately content-free: the projection owner writes every body into the
    /// shared session and the GUI reads it from that one content window, so the status feed carries
    /// only Turn lifecycle and interaction facts. A subscriber therefore never projects or
    /// republishes content.
    Committed {
        sequence: u64,
        changes: Vec<LiveEvent>,
    },
    /// No State frames were prepared because no receiver existed at the preparation boundary.
    /// A receiver whose baseline does not cover this commit must resynchronize, not silently
    /// continue from an older conversation/current cut. This carries no inferred lifecycle fact.
    UnframedCommit { sequence: u64 },
    /// The projection owner could not prove continuity for `dropped` commits and re-seeded; every
    /// subscriber must resynchronize from the database window.
    Rebase { dropped: u64 },
    /// Current runtime facts, including live model availability (absent from checkpoints).
    Runtime {
        observation_revision: u64,
        catalog_revision: u64,
        runtime: Arc<crate::ThreadRuntimeSnapshot>,
        model_route: Option<crate::ThreadModelRouteSnapshot>,
    },
    /// Current execution activity of the Thread; `None` means no activity.
    ///
    /// The activity is an independent typed projection of the same owner state (it never carries a
    /// second copy of the content), so it is published by the same single owner and only when it
    /// really changed; a subscriber only forwards it. It rides as one shared handle rather than an
    /// inline value: the feed is a `broadcast` channel that clones its frame once per subscriber, so
    /// the body must stay cheap to clone and must not bloat the frame every other variant shares.
    Activity {
        observation_revision: u64,
        activity: Option<Arc<crate::ThreadActivity>>,
    },
}

#[derive(Debug, Clone)]
pub(super) struct RuntimeStateCut {
    pub(super) observation_revision: u64,
    pub(super) catalog_revision: u64,
    pub(super) runtime: Arc<crate::ThreadRuntimeSnapshot>,
    pub(super) model_route: Option<crate::ThreadModelRouteSnapshot>,
}

#[derive(Clone)]
pub(super) struct StateActivityCut {
    pub(super) observation_revision: u64,
    pub(super) activity: Option<Arc<crate::ThreadActivity>>,
}

/// A bounded State observation, cancelled with its owner.
///
/// This carries Tokio's explicit lag errors without taking responsibility for reliable delivery
/// capacity. A slow observer must resynchronize; it cannot hold up effect handoff or storage.
pub(in crate::studio) struct StateReceiver {
    receiver: broadcast::Receiver<ThreadLiveEvent>,
    closed: tokio_util::sync::CancellationToken,
}

impl StateReceiver {
    pub(super) fn new(
        receiver: broadcast::Receiver<ThreadLiveEvent>,
        closed: tokio_util::sync::CancellationToken,
    ) -> Self {
        Self { receiver, closed }
    }

    pub(super) fn is_closed(&self) -> bool {
        self.closed.is_cancelled() || (self.receiver.is_closed() && self.receiver.is_empty())
    }

    pub(super) async fn recv(&mut self) -> Result<ThreadLiveEvent, broadcast::error::RecvError> {
        // The owner can retain the Sender while draining storage. Revocation must wake a parked
        // reader and win over buffered frames so neither consumer delivers after owner closure.
        tokio::select! { biased;
            _ = self.closed.cancelled() => Err(broadcast::error::RecvError::Closed),
            result = self.receiver.recv() => result,
        }
    }

    pub(super) fn try_recv(&mut self) -> Result<ThreadLiveEvent, broadcast::error::TryRecvError> {
        if self.closed.is_cancelled() {
            return Err(broadcast::error::TryRecvError::Closed);
        }
        self.receiver.try_recv()
    }
}

/// The realtime projection feed of one Thread.
///
/// The Thread's observation worker is its only producer, and it publishes into the shared chat
/// session at the same time. Subscribers therefore forward typed events and never project, publish
/// or read the effect window themselves.
pub(in crate::studio) struct ThreadLiveFeed {
    delivery_closed: tokio_util::sync::CancellationToken,
    events: broadcast::Sender<ThreadLiveEvent>,
    /// The Thread's authoritative typed storage state, published by this owner only.
    ///
    /// The projection owner is the one place that derives it from the owner snapshot and the
    /// coordinator's typed watch, so a subscriber mirrors this value instead of recomputing the
    /// state from its own copies. A storage pause changes neither the content nor the activity, so
    /// the value is watched on its own instead of riding the content feed: a subscriber parked on
    /// the feed still learns about a pause the moment the owner publishes it.
    storage: watch::Sender<Option<crate::ThreadStorageState>>,
    /// Newest terminal Turn this owner projected, published by this owner only.
    ///
    /// A subscription's authoritative snapshot carries only the *active* Turn, and `turnCompleted`
    /// is broadcast exactly once, so a terminal Turn that committed before a client registered —
    /// a late (re)subscription, or one that resynchronizes after observing a lag — has no other way
    /// to reach it. The owner retains the last terminal Turn here as the same typed fact its frame
    /// carried, so a new subscriber is told the authoritative terminal Turn instead of guessing it
    /// from the timeline window, re-reading SQL, or caching the `running` state it happened to see.
    /// It is a watch rather than a feed frame precisely because it has to outlive the broadcast: a
    /// fact nobody was subscribed for is still the fact the next subscriber must start from.
    last_turn: watch::Sender<Option<Arc<crate::Turn>>>,
    /// Latest shared current content, never a queue of deltas. Subscribers derive their own bounded
    /// increments from these canonical blocks, so coalescing a wakeup cannot drop text.
    conversation: Mutex<Arc<publication::ConversationPublication>>,
    /// Borrowed from this owner's original retained progress, including failures before publication.
    owner_progress: watch::Receiver<Progress>,
    latest_runtime: Mutex<Option<RuntimeStateCut>>,
    /// Original State activity event retained for subscribers opening after its broadcast.
    latest_activity: Mutex<Option<StateActivityCut>>,
    /// 现役 State 协议的通知去重，不拥有业务内容或读取资格。
    latest_business_refs: Mutex<Option<crate::ThreadBusinessRefs>>,
    state_resources: Mutex<state_resources::StateResources>,
}

impl ThreadLiveFeed {
    fn publication(&self) -> Arc<publication::ConversationPublication> {
        self.conversation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    pub(in crate::studio::runtime) fn bind_conversation(
        &self,
        store: &crate::studio::conversation_store::ConversationStore,
        owner_id: String,
    ) {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .bind(owner_id.clone());
        store.publication.bind_current_owner(owner_id);
        *self
            .conversation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = store.publication.clone();
    }

    pub(super) fn is_delivery_closed(&self) -> bool {
        self.delivery_closed.is_cancelled()
    }

    pub(super) async fn delivery_closed(&self) {
        self.delivery_closed.cancelled().await;
    }

    #[cfg(test)]
    pub(super) fn publish_test_state_activity(
        &self,
        observation_revision: u64,
        activity: Option<crate::ThreadActivity>,
    ) {
        self.publish(|| ThreadLiveEvent::Activity {
            observation_revision,
            activity: activity.map(Arc::new),
        });
    }

    fn publish_conversation(
        &self,
        current: Arc<crate::studio::thread_projection::CurrentState>,
    ) -> Result<()> {
        let references = current.business_refs();
        let sequence = current.revision();
        // Install the resource owner before its reference can enter State.
        self.publication().publish(current)?;
        self.publish_business_refs(sequence, references);
        Ok(())
    }

    fn publish_business_refs(&self, sequence: u64, references: crate::ThreadBusinessRefs) {
        let mut previous = self
            .latest_business_refs
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if previous.as_ref() != Some(&references) {
            *previous = Some(references.clone());
            self.publish(|| ThreadLiveEvent::BusinessRefs {
                sequence,
                references,
            });
        }
    }

    pub(super) fn new(
        storage: Option<crate::ThreadStorageState>,
        owner_progress: watch::Receiver<Progress>,
        delivery_closed: tokio_util::sync::CancellationToken,
    ) -> Self {
        let (events, _) = broadcast::channel(LIVE_FEED_FRAMES);
        let (storage, _) = watch::channel(storage);
        let (last_turn, _) = watch::channel(None);
        Self {
            conversation: Mutex::new(Arc::new(publication::ConversationPublication::new())),
            delivery_closed,
            events,
            storage,
            last_turn,
            owner_progress,
            latest_runtime: Default::default(),
            latest_activity: Default::default(),
            latest_business_refs: Default::default(),
            state_resources: Default::default(),
        }
    }

    pub(super) fn conversation(&self) -> ConversationRegistration {
        self.publication().capture(self.owner_progress.clone())
    }
    pub(super) fn current_revision(&self) -> u64 {
        self.publication().metadata_revision()
    }
    pub(super) fn current_conversation(&self) -> Option<Arc<ConversationSource>> {
        self.publication().current()
    }
    pub(super) fn runtime(&self) -> Option<RuntimeStateCut> {
        self.latest_runtime
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(super) fn state_resources(&self) -> state_resources::StateResources {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn compact_runtime(
        &self,
        runtime: crate::ThreadRuntimeSnapshot,
    ) -> Result<crate::ThreadRuntimeSnapshot> {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .runtime(runtime)
    }

    fn compact_activity(
        &self,
        activity: Option<crate::ThreadActivity>,
    ) -> Result<Option<crate::ThreadActivity>> {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .activity(activity)
    }

    pub(super) fn state_activity(&self) -> Option<StateActivityCut> {
        self.latest_activity
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(in crate::studio) fn subscribe(&self) -> StateReceiver {
        StateReceiver::new(self.events.subscribe(), self.delivery_closed.clone())
    }

    /// Watches the newest terminal Turn this owner projected, so a subscriber that registers after
    /// that commit never has to derive the fact from the window or from SQL.
    pub(in crate::studio) fn last_turn(&self) -> watch::Receiver<Option<Arc<crate::Turn>>> {
        self.last_turn.subscribe()
    }

    /// Publishes the newest terminal Turn the owner projected.
    ///
    /// Only a terminal Turn qualifies: the running Turn is already the authoritative snapshot's own
    /// fact, and replacing the retained terminal Turn with a busy one would let a resubscribing
    /// client mistake an in-flight Turn for the last finished one. A committed effect can also reach
    /// this owner *after* a newer one — a deferred admission that storage pressure released late is
    /// taken over behind the live stream — so the retained fact only ever moves forward and the newest
    /// terminal Turn is never replaced by an older one.
    fn publish_last_turn(&self, turn: Arc<crate::Turn>) {
        if self.is_delivery_closed() {
            return;
        }
        let current = self.last_turn.borrow().clone();
        if let Some(current) = current.as_ref() {
            // Only a strictly newer fact moves the slot. A duplicate of the newest fact — the same
            // effect sequence and identity, e.g. a cold seed the live path then re-derives — would
            // only wake every subscriber to deliver nothing, and a terminal Turn that storage
            // pressure released late must never replace a newer one.
            if current.revision > turn.revision
                || (current.revision == turn.revision && current.id == turn.id)
            {
                return;
            }
        }
        self.last_turn.send_replace(Some(turn));
    }

    /// Watches the owner's typed storage state, so a subscriber only mirrors it.
    pub(in crate::studio) fn storage(&self) -> watch::Receiver<Option<crate::ThreadStorageState>> {
        self.storage.subscribe()
    }

    /// Publishes the owner's newly derived typed storage state.
    fn publish_storage(&self, storage: Option<crate::ThreadStorageState>) {
        self.publication().metadata_changed();
        self.storage.send_replace(storage);
    }

    fn has_subscribers(&self) -> bool {
        !self.delivery_closed.is_cancelled() && self.events.receiver_count() != 0
    }

    fn publish(&self, event: impl FnOnce() -> ThreadLiveEvent) {
        // Demand is advisory, not the registration barrier. Facts and retained watches are updated
        // independently; no outward envelope (or its dedicated clone) is built without a receiver.
        let event = event();
        self.publication().metadata_changed();
        if let ThreadLiveEvent::Activity {
            observation_revision,
            activity,
        } = &event
        {
            let mut latest = self
                .latest_activity
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if latest
                .as_ref()
                .is_none_or(|cut| *observation_revision > cut.observation_revision)
            {
                *latest = Some(StateActivityCut {
                    observation_revision: *observation_revision,
                    activity: activity.clone(),
                });
            }
        }
        if let ThreadLiveEvent::Runtime {
            runtime,
            model_route,
            observation_revision,
            catalog_revision,
        } = &event
        {
            *self
                .latest_runtime
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(RuntimeStateCut {
                observation_revision: *observation_revision,
                catalog_revision: *catalog_revision,
                runtime: runtime.clone(),
                model_route: model_route.clone(),
            });
        }
        if self.has_subscribers() {
            let _ = self.events.send(event);
        }
    }

    /// Tells every subscriber that the owner re-seeded and continuity is no longer provable.
    fn rebase(&self, dropped: u64) {
        self.publish(|| ThreadLiveEvent::Rebase { dropped });
    }
}

#[derive(Clone, Default)]
pub(super) struct Progress {
    initialized: bool,
    applied: u64,
    /// Newest commit this projection owner had handed over when it applied `applied`.
    ///
    /// The durable barrier of a settled observation waits for exactly this ticket. It is not the
    /// absolute commit watermark: a Thread re-activated in this process starts from a fresh reliable
    /// channel whose commits are already durable, so waiting for the checkpoint's sequence would wait
    /// for a watermark that can never move.
    handoff: u64,
    error: Option<Arc<anyhow::Error>>,
    finished: bool,
}

impl Progress {
    pub(super) fn retained_error(&self) -> Option<Arc<anyhow::Error>> {
        self.error.clone()
    }

    pub(super) fn is_finished(&self) -> bool {
        self.finished
    }
}

struct WorkerState {
    /// Frozen at observer installation, before any asynchronous history preparation can finish late.
    native_directory: Option<crate::studio::product_event_bus::NativeAgentObservation>,
    deletion: tokio_util::sync::CancellationToken,
    join_failure: std::sync::Mutex<Option<Arc<anyhow::Error>>>,
    terminal_transfer: Arc<
        std::sync::Mutex<Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>>,
    >,
    progress: watch::Sender<Progress>,
    retry: Notify,
    /// The Thread's reliable admission channel, shared with its history writer.
    ///
    /// An explicit synchronization asks the writer that took the projection's handoff how far
    /// it is durable. Live processing never waits for that barrier. The handle is captured
    /// here, at observation time, so the barrier observes the very incarnation the writer admits
    /// into instead of a channel that a cleanly detached predecessor already released.
    channel: Arc<HistoryChannel>,
    /// Explicit reconciliation is observation only, even when it catches a newly committed Turn.
    reconciliation_through: Arc<std::sync::atomic::AtomicU64>,
    observed_before_execution: bool,
}
pub(crate) struct Observation {
    owner: std::sync::Weak<crate::session::NativeResources>,
    thread: ThreadHandle,
    feed: Arc<ThreadLiveFeed>,
    state: Arc<WorkerState>,
    task: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}
impl Drop for Observation {
    fn drop(&mut self) {
        if let Some(task) = self.task.get_mut().take() {
            task.abort();
        }
    }
}

impl Observation {
    async fn join(&self) -> Result<()> {
        self.join_for_purpose(crate::thread_assembler::ClosePurpose::Preserve)
            .await
    }

    async fn join_for_purpose(&self, purpose: crate::thread_assembler::ClosePurpose) -> Result<()> {
        let mut slot = self.task.lock().await;
        if let Some(task) = slot.as_mut() {
            let joined = task.await;
            *slot = None;
            if let Err(error) = joined {
                let error = Arc::new(anyhow::Error::new(error));
                *self
                    .state
                    .join_failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(error.clone());
                self.state.progress.send_modify(|progress| {
                    progress.finished = true;
                    progress.error = Some(error.clone());
                });
                bail!("Thread product observer join failed: {error:#}");
            }
            if purpose == crate::thread_assembler::ClosePurpose::Preserve
                && !self.state.progress.borrow().finished
            {
                let error = Arc::new(anyhow::anyhow!(
                    "Thread product observer ended without its final durable projection"
                ));
                self.state.progress.send_modify(|progress| {
                    progress.finished = true;
                    progress.error = Some(error.clone());
                });
            }
        }
        if let Some(error) = self
            .state
            .join_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
        {
            bail!("Thread product observer join failed: {error:#}");
        }
        if purpose == crate::thread_assembler::ClosePurpose::Delete {
            return Ok(());
        }
        if let Some(error) = self.state.progress.borrow().error.as_ref() {
            bail!("Thread product observer failed: {error:#}");
        }
        Ok(())
    }
}
#[derive(Clone)]
pub(super) struct ObservationServices {
    pub(super) config: crate::config::ConfigRuntime,
    pub(super) settings_updates: watch::Receiver<crate::config::ConfigRuntimeSnapshot>,
    pub(super) recovery: crate::studio::StudioRecoveryRegistry,
    pub(super) store: StudioStore,
    pub(super) events: ProductEventBus,
    pub(super) performance: ModelPerformanceOwner,
    pub(super) sessions: crate::session::WeakSessionTable,
    pub(super) writer: crate::studio::agent_host::ThreadWriteBehindWriter,
    pub(super) run_export: Option<std::sync::Arc<super::run_export::RunExportCoordinator>>,
}
impl ObservationServices {
    fn session_of(&self, id: &str) -> Option<crate::session::SessionRuntime> {
        if let Some((identity, _, _)) = self.events.agent_execution_identity(id) {
            return self.sessions.upgrade()?.get(&identity.session_id);
        }
        self.sessions.upgrade()?.holding(id)
    }

    fn require_session(&self, id: &str) -> Result<crate::session::SessionRuntime> {
        self.session_of(id)
            .context("Thread has no resident session")
    }
}
struct Shared {
    delivery_closed: tokio_util::sync::CancellationToken,
    projector: ObservationServices,
    observations: Mutex<BTreeMap<String, Vec<std::sync::Weak<Observation>>>>,
    /// Stable passive slots survive absent → live → absent transitions.
    live: Mutex<BTreeMap<String, Arc<ObservationSlot>>>,
}
#[derive(Clone)]
pub(super) struct ThreadObservations(Arc<Shared>);

impl ThreadObservations {
    fn observations(&self, id: Option<&str>) -> Vec<(String, Arc<Observation>)> {
        self.0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|(key, _)| id.is_none_or(|id| key.as_str() == id))
            .flat_map(|(id, entries)| {
                entries
                    .iter()
                    .filter_map(std::sync::Weak::upgrade)
                    .map(|entry| (id.clone(), entry))
            })
            .collect()
    }

    pub(super) fn new(projector: ObservationServices) -> Self {
        Self(Arc::new(Shared {
            delivery_closed: Default::default(),
            projector,
            observations: Mutex::new(BTreeMap::new()),
            live: Mutex::new(BTreeMap::new()),
        }))
    }

    /// The live feed of one observed Thread, if its projection owner was installed.
    pub(super) fn live_feed(&self, id: &str) -> Option<Arc<ThreadLiveFeed>> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|slot| slot.source())
    }

    /// End outward delivery before joining producers; their original save
    /// responsibility continues independently of an idle external receiver.
    pub(super) fn close_deliveries(&self) {
        self.0.delivery_closed.cancel();
    }

    pub(super) fn read_lifetime(&self) -> tokio_util::sync::CancellationToken {
        self.0.delivery_closed.clone()
    }

    fn close_delivery(&self, id: &str, thread: &ThreadHandle) {
        for (_, observation) in self.observations(Some(id)) {
            if observation.thread.same_instance(thread) {
                observation.feed.delivery_closed.cancel();
            }
        }
    }

    /// Register the passive source before asynchronous reads without activating execution.
    pub(super) fn observation_slot(&self, id: &str) -> Arc<ObservationSlot> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(id.to_owned())
            .or_default()
            .clone()
    }

    pub(super) fn install(&self) -> Result<()> {
        let observations = Arc::downgrade(&self.0);
        self.0
            .projector
            .sessions
            .upgrade()
            .context("Session table closed")?
            .push_installer(Arc::new(move |session| {
                let observations = observations
                    .upgrade()
                    .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                ThreadObservations(observations)
                    .install_session(session)
                    .map_err(
                        |source| crate::thread_assembler::ThreadAssemblyError::Resource {
                            operation: "install session observations",
                            source: source.into_boxed_dyn_error(),
                        },
                    )
            }))?;
        Ok(())
    }

    fn install_session(&self, session: &crate::session::SessionRuntime) -> Result<()> {
        let owner = Arc::downgrade(&self.0);
        let draining = owner.clone();
        let synchronizing = owner.clone();
        let closing = owner.clone();
        let terminal = owner.clone();
        session.observe_assembly(
            move |id, thread, resources| {
                if let Some(owner) = owner.upgrade() {
                    ThreadObservations(owner).observe(id, thread, resources);
                }
            },
            move |id, purpose| {
                let owner = draining.clone();
                Box::pin(async move {
                    let owner = owner
                        .upgrade()
                        .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    let observations = ThreadObservations(owner);
                    if purpose == crate::thread_assembler::ClosePurpose::Preserve {
                        observations
                            .synchronize(Some(&id))
                            .await
                            .map_err(|source| {
                                crate::thread_assembler::ThreadAssemblyError::Resource {
                                    operation: "drain Thread product observation",
                                    source: source.into_boxed_dyn_error(),
                                }
                            })?;
                    }
                    observations
                        .drain_for_purpose(&id, purpose)
                        .await
                        .map_err(|source| {
                            crate::thread_assembler::ThreadAssemblyError::Resource {
                                operation: "join Thread storage and observation workers",
                                source: source.into_boxed_dyn_error(),
                            }
                        })?;
                    Ok(())
                })
            },
            Some(Arc::new(move |id: &str| {
                let owner = terminal.upgrade()?;
                let (position, _) = ThreadObservations(owner).observation_slot(id).capture();
                let feed = position
                    .source
                    .filter(|source| !source.is_delivery_closed())?;
                feed.last_turn.borrow().clone()
            })),
            move |id, thread, purpose| {
                if let Some(owner) = closing.upgrade() {
                    let observations = ThreadObservations(owner);
                    observations.close_delivery(&id, &thread);
                    if purpose == crate::thread_assembler::ClosePurpose::Delete {
                        observations.cancel_for_deletion(&id);
                    }
                }
                Box::pin(async { Ok(()) })
            },
            move |id| {
                let owner = synchronizing.clone();
                Box::pin(async move {
                    let owner = owner
                        .upgrade()
                        .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    ThreadObservations(owner)
                        .synchronize(Some(&id))
                        .await
                        .map_err(
                            |source| crate::thread_assembler::ThreadAssemblyError::Resource {
                                operation: "acknowledge parent report handoff",
                                source: source.into_boxed_dyn_error(),
                            },
                        )
                })
            },
        )?;
        Ok(())
    }

    fn cancel_for_deletion(&self, id: &str) {
        for (_, observation) in self.observations(Some(id)) {
            observation.state.deletion.cancel();
        }
    }

    async fn drain_for_purpose(
        &self,
        id: &str,
        purpose: crate::thread_assembler::ClosePurpose,
    ) -> Result<()> {
        let observations = self
            .observations(Some(id))
            .into_iter()
            .map(|(_, observation)| observation)
            .collect::<Vec<_>>();
        let feed = self.live_feed(id);
        for observation in &observations {
            anyhow::ensure!(
                observation.thread.snapshot().lifecycle == ThreadLifecycle::Closed,
                "cannot retire workers of an open Thread"
            );
            observation.join_for_purpose(purpose).await?;
            if purpose == crate::thread_assembler::ClosePurpose::Delete {
                observation
                    .state
                    .channel
                    .stop_and_join_for_deletion()
                    .await?;
            } else {
                observation.state.channel.stop_and_join().await?;
            }
        }
        for observation in &observations {
            if let Some(owner) = observation.owner.upgrade() {
                owner
                    .observations
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .retain(|current| !Arc::ptr_eq(current, observation));
            }
        }
        let mut all = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(entries) = all.get_mut(id) {
            entries.retain(|entry| {
                entry
                    .upgrade()
                    .is_some_and(|entry| !observations.iter().any(|old| Arc::ptr_eq(&entry, old)))
            });
            if entries.is_empty() {
                all.remove(id);
            }
        }
        drop(all);
        if let Some(feed) = feed {
            self.observation_slot(id).retire(&feed);
        }
        Ok(())
    }

    fn observe(
        &self,
        id: String,
        thread: ThreadHandle,
        resources: Arc<crate::session::NativeResources>,
    ) {
        let observed = thread.snapshot();
        let recovered_through = observed.commit_sequence;
        // Bootstrap facts/extensions can already have commits. The monotonic execution/call
        // ledgers, not a zero commit fence, prove that no prior model Turn needs reconciliation.
        let observed_before_execution = observed.lifecycle == ThreadLifecycle::Open
            && observed.execution_sequence == 0
            && observed.execution.is_none()
            && observed.turns.is_empty()
            && observed.attempts.is_empty()
            && observed.attempt_ids.is_empty()
            && observed.live_calls.is_empty()
            && observed
                .context
                .records
                .iter()
                .all(|record| record.turn_id.is_none());
        let (progress, _) = watch::channel(Progress {
            applied: recovered_through,
            ..Progress::default()
        });
        // The same channel the writer incarnation admits into: the observation barrier below asks
        // this handle how far the writer is durable, not a freshly created one.
        let channel = self
            .0
            .projector
            .store
            .thread_persistence()
            .history_channel(&id);
        let state = Arc::new(WorkerState {
            native_directory: self.0.projector.events.begin_native_observation(&id),
            deletion: Default::default(),
            join_failure: Default::default(),
            terminal_transfer: Default::default(),
            progress,
            retry: Notify::new(),
            channel,
            reconciliation_through: Arc::new(std::sync::atomic::AtomicU64::new(recovered_through)),
            observed_before_execution,
        });
        // Seed the feed with the newest typed storage state the coordinator already reports, so a
        // subscriber that opens before this owner's first pass mirrors a real fact instead of an
        // unset placeholder. The owner republishes its own derivation on the first pass.
        let initial_storage = self
            .0
            .projector
            .store
            .thread_persistence()
            .snapshot()
            .threads
            .iter()
            .find(|detail| detail.thread_id == id)
            .map(|detail| storage_state(&thread.snapshot(), detail));
        // Register the non-replayable catalog source before publishing the feed.
        let catalogs = self.0.projector.config.subscribe_model_catalogs();
        let feed = Arc::new(ThreadLiveFeed::new(
            initial_storage,
            state.progress.subscribe(),
            self.0.delivery_closed.child_token(),
        ));
        self.observation_slot(&id).install(feed.clone());
        let worker_state = state.clone();
        let projector = self.0.projector.clone();
        let worker_thread = thread.clone();
        let worker_id = id.clone();
        let observed_feed = feed.clone();
        let deletion = state.deletion.clone();
        let task = tokio::spawn(async move {
            tokio::select! {
                biased;
                () = deletion.cancelled() => {},
                () = run(
                projector,
                worker_id,
                worker_thread,
                worker_state,
                recovered_through,
                feed,
                catalogs,
                ) => {},
            }
        });
        let observation = Arc::new(Observation {
            owner: Arc::downgrade(&resources),
            thread,
            feed: observed_feed,
            state,
            task: tokio::sync::Mutex::new(Some(task)),
        });
        resources
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(observation.clone());
        let mut all = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let previous = all.entry(id).or_default();
        previous.retain(|entry| entry.strong_count() > 0);
        previous.push(Arc::downgrade(&observation));
    }

    pub(super) async fn synchronize(&self, id: Option<&str>) -> Result<()> {
        self.0.projector.writer.retry_now();
        let observations = self.observations(id);
        for (id, observation) in observations {
            let target_snapshot = observation.thread.snapshot();
            let target = target_snapshot.commit_sequence;
            // A fixed durability wait is not a new observation source. Only recovery from a
            // discontinuity revokes first-send authority; otherwise a caller merely observing a
            // healthy terminal could race and cancel its legitimate live feedback.
            if observation.state.progress.borrow().error.is_some() {
                observation
                    .state
                    .reconciliation_through
                    .fetch_max(target, std::sync::atomic::Ordering::AcqRel);
            }
            // The explicit retry only wakes the worker: an unresolved error is reported as it
            // stands, and only the worker's own successful pass — which replaces the whole
            // progress value, error included — can settle the observation again.
            observation.state.retry.notify_one();
            let durable_through =
                await_settled_target(&id, observation.as_ref(), &target_snapshot).await?;
            // A settled observation is also durable. Observation no longer flushes history per batch,
            // so this barrier is what keeps "the observer applied commit N" meaning "history holds
            // commit N" for explicit history queries and shutdown verification. The wait is for
            // the handoff ticket the
            // projection had reached when it applied `target` — every commit up to `target` it owns —
            // so it neither waits on the owner's command queue nor on a later, unprojected commit, and
            // it never asks for a watermark a channel created by a re-activation cannot move.
            await_history_durable(&observation.state.channel, &id, durable_through)
                .await
                .with_context(|| format!("Thread {id} product observation barrier"))?;
        }
        // The observation worker no longer waits on disk for each projected batch, so the explicit
        // sync barrier carries the durability: every product write admitted up to the watermark this
        // barrier just waited for is drained before the caller observes a settled terminal state.
        // The target is fixed at call time, so this never waits for unrelated later writes.
        let target = self.0.projector.writer.admitted_ticket();
        self.0.projector.writer.flush_through(target).await?;
        Ok(())
    }

    /// Explicit parent continuation repairs only Current-backed pending Native deliveries even for
    /// unloaded children. It may prepare storage, but opens no child model, tool or workspace.
    pub(super) async fn reconcile_children(&self, parent: &str) -> Result<()> {
        let services = &self.0.projector;
        let parent_record = services
            .store
            .read_thread(parent)
            .await?
            .context("missing parent Thread record")?;
        services
            .require_session(parent)?
            .recover_saved_review_deliveries(&crate::Thread::from(parent_record))
            .await?;
        for member in services.store.read_directory_tree(parent).await? {
            if !member.is_native() || member.parent_thread_id.as_deref() != Some(parent) {
                continue;
            }
            let child =
                crate::studio::records::thread_projection(&member.session, &member.agent, |id| {
                    services
                        .store
                        .catalog()
                        .get_agent(id)
                        .map(|agent| agent.thread_id)
                })?;
            if services
                .session_of(&child.id)
                .and_then(|session| session.thread(&child.id))
                .is_some()
            {
                self.synchronize(Some(&child.id)).await?;
                services
                    .require_session(&child.id)?
                    .recover_saved_review_deliveries(&child)
                    .await?;
                continue;
            }
            // Parent recovery explicitly prepares its cold children's storage before projecting
            // their facts. It never activates a child, rebuilds its workspace or asks a model.
            // A complete Current can retain large domain state. Keep its
            // recovery result on the heap across directory/delivery awaits.
            let Some(current) = Box::pin(async {
                crate::studio::thread_factory::recovery::load_current_for_recovery(
                    &services.store,
                    &child,
                )
                .await
                .map(|current| current.map(Box::new))
            })
            .await?
            else {
                continue;
            };
            // A cold child's interruption is a fact the list must publish: a restart otherwise loses
            // "stopped, waiting for the main agent" for every member that is not loaded again. This
            // reads only the complete saved Current — no activation, no workspace, no model request.
            directory::publish_cold_scheduling_state(
                services,
                &child,
                &member.agent,
                &current.state.to_paused_snapshot(),
            )
            .await?;
            services
                .require_session(&child.id)?
                .recover_saved_review_deliveries(&child)
                .await?;
        }
        Ok(())
    }

    pub(super) async fn finish(&self) -> Result<()> {
        // 执行实例更换保留内容资格；整个运行时结束则封闭旧资格并等待在途读取。
        self.close_deliveries();
        let slots = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for slot in slots {
            slot.close_readers().await?;
        }
        self.synchronize(None).await?;
        let observations = self
            .observations(None)
            .into_iter()
            .map(|(_, observation)| observation);
        for observation in observations {
            let mut progress = observation.state.progress.subscribe();
            loop {
                let state = progress.borrow().clone();
                if let Some(error) = state.error {
                    bail!("Thread product observer failed: {error:#}");
                }
                if state.finished {
                    break;
                }
                tokio::select! {
                    changed = progress.changed() => {
                        changed.context("Thread product observer ended without final state")?;
                    }
                    joined = observation.join() => joined?,
                }
            }
            observation.join().await?;
            observation.state.channel.stop_and_join().await?;
        }
        Ok(())
    }
}

impl StudioRuntime {
    /// Waits for product directories and billing to reach the current committed Thread watermark.
    /// Reattempts a previously failed projection without invoking models or tools.
    pub async fn synchronize_thread_observation(&self, thread_id: &str) -> Result<()> {
        self.thread_observations
            .synchronize(Some(thread_id))
            .await?;
        self.require_session(thread_id)?
            .settle_review_deliveries(thread_id)
            .await?;
        self.thread_observations.synchronize(Some(thread_id)).await
    }
}

/// 同一稳定 Store 的串行执行驱动；借用投影，退出时将原批次归还 Store。
///
/// It lives in the Thread's observation worker, so a GUI opening and closing never changes who
/// projects or who publishes content: every committed effect is projected exactly once into the
/// shared chat session, and its typed changes are broadcast to whichever subscribers exist. The same
/// batch is handed to the Thread's reliable admission channel, so the history writer commits the
/// content this owner published instead of projecting the effect a second time.
/// Store 保留投影和至多一个原交接批次；执行驱动仅在租约期间借用它。
pub(in crate::studio) struct RetainedProjection {
    pub(in crate::studio) projection: LiveProjection,
    pub(in crate::studio) pending: Option<PendingHandoff>,
    pub(in crate::studio) baseline: Option<Arc<crate::studio::thread_projection::CurrentState>>,
    usage: UsageSummary,
}

struct ProjectionLease {
    store: Arc<crate::studio::conversation_store::ConversationStore>,
    value: Option<RetainedProjection>,
}
impl ProjectionLease {
    fn claim(store: Arc<crate::studio::conversation_store::ConversationStore>) -> Result<Self> {
        let value = store.take_projection()?;
        Ok(Self { store, value })
    }
}
impl std::ops::Deref for ProjectionLease {
    type Target = RetainedProjection;
    fn deref(&self) -> &Self::Target {
        self.value.as_ref().expect("initialized projection lease")
    }
}
impl std::ops::DerefMut for ProjectionLease {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.value.as_mut().expect("initialized projection lease")
    }
}
impl Drop for ProjectionLease {
    fn drop(&mut self) {
        self.store.retain_projection(self.value.take());
    }
}

struct LiveOwner {
    history_reader: crate::history::HistoryReader,
    native_directory: Option<crate::studio::product_event_bus::NativeAgentObservation>,
    terminal_transfer: Arc<
        std::sync::Mutex<Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>>,
    >,
    terminal_revocation: Arc<std::sync::atomic::AtomicU64>,
    terminal_floor: u64,
    first_send: bool,
    config: crate::config::ConfigRuntime,
    qualification_revision: u64,
    retained: ProjectionLease,
    binding: Option<Arc<crate::studio::ThreadStorageBinding>>,
    /// The Thread's only activity projection: the same owner derives it from the snapshot it just
    /// published, so activity never becomes a second fact source and never reads SQL.
    /// Last activity already broadcast, so an unchanged projection does not produce a frame.
    activity_published: Option<crate::ThreadActivity>,
    runtime_published: Option<crate::ThreadRuntimeSnapshot>,
    model_route_published: Option<crate::ThreadModelRouteSnapshot>,
    /// Last typed storage state this owner published to its feed.
    ///
    /// The owner derives it from the owner snapshot plus the coordinator's typed watch, so a
    /// subscriber mirrors the value instead of recomputing it from its own copies. It is kept as one
    /// value so a change of fault kind, generation, watermark or phase is all one comparison.
    storage_published: Option<crate::ThreadStorageState>,
    /// The Thread's reliable admission channel, shared with the history writer.
    channel: Arc<HistoryChannel>,
    thread: crate::Thread,
    feed: Arc<ThreadLiveFeed>,
}

/// Which path a retained handoff batch came from; a retry never re-decides it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HandoffMode {
    /// The realtime path: accounting folded and the projection advanced with the delivery decision
    /// of the moment it was projected.
    Live,
    /// A commit the owner already held before this projection existed: folded for durability only,
    /// it never gains realtime publication rights.
    Behind,
}

/// One committed batch this projection owner prepared but has not handed to the writer yet.
///
/// This is not a second ledger: it is the single in-flight handoff of the owner's serial pass, at
/// most one batch, holding the very `ThreadWrite` the reliable queue admitted and the prepared
/// content the writer will commit. Retaining it closes the window between the report preparation
/// and the handoff — a failure, a cancelled wait or an explicit retry re-enters this same batch
/// instead of projecting the same commit a second time and bumping its content revisions.
pub(in crate::studio) struct PendingHandoff {
    pub(in crate::studio) write: Arc<HistoryExport>,
    pub(in crate::studio) prepared: Arc<crate::studio::thread_projection::PreparedEffect>,
    pub(in crate::studio) admitted: bool,
    /// Managed terminal delivery prepared from the same frozen report, still owned here until the
    /// reliable channel accepts this batch (or proves the same sequence already durable).
    terminal: Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>,
    /// The delivery changes the live path decided when it projected the commit; `None` on the
    /// behind path and when the projection produced no frame.
    changes: Option<Vec<LiveEvent>>,
    mode: HandoffMode,
}

impl PendingHandoff {
    /// Delivery changes owned here in addition to the shared prepared batch.
    pub(in crate::studio) fn extra_retained_bytes(&self) -> u64 {
        // The prepared batch is measured by its owning projection (`PreparedEffect::retained_bytes`,
        // the one implementation the writer shares); the delivery changes are this owner's own
        // residents and are charged element by element.
        let mut bytes = 0_u64;
        if let Some(changes) = self.changes.as_ref() {
            for event in changes {
                bytes = bytes.saturating_add(event.retained_bytes());
            }
            // The Vec's spare capacity is resident too: every used element's shell is already part
            // of its own estimate, so only the unused slots add their element size here.
            let spare = changes.capacity() - changes.len();
            bytes = bytes.saturating_add(
                u64::try_from(spare)
                    .unwrap_or(u64::MAX)
                    .saturating_mul(std::mem::size_of::<LiveEvent>() as u64),
            );
        }
        bytes
    }

    /// Attaches the prepared batch to the reliable queue and publishes the accepted facts.
    ///
    /// # Errors
    /// The channel refused the handoff — the sequence is already durable or is not an admitted
    /// commit of this channel. The batch stays fully retained with its identity, so the refusal
    /// reaches the caller instead of a silent loss or a re-projection.
    fn hand_over(
        &self,
        channel: &HistoryChannel,
        feed: &ThreadLiveFeed,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let sequence = self.prepared.sequence;
        if !self.admitted && !channel.prepare(Arc::clone(&self.prepared)) {
            anyhow::bail!("reliable channel refused the handoff of live Thread commit {sequence}");
        }
        // Only the prepared content is authoritative for the terminal fact — never the optional
        // delivery changes, which a zero-subscriber commit may not carry at all.
        if let Some(turn) = crate::studio::thread_projection::prepared_terminal_turn(&self.prepared)
        {
            feed.publish_last_turn(Arc::new(turn));
        }
        if self.mode == HandoffMode::Live {
            feed.publish(|| match self.changes.as_ref() {
                Some(changes) => ThreadLiveEvent::Committed {
                    sequence,
                    changes: changes.clone(),
                },
                None => ThreadLiveEvent::UnframedCommit { sequence },
            });
        }
        Ok(self.prepared.parent_report.clone())
    }
}

impl LiveOwner {
    async fn open(
        projector: &ObservationServices,
        handle: &ThreadHandle,
        snapshot: &ThreadSnapshot,
        thread: crate::Thread,
        feed: Arc<ThreadLiveFeed>,
        state: Arc<WorkerState>,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) -> Result<Self> {
        let channel = state.channel.clone();
        let id = thread.id.as_str();
        let conversation = projector.store.conversation_store(id).await?;
        #[cfg(not(test))]
        let binding = projector
            .session_of(id)
            .map(|session| session.projection_storage_binding(id))
            .transpose()?
            .flatten();
        #[cfg(test)]
        let binding = projector
            .session_of(id)
            .and_then(|session| session.projection_storage_binding(id).ok())
            .flatten();
        #[cfg(not(test))]
        anyhow::ensure!(binding.is_some(), "execution has no storage binding");
        if let Some(binding) = &binding {
            conversation.attach_execution(binding).await?;
        }
        conversation.attach_current(handle.clone()).await?;
        feed.bind_conversation(&conversation, handle.runtime_epoch().to_string());
        let history = projector.store.history(id).await?;
        let history_reader = history.reader();
        let usage = snapshot.usage_summary.clone();
        let runtime_epoch = handle.runtime_epoch();
        let initialized = conversation
            .initialize_projection(Arc::new({
                let channel = channel.clone();
                let thread = thread.clone();
                let snapshot = snapshot.clone();
                let usage = usage.clone();
                move || {
                    let (channel, thread, snapshot, usage, history, runtime_epoch) = (
                        channel.clone(),
                        thread.clone(),
                        snapshot.clone(),
                        usage.clone(),
                        history.clone(),
                        runtime_epoch,
                    );
                    Box::pin(async move {
                        let mut projection = LiveProjection::new();
                        projection.bind_execution(
                            channel.order_index(),
                            runtime_epoch,
                            history.database_id().to_owned(),
                        )?;
                        // Current starts a new runtime epoch; it must not replay R1 history into
                        // R2's live publication rights. Late facts query HistoryReader by owner.
                        projection.restore_current(&thread, &snapshot).await?;
                        let baseline = projection.current_state();
                        Ok(RetainedProjection {
                            projection,
                            pending: None,
                            baseline,
                            usage,
                        })
                    })
                }
            }))
            .await;
        if let Err(error) = initialized {
            return match conversation
                .close_current(handle, crate::thread_assembler::ClosePurpose::Preserve)
                .await
            {
                Ok(()) => Err(error),
                Err(close) => Err(error.context(format!(
                    "closing current after projection initialization failure: {close:#}"
                ))),
            };
        }
        let retained = match ProjectionLease::claim(conversation.clone()) {
            Ok(retained) => retained,
            Err(error) => {
                return match conversation
                    .close_current(handle, crate::thread_assembler::ClosePurpose::Preserve)
                    .await
                {
                    Ok(()) => Err(error),
                    Err(close) => Err(error.context(format!(
                        "closing current after projection ownership failure: {close:#}"
                    ))),
                };
            }
        };
        // Publish the first activity only after this snapshot's admitted completions have been
        // folded below. Seeding the summary here would suppress that first shared content publish.
        let activity_published = None;
        // The owner is the single source of the typed storage state: publish the value it was
        // installed with, so a subscriber that opened before this first pass sees the authoritative
        // fact instead of an unset placeholder.
        let storage_published = persistence.map(|detail| storage_state(snapshot, detail));
        // A subscriber may already have an older catalog baseline while this
        // owner initializes. Publish the initial qualification too; its source
        // stamps let a current subscriber discard it without manufacturing a gap.
        let runtime = crate::studio::thread_projection::project_runtime(
            id,
            snapshot,
            thread.updated_at,
            &usage,
        )?;
        let mut model_route = crate::studio::model_route::projected(snapshot)?;
        let (config, catalog) = projector.config.read_with_catalog()?;
        crate::studio::model_route::annotate_availability(
            model_route.as_mut(),
            &thread,
            &config.config,
        )?;
        let compact_runtime = feed.compact_runtime(runtime.clone())?;
        feed.publish(|| ThreadLiveEvent::Runtime {
            observation_revision: snapshot.observation_revision,
            catalog_revision: catalog.revision,
            runtime: Arc::new(compact_runtime),
            model_route: model_route.clone(),
        });
        let runtime_published = Some(runtime);
        let model_route_published = model_route;
        feed.publish_storage(storage_published.clone());
        let owner = Self {
            history_reader,
            native_directory: state.native_directory.clone(),
            terminal_transfer: state.terminal_transfer.clone(),
            terminal_revocation: state.reconciliation_through.clone(),
            terminal_floor: state.progress.borrow().applied,
            first_send: state.observed_before_execution,
            config: projector.config.clone(),
            qualification_revision: catalog.revision,
            retained,
            binding,
            activity_published,
            runtime_published,
            model_route_published,
            storage_published,
            channel,
            thread,
            feed,
        };
        // The seeded facts are already resident, so the Thread's budget covers them from the moment
        // the owner is installed instead of only after its first commit.
        owner.publish_retained()?;
        // Terminal Turn history is served by the independent HistoryReader. Replaying it into the
        // new runtime epoch would recreate presentation restore and can publish an old run's fact.
        Ok(owner)
    }

    /// Publishes how much this projection currently retains in its own tables.
    ///
    /// The projection owns the retained bodies and the Turn report accumulator, and both outlive
    /// the batch the writer already committed. The reliable channel's budget is what pauses new
    /// model/tool admission at a safe gap, so it has to see this number; nothing here waits for a
    /// GUI, because the owner publishes whether or not anyone is subscribed.
    fn retention(&self) -> ProjectionRetention {
        // The activity summary and its bounded resident detail are resident facts of the same owner,
        // so they belong to the same Thread budget instead of living outside it.
        let mut bytes = self.retained.projection.retained_bytes();
        // The pending handoff batch is real resident product content this owner still holds. It is
        // charged here — under the same Thread budget — until the reliable channel takes it over;
        // the queue's own `ThreadWrite` Arc is the very object admission already charged, so only
        // the prepared content is added and no body is counted twice in steady state.
        let pending = self.retained.pending.as_ref().and_then(|pending| {
            bytes = bytes.saturating_add(pending.extra_retained_bytes());
            (!pending.admitted).then(|| PendingProjectionRetention {
                sequence: pending.prepared.sequence,
                prepared_bytes: pending.prepared.retained_bytes(),
            })
        });
        ProjectionRetention {
            resident_bytes: bytes,
            pending,
        }
    }

    fn publish_retained(&self) -> Result<()> {
        self.channel.set_projection_retention(self.retention())
    }

    /// Projects one admitted write into the session, broadcasts its live changes and hands the very
    /// same immutable batch to the Thread's reliable save channel.
    ///
    /// The batch is published before it is handed over, so the writer can only ever confirm a body
    /// the shared window already holds: there is no save-before-publish interleaving to lose.
    ///
    /// The producer cut and retained RAM material supply every projection fact. No History lookup
    /// supplements a released body, and the writer never re-projects an execution effect.
    async fn advance(
        &mut self,
        services: &ObservationServices,
        write: &Arc<HistoryExport>,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        self.project_write(services, write, snapshot).await
    }

    /// Folds one admitted write into the shared session and the reliable save channel.
    async fn project_write(
        &mut self,
        services: &ObservationServices,
        write: &Arc<HistoryExport>,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let effect = &write.effect;
        anyhow::ensure!(
            self.retained.pending.is_none(),
            "a retained handoff must finish before projecting another effect"
        );
        // A receiver may register while this effect is being prepared or retained before handoff.
        // Freeze its typed State facts in the original charged slot regardless of current demand;
        // only the outward envelope is optional. Otherwise that receiver loses a reliable commit.
        let started = std::time::Instant::now();
        let projected = self
            .retained
            .projection
            .prepare(&self.thread, effect, &write.state, true)
            .await;
        let (changes, prepared) = match projected {
            Ok(projected) => projected,
            Err(error) => {
                // The writer saves exactly what this owner projects, so a projection this owner cannot
                // complete is a fact that cannot be handed over or saved. Report it so the durable
                // barrier fails closed with the real reason instead of waiting forever.
                self.channel.fail_projection(
                    effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        prepared.accounting.fold_into(&mut self.retained.usage);
        // The folded commit is already resident in the shared session, so this owner retains the
        // whole handoff — the original write, the prepared batch, the delivery decision it made and
        // its mode — before the first await of the parent-report preparation. A failure, a
        // cancellation or a retry inside that window re-enters the same retained batch instead of
        // projecting the commit a second time, which would bump content revisions for the same fact.
        if let Some(pending) = self.retained.pending.as_ref() {
            anyhow::bail!(
                "live projection still owes the handoff of commit {} before projecting commit {}",
                pending.write.effect.sequence,
                effect.sequence
            );
        }
        self.retained.pending = Some(PendingHandoff {
            admitted: false,
            write: Arc::clone(write),
            prepared,
            terminal: None,
            changes,
            mode: HandoffMode::Live,
        });
        self.publish_retained()?;
        let result = self.finish_pending(services, snapshot).await;
        tracing::debug!(
            target: "conversation_work",
            thread_id = self.thread.id,
            current_revision = self
                .retained
                .projection
                .current_state()
                .map_or(0, |current| current.revision()),
            projection_handoff_elapsed_us = started.elapsed().as_micros() as u64,
            success = result.is_ok(),
            "live owner projection and handoff"
        );
        result
    }

    /// Prepares the retained batch's original parent report, then hands the batch over.
    /// The snapshot is the current cut of this worker's original ThreadHandle, including on retry;
    /// the frozen transfer remains the source of the report and content, never of runtime versions.
    async fn finish_pending(
        &mut self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        // 原批次先保留，全部可失败准备先完成；发布与可靠交接只推进同一冻结批次。
        self.publish_retained()?;
        self.prepare_parent_report()?;
        self.prepare_terminal_delivery(services)?;
        self.prepare_handoff(services, snapshot)?;
        if let Some(binding) = &self.binding {
            binding
                .conversation
                .admit_prepared(binding, &self.channel, &mut self.retained)?;
        }
        #[cfg(test)]
        if self.binding.is_none() {
            let retained = &mut *self.retained;
            if let Some(pending) = retained.pending.as_mut() {
                pending.admitted = true;
            }
        }
        self.publish_retained()?;
        if let (Some(exporter), Some(pending)) = (&services.run_export, &self.retained.pending)
            && (pending.mode == HandoffMode::Live
                || exporter.should_admit_behind_effect(&self.thread.id, pending.prepared.sequence))
        {
            let export_current = self
                .retained
                .projection
                .current_state()
                .context("export current owner is missing")?;
            Box::pin(exporter.admit_live_handoff(
                &self.thread.id,
                &pending.prepared.accounting,
                &pending.prepared.history_changes,
                &self.retained.usage,
                export_current.as_ref(),
                &self.history_reader,
            ))
            .await;
        }
        self.handover_pending(services)
    }

    /// Freezes the managed terminal-delivery authority beside the retained batch.
    ///
    /// The delivery is not published to `WorkerState` yet: while `HistoryChannel::prepare` may still
    /// refuse the batch, this pending slot remains its sole owner. That prevents the next worker pass
    /// from starting delivery before the reliable handoff and keeps cancellation/retry on one batch.
    fn prepare_terminal_delivery(&mut self, services: &ObservationServices) -> Result<()> {
        let Some(pending) = self.retained.pending.as_ref() else {
            return Ok(());
        };
        if pending.terminal.is_some() {
            return Ok(());
        }
        let Some(original) = pending.prepared.parent_report.clone() else {
            return Ok(());
        };
        // Ordinary effects have no terminal material to transfer. Measure only after that
        // qualification; the retained batch cannot change during these synchronous borrows.
        let before = self.retention();
        let pending = self
            .retained
            .pending
            .as_mut()
            .expect("terminal batch was checked above");
        anyhow::ensure!(
            self.terminal_transfer
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_none(),
            "terminal responsibility has not been handed over"
        );
        let authority = Arc::new(
            crate::thread_assembler::review_dispatch::TerminalAuthority::capture(
                &pending.write.state,
            )?,
        );
        let finish = pending.prepared.parent_finish.clone();
        let bytes = self
            .channel
            .terminal_material_bytes(&authority, &original, finish.as_deref());
        let source = before
            .pending
            .context("terminal batch has no charged identity")?;
        let prepared_bytes = source
            .prepared_bytes
            .checked_sub(pending.prepared.parent_report_retained_bytes())
            .context("terminal report exceeds its prepared batch charge")?;
        let transfer = ProjectionTransfer {
            source,
            after: ProjectionRetention {
                resident_bytes: before.resident_bytes,
                pending: Some(PendingProjectionRetention {
                    sequence: source.sequence,
                    prepared_bytes,
                }),
            },
        };
        let sequence = pending.write.effect.sequence;
        let Some(prepared) = Arc::get_mut(&mut pending.prepared) else {
            anyhow::bail!(
                "live Thread pending batch of commit {sequence} is unexpectedly shared before terminal retention"
            );
        };
        let retention = services
            .store
            .thread_persistence()
            .retain_terminal_material(&self.thread.id, &self.channel, bytes, Some(transfer))?;
        prepared.terminal_retention = Some(retention.clone());
        pending.terminal = Some(Arc::new(
            crate::thread_assembler::review_dispatch::TerminalDelivery {
                thread: self.thread.clone(),
                sequence,
                authority,
                original,
                finish,
                source: if self.first_send && sequence > self.terminal_floor {
                    ReviewDeliverySource::LiveTerminal
                } else {
                    ReviewDeliverySource::Reconciliation
                },
                revocation: self.terminal_revocation.clone(),
                channel: Some(self.channel.clone()),
                wake: sequence > self.terminal_floor,
                _material: Some(retention),
            },
        ));
        // The report moved from the pending-batch estimate to the managed terminal-material charge.
        // Publish the new absolute projection value before attempting the synchronous handoff.
        self.publish_retained()?;
        Ok(())
    }

    fn prepare_terminal_runtime(
        &self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
        sequence: u64,
        committed_at: i64,
    ) -> Result<()> {
        // Only this worker's original ThreadHandle supplies the live cut, including on retry.
        // Same-generation observation revisions are monotonic with its commit sequence, so a newer
        // accepted cut also covers this terminal; checkpoint revisions cannot establish that fact.
        anyhow::ensure!(
            snapshot.commit_sequence >= sequence,
            "terminal handoff requires its owner's snapshot through commit {} (got {})",
            sequence,
            snapshot.commit_sequence,
        );
        let accepted = services.events.patch_thread_runtime(
            self.native_directory.as_ref(),
            crate::studio::thread_projection::status(snapshot),
            committed_at,
            snapshot,
            None,
        )?;
        if accepted.is_none()
            && !services
                .events
                .native_observation_covers(self.native_directory.as_ref(), snapshot)
        {
            // A revoked token or resource is not an accepted cut. End only this obsolete feed's
            // outward delivery; its original reliable content and parent-transfer duties continue.
            self.feed.delivery_closed.cancel();
        }
        Ok(())
    }

    fn prepare_handoff(
        &self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
    ) -> Result<()> {
        let Some(pending) = &self.retained.pending else {
            return Ok(());
        };
        if crate::studio::thread_projection::prepared_terminal_turn(&pending.prepared).is_some() {
            // Behind also publishes a retained terminal, including a restart commit not saved yet.
            // Qualify the current live cut before any handoff, never the historical transfer's state.
            // This preserves newer Turns, version/token guards and explicit close; Behind still
            // produces no realtime frames. A failed patch leaves the original batch pending.
            self.prepare_terminal_runtime(
                services,
                snapshot,
                pending.write.effect.sequence,
                pending.write.effect.committed_at,
            )?;
        }
        if pending.mode == HandoffMode::Live {
            billing::record(
                &services.performance,
                &self.thread.root_thread_id,
                &pending.prepared.accounting,
            )?;
        }
        Ok(())
    }

    /// Hands the retained batch to the reliable channel, or keeps it fully retained.
    ///
    /// Nothing in here awaits: the channel's decision, the terminal and realtime publications, the
    /// slot release and the budget update form one boundary, so the batch is either still this
    /// owner's responsibility with an explicit refusal, or handed over with its facts published
    /// exactly once. `prepare` accepting is the explicit handoff, not a durability confirmation —
    /// durability remains the writer's own watermark.
    fn handover_pending(
        &mut self,
        _services: &ObservationServices,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let Some(pending) = self.retained.pending.as_ref() else {
            return Ok(None);
        };
        let sequence = pending.prepared.sequence;
        let handed_over = pending.hand_over(&self.channel, &self.feed);
        let report = match handed_over {
            Ok(report) => report,
            Err(error) => {
                // A durable replay has no queue entry to accept. Its stored original remains the
                // receipt, and the managed delivery may only reconcile from that durable source.
                if self.channel.delivery_retry_mark().0 < sequence {
                    return Err(error);
                }
                if let Some(terminal) = self
                    .retained
                    .pending
                    .as_mut()
                    .and_then(|pending| pending.terminal.as_mut())
                {
                    let terminal = Arc::make_mut(terminal);
                    terminal
                        .revocation
                        .fetch_max(sequence, std::sync::atomic::Ordering::AcqRel);
                    terminal.source = ReviewDeliverySource::Reconciliation;
                    terminal.wake = false;
                }
                None
            }
        };
        let terminal = self
            .retained
            .pending
            .as_mut()
            .and_then(|pending| pending.terminal.take());
        if let Some(terminal) = terminal {
            let mut transfer = self
                .terminal_transfer
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            assert!(
                transfer.is_none(),
                "terminal responsibility was validated before admission"
            );
            *transfer = Some(terminal);
        }
        self.retained.pending = None;
        self.publish_retained()?;
        Ok(report)
    }

    /// Freezes the original terminal report of the retained batch into its prepared content.
    ///
    /// Every await in here belongs to the pending slot: the slot keeps holding the original write
    /// and prepared content, a local clone carries the waits, and only a fully successful build is
    /// written back. A failure or a cancelled wait leaves the slot exactly as it was, so the next
    /// pass reuses the same batch instead of rebuilding the report from a later checkpoint.
    fn prepare_parent_report(&mut self) -> Result<()> {
        let (write, prepared) = match self.retained.pending.as_ref() {
            Some(pending) => (Arc::clone(&pending.write), Arc::clone(&pending.prepared)),
            None => return Ok(()),
        };
        let Some(turn) = write.effect.turn.as_ref().filter(|turn| {
            turn.state != pl_core::thread::TurnState::Running
                && self.thread.parent_thread_id.is_some()
        }) else {
            return Ok(());
        };
        // The retry of a batch whose report already exists reuses the original copy: the report is
        // the frozen receipt of this very commit, never rebuilt from a DTO or a newer checkpoint.
        if prepared.parent_report.is_some() {
            return Ok(());
        }
        let turn = turn.clone();
        let result = self
            .retained
            .projection
            .turn_result(&turn.turn_id)
            .cloned()
            .unwrap_or_default();
        // The report is built from read-only local clones while the slot keeps the only prepared
        // batch; only once the complete message exists are the clones dropped, so the write-back
        // below takes the slot's single strong reference and never copies the whole batch.
        let report = reports::terminal_message(
            &self.thread,
            &write.state,
            &turn,
            write.effect.sequence,
            &result,
        )?;
        drop(prepared);
        let shared = {
            let Some(pending) = self.retained.pending.as_mut() else {
                unreachable!(
                    "the pending handoff slot cannot vanish while its owner prepares its report"
                );
            };
            match Arc::get_mut(&mut pending.prepared) {
                Some(batch) => {
                    batch.parent_report = Some(Arc::new(report));
                    batch.parent_finish = result.finish.map(Arc::new);
                    None
                }
                // Before the handoff only this owner holds the batch; a second strong reference
                // is an internal invariant violation, reported while the slot stays retained.
                None => Some(pending.write.effect.sequence),
            }
        };
        if let Some(sequence) = shared {
            anyhow::bail!(
                "live Thread pending batch of commit {sequence} is unexpectedly shared before its handoff"
            );
        }
        // The report is now part of the retained batch: the Thread budget sees it before any
        // handoff attempt, and a refused handoff keeps the batch together with its report.
        self.publish_retained()?;
        Ok(())
    }

    /// Hands one admitted effect this owner installed *behind* to the reliable save channel.
    ///
    /// The Thread's initialization commits before the assembler publishes the observation, so those
    /// effects are already part of the snapshot this projection was seeded from and are never
    /// replayed as live frames. The history writer still owes them a durable row, so the same single
    /// projection folds their content into memory here — once, and never the writer projecting the
    /// effect itself.
    async fn prepare_behind(
        &mut self,
        services: &ObservationServices,
        write: &Arc<HistoryExport>,
        snapshot: &ThreadSnapshot,
    ) -> Result<()> {
        let projected = self
            .retained
            .projection
            .prepare_committed(&self.thread, &write.effect, &write.state)
            .await;
        let prepared = match projected {
            Ok(prepared) => prepared,
            Err(error) => {
                self.channel.fail_projection(
                    write.effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        // The behind batch is retained the same way before its report await; its mode keeps it from
        // ever gaining realtime publication rights on a retry.
        if let Some(pending) = self.retained.pending.as_ref() {
            anyhow::bail!(
                "live projection still owes the handoff of commit {} before taking over commit {}",
                pending.write.effect.sequence,
                write.effect.sequence
            );
        }
        self.retained.pending = Some(PendingHandoff {
            admitted: false,
            write: Arc::clone(write),
            prepared,
            terminal: None,
            changes: None,
            mode: HandoffMode::Behind,
        });
        self.publish_retained()?;
        self.finish_pending(services, snapshot).await?;
        Ok(())
    }

    /// Projects the uncommitted streaming preview of the current owner snapshot.
    ///
    /// The preview is written into the shared session — the one content window — and emits no
    /// content frame; current activity and runtime facts are published separately.
    async fn stream(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        self.retained
            .projection
            .stream(&self.thread, snapshot)
            .await
            .map_err(|error| anyhow::anyhow!("live Thread preview failed: {error}"))?;
        self.observe_runtime(snapshot).await?;
        self.observe_activity(snapshot).await?;
        if let Some(current) = self.retained.projection.current_state() {
            self.feed.publish_conversation(current)?;
        }
        Ok(())
    }

    /// Execution residency is live-only; next-admission availability also consumes current config.
    /// Derive runtime from the latest owner snapshot after folding all admitted usage,
    /// never from an effect's storage checkpoint. Stable timestamps allow deduplication.
    async fn observe_runtime(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let at = self
            .runtime_published
            .as_ref()
            .map_or(self.thread.updated_at, |runtime| runtime.updated_at);
        let mut runtime = crate::studio::thread_projection::project_runtime(
            &self.thread.id,
            snapshot,
            at,
            &snapshot.usage_summary,
        )?;
        let mut model_route = crate::studio::model_route::projected(snapshot)?;
        let same_identity = match (self.model_route_published.as_ref(), model_route.as_ref()) {
            (Some(previous), Some(current)) => {
                previous.account_id == current.account_id
                    && previous.model_id == current.model_id
                    && previous.effort == current.effort
                    && previous.revision == current.revision
            }
            (None, None) => true,
            _ => false,
        };
        let qualification_revision = if self.config.model_catalog_revision()?
            == self.qualification_revision
            && same_identity
        {
            if let (Some(previous), Some(current)) =
                (self.model_route_published.as_ref(), model_route.as_mut())
            {
                current.available = previous.available;
                current.unavailable_reason = previous.unavailable_reason.clone();
            }
            self.qualification_revision
        } else {
            let (config, catalog) = self.config.read_with_catalog()?;
            crate::studio::model_route::annotate_availability(
                model_route.as_mut(),
                &self.thread,
                &config.config,
            )?;
            catalog.revision
        };
        if self.runtime_published.as_ref() == Some(&runtime)
            && self.model_route_published == model_route
        {
            self.qualification_revision = qualification_revision;
            return Ok(());
        }
        runtime.updated_at = crate::studio::unix_seconds();
        runtime.usage.updated_at = runtime.updated_at;
        self.qualification_revision = qualification_revision;
        self.model_route_published.clone_from(&model_route);
        let runtime = self.runtime_published.insert(runtime);
        let compact_runtime = self.feed.compact_runtime(runtime.clone())?;
        self.feed.publish(|| ThreadLiveEvent::Runtime {
            observation_revision: snapshot.observation_revision,
            catalog_revision: self.qualification_revision,
            runtime: Arc::new(compact_runtime),
            model_route,
        });
        Ok(())
    }

    /// Re-derives the Thread's current activity from the snapshot this owner just published.
    ///
    /// The activity is an independent projection of the same facts: a phase change, a new foreground
    /// tool or an interaction change reaches it through the owner snapshot, never through `effect`.
    /// Shared producer versions cover body changes even when the bounded summary stays identical.
    /// The completion ceiling also advances independently of the activity summary.
    async fn observe_activity(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let activity = self.retained.projection.current_activity();
        let activity_changed = activity != self.activity_published;
        if !activity_changed {
            return Ok(());
        }
        self.activity_published = activity;
        let compact_activity = self
            .feed
            .compact_activity(self.activity_published.clone())?;
        // One shared handle per published change: every subscriber clones that handle, never the body.
        self.feed.publish(|| ThreadLiveEvent::Activity {
            observation_revision: snapshot.observation_revision,
            activity: compact_activity.map(Arc::new),
        });
        Ok(())
    }

    /// Republishes the typed storage state this owner derives, only when it really changed.
    ///
    /// A storage pause, a pressure warning, the explicit-resume latch or a durable receipt change
    /// nothing about the content or the activity, so they need their own fact: the owner watches the
    /// coordinator's typed status directly and republishes here even when no other frame arrived, so
    /// a parked subscriber learns about a save failure without waiting for an unrelated commit.
    fn observe_storage(
        &mut self,
        snapshot: &ThreadSnapshot,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) {
        if let Some(through) = persistence.and_then(|detail| detail.history_durable_sequence) {
            self.retained.projection.confirm_sources(through);
        }
        let storage = persistence.map(|detail| storage_state(snapshot, detail));
        if storage == self.storage_published {
            return;
        }
        self.storage_published = storage.clone();
        self.feed.publish_storage(storage);
    }
}

impl Drop for LiveOwner {
    fn drop(&mut self) {
        if let Some(binding) = &self.binding {
            binding.conversation.detach_execution(binding);
        }
    }
}

fn product_revision(
    snapshot: &ThreadSnapshot,
) -> (
    u64,
    ThreadLifecycle,
    Option<pl_core::thread::ActiveExecution>,
) {
    (
        snapshot.commit_sequence,
        snapshot.lifecycle,
        snapshot.execution.clone(),
    )
}

async fn run(
    projector: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    recovered_through: u64,
    feed: Arc<ThreadLiveFeed>,
    mut catalogs: broadcast::Receiver<crate::config::CatalogChange>,
) {
    use futures::FutureExt;
    let mut updates = thread.subscribe();
    // The reliable handoff can gain a commit this projection must take over without any new owner
    // snapshot: an admission that storage pressure deferred lands after the observation was
    // installed, so its fact is older than this projection's seed and is never replayed as a live
    // frame. The channel's own status is the signal for it, and it is what makes "the writer is
    // waiting for a handoff" reach the only task that can hand one over.
    let mut handoff = state.channel.subscribe();
    // The coordinator's typed persistence watch is a first-class wake source: a save failure can
    // change with no owner frame and no handoff, so without this arm the owner would only publish
    // the fault when something unrelated happened to arrive.
    let mut persistence = projector.store.thread_persistence().subscribe();
    let mut settings = projector.settings_updates.clone();
    settings.borrow_and_update();
    let mut settings_open = true;
    let mut current = thread.snapshot();
    let continuous = state.observed_before_execution;
    let mut worker = ProjectionWorker {
        services: projector,
        id,
        thread,
        state,
        recovered_through,
        feed,
        live: None,
        live_floor: recovered_through,
        // Fresh bootstrap may have a nonzero fence; the registered owner proved that its
        // reliable channel was installed before any execution or model call.
        continuous,
    };
    // Execution preparation and retirement can change without a history commit. The directory must
    // follow that identity as well as committed facts, but not pay for preview-only publications.
    // The live projection still follows every owner snapshot through the same single publisher.
    let mut projected = None;
    loop {
        let issue_id = format!("tool-cleanup:{}", worker.id);
        let issue = (!current.tool_cleanup.failures.is_empty()).then(|| {
            crate::studio::StudioRecoveryIssue {
                id: issue_id.clone(),
                scope: crate::studio::StudioRecoveryIssueScope::Thread,
                category: crate::studio::StudioRecoveryIssueCategory::ToolCatalog,
                impact: crate::studio::StudioRecoveryImpact::Advisory,
                action: crate::studio::StudioRecoveryIssueAction::Retry,
                workspace_id: None,
                thread_id: Some(worker.id.clone()),
                worktree: None,
                message: current
                    .tool_cleanup
                    .failures
                    .iter()
                    .map(|failure| format!("{}: {}", failure.tool_id, failure.error))
                    .collect::<Vec<_>>()
                    .join("; "),
            }
        });
        worker.services.recovery.update_if_current(
            &issue_id,
            issue,
            || {
                worker
                    .services
                    .sessions
                    .upgrade()
                    .map(|sessions| sessions.observed_threads())
                    .unwrap_or_default()
                    .iter()
                    .any(|(id, thread)| id == &worker.id && thread.same_instance(&worker.thread))
            },
            |issues| {
                worker.services.events.emit_recovery_state(issues);
            },
        );
        let revision = product_revision(&current);
        let products = projected.as_ref() != Some(&revision);
        // Read the coordinator's newest typed facts before publishing: a storage change is a fact
        // this pass has to carry, exactly like a commit or a preview it also projects.
        let detail = persistence
            .borrow_and_update()
            .threads
            .iter()
            .find(|detail| detail.thread_id == worker.id)
            .cloned();
        // The projection stays isolated behind `catch_unwind`, so a panicking projection is
        // still reported as an error instead of taking down the observation worker.
        // A closed physical owner hands its final Current to the independent JSON writer before
        // archive reconciliation. A failed History write cannot postpone that final save/join.
        let mut current_close = if current.lifecycle == ThreadLifecycle::Closed {
            if let Some(live) = worker.live.as_ref() {
                Some(
                    live.retained
                        .store
                        .close_current(
                            &worker.thread,
                            crate::thread_assembler::ClosePurpose::Preserve,
                        )
                        .await,
                )
            } else {
                None
            }
        } else {
            None
        };
        let mut result =
            std::panic::AssertUnwindSafe(worker.project(&current, products, detail.as_ref()))
                .catch_unwind()
                .await
                .unwrap_or_else(|_| Err(anyhow::anyhow!("Thread product projection panicked")));
        if current.lifecycle == ThreadLifecycle::Closed
            && current_close.is_none()
            && let Some(live) = worker.live.as_ref()
        {
            current_close = Some(
                live.retained
                    .store
                    .close_current(
                        &worker.thread,
                        crate::thread_assembler::ClosePurpose::Preserve,
                    )
                    .await,
            );
        }
        if let Some(Err(close)) = current_close {
            result = Err(match result {
                Ok(()) => close,
                Err(archive) => {
                    archive.context(format!("independent Current close also failed: {close:#}"))
                }
            });
        }
        match result {
            Ok(()) => {
                worker.continuous = true;
                if products {
                    projected = Some(revision);
                }
                let finished = current.lifecycle == ThreadLifecycle::Closed;
                worker.state.progress.send_replace(Progress {
                    initialized: true,
                    applied: current.commit_sequence,
                    handoff: worker.state.channel.handoff_ticket(),
                    error: None,
                    finished: false,
                });
                if finished {
                    // 固定目标 ticket：只等待本次观察已受理的产品写入，不等待整个系统空闲。
                    let target = worker.services.writer.admitted_ticket();
                    match worker.services.writer.flush_through(target).await {
                        Ok(()) => {
                            if let (Some(exporter), Some(live)) =
                                (&worker.services.run_export, &worker.live)
                            {
                                let status_value =
                                    crate::studio::thread_projection::status(&current);
                                let status = serde_json::to_value(status_value)
                                    .ok()
                                    .and_then(|value| value.as_str().map(str::to_owned));
                                let (aborted, error) = match &current.input_execution {
                                    pl_core::thread::input::InputExecution::Failed { error } => {
                                        (false, Some(error.to_string()))
                                    }
                                    pl_core::thread::input::InputExecution::Interrupting {
                                        ..
                                    } => (true, None),
                                    _ => (false, None),
                                };
                                let (history_cut, history_seq) =
                                    match live.history_reader.capture_position().await {
                                        Ok(position) => position,
                                        Err(error) => {
                                            worker.state.progress.send_modify(|progress| {
                                                progress.error = Some(Arc::new(error.into()));
                                                progress.finished = true;
                                            });
                                            return;
                                        }
                                    };
                                exporter.record_thread_final_cut(
                                    crate::studio::runtime::run_export::RetiredThreadCut {
                                        thread_id: worker.id.clone(),
                                        through_effect_seq: current.commit_sequence,
                                        history: live.history_reader.clone(),
                                        history_cut,
                                        history_seq,
                                        summary: live.retained.usage.clone(),
                                        status,
                                        aborted,
                                        error,
                                    },
                                );
                            }
                            if let Some(live) = &worker.live
                                && let Err(error) = live
                                    .retained
                                    .store
                                    .close_current(
                                        &worker.thread,
                                        crate::thread_assembler::ClosePurpose::Preserve,
                                    )
                                    .await
                            {
                                worker.state.progress.send_modify(|progress| {
                                    progress.error = Some(Arc::new(error));
                                    progress.finished = true;
                                });
                                return;
                            }
                            worker
                                .state
                                .progress
                                .send_modify(|progress| progress.finished = true);
                            return;
                        }
                        Err(error) => {
                            worker.continuous = false;
                            worker.live_floor = worker.live_floor.max(current.commit_sequence);
                            worker
                                .state
                                .reconciliation_through
                                .fetch_max(worker.live_floor, std::sync::atomic::Ordering::AcqRel);
                            worker.state.progress.send_modify(|progress| {
                                progress.error = Some(Arc::new(anyhow::Error::new(error)));
                                progress.finished = false;
                            });
                        }
                    }
                }
            }
            Err(error) => {
                // Archive faults do not revoke the original Current publisher. Its latest RAM
                // preview and State keep following this physical owner without a history read.
                if let Some(live) = worker.live.as_mut() {
                    if let Err(current_error) = live.stream(&current).await {
                        worker.state.progress.send_modify(|progress| {
                            progress.error = Some(Arc::new(current_error));
                        });
                    }
                    live.observe_storage(&current, detail.as_ref());
                }
                worker.continuous = false;
                worker.live_floor = worker.live_floor.max(current.commit_sequence);
                worker
                    .state
                    .reconciliation_through
                    .fetch_max(current.commit_sequence, std::sync::atomic::Ordering::AcqRel);
                // A fact this owner could not project leaves the committed stream discontinuous for
                // every subscriber, so the feed tells them to resynchronize from the durable window
                // instead of letting the client splice a hole; the worker retries the same watermark.
                worker.feed.rebase(0);
                worker
                    .state
                    .progress
                    .send_modify(|progress| progress.error = Some(Arc::new(error)));
            }
        }
        if current.lifecycle == ThreadLifecycle::Closed {
            tokio::select! {
                () = worker.state.retry.notified() => {}
                _ = handoff.changed() => {}
            }
            current = worker.thread.snapshot();
            continue;
        }
        tokio::select! {
            () = worker.state.retry.notified() => current = worker.thread.snapshot(),
            // A handoff the writer is waiting for may be the only reason this worker still has work
            // to do; re-run the projection so a deferred admission is taken over and saved.
            _ = handoff.changed() => current = worker.thread.snapshot(),
            // A typed storage change with no owner frame still has to reach subscribers; re-run the
            // pass so the owner republishes the state it just read.
            _ = persistence.changed() => current = worker.thread.snapshot(),
            changed = settings.changed(), if settings_open => {
                settings_open = changed.is_ok();
                settings.borrow_and_update();
                current = worker.thread.snapshot();
            }
            // Availability may change with no core publication or business
            // commit. The same owner reprojects against the new catalog.
            change = catalogs.recv(), if !catalogs.is_closed() => {
                match change {
                    Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => {
                        current = worker.thread.snapshot();
                    }
                    Err(broadcast::error::RecvError::Closed) => {}
                }
            }
            update = updates.next() => match update {
                Some(snapshot) => current = snapshot,
                None => {
                    let final_snapshot = worker.thread.snapshot();
                    if final_snapshot.lifecycle == ThreadLifecycle::Closed {
                        // Physical close can retire the subscription before this consumer takes
                        // its last update. The original owner still retains its final snapshot;
                        // process that real Closed state and complete Current/History shutdown.
                        current = final_snapshot;
                        continue;
                    }
                    worker.continuous = false;
                    worker.live_floor = worker.live_floor.max(worker.thread.snapshot().commit_sequence);
                    worker.state.reconciliation_through.fetch_max(worker.live_floor, std::sync::atomic::Ordering::AcqRel);
                    worker.state.progress.send_modify(|progress| progress.error = Some(Arc::new(anyhow::anyhow!("Thread subscription ended before its final projection"))));
                    tokio::select! {
                        () = worker.state.retry.notified() => {}
                        _ = handoff.changed() => {}
                    }
                    current = worker.thread.snapshot();
                }
            }
        }
    }
}

/// Everything one Thread's observation worker carries across a projection: the product services, the
/// owner handle it reads committed effects from, its progress and retry channel, the feed it
/// broadcasts on and the live projection it folds into.
///
/// Keeping this as one domain value is what lets the worker project without threading nine
/// independent arguments through every call; the live projection above stays a pure function of one
/// effect.
struct ProjectionWorker {
    services: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    /// Committed watermark the Thread already had when this projection was seeded. Terminal reports
    /// for Turns at or below it are repairs, not fresh continuations, so they do not wake a parent.
    recovered_through: u64,
    feed: Arc<ThreadLiveFeed>,
    live: Option<LiveOwner>,
    /// Commits already visible at installation or across an observation failure cannot first-send.
    live_floor: u64,
    continuous: bool,
}

async fn transfer_terminal(services: &ObservationServices, state: &WorkerState) -> Result<()> {
    let pending = state
        .terminal_transfer
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    let Some(pending) = pending else {
        return Ok(());
    };
    let channel = pending
        .channel
        .as_ref()
        .context("terminal transfer has no history channel")?;
    anyhow::ensure!(
        channel.handoff_ticket() >= pending.sequence
            || channel.delivery_retry_mark().0 >= pending.sequence,
        "terminal transfer precedes handoff"
    );
    services
        .require_session(&pending.thread.id)?
        .start_terminal_delivery(pending.clone())
        .await?;
    let mut slot = state
        .terminal_transfer
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if slot
        .as_ref()
        .is_some_and(|current| Arc::ptr_eq(current, &pending))
    {
        *slot = None;
    }
    Ok(())
}

/// Waits until the history writer's durable watermark covers the handoff ticket `sequence`.
///
/// This deliberately does not use `Thread::flush`. That barrier targets *every commit the owner has
/// admitted*, including ones this projection has not handed over yet, and the writer refuses to save
/// a fact no projection holds — so an observer waiting on it would wait for its own next step, and
/// the request itself travels through the owner's command queue, which a running Turn only reaches at
/// its own safety points. Waiting for this projection's own handoff ticket asks for exactly the
/// commits it already prepared, in the order they were prepared, so it always completes, and a
/// channel that never saw a handoff (`0`) is trivially durable instead of waiting for a watermark a
/// re-activated Thread's fresh channel can no longer move.
///
/// The writer publishes its terminal diagnostic on the same channel, so a storage failure ends this
/// barrier with the real reason instead of hanging on a watermark that can no longer advance.
async fn await_history_durable(channel: &HistoryChannel, id: &str, sequence: u64) -> Result<()> {
    channel.await_handoff_durable(id, sequence).await
}

/// The write this owner owes work on next: the retained handoff first, then the reliable queue.
///
/// The retained batch wins even when its queue entry has already left the unprojected set — the
/// owner still owes its report and handoff — and queue work is only picked up with no batch
/// retained, so a retry never depends on the queue still listing the commit.
fn next_projection_write(
    pending: &Option<PendingHandoff>,
    channel: &HistoryChannel,
) -> Option<Arc<HistoryExport>> {
    pending
        .as_ref()
        .map(|pending| Arc::clone(&pending.write))
        .or_else(|| channel.next_unprojected())
}

/// Waits for one observation to reach the committed target fixed at call time.
///
/// An existing error is reported as it stands: an explicit retry wakes the worker, but only the
/// worker's own successful pass, which replaces the whole progress value, clears the error — so a
/// synchronize call may wake the retry and still return the original failure, while a later call
/// observes the real success. The returned handoff ticket is the watermark this observation's own
/// durable barrier waits for.
///
/// # Errors
/// The observation's retained failure, or its worker ending before the target was reached.
async fn await_settled_target(
    id: &str,
    observation: &Observation,
    target_snapshot: &ThreadSnapshot,
) -> Result<u64> {
    let target = target_snapshot.commit_sequence;
    let mut progress = observation.state.progress.subscribe();
    loop {
        let state = progress.borrow().clone();
        if let Some(error) = state.error {
            bail!("Thread {id} product observation failed: {error:#}");
        }
        if state.initialized
            && state.applied >= target
            && (target_snapshot.lifecycle != ThreadLifecycle::Closed || state.finished)
        {
            break Ok(state.handoff);
        }
        if state.finished {
            bail!("Thread {id} product observer ended before commit {target}");
        }
        tokio::select! {
            changed = progress.changed() => {
                changed.context("Thread product observer progress closed")?;
            }
            joined = observation.join() => joined?,
        }
    }
}

/// The Thread's product association, from the resident directory entry or from durable storage.
///
/// Private assembly may not yet have published a directory view; its association is already in the
/// RAM catalog. Neither branch reads persisted rows or waits for directory writes.
async fn product_association(services: &ObservationServices, id: &str) -> Result<crate::Thread> {
    if let Some(thread) = services.events.thread_snapshot(id)? {
        return Ok(thread);
    }
    let association = services
        .store
        .read_thread(id)
        .await?
        .context("observed Thread has no product association")?;
    Ok(crate::Thread::from(association))
}

// The worker carries the projection owner, its feed and the product watermark across one projection;
// splitting them into a context struct would only hide the same state behind one more indirection.
impl ProjectionWorker {
    /// Takes over every admitted fact this projection owner has not folded yet, projects the current
    /// streaming overlay and, when `products` is set, the product directory and billing facts they
    /// imply.
    ///
    /// The reliable admission queue is the one source of committed work: a fact enters it when core
    /// commits it and leaves it only once this owner folded it *and* the durable store saved it, so
    /// the projection never races the owner's command queue or the disk. Facts the owner had already
    /// folded into the snapshot this projection was seeded from are taken over without being replayed
    /// as live frames.
    ///
    /// # Errors
    /// Returns a projection, storage association or directory failure. The worker reports it through
    /// its progress channel and retries the same watermark instead of skipping a commit.
    async fn project(
        &mut self,
        snapshot: &ThreadSnapshot,
        products: bool,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) -> Result<()> {
        let Self {
            services,
            id,
            thread,
            state,
            recovered_through,
            feed,
            live,
            live_floor,
            continuous,
            ..
        } = self;
        let recovered_through = *recovered_through;
        transfer_terminal(services, state).await?;
        if !*continuous {
            *live_floor = (*live_floor).max(snapshot.commit_sequence);
        }
        if live.is_none() {
            // The product association is resolved once, when this projection owner is installed.
            // A Thread re-activated after its directory entry left memory reads it from SQLite here.
            let product = product_association(services, id).await?;
            *live = Some(
                LiveOwner::open(
                    services,
                    thread,
                    snapshot,
                    product,
                    Arc::clone(feed),
                    state.clone(),
                    persistence,
                )
                .await?,
            );
        }
        let live = live
            .as_mut()
            .expect("live projection owner was just installed");
        live.stream(snapshot).await?;
        live.observe_storage(snapshot, persistence);
        live.first_send &= *continuous;
        // The projection owner is the single producer of realtime content: it folds every admitted
        // fact exactly once, publishes it into the shared session and broadcasts the typed change,
        // whether or not a GUI is open.
        //
        // The association the owner was installed with is what identifies a parent or a billing
        // root; it never changes for a Thread, so a commit does not re-read the directory DTO for it.
        let mut newest_commit_at = 0_i64;
        loop {
            // One projection includes table scans and encoding, not one cheap iterator item.
            // Yield between complete handoffs instead of spending only one cooperative credit
            // per effect; writer progress must not depend on exhausting a whole batch of them.
            tokio::task::yield_now().await;
            // The retained handoff is completed before any new queue work: its write is the very
            // Arc the queue admitted, so even a queue entry that already disappeared cannot make
            // this owner forget or re-project the commit it still owes.
            let retained_mode = live.retained.pending.as_ref().map(|pending| pending.mode);
            let mut next = next_projection_write(&live.retained.pending, &live.channel);
            if next.is_none()
                && let Some(binding) = &live.binding
            {
                let after = live.channel.subscribe().borrow().admitted_sequence;
                if let Some(export) = thread
                    .history_export_page(after, std::num::NonZeroUsize::new(1).unwrap())?
                    .into_iter()
                    .next()
                {
                    let sequence = export.effect.sequence;
                    binding.storage.admit_export(id, export.clone())?;
                    // The reliable native queue now owns the original export even if its disk
                    // writer fails. Current saving has no dependency on this acknowledgement.
                    thread.release_history_through(sequence)?;
                    next = next_projection_write(&live.retained.pending, &live.channel);
                }
            }
            let Some(write) = next else {
                break;
            };
            // Core admits effects before publishing its snapshot. Do not cross that publication
            // boundary: after a zero-demand decision, a later receiver registers before capturing a
            // snapshot that must already cover this effect. Otherwise admission could race receiver
            // registration and leave a skipped commit out of both baseline and feed. The existing
            // snapshot watch wakes us when this watermark advances; the reliable queue retains work.
            // A retained batch is retried along its original mode instead of being parked again.
            // finish_pending also checks terminal coverage against this same handle's current cut;
            // neither its frozen transfer nor another observation generation can supply that cut.
            if retained_mode.is_none() && write.effect.sequence > snapshot.commit_sequence {
                break;
            }
            let sequence = write.effect.sequence;
            if let Some(mode) = retained_mode {
                // Same batch, same mode: no re-seed, no re-fold, no re-projection and no
                // re-decided delivery — only the report preparation and the handoff are retried.
                let _parent_report = live.finish_pending(services, snapshot).await?;
                if mode == HandoffMode::Live {
                    newest_commit_at = newest_commit_at.max(write.effect.committed_at);
                }
                transfer_terminal(services, state).await?;
                continue;
            }
            if sequence <= recovered_through {
                // A fact the owner committed before this projection existed: it is already part of
                // the snapshot the projection was seeded from, so it is folded for durability only.
                live.prepare_behind(services, &write, snapshot).await?;
                transfer_terminal(services, state).await?;
                continue;
            }
            live.advance(services, &write, snapshot).await?;
            newest_commit_at = newest_commit_at.max(write.effect.committed_at);
            transfer_terminal(services, state).await?;
        }
        // Streaming previews change without a commit and belong to the same publisher.
        live.stream(snapshot).await?;
        // The typed storage state is one owner fact: it is republished here whether this pass was
        // triggered by a commit, a preview or the coordinator's own typed status changing.
        live.observe_storage(snapshot, persistence);
        if !products {
            return Ok(());
        }
        // The directory DTO is re-read for a product refresh, because a concurrent title, mode or
        // archive operation owns those fields and a preview-only pass must not pay for the lookup.
        let mut product = product_association(services, id).await?;
        product.status = crate::studio::thread_projection::status(snapshot);
        product.updated_at = product.updated_at.max(newest_commit_at);
        // The directory summary is derived from the same reliable owner as the terminal report: the
        // in-memory projection; unobserved old Turns do not trigger a History read.
        let summary = match snapshot
            .turns
            .last()
            .filter(|turn| turn.state != pl_core::thread::TurnState::Running)
        {
            Some(turn) => live
                .retained
                .projection
                .turn_result(&turn.turn_id)
                .and_then(|result| result.final_text()),
            None => None,
        };
        directory::publish(
            services,
            product,
            live.native_directory.as_ref(),
            snapshot,
            summary,
        )
        .await?;
        Ok(())
    }
}

#[cfg(test)]
mod live_feed_tests {
    use super::*;
    use tokio_util::sync::CancellationToken;

    #[tokio::test]
    async fn state_lag_resets_before_replay_and_closure_wins_over_buffered_frames() {
        let (_, progress) = watch::channel(Progress::default());
        let cancellation = CancellationToken::new();
        let feed = ThreadLiveFeed::new(None, progress, cancellation.clone());
        let mut slow = feed.subscribe();
        let mut parked = feed.subscribe();

        for revision in 1_u64..=(u64::try_from(LIVE_FEED_FRAMES).unwrap() + 2) {
            feed.publish_test_state_activity(revision, None);
        }
        match slow.try_recv() {
            Err(broadcast::error::TryRecvError::Lagged(dropped)) => {
                assert_eq!(
                    dropped, 2,
                    "exactly the two frames beyond the bound are lost"
                );
            }
            other => panic!("expected an explicit lag reset, got {other:?}"),
        }
        match slow.try_recv() {
            Ok(ThreadLiveEvent::Activity {
                observation_revision,
                activity,
            }) => {
                assert_eq!(observation_revision, 3);
                assert!(activity.is_none());
            }
            other => panic!("lag must reset to the oldest retained frame, got {other:?}"),
        }
        assert_eq!(
            feed.state_activity()
                .expect("latest observation")
                .observation_revision,
            u64::try_from(LIVE_FEED_FRAMES).unwrap() + 2
        );

        let parked = tokio::spawn(async move { parked.recv().await });
        cancellation.cancel();
        assert!(matches!(
            parked.await.expect("receiver task finishes"),
            Err(broadcast::error::RecvError::Closed)
        ));
        assert!(matches!(
            slow.try_recv(),
            Err(broadcast::error::TryRecvError::Closed)
        ));
    }

    #[tokio::test]
    async fn state_receiver_close_wins_over_buffered_content_and_wakes_parked_readers() {
        let (events, receiver) = broadcast::channel(4);
        let closed = CancellationToken::new();
        events
            .send(ThreadLiveEvent::UnframedCommit { sequence: 1 })
            .unwrap();
        let mut buffered = StateReceiver::new(receiver, closed.clone());
        assert!(matches!(
            buffered.recv().await,
            Ok(ThreadLiveEvent::UnframedCommit { sequence: 1 })
        ));

        let mut parked = StateReceiver::new(events.subscribe(), closed.clone());
        let task = tokio::spawn(async move { parked.recv().await });
        let _ = events.send(ThreadLiveEvent::UnframedCommit { sequence: 2 });
        closed.cancel();
        assert!(matches!(
            task.await.expect("parked State receiver task"),
            Err(broadcast::error::RecvError::Closed)
        ));
        assert!(matches!(
            StateReceiver::new(events.subscribe(), closed).try_recv(),
            Err(broadcast::error::TryRecvError::Closed)
        ));
    }
}
