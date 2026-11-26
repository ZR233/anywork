//! Unified `ConversationFeed` port combining `TimelineDataLayer`, `LiveStatusDataLayer`,
//! and `SessionMetaLayer` over one per-thread stream and explicit on-demand queries.

use std::sync::{Arc, Mutex, Weak};

use anyhow::Result;
use tokio::sync::{mpsc, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use pl_core::thread::UsageSummary;

use crate::history::HistoryReader;
use crate::{
    ThreadActivity, ThreadModelRouteSnapshot, ThreadRuntimeSnapshot, ThreadRuntimeUsage,
    ThreadStorageState, Turn, mode::ThreadModeId,
};

use super::meta_bus::{MetaEventBus, ThreadMetaEvent};
use super::models::{
    BodyRef, BodyWindow, ConversationEvent, LiveStatusPhase, LiveStatusSnapshot,
    SessionMetaSnapshot, TimelinePatch, WorkGroupMember,
};
use super::session_detail::{SessionDetailKind, SessionDetailSnapshot, SessionDetailWindow};
use super::timeline_layer::TimelineDataLayer;

const FEED_CHANNEL_CAPACITY: usize = 512;

fn session_meta_head(mut snapshot: SessionMetaSnapshot) -> SessionMetaSnapshot {
    if let Some(plan) = snapshot.plan.as_mut() {
        plan.document = None;
    }
    if let Some(plan) = snapshot
        .runtime
        .as_mut()
        .and_then(|runtime| runtime.plan.as_mut())
    {
        plan.document = None;
    }
    snapshot
}

#[derive(Debug)]
pub struct SessionMetaLayer {
    state: Mutex<SessionMetaSnapshot>,
}

impl SessionMetaLayer {
    #[must_use]
    pub fn new(initial: SessionMetaSnapshot) -> Self {
        Self {
            state: Mutex::new(initial),
        }
    }

    #[must_use]
    pub fn empty(thread_id: impl Into<String>) -> Self {
        let thread_id = thread_id.into();
        Self::new(SessionMetaSnapshot {
            thread_id: thread_id.clone(),
            status: crate::ThreadStatus::Idle,
            title: Some(String::new()),
            parent_thread_id: None,
            root_thread_id: thread_id,
            owner_epoch: String::new(),
            revision: 0,
            active_turn: None,
            last_turn: None,
            activity: None,
            usage: UsageSummary::default(),
            context_metrics: None,
            model_route: None,
            runtime: None,
            storage_state: None,
            interactions: Vec::new(),
            pending_interaction_count: 0,
            plan: None,
            mode: None,
            execution_present: false,
        })
    }

    #[must_use]
    pub fn snapshot(&self) -> SessionMetaSnapshot {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(super) fn detail_snapshot(&self, kind: SessionDetailKind) -> SessionDetailSnapshot {
        let guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        SessionDetailSnapshot::capture(&guard, kind)
    }

    pub fn update(&self, next: SessionMetaSnapshot) -> Option<SessionMetaSnapshot> {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if *guard == next {
            return None;
        }
        *guard = next.clone();
        Some(next)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn update_fields(
        &self,
        activity: Option<ThreadActivity>,
        active_turn: Option<Turn>,
        usage: UsageSummary,
        context_metrics: Option<ThreadRuntimeUsage>,
        model_route: Option<ThreadModelRouteSnapshot>,
        runtime: Option<ThreadRuntimeSnapshot>,
        storage_state: Option<ThreadStorageState>,
        mode: Option<ThreadModeId>,
    ) -> SessionMetaSnapshot {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.revision += 1;
        guard.activity = activity;
        guard.active_turn = active_turn;
        guard.usage = usage;
        guard.context_metrics = context_metrics;
        guard.model_route = model_route;
        guard.runtime = runtime;
        guard.storage_state = storage_state;
        guard.mode = mode;
        guard.clone()
    }
}

struct FeedInner {
    thread_id: String,
    reader: Mutex<Option<HistoryReader>>,
    timeline: tokio::sync::Mutex<TimelineDataLayer>,
    live_status: Mutex<LiveStatusSnapshot>,
    session_meta: SessionMetaLayer,
    events_rx: tokio::sync::Mutex<mpsc::Receiver<ConversationEvent>>,
    events_tx: mpsc::Sender<ConversationEvent>,
    cancel: CancellationToken,
    tasks: TaskTracker,
}

impl Drop for FeedInner {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}

impl FeedInner {
    fn reader(&self) -> std::sync::MutexGuard<'_, Option<HistoryReader>> {
        self.reader
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn request_close(&self) {
        self.cancel.cancel();
        if let Some(reader) = self.reader().as_ref() {
            reader.request_close();
        }
    }

    async fn close_inner(&self) {
        self.request_close();
        self.tasks.close();
        self.tasks.wait().await;
        let reader = self.reader().clone();
        if let Some(reader) = reader {
            reader.close().await;
            // A retired feed may still be held by a client. Release its share
            // of the history writer so a new runtime can acquire the lease.
            self.reader().take();
        }
    }
}

/// Non-owning close handle registered on `ObservationSlot` so thread deletion or shutdown can
/// revoke read qualification and join `HistoryReader` without creating an `Arc` cycle.
#[derive(Clone)]
pub struct FeedCloseHandle(Weak<FeedInner>);

impl FeedCloseHandle {
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.0
            .upgrade()
            .is_none_or(|inner| inner.cancel.is_cancelled())
    }

    pub fn request_close(&self) {
        if let Some(inner) = self.0.upgrade() {
            inner.request_close();
        }
    }

    pub async fn close(&self) {
        if let Some(inner) = self.0.upgrade() {
            inner.close_inner().await;
        }
    }
}

fn stale_feed_error() -> anyhow::Error {
    crate::StudioError::new(
        crate::StudioErrorCode::StaleRevision,
        "ConversationFeed is closed or retired",
        false,
    )
    .into()
}

/// Single conversation observation port replacing separate `HistoryReader`, `CurrentReader`,
/// `CurrentWatch`, and `CurrentBodyWatch` handles.
#[derive(Clone)]
pub struct ConversationFeed {
    inner: Arc<FeedInner>,
}

impl std::fmt::Debug for ConversationFeed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationFeed")
            .field("thread_id", &self.inner.thread_id)
            .finish_non_exhaustive()
    }
}

impl ConversationFeed {
    /// Opens a `ConversationFeed` using a static initial `Option<MetaEventBus>` (without dynamic
    /// cold->live re-attachment). Primarily for unit tests.
    pub async fn open_static(
        thread_id: impl Into<String>,
        reader: HistoryReader,
        bus: Option<MetaEventBus>,
        initial_meta: SessionMetaSnapshot,
        initial_limit: u32,
    ) -> Result<Self> {
        let (_tx, rx) = watch::channel(bus);
        Self::open(thread_id, reader, rx, initial_meta, initial_limit).await
    }

    /// Opens a `ConversationFeed`. Subscribes to `bus_rx` (and its current `MetaEventBus` if
    /// already active) BEFORE reading the initial `HistoryReader` cut so zero live/pending/DB
    /// frames fall through any gap, and seamlessly attaches/detaches across cold->live transitions.
    pub async fn open(
        thread_id: impl Into<String>,
        reader: HistoryReader,
        mut bus_rx: watch::Receiver<Option<MetaEventBus>>,
        initial_meta: SessionMetaSnapshot,
        initial_limit: u32,
    ) -> Result<Self> {
        let thread_id = thread_id.into();
        let initial_bus = bus_rx.borrow_and_update().clone();
        let initial_live_rx = initial_bus.as_ref().map(MetaEventBus::subscribe);
        let initial_live = initial_bus
            .as_ref()
            .map_or_else(LiveStatusSnapshot::default, |b| b.live_status().snapshot());
        let initial_bus_meta = initial_bus.as_ref().and_then(MetaEventBus::latest_meta);
        let initial_meta_revision = initial_bus_meta.as_ref().map(|meta| meta.revision);
        let initial_meta = initial_bus_meta
            .map(|m| (*m).clone())
            .unwrap_or(initial_meta);

        let is_working_live = matches!(initial_live.phase, LiveStatusPhase::Working { .. });
        let mut tl = TimelineDataLayer::new();
        let reset_patch = tl
            .load_initial_page(&reader, initial_limit, is_working_live)
            .await?;

        let (events_tx, events_rx) = mpsc::channel(FEED_CHANNEL_CAPACITY);
        let initial_events = vec![
            ConversationEvent::Timeline(reset_patch),
            ConversationEvent::LiveStatus(initial_live.clone()),
            ConversationEvent::SessionMeta(session_meta_head(initial_meta.clone())),
        ];

        let inner = Arc::new(FeedInner {
            thread_id,
            reader: Mutex::new(Some(reader)),
            timeline: tokio::sync::Mutex::new(tl),
            live_status: Mutex::new(initial_live.clone()),
            session_meta: SessionMetaLayer::new(initial_meta),
            events_rx: tokio::sync::Mutex::new(events_rx),
            events_tx,
            cancel: CancellationToken::new(),
            tasks: TaskTracker::new(),
        });

        for event in initial_events {
            if !send_event(&inner, event).await {
                return Err(stale_feed_error());
            }
        }

        let pump_inner = Arc::clone(&inner);
        inner.tasks.spawn(run_feed_pump(
            pump_inner,
            bus_rx,
            initial_bus,
            initial_live_rx,
            initial_live.revision,
            initial_meta_revision,
        ));

        Ok(Self { inner })
    }

    #[must_use]
    pub fn close_handle(&self) -> FeedCloseHandle {
        FeedCloseHandle(Arc::downgrade(&self.inner))
    }

    #[must_use]
    pub fn thread_id(&self) -> &str {
        &self.inner.thread_id
    }

    #[must_use]
    pub fn live_status_snapshot(&self) -> LiveStatusSnapshot {
        self.inner
            .live_status
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    #[must_use]
    pub fn session_meta_snapshot(&self) -> SessionMetaSnapshot {
        session_meta_head(self.inner.session_meta.snapshot())
    }

    /// Reads the selected full metadata field from this Feed's most recently applied cut.
    /// Compare both owner epoch and revision before combining windows from separate requests.
    pub fn read_session_detail(
        &self,
        kind: SessionDetailKind,
        offset: u64,
        max_bytes: u32,
    ) -> Result<SessionDetailWindow> {
        self.ensure_active()?;
        let snapshot = self.inner.session_meta.detail_snapshot(kind);
        let window = snapshot.window(offset, max_bytes)?;
        self.ensure_active()?;
        Ok(window)
    }

    #[must_use]
    pub fn cancellation_token(&self) -> CancellationToken {
        self.inner.cancel.clone()
    }

    fn ensure_active(&self) -> Result<()> {
        if self.inner.cancel.is_cancelled() {
            return Err(stale_feed_error());
        }
        Ok(())
    }

    pub async fn next_event(&self) -> Option<ConversationEvent> {
        let mut rx = tokio::select! {
            biased;
            () = self.inner.cancel.cancelled() => return None,
            rx = self.inner.events_rx.lock() => rx,
        };
        tokio::select! {
            biased;
            () = self.inner.cancel.cancelled() => None,
            event = rx.recv() => event,
        }
    }

    pub async fn load_older(&self, cursor: String, limit: u32) -> Result<TimelinePatch> {
        self.ensure_active()?;
        let mut tl = self.inner.timeline.lock().await;
        let reader = self.history_reader()?;
        let patch = tl.load_older(&reader, cursor, limit).await?;
        self.ensure_active()?;
        Ok(patch)
    }

    pub async fn load_work_group_members(
        &self,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
    ) -> Result<Vec<WorkGroupMember>> {
        let reader = self.history_reader()?;
        let members =
            TimelineDataLayer::load_work_group_members(&reader, after_seq, before_seq).await?;
        self.ensure_active()?;
        Ok(members)
    }

    pub async fn read_body_window(
        &self,
        reference: &BodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BodyWindow> {
        let reader = self.history_reader()?;
        let window =
            TimelineDataLayer::read_body_window(&reader, reference, offset, max_bytes).await?;
        self.ensure_active()?;
        Ok(window)
    }

    pub async fn reset_to_latest(&self, limit: u32) -> Result<TimelinePatch> {
        self.ensure_active()?;
        let is_working_live = matches!(
            self.live_status_snapshot().phase,
            LiveStatusPhase::Working { .. }
        );
        // Keep the rebuilt cut and its first patch in the same ordering as live appends.
        let mut timeline = self.inner.timeline.lock().await;
        let reader = self.history_reader()?;
        let patch = timeline
            .load_initial_page(&reader, limit, is_working_live)
            .await?;
        self.ensure_active()?;
        if !send_event(&self.inner, ConversationEvent::Timeline(patch.clone())).await {
            return Err(stale_feed_error());
        }
        Ok(patch)
    }

    pub fn request_close(&self) {
        self.inner.request_close();
    }

    fn history_reader(&self) -> Result<HistoryReader> {
        self.ensure_active()?;
        self.inner.reader().clone().ok_or_else(stale_feed_error)
    }

    pub async fn close(&self) {
        self.inner.close_inner().await;
    }
}

async fn send_event(inner: &FeedInner, event: ConversationEvent) -> bool {
    tokio::select! {
        biased;
        () = inner.cancel.cancelled() => false,
        result = inner.events_tx.send(event) => result.is_ok(),
    }
}

async fn emit_events(inner: &FeedInner, events: Vec<ConversationEvent>) -> bool {
    for ev in events {
        if !send_event(inner, ev).await {
            return false;
        }
    }
    true
}

fn stage_live_status(inner: &FeedInner, mut snapshot: LiveStatusSnapshot) -> ConversationEvent {
    let mut current = inner
        .live_status
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    snapshot.revision = current.revision.saturating_add(1);
    *current = snapshot.clone();
    ConversationEvent::LiveStatus(snapshot)
}

async fn run_feed_pump(
    inner: Arc<FeedInner>,
    mut bus_rx: watch::Receiver<Option<MetaEventBus>>,
    mut current_bus: Option<MetaEventBus>,
    mut initial_live_rx: Option<tokio::sync::broadcast::Receiver<ThreadMetaEvent>>,
    mut last_live_rev: u64,
    mut last_meta_rev: Option<u64>,
) {
    let mut attached_on_open = current_bus.is_some();
    let mut bus_watch_closed = false;

    loop {
        if inner.cancel.is_cancelled() {
            return;
        }
        let Some(bus) = current_bus.take() else {
            if bus_watch_closed {
                return;
            }
            tokio::select! {
                biased;
                () = inner.cancel.cancelled() => return,
                changed = bus_rx.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    current_bus = bus_rx.borrow_and_update().clone();
                    attached_on_open = false;
                }
            }
            continue;
        };

        let mut rx = match initial_live_rx.take() {
            Some(rx) => rx,
            None => bus.subscribe(),
        };

        if !attached_on_open {
            // The receiver is installed before the replay cut. Duplicate records are ignored by
            // sequence, and a missing range asks the client to reopen from cold history.
            let snap = bus.live_status().snapshot();
            // Each bus owns its own revisions. A new owner may start back at zero.
            last_live_rev = snap.revision;
            if !send_event(&inner, stage_live_status(&inner, snap)).await {
                return;
            }
            let latest_meta = bus.latest_meta();
            last_meta_rev = latest_meta.as_ref().map(|meta| meta.revision);
            if let Some(meta) = latest_meta
                && let Some(updated) = inner.session_meta.update((*meta).clone())
                && !send_event(
                    &inner,
                    ConversationEvent::SessionMeta(session_meta_head(updated)),
                )
                .await
            {
                return;
            }
            let mut timeline = tokio::select! {
                biased;
                () = inner.cancel.cancelled() => return,
                timeline = inner.timeline.lock() => timeline,
            };
            let Some(records) = bus.replay_history_after(timeline.cut_seq()) else {
                let _ = send_event(
                    &inner,
                    ConversationEvent::ResyncRequired {
                        reason: "in-memory history replay cannot reach the feed cut".into(),
                    },
                )
                .await;
                return;
            };
            for record in records {
                let input_id = match &record.source {
                    Some(crate::ChatSourceId::Input { input_id }) => Some(input_id.as_str()),
                    _ => None,
                };
                if !emit_events(&inner, timeline.on_history_record(&record, input_id)).await {
                    return;
                }
            }
        }
        attached_on_open = false;

        loop {
            tokio::select! {
                biased;
                () = inner.cancel.cancelled() => return,
                recv = rx.recv() => {
                    match recv {
                        Ok(ThreadMetaEvent::History { record, input_id, .. }) => {
                            let mut timeline = tokio::select! {
                                biased;
                                () = inner.cancel.cancelled() => return,
                                timeline = inner.timeline.lock() => timeline,
                            };
                            let evs = timeline.on_history_record(&record, input_id.as_deref());
                            if !emit_events(&inner, evs).await {
                                return;
                            }
                        }
                        Ok(ThreadMetaEvent::Live(live_ev)) => {
                            let evs = {
                                let mut tl = tokio::select! {
                                    biased;
                                    () = inner.cancel.cancelled() => return,
                                    tl = inner.timeline.lock() => tl,
                                };
                                tl.on_live_event(&live_ev)
                            };
                            if !emit_events(&inner, evs).await {
                                return;
                            }
                        }
                        Ok(ThreadMetaEvent::LiveStatus(live)) => {
                            if live.revision > last_live_rev {
                                last_live_rev = live.revision;
                                if !send_event(&inner, stage_live_status(&inner, (*live).clone())).await
                                {
                                    return;
                                }
                            }
                        }
                        Ok(ThreadMetaEvent::SessionMeta(meta)) => {
                            if last_meta_rev.is_some_and(|revision| meta.revision <= revision) {
                                continue;
                            }
                            last_meta_rev = Some(meta.revision);
                            if let Some(updated) = inner.session_meta.update((*meta).clone())
                                && !send_event(&inner, ConversationEvent::SessionMeta(session_meta_head(updated))).await
                            {
                                return;
                            }
                        }
                        Ok(ThreadMetaEvent::Closed) | Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                            if bus_watch_closed {
                                return;
                            }
                            current_bus = bus_rx.borrow_and_update().clone()
                                .filter(|candidate| !candidate.ptr_eq(&bus));
                            break;
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                            let _ = send_event(&inner, ConversationEvent::ResyncRequired {
                                    reason: format!("broadcast lagged by {skipped} events"),
                                }).await;
                            return;
                        }
                    }
                }
                // Drain already-published records from the retiring owner before switching.
                changed = bus_rx.changed(), if !bus_watch_closed => {
                    match changed {
                        Ok(()) => {
                            let next = bus_rx.borrow_and_update().clone();
                            if next.as_ref().is_some_and(|candidate| candidate.ptr_eq(&bus)) {
                                continue;
                            }
                            current_bus = next;
                            break;
                        }
                        Err(_) => {
                            bus_watch_closed = true;
                        }
                    }
                }
            }
        }
        let needs_idle = current_bus.is_none()
            && inner
                .live_status
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .phase
                != LiveStatusPhase::Idle;
        if needs_idle
            && !send_event(
                &inner,
                stage_live_status(&inner, LiveStatusSnapshot::default()),
            )
            .await
        {
            return;
        }
    }
}

#[cfg(test)]
mod cancellation_tests {
    use super::*;
    use crate::history::{HistoryLimits, HistoryStore};
    use std::time::Duration;

    #[tokio::test]
    async fn full_event_queue_without_a_consumer_does_not_block_close() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = HistoryStore::open(
            temp.path().join("history.sqlite"),
            "full-feed",
            HistoryLimits::default(),
        )
        .await?;
        let bus = MetaEventBus::open(
            crate::Thread::placeholder("full-feed"),
            store.clone(),
            pl_core::thread::current::RuntimeEpoch::new(),
        );
        let meta = SessionMetaLayer::empty("full-feed").snapshot();
        let feed = ConversationFeed::open_static(
            "full-feed",
            store.reader(),
            Some(bus.clone()),
            meta.clone(),
            64,
        )
        .await?;
        // Fill the actual outgoing channel; no receiver ever drains it.
        while feed
            .inner
            .events_tx
            .try_send(ConversationEvent::SessionMeta(meta.clone()))
            .is_ok()
        {}
        assert_eq!(feed.inner.events_tx.capacity(), 0);
        let mut updated = meta;
        updated.revision = 7;
        bus.update_session_meta(updated);
        // Updating the exposed snapshot happens immediately before the pump awaits its send.
        tokio::time::timeout(Duration::from_secs(2), async {
            while feed.session_meta_snapshot().revision != 7 {
                tokio::task::yield_now().await;
            }
        })
        .await?;
        tokio::time::timeout(Duration::from_secs(2), feed.close()).await?;
        assert!(
            tokio::time::timeout(Duration::from_secs(2), feed.next_event())
                .await?
                .is_none()
        );
        bus.close().await;
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn close_cancels_both_receive_and_receiver_lock_waiters() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = HistoryStore::open(
            temp.path().join("history.sqlite"),
            "empty-feed",
            HistoryLimits::default(),
        )
        .await?;
        let feed = ConversationFeed::open_static(
            "empty-feed",
            store.reader(),
            None,
            SessionMetaLayer::empty("empty-feed").snapshot(),
            64,
        )
        .await?;
        for _ in 0..3 {
            assert!(feed.next_event().await.is_some());
        }
        let mut first = std::pin::pin!(feed.next_event());
        let mut second = std::pin::pin!(feed.next_event());
        assert!(futures::poll!(&mut first).is_pending());
        assert!(futures::poll!(&mut second).is_pending());
        tokio::time::timeout(Duration::from_secs(2), feed.close()).await?;
        assert!(
            tokio::time::timeout(Duration::from_secs(2), first)
                .await?
                .is_none()
        );
        assert!(
            tokio::time::timeout(Duration::from_secs(2), second)
                .await?
                .is_none()
        );
        store.close().await?;
        Ok(())
    }
}
