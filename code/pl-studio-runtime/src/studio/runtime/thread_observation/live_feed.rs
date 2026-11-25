//! Bounded State delivery and retained latest cuts.

use super::publication::{ConversationRegistration, ConversationSource};
use super::worker::Progress;
use super::{publication, state_resources};
use crate::studio::thread_projection::LiveEvent;
use anyhow::Result;
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, watch};

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
pub(in crate::studio::runtime) struct RuntimeStateCut {
    pub(in crate::studio::runtime) observation_revision: u64,
    pub(in crate::studio::runtime) catalog_revision: u64,
    pub(in crate::studio::runtime) runtime: Arc<crate::ThreadRuntimeSnapshot>,
    pub(in crate::studio::runtime) model_route: Option<crate::ThreadModelRouteSnapshot>,
}

#[derive(Clone)]
pub(in crate::studio::runtime) struct StateActivityCut {
    pub(in crate::studio::runtime) observation_revision: u64,
    pub(in crate::studio::runtime) activity: Option<Arc<crate::ThreadActivity>>,
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
    pub(in crate::studio::runtime) fn new(
        receiver: broadcast::Receiver<ThreadLiveEvent>,
        closed: tokio_util::sync::CancellationToken,
    ) -> Self {
        Self { receiver, closed }
    }

    pub(in crate::studio::runtime) fn is_closed(&self) -> bool {
        self.closed.is_cancelled() || (self.receiver.is_closed() && self.receiver.is_empty())
    }

    pub(in crate::studio::runtime) async fn recv(
        &mut self,
    ) -> Result<ThreadLiveEvent, broadcast::error::RecvError> {
        // The owner can retain the Sender while draining storage. Revocation must wake a parked
        // reader and win over buffered frames so neither consumer delivers after owner closure.
        tokio::select! { biased;
            _ = self.closed.cancelled() => Err(broadcast::error::RecvError::Closed),
            result = self.receiver.recv() => result,
        }
    }

    pub(in crate::studio::runtime) fn try_recv(
        &mut self,
    ) -> Result<ThreadLiveEvent, broadcast::error::TryRecvError> {
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

    pub(in crate::studio::runtime) fn is_delivery_closed(&self) -> bool {
        self.delivery_closed.is_cancelled()
    }

    pub(in crate::studio::runtime) async fn delivery_closed(&self) {
        self.delivery_closed.cancelled().await;
    }

    pub(super) fn close_delivery(&self) {
        self.delivery_closed.cancel();
    }

    pub(super) fn publish_conversation(
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

    pub(super) fn publish_business_refs(
        &self,
        sequence: u64,
        references: crate::ThreadBusinessRefs,
    ) {
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

    pub(in crate::studio::runtime) fn new(
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

    pub(in crate::studio::runtime) fn conversation(&self) -> ConversationRegistration {
        self.publication().capture(self.owner_progress.clone())
    }
    pub(in crate::studio::runtime) fn current_revision(&self) -> u64 {
        self.publication().metadata_revision()
    }
    pub(in crate::studio::runtime) fn current_conversation(
        &self,
    ) -> Option<Arc<ConversationSource>> {
        self.publication().current()
    }
    pub(in crate::studio::runtime) fn runtime(&self) -> Option<RuntimeStateCut> {
        self.latest_runtime
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(in crate::studio::runtime) fn state_resources(&self) -> state_resources::StateResources {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(super) fn compact_runtime(
        &self,
        runtime: crate::ThreadRuntimeSnapshot,
    ) -> Result<crate::ThreadRuntimeSnapshot> {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .runtime(runtime)
    }

    pub(super) fn compact_activity(
        &self,
        activity: Option<crate::ThreadActivity>,
    ) -> Result<Option<crate::ThreadActivity>> {
        self.state_resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .activity(activity)
    }

    pub(in crate::studio::runtime) fn state_activity(&self) -> Option<StateActivityCut> {
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

    pub(super) fn current_last_turn(&self) -> Option<Arc<crate::Turn>> {
        self.last_turn.borrow().clone()
    }

    /// Publishes the newest terminal Turn the owner projected.
    ///
    /// Only a terminal Turn qualifies: the running Turn is already the authoritative snapshot's own
    /// fact, and replacing the retained terminal Turn with a busy one would let a resubscribing
    /// client mistake an in-flight Turn for the last finished one. A committed effect can also reach
    /// this owner *after* a newer one — a deferred admission that storage pressure released late is
    /// taken over behind the live stream — so the retained fact only ever moves forward and the newest
    /// terminal Turn is never replaced by an older one.
    pub(super) fn publish_last_turn(&self, turn: Arc<crate::Turn>) {
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
    pub(super) fn publish_storage(&self, storage: Option<crate::ThreadStorageState>) {
        self.publication().metadata_changed();
        self.storage.send_replace(storage);
    }

    pub(super) fn has_subscribers(&self) -> bool {
        !self.delivery_closed.is_cancelled() && self.events.receiver_count() != 0
    }

    pub(super) fn publish(&self, event: impl FnOnce() -> ThreadLiveEvent) {
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
    pub(super) fn rebase(&self, dropped: u64) {
        self.publish(|| ThreadLiveEvent::Rebase { dropped });
    }
}

#[cfg(test)]
#[path = "live_feed_tests.rs"]
mod tests;
