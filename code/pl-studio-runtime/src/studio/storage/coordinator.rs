//! Process-wide observation and retry coordination for per-Thread persistence sinks.

use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex, Weak,
        atomic::{AtomicU64, Ordering},
    },
};

use anyhow::{Context, Result, bail};
use pl_core::thread::UsageSummary;
use tokio::sync::{Notify, watch};

use crate::history::{HistoryStore, HistoryStoreShare};
use crate::studio::conversation_store::ConversationStore;
use crate::studio::storage::calls::CallsStore;
use crate::studio::storage::thread_writer::HistoryChannel;

/// Per-Thread persistence watermarks and queue pressure reported by the owning writer.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct ThreadPersistenceMetrics {
    pub(crate) fault_generation: u64,
    pub(crate) fault: Option<crate::HistoryFault>,
    pub(crate) history_admitted_sequence: u64,
    pub(crate) history_durable_sequence: u64,
    pub(crate) pending_operations: u64,
    pub(crate) pending_bytes: u64,
    pub(crate) in_flight_bytes: u64,
    pub(crate) oldest_pending_age_millis: Option<u64>,
    pub(crate) pressure_paused: bool,
}

/// One owner's absolute reliable-history state.
pub(crate) struct ThreadPersistenceReport {
    pub(crate) pending: Option<PendingSequenceRange>,
    pub(crate) error: Option<String>,
    pub(crate) metrics: ThreadPersistenceMetrics,
}

/// One writer's continuous reliable queue, expressed without copying every sequence on each report.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct PendingSequenceRange {
    pub(crate) first: u64,
    pub(crate) last: u64,
}

impl PendingSequenceRange {
    pub(crate) fn count(self) -> u64 {
        self.last
            .checked_sub(self.first)
            .and_then(|length| length.checked_add(1))
            .expect("validated pending sequence range")
    }

    fn covers(self, previous: Self, durable: u64) -> bool {
        if durable >= previous.last {
            return true;
        }
        let first_undurable = previous.first.max(durable.saturating_add(1));
        self.first <= first_undurable && self.last >= previous.last
    }
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
    pub(crate) threads: Vec<crate::ThreadPersistenceSnapshot>,
    /// Newest call-write ticket admitted by the global call recorder.
    pub(crate) calls_admitted_ticket: u64,
    /// Newest call-write ticket processed, including explicit rejection; not proof of durability.
    pub(crate) calls_processed_ticket: u64,
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
    pub(crate) admitted_ticket: u64,
    pub(crate) processed_ticket: u64,
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
    /// Admitted effects this incarnation still owes an ordered history write.
    pending: Option<PendingSequenceRange>,
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
        self.pending.map_or(0, PendingSequenceRange::count)
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
    /// Independent current lifecycle; history reports never acknowledge or clear this writer.
    current: Option<RegisteredCurrentWriter>,
}

#[derive(Debug)]
struct RegisteredCurrentWriter {
    directory_key: String,
    writer: Arc<super::current_writer::CurrentWriter>,
}

#[derive(Debug)]
struct Inner {
    threads: Mutex<BTreeMap<String, ThreadStatus>>,
    /// Serializes registration and one-shot migration. A registered slot owns the writer's
    /// physical directory after admission, so normal writes never retain this lock.
    current_admission: Arc<tokio::sync::Mutex<()>>,
    stores: SharedStores,
    observations: Observations,
    queued_bytes: Arc<AtomicU64>,
    capacity: watch::Sender<u64>,
    state: watch::Sender<ThreadPersistenceSnapshot>,
    retry: Notify,
}

/// Weak registries share live read models without turning observation into cache ownership.
#[derive(Debug, Default)]
struct SharedStores {
    /// Per-Thread shared history writer handles.
    ///
    /// One Thread must have exactly one ordered history writer, so its effect sink and every live
    /// subscriber share the handle this registry remembers. It keeps only a weak view: the handle
    /// lives exactly as long as a real holder keeps it, so a closed or evicted Thread releases its
    /// database connections (there is no never-expiring strong history cache), while re-activating a
    /// Thread that still has a live holder reuses the same writer identity.
    history: Mutex<BTreeMap<String, HistoryStoreShare>>,
    /// Views and the active writer share one session without pinning cold sessions forever.
    conversations: Mutex<BTreeMap<String, Weak<ConversationStore>>>,
}

/// Derived readouts have their own locks and do not own the writer or its queue.
#[derive(Debug, Default)]
struct Observations {
    /// Last cumulative usage summary per Thread.
    ///
    /// The projection reads this instead of re-aggregating whatever attempts are still resident, so
    /// a hot increment, a reconnect first frame and a cold restore read one cumulative value.
    usage: Mutex<BTreeMap<String, UsageSummary>>,
    /// Last observed global call-write queue pressure.
    calls: Mutex<CallsQueueMetrics>,
    /// Explicit `state.prev.toml` fallback diagnostics, owned by this coordinator.
    ///
    /// A successful current save on the same instance clears the Thread's entry. Another
    /// coordinator must not observe or clear it.
    checkpoint_recovery: Mutex<BTreeMap<String, String>>,
}

#[derive(Debug, Clone)]
pub(crate) struct ThreadPersistenceCoordinator(Arc<Inner>);

struct ReleasedHistory {
    channel: Arc<HistoryChannel>,
    unavailable: bool,
}

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
            threads: Mutex::new(BTreeMap::new()),
            current_admission: Arc::new(tokio::sync::Mutex::new(())),
            stores: SharedStores::default(),
            observations: Observations::default(),
            queued_bytes: Arc::new(AtomicU64::new(0)),
            capacity,
            state,
            retry: Notify::new(),
        }))
    }
}

impl ThreadPersistenceCoordinator {
    /// Stops and joins every registered append-only writer before a one-shot schema upgrade.
    ///
    /// The caller owns the maintenance gate that prevents a new writer from being admitted while
    /// this method runs. Existing queued work must drain successfully; an unresolved writer failure
    /// is returned instead of being hidden by the upgrade's writer lease.
    pub(crate) async fn retire_history_for_upgrade(&self, thread_id: &str) -> Result<()> {
        let channel = {
            self.0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .get(thread_id)
                .map(|status| status.channel.clone())
        };
        if let Some(channel) = channel {
            channel.stop_and_join().await?;
            self.release_delivery_channel(thread_id, &channel);
        }
        Ok(())
    }

    /// Performs the explicit v1 Current upgrade before recovery. The directory's normal writer
    /// retains ownership until it has joined and released its registration.
    pub(crate) async fn upgrade_current_for_recovery(
        &self,
        thread_id: &str,
        directory: PathBuf,
    ) -> Result<()> {
        anyhow::ensure!(!thread_id.is_empty(), "current Thread identity is empty");
        let admission = self.0.current_admission.clone().lock_owned().await;
        let Some((directory, directory_key)) = current_directory(directory, false).await? else {
            return Ok(());
        };
        let registered = {
            let threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            registered_current(&threads, thread_id, &directory, &directory_key)?.is_some()
        };
        let file = super::current_file::CurrentFile::new(directory, thread_id.to_owned());
        let Some(original) = file.legacy_bytes().await? else {
            return Ok(());
        };
        // A registered writer may have changed the file during the read and released its slot
        // since. Never publish those bytes. A subsequent admission reads its successor afresh.
        anyhow::ensure!(
            !registered,
            "legacy Current cannot be upgraded while its writer is registered"
        );
        let (current, original) = file.prepare_legacy(original).await?;
        publish_current_upgrade(admission, move || file.publish_legacy(&current, &original)).await
    }

    /// Install exactly one stable current writer in the existing per-Thread registration slot.
    /// Prepare only the caller-owned session directory, then identify its physical location before
    /// taking the registration lock. Creation/lookup errors propagate; no guessed missing-path key,
    /// history access, or extra global path registry is involved. The owner must keep this directory
    /// in place until join/release, just as for the session's other physical assets.
    pub(crate) async fn current_writer(
        &self,
        thread_id: &str,
        directory: PathBuf,
    ) -> Result<Arc<super::current_writer::CurrentWriter>> {
        anyhow::ensure!(!thread_id.is_empty(), "current Thread identity is empty");
        let (directory, directory_key) = current_directory(directory, true)
            .await?
            .context("prepared Current session directory is missing")?;
        let _admission = self.0.current_admission.lock().await;
        let mut threads = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(registered) =
            registered_current(&threads, thread_id, &directory, &directory_key)?
        {
            return Ok(registered.writer.clone());
        }
        let status = threads
            .entry(thread_id.to_owned())
            .or_insert_with(|| ThreadStatus {
                incarnations: BTreeMap::new(),
                channel: Arc::new(HistoryChannel::with_capacity(
                    self.0.queued_bytes.clone(),
                    self.0.capacity.clone(),
                )),
                current: None,
            });
        let weak = Arc::downgrade(&self.0);
        let recovery = Arc::downgrade(&self.0);
        let writer = super::current_writer::CurrentWriter::with_saved_hook(
            super::current_file::CurrentFile::new(directory, thread_id.to_owned()),
            move || {
                if let Some(inner) = weak.upgrade() {
                    ThreadPersistenceCoordinator(inner).refresh();
                }
            },
            move |thread_id| {
                if let Some(inner) = recovery.upgrade() {
                    ThreadPersistenceCoordinator(inner).clear_checkpoint_recovery(thread_id);
                }
            },
        );
        status.current = Some(RegisteredCurrentWriter {
            directory_key,
            writer: writer.clone(),
        });
        drop(threads);
        self.refresh();
        Ok(writer)
    }

    pub(crate) fn release_current_writer(
        &self,
        thread_id: &str,
        writer: &Arc<super::current_writer::CurrentWriter>,
    ) {
        if !writer.is_joined() {
            return;
        }
        let channel = {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let Some(status) = threads.get_mut(thread_id) else {
                return;
            };
            if !status
                .current
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(&current.writer, writer))
            {
                return;
            }
            status.current = None;
            status.channel.clone()
        };
        self.release_delivery_channel(thread_id, &channel);
        self.refresh();
    }

    pub(in crate::studio) fn forget_deleted(&self, thread_id: &str) -> anyhow::Result<()> {
        {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            anyhow::ensure!(
                threads
                    .get(thread_id)
                    .is_none_or(|status| status.current.is_none()
                        && status
                            .incarnations
                            .values()
                            .all(|incarnation| !incarnation.is_live()
                                && (incarnation.settled() || status.channel.deletion_joined()))
                        && (status.channel.is_clean() || status.channel.deletion_joined())
                        && !status.channel.has_delivery_bytes()),
                "deleted Thread still has a live writer or reliable delivery responsibility"
            );
            threads.remove(thread_id);
        }
        self.0
            .observations
            .usage
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(thread_id);
        self.0
            .stores
            .conversations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(thread_id);
        self.0
            .stores
            .history
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(thread_id);
        self.refresh();
        Ok(())
    }

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
        transfer: Option<super::thread_writer::ProjectionTransfer>,
    ) -> anyhow::Result<Arc<crate::thread_assembler::review_dispatch::TerminalMaterialRetention>>
    {
        let admission = {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let status = threads
                .entry(thread_id.to_owned())
                .or_insert_with(|| ThreadStatus {
                    incarnations: BTreeMap::new(),
                    channel: channel.clone(),
                    current: None,
                });
            anyhow::ensure!(
                status.channel.shares_delivery_budget(channel),
                "terminal material belongs to another history channel"
            );
            channel.pin_review_delivery(self.clone(), thread_id.to_owned())
        };
        let counter = match transfer {
            Some(transfer) => channel.retain_terminal_bytes(bytes, transfer)?,
            None => channel.retain_cold_terminal_bytes(bytes)?,
        };
        let process_bytes = self.0.queued_bytes.clone();
        let weak_owner = Arc::downgrade(&self.0);
        let weak_channel = Arc::downgrade(channel);
        let thread_id = thread_id.to_owned();
        let retained = Arc::new(
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
        );
        drop(admission);
        Ok(retained)
    }
    pub(crate) fn conversation_store(&self, thread_id: &str) -> Option<Arc<ConversationStore>> {
        let mut chats = self
            .0
            .stores
            .conversations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let active = chats.get(thread_id).and_then(Weak::upgrade);
        if active.is_none() {
            chats.remove(thread_id);
        }
        active
    }

    pub(crate) fn install_conversation_store(
        &self,
        thread_id: &str,
        session: Arc<ConversationStore>,
    ) -> Arc<ConversationStore> {
        let mut chats = self
            .0
            .stores
            .conversations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(active) = chats.get(thread_id).and_then(Weak::upgrade) {
            return active;
        }
        chats.retain(|_, session| session.upgrade().is_some());
        chats.insert(thread_id.to_owned(), Arc::downgrade(&session));
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
                current: None,
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
        let (channel, admission) = {
            let mut threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let status = threads
                .entry(thread_id.to_owned())
                .or_insert_with(|| ThreadStatus {
                    incarnations: BTreeMap::new(),
                    current: None,
                    channel: Arc::new(HistoryChannel::with_capacity(
                        self.0.queued_bytes.clone(),
                        self.0.capacity.clone(),
                    )),
                });
            let admission = status
                .channel
                .pin_review_delivery(self.clone(), thread_id.to_owned());
            (status.channel.clone(), admission)
        };
        channel.charge_review_delivery(bytes)?;
        let retention =
            channel.retain_charged_review_delivery(bytes, self.clone(), thread_id.to_owned());
        drop(admission);
        retention
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
                && status.current.is_none()
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
        let mut reports = self.subscribe();
        channel.retry(generation)?;
        loop {
            // Register the report observation before checking its rows; no watch
            // borrow or registry lock is held while waiting for either source.
            drop(reports.borrow_and_update());
            let status = updates.borrow_and_update().clone();
            if status.fault_generation != generation {
                bail!(
                    "history fault generation changed during recovery: {}",
                    status.error.unwrap_or_default()
                );
            }
            if status.fault.is_none() {
                let pending_reports = self
                    .0
                    .threads
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .get(thread_id)
                    .is_some_and(|thread| {
                        thread.incarnations.values().any(|incarnation| {
                            incarnation.metrics.fault_generation <= generation
                                && incarnation.metrics.fault == Some(crate::HistoryFault::QueueFull)
                        })
                    });
                if !pending_reports {
                    // Rows may have changed just before their publisher entered refresh.
                    // Publish them here as well; refresh serializes capture and publication.
                    self.refresh();
                    if !updates
                        .has_changed()
                        .map_err(|_| anyhow::anyhow!("history status channel closed"))?
                    {
                        if channel.stopping.is_cancelled() {
                            bail!("history writer is stopping");
                        }
                        return Ok(());
                    }
                    // A newer shared fault can arrive between the first status read
                    // and the report check. Validate its generation before returning.
                    continue;
                }
            }
            tokio::select! {
                result = updates.changed() => {
                    result.map_err(|_| anyhow::anyhow!("history status channel closed"))?;
                },
                result = reports.changed() => {
                    result.map_err(|_| anyhow::anyhow!("Thread persistence progress channel closed"))?;
                },
                () = channel.stopping.cancelled() => bail!("history writer is stopping"),
            }
        }
    }
    pub(crate) fn subscribe(&self) -> watch::Receiver<ThreadPersistenceSnapshot> {
        self.0.state.subscribe()
    }

    #[cfg(test)]
    pub(crate) fn state_subscriber_count_for_test(&self) -> usize {
        self.0.state.receiver_count()
    }

    pub(crate) fn snapshot(&self) -> ThreadPersistenceSnapshot {
        self.0.state.borrow().clone()
    }

    /// Process-wide persistence queue pressure with the real per-Thread watermarks behind it.
    ///
    /// Bridge/GUI publication is a later task; this is the canonical runtime value it maps onto
    /// [`crate::PersistenceQueueSnapshot`], so the protocol fields never report placeholders.
    pub(crate) fn queue_snapshot(&self) -> crate::PersistenceQueueSnapshot {
        // Re-sample the real Current owners so snapshot age advances even without a new save.
        // This read does not publish to the watch channel, which would wake its own consumers.
        // Recovery is cloned before the registry locks. record/clear take that map and then
        // refresh, which takes the registry; the opposite order would deadlock.
        let recovery = self.checkpoint_recovery_map();
        let threads = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let calls = self
            .0
            .observations
            .calls
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let snapshot = aggregate(&threads, &calls, &recovery);
        crate::PersistenceQueueSnapshot {
            statistics_gap: snapshot.statistics_gap,
            pending_operations: snapshot
                .threads
                .iter()
                .fold(0_u64, |total, thread| {
                    total.saturating_add(thread.pending_operations)
                })
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
                (Some(left), Some(right)) => Some(left.max(right)),
                (left, right) => left.or(right),
            },
            pressure_paused: snapshot.pressure_paused,
            last_error: snapshot.error.clone().or(snapshot.calls_last_error.clone()),
            threads: snapshot.threads,
        }
    }

    pub(crate) fn report(
        &self,
        thread_id: &str,
        owner: usize,
        report: ThreadPersistenceReport,
        calls: Option<&CallsStore>,
    ) {
        self.report_with_sample(
            thread_id,
            owner,
            report,
            calls.map(|calls| || calls.metrics()),
        );
    }

    fn report_with_sample(
        &self,
        thread_id: &str,
        owner: usize,
        report: ThreadPersistenceReport,
        calls: Option<impl FnOnce() -> CallsQueueMetrics>,
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
            incarnation.pending = report.pending;
            incarnation.error = report.error;
            incarnation.metrics = report.metrics;
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
                        && previous.pending.is_none_or(|previous| {
                            inherited.pending.is_some_and(|pending| {
                                pending.covers(previous, inherited.metrics.history_durable_sequence)
                            }) || inherited.metrics.history_durable_sequence >= previous.last
                        }))
                    .then_some(*id)
                })
                .collect::<Vec<_>>();
            for id in covered {
                status.incarnations.remove(&id);
            }
            if let Some(calls) = calls {
                // Validate the owner before sampling. Keep threads -> calls and adopt both
                // observations before publishing once; history-only reports retain global calls.
                self.adopt_calls_metrics(calls);
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
                    current: None,
                    channel: Arc::new(HistoryChannel::with_capacity(
                        self.0.queued_bytes.clone(),
                        self.0.capacity.clone(),
                    )),
                });
            if status.incarnations.is_empty() && status.channel.is_stopping() {
                status.channel = Arc::new(status.channel.next_storage_channel());
            }
            anyhow::ensure!(!status.channel.is_stopping(), "history writer is stopping");
            // Queue adoption is confirmed by report(), not by this preparation reservation.
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
        if let Some(released) = self.unregister(thread_id, owner) {
            self.finish_release(thread_id, released);
        }
    }

    fn unregister(&self, thread_id: &str, owner: usize) -> Option<ReleasedHistory> {
        let channel = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread_id)
            .map(|status| status.channel.clone());
        let channel = channel?;
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
                return None;
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
            empty = status.incarnations.is_empty() && status.current.is_none();
        }
        if empty && clean && !channel.has_delivery_bytes() {
            threads.remove(thread_id);
        }
        Some(ReleasedHistory {
            channel,
            unavailable,
        })
    }

    fn finish_release(&self, thread_id: &str, released: ReleasedHistory) {
        let ReleasedHistory {
            channel,
            unavailable,
        } = released;
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
            .stores
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
            .stores
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
            .stores
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
            .observations
            .usage
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(thread_id.to_owned(), summary);
    }

    /// Samples and adopts global call-write pressure under one ordered boundary.
    pub(crate) fn report_calls(&self, calls: &CallsStore) {
        self.report_calls_with(|| calls.metrics());
    }

    fn report_calls_with(&self, sample: impl FnOnce() -> CallsQueueMetrics) {
        self.adopt_calls_metrics(sample);
        self.refresh();
    }

    /// Watch-driven publishers re-enter this after their own notification. Only a change
    /// in the observed source can publish a new snapshot from this entry point.
    pub(crate) fn refresh_calls_metrics(&self, calls: &CallsStore) -> bool {
        self.refresh_calls_with(|| calls.metrics())
    }

    fn refresh_calls_with(&self, sample: impl FnOnce() -> CallsQueueMetrics) -> bool {
        let changed = self.adopt_calls_metrics(sample);
        if changed {
            self.refresh();
        }
        changed
    }

    /// Serialize sampling with adoption so a delayed observation cannot overwrite a newer one.
    fn adopt_calls_metrics(&self, sample: impl FnOnce() -> CallsQueueMetrics) -> bool {
        let mut current = self
            .0
            .observations
            .calls
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let metrics = sample();
        if *current == metrics {
            return false;
        }
        *current = metrics;
        true
    }

    /// Seeds the summary from a loaded checkpoint without overwriting a fresher reported value.
    pub(crate) fn seed_usage(&self, thread_id: &str, summary: UsageSummary) {
        self.0
            .observations
            .usage
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(thread_id.to_owned())
            .or_insert(summary);
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
                calls_admitted = snapshot.calls_admitted_ticket,
                calls_processed = snapshot.calls_processed_ticket,
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
        let recovery = self.checkpoint_recovery_map();
        // Capture inside watch's publication lock so an older aggregate cannot
        // overtake a newer one. All callers release registry/calls locks first.
        self.0.state.send_modify(|snapshot| {
            let threads = self
                .0
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let calls = self
                .0
                .observations
                .calls
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            *snapshot = aggregate(&threads, &calls, &recovery);
        });
    }

    /// Records one explicit checkpoint fallback for this coordinator's Threads.
    pub(crate) fn record_checkpoint_recovery(&self, thread_id: &str, diagnostic: String) {
        self.0
            .observations
            .checkpoint_recovery
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(thread_id.to_owned(), diagnostic);
        self.refresh();
    }

    /// Clears the fallback diagnostic after the same coordinator saves current successfully.
    pub(crate) fn clear_checkpoint_recovery(&self, thread_id: &str) {
        let removed = self
            .0
            .observations
            .checkpoint_recovery
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(thread_id);
        if removed.is_some() {
            self.refresh();
        }
    }

    fn checkpoint_recovery_map(&self) -> BTreeMap<String, String> {
        self.0
            .observations
            .checkpoint_recovery
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
}

async fn current_directory(directory: PathBuf, create: bool) -> Result<Option<(PathBuf, String)>> {
    tokio::task::spawn_blocking(move || {
        anyhow::ensure!(
            !directory.as_os_str().is_empty(),
            "current session directory is empty"
        );
        if create {
            std::fs::create_dir_all(&directory).with_context(|| {
                format!("prepare current session directory {}", directory.display())
            })?;
        }
        let directory = match dunce::canonicalize(&directory) {
            Ok(directory) => directory,
            Err(error) if !create && error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(None);
            }
            Err(error) => {
                return Err(error).with_context(|| {
                    format!("resolve current session directory {}", directory.display())
                });
            }
        };
        let metadata = std::fs::metadata(&directory).with_context(|| {
            format!("inspect current session directory {}", directory.display())
        })?;
        anyhow::ensure!(
            metadata.is_dir(),
            "current session path is not a directory: {}",
            directory.display()
        );
        let key = crate::studio::instance::directory_key(&directory).with_context(|| {
            format!("identify current session directory {}", directory.display())
        })?;
        Ok(Some((directory, key)))
    })
    .await
    .context("join current session directory preparation")?
}

async fn publish_current_upgrade(
    admission: tokio::sync::OwnedMutexGuard<()>,
    publish: impl FnOnce() -> Result<()> + Send + 'static,
) -> Result<()> {
    tokio::task::spawn_blocking(move || {
        // The blocking operation owns admission through both atomic publications and their syncs.
        // Dropping the async join waiter cannot admit a writer while either I/O is still running.
        let _admission = admission;
        publish()
    })
    .await
    .context("join Current upgrade publication")?
}

fn registered_current<'a>(
    threads: &'a BTreeMap<String, ThreadStatus>,
    thread_id: &str,
    directory: &Path,
    directory_key: &str,
) -> Result<Option<&'a RegisteredCurrentWriter>> {
    // Physical identity catches aliases. The canonical name protects replacement in place.
    for (owner, status) in threads {
        let Some(registered) = &status.current else {
            continue;
        };
        if registered.directory_key == directory_key || registered.writer.directory() == directory {
            anyhow::ensure!(
                owner == thread_id,
                "current session directory {} is already registered for another Thread {owner}",
                directory.display()
            );
            anyhow::ensure!(
                registered.directory_key == directory_key,
                "current Thread physical directory changed while registered: {}",
                directory.display()
            );
            return Ok(Some(registered));
        }
    }
    anyhow::ensure!(
        threads
            .get(thread_id)
            .is_none_or(|status| status.current.is_none()),
        "current Thread registered under another session directory"
    );
    Ok(None)
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
    recovery: &BTreeMap<String, String>,
) -> ThreadPersistenceSnapshot {
    // `state.prev.toml` fallback is recorded on this coordinator and cleared by its own save.
    // It is that Thread's diagnostic, never a process-wide writer failure.
    let mut snapshot = ThreadPersistenceSnapshot {
        calls_admitted_ticket: calls.admitted_ticket,
        calls_processed_ticket: calls.processed_ticket,
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
        let mut row = crate::ThreadPersistenceSnapshot {
            thread_id: id.clone(),
            ..Default::default()
        };
        let mut newest_live = None;
        let mut newest = None;
        // Each incarnation contributes to outstanding History pressure. Only the latest live
        // incarnation supplies watermarks. BTreeMap visits the oldest owner first.
        for incarnation in status.incarnations.values() {
            let metrics = &incarnation.metrics;
            row.pending_operations = row.pending_operations.saturating_add(incarnation.owed());
            row.pending_bytes = row.pending_bytes.saturating_add(metrics.pending_bytes);
            row.in_flight_bytes = row.in_flight_bytes.saturating_add(metrics.in_flight_bytes);
            row.oldest_pending_age_millis = row
                .oldest_pending_age_millis
                .max(metrics.oldest_pending_age_millis);
            row.pressure_paused |= metrics.pressure_paused;
            if let Some(pending) = incarnation.pending {
                snapshot.oldest_pending_revision = Some(
                    snapshot
                        .oldest_pending_revision
                        .map_or(pending.first, |oldest| oldest.min(pending.first)),
                );
            }
            if row.last_error.is_none()
                && let Some(error) = incarnation.failure()
            {
                if snapshot.error.is_none() {
                    snapshot.error = Some(error.clone());
                }
                row.last_error = Some(error);
            }
            newest = Some(metrics);
            if incarnation.is_live() {
                newest_live = Some(metrics);
            }
        }
        snapshot.pending_commits = snapshot
            .pending_commits
            .saturating_add(row.pending_operations);
        snapshot.pending_bytes = snapshot.pending_bytes.saturating_add(row.pending_bytes);
        snapshot.in_flight_bytes = snapshot.in_flight_bytes.saturating_add(row.in_flight_bytes);
        snapshot.oldest_pending_age_millis = snapshot
            .oldest_pending_age_millis
            .max(row.oldest_pending_age_millis);
        snapshot.pressure_paused |= row.pressure_paused;
        if row.last_error.is_none() {
            row.last_error = recovery.get(id).cloned();
        }
        if let Some(metrics) = newest_live.or(newest) {
            row.fault_generation = metrics.fault_generation;
            row.fault = metrics.fault;
        }
        if let Some(metrics) = newest_live {
            row.history_admitted_sequence = Some(metrics.history_admitted_sequence);
            row.history_durable_sequence = Some(metrics.history_durable_sequence);
        }
        if let Some(current) = &status.current {
            let current = current.writer.snapshot().persistence_snapshot();
            row.pending_operations = row
                .pending_operations
                .saturating_add(u64::from(current.dirty || current.in_flight));
            if let Some(error) = &current.last_error {
                row.last_error.get_or_insert_with(|| error.clone());
                snapshot.error.get_or_insert_with(|| error.clone());
            }
            row.current = Some(current);
        }
        snapshot.threads.push(row);
    }
    // 只有 checkpoint 回退诊断、尚未报告过水位的 Thread 也必须可见；它没有 writer，
    // 因此水位保持 `None`（未知），而不是补零伪装成已观测事实。
    for (id, diagnostic) in recovery.iter() {
        if threads.contains_key(id) {
            continue;
        }
        snapshot.threads.push(crate::ThreadPersistenceSnapshot {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn tool_result_current_migration_orders_registration_behind_the_same_admission()
    -> Result<()> {
        use pl_core::thread::current::{RuntimeEpoch, ThreadCurrent};
        let temp = tempfile::tempdir()?;
        let path = temp.path().join(crate::studio::paths::CURRENT_FILE_NAME);
        let id = "current-admission";
        let coordinator = ThreadPersistenceCoordinator::default();
        let mut legacy = serde_json::to_value(ThreadCurrent::new(id.into(), RuntimeEpoch::new()))?;
        legacy["schemaVersion"] = 1.into();
        let legacy = serde_json::to_vec_pretty(&legacy)?;
        std::fs::write(&path, &legacy)?;

        let admission = coordinator.0.current_admission.lock().await;
        {
            let mut cancelled = std::pin::pin!(
                coordinator.upgrade_current_for_recovery(id, temp.path().to_owned())
            );
            assert!(futures::poll!(&mut cancelled).is_pending());
        }
        assert_eq!(std::fs::read(&path)?, legacy);
        let mut migration =
            std::pin::pin!(coordinator.upgrade_current_for_recovery(id, temp.path().to_owned()));
        assert!(futures::poll!(&mut migration).is_pending());
        let mut registration = std::pin::pin!(async {
            let writer = coordinator
                .current_writer(id, temp.path().to_owned())
                .await?;
            ThreadCurrent::from_json(&std::fs::read(&path)?, id)?;
            Ok::<_, anyhow::Error>(writer)
        });
        assert!(futures::poll!(&mut registration).is_pending());
        drop(admission);
        let (migrated, registered) = tokio::join!(migration, registration);
        migrated?;
        let writer = registered?;
        assert_eq!(writer.directory(), dunce::canonicalize(temp.path())?);
        assert_eq!(
            std::fs::read(
                temp.path()
                    .join("migration-backups/current-tool-result-v1/current.original.json")
            )?,
            legacy
        );
        Ok(())
    }

    #[tokio::test]
    async fn tool_result_current_publication_keeps_admission_after_join_waiter_is_cancelled()
    -> Result<()> {
        let coordinator = ThreadPersistenceCoordinator::default();
        let temp = tempfile::tempdir()?;
        let published = temp.path().join("publication-complete");
        let (entered, started) = tokio::sync::oneshot::channel();
        let (release, blocked) = std::sync::mpsc::channel();
        let admission = coordinator.0.current_admission.clone().lock_owned().await;
        let waiter = tokio::spawn(publish_current_upgrade(admission, {
            let published = published.clone();
            move || {
                entered
                    .send(())
                    .map_err(|_| anyhow::anyhow!("missing publication observer"))?;
                blocked.recv()?;
                std::fs::write(&published, b"completed")?;
                Ok(())
            }
        }));
        tokio::time::timeout(std::time::Duration::from_secs(5), started).await??;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        assert!(coordinator.0.current_admission.try_lock().is_err());
        assert!(!published.exists());

        let registration = coordinator.current_writer("after-cancellation", temp.path().to_owned());
        release.send(())?;
        let _writer =
            tokio::time::timeout(std::time::Duration::from_secs(5), registration).await??;
        assert_eq!(std::fs::read(published)?, b"completed");
        Ok(())
    }

    fn history_report() -> ThreadPersistenceReport {
        ThreadPersistenceReport {
            pending: Some(PendingSequenceRange { first: 3, last: 3 }),
            error: Some("retained failure".into()),
            metrics: ThreadPersistenceMetrics {
                fault_generation: 4,
                history_admitted_sequence: 3,
                history_durable_sequence: 2,
                pending_operations: 1,
                pending_bytes: 17,
                ..Default::default()
            },
        }
    }

    #[test]
    fn continuous_ranges_and_oldest_age_aggregate_without_sequence_vectors() -> Result<()> {
        let coordinator = ThreadPersistenceCoordinator::default();
        let _first = coordinator.claim("range-first", 1)?;
        let _second = coordinator.claim("range-second", 2)?;
        let mut first = history_report();
        first.pending = Some(PendingSequenceRange { first: 3, last: 5 });
        first.metrics.pending_operations = 3;
        first.metrics.oldest_pending_age_millis = Some(40);
        coordinator.report("range-first", 1, first, None);
        let mut second = history_report();
        second.pending = Some(PendingSequenceRange {
            first: 10,
            last: 11,
        });
        second.metrics.pending_operations = 2;
        second.metrics.oldest_pending_age_millis = Some(90);
        coordinator.report("range-second", 2, second, None);

        let snapshot = coordinator.snapshot();
        assert_eq!(snapshot.pending_commits, 5);
        assert_eq!(snapshot.oldest_pending_revision, Some(3));
        assert_eq!(snapshot.oldest_pending_age_millis, Some(90));
        {
            let mut calls = coordinator.0.observations.calls.lock().unwrap();
            calls.oldest_pending_age_millis = Some(120);
        }
        coordinator.refresh();
        assert_eq!(
            coordinator.queue_snapshot().oldest_pending_age_millis,
            Some(120)
        );
        for (thread_id, owner) in [("range-first", 1), ("range-second", 2)] {
            coordinator.report(
                thread_id,
                owner,
                ThreadPersistenceReport {
                    pending: None,
                    error: None,
                    metrics: ThreadPersistenceMetrics::default(),
                },
                None,
            );
        }
        Ok(())
    }

    #[test]
    fn checkpoint_recovery_is_isolated_to_its_coordinator() {
        let owner = ThreadPersistenceCoordinator::default();
        let other = ThreadPersistenceCoordinator::default();
        owner.record_checkpoint_recovery("thread-a", "recovered from prev".into());

        let snapshot = owner.snapshot();
        let row = snapshot
            .threads
            .iter()
            .find(|thread| thread.thread_id == "thread-a")
            .expect("recovery thread");
        assert_eq!(row.last_error.as_deref(), Some("recovered from prev"));
        assert!(
            snapshot.error.is_none(),
            "fallback must not block process drain"
        );
        assert!(
            other
                .snapshot()
                .threads
                .iter()
                .all(|thread| thread.thread_id != "thread-a")
        );

        owner.clear_checkpoint_recovery("thread-a");
        assert!(
            owner
                .snapshot()
                .threads
                .iter()
                .all(|thread| thread.thread_id != "thread-a")
        );
    }

    #[tokio::test]
    async fn joint_report_publishes_one_coherent_owned_snapshot() -> Result<()> {
        let directory = tempfile::tempdir()?;
        // Prepare a real source without starting its worker: observations cannot race a drain.
        let calls = CallsStore::prepare(&directory.path().join("calls.sqlite")).await?;
        calls.mark_statistics_gap();
        let coordinator = ThreadPersistenceCoordinator::default();
        let _registration = coordinator.claim("joint-report", 7)?;
        let mut observed = coordinator.subscribe();
        coordinator.report("joint-report", 7, history_report(), Some(&calls));
        assert!(observed.has_changed()?);
        let snapshot = observed.borrow_and_update().clone();
        assert_eq!(snapshot.pending_commits, 1);
        assert_eq!(snapshot.pending_bytes, 17);
        assert_eq!(snapshot.calls_admitted_ticket, calls.admitted_ticket());
        assert_eq!(snapshot.calls_processed_ticket, calls.processed_ticket());
        assert!(snapshot.statistics_gap);
        let thread = &snapshot.threads[0];
        assert_eq!(thread.history_admitted_sequence, Some(3));
        assert_eq!(thread.history_durable_sequence, Some(2));
        assert_eq!(thread.last_error.as_deref(), Some("retained failure"));

        let adopted_calls = coordinator.0.observations.calls.lock().unwrap().clone();
        calls.replace_session_usage(super::super::calls::SessionUsageProjection {
            root_thread_id: "joint-report".into(),
            thread_id: "joint-report".into(),
            revision: 1,
            has_unpriced_usage: false,
            has_incomplete_usage: false,
            purpose_costs: vec![],
        })?;
        assert!(calls.admitted_ticket() > snapshot.calls_admitted_ticket);
        let mut historical = history_report();
        historical.pending = Some(PendingSequenceRange { first: 4, last: 4 });
        historical.metrics.history_admitted_sequence = 4;
        historical.metrics.history_durable_sequence = 3;
        coordinator.report("joint-report", 7, historical, None);
        assert_eq!(
            *coordinator.0.observations.calls.lock().unwrap(),
            adopted_calls
        );
        assert!(observed.has_changed()?);
        let history_only = observed.borrow_and_update().clone();
        assert_eq!(
            history_only.calls_admitted_ticket,
            snapshot.calls_admitted_ticket
        );
        assert_eq!(history_only.threads[0].history_admitted_sequence, Some(4));
        assert_eq!(history_only.threads[0].history_durable_sequence, Some(3));
        // A stale/unregistered incarnation owns neither history nor the authority to sample calls.
        let unexpected_sample = || panic!("unknown writer cannot sample Calls");
        coordinator.report_with_sample(
            "joint-report",
            8,
            history_report(),
            Some(unexpected_sample),
        );
        coordinator.report_with_sample(
            "unregistered",
            7,
            history_report(),
            Some(unexpected_sample),
        );
        assert!(!observed.has_changed()?);
        assert_eq!(coordinator.snapshot(), history_only);
        calls.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn calls_sampling_and_adoption_are_ordered_across_all_entrypoints() -> Result<()> {
        fn publish(
            coordinator: &ThreadPersistenceCoordinator,
            entry: usize,
            sample: impl FnOnce() -> CallsQueueMetrics,
        ) {
            match entry {
                0 => coordinator.report_with_sample("ordered", 7, history_report(), Some(sample)),
                1 => coordinator.report_calls_with(sample),
                2 => {
                    coordinator.refresh_calls_with(sample);
                }
                _ => unreachable!(),
            }
        }

        for entry in 0..3 {
            let directory = tempfile::tempdir()?;
            let calls = CallsStore::prepare(&directory.path().join("calls.sqlite")).await?;
            let coordinator = ThreadPersistenceCoordinator::default();
            let _registration = coordinator.claim("ordered", 7)?;
            let (entered, sampled) = tokio::sync::oneshot::channel();
            let (release, waiting) = std::sync::mpsc::channel();
            let first = tokio::task::spawn_blocking({
                let coordinator = coordinator.clone();
                let calls = calls.clone();
                move || {
                    publish(&coordinator, entry, || {
                        let metrics = calls.metrics();
                        entered.send(()).expect("test waits for sample");
                        waiting.recv().expect("test releases sample");
                        metrics
                    })
                }
            });
            tokio::time::timeout(std::time::Duration::from_secs(5), sampled).await??;
            // The source was really sampled, but adoption is paused. No other entrypoint may
            // sample/adopt a newer value and then be overwritten by this older observation.
            let serialized = matches!(
                coordinator.0.observations.calls.try_lock(),
                Err(std::sync::TryLockError::WouldBlock)
            );
            calls.mark_statistics_gap();
            let second = tokio::task::spawn_blocking({
                let coordinator = coordinator.clone();
                let calls = calls.clone();
                move || publish(&coordinator, (entry + 1) % 3, || calls.metrics())
            });
            release.send(())?;
            tokio::time::timeout(std::time::Duration::from_secs(5), first).await??;
            tokio::time::timeout(std::time::Duration::from_secs(5), second).await??;
            assert!(
                serialized,
                "entrypoint {entry} released the calls boundary after sampling"
            );
            assert!(coordinator.snapshot().statistics_gap);
            assert!(
                coordinator
                    .0
                    .observations
                    .calls
                    .lock()
                    .unwrap()
                    .statistics_gap
            );
            calls.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn unchanged_calls_metrics_do_not_feed_back_into_the_watch() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let calls = CallsStore::prepare(&directory.path().join("calls.sqlite")).await?;
        let coordinator = ThreadPersistenceCoordinator::default();
        let mut observed = coordinator.subscribe();
        assert!(!coordinator.refresh_calls_metrics(&calls));
        assert!(!observed.has_changed()?);
        calls.mark_statistics_gap();
        assert!(coordinator.refresh_calls_metrics(&calls));
        assert!(observed.has_changed()?);
        assert!(observed.borrow_and_update().statistics_gap);
        assert!(!coordinator.refresh_calls_metrics(&calls));
        assert!(!observed.has_changed()?);
        coordinator.report_calls(&calls);
        assert!(observed.has_changed()?);
        calls.close().await?;
        Ok(())
    }

    #[test]
    fn a_replacement_claim_survives_a_predecessors_release() -> Result<()> {
        let coordinator = ThreadPersistenceCoordinator::default();
        let predecessor = coordinator.claim("overlap", 1)?;
        let released = coordinator
            .unregister("overlap", 1)
            .context("predecessor released")?;
        let replacement = coordinator.claim("overlap", 2)?;
        assert!(!Arc::ptr_eq(&predecessor.channel, &replacement.channel));
        coordinator.finish_release("overlap", released);
        assert!(Arc::ptr_eq(
            &replacement.channel,
            &coordinator.history_channel("overlap")
        ));
        assert!(replacement.channel.subscribe().borrow().fault.is_none());
        Ok(())
    }
}
