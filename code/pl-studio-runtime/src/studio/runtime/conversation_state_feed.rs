//! Passive State observation. One assembler owns the snapshot and continuous notifications.
//!
//! Opening registers on the existing observation slot and reads cold history when no source is
//! installed. It never activates execution or waits for an execution workspace check.
use super::{
    StudioRuntime,
    conversation_reader::resync,
    thread_observation::{StateReceiver, ThreadLiveEvent},
};
use crate::studio::thread_projection::{LiveEvent, TurnEvent};
use anyhow::{Result, ensure};
use pl_core::chat as core;
use pl_protocol::{
    COMPLETED_HISTORY_VERSION, THREAD_SCHEMA_VERSION, ThreadActivity, ThreadBusinessRefs,
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

impl StudioRuntime {
    /// Opens a passive State feed. A missing execution owner stays missing.
    pub async fn open_conversation_state_feed(
        &self,
        thread_id: &str,
    ) -> Result<ConversationStateFeed> {
        let subscription_id = crate::studio::ids::new_id("state");
        let slot = self.thread_observations.observation_slot(thread_id);
        let (position, mut slot_changed) = slot.capture();
        let registered = position.source.as_ref().map(|source| {
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
        let mut cold_terminal = None;
        let mut annotate_route = false;
        let (effect_cut, active_turn, interactions, business_refs) = if let Some((
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
            let effect_cut = source.current.projection().source_effect_seq;
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
            let history = self.store.history(thread_id).await?;
            history.prepare_conversation_read().await?;
            let facet = history.cold_state_facet().await?;
            ensure!(slot.is_current(position.epoch), resync());
            match facet {
                Some(facet) => {
                    let effect_cut = facet.current.projection().source_effect_seq;
                    let active_turn = facet.current.active_turn().cloned();
                    let interactions = facet.current.interactions().to_vec();
                    let business_refs = facet.current.business_refs();
                    model_route = facet.model_route.map(|route| route.snapshot(false));
                    if let Some(saved) = facet.saved_state.as_ref() {
                        // Core resource shutdown is not permanent product Thread closure.
                        // Keep the directory status captured above, alongside this cold slice.
                        runtime = Some(
                            crate::studio::thread_projection::project_cold_runtime(
                                thread_id,
                                saved,
                                thread.updated_at,
                                &saved.usage_summary,
                            )
                            .map_err(anyhow::Error::from)?,
                        );
                    }
                    cold_terminal = facet.terminal_turn;
                    (effect_cut, active_turn, interactions, business_refs)
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
            interactions,
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
            cancel: CancellationToken::new(),
            runtime_owner: self.clone(),
            ended: false,
        };
        feed.push_frame_update(ThreadSubscriptionUpdate::Snapshot {
            completed_history_version: COMPLETED_HISTORY_VERSION,
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
    use anyhow::Context;
    use pl_core::context::ContextContent;
    use pl_core::thread::ThreadSnapshot;

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
        let mut state = ThreadSnapshot::default();
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
        // Unrelated Core progress does not invalidate the same business slice.
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

    /// Inject delayed status frames after a real persisted Thread is reopened.
    /// Its first snapshot must stand even if the projection worker was behind
    /// the core publication when a new receiver registered.
    #[tokio::test]
    async fn history_reopen_baseline_rejects_older_live_observations() -> Result<()> {
        let stage = std::cell::Cell::new("initialize");
        tokio::time::timeout(
            Duration::from_secs(30),
            history_reopen_case(&stage, HistoryReadCase::Live),
        )
        .await
        .with_context(|| format!("history reopen timed out during {}", stage.get()))?
    }

    #[tokio::test]
    async fn cold_state_snapshot_uses_saved_business_slice_without_owner() -> Result<()> {
        let stage = std::cell::Cell::new("initialize");
        tokio::time::timeout(
            Duration::from_secs(30),
            history_reopen_case(&stage, HistoryReadCase::Cold),
        )
        .await
        .with_context(|| format!("cold State read timed out during {}", stage.get()))?
    }

    #[tokio::test]
    async fn first_current_wait_closes_without_new_publication() -> Result<()> {
        close_first_current_cases(false).await
    }

    #[tokio::test]
    async fn first_current_wait_prefers_close_when_current_is_also_ready() -> Result<()> {
        close_first_current_cases(true).await
    }

    async fn close_first_current_cases(current_ready: bool) -> Result<()> {
        for shutdown in [false, true] {
            let stage = std::cell::Cell::new("initialize");
            tokio::time::timeout(
                Duration::from_secs(30),
                history_reopen_case(
                    &stage,
                    HistoryReadCase::CloseFirstCurrent {
                        shutdown,
                        current_ready,
                    },
                ),
            )
            .await
            .with_context(|| {
                format!(
                    "first-current close timed out during {} (shutdown={shutdown}, current_ready={current_ready})",
                    stage.get()
                )
            })??;
        }
        Ok(())
    }

    enum HistoryReadCase {
        Live,
        Cold,
        CloseFirstCurrent { shutdown: bool, current_ready: bool },
    }

    async fn history_reopen_case(
        stage: &std::cell::Cell<&'static str>,
        case: HistoryReadCase,
    ) -> Result<()> {
        use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
        use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
        use pl_model::model::ModelInfo;
        use pl_model::protocol::ProtocolEndpoint;

        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        // Anonymous loopback route, never called by this storage-only scenario.
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account_id = AccountId::new("observation-reopen")?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: "storage-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "Storage fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![ModelInfo::compatible(&route.model_id)],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
        let options = || crate::StudioRuntimeOptions {
            studio_home: Some(home.clone()),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        };
        let runtime = StudioRuntime::initialize(options()).await?;
        let project = runtime.open_project(&workspace).await?;
        let thread = runtime
            .create_thread(&project.id, "observation baseline")
            .await?;
        stage.set("settle initial observation");
        runtime
            .synchronize_thread_observation(&thread.id)
            .await
            .context("settle stored thread")?;
        let observer_progress = runtime
            .thread_observations
            .live_feed(&thread.id)
            .context("stored thread observer")?
            .conversation()
            .owner_progress;
        stage.set("initial shutdown");
        runtime.shutdown_runtime().await.with_context(|| {
            format!(
                "history observer shutdown; retained projection error: {:?}",
                observer_progress.borrow().retained_error()
            )
        })?;

        stage.set("reinitialize");
        let runtime = StudioRuntime::initialize(options()).await?;
        // Isolate the catalog-to-State projection before creating its execution owner.
        // Independent model/tool refresh legitimately enqueues Core updates on settings changes;
        // join those producers so the unchanged-revision assertion measures only this projection.
        runtime.stop_model_refresh().await?;
        runtime.stop_tool_refresh().await?;
        if let HistoryReadCase::CloseFirstCurrent {
            shutdown,
            current_ready,
        } = case
        {
            stage.set("prepare existing hot owner");
            runtime.ensure_thread_owner(&thread.id).await?;
            runtime.synchronize_thread_observation(&thread.id).await?;
            let slot = runtime.thread_observations.observation_slot(&thread.id);
            let original = slot.capture().0.source.context("original live feed")?;
            let source = original
                .current_conversation()
                .context("original current resource")?;
            // Keep the original execution owner, but hold back this feed's first resource value.
            // Neither closing signal needs the retained owner to publish or finish.
            let (owner_progress, progress) = watch::channel(Default::default());
            let delivery = tokio_util::sync::CancellationToken::new();
            let paused = Arc::new(super::super::thread_observation::ThreadLiveFeed::new(
                None,
                progress,
                delivery.clone(),
            ));
            slot.install(paused.clone());
            let entered = paused.arm_first_open_wait();
            let mut subscribing = Box::pin(runtime.open_conversation_state_feed(&thread.id));
            stage.set("await first-resource wait registration");
            tokio::select! {
                result = subscribing.as_mut() => {
                    anyhow::bail!("subscription ended before close: {}", result.is_ok());
                }
                entered = entered => entered.context("first-resource wait entered")?,
            }
            assert!(paused.current_conversation().is_none());
            assert!(!owner_progress.borrow().is_finished());
            let mut closing = shutdown.then(|| Box::pin(runtime.shutdown_runtime()));
            if let Some(closing) = closing.as_mut() {
                // shutdown arms before blocking on the lifecycle lock held by subscribing.
                assert!(futures::poll!(closing.as_mut()).is_pending());
                assert!(runtime.shutdown_latch.is_committed());
            } else {
                delivery.cancel();
                assert!(!runtime.shutdown_latch.is_committed());
            }
            if current_ready {
                // Both branches become ready before the subscription is polled again.
                paused.publish_test_conversation(&source.session, source.current.clone())?;
            }
            stage.set("close first-resource wait");
            let result = tokio::time::timeout(Duration::from_secs(5), subscribing.as_mut())
                .await
                .context("subscription did not leave first-resource wait on close")?;
            let Err(error) = result else {
                anyhow::bail!("closed first-resource wait returned a late subscription");
            };
            assert_eq!(
                error
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .and_then(|error| error.reason()),
                Some("conversationResyncRequired"),
                "{error:#}"
            );
            if !current_ready {
                assert!(paused.current_conversation().is_none());
            }
            assert!(!owner_progress.borrow().is_finished());
            drop(subscribing);
            slot.install(original);
            stage.set("join shutdown after first-resource cancellation");
            if let Some(closing) = closing {
                tokio::time::timeout(Duration::from_secs(5), closing)
                    .await
                    .context("shutdown did not acquire released lifecycle lock")??;
            } else {
                assert!(runtime.lifecycle_lock.try_lock().is_ok());
                runtime.shutdown_runtime().await?;
            }
            assert!(runtime.lifecycle_lock.try_lock().is_ok());
            return Ok(());
        }
        if matches!(case, HistoryReadCase::Cold) {
            stage.set("cold State snapshot without execution owner");
            assert!(
                runtime
                    .session_of(&thread.id)
                    .and_then(|session| session.observed_thread(&thread.id))
                    .is_none()
            );
            let (saved, references) = runtime
                .store
                .history(&thread.id)
                .await?
                .read_state_with_business_refs()
                .await?
                .context("saved State and business references")?;
            let snapshot = runtime.thread_snapshot(&thread.id).await?;
            assert_eq!(snapshot.revision, saved.commit_sequence);
            assert_eq!(snapshot.business_refs, references);
            assert!(snapshot.business_refs.interactions.is_some());
            assert!(snapshot.interactions.is_empty());
            assert!(snapshot.active_turn.is_none());
            assert!(snapshot.activity.is_none());
            assert!(
                runtime
                    .session_of(&thread.id)
                    .and_then(|session| session.observed_thread(&thread.id))
                    .is_none(),
                "cold State reading activated an execution owner"
            );
            assert_eq!(
                runtime
                    .store
                    .thread_persistence()
                    .usage(&thread.id)
                    .context("cold State seeded usage")?
                    .applied_sequence,
                saved.usage_summary.applied_sequence
            );
            stage.set("cold snapshot fixture shutdown");
            runtime.shutdown_runtime().await?;
            endpoint.set_nonblocking(true)?;
            assert!(
                matches!(endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
            );
            return Ok(());
        }
        stage.set("explicit admission before live observation");
        runtime.ensure_thread_owner(&thread.id).await?;
        runtime.synchronize_thread_observation(&thread.id).await?;
        let mut subscription = runtime
            .open_conversation_state_feed(&thread.id)
            .await
            .context("cold history subscribe")?;
        let (events, receiver) = broadcast::channel(16);
        let baseline = runtime
            .require_session(&thread.id)?
            .observed_thread(&thread.id)
            .context("explicitly activated owner")?
            .snapshot();
        let baseline_revision = subscription.runtime_floor.0;
        let original_feed = subscription
            .state
            .replace(StateReceiver::new(receiver, Default::default()));
        let catalog_revision = runtime.config_runtime.model_catalog_revision()?;
        let mut obsolete = crate::studio::thread_projection::project_runtime(
            &thread.id,
            &baseline,
            0,
            &baseline.usage_summary,
        )?;
        obsolete.progress = Some("obsolete before baseline".into());
        // These frames are queued before the first recv, at the exact boundary
        // already covered by its atomic source snapshot (including activity=None).
        events.send(ThreadLiveEvent::Runtime {
            observation_revision: baseline_revision,
            catalog_revision,
            runtime: Arc::new(obsolete),
            model_route: crate::studio::model_route::projected(&baseline)?,
        })?;
        events.send(ThreadLiveEvent::Activity {
            observation_revision: baseline_revision,
            activity: Some(Arc::new(pl_protocol::ThreadActivity {
                thread_id: thread.id.clone(),
                identity: "old-activity".into(),
                revision: 9,
                turn_id: Some("old-turn".into()),
                execution_id: None,
                input_id: None,
                attempt_id: None,
                kind: pl_protocol::ThreadActivityKind::Thinking,
                summary: "obsolete before baseline".into(),
                summary_truncated: false,
                thinking_summary: None,
                thinking_seconds: None,
                tools: Default::default(),
            })),
        })?;
        stage.set("first State baseline");
        let first = subscription
            .recv()
            .await?
            .context("first reopened snapshot")?;
        let ThreadSubscriptionUpdate::Snapshot { snapshot, .. } = first else {
            anyhow::bail!("first status frame was not a snapshot");
        };
        let source = runtime
            .thread_observations
            .live_feed(&thread.id)
            .and_then(|feed| feed.current_conversation())
            .context("baseline resource owner")?;
        assert_eq!(
            snapshot.business_refs,
            source.current.business_refs_at(&thread.id, &baseline)?
        );
        assert!(snapshot.business_refs.interactions.is_some());
        let initial = snapshot.runtime.context("runtime in first frame")?;
        assert!(
            snapshot
                .model_route
                .as_ref()
                .context("cold saved route")?
                .available
        );
        assert!(snapshot.active_turn.is_none());
        assert!(snapshot.activity.is_none());
        assert!(initial.progress.is_none());
        let handle = runtime
            .require_session(&thread.id)?
            .thread(&thread.id)
            .context("reopened owner")?;
        stage.set("patch runtime facts");
        let mut publications = handle.subscribe();
        let before = publications.next().await.context("owner baseline")?;
        handle
            .patch_runtime_facts(vec![pl_core::thread::RuntimeFact {
                source_id: "storage-observation".into(),
                content: vec![ContextContent::Text {
                    text: Arc::from("new stored fact"),
                }],
            }])
            .await?;
        let after = tokio::time::timeout(Duration::from_secs(5), publications.next())
            .await
            .context("stored fact publication")?
            .context("owner remains open")?;
        assert!(after.observation_revision > before.observation_revision);
        let mut current = initial;
        current.progress = Some("new observation".into());
        events.send(ThreadLiveEvent::Runtime {
            observation_revision: after.observation_revision,
            catalog_revision,
            runtime: Arc::new(current),
            model_route: crate::studio::model_route::projected(&baseline)?,
        })?;
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let frame = subscription.recv().await?.context("status stream ended")?;
                if let ThreadSubscriptionUpdate::Notification { notification } = frame {
                    match notification.notification {
                        ThreadNotification::ThreadRuntimeUpdated { runtime, .. } => {
                            assert_ne!(
                                runtime.progress.as_deref(),
                                Some("obsolete before baseline")
                            );
                            if runtime.progress.as_deref() == Some("new observation") {
                                break;
                            }
                        }
                        ThreadNotification::ActivityChanged { activity } => {
                            assert_ne!(
                                activity.as_deref().map(|a| a.identity.as_str()),
                                Some("old-activity")
                            );
                        }
                        _ => {}
                    }
                }
            }
            Ok::<_, anyhow::Error>(())
        })
        .await
        .context("delayed baseline frames")??;
        stage.set("same-sequence BusinessRefs in both orders");
        {
            let live = &mut subscription;
            // Baseline-covered references and unchanged later publications spend no revision.
            let revision = live.revision;
            let covered = live.business_refs_sequence;
            let references = live.business_refs.clone();
            live.apply(ThreadLiveEvent::BusinessRefs {
                sequence: covered,
                references: references.clone(),
            })?;
            live.apply(ThreadLiveEvent::BusinessRefs {
                sequence: covered + 1,
                references: references.clone(),
            })?;
            assert_eq!(live.revision, revision);
            // Both orders are legal: the Committed watermark must not swallow same-sequence refs,
            // and accepting refs must not swallow the corresponding committed lifecycle fact.
            for refs_first in [false, true] {
                let sequence = live.applied.max(live.business_refs_sequence) + 1;
                let mut changed = references.clone();
                changed
                    .interactions
                    .as_mut()
                    .context("interaction reference")?
                    .revision += sequence;
                let refs = ThreadLiveEvent::BusinessRefs {
                    sequence,
                    references: changed.clone(),
                };
                let committed = ThreadLiveEvent::Committed {
                    sequence,
                    changes: Vec::new(),
                };
                let revision = live.revision;
                let epoch = live.epoch;
                if refs_first {
                    live.apply(refs)?;
                    live.apply(committed)?;
                } else {
                    live.apply(committed)?;
                    live.apply(refs)?;
                }
                assert_eq!(live.applied, sequence);
                assert_eq!(live.revision, revision + 1);
                assert_eq!(live.epoch, epoch);
                assert!(matches!(
                    live.pending.back(),
                    Some(ThreadSubscriptionUpdate::Notification { notification })
                        if notification.base_revision == revision
                            && notification.revision == revision + 1
                            && matches!(
                                &notification.notification,
                                ThreadNotification::BusinessRefsChanged { references }
                                    if references == &changed
                            )
                ));
                live.apply(ThreadLiveEvent::BusinessRefs {
                    sequence,
                    references: changed,
                })?;
                live.apply(ThreadLiveEvent::BusinessRefs {
                    sequence: covered,
                    references: references.clone(),
                })?;
                assert_eq!(live.revision, revision + 1);
            }
            let revision = live.revision;
            let epoch = live.epoch;
            let pending = live.pending.len();
            live.apply(ThreadLiveEvent::UnframedCommit {
                sequence: live.applied,
            })?;
            assert_eq!(live.revision, revision);
            assert_eq!(live.epoch, epoch);
            assert_eq!(live.pending.len(), pending);
            live.apply(ThreadLiveEvent::UnframedCommit {
                sequence: live.applied + 1,
            })?;
            assert_eq!(live.epoch, epoch + 1);
            assert_eq!(live.pending.len(), 1);
            assert!(matches!(
                live.pending.front(),
                Some(ThreadSubscriptionUpdate::Notification { notification })
                    if matches!(&notification.notification, ThreadNotification::Lagged { dropped: 1 })
            ));
        }
        // Restore the real owner feed retained throughout the injection.
        {
            let live = &mut subscription;
            live.state = original_feed;
        }
        drop(subscription);
        stage.set("flush fixture");
        handle.flush().await?;
        stage.set("settle reconnect observation");
        runtime.synchronize_thread_observation(&thread.id).await?;
        stage.set("reconnect subscribe");
        let owner_revision = handle.snapshot().observation_revision;
        let mut subscription = runtime.open_conversation_state_feed(&thread.id).await?;
        stage.set("reconnect State baseline");
        let first = subscription.recv().await?.context("reconnected snapshot")?;
        let ThreadSubscriptionUpdate::Snapshot { snapshot, .. } = first else {
            anyhow::bail!("reconnect baseline missing");
        };
        snapshot.runtime.as_ref().context("reconnected runtime")?;
        assert!(snapshot.model_route.context("saved route")?.available);
        assert_eq!(handle.snapshot().observation_revision, owner_revision);
        let configured = runtime.config_runtime.read()?;
        runtime.set_account_model_enabled(pl_protocol::studio::SetAccountModelEnabledRequest {
            operation_id: "observation-disable-model".into(),
            expected_revision: configured.revision,
            account_id: route.account_id.to_string(),
            model_id: route.model_id.clone(),
            enabled: false,
        })?;
        assert!(runtime.config_runtime.model_catalog_revision()? > catalog_revision);
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let Some(ThreadSubscriptionUpdate::Notification { notification }) =
                    subscription.recv().await?
                    && let ThreadNotification::ThreadRuntimeUpdated { model_route, .. } =
                        notification.notification
                    && model_route.as_ref().is_some_and(|route| !route.available)
                {
                    break;
                }
            }
            Ok::<_, anyhow::Error>(())
        })
        .await
        .context("catalog-only availability notification")??;
        assert_eq!(handle.snapshot().observation_revision, owner_revision);
        drop(subscription);
        stage.set("final shutdown");
        runtime
            .shutdown_runtime()
            .await
            .context("history observer shutdown")?;
        endpoint.set_nonblocking(true)?;
        assert!(
            matches!(endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
        );
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn cold_state_reads_legacy_mode_without_requiring_its_original_graph() -> Result<()> {
        use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
        use sea_orm::{ConnectionTrait, Database};
        let mut env = support::Environment::new(
            vec![support::prompt_step(
                "legacy-mode-seed",
                0,
                support::text_reply("saved", "legacy-seed"),
            )],
            vec![],
        )
        .await?;
        let result = async {
            let thread = env
                .start(ThreadWorkspaceMode::Local, "legacy-mode-seed")
                .await?
                .thread;
            support::completed_prompt(&env.runtime, &thread.id, "legacy-mode-seed").await?;
            let history = env.runtime.store.history(&thread.id).await?;
            let path = env
                .runtime
                .store
                .registered_session_paths(&thread.id)?
                .history_database();
            env.runtime.shutdown_runtime().await?;
            let original = history.checkpoint().await?.context("saved checkpoint")?;
            let mut legacy = original.clone();
            let mode = legacy
                .state
                .extensions
                .get_mut("studio.mode")
                .context("saved Mode")?;
            let legacy_id = ThreadModeId::new("mode.retired-original")?;
            mode.payload = pl_core::context::OpaquePayload::new(
                "pl.studio.mode",
                1,
                serde_json::to_string(&legacy_id)?,
            )?;
            let workflow = WorkflowSessionState {
                current_run: Some(WorkflowRun {
                    lineage_id: "saved-lineage".into(),
                    run_id: "saved-run".into(),
                    mode_id: legacy_id,
                    graph_revision: 1,
                    graph_hash: "retired-original-graph".into(),
                    lifecycle: WorkflowRunLifecycle::Active,
                    current_state_id: "saved-state".into(),
                    started_at: 1,
                    updated_at: 2,
                    history_tail: vec![],
                    archived_transition_count: 0,
                    archived_transition_digest: String::new(),
                }),
                ..Default::default()
            };
            legacy.state.extensions.insert(
                "studio.workflow".into(),
                pl_core::thread::extensions::ExtensionRecord {
                    revision: 1,
                    payload: crate::workflow_tool::encode_workflow_state(&workflow)?,
                },
            );
            drop(history);
            let db = Database::connect(
                sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
            )
            .await?;
            // Freeze the published ID-only representation without changing unrelated checkpoint facts.
            let row = db
                .query_one_raw(sea_orm::Statement::from_string(
                    sea_orm::DatabaseBackend::Sqlite,
                    "SELECT payload FROM session_checkpoint WHERE id=1",
                ))
                .await?
                .context("saved envelope")?;
            let mut payload: serde_json::Value =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
            payload["state"]["extensions"]["studio.mode"] =
                serde_json::to_value(&legacy.state.extensions["studio.mode"])?;
            payload["state"]["extensions"]["studio.workflow"] =
                serde_json::to_value(&legacy.state.extensions["studio.workflow"])?;
            let payload = serde_json::to_string(&payload)?;
            db.execute_raw(sea_orm::Statement::from_sql_and_values(
                sea_orm::DatabaseBackend::Sqlite,
                "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
                [
                    payload.clone().into(),
                    pl_core::context::content_hash(payload.as_bytes()).into(),
                ],
            ))
            .await?;
            db.close().await?;
            env.restart().await?;
            for _ in 0..2 {
                let mut feed = env.runtime.open_conversation_state_feed(&thread.id).await?;
                let snapshot = state_snapshot(&mut feed).await?;
                assert_eq!(snapshot.thread.id, thread.id);
                let run = snapshot
                    .runtime
                    .as_ref()
                    .context("runtime")?
                    .workflow
                    .as_ref()
                    .context("workflow")?
                    .current_run
                    .as_ref()
                    .context("run")?;
                assert_eq!(run.graph_hash, "retired-original-graph");
                assert!(run.mode_display_name.is_empty() && run.current_state_title.is_empty());
                assert!(
                    env.runtime
                        .session_of(&thread.id)
                        .and_then(|session| session.observed_thread(&thread.id))
                        .is_none()
                );
                feed.close().await?;
                let history = env.runtime.store.history(&thread.id).await?;
                let migrated = history.checkpoint().await?.context("durable checkpoint")?;
                assert_eq!(
                    migrated.state.extensions["studio.mode"],
                    legacy.state.extensions["studio.mode"]
                );
                assert_eq!(
                    migrated.state.extensions["studio.workflow"],
                    legacy.state.extensions["studio.workflow"]
                );
                assert_eq!(migrated.state_revision, original.state_revision);
                assert_eq!(migrated.history_fence, original.history_fence);
                assert_eq!(migrated.state.context, original.state.context);
                env.restart().await?;
            }
            assert_eq!(
                env.root_provider.recorded().len(),
                1,
                "cold reads cannot issue model requests"
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    use super::*;
    use crate::runtime_test_support as support;
    use crate::studio::runtime::conversation_feed::tests::{completed_runs, state_snapshot};
    use anyhow::{Context, Result, bail};
    use pl_protocol::*;
    use std::time::Duration;

    #[tokio::test]
    async fn state_only_cold_open_prepares_supported_history_without_execution() -> Result<()> {
        use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
        use crate::studio::storage::history::{HistoryStore, discard_empty_demand_fixture};
        use sea_orm::{ConnectionTrait, Database};

        let mut env = support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "state-only migration")
                .await?;
            let path = env
                .runtime
                .store
                .registered_session_paths(&thread.id)?
                .history_database();
            env.runtime.shutdown_runtime().await?;
            let history = HistoryStore::open(&path, &thread.id).await?;
            let saved_sequence = history.watermark().await?;
            let saved_checkpoint =
                serde_json::to_value(history.checkpoint().await?.context("created checkpoint")?)?;
            drop(history);

            // Match the supported-v2 fixture at the original storage boundary.
            // This isolated history has no completion outputs to discard.
            let db = Database::connect(
                sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
            )
            .await?;
            discard_empty_demand_fixture(&db).await?;
            db.execute_unprepared(
                "DROP TABLE seaql_migrations;
             DROP TABLE timeline_records;
             ALTER TABLE history_input_identities DROP COLUMN request_digest;
             UPDATE history_meta SET schema_version=8",
            )
            .await?;
            db.close().await?;
            env.restart().await?;
            assert!(
                env.runtime
                    .session_of(&thread.id)
                    .and_then(|session| session.observed_thread(&thread.id))
                    .is_none()
            );
            let history = env.runtime.store.history(&thread.id).await?;
            assert!(
                history.cold_state_facet().await.is_err(),
                "fixture must still require supported-history preparation"
            );

            // No content feed or execution admission may prepare this for State.
            let mut state = env.runtime.open_conversation_state_feed(&thread.id).await?;
            let snapshot = state_snapshot(&mut state).await?;
            assert_eq!(snapshot.thread.id, thread.id);
            assert!(snapshot.active_turn.is_none() && snapshot.activity.is_none());
            assert!(
                env.runtime
                    .session_of(&thread.id)
                    .and_then(|session| session.observed_thread(&thread.id))
                    .is_none()
            );
            assert_eq!(env.root_provider.recorded().len(), 0);
            assert_eq!(
                serde_json::to_value(history.checkpoint().await?.context("prepared checkpoint")?)?,
                saved_checkpoint
            );
            assert_eq!(history.watermark().await?, saved_sequence);
            state.close().await?;
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn unconsumed_content_does_not_delay_final_state_and_cold_statistics() -> Result<()> {
        use crate::config::{ConfigPaths, ConfigStore};
        use crate::studio::runtime::conversation_feed::tests::demand;
        use pl_model::{
            config::{AccountId, AccountModelCatalogConfig},
            model::{ModelPricing, TokenPriceTier},
        };
        use pl_provider_fixture::ReplyStage;

        let stage = ReplyStage::new();
        let mut env = support::Environment::new(
            vec![support::prompt_step(
                "independent-state",
                0,
                support::held_reply(&stage, "state-response"),
            )],
            vec![],
        )
        .await?;
        let phase = std::cell::Cell::new("configure");
        let result = tokio::time::timeout(Duration::from_secs(45), async {
        let store = ConfigStore::new(ConfigPaths::from_config_dir(&env.home));
        let mut config = store.load()?;
        let account = config
            .models
            .accounts
            .get_mut(&AccountId::new("root-fixture")?)
            .context("fixture account")?;
        let AccountModelCatalogConfig::Explicit { models, .. } = &mut account.catalog else {
            bail!("expected explicit fixture catalog");
        };
        let model = models
            .iter_mut()
            .find(|model| model.model_id == support::MODEL)
            .context("fixture model")?;
        model.context_window = Some(128_000);
        model.max_context_window = Some(256_000);
        model.pricing = ModelPricing::Rates {
            currency: "USD".into(),
            tiers: vec![TokenPriceTier::flat(1.0, 2.0, Some(0.1), None)],
            weekly_adjustment: None,
            source: "state regression".into(),
            verified_at: 1,
        };
        store.save(&config)?;
        phase.set("restart configured fixture");
        env.restart().await?;
        phase.set("admit prompt");
        let started = env
            .start(ThreadWorkspaceMode::Local, "independent-state")
            .await?;
        let id = &started.thread.id;
        phase.set("provider stage");
        support::reached(&stage).await?;
        // The fixture gate proves provider admission, not projection progress.
        // Settle the known running cut before checking its baseline.
        env.runtime.synchronize_thread_observation(id).await?;
        phase.set("open content");
        let mut content = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        phase.set("open State");
        let mut state = env.runtime.open_conversation_state_feed(id).await?;
        assert_eq!(state.thread_id(), id);
        assert_ne!(state.subscription_id(), content.subscription_id());
        let baseline = state_snapshot(&mut state).await?;
        let turn_id = baseline.active_turn.context("running baseline")?.id;
        let mut revision = baseline.revision;
        let mut epoch = 1;
        stage.release();
        phase.set("final State");
        // Do not poll content at all, including its initial Set/Activity. There is
        // no subsequent prompt or activity publication to flush a lost final value.
        let final_runtime = tokio::time::timeout(Duration::from_secs(20), async {
            let mut terminal = false;
            let mut durable = None;
            loop {
                let update = state
                    .recv()
                    .await?
                    .context("State ended before terminal statistics")?;
                let ThreadSubscriptionUpdate::Notification { notification } = update else {
                    bail!("unexpected second baseline");
                };
                assert_eq!(notification.thread_id, *id);
                assert_eq!(notification.epoch, epoch);
                assert_eq!(notification.base_revision, revision);
                assert_eq!(notification.revision, revision + 1);
                revision = notification.revision;
                epoch = notification.epoch;
                match notification.notification {
                    ThreadNotification::TurnCompleted { turn } => {
                        assert_eq!(turn.id, turn_id);
                        assert!(matches!(turn.state, TurnState::Completed(_)));
                        terminal = true;
                    }
                    ThreadNotification::ThreadRuntimeUpdated { runtime, .. }
                        if runtime.live_usage.is_none() && runtime.usage.completion_tokens == 5 =>
                    {
                        durable = Some(*runtime);
                    }
                    ThreadNotification::Lagged { .. } => bail!("finite State script lost frames"),
                    _ => {}
                }
                if terminal && let Some(runtime) = durable.take() {
                    break Ok::<_, anyhow::Error>(runtime);
                }
            }
        })
        .await
        .context("final State required unrelated future content")??;
        assert_eq!(final_runtime.usage.prompt_tokens, 11);
        assert_eq!(final_runtime.usage.total_tokens, 16);
        assert!(final_runtime.usage.latest_context_tokens > 0);
        assert!(!final_runtime.usage.estimated_costs.is_empty());
        assert_eq!(final_runtime.turn_completion_tokens, 5);
        assert!(final_runtime.turn_response_millis > 0);
        state.close().await?;
        assert!(state.cancellation_token().is_cancelled());
        assert!(!content.cancellation_token().is_cancelled());
        assert!(
            matches!(
                content.recv().await?,
                Some(crate::studio::ConversationEvent::Chat { batch })
                    if batch.placement == ChatPlacement::Set
            ),
            "closing State invalidated the independently owned content feed"
        );
        content.close().await?;
        content.reader().close().await?;
        phase.set("flush executed owner");
        env.runtime
            .require_session(id)?
            .observed_thread(id)
            .context("executed owner")?
            .flush()
            .await?;
        phase.set("cold restart");
        env.restart().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none()
        );
        let requests = env.root_provider.recorded().len();
        let directory = env
            .runtime
            .store
            .read_thread(id)
            .await?
            .context("retained product directory")?;
        assert_eq!(directory.status, ThreadStatus::Idle);
        let saved = env
            .runtime
            .store
            .history(id)
            .await?
            .checkpoint()
            .await?
            .context("owner shutdown checkpoint")?;
        assert_eq!(saved.state.lifecycle, pl_core::thread::ThreadLifecycle::Closed);
        assert_eq!(
            crate::studio::thread_projection::status(&saved.state),
            ThreadStatus::Closed,
            "the old direct Core-lifecycle projection would fail the product-status assertions below"
        );
        assert!(!crate::studio::agent_close::is_explicitly_closed(&saved.state)?);
        assert!(env.runtime.store.agent_close(id).await?.is_none());
        phase.set("cold State");
        let mut cold = env.runtime.open_conversation_state_feed(id).await?;
        let snapshot = state_snapshot(&mut cold).await?;
        assert_eq!(
            snapshot.thread.status, directory.status,
            "a saved Closed Core owner must not permanently close the product Thread"
        );
        assert!(snapshot.active_turn.is_none() && snapshot.activity.is_none());
        assert!(snapshot.business_refs.interactions.is_some());
        let one_shot = env.runtime.thread_snapshot(id).await?;
        assert_eq!(
            one_shot.thread.status, directory.status,
            "one-shot and State must expose the same resumable product status"
        );
        assert_eq!(one_shot.business_refs, snapshot.business_refs);
        assert_eq!(one_shot.active_turn, snapshot.active_turn);
        assert_eq!(
            one_shot.runtime.as_ref().context("cold one-shot runtime")?,
            snapshot.runtime.as_ref().context("cold State runtime")?
        );
        let runtime = snapshot.runtime.context("cold saved runtime missing")?;
        assert!(runtime.live_usage.is_none());
        let mut expected_usage = final_runtime.usage;
        expected_usage.updated_at = runtime.usage.updated_at;
        assert_eq!(runtime.usage, expected_usage);
        assert_eq!(
            runtime.turn_completion_tokens,
            final_runtime.turn_completion_tokens
        );
        assert_eq!(
            runtime.turn_response_millis,
            final_runtime.turn_response_millis
        );
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none(),
            "cold State activated execution"
        );
        assert_eq!(env.root_provider.recorded().len(), requests);
        cold.request_close();
        assert!(matches!(
            cold.recv()
                .await
                .unwrap_err()
                .downcast_ref::<core::ChatError>(),
            Some(core::ChatError::Cancelled)
        ));
        cold.close().await?;
        Ok(())
    })
    .await
    .with_context(|| format!("State scenario timed out during {}", phase.get()))
    .and_then(std::convert::identity);
        stage.release();
        if let Err(error) = &result {
            eprintln!("State scenario failed during {}: {error:#}", phase.get());
        }
        env.finish(result).await
    }

    #[tokio::test]
    async fn permanent_child_close_intent_stays_read_only_in_cold_state_and_one_shot() -> Result<()>
    {
        use pl_provider_fixture::{Protocol, ReplyStage, Step};

        let spawned = ReplyStage::new();
        let child_running = ReplyStage::new();
        let mut env = support::Environment::new(
            vec![
                support::prompt_step(
                    "cold-close-parent",
                    0,
                    support::spawn_reply("cold-close-spawn", "cold-close-child"),
                ),
                Step::tool_output(
                    Protocol::ResponsesHttp,
                    "cold-close-spawn",
                    "agentId",
                    1,
                    support::held_reply(&spawned, "spawned"),
                ),
            ],
            vec![support::prompt_step(
                "cold-close-child",
                0,
                support::held_reply(&child_running, "child response"),
            )],
        )
        .await?;
        let result = tokio::time::timeout(Duration::from_secs(45), async {
            let root = env
                .start(ThreadWorkspaceMode::Local, "cold-close-parent")
                .await?;
            support::reached(&spawned).await?;
            support::reached(&child_running).await?;
            let receipt = support::receipt(&env.root_provider, "cold-close-spawn")?;
            let id = support::child_id(&receipt)?.to_owned();
            let child = env.runtime.read_protocol_thread(&id).await?;
            let session = env.runtime.require_session(&id)?;
            let handle = session.observed_thread(&id).context("real spawned child")?;
            let operation = session.agent_operation(&root.thread.id).await;
            let close = env
                .runtime
                .thread_factory
                .begin_child_close(&child, Some(&handle.snapshot()), false)
                .await?;
            assert!(!close.execution_closed);
            drop(operation);
            drop(handle);
            drop(session);
            spawned.release();
            support::completed_prompt(&env.runtime, &root.thread.id, "cold-close-parent").await?;
            // Stop between the durable business seal and its later execution-close ACK.
            // The ordinary host shutdown must not complete or erase that permanent intent.
            env.restart().await?;
            let requests = (
                env.root_provider.recorded().len(),
                env.child_provider.recorded().len(),
            );
            assert!(
                env.runtime
                    .session_of(&id)
                    .and_then(|s| s.observed_thread(&id))
                    .is_none()
            );
            assert_eq!(
                env.runtime.store.agent_close(&id).await?,
                Some(close.clone())
            );
            let directory = env
                .runtime
                .store
                .read_thread(&id)
                .await?
                .context("closed child directory")?;
            assert_eq!(directory.status, ThreadStatus::Closing);
            let mut feed = env.runtime.open_conversation_state_feed(&id).await?;
            let state = state_snapshot(&mut feed).await?;
            let one_shot = env.runtime.thread_snapshot(&id).await?;
            eprintln!(
                "COLD_CLOSE_STATUS directory={:?} state={:?} one_shot={:?} execution_closed={}",
                directory.status,
                state.thread.status,
                one_shot.thread.status,
                close.execution_closed
            );
            assert!(state.active_turn.is_none() && state.activity.is_none());
            assert_eq!(one_shot.business_refs, state.business_refs);
            feed.close().await?;
            assert!(
                env.runtime.ensure_thread_owner(&id).await.is_err(),
                "a cold read must not turn a permanent child close into execution permission"
            );
            assert!(
                env.runtime
                    .session_of(&id)
                    .and_then(|s| s.observed_thread(&id))
                    .is_none()
            );
            assert_eq!(
                env.runtime.store.agent_close(&id).await?,
                Some(close.clone())
            );
            assert_eq!(
                (
                    env.root_provider.recorded().len(),
                    env.child_provider.recorded().len()
                ),
                requests,
                "cold observations and rejected execution cannot issue a model request"
            );
            anyhow::ensure!(
                state.thread.status == directory.status
                    && one_shot.thread.status == directory.status,
                "cold close status disagrees: directory={:?}, State={:?}, one-shot={:?}",
                directory.status,
                state.thread.status,
                one_shot.thread.status
            );
            // Resume the original close coordinator, not an execution/model owner. It
            // must join the saved child and original parent-report acknowledgement
            // before finish_child_execution can persist the true completion bit.
            let coordinator = env
                .runtime
                .sessions
                .materialize(&SessionId::new(root.thread.id.clone())?)?;
            coordinator.resume_agent_closes().await?;
            drop(coordinator);
            let finished = env
                .runtime
                .store
                .agent_close(&id)
                .await?
                .context("finished close ACK")?;
            assert!(finished.execution_closed);
            assert!(finished.revision > close.revision);
            for reopen in [false, true] {
                if reopen {
                    env.restart().await?;
                }
                assert_eq!(
                    env.runtime.store.agent_close(&id).await?,
                    Some(finished.clone())
                );
                let directory = env
                    .runtime
                    .store
                    .read_thread(&id)
                    .await?
                    .context("finished directory")?;
                let mut feed = env.runtime.open_conversation_state_feed(&id).await?;
                let state = state_snapshot(&mut feed).await?;
                let one_shot = env.runtime.thread_snapshot(&id).await?;
                assert_eq!(directory.status, ThreadStatus::Closed);
                assert_eq!(state.thread.status, directory.status);
                assert_eq!(one_shot.thread.status, directory.status);
                assert_eq!(one_shot.business_refs, state.business_refs);
                assert!(state.active_turn.is_none() && state.activity.is_none());
                feed.close().await?;
                assert!(env.runtime.ensure_thread_owner(&id).await.is_err());
                assert!(
                    env.runtime
                        .session_of(&id)
                        .and_then(|s| s.observed_thread(&id))
                        .is_none()
                );
                assert_eq!(
                    (
                        env.root_provider.recorded().len(),
                        env.child_provider.recorded().len()
                    ),
                    requests,
                    "close recovery and cold reads cannot execute the model"
                );
            }
            Ok(())
        })
        .await
        .context("permanent-close cold observation timed out")
        .and_then(std::convert::identity);
        spawned.release();
        child_running.release();
        env.finish(result).await
    }

    #[tokio::test]
    async fn retained_terminal_state_requires_coverage_and_no_active_turn_and_is_deduplicated()
    -> Result<()> {
        let env = support::Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "retained State qualification")
                .await?;
            let mut feed = env.runtime.open_conversation_state_feed(&thread.id).await?;
            let _snapshot = feed.recv().await?.context("initial State snapshot")?;
            assert!(feed.pending.is_empty());
            let uncovered = feed
                .applied
                .checked_add(1)
                .context("test State cut exhausted")?;
            let terminal = Turn {
                input_id: Some("original-input".into()),
                id: "original-turn".into(),
                thread_id: thread.id.clone(),
                revision: uncovered,
                state: TurnState::Completed(CompletedTurnState::new(
                    Some(1),
                    2,
                    TurnCompletion::Normal,
                )),
                updated_at: 2,
            };
            let revision = feed.revision;
            feed.reflect_terminal(terminal.clone())?;
            assert!(feed.pending.is_empty(), "future terminal crossed the cut");
            assert_eq!(feed.revision, revision);

            feed.applied = terminal.revision;
            feed.active_turn = Some("newer-active-turn".into());
            feed.reflect_terminal(terminal.clone())?;
            assert!(feed.pending.is_empty(), "older terminal hid an active Turn");
            assert_eq!(feed.revision, revision);

            feed.active_turn = None;
            feed.reflect_terminal(terminal.clone())?;
            assert_eq!(feed.pending.len(), 1);
            assert_eq!(feed.revision, revision + 1);
            feed.reflect_terminal(terminal.clone())?;
            feed.apply(ThreadLiveEvent::Committed {
                sequence: terminal.revision + 1,
                changes: vec![LiveEvent::Turn {
                    turn: terminal.clone(),
                    event: TurnEvent::Completed,
                }],
            })?;
            assert_eq!(
                feed.pending.len(),
                1,
                "retained/live duplicate spent a frame"
            );
            assert_eq!(feed.revision, revision + 1);

            let newer = Turn {
                revision: terminal.revision + 1,
                ..terminal
            };
            feed.reflect_terminal(newer)?;
            assert_eq!(feed.pending.len(), 2, "newer same-Turn fact was suppressed");
            assert_eq!(feed.revision, revision + 2);
            feed.apply(ThreadLiveEvent::UnframedCommit {
                sequence: feed.applied,
            })?;
            assert_eq!(feed.pending.len(), 2, "covered gap spent a State frame");
            assert_eq!(feed.revision, revision + 2);
            for _ in 0..2 {
                assert!(matches!(
                    feed.recv().await?,
                    Some(ThreadSubscriptionUpdate::Notification { .. })
                ));
            }
            let (events, state) = tokio::sync::broadcast::channel(1);
            feed.state = Some(StateReceiver::new(state, Default::default()));
            events.send(ThreadLiveEvent::UnframedCommit {
                sequence: feed.applied + 1,
            })?;
            let update = feed
                .recv()
                .await?
                .context("uncovered gap must publish Lagged")?;
            assert!(
                matches!(update, ThreadSubscriptionUpdate::Notification { notification }
            if notification.epoch == 2
                && matches!(notification.notification, ThreadNotification::Lagged { dropped: 1 }))
            );
            feed.close().await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        env.finish(result).await
    }

    mod coalescing {
        use super::*;

        fn runtime_update(
            thread_id: &str,
            turn_id: &str,
            attempt_id: &str,
            state: ThreadRuntimeUsageState,
            sequence: u64,
        ) -> Result<ThreadNotification> {
            let mut runtime = crate::studio::thread_projection::project_runtime(
                thread_id,
                &Default::default(),
                sequence as i64,
                &Default::default(),
            )?;
            runtime.live_usage = Some(ThreadRuntimeLiveUsage {
                turn_id: turn_id.into(),
                attempt_id: attempt_id.into(),
                completion_tokens: Some(sequence),
                response_millis: Some(sequence * 10),
                latest_context_tokens: None,
                state,
                observation_sequence: sequence,
            });
            runtime.progress = Some(format!("progress-{sequence}"));
            Ok(ThreadNotification::ThreadRuntimeUpdated {
                runtime: Box::new(runtime),
                model_route: Some(ThreadModelRouteSnapshot {
                    bot_id: None,
                    account_id: "coalescing-account".into(),
                    model_id: format!("model-{sequence}"),
                    effort: None,
                    revision: sequence,
                    available: true,
                    unavailable_reason: None,
                }),
            })
        }

        fn runtime_event(notification: &ThreadNotification, revision: u64) -> ThreadLiveEvent {
            let ThreadNotification::ThreadRuntimeUpdated {
                runtime,
                model_route,
            } = notification
            else {
                panic!("expected Runtime test input");
            };
            ThreadLiveEvent::Runtime {
                runtime: Arc::new((**runtime).clone()),
                model_route: model_route.clone(),
                observation_revision: revision,
                catalog_revision: revision,
            }
        }

        #[tokio::test]
        async fn bounded_scan_coalesces_live_runtime_without_crossing_state_or_identity_boundaries()
        -> Result<()> {
            use ThreadRuntimeUsageState::{Authoritative, Live};
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut harness = completed_runs::Harness::new(&env).await?;
                harness.effect(vec![], vec![]).await?;
                let mut feed = env
                    .runtime
                    .open_conversation_state_feed(&harness.thread.id)
                    .await?;
                let snapshot = state_snapshot(&mut feed).await?;
                let mut turn = snapshot.active_turn.context("running Turn baseline")?;
                let base_revision = feed.revision;
                let effect_floor = feed.applied;
                let runtime_floor = feed.runtime_floor.0.max(feed.runtime_floor.1);
                let (events, state) = broadcast::channel(64);
                feed.state = Some(StateReceiver::new(state, CancellationToken::new()));

                let mut expected = Vec::new();
                for (index, (turn_id, attempt_id, usage_state)) in [
                    ("turn-a", "attempt-a", Live),
                    ("turn-a", "attempt-a", Live),
                    ("turn-a", "attempt-a", Live),
                    ("turn-a", "attempt-a", Live),
                    ("turn-a", "attempt-a", Live),
                    ("turn-a", "attempt-a", Live),
                    ("turn-b", "attempt-a", Live),
                    ("turn-b", "attempt-b", Live),
                    ("turn-b", "attempt-b", Authoritative),
                    ("turn-b", "attempt-b", Authoritative),
                    ("turn-b", "attempt-b", Live),
                    ("turn-b", "attempt-b", Live),
                ]
                .into_iter()
                .enumerate()
                {
                    let sequence = index as u64 + 1;
                    let notification = runtime_update(
                        &harness.thread.id,
                        turn_id,
                        attempt_id,
                        usage_state,
                        sequence,
                    )?;
                    events.send(runtime_event(&notification, runtime_floor + sequence))?;
                    events.send(ThreadLiveEvent::Activity {
                        observation_revision: runtime_floor + sequence,
                        activity: None,
                    })?;
                    if [2, 4, 6, 7, 8, 9, 10, 12].contains(&sequence) {
                        expected.push(notification);
                    }
                    let change = match sequence {
                        2 => {
                            turn.revision = effect_floor + 1;
                            expected.push(ThreadNotification::TurnUpdated { turn: turn.clone() });
                            Some(LiveEvent::Turn {
                                turn: turn.clone(),
                                event: TurnEvent::Updated,
                            })
                        }
                        4 => {
                            let interaction = Box::new(InteractionRequest::user_input(
                                "coalescing-interaction",
                                InteractionScope {
                                    thread_id: harness.thread.id.clone(),
                                    turn_id: turn.id.clone(),
                                    item_id: None,
                                    tool_id: None,
                                    agent_path: None,
                                    purpose: InteractionPurpose::General,
                                },
                                vec![],
                                1,
                            ));
                            expected.push(ThreadNotification::InteractionChanged {
                                interaction: interaction.clone(),
                            });
                            Some(LiveEvent::Interaction(interaction))
                        }
                        _ => None,
                    };
                    if let Some(change) = change {
                        events.send(ThreadLiveEvent::Committed {
                            sequence: effect_floor + sequence / 2,
                            changes: vec![change],
                        })?;
                    }
                }
                for (index, notification_expected) in expected.iter().enumerate() {
                    let Some(update) = feed.recv().await? else {
                        bail!("missing ordered State frame {index}");
                    };
                    if index == 0 {
                        assert_eq!(feed.state.as_ref().unwrap().len(), 0, "scan stopped early");
                        assert_eq!(feed.pending.len(), expected.len() - 1);
                        assert_eq!(feed.revision, base_revision + expected.len() as u64);
                    }
                    let ThreadSubscriptionUpdate::Notification { notification } = update else {
                        bail!("unexpected State snapshot");
                    };
                    assert_eq!(notification.base_revision, base_revision + index as u64);
                    assert_eq!(notification.revision, base_revision + index as u64 + 1);
                    assert_eq!(&notification.notification, notification_expected);
                }
                assert!(feed.pending.is_empty());

                // A successful tail replacement refreshes time, but keeps both envelope revisions
                // and the subscription watermark. Compare the whole payload, including model_route.
                let first =
                    runtime_update(&harness.thread.id, "tail-turn", "tail-attempt", Live, 20)?;
                feed.enqueue(first)?;
                let Some(ThreadSubscriptionUpdate::Notification { notification: tail }) =
                    feed.pending.back_mut()
                else {
                    bail!("missing pending tail");
                };
                tail.emitted_at = -1;
                let revisions = (tail.base_revision, tail.revision, feed.revision);
                let latest =
                    runtime_update(&harness.thread.id, "tail-turn", "tail-attempt", Live, 21)?;
                feed.enqueue(latest.clone())?;
                assert_eq!(feed.pending.len(), 1);
                let Some(ThreadSubscriptionUpdate::Notification { notification: tail }) =
                    feed.pending.back()
                else {
                    bail!("missing replaced tail");
                };
                assert_eq!(tail.notification, latest);
                assert!(tail.emitted_at >= 0);
                assert_eq!(
                    (tail.base_revision, tail.revision, feed.revision),
                    revisions
                );
                feed.close().await?;
                Ok::<_, anyhow::Error>(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn bounded_scan_preserves_budget_and_raw_channel_failures() -> Result<()> {
            use ThreadRuntimeUsageState::{Authoritative, Live};
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "State bounds")
            .await?;
        for case in ["replacement-bytes", "pending-frames", "lagged", "closed"] {
            let mut feed = env
                .runtime
                .open_conversation_state_feed(&thread.id)
                .await?;
            let _snapshot = state_snapshot(&mut feed).await?;
            let revision = feed.revision;
            let floor = feed.runtime_floor.0.max(feed.runtime_floor.1);
            let (events, state) = broadcast::channel(if case == "lagged" { 2 } else { 128 });
            feed.state = Some(StateReceiver::new(
                state,
                CancellationToken::new(),
            ));

            if case == "pending-frames" {
                for sequence in 1..=PENDING_FRAMES as u64 + 1 {
                    feed.enqueue(runtime_update(&thread.id, "bounded-turn", "bounded-attempt", Authoritative, sequence)?)?;
                }
                let update = feed.recv().await?.context("overflow must publish Lagged")?;
                assert!(matches!(update, ThreadSubscriptionUpdate::Notification { notification }
                    if notification.epoch == 2
                        && matches!(notification.notification, ThreadNotification::Lagged { dropped } if dropped == PENDING_FRAMES as u64)));
            } else {
                let frames = match case {
                    "replacement-bytes" => 2,
                    "lagged" => 3,
                    "closed" => 0,
                    _ => unreachable!(),
                };
                for sequence in 1..=frames {
                    let mut notification = runtime_update(&thread.id, "bounded-turn", "bounded-attempt", Live, sequence)?;
                    if case == "replacement-bytes" && sequence == 2
                        && let ThreadNotification::ThreadRuntimeUpdated { runtime, .. } = &mut notification {
                        runtime.progress = Some("x".repeat(PENDING_BYTES));
                    }
                    events.send(runtime_event(&notification, floor + sequence))?;
                }
                drop(events);
                match case {
                    "replacement-bytes" => {
                        let error = feed.recv().await.expect_err(case);
                        assert_eq!(error.downcast_ref::<pl_protocol::studio::StudioError>().and_then(|error| error.reason()), Some("conversationResyncRequired"));
                        assert!(feed.cancellation_token().is_cancelled());
                        assert_eq!(feed.revision, revision + 1, "replacement spent a revision");
                    }
                    "lagged" => {
                        let update = feed.recv().await?.context("channel loss must publish Lagged")?;
                        assert!(matches!(update, ThreadSubscriptionUpdate::Notification { notification }
                            if notification.epoch == 2
                                && matches!(notification.notification, ThreadNotification::Lagged { dropped: 1 })));
                    }
                    "closed" => assert!(feed.recv().await?.is_none()),
                    _ => unreachable!(),
                }
            }
            feed.close().await?;
            }
        Ok::<_, anyhow::Error>(())
    }
    .await;
            env.finish(result).await
        }
    }
}
