//! Passive State observation. One assembler owns the snapshot and continuous notifications.
//!
//! Opening registers on the existing observation slot and reads cold current JSON when no source is
//! installed. It never activates execution or waits for an execution workspace check.
use super::{
    StudioRuntime,
    thread_observation::{StateReceiver, ThreadLiveEvent},
};
use crate::studio::thread_projection::{LiveEvent, TurnEvent};
use anyhow::{Result, ensure};
use pl_core::chat as core;
use pl_protocol::{
    THREAD_SCHEMA_VERSION, ThreadActivity, ThreadBusinessRefs,
    ThreadNotification, ThreadNotificationEnvelope, ThreadStorageState, ThreadSubscriptionUpdate,
};
use std::{collections::VecDeque, sync::Arc, time::Duration};
use tokio::{
    sync::{broadcast, watch},
    time::{Instant, timeout_at},
};
use tokio_util::sync::CancellationToken;

const PENDING_FRAMES: usize = 512;
const PENDING_BYTES: usize = 1024 * 1024;
const OBSERVATION_DELIVERY_INTERVAL: Duration = Duration::from_millis(16);

/// Independent State receiver. Content consumption cannot delay these frames.
pub struct ConversationStateFeed {
    thread_id: String,
    subscription_id: String,
    pending: VecDeque<ThreadSubscriptionUpdate>,
    ready_frames: usize,
    observation_due: Option<Instant>,
    state: Option<StateReceiver>,
    storage: Option<watch::Receiver<Option<ThreadStorageState>>>,
    last_turn: Option<watch::Receiver<Option<Arc<pl_protocol::Turn>>>>,
    slot_changed: watch::Receiver<u64>,
    slot_epoch: u64,
    applied: u64,
    business_refs_sequence: u64,
    business_refs: ThreadBusinessRefs,
    revision: u64,
    epoch: u64,
    runtime_floor: (u64, u64),
    activity_floor: u64,
    activity: Option<ThreadActivity>,
    runtime: Option<pl_protocol::ThreadRuntimeSnapshot>,
    model_route: Option<pl_protocol::ThreadModelRouteSnapshot>,
    storage_state: Option<ThreadStorageState>,
    active_turn: Option<String>,
    delivered_terminal: Option<(String, u64)>,
    cancel: CancellationToken,
    runtime_owner: StudioRuntime,
    ended: bool,
}

impl std::fmt::Debug for ConversationStateFeed {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ConversationStateFeed")
            .field("thread_id", &self.thread_id)
            .field("subscription_id", &self.subscription_id)
            .field("revision", &self.revision)
            .finish_non_exhaustive()
    }
}

fn resync() -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "Current source continuity changed; open a new handle",
        true,
    )
    .with_reason(
        pl_protocol::studio::StudioErrorReason::ConversationResyncRequired,
        serde_json::Value::Null,
    )
    .into()
}

impl StudioRuntime {
    /// Opens a passive State feed. A missing execution owner stays missing.
    pub(super) async fn open_current_state_feed(
        &self,
        thread_id: &str,
        cancellation: CancellationToken,
    ) -> Result<ConversationStateFeed> {
        ensure!(!cancellation.is_cancelled(), core::ChatError::Cancelled);
        let subscription_id = crate::studio::ids::new_id("state");
        let slot = self.thread_observations.observation_slot(thread_id);
        let (position, mut slot_changed) = slot.capture();
        let registered = position
            .source
            .as_ref()
            .filter(|source| !source.is_delivery_closed())
            .map(|source| {
                (
                    source.subscribe(),
                    source.storage(),
                    source.last_turn(),
                    source.conversation(),
                    source.clone(),
                )
            });
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let mut state = None;
        let mut storage = None;
        let mut last_turn = None;
        let mut model_route = None;
        let mut runtime = None;
        let mut runtime_floor = (0, 0);
        let mut activity = None;
        let mut activity_floor = 0;
        let cold_terminal = None;
        let mut annotate_route = false;
        let (effect_cut, active_turn, _interactions, business_refs) = if let Some((
            state_rx,
            storage_rx,
            terminal_rx,
            registration,
            feed,
        )) = registered
        {
            let mut source = registration.source;
            let mut progress_rx = registration.progress;
            let mut owner_progress = registration.owner_progress;
            loop {
                ensure!(
                    slot.is_current(position.epoch)
                        && !self.shutdown_latch.is_committed()
                        && !feed.is_delivery_closed(),
                    resync()
                );
                if source.is_some() {
                    break;
                }
                let retained = owner_progress.borrow_and_update().clone();
                if let Some(error) = retained.retained_error() {
                    return Err(crate::error_mapping::shared_runtime_error(error));
                }
                source = progress_rx.borrow_and_update().clone();
                ensure!(
                    slot.is_current(position.epoch)
                        && !self.shutdown_latch.is_committed()
                        && !feed.is_delivery_closed()
                        && !retained.is_finished(),
                    resync()
                );
                if source.is_some() {
                    break;
                }
                #[cfg(test)]
                feed.notify_first_open_wait();
                tokio::select! { biased;
                    _ = cancellation.cancelled() => return Err(core::ChatError::Cancelled.into()),
                    _ = self.shutdown_latch.committed() => return Err(resync()),
                    _ = slot_changed.changed() => return Err(resync()),
                    _ = feed.delivery_closed() => return Err(resync()),
                    changed = owner_progress.changed() => { ensure!(changed.is_ok(), resync()); },
                    changed = progress_rx.changed() => { ensure!(changed.is_ok(), resync()); },
                }
            }
            let source = source.ok_or_else(resync)?;
            ensure!(
                slot.is_current(position.epoch)
                    && !self.shutdown_latch.is_committed()
                    && !feed.is_delivery_closed(),
                resync()
            );
            let effect_cut = source.current.revision();
            let active_turn = source.current.active_turn().cloned();
            let interactions = source.current.interactions().to_vec();
            let business_refs = source.current.business_refs();
            if let Some(cut) = feed.runtime() {
                runtime_floor = (cut.observation_revision, cut.catalog_revision);
                model_route = cut.model_route;
                runtime = Some((*cut.runtime).clone());
            }
            // A baseline with no activity is still a covered observation. An
            // older delayed phase must not revive after that idle cut.
            activity_floor = runtime_floor.0;
            if let Some(cut) = feed.state_activity() {
                activity_floor = activity_floor.max(cut.observation_revision);
                activity = cut.activity.as_deref().cloned();
            }
            state = Some(state_rx);
            storage = Some(storage_rx);
            last_turn = Some(terminal_rx);
            (effect_cut, active_turn, interactions, business_refs)
        } else {
            annotate_route = true;
            let saved = self
                .store
                .state_for(&thread.workspace_id, thread_id)?
                .load_current()
                .await?;
            ensure!(slot.is_current(position.epoch), resync());
            match saved {
                Some(saved) => {
                    let snapshot = saved.state.to_paused_snapshot();
                    let current =
                        crate::studio::thread_projection::CurrentState::from_saved(&saved)?;
                    model_route = crate::studio::model_route::saved(&snapshot)?
                        .map(|route| route.snapshot(false));
                    let projected = crate::studio::thread_projection::project_cold_runtime(
                        thread_id,
                        &snapshot,
                        thread.updated_at,
                        &snapshot.usage_summary,
                    )?;
                    let mut resources = super::thread_observation::state_resources::StateResources::cold(
                        current.owner_id().into(), saved.snapshot_revision,
                    );
                    runtime = Some(resources.runtime(projected)?);
                    (
                        saved.snapshot_revision,
                        current.active_turn().cloned(),
                        current.interactions().to_vec(),
                        current.business_refs(),
                    )
                }
                None => (0, None, Vec::new(), ThreadBusinessRefs::empty()),
            }
        };
        ensure!(
            slot.is_current(position.epoch) && !self.shutdown_latch.is_committed(),
            resync()
        );
        if annotate_route {
            let (config, _) = self.config_runtime.read_with_catalog()?;
            crate::studio::model_route::annotate_availability(
                model_route.as_mut(),
                &thread,
                &config.config,
            )?;
        }
        if let Some(runtime) = runtime.as_mut() {
            annotate_runtime_mode(self, runtime);
        }
        let storage_state = storage
            .as_mut()
            .and_then(|storage| storage.borrow_and_update().clone());
        let snapshot = pl_protocol::ThreadSnapshot {
            schema_version: THREAD_SCHEMA_VERSION,
            revision: effect_cut,
            thread,
            runtime: runtime.clone(),
            model_route: model_route.clone(),
            active_turn: active_turn.clone(),
            interactions: Vec::new(),
            business_refs: business_refs.clone(),
            activity: activity.clone(),
            storage: storage_state.clone(),
        };
        let mut feed = ConversationStateFeed {
            thread_id: thread_id.to_owned(),
            subscription_id,
            pending: VecDeque::new(),
            ready_frames: 0,
            observation_due: None,
            state,
            storage,
            last_turn,
            slot_changed,
            slot_epoch: position.epoch,
            applied: effect_cut,
            business_refs_sequence: effect_cut,
            business_refs,
            revision: effect_cut,
            epoch: 1,
            runtime_floor,
            activity_floor,
            activity,
            runtime,
            model_route,
            storage_state,
            active_turn: active_turn.as_ref().map(|turn| turn.id.clone()),
            delivered_terminal: None,
            cancel: cancellation,
            runtime_owner: self.clone(),
            ended: false,
        };
        feed.push_frame_update(ThreadSubscriptionUpdate::Snapshot {
            snapshot: Box::new(snapshot),
        })?;
        if let Some(turn) = cold_terminal {
            feed.reflect_terminal(turn)?;
        } else {
            feed.reflect_retained_turn()?;
        }
        feed.ready_frames = feed.pending.len();
        Ok(feed)
    }
}

impl ConversationStateFeed {
    pub fn thread_id(&self) -> &str {
        &self.thread_id
    }
    pub fn subscription_id(&self) -> &str {
        &self.subscription_id
    }
    pub fn cancellation_token(&self) -> CancellationToken {
        self.cancel.clone()
    }
    pub fn request_close(&self) {
        self.cancel.cancel();
    }
    pub async fn close(&mut self) -> Result<()> {
        self.finish();
        Ok(())
    }

    fn finish(&mut self) {
        self.cancel.cancel();
        self.state = None;
        self.storage = None;
        self.last_turn = None;
        self.pending.clear();
        self.ready_frames = 0;
        self.observation_due = None;
        self.ended = true;
    }

    fn terminal_delivered(&self, turn: &pl_protocol::Turn) -> bool {
        self.delivered_terminal
            .as_ref()
            .is_some_and(|(id, revision)| id == &turn.id && *revision >= turn.revision)
    }

    fn reflect_retained_turn(&mut self) -> Result<()> {
        let Some(watch) = self.last_turn.as_mut() else {
            return Ok(());
        };
        let Some(turn) = watch.borrow_and_update().clone() else {
            return Ok(());
        };
        self.reflect_terminal((*turn).clone())
    }

    fn reflect_terminal(&mut self, turn: pl_protocol::Turn) -> Result<()> {
        if turn.revision > self.applied
            || self.active_turn.is_some()
            || self.terminal_delivered(&turn)
        {
            return Ok(());
        }
        self.delivered_terminal = Some((turn.id.clone(), turn.revision));
        self.enqueue(ThreadNotification::TurnCompleted { turn })
    }

    fn refresh_storage(&mut self) -> Result<()> {
        let Some(watch) = self.storage.as_mut() else {
            return Ok(());
        };
        let storage = watch.borrow_and_update().clone();
        if storage != self.storage_state {
            self.storage_state.clone_from(&storage);
            self.enqueue(ThreadNotification::StorageChanged {
                storage: storage.map(Box::new),
            })?;
        }
        Ok(())
    }

    fn apply(&mut self, event: ThreadLiveEvent) -> Result<()> {
        match event {
            ThreadLiveEvent::Committed { sequence, changes } => {
                if sequence <= self.applied {
                    return Ok(());
                }
                self.applied = sequence;
                for change in changes {
                    self.push(change)?;
                }
            }
            ThreadLiveEvent::BusinessRefs {
                sequence,
                references,
            } => {
                if sequence <= self.business_refs_sequence {
                    return Ok(());
                }
                self.business_refs_sequence = sequence;
                if references != self.business_refs {
                    self.business_refs.clone_from(&references);
                    self.enqueue(ThreadNotification::BusinessRefsChanged { references })?;
                }
            }
            ThreadLiveEvent::Runtime {
                observation_revision,
                catalog_revision,
                runtime,
                model_route,
            } => {
                if observation_revision < self.runtime_floor.0
                    || (observation_revision == self.runtime_floor.0
                        && catalog_revision <= self.runtime_floor.1)
                {
                    return Ok(());
                }
                ensure!(
                    observation_revision >= self.runtime_floor.0
                        && catalog_revision >= self.runtime_floor.1,
                    resync()
                );
                self.runtime_floor = (observation_revision, catalog_revision);
                if self.runtime.as_ref() == Some(runtime.as_ref())
                    && self.model_route == model_route
                {
                    return Ok(());
                }
                self.runtime = Some((*runtime).clone());
                self.model_route.clone_from(&model_route);
                self.enqueue(ThreadNotification::ThreadRuntimeUpdated {
                    runtime: Box::new((*runtime).clone()),
                    model_route,
                })?;
            }
            ThreadLiveEvent::Activity {
                observation_revision,
                activity,
            } => {
                if observation_revision <= self.activity_floor {
                    return Ok(());
                }
                self.activity_floor = observation_revision;
                if activity.as_deref() != self.activity.as_ref() {
                    self.activity = activity.as_deref().cloned();
                    self.enqueue(ThreadNotification::ActivityChanged {
                        activity: activity.map(|activity| Box::new((*activity).clone())),
                    })?;
                }
            }
            ThreadLiveEvent::UnframedCommit { sequence } => {
                if sequence > self.applied {
                    self.lagged(1)?;
                }
            }
            ThreadLiveEvent::Rebase { dropped } => self.lagged(dropped)?,
        }
        Ok(())
    }

    fn push(&mut self, event: LiveEvent) -> Result<()> {
        let notification = match event {
            LiveEvent::Turn { turn, event } => {
                if self.terminal_delivered(&turn) {
                    return Ok(());
                }
                if matches!(&turn.state, pl_protocol::TurnState::Running(_)) {
                    self.active_turn = Some(turn.id.clone());
                } else if turn.state.is_terminal() {
                    self.delivered_terminal = Some((turn.id.clone(), turn.revision));
                    if self.active_turn.as_deref() == Some(turn.id.as_str()) {
                        self.active_turn = None;
                    }
                }
                match event {
                    TurnEvent::Started => ThreadNotification::TurnStarted { turn },
                    TurnEvent::Updated => ThreadNotification::TurnUpdated { turn },
                    TurnEvent::Completed => ThreadNotification::TurnCompleted { turn },
                }
            }
            LiveEvent::Interaction(interaction) => {
                ThreadNotification::InteractionChanged { interaction }
            }
        };
        self.enqueue(notification)
    }

    fn lagged(&mut self, dropped: u64) -> Result<()> {
        self.pending.clear();
        self.observation_due = None;
        self.ready_frames = 0;
        self.epoch = self.epoch.checked_add(1).ok_or_else(resync)?;
        self.enqueue(ThreadNotification::Lagged { dropped })
    }

    fn enqueue(&mut self, notification: ThreadNotification) -> Result<()> {
        if self.coalesce_pending(&notification) {
            return self.check_budget();
        }
        if self.pending.len() >= PENDING_FRAMES || self.pending_bytes() > PENDING_BYTES {
            let dropped = self.pending.len() as u64;
            self.pending.clear();
            self.observation_due = None;
            self.ready_frames = 0;
            self.epoch = self.epoch.checked_add(1).ok_or_else(resync)?;
            self.push_notification(ThreadNotification::Lagged { dropped })?;
        }
        self.push_notification(notification)
    }

    fn coalesce_pending(&mut self, notification: &ThreadNotification) -> bool {
        let Some(ThreadSubscriptionUpdate::Notification { notification: last }) =
            self.pending.back_mut()
        else {
            return false;
        };
        let mergeable = match notification {
            ThreadNotification::ActivityChanged { activity } => matches!(
                &last.notification,
                ThreadNotification::ActivityChanged { activity: old }
                    if old.as_ref().map(|old| old.identity.as_str())
                        == activity.as_ref().map(|activity| activity.identity.as_str())
            ),
            ThreadNotification::ThreadRuntimeUpdated { runtime, .. } => matches!(
                &last.notification,
                ThreadNotification::ThreadRuntimeUpdated { runtime: old, .. }
                    if same_live_runtime_identity(runtime, old)
            ),
            _ => false,
        };
        if mergeable {
            last.notification = notification.clone();
            last.emitted_at = crate::studio::unix_seconds();
        }
        mergeable
    }

    fn push_notification(&mut self, notification: ThreadNotification) -> Result<()> {
        let next = self.revision.checked_add(1).ok_or_else(resync)?;
        self.pending
            .push_back(ThreadSubscriptionUpdate::Notification {
                notification: Box::new(ThreadNotificationEnvelope::new(
                    self.thread_id.clone(),
                    self.epoch,
                    self.revision,
                    next,
                    crate::studio::unix_seconds(),
                    notification,
                )),
            });
        self.revision = next;
        self.check_budget()
    }

    fn push_frame_update(&mut self, update: ThreadSubscriptionUpdate) -> Result<()> {
        self.pending.push_back(update);
        self.check_budget()
    }

    fn pending_bytes(&self) -> usize {
        self.pending
            .iter()
            .map(|item| serde_json::to_vec(item).map_or(usize::MAX, |bytes| bytes.len()))
            .sum()
    }

    fn check_budget(&self) -> Result<()> {
        ensure!(
            self.pending.len() <= PENDING_FRAMES && self.pending_bytes() <= PENDING_BYTES,
            resync()
        );
        Ok(())
    }

    fn has_only_coalescable_frames(&self) -> bool {
        !self.pending.is_empty()
            && self.pending.iter().all(|frame| {
                matches!(frame, ThreadSubscriptionUpdate::Notification { notification }
                if matches!(
                    notification.notification,
                    ThreadNotification::ActivityChanged { .. }
                        | ThreadNotification::StorageChanged { .. }
                ) || matches!(
                    notification.notification,
                    ThreadNotification::ThreadRuntimeUpdated { ref runtime, .. }
                        if runtime.live_usage.as_ref().is_some_and(|usage| {
                            usage.state == pl_protocol::ThreadRuntimeUsageState::Live
                        })
                ))
            })
    }

    fn read_feed(&mut self) -> Result<Option<ThreadLiveEvent>> {
        let Some(feed) = self.state.as_mut() else {
            return Ok(None);
        };
        match feed.try_recv() {
            Ok(event) => Ok(Some(event)),
            Err(broadcast::error::TryRecvError::Empty) => Ok(None),
            Err(broadcast::error::TryRecvError::Lagged(dropped)) => {
                self.lagged(dropped)?;
                Ok(None)
            }
            Err(broadcast::error::TryRecvError::Closed) => {
                self.ended = true;
                Ok(None)
            }
        }
    }

    fn drain_feed(&mut self) -> Result<bool> {
        let mut progressed = false;
        for _ in 0..PENDING_FRAMES {
            match self.read_feed()? {
                Some(event) => {
                    progressed = true;
                    self.apply(event)?;
                }
                None => return Ok(progressed),
            }
        }
        Ok(true)
    }

    pub async fn recv(&mut self) -> Result<Option<ThreadSubscriptionUpdate>> {
        let result = self.receive().await;
        if result.is_err() {
            self.finish();
        }
        result
    }

    async fn receive(&mut self) -> Result<Option<ThreadSubscriptionUpdate>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(core::ChatError::Cancelled.into());
            }
            ensure!(*self.slot_changed.borrow() == self.slot_epoch, resync());
            if self.ended || self.state.as_ref().is_some_and(StateReceiver::is_closed) {
                self.ended = true;
                if self.pending.is_empty() {
                    return Ok(None);
                }
            }
            self.refresh_storage()?;
            self.reflect_retained_turn()?;
            if self.ready_frames == 0 {
                self.drain_feed()?;
                self.refresh_storage()?;
                self.reflect_retained_turn()?;
            }
            if !self.pending.is_empty() {
                if self.ready_frames == 0 {
                    if self.has_only_coalescable_frames() {
                        let due = *self
                            .observation_due
                            .get_or_insert_with(|| Instant::now() + OBSERVATION_DELIVERY_INTERVAL);
                        while Instant::now() < due && self.has_only_coalescable_frames() {
                            let wake = timeout_at(due, self.wait_wake()).await;
                            match wake {
                                Ok(Ok(Wake::Closed)) | Err(_) => break,
                                Ok(Err(error)) => return Err(error),
                                Ok(Ok(Wake::Cancel)) => {
                                    return Err(core::ChatError::Cancelled.into());
                                }
                                Ok(Ok(Wake::Slot)) => return Err(resync()),
                                Ok(Ok(Wake::Event(event))) => self.apply(event)?,
                                Ok(Ok(Wake::Storage(open))) => {
                                    if !open {
                                        self.storage = None;
                                    }
                                }
                                Ok(Ok(Wake::Terminal(open))) => {
                                    if !open {
                                        self.last_turn = None;
                                    }
                                }
                            }
                            self.refresh_storage()?;
                            self.reflect_retained_turn()?;
                        }
                    }
                    self.observation_due = None;
                    self.ready_frames = self.pending.len();
                }
                self.ready_frames = self.ready_frames.saturating_sub(1);
                let mut update = self.pending.pop_front();
                if let Some(ThreadSubscriptionUpdate::Notification { notification }) = &mut update
                    && let ThreadNotification::ThreadRuntimeUpdated { runtime, .. } =
                        &mut notification.notification
                {
                    annotate_runtime_mode(&self.runtime_owner, runtime);
                }
                return Ok(update);
            }
            self.observation_due = None;
            if self.state.is_none() {
                self.park_cold().await?;
                continue;
            }
            match self.wait_wake().await? {
                Wake::Cancel => return Err(core::ChatError::Cancelled.into()),
                Wake::Slot => return Err(resync()),
                Wake::Closed => return Ok(None),
                Wake::Event(event) => self.apply(event)?,
                Wake::Storage(open) => {
                    if !open {
                        self.storage = None;
                    }
                }
                Wake::Terminal(open) => {
                    if !open {
                        self.last_turn = None;
                    }
                }
            }
        }
    }

    async fn park_cold(&mut self) -> Result<()> {
        tokio::select! { biased;
            _ = self.cancel.cancelled() => Err(core::ChatError::Cancelled.into()),
            _ = self.slot_changed.changed() => Err(resync()),
        }
    }

    async fn wait_wake(&mut self) -> Result<Wake> {
        enum Source {
            Feed(Result<ThreadLiveEvent, broadcast::error::RecvError>),
            Storage(bool),
            Terminal(bool),
        }
        // Split the watches before polling. One `&mut self` cannot be shared by the select arms.
        let woke = {
            let state = &mut self.state;
            let storage = &mut self.storage;
            let last_turn = &mut self.last_turn;
            let cancel = &self.cancel;
            let slot_changed = &mut self.slot_changed;
            tokio::select! { biased;
                _ = cancel.cancelled() => return Ok(Wake::Cancel),
                _ = slot_changed.changed() => return Ok(Wake::Slot),
                received = async {
                    match state.as_mut() {
                        Some(state) => state.recv().await,
                        None => std::future::pending().await,
                    }
                } => Source::Feed(received),
                changed = async {
                    match storage.as_mut() {
                        Some(storage) => storage.changed().await.is_ok(),
                        None => std::future::pending().await,
                    }
                } => Source::Storage(changed),
                changed = async {
                    match last_turn.as_mut() {
                        Some(terminal) => terminal.changed().await.is_ok(),
                        None => std::future::pending().await,
                    }
                } => Source::Terminal(changed),
            }
        };
        match woke {
            Source::Feed(Ok(event)) => Ok(Wake::Event(event)),
            Source::Feed(Err(broadcast::error::RecvError::Lagged(dropped))) => {
                self.lagged(dropped)?;
                Ok(Wake::Storage(true))
            }
            Source::Feed(Err(broadcast::error::RecvError::Closed)) => Ok(Wake::Closed),
            Source::Storage(open) => Ok(Wake::Storage(open)),
            Source::Terminal(open) => Ok(Wake::Terminal(open)),
        }
    }
}

enum Wake {
    Event(ThreadLiveEvent),
    Storage(bool),
    Terminal(bool),
    Slot,
    Cancel,
    Closed,
}

fn annotate_runtime_mode(
    runtime: &StudioRuntime,
    snapshot: &mut pl_protocol::ThreadRuntimeSnapshot,
) {
    if let Some(run) = snapshot
        .workflow
        .as_mut()
        .and_then(|workflow| workflow.current_run.as_mut())
    {
        run.mode_deleted = runtime.thread_modes.snapshot().mode(&run.mode_id).is_none();
    }
}

/// Live runtime observations may replace only an observation for the same model attempt.
pub(in crate::studio::runtime) fn same_live_runtime_identity(
    incoming: &pl_protocol::ThreadRuntimeSnapshot,
    previous: &pl_protocol::ThreadRuntimeSnapshot,
) -> bool {
    let Some(incoming_usage) = incoming.live_usage.as_ref() else {
        return false;
    };
    let Some(previous_usage) = previous.live_usage.as_ref() else {
        return false;
    };
    incoming_usage.state == pl_protocol::ThreadRuntimeUsageState::Live
        && previous_usage.state == pl_protocol::ThreadRuntimeUsageState::Live
        && incoming_usage.turn_id == previous_usage.turn_id
        && incoming_usage.attempt_id == previous_usage.attempt_id
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;
    use anyhow::Result;

    #[test]
    fn state_baseline_carries_qualified_plan_and_rejects_mixed_business_slice() -> Result<()> {
        use crate::studio::thread_projection::CurrentState;
        use pl_protocol::{AgentSessionPlanDocument, AgentSessionPlanPhase, AgentSessionPlanState};

        let text = "# The saved Plan\n\nKeep the business references consistent.";
        let mut plan = AgentSessionPlanState {
            revision: 3,
            state: AgentSessionPlanPhase::Approved,
            document: Some(AgentSessionPlanDocument {
                version: 3,
                markdown: text.into(),
                content_hash: crate::canonical_content_hash(text.as_bytes()),
            }),
            ..Default::default()
        };
        let mut state = pl_core::thread::ThreadSnapshot::default();
        state.extensions.insert(
            crate::plan_tool::PLAN_EXTENSION.into(),
            pl_core::thread::extensions::ExtensionRecord {
                revision: 3,
                payload: crate::plan_tool::encode_plan_state(&plan)?,
            },
        );
        let thread = pl_protocol::Thread::placeholder("state-baseline");
        let current = CurrentState::cold("state-db".into(), thread.id.clone(), 7, &state)?;
        let references = current.business_refs_at(&thread.id, &state)?;
        let snapshot = crate::studio::thread_projection::project_snapshot(
            thread.clone(),
            &state,
            &state.usage_summary,
            None,
            references.clone(),
        )?;
        assert_eq!(snapshot.business_refs, references);
        assert!(
            snapshot
                .business_refs
                .plan
                .as_ref()
                .unwrap()
                .document
                .is_some()
        );
        assert!(snapshot.business_refs.interactions.is_some());
        assert!(snapshot.activity.is_none());
        state.commit_sequence = 8;
        assert_eq!(current.business_refs_at(&thread.id, &state)?, references);
        plan.revision = 4;
        state
            .extensions
            .get_mut(crate::plan_tool::PLAN_EXTENSION)
            .unwrap()
            .payload = crate::plan_tool::encode_plan_state(&plan)?;
        assert!(matches!(
            current
                .business_refs_at(&thread.id, &state)
                .unwrap_err()
                .downcast_ref::<pl_core::chat::ChatError>(),
            Some(pl_core::chat::ChatError::StaleContent)
        ));
        Ok(())
    }
}
