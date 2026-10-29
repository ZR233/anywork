//! Process-wide observation and retry coordination for per-Thread persistence sinks.

use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use anyhow::{Result, bail};
use pl_core::chat::{Session, WeakSession};
use pl_core::thread::UsageSummary;
use tokio::sync::{Notify, watch};

use crate::studio::storage::history::{HistoryStore, HistoryStoreShare};
use crate::studio::storage::thread_writer::HistoryChannel;

/// Per-Thread persistence watermarks and queue pressure reported by the owning writer.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct ThreadPersistenceMetrics {
    pub(crate) fault_generation: u64,
    pub(crate) fault: Option<pl_protocol::studio::HistoryFault>,
    pub(crate) state_dirty_revision: u64,
    pub(crate) state_saving_revision: u64,
    pub(crate) state_durable_revision: u64,
    pub(crate) history_admitted_sequence: u64,
    pub(crate) history_durable_sequence: u64,
    pub(crate) calls_admitted_sequence: u64,
    pub(crate) calls_durable_sequence: u64,
    pub(crate) pending_operations: u64,
    pub(crate) pending_bytes: u64,
    pub(crate) in_flight_bytes: u64,
    pub(crate) oldest_pending_age_millis: Option<u64>,
    pub(crate) pressure_paused: bool,
}

/// Process-wide persistence pressure plus the per-Thread watermarks behind it.
///
/// Counters are sums across Threads; watermarks stay per Thread, because a summed revision of two
/// Threads is not a fact about either of them.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct ThreadPersistenceSnapshot {
    pub(crate) pending_commits: u64,
    pub(crate) oldest_pending_revision: Option<u64>,
    pub(crate) pending_bytes: u64,
    pub(crate) in_flight_bytes: u64,
    pub(crate) oldest_pending_age_millis: Option<u64>,
    pub(crate) pressure_paused: bool,
    pub(crate) threads: Vec<pl_protocol::ThreadPersistenceSnapshot>,
    /// Newest call-write ticket admitted by the global call recorder.
    pub(crate) calls_admitted_sequence: u64,
    /// Newest call-write ticket the global call recorder made durable.
    pub(crate) calls_durable_sequence: u64,
    /// Call mutations still queued in the global recorder.
    pub(crate) calls_pending_operations: u64,
    /// Encoded bytes of the call mutations still queued.
    pub(crate) calls_pending_bytes: u64,
    /// Encoded bytes of the call batch currently being written.
    pub(crate) calls_in_flight_bytes: u64,
    /// Age of the oldest queued call mutation; absent when nothing is queued.
    pub(crate) calls_oldest_pending_age_millis: Option<u64>,
    /// Last typed call-recorder error, kept until a durable write succeeds.
    pub(crate) calls_last_error: Option<String>,
    /// Whether the call recorder is refusing admission under queue pressure.
    pub(crate) calls_pressure_paused: bool,
    pub(crate) statistics_gap: bool,
    pub(crate) error: Option<String>,
}

/// Process-wide call-write queue pressure as last observed by an owning writer.
///
/// The call recorder is a single global writer, so any Thread's writer reports the same values.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct CallsQueueMetrics {
    pub(crate) admitted_sequence: u64,
    pub(crate) durable_sequence: u64,
    pub(crate) pending_operations: u64,
    pub(crate) pending_bytes: u64,
    pub(crate) in_flight_bytes: u64,
    pub(crate) oldest_pending_age_millis: Option<u64>,
    pub(crate) last_error: Option<String>,
    pub(crate) pressure_paused: bool,
    pub(crate) statistics_gap: bool,
}

/// Watermarks reported by one per-Thread writer incarnation.
#[derive(Debug, Clone, Default)]
struct IncarnationStatus {
    /// Admitted effects this incarnation still owes an ordered history/calls write.
    pending: BTreeMap<u64, ()>,
    /// Whether this incarnation still owes the publication of a retained checkpoint.
    pending_checkpoint: bool,
    /// Last write failure of this incarnation, kept until one of its own writes succeeds.
    error: Option<String>,
    metrics: ThreadPersistenceMetrics,
    /// Terminal fact: this incarnation's writer task ended while it still owed commits.
    ///
    /// The shared channel retains these facts, but a successor's registration alone does not
    /// prove adoption. Its obligations stay counted until a real successor queue report covers
    /// every fact, so the process-wide drain fails with the real reason instead of hanging or
    /// reporting a synthetic success while no writer owns the queue.
    released_dirty: Option<String>,
}

impl IncarnationStatus {
    /// Commits this incarnation still owes durability for.
    fn owed(&self) -> u64 {
        self.pending.len() as u64 + u64::from(self.pending_checkpoint)
    }

    /// Last failure worth surfacing for this incarnation; its own write error outranks the terminal
    /// fact that it stopped while still owing commits.
    fn failure(&self) -> Option<String> {
        self.error.clone().or_else(|| self.released_dirty.clone())
    }

    /// Whether this incarnation has nothing left to make durable and no failure to report.
    fn settled(&self) -> bool {
        self.owed() == 0 && self.failure().is_none()
    }

    /// Whether this incarnation's writer task is still running.
    ///
    /// Only a stopped incarnation carries `released_dirty`, and a stopped one that owed nothing is
    /// dropped, so any incarnation still tracked without that diagnostic is live.
    fn is_live(&self) -> bool {
        self.released_dirty.is_none()
    }
}

/// One Thread's watermarks, kept per writer incarnation.
///
/// Incarnations overlap: an activation can be assembled while the previous writer task is still
/// draining, and a superseded writer must neither clear nor be cleared by the writer that replaced
/// it. One entry per incarnation is what makes three obligations hold at once: a stale report can
/// never overwrite the newer incarnation's row, an accepted-but-undurable fact is never dropped
/// when its writer is superseded, and a replaced writer that stops dirty keeps failing the drain
/// explicitly until a real successor adopts its queue or proves it durable.
///
/// The map stays bounded because a stopped incarnation is removed as soon as it owes nothing.
#[derive(Debug)]
struct ThreadStatus {
    incarnations: BTreeMap<usize, IncarnationStatus>,
    channel: Arc<HistoryChannel>,
}

#[derive(Debug)]
struct Inner {
    #[cfg(test)]
    release_gate: Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            std::sync::mpsc::Receiver<()>,
        )>,
    >,
    threads: Mutex<BTreeMap<String, ThreadStatus>>,
    /// Last cumulative usage summary per Thread.
    ///
    /// The projection reads this instead of re-aggregating whatever attempts are still resident, so
    /// a hot increment, a reconnect first frame and a cold restore read one cumulative value.
    usage: Mutex<BTreeMap<String, UsageSummary>>,
    /// Last observed global call-write queue pressure.
    calls: Mutex<CallsQueueMetrics>,
    /// Per-Thread shared history writer handles.
    ///
    /// One Thread must have exactly one ordered history writer, so its effect sink and every live
    /// subscriber share the handle this registry remembers. It keeps only a weak view: the handle
    /// lives exactly as long as a real holder keeps it, so a closed or evicted Thread releases its
    /// database connections (there is no never-expiring strong history cache), while re-activating a
    /// Thread that still has a live holder reuses the same writer identity.
    history: Mutex<BTreeMap<String, HistoryStoreShare>>,
    /// Views and the active writer share one session without pinning cold sessions forever.
    chats: Mutex<BTreeMap<String, WeakSession>>,
    queued_bytes: Arc<AtomicU64>,
    capacity: watch::Sender<u64>,
    state: watch::Sender<ThreadPersistenceSnapshot>,
    retry: Notify,
}

#[derive(Debug, Clone)]
pub(crate) struct ThreadPersistenceCoordinator(Arc<Inner>);

/// Claim and RAII release are established in the same synchronous registration boundary.
pub(crate) struct HistoryWriterRegistration {
    coordinator: ThreadPersistenceCoordinator,
    thread_id: String,
    owner: usize,
    pub(crate) channel: Arc<HistoryChannel>,
}

impl Drop for HistoryWriterRegistration {
    fn drop(&mut self) {
        self.coordinator.detach(&self.thread_id, self.owner);
    }
}

impl Default for ThreadPersistenceCoordinator {
    fn default() -> Self {
        let (state, _) = watch::channel(ThreadPersistenceSnapshot::default());
        let (capacity, _) = watch::channel(0);
        Self(Arc::new(Inner {
            #[cfg(test)]
            release_gate: Mutex::new(None),
            threads: Mutex::new(BTreeMap::new()),
            usage: Mutex::new(BTreeMap::new()),
            calls: Mutex::new(CallsQueueMetrics::default()),
            history: Mutex::new(BTreeMap::new()),
            chats: Mutex::new(BTreeMap::new()),
            queued_bytes: Arc::new(AtomicU64::new(0)),
            capacity,
            state,
            retry: Notify::new(),
        }))
    }
}

impl ThreadPersistenceCoordinator {
    pub(crate) fn delivery_process_bytes(&self) -> u64 {
        self.0.queued_bytes.load(Ordering::Acquire)
    }
    pub(crate) fn subscribe_delivery_capacity(&self) -> watch::Receiver<u64> {
        self.0.capacity.subscribe()
    }
    pub(crate) fn retain_terminal_material(
        &self,
        thread_id: &str,
        channel: &Arc<HistoryChannel>,
        bytes: u64,
    ) -> Arc<crate::thread_assembler::review_dispatch::TerminalMaterialRetention> {
        let counter = channel.retain_terminal_bytes(bytes);
        let process_bytes = self.0.queued_bytes.clone();
        let weak_owner = Arc::downgrade(&self.0);
        let weak_channel = Arc::downgrade(channel);
        let thread_id = thread_id.to_owned();
        Arc::new(
            crate::thread_assembler::review_dispatch::TerminalMaterialRetention::new(move || {
                counter.fetch_sub(bytes, Ordering::AcqRel);
                process_bytes.fetch_sub(bytes, Ordering::AcqRel);
                if let Some(owner) = weak_owner.upgrade() {
                    owner
                        .capacity
                        .send_modify(|revision| *revision = revision.wrapping_add(1));
                    let channel = weak_channel.upgrade().or_else(|| {
                        owner
                            .threads
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .get(&thread_id)
                            .map(|status| status.channel.clone())
                    });
                    if let Some(channel) = channel {
                        channel.refresh_terminal_bytes();
                        ThreadPersistenceCoordinator(owner)
                            .release_delivery_channel(&thread_id, &channel);
                    }
                }
            }),
        )
    }
    #[cfg(test)]
    pub(crate) fn arm_release_gate(
        &self,
    ) -> (
        tokio::sync::oneshot::Receiver<()>,
        std::sync::mpsc::Sender<()>,
    ) {
        let (entered, waiting) = tokio::sync::oneshot::channel();
        let (release, released) = std::sync::mpsc::channel();
        *self.0.release_gate.lock().unwrap() = Some((entered, released));
        (waiting, release)
    }

    pub(crate) fn chat_session(&self, thread_id: &str) -> Option<Session> {
        let mut chats = self
            .0
            .chats
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let active = chats.get(thread_id).and_then(WeakSession::upgrade);
        if active.is_none() {
            chats.remove(thread_id);
        }
        active
    }

    pub(crate) fn install_chat_session(&self, thread_id: &str, session: Session) -> Session {
        let mut chats = self
            .0
            .chats
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(active) = chats.get(thread_id).and_then(WeakSession::upgrade) {
            return active;
        }
        chats.retain(|_, session| session.upgrade().is_some());
        chats.insert(thread_id.to_owned(), session.downgrade());
        session
    }

    /// The manager owns admitted history independently of a writer or GUI subscription.
    pub(crate) fn history_channel(&self, thread_id: &str) -> Arc<HistoryChannel> {
        let mut threads = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let status = threads
            .entry(thread_id.to_owned())
            .or_insert_with(|| ThreadStatus {
                incarnations: BTreeMap::new(),
                channel: Arc::new(HistoryChannel::with_capacity(
                    self.0.queued_bytes.clone(),
                    self.0.capacity.clone(),
                )),
            });
        if status.incarnations.is_empty() && status.channel.is_stopping() {
            status.channel = Arc::new(status.channel.next_storage_channel());
        }
        status.channel.clone()
    }

    /// A receive-only producer can exist without a physical writer (e.g. receipt-first success).
    /// Release its empty coordinator row only after the last retained copy and writer are gone.
    pub(crate) fn retain_review_delivery(
        &self,
        thread_id: &str,
        bytes: u64,
    ) -> Result<super::thread_writer::ReviewDeliveryRetention> {
        let (channel, charged) = {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let status = threads
                .entry(thread_id.to_owned())
                .or_insert_with(|| ThreadStatus {
                    incarnations: BTreeMap::new(),
                    channel: Arc::new(HistoryChannel::with_capacity(
                        self.0.queued_bytes.clone(),
                        self.0.capacity.clone(),
                    )),
                });
            let charged = status.channel.charge_review_delivery(bytes);
            (status.channel.clone(), charged)
        };
        if let Err(error) = charged {
            self.release_delivery_channel(thread_id, &channel);
            return Err(error);
        }
        channel.retain_charged_review_delivery(bytes, self.clone(), thread_id.to_owned())
    }

    pub(crate) fn release_delivery_channel(&self, thread_id: &str, source: &Arc<HistoryChannel>) {
        let current = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .map(|status| status.channel.clone());
        let Some(current) = current else {
            return;
        };
        if !current.shares_delivery_budget(source)
            || !current.is_clean()
            || current.has_delivery_bytes()
        {
            return;
        }
        let mut threads = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if threads.get(thread_id).is_some_and(|status| {
            status.incarnations.is_empty()
                && Arc::ptr_eq(&status.channel, &current)
                && !status.channel.has_delivery_bytes()
        }) {
            threads.remove(thread_id);
        }
    }

    pub(crate) fn retained_history_channel(&self, thread_id: &str) -> Option<Arc<HistoryChannel>> {
        self.0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .map(|status| status.channel.clone())
    }

    /// Retry a fixed session fault generation and wait for its required history/checkpoint fence.
    pub(crate) async fn retry_history(&self, thread_id: &str, generation: u64) -> Result<()> {
        let channel = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .map(|status| status.channel.clone())
            .ok_or_else(|| anyhow::anyhow!("Thread has no pending history recovery"))?;
        let mut updates = channel.subscribe();
        channel.retry(generation)?;
        loop {
            let status = updates.borrow_and_update().clone();
            if status.fault_generation != generation {
                bail!(
                    "history fault generation changed during recovery: {}",
                    status.error.unwrap_or_default()
                );
            }
            if status.fault.is_none() {
                return Ok(());
            }
            updates
                .changed()
                .await
                .map_err(|_| anyhow::anyhow!("history status channel closed"))?;
        }
    }
    pub(crate) fn subscribe(&self) -> watch::Receiver<ThreadPersistenceSnapshot> {
        self.0.state.subscribe()
    }

    pub(crate) fn snapshot(&self) -> ThreadPersistenceSnapshot {
        self.0.state.borrow().clone()
    }

    /// Process-wide persistence queue pressure with the real per-Thread watermarks behind it.
    ///
    /// Bridge/GUI publication is a later task; this is the canonical runtime value it maps onto
    /// [`pl_protocol::PersistenceQueueSnapshot`], so the protocol fields never report placeholders.
    pub(crate) fn queue_snapshot(&self) -> pl_protocol::PersistenceQueueSnapshot {
        let snapshot = self.0.state.borrow().clone();
        pl_protocol::PersistenceQueueSnapshot {
            statistics_gap: snapshot.statistics_gap,
            pending_operations: snapshot
                .pending_commits
                .saturating_add(snapshot.calls_pending_operations),
            pending_bytes: snapshot
                .pending_bytes
                .saturating_add(snapshot.calls_pending_bytes),
            in_flight_bytes: snapshot
                .in_flight_bytes
                .saturating_add(snapshot.calls_in_flight_bytes),
            oldest_pending_age_millis: match (
                snapshot.oldest_pending_age_millis,
                snapshot.calls_oldest_pending_age_millis,
            ) {
                (Some(left), Some(right)) => Some(left.min(right)),
                (left, right) => left.or(right),
            },
            pressure_paused: snapshot.pressure_paused,
            last_error: snapshot.error.clone().or(snapshot.calls_last_error.clone()),
            threads: snapshot.threads,
        }
    }

    pub(crate) fn update(
        &self,
        thread_id: &str,
        owner: usize,
        pending: impl IntoIterator<Item = u64>,
        pending_checkpoint: bool,
        error: Option<String>,
        metrics: ThreadPersistenceMetrics,
    ) {
        {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            // Only the reported incarnation's own row may change: a superseded writer that is still
            // draining its task must not overwrite (or re-add pending work behind) the watermarks of
            // the writer that replaced it, and it must never create a row it does not own.
            let Some(status) = threads.get_mut(thread_id) else {
                return;
            };
            let Some(incarnation) = status.incarnations.get_mut(&owner) else {
                return;
            };
            incarnation.pending = pending.into_iter().map(|sequence| (sequence, ())).collect();
            incarnation.pending_checkpoint = pending_checkpoint;
            incarnation.error = error;
            incarnation.metrics = metrics;
            // A cancelled initializer has not adopted a predecessor's obligations merely by
            // reserving an identity. Retire its stopped predecessor only after a real queue report
            // proves that every owed fact is either adopted by this incarnation or already durable.
            let inherited = &status.incarnations[&owner];
            let covered = status
                .incarnations
                .iter()
                .filter_map(|(id, previous)| {
                    (*id != owner
                        && previous.released_dirty.is_some()
                        && previous.pending.keys().all(|sequence| {
                            inherited.pending.contains_key(sequence)
                                || inherited.metrics.history_durable_sequence >= *sequence
                        })
                        && (!previous.pending_checkpoint
                            || inherited.metrics.state_durable_revision
                                >= previous.metrics.state_dirty_revision))
                        .then_some(*id)
                })
                .collect::<Vec<_>>();
            for id in covered {
                status.incarnations.remove(&id);
            }
        }
        self.refresh();
    }

    /// Binds one live per-Thread writer incarnation to a Thread's watermarks.
    ///
    /// Called when a sink is created. The predecessor's rows are left untouched: only that writer's
    /// own [`Self::detach`] — which runs when its task has actually ended — may decide that a queue
    /// was released unsaved, so an overlapping incarnation can never be talked out of an obligation
    /// it accepted and still owns.
    pub(crate) fn claim(&self, thread_id: &str, owner: usize) -> Result<HistoryWriterRegistration> {
        let channel = {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let status = threads
                .entry(thread_id.to_owned())
                .or_insert_with(|| ThreadStatus {
                    incarnations: BTreeMap::new(),
                    channel: Arc::new(HistoryChannel::with_capacity(
                        self.0.queued_bytes.clone(),
                        self.0.capacity.clone(),
                    )),
                });
            if status.incarnations.is_empty() && status.channel.is_stopping() {
                status.channel = Arc::new(status.channel.next_storage_channel());
            }
            anyhow::ensure!(!status.channel.is_stopping(), "history writer is stopping");
            // Queue adoption is confirmed by update(), not by this preparation reservation.
            let superseded: Vec<usize> = status
                .incarnations
                .iter()
                .filter(|(previous, incarnation)| **previous != owner && incarnation.is_live())
                .map(|(previous, _)| *previous)
                .collect();
            status
                .incarnations
                .insert(owner, IncarnationStatus::default());
            if !superseded.is_empty() {
                // Overlap is expected during re-activation; the predecessor keeps its own row until
                // its task ends, so its outstanding obligations are neither adopted nor discarded.
                tracing::debug!(
                    thread_id,
                    owner,
                    ?superseded,
                    "Thread persistence writer incarnations overlap"
                );
            }
            status.channel.clone()
        };
        let registration = HistoryWriterRegistration {
            coordinator: self.clone(),
            thread_id: thread_id.into(),
            owner,
            channel,
        };
        self.refresh();
        Ok(registration)
    }

    /// Releases one Thread's watermarks when its per-Thread writer stops.
    ///
    /// A stopped writer can never report again. If it owed nothing its row is removed, because
    /// `wait_for_drain` must not keep waiting on a writer that can no longer run. If it still owed
    /// commits those obligations stay counted and become an explicit terminal diagnostic, so
    /// shutdown fails with the real reason instead of hanging or reporting a synthetic success.
    pub(crate) fn detach(&self, thread_id: &str, owner: usize) {
        let channel = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .map(|status| status.channel.clone());
        let Some(channel) = channel else {
            return;
        };
        // Do not take the channel's progress lock under the registry lock: reports take them in
        // the opposite order. A concurrent new claim keeps its own incarnation and prevents removal.
        let clean = channel.is_clean();
        let mut threads = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut empty = false;
        let mut unavailable = false;
        if let Some(status) = threads.get_mut(thread_id) {
            if !status.incarnations.contains_key(&owner) {
                return;
            }
            // Decide before mutating: `record_released_commits` deliberately keeps the row alive
            // when it owes commits, so the removal decision must come from the pre-release state.
            let mut release = false;
            let mut drop_row = false;
            let mut stale_error = None;
            if let Some(incarnation) = status.incarnations.get(&owner) {
                release = incarnation.owed() > 0;
                if !release {
                    // Nothing is owed, so the row goes away with the writer. Anything it reported
                    // is logged rather than kept as a permanent process-wide failure.
                    drop_row = incarnation.settled();
                    stale_error = incarnation.failure();
                }
            }
            if release && let Some(incarnation) = status.incarnations.get_mut(&owner) {
                // A queue it never drained is a still-owned obligation, not a stale counter: the
                // pending entries are kept so the drain keeps seeing them and fails explicitly.
                record_released_commits(incarnation, thread_id);
            }
            // A live successor may only have reserved its identity. Keep these obligations until
            // its real queue report proves adoption; cancellation before that report must not make
            // the process-wide drain mistake an unowned queue for a durable one.
            if let Some(error) = stale_error {
                tracing::error!(
                    thread_id,
                    owner,
                    error,
                    "Thread persistence writer stopped with nothing left to retry"
                );
            }
            if drop_row {
                status.incarnations.remove(&owner);
            }
            // An initializer can exit owing nothing itself while leaving its stopped predecessor's
            // queue unowned. Publish that channel's failure from all remaining obligations, not
            // just the departing incarnation, so both history barriers observe the terminal fact.
            unavailable = status
                .incarnations
                .values()
                .any(|incarnation| incarnation.owed() > 0)
                && !status.incarnations.values().any(IncarnationStatus::is_live);
            empty = status.incarnations.is_empty();
        }
        if empty && clean && !channel.has_delivery_bytes() {
            threads.remove(thread_id);
        }
        drop(threads);
        #[cfg(test)]
        {
            let gate = self.0.release_gate.lock().unwrap().take();
            if let Some((entered, release)) = gate {
                let _ = entered.send(());
                // This deliberate synchronous Drop gate must not occupy a Tokio
                // worker while the test awaits the replacement incarnation.
                tokio::task::block_in_place(|| {
                    let _ = release.recv();
                });
            }
        }
        if unavailable {
            // Recheck at publication, in the same progress -> registry order as a queue report.
            // A successor may have initialized after the earlier registration was released.
            channel.mark_unavailable(|| {
                self.0
                    .threads
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .get(thread_id)
                    .is_some_and(|status| {
                        Arc::ptr_eq(&status.channel, &channel)
                            && !status.incarnations.values().any(IncarnationStatus::is_live)
                    })
            });
        }
        // The history registry holds no strong reference, so prune the entries whose Thread released
        // its last handle: the map stays bounded by the Threads that currently have a history writer
        // instead of growing with every Thread this process ever touched.
        self.0
            .history
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .retain(|_, share| HistoryStore::from_share(share).is_some());
        self.refresh();
    }

    /// The Thread's shared history writer, while a real holder keeps it alive.
    ///
    /// `None` means a caller must open one (through the store) and register it, so two producers
    /// converge on a single writer instead of each keeping its own connection.
    pub(crate) fn shared_history(&self, thread_id: &str) -> Option<HistoryStore> {
        let mut history = self
            .0
            .history
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let revived = history.get(thread_id).and_then(HistoryStore::from_share);
        if revived.is_none() {
            // The last holder released the Thread; drop the dead entry instead of remembering it.
            history.remove(thread_id);
        }
        revived
    }

    /// Registers `store` as the Thread's shared history writer and returns the handle to use.
    ///
    /// A live handle that is already registered wins, so two producers that race to open one still
    /// converge on one writer instead of each keeping its own connection.
    pub(crate) fn install_shared_history(
        &self,
        thread_id: &str,
        store: &HistoryStore,
    ) -> HistoryStore {
        let mut history = self
            .0
            .history
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let existing = history.get(thread_id).and_then(HistoryStore::from_share);
        if let Some(existing) = existing {
            return existing;
        }
        history.insert(thread_id.to_owned(), store.shared());
        store.clone()
    }

    /// Publishes the cumulative usage summary of one Thread.
    ///
    /// The value is absolute, so a repeated report of the same fold is idempotent.
    pub(crate) fn set_usage(&self, thread_id: &str, summary: UsageSummary) {
        self.0
            .usage
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(thread_id.to_owned(), summary);
    }

    /// Publishes the global call-write queue pressure observed by the reporting writer.
    pub(crate) fn report_calls(&self, metrics: CallsQueueMetrics) {
        *self
            .0
            .calls
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = metrics;
        self.refresh();
    }

    /// Reports the global call-write queue pressure only when it actually changed.
    ///
    /// Watch-driven publishers call this from inside their own wakeup path; reporting
    /// unchanged metrics would `refresh()` (which always notifies) and wake the publisher
    /// again, so only real progress may re-enter the watch.
    pub(crate) fn refresh_calls_metrics(&self, metrics: CallsQueueMetrics) -> bool {
        let changed = *self
            .0
            .calls
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            != metrics;
        if changed {
            self.report_calls(metrics);
        }
        changed
    }

    /// Seeds the summary from a loaded checkpoint without overwriting a fresher reported value.
    pub(crate) fn seed_usage(&self, thread_id: &str, summary: UsageSummary) {
        self.0
            .usage
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(thread_id.to_owned())
            .or_insert(summary);
    }

    /// Latest cumulative usage summary of one Thread; absent until a checkpoint or a fold is seen.
    pub(crate) fn usage(&self, thread_id: &str) -> Option<UsageSummary> {
        self.0
            .usage
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .cloned()
    }

    pub(crate) fn retry_now(&self) {
        self.0.retry.notify_one();
    }

    pub(crate) async fn retry_notified(&self) {
        self.0.retry.notified().await;
    }

    pub(crate) async fn wait_for_drain(&self) -> Result<()> {
        let mut progress = self.subscribe();
        loop {
            // Clone out of the watch borrow before re-reading the same channel, so the two read
            // borrows of the shared watch state never overlap.
            let snapshot = progress.borrow_and_update().clone();
            if let Some(error) = snapshot.error.clone() {
                bail!("Thread persistence is blocked: {error}");
            }
            if snapshot.pending_commits == 0 {
                return Ok(());
            }
            let queue = self.queue_snapshot();
            tracing::debug!(
                calls_admitted = snapshot.calls_admitted_sequence,
                calls_durable = snapshot.calls_durable_sequence,
                calls_oldest_pending_age_millis = ?snapshot.calls_oldest_pending_age_millis,
                pending_operations = queue.pending_operations,
                pending_bytes = queue.pending_bytes,
                in_flight_bytes = queue.in_flight_bytes,
                oldest_pending_age_millis = ?queue.oldest_pending_age_millis,
                pressure_paused = queue.pressure_paused,
                threads = queue.threads.len(),
                "waiting for Thread persistence to drain"
            );
            progress
                .changed()
                .await
                .map_err(|_| anyhow::anyhow!("Thread persistence progress channel closed"))?;
        }
    }

    /// Re-aggregates the process-wide observation from the per-Thread status and recovery map.
    fn refresh(&self) {
        let snapshot = {
            let threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let calls = self
                .0
                .calls
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            aggregate(&threads, &calls)
        };
        self.0.state.send_replace(snapshot);
    }
}

/// Records the terminal fact that one writer incarnation stopped while it still owed commits.
///
/// Called under the Threads lock from `detach`, the one place that knows a writer task has actually
/// ended. A stopped writer can never make these facts durable, so the diagnostic turns an unowned
/// queue into an explicit shutdown failure instead of an unbounded wait. The shared channel keeps
/// the facts available for a successor, whose real queue report must prove adoption or durability
/// before this stopped incarnation's diagnostic may be removed.
///
/// Its `pending` bookkeeping is deliberately kept: the obligation is still owned by this
/// incarnation, so the process-wide drain keeps counting it and fails with this error instead of
/// pretending the queue was empty.
fn record_released_commits(incarnation: &mut IncarnationStatus, thread_id: &str) {
    let unsaved = incarnation.owed();
    if unsaved == 0 {
        return;
    }
    tracing::error!(
        thread_id,
        unsaved,
        "Thread persistence writer released unsaved commits"
    );
    incarnation.released_dirty = Some(format!(
        "Thread {thread_id} persistence writer released {unsaved} unsaved commit(s) before they became durable"
    ));
}

fn aggregate(
    threads: &BTreeMap<String, ThreadStatus>,
    calls: &CallsQueueMetrics,
) -> ThreadPersistenceSnapshot {
    // `state.prev.toml` 回退由 checkpoint 层登记，随后成功保存会清除；它作为该 Thread 的
    // 显式恢复诊断暴露，不升级为进程级阻塞错误。
    let recovery = crate::studio::storage::state::checkpoint_recovery_snapshot();
    let mut snapshot = ThreadPersistenceSnapshot {
        calls_admitted_sequence: calls.admitted_sequence,
        calls_durable_sequence: calls.durable_sequence,
        calls_pending_operations: calls.pending_operations,
        calls_pending_bytes: calls.pending_bytes,
        calls_in_flight_bytes: calls.in_flight_bytes,
        calls_oldest_pending_age_millis: calls.oldest_pending_age_millis,
        calls_last_error: calls.last_error.clone(),
        calls_pressure_paused: calls.pressure_paused,
        statistics_gap: calls.statistics_gap,
        ..Default::default()
    };
    for (id, status) in threads {
        // 每个 incarnation 的未落库义务都独立计入：被后继取代的 writer 留下的队列不会被覆盖，
        // 也不会因为后继的存在而从 pending 里消失。
        let mut newest_live: Option<(usize, &IncarnationStatus)> = None;
        let mut newest: Option<(usize, &IncarnationStatus)> = None;
        let mut failure: Option<String> = None;
        for (owner, incarnation) in &status.incarnations {
            snapshot.pending_commits = snapshot.pending_commits.saturating_add(incarnation.owed());
            if let Some(sequence) = incarnation.pending.keys().next().copied() {
                snapshot.oldest_pending_revision = Some(
                    snapshot
                        .oldest_pending_revision
                        .map_or(sequence, |current: u64| current.min(sequence)),
                );
            }
            let metrics = &incarnation.metrics;
            snapshot.pending_bytes = snapshot.pending_bytes.saturating_add(metrics.pending_bytes);
            snapshot.in_flight_bytes = snapshot
                .in_flight_bytes
                .saturating_add(metrics.in_flight_bytes);
            if let Some(age) = metrics.oldest_pending_age_millis {
                snapshot.oldest_pending_age_millis = Some(
                    snapshot
                        .oldest_pending_age_millis
                        .map_or(age, |current: u64| current.min(age)),
                );
            }
            snapshot.pressure_paused |= metrics.pressure_paused;
            if let Some(error) = incarnation.failure() {
                snapshot.error.get_or_insert(error.clone());
                failure.get_or_insert(error);
            }
            // 水位只取最新 incarnation：更旧的快照不得覆盖更新的观测。
            if newest.is_none_or(|(current, _)| *owner >= current) {
                newest = Some((*owner, incarnation));
            }
            if incarnation.is_live() && newest_live.is_none_or(|(current, _)| *owner >= current) {
                newest_live = Some((*owner, incarnation));
            }
        }
        let row = newest_live.or(newest);
        if let Some((_, incarnation)) = row {
            let metrics = &incarnation.metrics;
            // 只有仍在运行的 writer 报告的水位才是当前已观测事实（含 0）；已停止的 incarnation
            // 只能说明它退出时的队列压力，因此水位保持 `None`（未知），不补零。
            let live = newest_live.is_some();
            snapshot
                .threads
                .push(pl_protocol::ThreadPersistenceSnapshot {
                    thread_id: id.clone(),
                    fault_generation: metrics.fault_generation,
                    fault: metrics.fault,
                    state_dirty_revision: live.then_some(metrics.state_dirty_revision),
                    state_saving_revision: live.then_some(metrics.state_saving_revision),
                    state_durable_revision: live.then_some(metrics.state_durable_revision),
                    history_admitted_sequence: live.then_some(metrics.history_admitted_sequence),
                    history_durable_sequence: live.then_some(metrics.history_durable_sequence),
                    calls_admitted_sequence: live.then_some(metrics.calls_admitted_sequence),
                    calls_durable_sequence: live.then_some(metrics.calls_durable_sequence),
                    pending_operations: metrics.pending_operations,
                    pending_bytes: metrics.pending_bytes,
                    oldest_pending_age_millis: metrics.oldest_pending_age_millis,
                    in_flight_bytes: metrics.in_flight_bytes,
                    last_error: failure.or_else(|| recovery.get(id).cloned()),
                    pressure_paused: metrics.pressure_paused,
                });
        }
    }
    // 只有 checkpoint 回退诊断、尚未报告过水位的 Thread 也必须可见；它没有 writer，
    // 因此水位保持 `None`（未知），而不是补零伪装成已观测事实。
    for (id, diagnostic) in recovery.iter() {
        if threads.contains_key(id) {
            continue;
        }
        snapshot
            .threads
            .push(pl_protocol::ThreadPersistenceSnapshot {
                thread_id: id.clone(),
                last_error: Some(diagnostic.clone()),
                ..Default::default()
            });
    }
    // 回退诊断只属于发生恢复的那个 Thread：它已作为该 Thread 的 `last_error` 发布，
    // 不是进程级 writer 失败，因此绝不写入 `snapshot.error`。把它升级为进程级阻塞错误
    // 会让与之无关的 `wait_for_drain`（runtime shutdown/drain）因别人的恢复诊断失败，
    // 而真实 writer 失败仍通过各 incarnation 的 `failure()` 照常阻断 drain。
    snapshot
}
