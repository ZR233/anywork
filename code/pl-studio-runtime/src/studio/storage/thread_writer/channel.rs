//! Reliable admission, retained-byte accounting and per-Thread writer lifecycle.

use super::*;

pub(super) const MAX_HISTORY_BATCHES: usize = 4096;
pub(super) const MAX_HISTORY_THREAD_BYTES: u64 = 64 * 1024 * 1024;
pub(super) const MAX_HISTORY_PROCESS_BYTES: u64 = 256 * 1024 * 1024;
pub(super) const NO_PROGRESS_WINDOW: Duration = Duration::from_secs(60);
/// Conservative retained charge for the bounded age index entry owned by one queued effect.
pub(super) const PENDING_AGE_METADATA_BYTES: u64 = std::mem::size_of::<(i64, u64)>() as u64 + 64;

/// The serial projection owner's charged residents. The pending batch is named so
/// that handing its same Arc to the reliable queue transfers its existing charge.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct ProjectionRetention {
    /// Projection/activity state and pending live events; excludes the prepared batch.
    pub resident_bytes: u64,
    pub pending: Option<PendingProjectionRetention>,
}

impl ProjectionRetention {
    fn total_bytes(self) -> u64 {
        self.resident_bytes
            .saturating_add(self.pending.map_or(0, |pending| pending.prepared_bytes))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct PendingProjectionRetention {
    pub sequence: u64,
    pub prepared_bytes: u64,
}

/// Moves already charged report content from the pending batch into the managed
/// terminal owner. Source validation and the net new charge share one boundary.
#[derive(Debug, Clone, Copy)]
pub(crate) struct ProjectionTransfer {
    pub source: PendingProjectionRetention,
    pub after: ProjectionRetention,
}

/// One admitted effect waiting for its ordered durable write.
#[derive(Debug)]
pub(super) struct QueuedEffect {
    pub(super) _conversation: Option<Arc<crate::studio::conversation_store::ConversationStore>>,
    pub(super) sequence: u64,
    /// Starts the private batching deadline; later arrivals never reset it.
    pub(super) admitted_at: Instant,
    pub(super) write: Arc<HistoryExport>,
    /// Encoded size of `write.effect`, measured once at admission.
    pub(super) bytes: u64,
    /// The product content the Thread's single live projection owner prepared for this commit.
    ///
    /// `None` until the projection owner took the fact over. The writer never projects an effect
    /// itself, so a fact whose reliable handoff is still unfinished stays queued instead of being
    /// written out of the projection's order.
    pub(super) prepared: Option<Arc<PreparedEffect>>,
    /// Retained bytes of `prepared`, charged to the reliable budget while this entry holds it.
    pub(super) prepared_bytes: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum HistoryStage {
    ProjectionPrepare,
    WriterQueue,
    SqlCommit,
}

impl HistoryStage {
    pub(super) fn as_str(self) -> &'static str {
        match self {
            Self::ProjectionPrepare => "projection_prepare",
            Self::WriterQueue => "writer_queue",
            Self::SqlCommit => "sql_commit",
        }
    }
}

#[derive(Debug, Default)]
pub(super) struct Progress {
    pub(super) stopped: bool,
    pub(super) deleting: bool,
    /// Highest effect sequence whose History transaction completed.
    pub(super) durable: u64,
    /// Admitted effects awaiting their ordered History transaction.
    ///
    /// An entry leaves the queue only once the durable store committed it *and* the Thread's single
    /// live projection owner took it over, so this queue is the one reliable handoff between a core
    /// commit and both durable history and the live product.
    pub(super) effects: VecDeque<QueuedEffect>,
    /// Identity and usage baseline of the original queue's frozen transaction prefix.
    pub(super) in_flight: Option<batch::FrozenBatch>,
    /// Highest fixed barrier target; cancelling a waiter does not retract its request.
    pub(super) flush_target: u64,
    pub(super) effect_bytes: u64,
    /// Conservatively charged entries in `pending_saved_at`.
    pub(super) queue_metadata_bytes: u64,
    /// Counts original effect timestamps so the maximum age needs no queue scan.
    pub(super) pending_saved_at: BTreeMap<i64, u64>,
    pub(super) pending_accounting: Option<PendingAccounting>,
    /// Retained bytes of the prepared batches the queue still holds.
    ///
    /// A prepared batch is the immutable product content the projection owner published, and the
    /// queue holds it until the effect is durable: its text is real resident memory, so it is
    /// charged to the Thread's reliable budget instead of hiding outside it. It is released with the
    /// queue entry and never double-counted against that effect's own encoded size.
    pub(super) prepared_bytes: u64,
    /// Bytes the Thread's live projection currently retains in its own tables.
    ///
    /// The projection owner publishes this absolute gauge after every projection step. It is what
    /// keeps the Thread's budget honest past durability: the retained bodies and the report
    /// accumulator outlive the prepared batch the writer already committed, so without this the
    /// Thread would claim to be drained while still holding its Turn's process bodies.
    pub(super) projection_bytes: u64,
    /// The sole pending batch included in projection_bytes, before queue handoff.
    pub(super) projection_pending: Option<PendingProjectionRetention>,
    /// Newest commit the Thread's live projection owner has handed over.
    ///
    /// This is the handoff ticket the projection's own durability barrier asks for: effects are
    /// admitted in order and the owner hands its batch over in the same order, so "the writer is
    /// durable through this commit" is exactly "every fact this owner handed over is saved". A
    /// channel that has handed nothing over is at `0`, so a projection installed on a restored
    /// Thread — whose commits were already durable before this process started — never waits for a
    /// watermark that cannot move.
    pub(super) handoff: u64,
    /// Encoded bytes of the effect currently being written.
    pub(super) in_flight_bytes: u64,
    /// Whether the newest admitted state paused inference admission under storage pressure.
    pub(super) pressure_paused: bool,
    /// Cumulative usage summary folded through the effects committed so far.
    ///
    /// This is the running value hot reads see. Each effect folds its own absolute increment out of
    /// a clone of this value and sets the result on its checkpoint, so the summary that becomes
    /// durable with an effect is exactly the one this field advances to on that same commit.
    pub(super) usage: UsageSummary,
    pub(super) error: Option<String>,
    pub(super) fault: Option<crate::HistoryFault>,
    pub(super) fault_generation: u64,
    /// Whether the newest fault generation's retry has been verified as really landed.
    ///
    /// It stays `false` from the moment a fault is latched until a retry made the fixed target
    /// durable and published — the only fact that makes an explicit continue acceptable. A later
    /// fault clears it again, so a stale verification never vouches for a newer failure.
    pub(super) fault_recovered: bool,
    pub(super) fault_target: u64,
    pub(super) retry_requested: bool,
    /// The oldest undurable obligation's actual stage, shared with the existing watchdog.
    pub(super) stage: Option<HistoryStage>,
    pub(super) last_progress_at: Option<Instant>,
    /// Actual accepted output, separate from each operation's upper bound.
    pub(super) operation_output: BTreeMap<String, OperationOutput>,
}

impl Progress {
    pub(super) fn enter_stage(&mut self, stage: Option<HistoryStage>, now: Instant) {
        if self.stage != stage {
            self.stage = stage;
            self.last_progress_at = stage.map(|_| now);
        }
    }

    pub(super) fn refresh_head_stage(&mut self, now: Instant) {
        // Admissions and projection handoffs cannot end an outstanding SQL call.
        if self.stage == Some(HistoryStage::SqlCommit) {
            return;
        }
        let stage = self.effects.front().map(|head| {
            if head.prepared.is_some() {
                HistoryStage::WriterQueue
            } else {
                HistoryStage::ProjectionPrepare
            }
        });
        self.enter_stage(stage, now);
    }

    pub(super) fn prepared_through(&self) -> u64 {
        let mut through = self.durable;
        for effect in &self.effects {
            if effect.prepared.is_none() || through.checked_add(1) != Some(effect.sequence) {
                break;
            }
            through = effect.sequence;
        }
        through
    }
    /// Locate a sequence in the continuous original queue without scanning it.
    pub(super) fn queue_offset(&self, sequence: u64) -> Option<usize> {
        let first = self.effects.front()?.sequence;
        let offset = usize::try_from(sequence.checked_sub(first)?).ok()?;
        self.effects
            .get(offset)
            .is_some_and(|queued| queued.sequence == sequence)
            .then_some(offset)
    }

    /// The projection handoff advances continuously from the durable or handed-over tail.
    fn next_unprojected_offset(&self) -> Option<usize> {
        let sequence = self.durable.max(self.handoff).checked_add(1)?;
        self.queue_offset(sequence)
    }

    pub(super) fn admit_saved_at(&mut self, saved_at: i64) {
        *self.pending_saved_at.entry(saved_at).or_default() += 1;
        self.queue_metadata_bytes = self
            .queue_metadata_bytes
            .saturating_add(PENDING_AGE_METADATA_BYTES);
    }

    pub(super) fn release_saved_at(&mut self, saved_at: i64) {
        let remove = {
            let count = self
                .pending_saved_at
                .get_mut(&saved_at)
                .expect("queued effect has an age index entry");
            *count -= 1;
            *count == 0
        };
        if remove {
            self.pending_saved_at.remove(&saved_at);
        }
        self.queue_metadata_bytes = self
            .queue_metadata_bytes
            .saturating_sub(PENDING_AGE_METADATA_BYTES);
    }
}

#[derive(Debug)]
pub(super) struct PendingAccounting {
    pub(super) projection: crate::studio::storage::calls::SessionUsageProjection,
    pub(super) attempts: u8,
    pub(super) retry_at: Instant,
}

#[derive(Debug)]
struct OperationOutput {
    pub(super) limit: u64,
    pub(super) accepted: u64,
    pub(super) transferred: u64,
}

impl OperationOutput {
    pub(super) fn retained(&self) -> u64 {
        self.accepted - self.transferred
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct HistoryStatus {
    pub(crate) fault_generation: u64,
    pub(crate) fault: Option<crate::HistoryFault>,
    pub(crate) error: Option<String>,
    pub(crate) admitted_sequence: u64,
    pub(crate) committed_sequence: u64,
    pub(crate) queued_records: u64,
    pub(crate) queued_bytes: u64,
}

/// What the writer loop has to do next.
/// Reliable admission state owned by the session manager, not by a writer incarnation.
pub(crate) struct HistoryChannel {
    pub(super) order_index: Arc<RuntimeOrderIndex>,
    #[cfg(test)]
    pub(crate) effects_released: tokio::sync::watch::Sender<u64>,
    #[cfg(test)]
    pub(crate) terminal_parked: tokio::sync::watch::Sender<u64>,
    pub(super) progress: Mutex<Progress>,
    pub(super) changed: Arc<tokio::sync::Notify>,
    pub(super) step_lock: tokio::sync::Mutex<()>,
    /// Every writer incarnation's physical workers remain registered until actually joined.
    /// Registration and explicit stop share this gate, including cancellation during startup.
    pub(super) workers: tokio::sync::Mutex<Vec<tokio::task::JoinHandle<()>>>,
    worker_failure: Mutex<Option<Arc<tokio::task::JoinError>>>,
    deletion_joined: std::sync::atomic::AtomicBool,
    pub(in crate::studio::storage) stopping: tokio_util::sync::CancellationToken,
    /// The process-wide reliable budget, shared by every Thread's channel.
    ///
    /// It charges the effects the channels hold (their admission encoding plus bounded queue
    /// metadata), and the accepted output still retained by in-flight model/tool operations, each
    /// byte once. A fact produced by that operation takes those bytes over at admission instead of
    /// adding a second charge for the same output, and both charges are released when the fact
    /// becomes durable or the call ends without one.
    ///
    /// The prepared batches and the live projection's retained bodies are deliberately *not* part of
    /// this process counter: they are the same product content the queued effect already charged,
    /// kept alive by a different owner, so charging them here would count one body twice and make the
    /// process limit fire at half the memory it names. They are charged to the owning Thread's
    /// budget instead, which is the enforced per-Thread gate (`StoragePressure::thread_bytes`).
    pub(super) process_bytes: Arc<AtomicU64>,
    /// Logical-source budget shared across joined storage-only writer replacements.
    pub(super) delivery_bytes: Arc<AtomicU64>,
    /// Short admission pins share the logical delivery source across replacements.
    pub(super) delivery_admissions: Arc<AtomicU64>,
    pub(super) status: tokio::sync::watch::Sender<HistoryStatus>,
    pub(super) pressure_changed: tokio::sync::watch::Sender<()>,
    pub(super) capacity_changed: Option<tokio::sync::watch::Sender<u64>>,
}

/// A managed producer releases its additional resident copy on success, error or cancellation.
pub(crate) struct ReviewDeliveryRetention {
    channel: Arc<HistoryChannel>,
    bytes: u64,
    coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
    thread_id: String,
}

/// Keeps the registry row alive while channel accounting runs outside its lock.
pub(crate) struct ReviewDeliveryAdmission {
    channel: Arc<HistoryChannel>,
    coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
    thread_id: String,
}

impl Drop for ReviewDeliveryAdmission {
    fn drop(&mut self) {
        self.channel
            .delivery_admissions
            .fetch_sub(1, Ordering::AcqRel);
        self.coordinator
            .release_delivery_channel(&self.thread_id, &self.channel);
    }
}

impl Drop for ReviewDeliveryRetention {
    fn drop(&mut self) {
        let progress = self
            .channel
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.channel
            .delivery_bytes
            .fetch_sub(self.bytes, Ordering::AcqRel);
        self.channel.report(&progress);
        drop(progress);
        self.channel.release_process_bytes(self.bytes);
        self.coordinator
            .release_delivery_channel(&self.thread_id, &self.channel);
    }
}

impl HistoryChannel {
    /// Called under the registry lock; this only pins an atomic logical source,
    /// and never acquires progress or index.
    pub(crate) fn pin_review_delivery(
        self: &Arc<Self>,
        coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
        thread_id: String,
    ) -> ReviewDeliveryAdmission {
        self.delivery_admissions.fetch_add(1, Ordering::AcqRel);
        ReviewDeliveryAdmission {
            channel: self.clone(),
            coordinator,
            thread_id,
        }
    }

    pub(super) fn other_resident_bytes(progress: &Progress) -> u64 {
        progress
            .effect_bytes
            .saturating_add(progress.queue_metadata_bytes)
            .saturating_add(progress.prepared_bytes)
            .saturating_add(progress.projection_bytes)
            .saturating_add(
                progress
                    .operation_output
                    .values()
                    .map(OperationOutput::retained)
                    .sum::<u64>(),
            )
    }

    /// All channel resident mutations hold progress, then the index. The store is the
    /// linearization point seen by synchronous identity reservations; reports have no authority.
    pub(super) fn commit_residents(&self, progress: &Progress, index: &OrderIndexState) {
        self.order_index
            .set_other_resident_bytes(index, Self::other_resident_bytes(progress));
    }

    /// Caller holds the index lock, so no provider allocation can spend this same headroom.
    fn check_residents(&self, other_bytes: u64, added_delivery: u64) -> Result<()> {
        ensure!(
            other_bytes
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(added_delivery)
                .saturating_add(self.order_index.retained_bytes())
                <= MAX_HISTORY_THREAD_BYTES,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        Ok(())
    }

    /// Actual retained capacity was returned, independently from whether the per-Thread status
    /// also shrank (projection/delivery bytes may have changed concurrently). Atomic failed-claim
    /// rollback stays local. A charged guard's teardown can also finish a refused resident check;
    /// consumers must compare pre-attempt watermarks, never treat a notification alone as progress.
    pub(super) fn release_process_bytes(&self, bytes: u64) {
        if bytes == 0 {
            return;
        }
        self.process_bytes.fetch_sub(bytes, Ordering::AcqRel);
        self.pressure_changed.send_replace(());
        if let Some(capacity) = &self.capacity_changed {
            capacity.send_modify(|revision| *revision = revision.wrapping_add(1));
        }
    }
    #[cfg(test)]
    pub(crate) fn retained_delivery_bytes(&self) -> u64 {
        self.delivery_bytes.load(Ordering::Acquire)
    }
    pub(crate) fn with_capacity(
        process_bytes: Arc<AtomicU64>,
        capacity: tokio::sync::watch::Sender<u64>,
    ) -> Self {
        let mut channel = Self::new(process_bytes);
        channel
            .order_index
            .set_capacity_notifier(Some(capacity.clone()));
        channel.capacity_changed = Some(capacity);
        channel
    }
    pub(in crate::studio::storage) fn retain_terminal_bytes(
        &self,
        bytes: u64,
        transfer: ProjectionTransfer,
    ) -> Result<Arc<AtomicU64>> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure!(
            progress.projection_pending == Some(transfer.source),
            "terminal material does not own the charged pending batch"
        );
        let after = transfer
            .after
            .pending
            .context("terminal transfer lost its pending batch")?;
        ensure!(
            after.sequence == transfer.source.sequence
                && after.prepared_bytes <= transfer.source.prepared_bytes
                && transfer.after.resident_bytes
                    == progress
                        .projection_bytes
                        .checked_sub(transfer.source.prepared_bytes)
                        .context("invalid charged projection retention")?,
            "terminal transfer changed unrelated projection residents"
        );
        let mut index = self.order_index.lock_state();
        let other = Self::other_resident_bytes(&progress)
            .checked_sub(progress.projection_bytes)
            .context("invalid projection budget")?
            .saturating_add(transfer.after.total_bytes());
        if let Err(error) = self.check_residents(other, bytes) {
            index.resident_blocked = true;
            return Err(error);
        }
        // Projection bytes were never charged a second time to the process. The managed copy
        // owns its process charge in full, while the Thread only funds the net ownership growth.
        if !self.reserve(bytes) {
            index.resident_blocked = true;
            anyhow::bail!(ExecutionIndexBudgetFull { scope: "process" });
        }
        self.delivery_bytes.fetch_add(bytes, Ordering::AcqRel);
        progress.projection_bytes = transfer.after.total_bytes();
        progress.projection_pending = transfer.after.pending;
        index.resident_blocked = false;
        self.commit_residents(&progress, &index);
        drop(index);
        self.report(&progress);
        Ok(self.delivery_bytes.clone())
    }

    /// Cold enumeration owns newly loaded authority, without a live pending batch
    /// whose existing charge could be transferred.
    pub(in crate::studio::storage) fn retain_cold_terminal_bytes(
        &self,
        bytes: u64,
    ) -> Result<Arc<AtomicU64>> {
        self.charge_review_delivery(bytes)?;
        Ok(self.delivery_bytes.clone())
    }

    pub(in crate::studio::storage) fn refresh_terminal_bytes(&self) {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.report(&progress);
    }
    pub(crate) fn delivery_retry_mark(&self) -> (u64, u64, bool, u64, u64) {
        let status = self.status.borrow();
        (
            status.committed_sequence,
            status.fault_generation,
            status.error.is_some(),
            status.queued_bytes,
            self.process_bytes.load(Ordering::Acquire),
        )
    }
    pub(in crate::studio) fn terminal_material_bytes(
        &self,
        authority: &crate::thread_assembler::review_dispatch::TerminalAuthority,
        original: &pl_core::thread::inbox::ThreadMessage,
        finish: Option<&pl_tool::finish_turn::SavedFinishTurn>,
    ) -> u64 {
        // The producer retains these materials only, not an effect, prepared items or checkpoint.
        // The queue's normal prepared/effect accounting owns those until its durable ACK.
        (original.payload.content().len() as u64)
            .saturating_mul(2)
            .saturating_add(original.id.len() as u64)
            .saturating_add(original.source_id.len() as u64)
            .saturating_add(authority.retained_bytes())
            .saturating_add(finish.map_or(
                0,
                crate::thread_assembler::review_dispatch::finish_material_bytes,
            ))
            .saturating_add(4096)
    }
    /// The caller holds a logical-source admission pin, without the registry lock.
    /// The pin prevents idle-row cleanup while channel accounting takes progress -> index.
    pub(crate) fn charge_review_delivery(&self, bytes: u64) -> Result<()> {
        anyhow::ensure!(
            bytes <= MAX_HISTORY_THREAD_BYTES.min(MAX_HISTORY_PROCESS_BYTES),
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "terminal material exceeds the reliable byte ceiling"
            )
        );
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let index = self.order_index.lock_state();
        anyhow::ensure!(
            !index.resident_blocked,
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        self.check_residents(Self::other_resident_bytes(&progress), bytes)
            .map_err(|_| crate::thread_assembler::review_dispatch::TerminalBudgetBlocked)?;
        anyhow::ensure!(
            self.reserve(bytes),
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        self.delivery_bytes.fetch_add(bytes, Ordering::AcqRel);
        drop(index);
        self.report(&progress);
        Ok(())
    }

    pub(crate) fn retain_charged_review_delivery(
        self: &Arc<Self>,
        bytes: u64,
        coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
        thread_id: String,
    ) -> Result<ReviewDeliveryRetention> {
        let retained = ReviewDeliveryRetention {
            channel: self.clone(),
            bytes,
            coordinator,
            thread_id,
        };
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let index = self.order_index.lock_state();
        let result = self.check_residents(Self::other_resident_bytes(&progress), 0);
        drop(index);
        self.report(&progress);
        drop(progress);
        anyhow::ensure!(
            result.is_ok(),
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        Ok(retained)
    }

    pub(crate) fn has_delivery_bytes(&self) -> bool {
        self.delivery_bytes.load(Ordering::Acquire) > 0
            || self.delivery_admissions.load(Ordering::Acquire) > 0
    }
    pub(crate) fn shares_delivery_budget(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.delivery_bytes, &other.delivery_bytes)
    }

    /// The old physical workers were joined by the storage-only owner. Carry only the logical
    /// producer budget/wakeup, never an old queue, core sequence or writer incarnation.
    pub(crate) fn next_storage_channel(&self) -> Self {
        let mut channel = Self::new(self.process_bytes.clone());
        // A stopped storage-only writer may still have a live producer holding reservations.
        // A resident ConversationStore must keep that same allocator across writer replacement.
        // Only a fully unreferenced index can restart from its scalar ceiling.
        if self.order_index.has_pending() || Arc::strong_count(&self.order_index) > 1 {
            channel.order_index = self.order_index.clone();
        } else {
            let ceiling = self.order_index.ceiling();
            channel.order_index = Arc::new(RuntimeOrderIndex::with_delivery(
                self.process_bytes.clone(),
                ceiling,
                self.delivery_bytes.clone(),
            ));
        }
        channel.delivery_bytes = self.delivery_bytes.clone();
        channel.delivery_admissions = self.delivery_admissions.clone();
        channel.pressure_changed = self.pressure_changed.clone();
        channel.capacity_changed = self.capacity_changed.clone();
        channel
            .order_index
            .set_capacity_notifier(channel.capacity_changed.clone());
        channel
    }
    /// Wait only for an already handed-over effect, never for a producer's future projection.
    pub(crate) async fn await_handoff_durable(&self, id: &str, sequence: u64) -> Result<()> {
        ensure!(
            sequence <= self.handoff_ticket(),
            "history wait precedes reliable handoff"
        );
        self.request_flush(sequence);
        let mut status = self.subscribe();
        loop {
            {
                let status = status.borrow_and_update();
                if status.committed_sequence >= sequence {
                    return Ok(());
                }
                if let Some(error) = &status.error {
                    anyhow::bail!(
                        "Thread {id} history did not become durable through {sequence}: {error}"
                    );
                }
            }
            status
                .changed()
                .await
                .context("Thread history progress channel closed")?;
        }
    }

    pub(super) fn request_flush(&self, sequence: u64) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress.flush_target = progress.flush_target.max(sequence);
        drop(progress);
        self.changed.notify_one();
    }
    pub(crate) fn is_stopping(&self) -> bool {
        self.stopping.is_cancelled()
    }

    pub(crate) fn new(process_bytes: Arc<AtomicU64>) -> Self {
        let (status, _) = tokio::sync::watch::channel(HistoryStatus::default());
        let (pressure_changed, _) = tokio::sync::watch::channel(());
        let order_index = Arc::new(RuntimeOrderIndex::new(process_bytes.clone(), 0));
        let delivery_bytes = order_index.delivery_counter();
        Self {
            order_index,
            #[cfg(test)]
            effects_released: tokio::sync::watch::channel(0).0,
            #[cfg(test)]
            terminal_parked: tokio::sync::watch::channel(0).0,
            progress: Mutex::new(Progress::default()),
            changed: Arc::new(tokio::sync::Notify::new()),
            step_lock: tokio::sync::Mutex::new(()),
            workers: tokio::sync::Mutex::new(Vec::new()),
            worker_failure: Mutex::new(None),
            deletion_joined: std::sync::atomic::AtomicBool::new(false),
            stopping: tokio_util::sync::CancellationToken::new(),
            process_bytes,
            delivery_bytes,
            delivery_admissions: Arc::new(AtomicU64::new(0)),
            status,
            pressure_changed,
            capacity_changed: None,
        }
    }

    pub(super) fn reserve(&self, bytes: u64) -> bool {
        self.process_bytes
            .try_update(Ordering::AcqRel, Ordering::Acquire, |current| {
                current
                    .checked_add(bytes)
                    .filter(|total| *total <= MAX_HISTORY_PROCESS_BYTES)
            })
            .is_ok()
    }

    /// Registers an output ceiling without charging bytes that do not exist yet.
    /// The producer must charge each cumulative increment before retaining it.
    pub(super) fn reserve_operation_output(
        &self,
        operation_id: &str,
        max_bytes: u64,
    ) -> Option<u64> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(output) = progress.operation_output.get(operation_id) {
            return Some(output.limit);
        }
        if max_bytes == 0 || self.process_bytes.load(Ordering::Acquire) >= MAX_HISTORY_PROCESS_BYTES
        {
            return None;
        }
        progress.operation_output.insert(
            operation_id.to_owned(),
            OperationOutput {
                limit: max_bytes,
                accepted: 0,
                transferred: 0,
            },
        );
        Some(max_bytes)
    }

    /// Charges only newly accepted bytes. A transfer to an effect never resets the cumulative
    /// producer counter, so later progress cannot charge the same output again.
    pub(super) fn charge_operation_output(
        &self,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(output) = progress.operation_output.get(operation_id) else {
            return Err(cold_error("operation output quota is no longer registered"));
        };
        if accepted_bytes <= output.accepted {
            return Ok(());
        }
        let added = accepted_bytes - output.accepted;
        let index = self.order_index.lock_state();
        if index.resident_blocked
            || accepted_bytes > output.limit
            || self
                .check_residents(
                    Self::other_resident_bytes(&progress).saturating_add(added),
                    0,
                )
                .is_err()
            || !self.reserve(added)
        {
            return Err(cold_error(&format!(
                "operation {operation_id} cannot retain {added} additional output bytes"
            )));
        }
        progress
            .operation_output
            .get_mut(operation_id)
            .expect("registered output")
            .accepted = accepted_bytes;
        self.commit_residents(&progress, &index);
        drop(index);
        self.report(&progress);
        // Accepted output is part of pressure, but not the queue-only HistoryStatus.
        drop(progress);
        self.pressure_changed.send_replace(());
        Ok(())
    }

    pub(super) fn release_operation_output(&self, operation_id: &str) {
        let retained = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let index = self.order_index.lock_state();
            let retained = progress
                .operation_output
                .remove(operation_id)
                .map_or(0, |output| output.retained());
            self.commit_residents(&progress, &index);
            drop(index);
            self.report(&progress);
            retained
        };
        // OutputBudget::release can be the only remaining producer event, even cross-Thread.
        self.release_process_bytes(retained);
    }

    pub(crate) fn subscribe(&self) -> tokio::sync::watch::Receiver<HistoryStatus> {
        self.status.subscribe()
    }

    pub(in crate::studio) fn order_index(&self) -> Arc<RuntimeOrderIndex> {
        self.order_index.clone()
    }

    /// Publishes the bytes the Thread's live projection currently retains in its own tables.
    ///
    /// The projection owner is the only writer of this gauge, and it reports an absolute value, so
    /// the Thread's budget covers the report accumulator and the retained bodies without charging a
    /// cumulative estimate twice. It is reported through the same status the reliable queue uses,
    /// so a Thread whose projection still holds its Turn's bodies reads as pending work — which is
    /// what pauses new model/tool admission at a safe gap instead of growing unseen memory.
    pub(in crate::studio) fn set_projection_retention(
        &self,
        retention: ProjectionRetention,
    ) -> Result<()> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(pending) = retention.pending {
            let offset = progress.next_unprojected_offset();
            ensure!(
                offset.is_some_and(|offset| {
                    let effect = &progress.effects[offset];
                    effect.sequence == pending.sequence && effect.prepared.is_none()
                }),
                "projection retention does not name an unprepared admitted effect"
            );
        }
        if let Some(previous) = progress.projection_pending {
            ensure!(
                retention
                    .pending
                    .is_some_and(|pending| pending.sequence == previous.sequence),
                "projection still owns an untransferred pending batch"
            );
        }
        let mut index = self.order_index.lock_state();
        // These are the current materials of an already admitted fact, not a new allocation
        // request. Even on failure retain their full charge, preventing further allocations.
        progress.projection_bytes = retention.total_bytes();
        progress.projection_pending = retention.pending;
        self.commit_residents(&progress, &index);
        let result = self.check_residents(Self::other_resident_bytes(&progress), 0);
        let newly_blocked = result.is_err() && !index.resident_blocked;
        index.resident_blocked = result.is_err();
        drop(index);
        self.report(&progress);
        if newly_blocked {
            self.changed.notify_one();
        }
        result
    }

    pub(in crate::studio) fn release_projection_retention(&self) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut index = self.order_index.lock_state();
        progress.projection_bytes = 0;
        progress.projection_pending = None;
        index.resident_blocked = self
            .check_residents(Self::other_resident_bytes(&progress), 0)
            .is_err();
        self.commit_residents(&progress, &index);
        drop(index);
        self.report(&progress);
    }

    /// Newest commit the Thread's live projection owner has handed over to this channel.
    ///
    /// The projection owner waits on the writer's watermark only for facts it handed over itself, so
    /// this ticket — not an absolute commit sequence — is what its durability barrier targets. It is
    /// `0` while nothing was handed over, which is already durable.
    pub(crate) fn handoff_ticket(&self) -> u64 {
        self.progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .handoff
    }

    /// Hands the Thread's single live projection owner's prepared batch to the reliable handoff.
    ///
    /// The batch is attached to the admitted effect it belongs to, so the writer commits exactly the
    /// content the projection published instead of projecting the effect a second time. Only a fact
    /// this channel already admitted can be handed over — the projection owner reads its work from
    /// this same queue — so an unknown or already durable sequence is refused rather than stored in a
    /// second, unordered slot. Returns whether the batch was attached.
    pub(in crate::studio) fn prepare(&self, prepared: Arc<PreparedEffect>) -> bool {
        self.accept_prepared(None, prepared).is_ok()
    }

    /// 在唯一可靠记录上校验原批次及预算，再同步发布并接收同一原件。
    pub(in crate::studio) fn accept_prepared(
        &self,
        original: Option<&Arc<HistoryExport>>,
        prepared: Arc<PreparedEffect>,
    ) -> Result<()> {
        // Measure before taking the lock: the batch is immutable, and the owner's one estimate
        // (see `PreparedEffect::retained_bytes`) walks text lengths instead of encoding a payload
        // inside the critical section.
        let bytes = prepared.retained_bytes();
        let sequence = prepared.sequence;
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if sequence <= progress.durable {
            anyhow::bail!("reliable channel refused prepared effect");
        }
        let Some(index) = progress.queue_offset(sequence) else {
            anyhow::bail!("reliable channel refused prepared effect");
        };
        if let Some(original) = original {
            ensure!(
                Arc::ptr_eq(&progress.effects[index].write, original),
                "original effect is not this channel's accepted write"
            );
        }
        if let Some(existing) = &progress.effects[index].prepared {
            // Retries hand over the original frozen batch; replacing it could lose a published
            // completion or change the bytes behind an unchanged reliable-budget charge.
            ensure!(
                Arc::ptr_eq(existing, &prepared),
                "prepared effect identity differs"
            );
            return Ok(());
        }
        if progress.next_unprojected_offset() != Some(index) {
            anyhow::bail!("reliable channel refused prepared effect");
        }
        let mut order_index = self.order_index.lock_state();
        let transferred = match progress.projection_pending {
            Some(source) if source.sequence == sequence && source.prepared_bytes == bytes => bytes,
            Some(_) => anyhow::bail!("prepared effect budget differs"),
            None => 0,
        };
        let other = Self::other_resident_bytes(&progress);
        if (transferred == 0 && bytes > 0 && order_index.resident_blocked)
            || self
                .check_residents(other.saturating_add(bytes - transferred), 0)
                .is_err()
        {
            let newly_blocked = !order_index.resident_blocked;
            order_index.resident_blocked = true;
            if newly_blocked {
                self.changed.notify_one();
            }
            anyhow::bail!("reliable channel refused prepared effect");
        }
        if transferred > 0 || progress.projection_pending.is_some() {
            progress.projection_bytes -= transferred;
            progress.projection_pending = None;
        }
        progress.prepared_bytes = progress.prepared_bytes.saturating_add(bytes);
        progress.effects[index].prepared_bytes = bytes;
        progress.effects[index].prepared = Some(prepared);
        progress.handoff = sequence;
        progress.refresh_head_stage(Instant::now());
        self.commit_residents(&progress, &order_index);
        drop(order_index);
        let reported = self.report(&progress);
        drop(progress);
        if !reported {
            // A zero-byte handoff is still a new durable-work boundary, exactly once.
            self.status.send_modify(|_| {});
        }
        self.changed.notify_one();
        Ok(())
    }

    /// Oldest admitted effect the Thread's live projection owner has not taken over yet.
    ///
    /// The reliable queue is the Thread's one ordered handoff, so the projection owner consumes it in
    /// admission order: this is the next fact it owes a projection, and `None` while every admitted
    /// effect is already prepared. Nothing waits for a GUI — a Thread without subscribers still
    /// drains the queue, because the writer cannot save a fact no projection holds.
    pub(in crate::studio) fn next_unprojected(&self) -> Option<Arc<HistoryExport>> {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress
            .next_unprojected_offset()
            .and_then(|offset| progress.effects.get(offset))
            .map(|queued| queued.write.clone())
    }

    /// Publishes the failure of one admitted fact's projection.
    ///
    /// The writer never projects an effect itself, so a fact the projection owner cannot project is
    /// never handed over and never saved. Reporting it here is what makes the durable barrier fail
    /// closed with the projection's own reason — and what keeps `pressure()` agreeing with it —
    /// instead of waiting forever for a batch that will never arrive.
    ///
    /// An unchanged fault is published once. The projection owner re-observes the same pending fact
    /// on every owner snapshot, so re-publishing the identical status would wake its own status
    /// watcher and turn the failure into a busy loop instead of a paused, fail-closed Thread.
    pub(crate) fn fail_projection(&self, sequence: u64, message: String) {
        let published = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let published = progress.error.as_deref() != Some(message.as_str());
            if progress.error.is_none() {
                progress.fault_generation = progress.fault_generation.saturating_add(1);
                progress.retry_requested = false;
            }
            progress.fault_target = progress.fault_target.max(sequence);
            progress.fault = Some(crate::HistoryFault::WriteFailed);
            progress.error = Some(message);
            progress.fault_recovered = false;
            if published {
                self.diagnose(
                    &progress,
                    Instant::now(),
                    "projection_prepare",
                    crate::HistoryFault::WriteFailed,
                    &["projection_failed"],
                );
                self.report(&progress);
            }
            published
        };
        if published {
            self.changed.notify_one();
        }
    }

    pub(super) fn report(&self, progress: &Progress) -> bool {
        let previous_bytes = self.status.borrow().queued_bytes;
        let next = HistoryStatus {
            fault_generation: progress.fault_generation,
            fault: progress.fault,
            error: progress.error.clone(),
            admitted_sequence: progress
                .effects
                .back()
                .map_or(progress.durable, |queued| queued.sequence),
            committed_sequence: progress.durable,
            queued_records: progress.effects.len() as u64,
            queued_bytes: progress
                .effect_bytes
                .saturating_add(progress.queue_metadata_bytes)
                .saturating_add(progress.prepared_bytes)
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(progress.projection_bytes)
                .saturating_add(self.order_index.retained_bytes()),
        };
        let decreased = next.queued_bytes < previous_bytes;
        let changed = self.status.send_if_modified(|status| {
            if *status == next {
                return false;
            }
            *status = next;
            true
        });
        if changed {
            self.pressure_changed.send_replace(());
        }
        if decreased && let Some(capacity) = &self.capacity_changed {
            capacity.send_modify(|revision| *revision = revision.wrapping_add(1));
        }
        changed
    }

    pub(crate) fn retry(&self, generation: u64) -> Result<()> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure!(
            progress.error.is_some() && progress.fault_generation == generation,
            "history fault generation changed; refresh the session status"
        );
        progress.retry_requested = true;
        let mut index = self.order_index.lock_state();
        index.resident_blocked = self
            .check_residents(Self::other_resident_bytes(&progress), 0)
            .is_err();
        drop(index);
        drop(progress);
        // Explicit retry is an owner action even when its public status is unchanged.
        self.status.send_modify(|_| {});
        self.pressure_changed.send_replace(());
        self.changed.notify_one();
        Ok(())
    }

    /// Recheck the owning registry while holding progress, before publishing its terminal fault.
    /// The callback only inspects that registry and follows the report's progress -> registry order.
    pub(crate) fn mark_unavailable(&self, still_unowned: impl FnOnce() -> bool) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.effects.is_empty() || !still_unowned() {
            return;
        }
        if progress.error.is_none() {
            progress.fault_generation = progress.fault_generation.saturating_add(1);
        }
        progress.fault = Some(crate::HistoryFault::WriterUnavailable);
        progress.error = Some("history writer unavailable; queued facts retained".to_owned());
        progress.fault_recovered = false;
        progress.retry_requested = false;
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        self.report(&progress);
    }

    pub(crate) fn is_clean(&self) -> bool {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress.effects.is_empty() && progress.error.is_none()
    }

    /// Called only after the producer stopped and the observation's handoff became durable.
    /// Cancelling the waiter leaves the workers in this owner for a subsequent join.
    pub(crate) async fn stop_and_join(&self) -> Result<()> {
        self.stop_and_join_with_purpose(crate::thread_assembler::ClosePurpose::Preserve)
            .await
    }

    pub(crate) async fn stop_and_join_for_deletion(&self) -> Result<()> {
        self.stop_and_join_with_purpose(crate::thread_assembler::ClosePurpose::Delete)
            .await
    }

    pub(crate) fn deletion_joined(&self) -> bool {
        self.deletion_joined.load(Ordering::Acquire)
    }

    async fn stop_and_join_with_purpose(
        &self,
        purpose: crate::thread_assembler::ClosePurpose,
    ) -> Result<()> {
        let mut workers = self.workers.lock().await;
        {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            ensure!(
                purpose == crate::thread_assembler::ClosePurpose::Delete
                    || (progress.effects.is_empty() && progress.error.is_none()),
                "cannot stop a history writer with undurable facts"
            );
            progress.stopped = true;
            progress.deleting = purpose == crate::thread_assembler::ClosePurpose::Delete;
        }
        self.stopping.cancel();
        self.changed.notify_waiters();
        while let Some(worker) = workers.last_mut() {
            let joined = worker.await;
            workers.pop();
            if let Err(error) = joined {
                self.worker_failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .get_or_insert_with(|| Arc::new(error));
            }
        }
        let failure = self
            .worker_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(error) = failure {
            return Err(error).context("history worker failed while stopping");
        }
        if purpose == crate::thread_assembler::ClosePurpose::Delete {
            let (released, discarded) = {
                let mut progress = self
                    .progress
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let released = progress
                    .effect_bytes
                    .saturating_add(progress.queue_metadata_bytes)
                    .saturating_add(
                        progress
                            .operation_output
                            .values()
                            .map(OperationOutput::retained)
                            .sum::<u64>(),
                    );
                let discarded = (
                    std::mem::take(&mut progress.effects),
                    progress.in_flight.take(),
                    progress.projection_pending.take(),
                    progress.pending_accounting.take(),
                );
                progress.effect_bytes = 0;
                progress.queue_metadata_bytes = 0;
                progress.prepared_bytes = 0;
                progress.projection_bytes = 0;
                progress.in_flight_bytes = 0;
                progress.pending_saved_at.clear();
                progress.operation_output.clear();
                self.report(&progress);
                (released, discarded)
            };
            // Prepared material may release delivery guards that re-enter this channel.
            drop(discarded);
            self.release_process_bytes(released);
            self.deletion_joined.store(true, Ordering::Release);
        }
        ensure!(
            purpose == crate::thread_assembler::ClosePurpose::Delete || self.is_clean(),
            "history writer stopped with undurable facts"
        );
        Ok(())
    }

    pub(super) fn detect_stall(&self) {
        self.detect_stall_at(Instant::now());
    }

    pub(super) fn detect_stall_at(&self, now: Instant) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.error.is_some()
            || progress.effects.is_empty()
            || !progress
                .last_progress_at
                .is_some_and(|last| now.saturating_duration_since(last) >= NO_PROGRESS_WINDOW)
        {
            return;
        }
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault = Some(crate::HistoryFault::NoProgress);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        progress.error = Some("history writer made no progress with queued facts".to_owned());
        progress.fault_recovered = false;
        progress.retry_requested = false;
        self.diagnose(
            &progress,
            now,
            "watchdog",
            crate::HistoryFault::NoProgress,
            &["no_progress"],
        );
        self.report(&progress);
    }

    /// Log only identities, counters and bounded reason categories. Raw error Display/source
    /// strings may contain provider responses, paths or credentials and never enter this event.
    pub(super) fn diagnose(
        &self,
        progress: &Progress,
        now: Instant,
        source: &str,
        kind: crate::HistoryFault,
        reasons: &[&str],
    ) {
        let head = progress.effects.front();
        let execution_id = head
            .and_then(|effect| effect.write.state.execution.as_ref())
            .map(|execution| execution.id.as_str());
        // The reliable queue carries execution identity, not live provider request/generation
        // metadata. Attempt IDs and the execution counter cannot substitute for those identities.
        tracing::warn!(
            target: "conversation_work",
            operation = "history_persistence",
            thread_id = ?head.map(|effect| effect.write.effect.thread_id.as_str()),
            execution_id = ?execution_id,
            request_id = ?Option::<&str>::None,
            generation = ?Option::<u32>::None,
            effect = ?head.map(|effect| effect.sequence),
            stage = ?progress.stage.map(HistoryStage::as_str),
            stage_started_at = ?progress.last_progress_at,
            stage_elapsed_ms = ?progress.last_progress_at.map(|started|
                now.saturating_duration_since(started).as_millis().min(u128::from(u64::MAX)) as u64),
            head = ?head.map(|effect| effect.sequence),
            admitted = progress.effects.back().map_or(progress.durable, |effect| effect.sequence),
            prepared_through = progress.prepared_through(),
            durable = progress.durable,
            flush_target = ?(progress.flush_target > progress.durable).then_some(progress.flush_target),
            pending_count = progress.effects.len(),
            pending_bytes = progress.effect_bytes.saturating_add(progress.queue_metadata_bytes)
                .saturating_add(progress.prepared_bytes),
            fault_kind = ?kind,
            fault_generation = progress.fault_generation,
            error_source = source,
            reason_chain = ?reasons,
            "history persistence stalled or failed"
        );
    }
}

impl std::fmt::Debug for HistoryChannel {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryChannel")
            .finish_non_exhaustive()
    }
}
