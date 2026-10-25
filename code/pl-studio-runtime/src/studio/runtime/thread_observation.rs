//! Owned, retryable product projections of the Thread's committed effect stream.
//!
//! Observation consumes the Thread's reliable admission queue and is its **single realtime
//! projection owner**: it projects every admitted fact and the streaming overlay once, publishes the
//! content into the shared session and broadcasts the same typed changes on a bounded feed that
//! subscriptions only read. Billing, directory and terminal facts come from the same in-memory
//! projection, so an ordinary commit neither parks this observer behind the owner's command queue
//! nor waits for the disk. Durable history is read back once when the projection is installed on a
//! Thread whose work started earlier, and by the explicit cold recovery of an unloaded child.
mod billing;
mod close;
mod directory;
mod failure;
mod fences;
mod reports;

pub(crate) use failure::ObservationCloseFailure;
pub(super) use failure::{ProgressFailure, RetryPoint};
use fences::{HistoryFence, ObservationFence, ProjectionFences, WriteFence};

use super::background_task::BackgroundTask;
use super::{ModelPerformanceOwner, StudioRuntime};
use crate::studio::{ProductEventBus, StudioStore};
use anyhow::{Context, Result};
use pl_core::chat::Session;
use pl_core::thread::{
    ThreadHandle, ThreadLifecycle, ThreadSnapshot, UsageSummary, cold::ThreadWrite,
};
use std::{
    collections::BTreeMap,
    num::NonZeroU64,
    sync::{Arc, Mutex},
};
use tokio::sync::{Notify, broadcast, watch};
pub(in crate::studio::runtime) mod facets;

use crate::studio::storage::thread_writer::HistoryChannel;
use crate::studio::thread_projection::{LiveEvent, LiveProjection, storage_state};

/// Fixed bound on the frames one subscriber may fall behind the projection owner.
///
/// The feed is a bounded observation channel, not a log: a subscriber that stops draining observes
/// a lag and resynchronizes from the database window instead of letting this queue grow with history.
const LIVE_FEED_FRAMES: usize = 512;

/// One output of a Thread's single realtime projection owner.
#[derive(Debug, Clone)]
pub(in crate::studio) enum ThreadLiveEvent {
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
    /// The projection owner could not prove continuity for `dropped` commits and re-seeded; every
    /// subscriber must resynchronize from the database window.
    Rebase { dropped: u64 },
    /// Current runtime facts, including live model availability (absent from checkpoints).
    Runtime {
        runtime: Arc<pl_protocol::ThreadRuntimeSnapshot>,
    },
    /// Current execution activity of the Thread; `None` means no activity.
    ///
    /// The activity is an independent typed projection of the same owner state (it never carries a
    /// second copy of the content), so it is published by the same single owner and only when it
    /// really changed; a subscriber only forwards it. It rides as one shared handle rather than an
    /// inline value: the feed is a `broadcast` channel that clones its frame once per subscriber, so
    /// the body must stay cheap to clone and must not bloat the frame every other variant shares.
    Activity {
        activity: Option<Arc<pl_protocol::ThreadActivity>>,
    },
}

/// The realtime projection feed of one Thread.
///
/// The Thread's observation worker is its only producer, and it publishes into the shared chat
/// session at the same time. Subscribers therefore forward typed events and never project, publish
/// or read the effect window themselves.
pub(in crate::studio) struct ThreadLiveFeed {
    mode: pl_protocol::thread_facets::identity::ThreadObservationMode,
    facets: Result<Arc<facets::ThreadFacetSources>, pl_protocol::studio::StudioError>,
    events: broadcast::Sender<ThreadLiveEvent>,
    /// The Thread's authoritative typed storage state, published by this owner only.
    ///
    /// The projection owner is the one place that derives it from the owner snapshot and the
    /// coordinator's typed watch, so a subscriber mirrors this value instead of recomputing the
    /// state from its own copies. A storage pause changes neither the content nor the activity, so
    /// the value is watched on its own instead of riding the content feed: a subscriber parked on
    /// the feed still learns about a pause the moment the owner publishes it.
    storage: watch::Sender<Option<pl_protocol::ThreadStorageState>>,
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
    last_turn: watch::Sender<Option<Arc<pl_protocol::Turn>>>,
}

impl ThreadLiveFeed {
    fn new(
        storage: Option<pl_protocol::ThreadStorageState>,
        ids: &super::observation_ids::ObservationIds,
        mode: pl_protocol::thread_facets::identity::ThreadObservationMode,
        reads: &super::thread_reads::lifetime::ThreadReadRegistry,
        thread_id: &str,
    ) -> Self {
        let (events, _) = broadcast::channel(LIVE_FEED_FRAMES);
        let (storage, _) = watch::channel(storage);
        let (last_turn, _) = watch::channel(None);
        Self {
            mode,
            facets: facets::ThreadFacetSources::new(ids, reads, thread_id),
            events,
            storage,
            last_turn,
        }
    }

    pub(in crate::studio) fn subscribe(&self) -> broadcast::Receiver<ThreadLiveEvent> {
        self.events.subscribe()
    }

    /// Watches the newest terminal Turn this owner projected, so a subscriber that registers after
    /// that commit never has to derive the fact from the window or from SQL.
    pub(in crate::studio) fn last_turn(&self) -> watch::Receiver<Option<Arc<pl_protocol::Turn>>> {
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
    fn publish_last_turn(&self, turn: Arc<pl_protocol::Turn>) {
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
    pub(in crate::studio) fn storage(
        &self,
    ) -> watch::Receiver<Option<pl_protocol::ThreadStorageState>> {
        self.storage.subscribe()
    }

    /// Publishes the owner's newly derived typed storage state.
    fn publish_storage(&self, storage: Option<pl_protocol::ThreadStorageState>) {
        self.storage.send_replace(storage);
    }

    fn publish(&self, event: ThreadLiveEvent) {
        // A feed with no subscriber is the normal state of a Thread without an open GUI; the
        // projection owner still consumed and published the fact.
        let _ = self.events.send(event);
    }

    /// Tells every subscriber that the owner re-seeded and continuity is no longer provable.
    fn rebase(&self, dropped: u64) {
        if let Ok(facets) = &self.facets {
            facets
                .execution
                .resync(pl_protocol::thread_facets::identity::ResyncReason::SourceLagged);
            facets
                .authoring
                .resync(pl_protocol::thread_facets::identity::ResyncReason::SourceLagged);
            facets
                .configuration
                .resync(pl_protocol::thread_facets::identity::ResyncReason::SourceLagged);
            facets
                .context
                .resync(pl_protocol::thread_facets::identity::ResyncReason::SourceLagged);
        }
        self.publish(ThreadLiveEvent::Rebase { dropped });
    }
}

#[derive(Debug, Clone, Default)]
pub(in crate::studio::runtime) struct Progress {
    pub(in crate::studio::runtime) initialized: bool,
    pub(in crate::studio::runtime) applied: u64,
    /// Newest commit this projection owner had handed over when it applied `applied`.
    ///
    /// The durable barrier of a settled observation waits for exactly this ticket. It is not the
    /// absolute commit watermark: a Thread re-activated in this process starts from a fresh reliable
    /// channel whose commits are already durable, so waiting for the checkpoint's sequence would wait
    /// for a watermark that can never move.
    pub(in crate::studio::runtime) handoff: u64,
    pub(in crate::studio::runtime) error: Option<Arc<ProgressFailure>>,
    pub(in crate::studio::runtime) finished: bool,
}
struct WorkerState {
    progress: watch::Sender<Progress>,
    retry: Notify,
    fence: Mutex<Option<Arc<ObservationFence>>>,
    /// The Thread's reliable admission channel, shared with its history writer.
    ///
    /// A settled observation reads a finished Turn back from history, and its own barrier has to ask
    /// the writer that took the projection's handoff how far it is durable. The handle is captured
    /// here, at observation time, so the barrier observes the very incarnation the writer admits
    /// into instead of a channel that a cleanly detached predecessor already released.
    channel: Arc<HistoryChannel>,
}
struct Observation {
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    feed: Arc<ThreadLiveFeed>,
    task: Arc<BackgroundTask>,
}
impl Drop for Observation {
    fn drop(&mut self) {
        self.task.signal();
    }
}
#[derive(Clone)]
pub(super) struct ObservationServices {
    pub(super) config: crate::config::ConfigRuntime,
    pub(super) thread_modes: crate::mode::ThreadModeManager,
    pub(super) observation_ids: super::observation_ids::ObservationIds,
    pub(super) recovery: crate::studio::StudioRecoveryRegistry,
    pub(super) store: StudioStore,
    pub(super) events: ProductEventBus,
    pub(super) performance: ModelPerformanceOwner,
    pub(super) threads: crate::thread_assembler::WeakStudioThreadAssembler,
    pub(super) thread_factory: crate::studio::thread_factory::StudioThreadFactory,
    pub(super) writer: crate::studio::agent_host::ThreadWriteBehindWriter,
}
struct Shared {
    projector: ObservationServices,
    observations: Mutex<BTreeMap<String, Vec<Arc<Observation>>>>,
    /// One feed per currently observed Thread; removed when the Thread is drained.
    live: Mutex<BTreeMap<String, Arc<ThreadLiveFeed>>>,
    /// Frozen checkpoint projections never borrow or replace a live execution projection. They
    /// own a separate read incarnation, but no Thread handle, writer or observation worker.
    cold: Mutex<BTreeMap<String, ColdEntry>>,
    reads: super::thread_reads::lifetime::ThreadReadRegistry,
    empty_fence: Mutex<Option<Arc<WriteFence>>>,
}
#[derive(Clone)]
pub(super) struct ThreadObservations(Arc<Shared>);

impl ObservationCloseFailure {
    /// After this exact drain request resumes successfully, finish its original callback's
    /// remaining binding retirement. Caller retains the original Thread operation/cleanup gates.
    pub(crate) fn finish_original_drain(&self, thread_id: &str) {
        self.request
            .owner()
            .0
            .projector
            .thread_factory
            .forget_tool_binding(thread_id);
    }
}

struct ColdEntry {
    facets: Arc<facets::ThreadFacetSources>,
    /// Registered logical borrows, including admission guards. Arc clones are only memory
    /// references and never decide whether this checkpoint generation remains reusable.
    borrows: NonZeroU64,
}

/// Source acquisition and a final Cold borrow's retirement share the Cold registry guard. A lease
/// is moved into the accepted feed/scope, or rolls back on every failed admission path.
/// It is intentionally not Clone; feed samples may share an Arc of the same registered lease.
pub(super) struct ThreadFacetLease {
    owner: std::sync::Weak<Shared>,
    thread_id: String,
    facets: Arc<facets::ThreadFacetSources>,
    mode: pl_protocol::thread_facets::identity::ThreadObservationMode,
}

impl ThreadFacetLease {
    pub(super) fn source(&self) -> &facets::ThreadFacetSources {
        &self.facets
    }
    pub(super) fn thread_id(&self) -> &str {
        &self.thread_id
    }
    pub(super) fn mode(&self) -> pl_protocol::thread_facets::identity::ThreadObservationMode {
        self.mode
    }

    pub(super) fn open_read<M: Send + Sync + 'static>(
        self,
        revision: u64,
        material: impl FnOnce(pl_protocol::thread_facets::identity::ReadScopeIdentity) -> M,
        residency: super::residency::ThreadResidencyPins,
    ) -> Result<
        (
            Arc<super::thread_reads::lifetime::ThreadReadOwner>,
            Arc<super::thread_reads::lifetime::PinnedMaterial<M>>,
        ),
        pl_protocol::studio::StudioError,
    > {
        // Keep the receiver's allocation alive while moving the actual borrow into the scope.
        // On refusal, Group.open drops this lease after its admission locks; this Arc is not a
        // logical borrow and cannot suppress retirement when that rollback is the last lease.
        let facets = self.facets.clone();
        facets.reads.open(revision, material, self, residency)
    }
}

impl Drop for ThreadFacetLease {
    fn drop(&mut self) {
        if self.mode == pl_protocol::thread_facets::identity::ThreadObservationMode::Cold
            && let Some(owner) = self.owner.upgrade()
        {
            ThreadObservations(owner).release_cold_lease(self);
        }
    }
}

impl ThreadObservations {
    pub(super) fn new(
        projector: ObservationServices,
        reads: super::read_scopes::ReadScopeRegistry,
    ) -> Self {
        Self(Arc::new(Shared {
            projector,
            observations: Mutex::new(BTreeMap::new()),
            live: Mutex::new(BTreeMap::new()),
            cold: Mutex::new(BTreeMap::new()),
            reads: super::thread_reads::lifetime::ThreadReadRegistry::new(reads),
            empty_fence: Mutex::new(None),
        }))
    }

    fn live_lease(
        &self,
        thread_id: &str,
        facets: Arc<facets::ThreadFacetSources>,
    ) -> ThreadFacetLease {
        ThreadFacetLease {
            owner: Arc::downgrade(&self.0),
            thread_id: thread_id.to_owned(),
            facets,
            mode: pl_protocol::thread_facets::identity::ThreadObservationMode::Live,
        }
    }

    /// Called only with the Cold registry held, before the source can escape to a reader.
    fn borrow_cold(&self, thread_id: &str, entry: &mut ColdEntry) -> Result<ThreadFacetLease> {
        let thread_id = thread_id.to_owned();
        let next = entry.borrows.checked_add(1).ok_or_else(|| {
            pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Overloaded,
                "Cold projection borrow counter is exhausted",
                false,
            )
        })?;
        let lease = ThreadFacetLease {
            owner: Arc::downgrade(&self.0),
            thread_id,
            facets: entry.facets.clone(),
            mode: pl_protocol::thread_facets::identity::ThreadObservationMode::Cold,
        };
        entry.borrows = next;
        Ok(lease)
    }

    /// The live feed of one observed Thread, if its projection owner was installed.
    pub(super) fn live_feed(&self, id: &str) -> Option<Arc<ThreadLiveFeed>> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .filter(|feed| {
                feed.mode == pl_protocol::thread_facets::identity::ThreadObservationMode::Live
            })
            .cloned()
    }

    pub(super) fn live_facet_lease(&self, id: &str) -> Result<Option<ThreadFacetLease>> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .map(|feed| {
                feed.facets
                    .as_ref()
                    .map(|facets| self.live_lease(id, facets.clone()))
                    .map_err(|error| anyhow::Error::new(error.clone()))
            })
            .transpose()
    }

    /// Match the concrete physical handle captured by assembly, not a later current Thread ID.
    pub(super) fn execution_lease_for(&self, handle: &ThreadHandle) -> Result<ThreadFacetLease> {
        let observations = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for (id, entries) in observations.iter() {
            if let Some(observation) = entries
                .iter()
                .rev()
                .find(|entry| entry.thread.same_instance(handle))
            {
                let facets = observation
                    .feed
                    .facets
                    .as_ref()
                    .map_err(|error| anyhow::Error::new(error.clone()))?;
                facets.execution.ensure_open()?;
                return Ok(self.live_lease(id, facets.clone()));
            }
        }
        Err(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Unavailable,
            "The original Thread execution observation is not installed",
            true,
        )
        .into())
    }

    pub(super) fn execution_sources_at(
        &self,
        id: &str,
        origin: &pl_protocol::thread_facets::identity::ThreadFacetStamp,
    ) -> Result<Option<ThreadFacetLease>> {
        let live = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|feed| match &feed.facets {
                Ok(facets) if facets.execution.matches_origin(origin) => {
                    Some(self.live_lease(id, facets.clone()))
                }
                Ok(_) | Err(_) => None,
            });
        if live.is_some() {
            return Ok(live);
        }
        let mut entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match entries.get_mut(id) {
            Some(entry) if entry.facets.execution.matches_origin(origin) => {
                entry.facets.execution.ensure_open()?;
                self.borrow_cold(id, entry).map(Some)
            }
            Some(_) | None => Ok(None),
        }
    }

    /// Authoring reads resolve the original live/cold incarnation, not an ID's newer current entry.
    pub(super) fn authoring_sources_at(
        &self,
        id: &str,
        origin: &pl_protocol::thread_facets::identity::ThreadFacetStamp,
    ) -> Result<Option<ThreadFacetLease>> {
        let live = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|feed| match &feed.facets {
                Ok(facets) if facets.authoring.matches_origin(origin) => {
                    Some(self.live_lease(id, facets.clone()))
                }
                Ok(_) | Err(_) => None,
            });
        if live.is_some() {
            return Ok(live);
        }
        let mut entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match entries.get_mut(id) {
            Some(entry) if entry.facets.authoring.matches_origin(origin) => {
                entry.facets.authoring.ensure_open()?;
                self.borrow_cold(id, entry).map(Some)
            }
            Some(_) | None => Ok(None),
        }
    }

    /// Configuration details resolve only the original live/cold entry; never load current by ID.
    pub(super) fn configuration_sources_at(
        &self,
        id: &str,
        origin: &pl_protocol::thread_facets::identity::ThreadFacetStamp,
    ) -> Result<Option<ThreadFacetLease>> {
        let live = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|feed| match &feed.facets {
                Ok(facets) if facets.configuration.matches_origin(origin) => {
                    Some(self.live_lease(id, facets.clone()))
                }
                Ok(_) | Err(_) => None,
            });
        if live.is_some() {
            return Ok(live);
        }
        let mut entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match entries.get_mut(id) {
            Some(entry) if entry.facets.configuration.matches_origin(origin) => {
                entry.facets.configuration.ensure_open()?;
                self.borrow_cold(id, entry).map(Some)
            }
            Some(_) | None => Ok(None),
        }
    }

    /// Context uses its original observation incarnation, including checkpoint-backed Cold reads.
    pub(super) fn context_sources_at(
        &self,
        id: &str,
        origin: &pl_protocol::thread_facets::identity::ThreadFacetStamp,
    ) -> Result<Option<ThreadFacetLease>> {
        let live = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|feed| match &feed.facets {
                Ok(facets) if facets.context.matches_origin(origin) => {
                    Some(self.live_lease(id, facets.clone()))
                }
                Ok(_) | Err(_) => None,
            });
        if live.is_some() {
            return Ok(live);
        }
        let mut entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match entries.get_mut(id) {
            Some(entry) if entry.facets.context.matches_origin(origin) => {
                entry.facets.context.ensure_open()?;
                self.borrow_cold(id, entry).map(Some)
            }
            Some(_) | None => Ok(None),
        }
    }

    /// A ref resolves only its original metrics incarnation, even when both modes coexist. An
    /// unrelated failed Live allocation must not hide a valid checkpoint-backed Cold origin.
    /// The returned admission lease is registered before identity validation or scope budgeting.
    pub(super) fn metrics_sources_at(
        &self,
        id: &str,
        origin: &pl_protocol::thread_facets::identity::ThreadFacetStamp,
    ) -> Result<Option<ThreadFacetLease>> {
        let live = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|feed| match &feed.facets {
                Ok(facets) if facets.metrics.matches_origin(origin) => {
                    Some(self.live_lease(id, facets.clone()))
                }
                Ok(_) | Err(_) => None,
            });
        if live.is_some() {
            return Ok(live);
        }
        let mut entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match entries.get_mut(id) {
            Some(entry) if entry.facets.metrics.matches_origin(origin) => {
                entry.facets.metrics.ensure_open()?;
                self.borrow_cold(id, entry).map(Some)
            }
            Some(_) | None => Ok(None),
        }
    }

    /// Reserve the unique cold entry before its first storage await. A concurrent caller reuses
    /// that Pending source; only its opening owner performs the immutable checkpoint read.
    pub(super) fn cold_facet_sources(&self, id: &str) -> Result<(ThreadFacetLease, bool)> {
        let mut entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(entry) = entries.get_mut(id) {
            entry.facets.metrics.ensure_open()?;
            return Ok((self.borrow_cold(id, entry)?, false));
        }
        let facets =
            facets::ThreadFacetSources::new(&self.0.projector.observation_ids, &self.0.reads, id)?;
        let lease = ThreadFacetLease {
            owner: Arc::downgrade(&self.0),
            thread_id: id.to_owned(),
            facets: facets.clone(),
            mode: pl_protocol::thread_facets::identity::ThreadObservationMode::Cold,
        };
        entries.insert(
            id.to_owned(),
            ColdEntry {
                facets,
                borrows: NonZeroU64::MIN,
            },
        );
        Ok((lease, true))
    }

    /// A failed opening published no baseline. Later retry gets a new original incarnation,
    /// rather than retaining an unchangeable transient read failure as the current cold owner.
    pub(super) fn discard_cold_sources(&self, lease: &ThreadFacetLease) {
        let entries = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(entry) = entries.get(&lease.thread_id)
            && Arc::ptr_eq(&entry.facets, &lease.facets)
        {
            // Seal this failed generation, but keep its admission bookkeeping until all guards
            // roll back. No failed opening can detach a still-registered borrow from its entry.
            entry
                .facets
                .close(pl_protocol::thread_facets::identity::FeedClosedReason::OwnerReplaced);
        }
    }

    fn release_cold_lease(&self, lease: &ThreadFacetLease) {
        let retired = {
            let mut entries = self
                .0
                .cold
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let remove = match entries.get_mut(&lease.thread_id) {
                Some(entry) if Arc::ptr_eq(&entry.facets, &lease.facets) => {
                    // A stored entry always has at least one registered lease. Removal, rather
                    // than publishing zero, linearizes against every new Cold acquisition.
                    match NonZeroU64::new(entry.borrows.get() - 1) {
                        Some(remaining) => {
                            entry.borrows = remaining;
                            false
                        }
                        None => true,
                    }
                }
                Some(_) | None => false,
            };
            if remove {
                entries.remove(&lease.thread_id).map(|entry| entry.facets)
            } else {
                None
            }
        };
        if let Some(facets) = retired {
            // Close only the removed generation, outside the registry lock. A new incarnation
            // may already be registered; neither its lease count nor its source is touched here.
            facets.close(pl_protocol::thread_facets::identity::FeedClosedReason::Requested);
        }
    }

    pub(super) fn install(
        &self,
        rejected_tools: super::rejected_tools::RejectedToolOwners,
    ) -> Result<()> {
        let thread_factory = self.0.projector.thread_factory.clone();
        let owner = Arc::downgrade(&self.0);
        let draining = owner.clone();
        let message_store = self.0.projector.store.clone();
        let closing_factory = thread_factory.clone();
        let threads = self.0.projector.threads.upgrade()?;
        threads.observe_assembly(
            move |id, thread| {
                if let Some(owner) = owner.upgrade() {
                    ThreadObservations(owner).observe(id, thread);
                }
            },
            move |id: String| {
                let owner = draining.clone();
                let thread_factory = thread_factory.clone();
                Box::pin(async move {
                    let owner = owner
                        .upgrade()
                        .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    let observations = ThreadObservations(owner);
                    observations
                        .drain(&id)
                        .await
                        .map_err(|source| {
                            crate::thread_assembler::ThreadAssemblyError::Resource {
                                operation: "drain Thread product observation",
                                source: source.into(),
                            }
                        })?;
                    thread_factory.forget_tool_binding(&id);
                    Ok(())
                })
            },
            // 一条已受理消息的持久身份：per-Thread 身份索引给出正文摘要与原始受理序号，因此离开
            // 常驻窗口的重复投递会被裁决而不是再送一次。索引行缺少摘要（迁移回填）或时间线已提交
            // 但索引无法证明正文的旧消息都按“不可验证”上报，让上层 fail-closed；查询失败同样上报，
            // 绝不在无法证明身份时把投递当成新消息受理。
            Some(Arc::new(move |thread_id: String, message_id: String| {
                let store = message_store.clone();
                Box::pin(async move {
                    let identity_error = |source: anyhow::Error| {
                        crate::thread_assembler::ThreadAssemblyError::Resource {
                            operation: "read durable message identity",
                            source: source.into_boxed_dyn_error(),
                        }
                    };
                    // 该身份查询是冷读路径：没有活跃 writer 时 `history` 只是一个不做 IO 的句柄，
                    // 不建库也不升级它；有活跃 writer 时它正是这个 Thread 的同一权威句柄，读会等
                    // 本句柄 writer 完成建表与 identity meta，因此不会读到半初始化库。这里刻意不
                    // 另开独立 HistoryStore，避免未启动的冷读绕过本句柄的初始化锁。
                    let history = store.history(&thread_id).await.map_err(identity_error)?;
                    if let Some(identity) =
                        history.message_identity(&message_id).await.map_err(identity_error)?
                    {
                        return Ok(Some(match identity.digest {
                            Some(digest) => {
                                crate::thread_assembler::observation::DurableMessageIdentity::Proven {
                                    sequence: identity.sequence,
                                    digest,
                                }
                            }
                            None => crate::thread_assembler::observation::DurableMessageIdentity::Unverifiable,
                        }));
                    }
                    // 时间线已经提交这条消息、但索引没有它的记录：升级前的历史无法证明正文，
                    // 必须 fail-closed，而不是重新投递成新消息。
                    let item = crate::studio::thread_projection::order::message_id(&message_id);
                    let committed = history
                        .existing_items([item])
                        .await
                        .map_err(identity_error)?;
                    Ok((!committed.is_empty()).then_some(
                        crate::thread_assembler::observation::DurableMessageIdentity::Unverifiable,
                    ))
                })
            })),
            move |id: String, thread: ThreadHandle| {
                // Cancellation is synchronous, so no new preparation can pass the gate.
                let gate = closing_factory.stop_tool_operation(&id);
                let rejected = rejected_tools.clone();
                Box::pin(async move {
                    let _guard = match gate { Some(gate) => Some(gate.lock_owned().await), None => None };
                    rejected.retry(Some(&thread)).await.map_err(|source| crate::thread_assembler::ThreadAssemblyError::Resource {
                        operation: "drain Thread tool candidates", source: source.into_boxed_dyn_error(),
                    })
                })
            },
        )?;
        Ok(())
    }

    /// Releases the retained observation for a drained or evicted Thread.
    ///
    /// The observation worker owns a strong `ThreadHandle`; keeping its entry after the assembly
    /// registry released the owner would keep every session that was ever activated resident. The
    /// entry is removed once its final projection is durable, so a later re-activation installs a
    /// fresh observation instead of reusing the released handle.
    async fn drain(&self, id: &str) -> Result<(), ObservationCloseFailure> {
        let entries = self.observations(Some(id));
        let request = self.close_request(close::CloseKind::Drain, &entries);
        self.execute_close_request(request, None).await
    }

    fn observe(&self, id: String, thread: ThreadHandle) {
        let recovered_through = thread.snapshot().commit_sequence;
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
            progress,
            retry: Notify::new(),
            fence: Mutex::new(None),
            channel,
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
        let feed = Arc::new(ThreadLiveFeed::new(
            initial_storage,
            &self.0.projector.observation_ids,
            pl_protocol::thread_facets::identity::ThreadObservationMode::Live,
            &self.0.reads,
            &id,
        ));
        let previous = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(id.clone(), feed.clone());
        if let Some(previous) = previous
            && let Ok(facets) = &previous.facets
        {
            facets.close(pl_protocol::thread_facets::identity::FeedClosedReason::OwnerReplaced);
        }
        let worker_state = state.clone();
        let projector = self.0.projector.clone();
        let worker_thread = thread.clone();
        let worker_id = id.clone();
        let worker_feed = feed.clone();
        let task = tokio::spawn(async move {
            use futures::FutureExt;
            let failure_feed = worker_feed.clone();
            let result = std::panic::AssertUnwindSafe(run(
                projector,
                worker_id,
                worker_thread,
                worker_state,
                recovered_through,
                worker_feed,
            ))
            .catch_unwind()
            .await;
            if let Err(panic) = result {
                if let Ok(facets) = &failure_feed.facets {
                    facets
                        .metrics
                        .fail(pl_protocol::studio::StudioError::internal());
                    facets
                        .execution
                        .fail(pl_protocol::studio::StudioError::internal());
                    facets
                        .authoring
                        .fail(pl_protocol::studio::StudioError::internal());
                    facets
                        .configuration
                        .fail(pl_protocol::studio::StudioError::internal());
                    facets
                        .context
                        .fail(pl_protocol::studio::StudioError::internal());
                }
                // Publish the facet's failure, but preserve the real failed join for drain/exit.
                std::panic::resume_unwind(panic);
            }
        });
        let observation = Arc::new(Observation {
            thread,
            state,
            feed,
            task: BackgroundTask::new(task),
        });
        let mut all = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let previous = all.entry(id).or_default();
        // A final frame and successful task alone do not settle the original history/read
        // obligations. Only exact-Arc drain after all its fences/scopes are Clean retires it.
        previous.push(observation);
    }

    async fn synchronize(&self, id: Option<&str>) -> Result<()> {
        let observations = self.observations(id);
        self.synchronize_entries(&observations).await
    }

    fn observations(&self, id: Option<&str>) -> Vec<(String, Arc<Observation>)> {
        self.0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|(key, _)| id.is_none_or(|id| id == key.as_str()))
            .flat_map(|(id, entries)| entries.iter().map(|entry| (id.clone(), entry.clone())))
            .collect()
    }

    async fn synchronize_entries(&self, observations: &[(String, Arc<Observation>)]) -> Result<()> {
        let request = self.close_request(close::CloseKind::Synchronize, observations);
        self.execute_close_request(request, None)
            .await
            .map_err(anyhow::Error::new)
    }

    /// Explicit parent continuation repairs terminal notifications even for unloaded children.
    /// This prepares persisted schemas (including saved-representation versions) and reads
    /// checkpoints plus durable history; no child owner, model or workspace is opened.
    pub(super) async fn reconcile_children(&self, parent: &str) -> Result<()> {
        let services = &self.0.projector;
        for child in services.store.list_threads_for_root(parent).await? {
            if child.parent_thread_id.as_deref() != Some(parent) {
                continue;
            }
            let resident = services.threads.upgrade()?.thread(&child.id).is_some();
            if resident {
                self.synchronize(Some(&child.id)).await?;
                continue;
            }
            let child = pl_protocol::Thread::from(child);
            let Some(checkpoint) =
                crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                    &services.store,
                    &child,
                )
                .await?
            else {
                continue;
            };
            if let Some(turn) = checkpoint
                .state
                .turns
                .iter()
                .rev()
                .find(|turn| turn.state != pl_core::thread::TurnState::Running)
            {
                // An unloaded child has no resident projection, so this repair reads the Turn's
                // items from durable history: it is the cold path, and the checkpoint cannot carry
                // the finished Turn's body.
                let items = services
                    .store
                    .history(&child.id)
                    .await?
                    .items_for_turn(&turn.turn_id)
                    .await?;
                reports::publish_terminal(
                    services,
                    &child,
                    &checkpoint.state,
                    turn,
                    checkpoint.state_revision,
                    false,
                    &crate::studio::thread_projection::TurnResult::from_items(&items),
                )
                .await?;
            }
        }
        Ok(())
    }

    pub(super) async fn finish(&self) -> Result<()> {
        // Cold has no worker dependency: seal its original scopes before the first await.
        let cold: Vec<_> = self
            .0
            .cold
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .map(|entry| entry.facets.clone())
            .collect();
        for facets in cold {
            facets.close(pl_protocol::thread_facets::identity::FeedClosedReason::RuntimeStopped);
        }
        let entries = self.observations(None);
        let request = self.close_request(close::CloseKind::Finish, &entries);
        self.execute_close_request(request, None)
            .await
            .map_err(anyhow::Error::new)
    }
}

impl StudioRuntime {
    /// Waits for product directories and billing to reach the current committed Thread watermark.
    /// Reattempts a previously failed projection without invoking models or tools.
    pub async fn synchronize_thread_observation(&self, thread_id: &str) -> Result<()> {
        self.thread_observations.synchronize(Some(thread_id)).await
    }
}

/// The single realtime projection owner of one Thread.
///
/// It lives in the Thread's observation worker, so a GUI opening and closing never changes who
/// projects or who publishes content: every committed effect is projected exactly once into the
/// shared chat session, and its typed changes are broadcast to whichever subscribers exist. The same
/// batch is handed to the Thread's reliable admission channel, so the history writer commits the
/// content this owner published instead of projecting the effect a second time.
struct LiveOwner {
    config: crate::config::ConfigRuntime,
    thread_modes: crate::mode::ThreadModeManager,
    configuration_inputs: facets::configuration::ConfigurationInputs,
    projection: LiveProjection,
    /// The Thread's only activity projection: the same owner derives it from the snapshot it just
    /// published, so activity never becomes a second fact source and never reads SQL.
    activity: crate::studio::thread_projection::ActivityProjection,
    /// Last activity already broadcast, so an unchanged projection does not produce a frame.
    activity_published: Option<Arc<pl_protocol::ThreadActivity>>,
    runtime_published: Option<pl_protocol::ThreadRuntimeSnapshot>,
    /// Last typed storage state this owner published to its feed.
    ///
    /// The owner derives it from the owner snapshot plus the coordinator's typed watch, so a
    /// subscriber mirrors the value instead of recomputing it from its own copies. It is kept as one
    /// value so a change of fault kind, generation, watermark or phase is all one comparison.
    storage_published: Option<Arc<pl_protocol::ThreadStorageState>>,
    persistence: Option<pl_protocol::ThreadPersistenceSnapshot>,
    /// The Thread's reliable admission channel, shared with the history writer.
    channel: Arc<HistoryChannel>,
    chat: Session,
    thread: pl_protocol::Thread,
    usage: UsageSummary,
    feed: Arc<ThreadLiveFeed>,
}

impl LiveOwner {
    async fn open(
        projector: &ObservationServices,
        handle: &ThreadHandle,
        snapshot: &ThreadSnapshot,
        thread: pl_protocol::Thread,
        feed: Arc<ThreadLiveFeed>,
        channel: Arc<HistoryChannel>,
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
    ) -> Result<Self> {
        let id = thread.id.as_str();
        let chat = projector.store.chat_session(id).await?;
        let usage = live_usage(projector, id, snapshot);
        if let Ok(facets) = &feed.facets {
            facets.metrics.observe(snapshot, &usage);
            facets.authoring.seed(snapshot);
        }
        // The one cold read of a projection: the durable facts of work that already started before
        // this owner existed. Everything the commit and preview paths resolve afterwards comes from
        // these tables, so a re-activated Thread never waits on a history reader mid-Turn.
        let mut projection = LiveProjection::new();
        let retained = handle.effects().await?;
        let (seed_items, hidden) =
            cold_seed(&projector.store, &thread, snapshot, &channel, &retained).await?;
        projection.seed(seed_items, hidden);
        // Seed the activity projection from the very snapshot this owner was installed on, so a
        // subscriber that opens mid-Turn immediately sees the authoritative current activity.
        let mut activity = crate::studio::thread_projection::ActivityProjection::default();
        let activity_published = activity.observe(id, snapshot).map(Arc::new);
        // The owner is the single source of the typed storage state: publish the value it was
        // installed with, so a subscriber that opened before this first pass sees the authoritative
        // fact instead of an unset placeholder.
        let storage_published = persistence.map(|detail| Arc::new(storage_state(snapshot, detail)));
        // Seed the runtime baseline from the same snapshot and cumulative usage that the first
        // stream pass will project. This prevents owner activation itself from emitting a duplicate
        // runtime frame; subsequent frames still advance only when the typed projection changes.
        let mut runtime = crate::studio::thread_projection::project_runtime(
            id,
            snapshot,
            thread.updated_at,
            &usage,
        )?;
        let (configuration_inputs, config) = facets::configuration::ConfigurationInputs::observe(
            &projector.config,
            &projector.thread_modes,
        )?;
        crate::studio::model_route::annotate_availability(&mut runtime, &thread, &config.config)?;
        if let Ok(facets) = &feed.facets {
            facets.configuration.observe(
                &runtime,
                configuration_inputs.stamp,
                configuration_inputs.mode_revision(),
                snapshot
                    .extensions
                    .get("studio.mode")
                    .map(|record| record.revision),
            )?;
            let policy = facets::context::current_policy(
                &config.config,
                runtime.model_route.as_ref(),
                configuration_inputs.stamp,
                configuration_inputs.mode_revision(),
            )?;
            facets
                .context
                .observe(&runtime, policy, facets.metrics.snapshot()?)?;
        }
        let runtime_published = Some(runtime);
        feed.publish_storage(storage_published.as_deref().cloned());
        let owner = Self {
            config: projector.config.clone(),
            thread_modes: projector.thread_modes.clone(),
            configuration_inputs,
            projection,
            activity,
            activity_published,
            runtime_published,
            storage_published,
            persistence: persistence.cloned(),
            channel,
            chat,
            thread,
            usage,
            feed,
        };
        // The seeded facts are already resident, so the Thread's budget covers them from the moment
        // the owner is installed instead of only after its first commit.
        owner.publish_retained();
        // A Thread re-activated after its last Turn finished has no live frame left for that fact:
        // the authoritative snapshot carries only the active Turn and `turnCompleted` was broadcast
        // once, to subscribers that may be long gone. This is the very cold-read path the owner is
        // installed on, so the newest terminal Turn is read here once — bounded, without item bodies
        // — and seeded into the same retained fact the live projection publishes. The live path can
        // then only move it forward, so a seed can never hide a later finished Turn, and a late
        // duplicate of a Turn already retained is dropped by the same identity/revision guard.
        if let Some(turn) = projector
            .store
            .history(&owner.thread.id)
            .await?
            .newest_terminal_turn()
            .await?
        {
            owner.feed.publish_last_turn(Arc::new(turn));
        }
        Ok(owner)
    }

    /// Publishes how much this projection currently retains in its own tables.
    ///
    /// The projection owns the retained bodies and the Turn report accumulator, and both outlive
    /// the batch the writer already committed. The reliable channel's budget is what pauses new
    /// model/tool admission at a safe gap, so it has to see this number; nothing here waits for a
    /// GUI, because the owner publishes whether or not anyone is subscribed.
    fn publish_retained(&self) {
        // The activity summary and its bounded resident detail are resident facts of the same owner,
        // so they belong to the same Thread budget instead of living outside it.
        let bytes = self
            .projection
            .retained_bytes()
            .saturating_add(self.activity.retained_bytes());
        self.channel.set_projection_bytes(bytes);
    }

    /// Projects one admitted write into the session, broadcasts its live changes and hands the very
    /// same immutable batch to the Thread's reliable save channel.
    ///
    /// The batch is published before it is handed over, so the writer can only ever confirm a body
    /// the shared window already holds: there is no save-before-publish interleaving to lose.
    ///
    /// A reliable-output repair can name an identity the bounded window already released. This owner is
    /// still the single fact source for the canonical item and its content version, so it reads that
    /// already-committed body back once here and folds it in before projecting; the ordinary path reads
    /// nothing, and the writer never invents a version or re-projects a written effect.
    async fn advance(
        &mut self,
        services: &ObservationServices,
        thread_id: &str,
        write: &ThreadWrite,
    ) -> Result<()> {
        self.seed_durable_targets(services, thread_id, write)
            .await?;
        self.project_write(write)
    }

    /// Reads the identities one effect needs but this projection holds no canonical body for.
    ///
    /// Two effects reference an already-committed body the bounded window may have released: a
    /// reliable-output repair names a committed result, and a user-input interaction names the call
    /// that raised it — a call whose Turn is already finished, so after a restart the projection never
    /// saw it at all. Both are read back **by identity only** and handed to the projection as facts,
    /// so the projection still consumes facts and never performs IO. The ordinary path reads nothing,
    /// and a missing or invalid durable body fails here instead of being skipped.
    async fn seed_durable_targets(
        &mut self,
        services: &ObservationServices,
        thread_id: &str,
        write: &ThreadWrite,
    ) -> Result<()> {
        if write.effect.delivery_repairs.is_empty() && write.effect.interactions.is_empty() {
            return Ok(());
        }
        let history = services.store.history(thread_id).await?;
        crate::studio::thread_projection::seed_repaired_targets(
            &mut self.projection,
            &history,
            &write.effect,
        )
        .await
        .map_err(|error| anyhow::anyhow!("live Thread repair seed failed: {error}"))?;
        crate::studio::thread_projection::seed_interaction_targets(
            &mut self.projection,
            thread_id,
            &history,
            &write.effect,
        )
        .await
        .map_err(|error| anyhow::anyhow!("live Thread user-input seed failed: {error}"))?;
        Ok(())
    }

    /// Folds one admitted write into the shared session and the reliable save channel.
    fn project_write(&mut self, write: &ThreadWrite) -> Result<()> {
        let effect = &write.effect;
        let projected = (|| {
            crate::studio::thread_projection::fold_effect_accounting(&mut self.usage, effect)?;
            self.projection
                .advance(&self.chat, &self.thread, effect, &write.checkpoint.state)
        })();
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
        self.channel.prepare(prepared);
        // Retain the terminal Turn of this commit as the owner's own last-turn fact before the frame
        // is broadcast: `turnCompleted` reaches only the subscribers that exist right now, so the
        // value a later subscriber is told has to be the very frame this commit produced.
        if let Some(turn) = changes.iter().rev().find_map(|change| match change {
            LiveEvent::Turn { turn, .. } if turn.state.is_terminal() => Some(turn),
            _ => None,
        }) {
            self.feed.publish_last_turn(Arc::new(turn.clone()));
        }
        self.observe_activity(&write.checkpoint.state);
        let persistence = self.persistence.clone();
        self.observe_storage(&write.checkpoint.state, persistence.as_ref());
        self.publish_execution(&write.checkpoint.state, &changes);
        if let Ok(facets) = &self.feed.facets {
            facets.authoring.observe(write);
        }
        self.feed.publish(ThreadLiveEvent::Committed {
            sequence: effect.sequence,
            changes,
        });
        self.publish_retained();
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
        thread_id: &str,
        write: &ThreadWrite,
    ) -> Result<()> {
        self.seed_durable_targets(services, thread_id, write)
            .await?;
        let projected = self.projection.project_committed(
            &self.chat,
            &self.thread,
            &write.effect,
            &write.checkpoint.state,
        );
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
        if let Some(turn) = crate::studio::thread_projection::prepared_terminal_turn(&prepared) {
            self.feed.publish_last_turn(Arc::new(turn));
        }
        self.channel.prepare(prepared);
        self.publish_retained();
        Ok(())
    }

    /// Projects the uncommitted streaming preview of the current owner snapshot.
    ///
    /// The preview is written into the shared session — the one content window — and emits no
    /// content frame; current activity and runtime facts are published separately.
    async fn stream(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        if let Ok(facets) = &self.feed.facets {
            facets.metrics.observe(snapshot, &self.usage);
        }
        self.projection
            .stream(&self.chat, &self.thread, snapshot, snapshot.commit_sequence)
            .await
            .map_err(|error| anyhow::anyhow!("live Thread preview failed: {error}"))?;
        self.observe_runtime(snapshot)?;
        self.observe_activity(snapshot);
        self.publish_retained();
        Ok(())
    }

    /// Execution residency is live-only; next-admission availability also consumes current config.
    /// Derive runtime from the latest owner snapshot after folding all admitted usage,
    /// never from an effect's storage checkpoint. Stable timestamps allow deduplication.
    fn observe_runtime(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let at = self
            .runtime_published
            .as_ref()
            .map_or(self.thread.updated_at, |runtime| runtime.updated_at);
        let mut runtime = crate::studio::thread_projection::project_runtime(
            &self.thread.id,
            snapshot,
            at,
            &self.usage,
        )?;
        let mut policy = self
            .configuration_inputs
            .refresh(&self.config, &self.thread_modes)?;
        let same_identity = match (
            self.runtime_published
                .as_ref()
                .and_then(|runtime| runtime.model_route.as_ref()),
            runtime.model_route.as_ref(),
        ) {
            (Some(previous), Some(current)) => {
                previous.account_id == current.account_id
                    && previous.model_id == current.model_id
                    && previous.effort == current.effort
                    && previous.revision == current.revision
            }
            (None, None) => true,
            _ => false,
        };
        if policy.is_none() && !same_identity && !self.configuration_inputs.stamp.closing {
            policy = Some(self.configuration_inputs.read_policy(&self.config)?);
        }
        if let Some(config) = &policy {
            crate::studio::model_route::annotate_availability(
                &mut runtime,
                &self.thread,
                &config.config,
            )?;
        } else if same_identity
            && let (Some(previous), Some(current)) = (
                self.runtime_published
                    .as_ref()
                    .and_then(|runtime| runtime.model_route.as_ref()),
                runtime.model_route.as_mut(),
            )
        {
            current.available = previous.available;
            current.unavailable_reason = previous.unavailable_reason.clone();
        }
        if let Ok(facets) = &self.feed.facets {
            facets.configuration.observe(
                &runtime,
                self.configuration_inputs.stamp,
                self.configuration_inputs.mode_revision(),
                snapshot
                    .extensions
                    .get("studio.mode")
                    .map(|record| record.revision),
            )?;
            let context_policy = if let Some(config) = &policy {
                facets::context::current_policy(
                    &config.config,
                    runtime.model_route.as_ref(),
                    self.configuration_inputs.stamp,
                    self.configuration_inputs.mode_revision(),
                )?
            } else if same_identity {
                facets.context.current_policy().map(|mut value| {
                    value.mode_revision = self.configuration_inputs.mode_revision();
                    value
                })
            } else {
                None
            };
            facets
                .context
                .observe(&runtime, context_policy, facets.metrics.snapshot()?)?;
        }
        if self.runtime_published.as_ref() == Some(&runtime) {
            return Ok(());
        }
        runtime.updated_at = crate::studio::unix_seconds();
        runtime.usage.updated_at = runtime.updated_at;
        self.runtime_published = Some(runtime.clone());
        self.feed.publish(ThreadLiveEvent::Runtime {
            runtime: Arc::new(runtime),
        });
        Ok(())
    }

    /// Re-derives the Thread's current activity from the snapshot this owner just published.
    ///
    /// The activity is an independent projection of the same facts: a phase change, a new foreground
    /// tool or an interaction change reaches it through the owner snapshot, never through `effect`.
    /// Only a real change is broadcast, so a streaming body update does not cost a second status
    /// frame and no subscriber ever has to project the activity itself.
    fn observe_activity(&mut self, snapshot: &ThreadSnapshot) {
        let activity = self
            .activity
            .observe(&self.thread.id, snapshot)
            .map(Arc::new);
        if activity == self.activity_published {
            return;
        }
        self.activity_published = activity.clone();
        // One shared handle per published change: every subscriber clones that handle, never the body.
        self.feed.publish(ThreadLiveEvent::Activity { activity });
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
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
    ) {
        let storage = persistence.map(|detail| Arc::new(storage_state(snapshot, detail)));
        if storage == self.storage_published {
            return;
        }
        self.storage_published = storage.clone();
        self.feed.publish_storage(storage.as_deref().cloned());
    }

    fn publish_execution(&self, snapshot: &ThreadSnapshot, effects: &[LiveEvent]) {
        if let Ok(facets) = &self.feed.facets {
            facets.execution.observe(
                &self.thread.id,
                self.thread.updated_at,
                snapshot,
                self.feed.last_turn.borrow().clone(),
                self.activity_published.clone(),
                self.storage_published.clone(),
                effects,
            );
        }
    }
}

impl Drop for LiveOwner {
    /// Releases this owner's share of the Thread's budget when the observation ends.
    ///
    /// The retained bodies die with the owner, so leaving the gauge where it was would keep a
    /// released Thread reading as pending work forever. A re-activated Thread installs a new owner
    /// that republishes its own tables on its first step.
    fn drop(&mut self) {
        self.channel.set_projection_bytes(0);
    }
}

/// The one cold read of a live projection: the durable facts of the work it is installed onto.
///
/// The current owner snapshot is deliberately compact — it no longer holds the process bodies a
/// running Turn committed earlier — so a projection installed mid-Turn would be unable to resolve an
/// identity a later effect still references. Reading the running and newest Turn's committed items
/// once, together with the hidden dispositions of the inputs still in play, closes that gap without
/// putting a history read on the commit or preview path.
async fn cold_seed(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
    snapshot: &ThreadSnapshot,
    channel: &HistoryChannel,
    retained: &[Arc<pl_core::thread::ThreadEffectBatch>],
) -> Result<(
    Vec<pl_protocol::ThreadItem>,
    std::collections::BTreeSet<String>,
)> {
    use std::collections::BTreeSet;

    // Capture before reading history: core may already have pruned the terminal Turn from
    // its current snapshot, but the reliable queue still owns the recovery commit's references.
    let pending = channel.unprojected_writes();
    let mut turn_ids = BTreeSet::new();
    let mut input_ids = BTreeSet::new();
    let mut item_ids = BTreeSet::new();
    for state in
        std::iter::once(snapshot).chain(pending.iter().map(|write| &write.checkpoint.state))
    {
        for turn in state.turns.iter() {
            turn_ids.insert(turn.turn_id.clone());
            input_ids.extend(turn.input_id.iter().cloned());
        }
        input_ids.extend(state.inputs.iter().map(|record| record.input.id.clone()));
        item_ids.extend(
            state.inbox.iter().map(|record| {
                crate::studio::thread_projection::order::message_id(&record.message.id)
            }),
        );
    }
    for write in &pending {
        // Reuse the projection's identity enumeration, including tool results whose attempt
        // already left the checkpoint. Do not maintain a second interpretation of effect kinds.
        let referenced = crate::studio::thread_projection::project_effect_items(
            thread,
            &write.checkpoint.state,
            &write.effect,
            &BTreeMap::new(),
            &BTreeMap::new(),
            &BTreeSet::new(),
        )?;
        for item in referenced.items {
            if !item.turn_id.is_empty() {
                turn_ids.insert(item.turn_id.clone());
            }
            item_ids.insert(item.id);
        }
        input_ids.extend(referenced.unresolved_inputs);
        item_ids.extend(referenced.unresolved_calls);
    }
    // Storage admission may lag behind core publication. These immutable effects remain in core
    // until durable acknowledgement, including recovery facts absent from both the pruned snapshot
    // and the admission queue. Enumerate their references before the first history read.
    for effect in retained {
        if let Some(turn) = &effect.turn {
            turn_ids.insert(turn.turn_id.clone());
            input_ids.extend(turn.input_id.iter().cloned());
        }
        if let Some(attempt) = &effect.attempt {
            turn_ids.insert(attempt.turn_id.clone());
        }
        for change in effect.inputs.iter() {
            use pl_core::thread::input::InputChange;
            input_ids.insert(match change {
                InputChange::Accepted(record) => record.input.id.clone(),
                InputChange::Transition { id, .. } => id.clone(),
            });
        }
        for task in effect.tasks.iter() {
            turn_ids.insert(task.turn_id.clone());
        }
        item_ids.extend(
            effect
                .tasks
                .iter()
                .map(|record| &record.call_id)
                .chain(effect.permissions.iter().map(|record| &record.call_id))
                .chain(effect.deliveries.iter().map(|record| &record.call_id))
                .chain(effect.delivery_repairs.iter().map(|record| &record.call_id))
                .map(|id| crate::studio::thread_projection::order::tool_id(id)),
        );
        item_ids.extend(
            effect.inbox.iter().map(|record| {
                crate::studio::thread_projection::order::message_id(&record.message.id)
            }),
        );
    }
    item_ids.extend(input_ids.iter().cloned());
    if turn_ids.is_empty() && item_ids.is_empty() {
        return Ok((Vec::new(), BTreeSet::new()));
    }
    let history = store.history(&thread.id).await?;
    history.prepare_activation().await?;
    let mut items = history.existing_items(item_ids).await?;
    turn_ids.extend(
        items
            .values()
            .filter(|item| !item.turn_id.is_empty())
            .map(|item| item.turn_id.clone()),
    );
    for turn_id in turn_ids {
        for item in history.items_for_turn(&turn_id).await? {
            items.insert(item.id.clone(), item);
        }
    }
    let hidden = history.hidden_input_identities(input_ids).await?;
    Ok((items.into_values().collect(), hidden))
}

/// Cumulative usage the live projection folds further effects onto.
///
/// The history writer's reported summary is the value a hot increment, a reconnect and a cold
/// restore agree on; a checkpoint that was loaded before any report seeds the same value.
fn live_usage(
    projector: &ObservationServices,
    id: &str,
    snapshot: &ThreadSnapshot,
) -> UsageSummary {
    let coordinator = projector.store.thread_persistence();
    match coordinator.usage(id) {
        Some(usage) => usage,
        None => {
            coordinator.seed_usage(id, snapshot.usage_summary.clone());
            snapshot.usage_summary.clone()
        }
    }
}

async fn run(
    projector: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    recovered_through: u64,
    feed: Arc<ThreadLiveFeed>,
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
    let mut current = thread.snapshot();
    let mut worker = ProjectionWorker {
        services: projector,
        id,
        thread,
        state,
        recovered_through,
        feed,
        live: None,
        pass: None,
        fences: ProjectionFences::default(),
        final_write: None,
    };
    // Product facts are projected once per committed revision; the live projection additionally
    // follows every owner snapshot so streaming previews reach the same single publisher.
    let mut projected = None;
    loop {
        if let Some(fence) = &worker.final_write {
            match fence.wait().await {
                Ok(()) => {
                    worker.state.progress.send_modify(|progress| {
                        progress.error = None;
                        progress.finished = true;
                    });
                    return;
                }
                Err(error) => {
                    worker.state.progress.send_modify(|progress| {
                        progress.error = Some(Arc::new(ProgressFailure::FinalWriteBehind(error)));
                    });
                }
            }
            tokio::select! {
                () = worker.state.retry.notified() => {}
                _ = handoff.changed() => {}
            }
            continue;
        }
        let issue_id = format!("tool-cleanup:{}", worker.id);
        let issue = (!current.tool_cleanup.failures.is_empty()).then(|| {
            crate::studio::StudioRecoveryIssue {
                id: issue_id.clone(),
                scope: crate::studio::StudioRecoveryIssueScope::Thread,
                category: crate::studio::StudioRecoveryIssueCategory::ToolCatalog,
                action: crate::studio::StudioRecoveryIssueAction::Retry,
                project_id: None,
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
                worker.services.threads.upgrade().is_ok_and(|threads| {
                    threads.observed_threads().iter().any(|(id, thread)| {
                        id == &worker.id && thread.same_instance(&worker.thread)
                    })
                })
            },
            |issues| {
                worker.services.events.emit_recovery_state(issues);
            },
        );
        let products = projected != Some((current.commit_sequence, current.lifecycle));
        // Read the coordinator's newest typed facts before publishing: a storage change is a fact
        // this pass has to carry, exactly like a commit or a preview it also projects.
        let detail = persistence
            .borrow_and_update()
            .threads
            .iter()
            .find(|detail| detail.thread_id == worker.id)
            .cloned();
        let resumed_pass = worker.pass.is_some();
        // The projection stays isolated behind `catch_unwind`, so a panicking projection is
        // still reported as an error instead of taking down the observation worker.
        let result =
            match std::panic::AssertUnwindSafe(worker.project(&current, products, detail.as_ref()))
                .catch_unwind()
                .await
            {
                Ok(result) => result,
                Err(_) => {
                    worker.state.progress.send_modify(|progress| {
                        progress.error = Some(Arc::new(ProgressFailure::ProjectionPanicked));
                        progress.finished = true;
                    });
                    worker.feed.rebase(0);
                    if let Ok(facets) = &worker.feed.facets {
                        facets
                            .metrics
                            .fail(pl_protocol::studio::StudioError::internal());
                        facets
                            .execution
                            .fail(pl_protocol::studio::StudioError::internal());
                        facets
                            .authoring
                            .fail(pl_protocol::studio::StudioError::internal());
                        facets
                            .configuration
                            .fail(pl_protocol::studio::StudioError::internal());
                        facets
                            .context
                            .fail(pl_protocol::studio::StudioError::internal());
                    }
                    // A partially panicked projection is terminal. Never replay its producer to
                    // disguise the failure as a cleanup retry.
                    return;
                }
            };
        match result {
            Ok(completed) => {
                if let Ok(facets) = &worker.feed.facets {
                    facets
                        .authoring
                        .confirm_caught_up(completed.commit_sequence);
                }
                if products {
                    projected = Some((completed.commit_sequence, completed.lifecycle));
                }
                let finished = completed.lifecycle == ThreadLifecycle::Closed;
                worker.state.progress.send_replace(Progress {
                    initialized: true,
                    applied: completed.commit_sequence,
                    handoff: worker.state.channel.handoff_ticket(),
                    error: None,
                    finished: false,
                });
                if finished {
                    worker.final_write = Some(WriteFence::capture(&worker.services.writer));
                    continue;
                }
                if resumed_pass
                    || (completed.commit_sequence, completed.lifecycle)
                        != (current.commit_sequence, current.lifecycle)
                {
                    // A failed pass kept its original snapshot. Catch up the already observed
                    // successor only after every phase of that original pass really completed.
                    // Previews/storage can change without a commit: the next fresh pass consumes
                    // them once, rather than sleeping after their wake was already consumed.
                    continue;
                }
            }
            Err(error) => {
                let error = Arc::new(error);
                let failure = Arc::new(ProgressFailure::Retry {
                    point: RetryPoint::Projection,
                    cause: error.clone(),
                });
                // Preserve the actual business failure before any facet/diagnostic callback can
                // cause an independent outer panic. The projection pass retains its phase.
                worker
                    .state
                    .progress
                    .send_modify(|progress| progress.error = Some(failure));
                worker.feed.rebase(0);
                if let Ok(facets) = &worker.feed.facets {
                    facets
                        .execution
                        .capture_failed(crate::studio_error_from_anyhow_ref(error.as_ref()));
                    facets.authoring.capture_failed(error.clone());
                    facets
                        .configuration
                        .capture_failed(crate::studio_error_from_anyhow_ref(error.as_ref()));
                    facets
                        .context
                        .capture_failed(crate::studio_error_from_anyhow_ref(error.as_ref()));
                }
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
            () = async {
                match worker.live.as_mut() {
                    Some(owner) => owner.configuration_inputs.changed().await,
                    None => std::future::pending().await,
                }
            } => current = worker.thread.snapshot(),
            // A handoff the writer is waiting for may be the only reason this worker still has work
            // to do; re-run the projection so a deferred admission is taken over and saved.
            _ = handoff.changed() => current = worker.thread.snapshot(),
            // A typed storage change with no owner frame still has to reach subscribers; re-run the
            // pass so the owner republishes the state it just read.
            _ = persistence.changed() => current = worker.thread.snapshot(),
            update = updates.next() => match update {
                Some(snapshot) => current = snapshot,
                None => {
                    worker.state.progress.send_modify(|progress| {
                        progress.error = Some(Arc::new(ProgressFailure::Retry {
                            point: RetryPoint::SubscriptionEnded,
                            cause: Arc::new(anyhow::anyhow!("Thread subscription ended before its final projection")),
                        }));
                    });
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
    pass: Option<fences::ProjectionPass>,
    fences: ProjectionFences,
    final_write: Option<Arc<WriteFence>>,
}

/// The report facts of one finished Turn: the live projection's bounded accumulator when it folded
/// the Turn, otherwise the durable single-Turn slice.
///
/// The hot path takes the accumulator, which the projection maintained from the Turn's first
/// record, so a Turn that committed its visible output over many effects reports all of it without a
/// second copy of every body and without a history read. A Turn the resident projection never saw
/// from its start — a Thread re-activated once its Turn had already run, or a recovered child — has
/// no accumulator, and only then does this wait for the matching durable handoff and read the
/// bounded single-Turn slice from history. That is the cold recovery path, never a routine commit.
async fn turn_result(
    services: &ObservationServices,
    live: &LiveOwner,
    turn_id: &str,
    fences: &mut ProjectionFences,
) -> Result<crate::studio::thread_projection::TurnResult> {
    if fences.turn.is_none() {
        if let Some(result) = live.projection.turn_result(turn_id) {
            return Ok(result.clone());
        }
        fences.turn = Some((
            turn_id.to_owned(),
            HistoryFence {
                channel: live.channel.clone(),
                through: live.channel.handoff_ticket(),
            },
        ));
    }
    let (original_turn, fence) = fences.turn.as_ref().expect("original Turn fence installed");
    anyhow::ensure!(
        original_turn == turn_id,
        "original observation Turn fence changed identity"
    );
    fence.wait(&live.thread.id).await?;
    let items = services
        .store
        .history(&live.thread.id)
        .await?
        .items_for_turn(turn_id)
        .await?;
    let result = crate::studio::thread_projection::TurnResult::from_items(&items);
    fences.turn = None;
    Ok(result)
}

/// The Thread's product association, from the resident directory entry or from durable storage.
///
/// An archived hot entry may disappear before its original registration reaches SQLite, so the cold
/// branch drains the accepted directory writes first. The target is fixed at admission time and later
/// unrelated writes do not extend the wait. Only the first install and a product refresh resolve this
/// DTO: a streaming preview belongs to the owner already installed and never reads the directory.
async fn product_association(
    services: &ObservationServices,
    id: &str,
    fences: &mut ProjectionFences,
) -> Result<pl_protocol::Thread> {
    if fences.association.is_none() {
        if let Some(thread) = services.events.thread_snapshot(id) {
            return Ok(thread);
        }
        fences.association = Some(WriteFence::capture(&services.writer));
    }
    fences
        .association
        .as_ref()
        .expect("original association fence installed")
        .wait()
        .await?;
    let association = services
        .store
        .read_thread_association(id)
        .await?
        .context("observed Thread has no product association")?;
    fences.association = None;
    Ok(pl_protocol::Thread::from(association))
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
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
    ) -> Result<Arc<ThreadSnapshot>> {
        use fences::{EffectPhase, PendingEffect, ProjectionPass, ProjectionPhase};
        let Self {
            services,
            id,
            thread,
            state,
            recovered_through,
            feed,
            live,
            pass,
            fences,
            ..
        } = self;
        if pass.is_none() {
            *pass = Some(ProjectionPass::new(Arc::new(snapshot.clone()), products));
        }
        let original = pass.as_mut().expect("original projection pass installed");
        // Persistence is a current owner fact, not one of the pass's fixed durability tickets.
        // Retrying a phase must not replace a newer storage observation with its old diagnostic.
        if let Some(owner) = live.as_mut() {
            owner.persistence = persistence.cloned();
            owner.observe_storage(snapshot, persistence);
        }
        loop {
            match original.phase {
                ProjectionPhase::Initialize => {
                    if live.is_none() {
                        if original.product.is_none() {
                            original.product =
                                Some(product_association(services, id, fences).await?);
                        }
                        let product = original
                            .product
                            .as_ref()
                            .expect("original association retained")
                            .clone();
                        *live = Some(
                            LiveOwner::open(
                                services,
                                thread,
                                &original.snapshot,
                                product,
                                feed.clone(),
                                state.channel.clone(),
                                persistence,
                            )
                            .await?,
                        );
                        original.product = None;
                    }
                    let owner = live.as_mut().expect("live owner installed");
                    owner.persistence = persistence.cloned();
                    owner.observe_storage(snapshot, persistence);
                    original.phase = ProjectionPhase::Effects;
                }
                ProjectionPhase::Effects => {
                    let owner = live.as_mut().expect("original live owner retained");
                    if original.effect.is_none() {
                        original.effect =
                            owner.channel.next_unprojected().map(|write| PendingEffect {
                                write,
                                phase: EffectPhase::Project,
                                result: None,
                            });
                    }
                    let Some(effect) = original.effect.as_mut() else {
                        original.phase = ProjectionPhase::Stream;
                        continue;
                    };
                    let write = &effect.write;
                    let sequence = write.effect.sequence;
                    match effect.phase {
                        EffectPhase::Project => {
                            if sequence <= *recovered_through {
                                owner.prepare_behind(services, id, write).await?;
                                original.effect = None;
                                continue;
                            }
                            owner.advance(services, id, write).await?;
                            effect.phase = EffectPhase::Billing;
                        }
                        EffectPhase::Billing => {
                            billing::record(
                                &services.performance,
                                &owner.thread.root_thread_id,
                                &write.effect,
                            )?;
                            original.newest_commit_at =
                                original.newest_commit_at.max(write.effect.committed_at);
                            effect.phase = EffectPhase::Result;
                        }
                        EffectPhase::Result => {
                            if let Some(turn) =
                                write.effect.turn.as_ref().filter(|turn| {
                                    turn.state != pl_core::thread::TurnState::Running
                                })
                            {
                                let result = Arc::new(
                                    turn_result(services, owner, &turn.turn_id, fences).await?,
                                );
                                if original
                                    .snapshot
                                    .turns
                                    .last()
                                    .is_some_and(|last| last.turn_id == turn.turn_id)
                                {
                                    original.summary_result = Some(result.clone());
                                }
                                effect.result = Some(result);
                                effect.phase = EffectPhase::Report;
                            } else {
                                original.effect = None;
                            }
                        }
                        EffectPhase::Report => {
                            let turn = write
                                .effect
                                .turn
                                .as_ref()
                                .expect("original terminal Turn retained");
                            let result = effect
                                .result
                                .as_ref()
                                .expect("original Turn result retained");
                            reports::publish_terminal(
                                services,
                                &owner.thread,
                                &original.snapshot,
                                turn,
                                sequence,
                                sequence > *recovered_through,
                                result,
                            )
                            .await?;
                            // prepare() already handed this write over. Retaining the phase until
                            // this acknowledgement is what prevents either losing or replaying it.
                            original.effect = None;
                        }
                    }
                }
                ProjectionPhase::Stream => {
                    let owner = live.as_mut().expect("original live owner retained");
                    owner.stream(&original.snapshot).await?;
                    owner.observe_storage(snapshot, persistence);
                    owner.publish_execution(&original.snapshot, &[]);
                    if !original.products {
                        let snapshot = original.snapshot.clone();
                        *pass = None;
                        return Ok(snapshot);
                    }
                    original.phase = ProjectionPhase::Product;
                }
                ProjectionPhase::Product => {
                    let mut product = product_association(services, id, fences).await?;
                    product.status = crate::studio::thread_projection::status(&original.snapshot);
                    product.updated_at = product.updated_at.max(original.newest_commit_at);
                    original.product = Some(product);
                    original.phase = ProjectionPhase::Summary;
                }
                ProjectionPhase::Summary => {
                    let owner = live.as_mut().expect("original live owner retained");
                    original.summary = if let Some(turn) = original
                        .snapshot
                        .turns
                        .last()
                        .filter(|turn| turn.state != pl_core::thread::TurnState::Running)
                    {
                        if original.summary_result.is_none() {
                            let result =
                                turn_result(services, owner, &turn.turn_id, fences).await?;
                            original.summary_result = Some(Arc::new(result));
                        }
                        original
                            .summary_result
                            .as_ref()
                            .and_then(|result| result.final_text())
                    } else {
                        None
                    };
                    original.phase = ProjectionPhase::Directory;
                }
                ProjectionPhase::Directory => {
                    directory::publish(
                        services,
                        original
                            .product
                            .as_ref()
                            .expect("original product retained")
                            .clone(),
                        &original.snapshot,
                        original.summary.clone(),
                    )
                    .await?;
                    let snapshot = original.snapshot.clone();
                    *pass = None;
                    return Ok(snapshot);
                }
            }
        }
    }
}

#[cfg(test)]
mod context_contract_tests {
    use super::super::thread_reads::context::ContextMaterial;
    use super::*;
    use facets::context::{ContextDelivery, DeliveryStep};
    use pl_protocol::studio::{ConfigProjectionStamp, ReadText, StudioError, StudioErrorCode};
    use pl_protocol::thread_facets::context::{ContextEvent, ContextFrame, CurrentContextPolicy};
    use pl_protocol::thread_facets::identity::{
        FeedClosedReason, MetricsIdentityRef, ThreadFacet, ThreadFacetStamp, ThreadObservationMode,
    };

    fn sources() -> Result<(
        Arc<facets::ThreadFacetSources>,
        super::super::read_scopes::ReadScopeRegistry,
    )> {
        let registry = super::super::read_scopes::ReadScopeRegistry::default();
        let reads = super::super::thread_reads::lifetime::ThreadReadRegistry::new(registry.clone());
        let ids = super::super::observation_ids::ObservationIds::new("context-contract".into());
        Ok((
            facets::ThreadFacetSources::new(&ids, &reads, "thread-context")?,
            registry,
        ))
    }

    fn runtime() -> Result<pl_protocol::ThreadRuntimeSnapshot> {
        let snapshot = ThreadSnapshot::default();
        Ok(crate::studio::thread_projection::project_runtime(
            "thread-context",
            &snapshot,
            1,
            &snapshot.usage_summary,
        )?)
    }

    fn policy() -> CurrentContextPolicy {
        CurrentContextPolicy {
            sources: ConfigProjectionStamp {
                settings_revision: 2,
                model_catalog_revision: 3,
                closing: false,
            },
            mode_revision: 4,
            route_revision: 5,
            context_window: Some(32_000),
            max_context_window: Some(32_000),
            input_token_limit: Some(27_904),
            auto_compact_limit: Some(27_904),
            unavailable: None,
            adjustment: None,
        }
    }

    fn sample(completion_tokens: u64) -> Arc<facets::metrics::MetricsSnapshot> {
        Arc::new(facets::metrics::MetricsSnapshot {
            stamp: ThreadFacetStamp {
                runtime_epoch: "context-contract".into(),
                incarnation: 1,
                facet: ThreadFacet::Metrics,
                revision: completion_tokens,
            },
            value: pl_protocol::thread_facets::metrics::MetricsValue {
                live: Some(pl_protocol::thread_facets::metrics::LiveTurnMetrics {
                    identity: MetricsIdentityRef { entry: 77 },
                    completion_tokens: Some(completion_tokens),
                    response_millis: Some(completion_tokens * 10),
                    state: pl_protocol::ThreadRuntimeUsageState::Live,
                    observation_sequence: completion_tokens,
                }),
                authoritative: None,
            },
            identities: Vec::new(),
        })
    }

    fn receive(delivery: &ContextDelivery) -> Result<ContextFrame> {
        let mut frame = None;
        delivery.send_next(|value| {
            frame = Some(value);
            Ok(())
        })?;
        frame.context("Context frame was not delivered")
    }

    #[tokio::test]
    async fn context_versions_track_context_not_speed_and_keep_frozen_usage_separate() -> Result<()>
    {
        let (facets, _registry) = sources()?;
        let mut runtime = runtime()?;
        runtime.usage.model_id = "frozen-model".into();
        runtime.usage.context_window = Some(8_000);
        runtime.usage.max_context_window = Some(16_000);
        runtime.usage.auto_compact_limit = Some(7_000);
        runtime.live_usage = Some(pl_protocol::ThreadRuntimeLiveUsage {
            turn_id: "turn-1".into(),
            attempt_id: "attempt-1".into(),
            completion_tokens: Some(10),
            response_millis: Some(100),
            latest_context_tokens: Some(200),
            state: pl_protocol::ThreadRuntimeUsageState::Live,
            observation_sequence: 10,
        });
        facets
            .context
            .observe(&runtime, Some(policy()), Some(sample(10)))?;
        let delivery = facets.context.subscribe(ThreadObservationMode::Live)?;
        delivery.claim()?;
        let mut attempted = None;
        assert!(
            delivery
                .send_next(|frame| {
                    attempted = Some(frame);
                    Err(StudioError::new(
                        StudioErrorCode::Unavailable,
                        "synthetic failed post",
                        false,
                    ))
                })
                .is_err()
        );
        let Some(ContextFrame::Data { event, .. }) = attempted else {
            anyhow::bail!("Context baseline was not attempted");
        };
        let ContextEvent::Baseline {
            stamp: origin,
            value,
            ..
        } = *event
        else {
            anyhow::bail!("Context baseline was not attempted");
        };
        assert!(facets.context.material_at(value.details, &origin).is_err());
        assert_eq!(
            receive(&delivery)?,
            ContextFrame::Data {
                delivery_sequence: 1,
                event: Box::new(ContextEvent::Baseline {
                    identity: delivery.identity(),
                    stamp: origin.clone(),
                    value: value.clone()
                })
            }
        );
        assert_eq!(origin.facet, ThreadFacet::Context);
        assert_eq!(
            value.usage.as_ref().and_then(|usage| usage.context_window),
            Some(8_000)
        );
        assert_eq!(
            value
                .current_policy
                .as_ref()
                .and_then(|policy| policy.context_window),
            Some(32_000)
        );
        assert_eq!(
            value.live_context.as_ref().map(|live| live.identity.entry),
            Some(77)
        );

        runtime.live_usage.as_mut().unwrap().completion_tokens = Some(20);
        runtime.live_usage.as_mut().unwrap().response_millis = Some(200);
        runtime.live_usage.as_mut().unwrap().observation_sequence = 20;
        runtime.usage.updated_at += 10;
        facets
            .context
            .observe(&runtime, Some(policy()), Some(sample(20)))?;
        assert!(matches!(
            delivery.send_next(|_| panic!("speed-only sample advanced Context"))?,
            DeliveryStep::Waiting
        ));

        let mut next_policy = policy();
        next_policy.context_window = Some(64_000);
        facets
            .context
            .observe(&runtime, Some(next_policy.clone()), Some(sample(20)))?;
        let ContextFrame::Data {
            delivery_sequence: 2,
            event,
        } = receive(&delivery)?
        else {
            anyhow::bail!("current policy did not produce Context Replace");
        };
        let ContextEvent::Replace {
            stamp: next_origin,
            value: next,
        } = *event
        else {
            anyhow::bail!("current policy did not produce Context Replace");
        };
        assert_eq!(next_origin.revision, origin.revision + 1);
        assert_eq!(next.details, value.details);
        assert_eq!(next.usage, value.usage);
        assert!(
            facets
                .context
                .material_at(value.details, &next_origin)
                .is_ok()
        );
        runtime.live_usage.as_mut().unwrap().latest_context_tokens = Some(300);
        facets
            .context
            .observe(&runtime, Some(next_policy), Some(sample(20)))?;
        assert!(matches!(
            delivery.send_next(|_| panic!("third Context frame exceeded ACK window"))?,
            DeliveryStep::Waiting
        ));
        assert_eq!(
            delivery.ack(3).err().map(|error| error.code),
            Some(StudioErrorCode::Protocol)
        );
        delivery.ack(1)?;
        let ContextFrame::Data {
            delivery_sequence: 3,
            event,
        } = receive(&delivery)?
        else {
            anyhow::bail!("expected a third Context data frame");
        };
        assert!(matches!(
            *event,
            ContextEvent::Replace {
                value: pl_protocol::thread_facets::context::ContextValue {
                    live_context: Some(pl_protocol::thread_facets::context::LiveContext {
                        latest_context_tokens: Some(300),
                        ..
                    }),
                    ..
                },
                ..
            }
        ));
        delivery.ack(2)?;
        delivery.ack(2)?;
        let mut wrong = next_origin.clone();
        wrong.facet = ThreadFacet::Configuration;
        assert!(facets.context.material_at(value.details, &wrong).is_err());
        facets.close(FeedClosedReason::OwnerReplaced);
        assert_eq!(
            receive(&delivery)?,
            ContextFrame::Closed {
                identity: delivery.identity(),
                reason: FeedClosedReason::OwnerReplaced
            }
        );
        delivery.close();
        Ok(())
    }

    #[tokio::test]
    async fn context_details_pin_original_costs_and_share_thread_read_budget() -> Result<()> {
        let (facets, _registry) = sources()?;
        let mut runtime = runtime()?;
        let currency = "币🦀\n\"".repeat(20_000);
        runtime.usage.estimated_costs = vec![pl_protocol::RuntimeCostAmount {
            currency: currency.clone(),
            amount: 1.25,
        }];
        runtime.usage.estimated_cache_savings = vec![pl_protocol::RuntimeCostAmount {
            currency: "USD".into(),
            amount: 0.5,
        }];
        facets.context.observe(&runtime, Some(policy()), None)?;
        let delivery = facets.context.subscribe(ThreadObservationMode::Cold)?;
        delivery.claim()?;
        let ContextFrame::Data { event, .. } = receive(&delivery)? else {
            anyhow::bail!("missing Context baseline");
        };
        let ContextEvent::Baseline {
            stamp: origin,
            value,
            ..
        } = *event
        else {
            anyhow::bail!("missing Context baseline");
        };
        let source = facets.context.material_at(value.details, &origin)?;
        let residency = super::super::residency::ThreadResidency::new();
        let mut scopes = Vec::new();
        for _ in 0..8 {
            let lease = ThreadFacetLease {
                owner: std::sync::Weak::new(),
                thread_id: "thread-context".into(),
                facets: facets.clone(),
                mode: ThreadObservationMode::Live,
            };
            scopes.push(lease.open_read(
                source.revision,
                |identity| ContextMaterial::new(identity, source.clone()),
                residency.pin_many(["thread-context".into()]),
            )?);
        }
        let lease = ThreadFacetLease {
            owner: std::sync::Weak::new(),
            thread_id: "thread-context".into(),
            facets: facets.clone(),
            mode: ThreadObservationMode::Live,
        };
        assert_eq!(
            lease
                .open_read(
                    source.revision,
                    |_| (),
                    residency.pin_many(["thread-context".into()])
                )
                .err()
                .map(|error| error.code),
            Some(StudioErrorCode::Overloaded)
        );
        let (owner, pinned) = &scopes[0];
        let header = pinned.read(|material| material.as_ref().map_err(Clone::clone)?.header())?;
        assert_eq!(header.scope, owner.identity());
        assert_eq!(
            header.frozen_model_id, None,
            "current policy cannot fill an unknown frozen model"
        );
        let page = pinned.read(|material| material.as_ref().map_err(Clone::clone)?.costs(0, 1))?;
        assert_eq!(page.scope, owner.identity());
        assert_eq!(page.items[0].amount, 1.25);
        let ReadText::Deferred {
            field_id,
            utf8_bytes,
        } = page.items[0].currency
        else {
            anyhow::bail!("large currency was not deferred");
        };
        assert_eq!(utf8_bytes, currency.len() as u64);
        let savings =
            pinned.read(|material| material.as_ref().map_err(Clone::clone)?.cache_savings(0, 1))?;
        assert_eq!(
            savings.items[0].currency,
            ReadText::Inline { text: "USD".into() }
        );
        assert_eq!(savings.items[0].amount, 0.5);
        runtime.usage.estimated_costs[0].amount = 7.5;
        facets.context.observe(&runtime, Some(policy()), None)?;
        let ContextFrame::Data { event, .. } = receive(&delivery)? else {
            anyhow::bail!("cost change did not replace details");
        };
        let ContextEvent::Replace {
            stamp: next_origin,
            value: next,
        } = *event
        else {
            anyhow::bail!("cost change did not replace details");
        };
        assert_ne!(value.details, next.details);
        assert!(facets.context.material_at(next.details, &origin).is_err());
        assert!(
            facets
                .context
                .material_at(value.details, &next_origin)
                .is_err()
        );
        assert!(
            pinned
                .read(|material| material
                    .as_ref()
                    .map_err(Clone::clone)?
                    .text(field_id, 1, 65536))
                .is_err()
        );
        assert!(
            pinned
                .read(|material| material
                    .as_ref()
                    .map_err(Clone::clone)?
                    .text(field_id, 0, 262145))
                .is_err()
        );
        delivery.close();
        let mut text = String::new();
        let mut offset = 0;
        loop {
            let chunk = pinned.read(|material| {
                material
                    .as_ref()
                    .map_err(Clone::clone)?
                    .text(field_id, offset, 65536)
            })?;
            assert_eq!(chunk.offset, offset);
            assert!(chunk.text.len() <= 65536);
            assert!(super::super::read_budget::json_bytes(&chunk)? <= 256 * 1024);
            text.push_str(&chunk.text);
            match chunk.next_offset {
                Some(next) => {
                    assert!(next > offset);
                    offset = next;
                }
                None => break,
            }
        }
        assert_eq!(text, currency);
        assert_eq!(
            pinned
                .read(|material| material.as_ref().map_err(Clone::clone)?.costs(0, 1))?
                .items[0]
                .amount,
            1.25
        );
        assert!(matches!(
            owner.close().await.outcome,
            pl_protocol::studio::FeedCloseOutcome::Clean
        ));
        assert!(
            pinned
                .read(|material| material.as_ref().map_err(Clone::clone)?.header())
                .is_err()
        );
        facets.close(FeedClosedReason::Requested);
        assert!(facets.reads.close().await.is_empty());
        Ok(())
    }

    #[tokio::test]
    async fn context_terminal_does_not_wait_for_full_pending_or_ack_windows() -> Result<()> {
        let (facets, _registry) = sources()?;
        let mut runtime = runtime()?;
        facets.context.observe(&runtime, None, None)?;
        let delivery = facets.context.subscribe(ThreadObservationMode::Live)?;
        delivery.claim()?;
        receive(&delivery)?;
        for tokens in 1..=66 {
            runtime.usage.latest_context_tokens = tokens;
            facets.context.observe(&runtime, None, None)?;
            if tokens == 1 {
                receive(&delivery)?;
            }
        }
        assert!(matches!(
            receive(&delivery)?,
            ContextFrame::ResyncRequired {
                reason: pl_protocol::thread_facets::identity::ResyncReason::ReliableQueueFull,
                ..
            }
        ));
        delivery.ack(2)?;
        assert!(matches!(
            delivery.send_next(|_| panic!("Context terminal was sent twice"))?,
            DeliveryStep::Terminal
        ));
        let closing = facets.context.subscribe(ThreadObservationMode::Live)?;
        closing.claim()?;
        receive(&closing)?;
        runtime.usage.latest_context_tokens += 1;
        facets.context.observe(&runtime, None, None)?;
        receive(&closing)?;
        facets.close(FeedClosedReason::OwnerReplaced);
        closing.ready().await;
        assert_eq!(
            receive(&closing)?,
            ContextFrame::Closed {
                identity: closing.identity(),
                reason: FeedClosedReason::OwnerReplaced
            }
        );
        closing.close();
        delivery.close();
        Ok(())
    }
}

#[cfg(test)]
mod configuration_contract_tests {
    use super::super::thread_reads::configuration::ConfigurationMaterial;
    use super::*;
    use facets::configuration::{ConfigurationDelivery, DeliveryStep};
    use pl_protocol::studio::{ConfigProjectionStamp, ReadText, StudioError, StudioErrorCode};
    use pl_protocol::thread_facets::configuration::{ConfigurationEvent, ConfigurationFrame};
    use pl_protocol::thread_facets::identity::{
        FeedClosedReason, ThreadFacet, ThreadObservationMode,
    };

    fn sources() -> Result<(
        Arc<facets::ThreadFacetSources>,
        super::super::read_scopes::ReadScopeRegistry,
    )> {
        let registry = super::super::read_scopes::ReadScopeRegistry::default();
        let reads = super::super::thread_reads::lifetime::ThreadReadRegistry::new(registry.clone());
        let ids =
            super::super::observation_ids::ObservationIds::new("configuration-contract".into());
        Ok((
            facets::ThreadFacetSources::new(&ids, &reads, "thread-original")?,
            registry,
        ))
    }

    fn runtime() -> Result<pl_protocol::ThreadRuntimeSnapshot> {
        let snapshot = ThreadSnapshot::default();
        let mut runtime = crate::studio::thread_projection::project_runtime(
            "thread-original",
            &snapshot,
            1,
            &snapshot.usage_summary,
        )?;
        runtime.model_route = Some(pl_protocol::ThreadModelRouteSnapshot {
            bot_id: Some("original-bot".into()),
            account_id: "original-account".into(),
            model_id: "original-model".into(),
            effort: Some("high".into()),
            revision: 7,
            available: true,
            unavailable_reason: None,
        });
        runtime.active_skills = vec!["original-skill".into()];
        Ok(runtime)
    }

    fn stamp(revision: u64) -> ConfigProjectionStamp {
        ConfigProjectionStamp {
            settings_revision: revision,
            model_catalog_revision: 2,
            closing: false,
        }
    }

    fn receive(delivery: &ConfigurationDelivery) -> Result<ConfigurationFrame> {
        let mut received = None;
        delivery.send_next(|frame| {
            received = Some(frame);
            Ok(())
        })?;
        received.context("configuration frame was not delivered")
    }

    #[tokio::test]
    async fn configuration_delivery_exposes_only_sent_refs_and_retires_the_acked_prefix()
    -> Result<()> {
        let (facets, _registry) = sources()?;
        let projection = &facets.configuration;
        let mut runtime = runtime()?;
        projection.observe(&runtime, stamp(3), 4, Some(5))?;
        let delivery = projection.subscribe(ThreadObservationMode::Live)?;
        delivery.claim()?;
        assert_eq!(
            delivery.claim().err().map(|error| error.code),
            Some(StudioErrorCode::Conflict)
        );
        let mut attempted = None;
        assert!(
            delivery
                .send_next(|frame| {
                    attempted = Some(frame);
                    Err(StudioError::new(
                        StudioErrorCode::Unavailable,
                        "synthetic failed post",
                        false,
                    ))
                })
                .is_err()
        );
        let Some(ConfigurationFrame::Data {
            event:
                ConfigurationEvent::Baseline {
                    stamp: origin,
                    value,
                    ..
                },
            ..
        }) = attempted
        else {
            anyhow::bail!("first attempt was not a baseline");
        };
        assert!(projection.material_at(value.details, &origin).is_err());
        assert_eq!(
            receive(&delivery)?,
            ConfigurationFrame::Data {
                delivery_sequence: 1,
                event: ConfigurationEvent::Baseline {
                    identity: delivery.identity(),
                    stamp: origin.clone(),
                    value: value.clone()
                }
            }
        );
        assert_eq!(origin.facet, ThreadFacet::Configuration);
        assert_eq!(origin.revision, 0);
        assert_eq!(
            projection.material_at(value.details, &origin)?.route,
            runtime.model_route
        );
        projection.observe(&runtime, stamp(3), 4, Some(5))?;
        assert!(matches!(
            delivery.send_next(|_| panic!("unchanged configuration was published"))?,
            DeliveryStep::Waiting
        ));

        runtime.model_route.as_mut().unwrap().bot_id = Some("replacement-bot".into());
        projection.observe(&runtime, stamp(4), 4, Some(5))?;
        let ConfigurationFrame::Data {
            delivery_sequence: 2,
            event:
                ConfigurationEvent::Replace {
                    stamp: next_origin,
                    value: next,
                },
        } = receive(&delivery)?
        else {
            anyhow::bail!("configuration update was not the second Replace");
        };
        assert_eq!(next_origin.revision, 1);
        assert_eq!(next_origin.runtime_epoch, origin.runtime_epoch);
        assert_eq!(next_origin.incarnation, origin.incarnation);
        assert!(projection.material_at(next.details, &origin).is_err());
        assert!(projection.material_at(value.details, &next_origin).is_err());
        let mut wrong = origin.clone();
        wrong.facet = ThreadFacet::Authoring;
        assert!(projection.material_at(value.details, &wrong).is_err());
        wrong = origin.clone();
        wrong.incarnation += 1;
        assert!(projection.material_at(value.details, &wrong).is_err());

        projection.observe(&runtime, stamp(5), 4, Some(5))?;
        assert!(matches!(
            delivery.send_next(|_| panic!("third frame exceeded the ACK window"))?,
            DeliveryStep::Waiting
        ));
        assert_eq!(
            delivery.ack(3).err().map(|error| error.code),
            Some(StudioErrorCode::Protocol)
        );
        delivery.ack(0)?;
        assert!(projection.material_at(value.details, &origin).is_ok());
        delivery.ack(1)?;
        delivery.ack(1)?;
        assert!(projection.material_at(value.details, &origin).is_err());
        assert!(matches!(
            receive(&delivery)?,
            ConfigurationFrame::Data {
                delivery_sequence: 3,
                event: ConfigurationEvent::Replace { .. }
            }
        ));
        assert!(projection.material_at(next.details, &next_origin).is_ok());
        delivery.close();
        assert!(projection.material_at(next.details, &next_origin).is_err());
        Ok(())
    }

    #[tokio::test]
    async fn configuration_details_share_thread_scope_budget_and_chunk_original_text() -> Result<()>
    {
        let (facets, _registry) = sources()?;
        let mut runtime = runtime()?;
        let original = "机器人🦀\n\"".repeat(20_000);
        runtime.model_route.as_mut().unwrap().bot_id = Some(original.clone());
        runtime.active_skills.push("skill🦀".repeat(2_000));
        facets.configuration.observe(&runtime, stamp(3), 4, None)?;
        let delivery = facets
            .configuration
            .subscribe(ThreadObservationMode::Cold)?;
        delivery.claim()?;
        let ConfigurationFrame::Data {
            event:
                ConfigurationEvent::Baseline {
                    stamp: origin,
                    value,
                    ..
                },
            ..
        } = receive(&delivery)?
        else {
            anyhow::bail!("missing configuration baseline");
        };
        let source = facets.configuration.material_at(value.details, &origin)?;
        let residency = super::super::residency::ThreadResidency::new();
        let mut scopes = Vec::new();
        for _ in 0..8 {
            let lease = ThreadFacetLease {
                owner: std::sync::Weak::new(),
                thread_id: "thread-original".into(),
                facets: facets.clone(),
                mode: ThreadObservationMode::Live,
            };
            scopes.push(lease.open_read(
                source.revision,
                |identity| ConfigurationMaterial::new(identity, source.clone()),
                residency.pin_many(["thread-original".into()]),
            )?);
        }
        let lease = ThreadFacetLease {
            owner: std::sync::Weak::new(),
            thread_id: "thread-original".into(),
            facets: facets.clone(),
            mode: ThreadObservationMode::Live,
        };
        let refused = lease.open_read(
            source.revision,
            |_| (),
            residency.pin_many(["thread-original".into()]),
        );
        assert_eq!(
            refused.err().map(|error| error.code),
            Some(StudioErrorCode::Overloaded)
        );

        let (owner, pinned) = &scopes[0];
        let header = pinned.read(|material| material.as_ref().map_err(Clone::clone)?.header())?;
        assert_eq!(header.scope, owner.identity());
        let Some(route) = header.route else {
            anyhow::bail!("missing original route");
        };
        let Some(ReadText::Deferred {
            field_id,
            utf8_bytes,
        }) = route.bot_id
        else {
            anyhow::bail!("long bot ID was not deferred");
        };
        assert_eq!(utf8_bytes, original.len() as u64);
        assert_eq!(
            route.account_id,
            ReadText::Inline {
                text: "original-account".into()
            }
        );
        let skills =
            pinned.read(|material| material.as_ref().map_err(Clone::clone)?.active_skills(1, 1))?;
        assert_eq!(skills.total, 2);
        assert!(matches!(skills.items[0].name, ReadText::Deferred { .. }));
        assert!(
            pinned
                .read(|material| material
                    .as_ref()
                    .map_err(Clone::clone)?
                    .text(field_id, 1, 65536))
                .is_err()
        );
        assert!(
            pinned
                .read(|material| material
                    .as_ref()
                    .map_err(Clone::clone)?
                    .text(field_id, 0, 262145))
                .is_err()
        );

        delivery.close();
        let mut reconstructed = String::new();
        let mut offset = 0;
        loop {
            let chunk = pinned.read(|material| {
                material
                    .as_ref()
                    .map_err(Clone::clone)?
                    .text(field_id, offset, 65536)
            })?;
            assert_eq!(chunk.field_id, field_id);
            assert_eq!(chunk.offset, offset);
            assert!(chunk.text.len() <= 65536);
            assert!(super::super::read_budget::json_bytes(&chunk)? <= 256 * 1024);
            reconstructed.push_str(&chunk.text);
            match chunk.next_offset {
                Some(next) => {
                    assert!(next > offset);
                    offset = next;
                }
                None => break,
            }
        }
        assert_eq!(reconstructed, original);
        assert!(matches!(
            owner.close().await.outcome,
            pl_protocol::studio::FeedCloseOutcome::Clean
        ));
        assert!(
            pinned
                .read(|material| material.as_ref().map_err(Clone::clone)?.header())
                .is_err()
        );
        facets.close(FeedClosedReason::OwnerReplaced);
        assert!(facets.reads.close().await.is_empty());
        assert!(
            facets
                .configuration
                .material_at(
                    pl_protocol::thread_facets::identity::ConfigurationReadRef {
                        entry: 1,
                        revision: 0
                    },
                    &origin
                )
                .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn configuration_resync_and_close_bypass_a_full_ack_window() -> Result<()> {
        let (facets, _registry) = sources()?;
        let runtime = runtime()?;
        facets.configuration.observe(&runtime, stamp(0), 0, None)?;
        let delivery = facets
            .configuration
            .subscribe(ThreadObservationMode::Live)?;
        delivery.claim()?;
        receive(&delivery)?;
        facets.configuration.observe(&runtime, stamp(1), 0, None)?;
        receive(&delivery)?;
        for revision in 2..=66 {
            facets
                .configuration
                .observe(&runtime, stamp(revision), 0, None)?;
        }
        assert!(matches!(
            receive(&delivery)?,
            ConfigurationFrame::ResyncRequired {
                reason: pl_protocol::thread_facets::identity::ResyncReason::ReliableQueueFull,
                ..
            }
        ));
        delivery.ack(2)?;
        assert!(matches!(
            delivery.send_next(|_| panic!("terminal was sent twice"))?,
            DeliveryStep::Terminal
        ));

        let closing = facets
            .configuration
            .subscribe(ThreadObservationMode::Live)?;
        closing.claim()?;
        receive(&closing)?;
        facets.configuration.observe(&runtime, stamp(67), 0, None)?;
        receive(&closing)?;
        facets.close(FeedClosedReason::OwnerReplaced);
        closing.ready().await;
        assert_eq!(
            receive(&closing)?,
            ConfigurationFrame::Closed {
                identity: closing.identity(),
                reason: FeedClosedReason::OwnerReplaced
            }
        );
        assert!(
            facets
                .configuration
                .subscribe(ThreadObservationMode::Live)
                .is_err()
        );
        closing.close();
        delivery.close();
        Ok(())
    }
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;
    use crate::studio::storage::history::{EffectCommit, FactReceiptWrite};
    use crate::studio::storage::thread_writer::ThreadStorageSink;
    use pl_core::{
        context::OpaquePayload,
        thread::{
            ThreadCheckpoint, ThreadEffectBatch, TurnRecord, TurnState,
            cold::ColdStore,
            input::{InputChange, InputRecord, InputState, ThreadInput},
        },
    };
    use pl_protocol::{ThreadItem, ThreadItemState};
    use std::time::Duration;

    #[tokio::test]
    async fn recovery_projection_loads_references_pruned_from_the_current_snapshot() -> Result<()> {
        recovery_projection(false).await?;
        recovery_projection(true).await
    }

    /// 普通问答的交互构造：问题来自生产者格式，回答用真实的 `pl.studio.user-answer` 载荷。
    fn qa_record(
        call_id: &str,
        revision: u64,
        state: pl_core::thread::interactions::InteractionState,
    ) -> Result<pl_core::thread::interactions::InteractionRecord> {
        let questions = vec![pl_protocol::UserQuestion {
            id: "provider".into(),
            header: "Provider".into(),
            question: "Which provider should the next release verify?".into(),
            is_other: true,
            is_secret: false,
            options: None,
        }];
        Ok(pl_core::thread::interactions::InteractionRecord {
            created_at: 10,
            updated_at: 10 + i64::try_from(revision)?,
            continuation_id: None,
            request: pl_core::thread::interactions::InteractionRequest {
                id: pl_core::tool::opaque::tool_interaction_id(call_id),
                turn_id: "turn-qa".into(),
                payload: OpaquePayload::new(
                    "pl.tool.user-input",
                    1,
                    serde_json::to_string(&questions)?,
                )?,
            },
            revision,
            state,
            extension_mutations: vec![],
        })
    }

    async fn register_test_thread(store: &StudioStore, thread: &pl_protocol::Thread) -> Result<()> {
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: thread.project_id.clone(),
                name: "Test".into(),
                path: "/tmp/project-test".into(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        delta.thread_upserts = vec![thread.clone()];
        store.persist_directory_summaries(&delta).await
    }

    fn bound_thread(thread_id: &str) -> pl_protocol::Thread {
        let mut thread = pl_protocol::Thread::placeholder(thread_id);
        thread.project_id = "project-test".into();
        thread.agent_path = thread_id.to_owned();
        thread.root_thread_id = thread_id.to_owned();
        thread
    }

    /// 跨重开的普通问答：回答 effect 只带交互与隐藏 continuation。
    ///
    /// 回答时那条调用已经不在 Thread 状态里（工具成功的 Task 已是终态、Turn 已结束），新建的
    /// LiveProjection 也没有它的正文。owner 必须按 identity 从可靠 history 补读那一条再投影，
    /// 否则这份被采纳的回答会以 MissingDurableToolCall 失败、永不落盘。
    #[tokio::test]
    async fn a_question_answered_after_a_restart_is_projected_and_saved() -> Result<()> {
        use pl_core::thread::interactions::{InteractionResponse, InteractionState};

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("qa-restart");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let history = store.history(&thread.id).await?;
        let call_id = "call-restart";
        let tool_id = crate::studio::thread_projection::order::tool_id(call_id);

        // 1) 提问在重启之前就已落盘：工具条目（尚未带问答）+ pending 交互回执。
        let pending = qa_record(call_id, 1, InteractionState::Pending)?;
        let question = ThreadItem::new(
            tool_id.clone(),
            thread.id.clone(),
            "turn-qa".into(),
            1,
            2,
            10,
            11,
            ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    call_id.into(),
                    "request_user_input".into(),
                    "{\"questions\":[]}".into(),
                ),
                pl_protocol::ThreadToolState::Running(pl_protocol::RunningThreadTool::new(
                    String::new(),
                )),
            )),
        );
        history
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&question),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[FactReceiptWrite {
                        item_id: crate::studio::thread_projection::order::receipt_id(
                            "interaction",
                            &pending.request.id,
                        ),
                        revision: pending.revision,
                        kind: "interaction",
                        payload: serde_json::to_string(&pending)?,
                    }],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;

        // 2) 重启：新投影没有任何驻留正文，Turn/Task 都不在（空且已剪枝的状态）。
        let mut projection = LiveProjection::new();
        let answered = qa_record(
            call_id,
            2,
            InteractionState::Resolved(InteractionResponse {
                payload: OpaquePayload::new(
                    "pl.studio.user-answer",
                    1,
                    serde_json::to_string(
                        &serde_json::json!({"answers": {"provider": {"answers": ["anthropic"]}}}),
                    )?,
                )?,
                context: vec![],
            }),
        )?;
        let answer_effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 2,
            interactions: [answered].into(),
            ..Default::default()
        };
        let answered_state = ThreadSnapshot {
            commit_sequence: 2,
            ..Default::default()
        };

        // 没有补读时这张投影无法完成这份回答：这是缺 body 的真实失败，而不是可接受的限制。
        assert!(
            projection
                .advance(&chat, &thread, &answer_effect, &answered_state)
                .is_err()
        );
        // owner 按 identity 补读那一条 durable 正文后，同一次投影就能完成。
        crate::studio::thread_projection::seed_interaction_targets(
            &mut projection,
            &thread.id,
            &history,
            &answer_effect,
        )
        .await?;
        let (_, prepared) = projection.advance(&chat, &thread, &answer_effect, &answered_state)?;

        // 3) 走真实 writer：回答必须落盘在原条目上，身份/顺序/创建时间不变。
        let answer_write = ThreadWrite {
            effect: Arc::new(answer_effect),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 2, answered_state),
            output_claim: None,
        };
        sink.admit(&thread.id, answer_write)?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 2)).await??;
        let saved = history
            .existing_items([tool_id.clone()])
            .await?
            .remove(&tool_id)
            .context("answered question item")?;
        assert_eq!(saved.ordinal, 1);
        assert_eq!(saved.created_at, 10);
        let user_input = saved
            .tool()
            .and_then(|tool| tool.user_input())
            .context("saved Q&A")?;
        assert_eq!(user_input.answers()[0].answers(), ["anthropic"]);
        Ok(())
    }

    /// 当前压缩回执必须同时穿过计量、时间线与真实 writer，不能在投影阶段阻塞保存。
    #[tokio::test]
    async fn a_current_compaction_receipt_is_projected_and_saved() -> Result<()> {
        use pl_core::thread::{
            ContextReplacement, ContextReplacementReason,
            extensions::{ExtensionChange, ExtensionRecord},
        };
        use pl_model::{
            protocol::{ProtocolKind, WireApi},
            runtime::ModelCallBinding,
        };

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("compaction-save");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let receipt = crate::compaction::CompactionReceipt {
            inference_id: "compaction-1".into(),
            binding: ModelCallBinding {
                account_id: "account".into(),
                model_id: "model".into(),
                protocol: ProtocolKind::OpenAi,
                wire_api: WireApi::Responses,
                isolation: thread.id.clone(),
                purpose: "compaction".into(),
                context_window: Some(100_000),
                max_context_window: Some(100_000),
                auto_compact_limit: Some(80_000),
            },
            reasoning_effort: None,
            context_window: Some(100_000),
            turn_id: "pruned-turn".into(),
            accounting: Default::default(),
            model_observation: None,
            implementation: Some("native".into()),
            error: None,
        };
        let extension = ExtensionRecord {
            revision: 1,
            payload: OpaquePayload::new(
                "pl.studio.compaction",
                2,
                serde_json::to_string(&receipt)?,
            )?,
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            extension_sequence: 1,
            extensions: [(crate::compaction::LATEST_RECEIPT.into(), extension.clone())].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            extensions: [ExtensionChange::Put {
                id: crate::compaction::LATEST_RECEIPT.into(),
                record: extension,
            }]
            .into(),
            replacements: [ContextReplacement {
                reason: ContextReplacementReason::Compaction,
                previous: Default::default(),
                current: state.context.clone(),
                previous_private_context: None,
            }]
            .into(),
            ..Default::default()
        };
        let mut usage = Default::default();
        crate::studio::thread_projection::fold_effect_accounting(&mut usage, &effect)?;
        assert_eq!(usage.inference_count, 1);
        let mut projection = LiveProjection::new();
        let (_, prepared) = projection.advance(&chat, &thread, &effect, &state)?;
        let write = ThreadWrite {
            effect: Arc::new(effect),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 1, state),
            output_claim: None,
        };
        sink.admit(&thread.id, write)?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
        let history = store.history(&thread.id).await?;
        let items = history.items_for_turn(&receipt.turn_id).await?;
        assert_eq!(items.len(), 1);
        let saved = &items[0];
        assert_eq!(saved.turn_id, receipt.turn_id);
        assert!(matches!(
            saved.state(),
            ThreadItemState::ContextCompaction(_)
        ));
        Ok(())
    }

    async fn recovery_projection(delayed_admission: bool) -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("recovered-hidden-input");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let input_id = "interaction:approved:continuation";
        let turn = TurnRecord {
            input_id: Some(input_id.into()),
            turn_id: "interrupted-turn".into(),
            state: TurnState::Running,
            model_steps: 0,
            elapsed_ms: None,
        };
        let input = InputRecord {
            input: ThreadInput {
                id: input_id.into(),
                payload: OpaquePayload::new(
                    "pl.studio.interaction-continuation",
                    1,
                    r#"{"interactionId":"approved","presentation":"hidden"}"#,
                )?,
                context: Vec::new(),
            },
            accepted_sequence: 1,
            ordinal: 1,
            revision: 1,
            delivery: Default::default(),
            state: InputState::Consumed {
                turn_id: turn.turn_id.clone(),
                attempt_id: "attempt".into(),
            },
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            inputs: Arc::from([input.clone()]),
            turns: Arc::from([turn.clone()]),
            ..Default::default()
        };
        let write = ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 1,
                committed_at: 1,
                inputs: Arc::from([InputChange::Accepted(input)]),
                turn: Some(turn.clone()),
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 1, state),
            output_claim: None,
        };
        sink.admit(&thread.id, write.clone())?;
        let mut projection = LiveProjection::new();
        let (_, prepared) =
            projection.advance(&chat, &thread, &write.effect, &write.checkpoint.state)?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
        drop(projection);

        let interrupted = TurnRecord {
            state: TurnState::Interrupted,
            ..turn
        };
        let state = ThreadSnapshot {
            commit_sequence: 2,
            turns: Arc::from([interrupted.clone()]),
            ..Default::default()
        };
        let recovery = ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 2,
                committed_at: 2,
                turn: Some(interrupted.clone()),
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 2, state),
            output_claim: None,
        };
        let current = recovery.checkpoint.clone().pruned().state;
        assert!(current.turns.is_empty());
        // Admission can be delayed by storage pressure until after observer installation.
        if !delayed_admission {
            sink.admit(&thread.id, recovery.clone())?;
        }
        let retained = if delayed_admission {
            assert!(channel.next_unprojected().is_none());
            vec![recovery.effect.clone()]
        } else {
            Vec::new()
        };
        let (items, hidden) = cold_seed(&store, &thread, &current, &channel, &retained).await?;
        let mut restored = LiveProjection::new();
        restored.seed(items, hidden);
        restored.stream(&chat, &thread, &current, 2).await?;
        if delayed_admission {
            sink.admit(&thread.id, recovery.clone())?;
        }
        let prepared = restored.project_committed(
            &chat,
            &thread,
            &recovery.effect,
            &recovery.checkpoint.state,
        )?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 2)).await??;
        let history = store.history(&thread.id).await?;
        assert_eq!(history.watermark().await?, 2);
        assert!(history.existing_items([input_id.into()]).await?.is_empty());
        assert!(
            history
                .hidden_input_identities([input_id.into()])
                .await?
                .contains(input_id)
        );
        let saved = history
            .newest_terminal_turn()
            .await?
            .context("saved interrupted turn")?;
        assert_eq!(saved.id, interrupted.turn_id);
        assert!(matches!(saved.state, pl_protocol::TurnState::Cancelled(_)));
        Ok(())
    }
}
