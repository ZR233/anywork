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
use super::timeline_layer::TimelineDataLayer;

const FEED_CHANNEL_CAPACITY: usize = 512;

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
    reader: HistoryReader,
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
    async fn close_inner(&self) {
        self.cancel.cancel();
        self.reader.request_close();
        self.tasks.close();
        self.tasks.wait().await;
        self.reader.close().await;
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
            inner.cancel.cancel();
            inner.reader.request_close();
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
        let initial_meta = initial_bus
            .as_ref()
            .and_then(MetaEventBus::latest_meta)
            .map(|m| (*m).clone())
            .unwrap_or(initial_meta);

        let is_working_live = matches!(initial_live.phase, LiveStatusPhase::Working { .. });
        let mut tl = TimelineDataLayer::new();
        let reset_patch = tl
            .load_initial_page(&reader, initial_limit, is_working_live)
            .await?;

        let (events_tx, events_rx) = mpsc::channel(FEED_CHANNEL_CAPACITY);
        let _ = events_tx.send(ConversationEvent::Timeline(reset_patch)).await;
        let _ = events_tx
            .send(ConversationEvent::LiveStatus(initial_live.clone()))
            .await;
        let _ = events_tx
            .send(ConversationEvent::SessionMeta(initial_meta.clone()))
            .await;

        let inner = Arc::new(FeedInner {
            thread_id,
            reader,
            timeline: tokio::sync::Mutex::new(tl),
            live_status: Mutex::new(initial_live.clone()),
            session_meta: SessionMetaLayer::new(initial_meta),
            events_rx: tokio::sync::Mutex::new(events_rx),
            events_tx,
            cancel: CancellationToken::new(),
            tasks: TaskTracker::new(),
        });

        let pump_inner = Arc::clone(&inner);
        inner.tasks.spawn(run_feed_pump(
            pump_inner,
            bus_rx,
            initial_bus,
            initial_live_rx,
            initial_live.revision,
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
        self.inner.session_meta.snapshot()
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
        let mut rx = self.inner.events_rx.lock().await;
        rx.recv().await
    }

    pub async fn load_older(&self, cursor: String, limit: u32) -> Result<TimelinePatch> {
        self.ensure_active()?;
        let mut tl = self.inner.timeline.lock().await;
        let patch = tl.load_older(&self.inner.reader, cursor, limit).await?;
        self.ensure_active()?;
        Ok(patch)
    }

    pub async fn load_work_group_members(
        &self,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
    ) -> Result<Vec<WorkGroupMember>> {
        self.ensure_active()?;
        let tl = self.inner.timeline.lock().await;
        let members = tl
            .load_work_group_members(&self.inner.reader, after_seq, before_seq)
            .await?;
        self.ensure_active()?;
        Ok(members)
    }

    pub async fn read_body_window(
        &self,
        reference: &BodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BodyWindow> {
        self.ensure_active()?;
        let tl = self.inner.timeline.lock().await;
        let window = tl
            .read_body_window(&self.inner.reader, reference, offset, max_bytes)
            .await?;
        self.ensure_active()?;
        Ok(window)
    }

    pub async fn reset_to_latest(&self, limit: u32) -> Result<TimelinePatch> {
        self.ensure_active()?;
        let is_working_live = matches!(
            self.live_status_snapshot().phase,
            LiveStatusPhase::Working { .. }
        );
        let patch = {
            let mut tl = self.inner.timeline.lock().await;
            tl.load_initial_page(&self.inner.reader, limit, is_working_live)
                .await?
        };
        self.ensure_active()?;
        let _ = self
            .inner
            .events_tx
            .send(ConversationEvent::Timeline(patch.clone()))
            .await;
        Ok(patch)
    }

    pub fn request_close(&self) {
        self.inner.cancel.cancel();
        self.inner.reader.request_close();
    }

    pub async fn close(&self) {
        self.inner.close_inner().await;
    }
}

async fn emit_events(inner: &FeedInner, events: Vec<ConversationEvent>) -> bool {
    for ev in events {
        if inner.events_tx.send(ev).await.is_err() {
            return false;
        }
    }
    true
}

async fn run_feed_pump(
    inner: Arc<FeedInner>,
    mut bus_rx: watch::Receiver<Option<MetaEventBus>>,
    mut current_bus: Option<MetaEventBus>,
    mut initial_live_rx: Option<tokio::sync::broadcast::Receiver<ThreadMetaEvent>>,
    mut last_live_rev: u64,
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
            // Re-attached on cold -> live transition (or owner epoch restart): sync live status,
            // session meta, and any early commits between `cut_seq` and `bus.subscribe()`.
            let snap = bus.live_status().snapshot();
            if snap.revision > last_live_rev || snap.phase != LiveStatusPhase::Idle {
                last_live_rev = last_live_rev.max(snap.revision);
                *inner
                    .live_status
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = snap.clone();
                if inner
                    .events_tx
                    .send(ConversationEvent::LiveStatus(snap))
                    .await
                    .is_err()
                {
                    return;
                }
            }
            if let Some(meta) = bus.latest_meta()
                && let Some(updated) = inner.session_meta.update((*meta).clone())
                && inner
                    .events_tx
                    .send(ConversationEvent::SessionMeta(updated))
                    .await
                    .is_err()
            {
                return;
            }
            let catchup = {
                let mut tl = inner.timeline.lock().await;
                tl.sync_from_reader_after(&inner.reader).await
            };
            match catchup {
                Ok(evs) => {
                    if !emit_events(&inner, evs).await {
                        return;
                    }
                }
                Err(error) => {
                    let _ = inner
                        .events_tx
                        .send(ConversationEvent::ResyncRequired {
                            reason: format!("catchup after live bus attach failed: {error}"),
                        })
                        .await;
                    return;
                }
            }
        }
        attached_on_open = false;

        loop {
            tokio::select! {
                biased;
                () = inner.cancel.cancelled() => return,
                changed = bus_rx.changed(), if !bus_watch_closed => {
                    match changed {
                        Ok(()) => {
                            let next = bus_rx.borrow_and_update().clone();
                            if next.as_ref().is_some_and(|candidate| candidate.ptr_eq(&bus)) {
                                continue;
                            }
                            if next.is_none() {
                                let prev = inner
                                    .live_status
                                    .lock()
                                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                                    .clone();
                                if prev.phase != LiveStatusPhase::Idle {
                                    last_live_rev = last_live_rev.max(prev.revision).saturating_add(1);
                                    let idle = LiveStatusSnapshot {
                                        revision: last_live_rev,
                                        phase: LiveStatusPhase::Idle,
                                        attentions: Vec::new(),
                                        suppressed_by_interaction: false,
                                    };
                                    *inner
                                        .live_status
                                        .lock()
                                        .unwrap_or_else(std::sync::PoisonError::into_inner) = idle.clone();
                                    if inner
                                        .events_tx
                                        .send(ConversationEvent::LiveStatus(idle))
                                        .await
                                        .is_err()
                                    {
                                        return;
                                    }
                                }
                            }
                            current_bus = next;
                            break;
                        }
                        Err(_) => {
                            bus_watch_closed = true;
                        }
                    }
                }
                recv = rx.recv() => {
                    match recv {
                        Ok(ThreadMetaEvent::History { record, input_id, .. }) => {
                            let evs = {
                                let mut tl = inner.timeline.lock().await;
                                tl.on_history_record(&record, input_id.as_deref())
                            };
                            if !emit_events(&inner, evs).await {
                                return;
                            }
                        }
                        Ok(ThreadMetaEvent::Live(live_ev)) => {
                            let evs = {
                                let mut tl = inner.timeline.lock().await;
                                tl.on_live_event(&live_ev)
                            };
                            if !emit_events(&inner, evs).await {
                                return;
                            }
                        }
                        Ok(ThreadMetaEvent::LiveStatus(live)) => {
                            if live.revision > last_live_rev {
                                last_live_rev = live.revision;
                                let snapshot = (*live).clone();
                                *inner
                                    .live_status
                                    .lock()
                                    .unwrap_or_else(std::sync::PoisonError::into_inner) = snapshot.clone();
                                if inner
                                    .events_tx
                                    .send(ConversationEvent::LiveStatus(snapshot))
                                    .await
                                    .is_err()
                                {
                                    return;
                                }
                            }
                        }
                        Ok(ThreadMetaEvent::SessionMeta(meta)) => {
                            if let Some(updated) = inner.session_meta.update((*meta).clone())
                                && inner
                                    .events_tx
                                    .send(ConversationEvent::SessionMeta(updated))
                                    .await
                                    .is_err()
                            {
                                return;
                            }
                        }
                        Ok(ThreadMetaEvent::Closed) | Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                            if bus_watch_closed {
                                return;
                            }
                            break;
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                            let _ = inner
                                .events_tx
                                .send(ConversationEvent::ResyncRequired {
                                    reason: format!("broadcast lagged by {skipped} events"),
                                })
                                .await;
                            return;
                        }
                    }
                }
            }
        }
    }
}
