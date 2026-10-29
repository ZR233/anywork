//! Per-Thread ordered persistence owner: each effect and its checkpoint commit in one transaction.
//!
//! Admission never blocks the executor. Effects are history facts, so every admitted batch is
//! written to `history.sqlite`/`calls.sqlite` in sequence order, each against the effect-matched
//! transfer state it arrived with. The matching checkpoint is not scheduled on its own: the writer
//! holds `write.checkpoint` as the candidate for exactly that effect and commits it together with
//! the effect's history facts, the latest context increment and the history watermark in one
//! `history.sqlite` transaction (`design/15` §15.5). There is no coalescing interval and no second
//! in-flight checkpoint, so no revision can be observed as dirty without its effect, and the
//! published revision always moves with the durable effect sequence.
//!
//! Publication order is fixed: every blob the checkpoint names must be durable first, and only then
//! is the transaction that writes the pruned checkpoint and advances the watermark committed. The
//! writer folds each effect's cumulative usage accounting exactly once, sets it on that effect's
//! checkpoint as `state.usage_summary`, and only publishes the running summary once the transaction
//! succeeded — so hot reads, reconnects and cold restores observe one cumulative value and a saved
//! checkpoint never carries a summary its own commit did not include.

use std::{
    collections::{BTreeMap, VecDeque},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::{Context, Result, ensure};
use pl_core::thread::{
    ThreadCheckpoint, ThreadSnapshot, UsageSummary,
    cold::{ColdStore, ColdStoreError, StoragePressure, ThreadWrite},
};
use tokio::time::Instant;

use crate::studio::StudioStore;
use crate::studio::storage::coordinator::ThreadPersistenceMetrics;
use crate::studio::storage::history::{
    EffectCommit, InputIdentityWrite, MessageIdentityWrite, is_retryable_write,
};
use crate::studio::thread_projection::PreparedEffect;

#[cfg(feature = "benchmarks")]
pub(crate) mod benchmark;
#[cfg(feature = "benchmarks")]
use super::calls::observation::Metric as BenchMetric;

/// How long one writer incarnation may keep retrying a transient storage conflict before it must
/// report it.
///
/// A short `SQLITE_BUSY`/`SQLITE_LOCKED`/`SQLITE_IOERR` is a self-healing conflict: the accepted
/// effects stay queued in order and the same `step` writes them again, so surfacing the error would
/// turn a conflict that resolves on its own into a terminal persistence failure that blocks the
/// next model admission. Only a conflict that outlives this window — or a structural, constraint
/// or corruption error, which is never retried — is reported and keeps failing the drain.
const RETRYABLE_BUSY_WINDOW: Duration = Duration::from_secs(30);
const MAX_HISTORY_BATCHES: usize = 4096;
const MAX_HISTORY_THREAD_BYTES: u64 = 64 * 1024 * 1024;
const MAX_HISTORY_PROCESS_BYTES: u64 = 256 * 1024 * 1024;
const NO_PROGRESS_WINDOW: Duration = Duration::from_secs(60);

/// Identity source for live per-Thread writer incarnations.
///
/// The coordinator keys its per-Thread watermarks by this value so a stopped writer can release
/// only its own state, and a replacement incarnation is never mistaken for the writer it replaced.
static NEXT_WRITER_INCARNATION: AtomicUsize = AtomicUsize::new(1);

/// One admitted effect waiting for its ordered durable write.
#[derive(Debug)]
struct QueuedEffect {
    sequence: u64,
    write: Arc<ThreadWrite>,
    /// Encoded size of `write.effect`, measured once at admission.
    bytes: u64,
    /// The product content the Thread's single live projection owner prepared for this commit.
    ///
    /// `None` until the projection owner took the fact over. The writer never projects an effect
    /// itself, so a fact whose reliable handoff is still unfinished stays queued instead of being
    /// written out of the projection's order.
    prepared: Option<Arc<PreparedEffect>>,
    /// Retained bytes of `prepared`, charged to the reliable budget while this entry holds it.
    prepared_bytes: u64,
}

#[derive(Debug, Default)]
struct Progress {
    stopped: bool,
    /// Highest effect sequence whose history/checkpoint transaction completed.
    durable: u64,
    /// Highest checkpoint revision already committed with its effect.
    published_revision: u64,
    /// Checkpoint revision of the effect whose atomic history+checkpoint write is in progress.
    saving_revision: u64,
    /// Admitted effects awaiting their ordered history/checkpoint transaction.
    ///
    /// An entry leaves the queue only once the durable store committed it *and* the Thread's single
    /// live projection owner took it over, so this queue is the one reliable handoff between a core
    /// commit and both durable history and the live product.
    effects: VecDeque<QueuedEffect>,
    /// Retained bytes of the prepared batches the queue still holds.
    ///
    /// A prepared batch is the immutable product content the projection owner published, and the
    /// queue holds it until the effect is durable: its text is real resident memory, so it is
    /// charged to the Thread's reliable budget instead of hiding outside it. It is released with the
    /// queue entry and never double-counted against that effect's own encoded size.
    prepared_bytes: u64,
    /// Bytes the Thread's live projection currently retains in its own tables.
    ///
    /// The projection owner publishes this absolute gauge after every projection step. It is what
    /// keeps the Thread's budget honest past durability: the retained bodies and the report
    /// accumulator outlive the prepared batch the writer already committed, so without this the
    /// Thread would claim to be drained while still holding its Turn's process bodies.
    projection_bytes: u64,
    /// Newest commit the Thread's live projection owner has handed over.
    ///
    /// This is the handoff ticket the projection's own durability barrier asks for: effects are
    /// admitted in order and the owner hands its batch over in the same order, so "the writer is
    /// durable through this commit" is exactly "every fact this owner handed over is saved". A
    /// channel that has handed nothing over is at `0`, so a projection installed on a restored
    /// Thread — whose commits were already durable before this process started — never waits for a
    /// watermark that cannot move.
    handoff: u64,
    /// Highest effect sequence whose call write was admitted.
    calls_admitted: u64,
    /// Highest effect sequence whose call write completed.
    calls_durable: u64,
    /// Encoded bytes of the effect currently being written.
    in_flight_bytes: u64,
    /// Whether the newest admitted state paused inference admission under storage pressure.
    pressure_paused: bool,
    /// Cumulative usage summary folded through the effects committed so far.
    ///
    /// This is the running value hot reads see. Each effect folds its own absolute increment out of
    /// a clone of this value and sets the result on its checkpoint, so the summary that becomes
    /// durable with an effect is exactly the one this field advances to on that same commit.
    usage: UsageSummary,
    error: Option<String>,
    fault: Option<pl_protocol::studio::HistoryFault>,
    fault_generation: u64,
    /// Whether the newest fault generation's retry has been verified as really landed.
    ///
    /// It stays `false` from the moment a fault is latched until a retry made the fixed target
    /// durable and published — the only fact that makes an explicit continue acceptable. A later
    /// fault clears it again, so a stale verification never vouches for a newer failure.
    fault_recovered: bool,
    fault_target: u64,
    retry_requested: bool,
    last_progress_at: Option<Instant>,
    /// Actual accepted output, separate from each operation's upper bound.
    operation_output: BTreeMap<String, OperationOutput>,
}

#[derive(Debug)]
struct OperationOutput {
    limit: u64,
    accepted: u64,
    transferred: u64,
}

impl OperationOutput {
    fn retained(&self) -> u64 {
        self.accepted - self.transferred
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct HistoryStatus {
    pub(crate) fault_generation: u64,
    pub(crate) fault: Option<pl_protocol::studio::HistoryFault>,
    pub(crate) error: Option<String>,
    pub(crate) admitted_sequence: u64,
    pub(crate) committed_sequence: u64,
    pub(crate) queued_records: u64,
    pub(crate) queued_bytes: u64,
}

/// What the writer loop has to do next.
enum Step {
    /// Progress was made; the loop runs another unit immediately.
    Progressed,
    /// Nothing to do yet; every admitted effect already carries its own checkpoint, so the loop
    /// just waits for the next admission or retry notification.
    Idle,
}

#[derive(Debug, thiserror::Error)]
#[error("{source}")]
struct ClassifiedWriteError {
    kind: pl_protocol::studio::HistoryFault,
    #[source]
    source: anyhow::Error,
}

fn classified(
    kind: pl_protocol::studio::HistoryFault,
    source: impl Into<anyhow::Error>,
) -> anyhow::Error {
    ClassifiedWriteError {
        kind,
        source: source.into(),
    }
    .into()
}

/// Reliable admission state owned by the session manager, not by a writer incarnation.
pub(crate) struct HistoryChannel {
    #[cfg(test)]
    pub(crate) effects_released: tokio::sync::watch::Sender<u64>,
    #[cfg(test)]
    pub(crate) terminal_parked: tokio::sync::watch::Sender<u64>,
    #[cfg(test)]
    initialization_gate: Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
    progress: Mutex<Progress>,
    changed: Arc<tokio::sync::Notify>,
    step_lock: tokio::sync::Mutex<()>,
    /// Every writer incarnation's physical workers remain registered until actually joined.
    /// Registration and explicit stop share this gate, including cancellation during startup.
    workers: tokio::sync::Mutex<Vec<tokio::task::JoinHandle<()>>>,
    worker_failure: Mutex<Option<Arc<tokio::task::JoinError>>>,
    stopping: tokio_util::sync::CancellationToken,
    /// The process-wide reliable budget, shared by every Thread's channel.
    ///
    /// It charges exactly two things, each byte once: the effects the channels hold, each at the
    /// encoded size it was admitted with, and the accepted output still retained by in-flight
    /// model/tool operations. A fact produced by that operation takes those bytes over at
    /// admission instead of adding a second charge for the same output, and both charges are
    /// released when the fact becomes durable or the call ends without one.
    ///
    /// The prepared batches and the live projection's retained bodies are deliberately *not* part of
    /// this process counter: they are the same product content the queued effect already charged,
    /// kept alive by a different owner, so charging them here would count one body twice and make the
    /// process limit fire at half the memory it names. They are charged to the owning Thread's
    /// budget instead, which is the enforced per-Thread gate (`StoragePressure::thread_bytes`).
    process_bytes: Arc<AtomicU64>,
    /// Logical-source budget shared across joined storage-only writer replacements.
    delivery_bytes: Arc<AtomicU64>,
    status: tokio::sync::watch::Sender<HistoryStatus>,
    pressure_changed: tokio::sync::watch::Sender<()>,
    capacity_changed: Option<tokio::sync::watch::Sender<u64>>,
}

/// A managed producer releases its additional resident copy on success, error or cancellation.
pub(crate) struct ReviewDeliveryRetention {
    channel: Arc<HistoryChannel>,
    bytes: u64,
    coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
    thread_id: String,
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
        self.channel.release_process_bytes(self.bytes);
        self.channel.report(&progress);
        drop(progress);
        self.coordinator
            .release_delivery_channel(&self.thread_id, &self.channel);
    }
}

impl HistoryChannel {
    /// Actual retained capacity was returned, independently from whether the per-Thread status
    /// also shrank (projection/delivery bytes may have changed concurrently). Atomic failed-claim
    /// rollback stays local. A charged guard's teardown can also finish a refused resident check;
    /// consumers must compare pre-attempt watermarks, never treat a notification alone as progress.
    fn release_process_bytes(&self, bytes: u64) {
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
        channel.capacity_changed = Some(capacity);
        channel
    }
    pub(super) fn retain_terminal_bytes(&self, bytes: u64) -> Arc<AtomicU64> {
        // These are already-existing immutable producer materials, not a fallible new copy.
        // Keep their process charge until the last queue/transfer/operation reference is gone.
        self.process_bytes.fetch_add(bytes, Ordering::AcqRel);
        self.delivery_bytes.fetch_add(bytes, Ordering::AcqRel);
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.report(&progress);
        self.delivery_bytes.clone()
    }
    pub(super) fn refresh_terminal_bytes(&self) {
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
    ) -> u64 {
        // The producer retains these materials only, not an effect, prepared items or checkpoint.
        // The queue's normal prepared/effect accounting owns those until its durable ACK.
        (original.payload.content().len() as u64)
            .saturating_mul(2)
            .saturating_add(original.id.len() as u64)
            .saturating_add(original.source_id.len() as u64)
            .saturating_add(authority.retained_bytes())
            .saturating_add(4096)
    }
    /// Called under the coordinator registry boundary, with no channel lock. Reserving before
    /// publishing the guard prevents an idle-row cleanup from orphaning a just-created producer.
    pub(crate) fn charge_review_delivery(&self, bytes: u64) -> Result<()> {
        anyhow::ensure!(
            bytes <= MAX_HISTORY_THREAD_BYTES.min(MAX_HISTORY_PROCESS_BYTES),
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "terminal material exceeds the reliable byte ceiling"
            )
        );
        anyhow::ensure!(
            self.reserve(bytes),
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        if self
            .delivery_bytes
            .try_update(Ordering::AcqRel, Ordering::Acquire, |current| {
                current
                    .checked_add(bytes)
                    .filter(|total| *total <= MAX_HISTORY_THREAD_BYTES)
            })
            .is_err()
        {
            // This undoes only this failed speculative claim; no retained capacity was freed.
            self.process_bytes.fetch_sub(bytes, Ordering::AcqRel);
            anyhow::bail!(crate::thread_assembler::review_dispatch::TerminalBudgetBlocked);
        }
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
        let resident = progress
            .effects
            .iter()
            .fold(progress.prepared_bytes, |total, effect| {
                total.saturating_add(effect.bytes)
            })
            .saturating_add(progress.projection_bytes)
            .saturating_add(self.delivery_bytes.load(Ordering::Acquire));
        self.report(&progress);
        drop(progress);
        anyhow::ensure!(
            resident <= MAX_HISTORY_THREAD_BYTES,
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        Ok(retained)
    }

    pub(crate) fn has_delivery_bytes(&self) -> bool {
        self.delivery_bytes.load(Ordering::Acquire) > 0
    }
    pub(crate) fn shares_delivery_budget(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.delivery_bytes, &other.delivery_bytes)
    }

    /// The old physical workers were joined by the storage-only owner. Carry only the logical
    /// producer budget/wakeup, never an old queue, core sequence or writer incarnation.
    pub(crate) fn next_storage_channel(&self) -> Self {
        let mut channel = Self::new(self.process_bytes.clone());
        channel.delivery_bytes = self.delivery_bytes.clone();
        channel.pressure_changed = self.pressure_changed.clone();
        channel.capacity_changed = self.capacity_changed.clone();
        channel
    }
    /// Wait only for an already handed-over effect, never for a producer's future projection.
    pub(crate) async fn await_handoff_durable(&self, id: &str, sequence: u64) -> Result<()> {
        ensure!(
            sequence <= self.handoff_ticket(),
            "history wait precedes reliable handoff"
        );
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
    pub(crate) fn is_stopping(&self) -> bool {
        self.stopping.is_cancelled()
    }

    pub(crate) fn new(process_bytes: Arc<AtomicU64>) -> Self {
        let (status, _) = tokio::sync::watch::channel(HistoryStatus::default());
        let (pressure_changed, _) = tokio::sync::watch::channel(());
        Self {
            #[cfg(test)]
            effects_released: tokio::sync::watch::channel(0).0,
            #[cfg(test)]
            terminal_parked: tokio::sync::watch::channel(0).0,
            #[cfg(test)]
            initialization_gate: Mutex::new(None),
            progress: Mutex::new(Progress::default()),
            changed: Arc::new(tokio::sync::Notify::new()),
            step_lock: tokio::sync::Mutex::new(()),
            workers: tokio::sync::Mutex::new(Vec::new()),
            worker_failure: Mutex::new(None),
            stopping: tokio_util::sync::CancellationToken::new(),
            process_bytes,
            delivery_bytes: Arc::new(AtomicU64::new(0)),
            status,
            pressure_changed,
            capacity_changed: None,
        }
    }

    fn reserve(&self, bytes: u64) -> bool {
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
    fn reserve_operation_output(&self, operation_id: &str, max_bytes: u64) -> Option<u64> {
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
    fn charge_operation_output(
        &self,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(output) = progress.operation_output.get_mut(operation_id) else {
            return Err(cold_error("operation output quota is no longer registered"));
        };
        if accepted_bytes <= output.accepted {
            return Ok(());
        }
        let added = accepted_bytes - output.accepted;
        if accepted_bytes > output.limit || !self.reserve(added) {
            return Err(cold_error(&format!(
                "operation {operation_id} cannot retain {added} additional output bytes"
            )));
        }
        output.accepted = accepted_bytes;
        Ok(())
    }

    fn release_operation_output(&self, operation_id: &str) {
        let retained = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            progress
                .operation_output
                .remove(operation_id)
                .map_or(0, |output| output.retained())
        };
        // OutputBudget::release can be the only remaining producer event, even cross-Thread.
        self.release_process_bytes(retained);
    }

    pub(crate) fn subscribe(&self) -> tokio::sync::watch::Receiver<HistoryStatus> {
        self.status.subscribe()
    }

    /// Publishes the bytes the Thread's live projection currently retains in its own tables.
    ///
    /// The projection owner is the only writer of this gauge, and it reports an absolute value, so
    /// the Thread's budget covers the report accumulator and the retained bodies without charging a
    /// cumulative estimate twice. It is reported through the same status the reliable queue uses,
    /// so a Thread whose projection still holds its Turn's bodies reads as pending work — which is
    /// what pauses new model/tool admission at a safe gap instead of growing unseen memory.
    pub(crate) fn set_projection_bytes(&self, bytes: u64) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.projection_bytes == bytes {
            return;
        }
        progress.projection_bytes = bytes;
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
            return false;
        }
        // Locate the entry by index so the budget update and the attach happen in one place without
        // holding a borrow of the queue while `prepared_bytes` changes.
        let Some(index) = progress
            .effects
            .iter()
            .position(|queued| queued.sequence == sequence)
        else {
            return false;
        };
        if progress.effects[index].prepared.is_none() {
            progress.prepared_bytes = progress.prepared_bytes.saturating_add(bytes);
            progress.effects[index].prepared_bytes = bytes;
        }
        progress.effects[index].prepared = Some(prepared);
        progress.handoff = progress.handoff.max(sequence);
        drop(progress);
        self.changed.notify_one();
        true
    }

    /// Oldest admitted effect the Thread's live projection owner has not taken over yet.
    ///
    /// The reliable queue is the Thread's one ordered handoff, so the projection owner consumes it in
    /// admission order: this is the next fact it owes a projection, and `None` while every admitted
    /// effect is already prepared. Nothing waits for a GUI — a Thread without subscribers still
    /// drains the queue, because the writer cannot save a fact no projection holds.
    pub(in crate::studio) fn next_unprojected(&self) -> Option<Arc<ThreadWrite>> {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress
            .effects
            .iter()
            .find(|queued| queued.prepared.is_none())
            .map(|queued| queued.write.clone())
    }

    /// Captures the bounded, ordered projection backlog for one observer initialization.
    /// Only immutable handles are cloned under the queue lock; history reads happen afterwards.
    pub(in crate::studio) fn unprojected_writes(&self) -> Vec<Arc<ThreadWrite>> {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress
            .effects
            .iter()
            .filter(|queued| queued.prepared.is_none())
            .map(|queued| queued.write.clone())
            .collect()
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
            progress.fault = Some(pl_protocol::studio::HistoryFault::WriteFailed);
            progress.error = Some(message);
            progress.fault_recovered = false;
            progress.saving_revision = 0;
            if published {
                self.report(&progress);
            }
            published
        };
        if published {
            self.changed.notify_one();
        }
    }

    fn report(&self, progress: &Progress) {
        let previous_bytes = self.status.borrow().queued_bytes;
        self.status.send_replace(HistoryStatus {
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
                .effects
                .iter()
                .map(|queued| queued.bytes)
                .sum::<u64>()
                .saturating_add(progress.prepared_bytes)
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(progress.projection_bytes),
        });
        self.pressure_changed.send_replace(());
        if self.status.borrow().queued_bytes < previous_bytes
            && let Some(capacity) = &self.capacity_changed
        {
            capacity.send_modify(|revision| *revision = revision.wrapping_add(1));
        }
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
        self.report(&progress);
        drop(progress);
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
        progress.fault = Some(pl_protocol::studio::HistoryFault::WriterUnavailable);
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
        let mut workers = self.workers.lock().await;
        {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            ensure!(
                progress.effects.is_empty() && progress.error.is_none(),
                "cannot stop a history writer with undurable facts"
            );
            progress.stopped = true;
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
        ensure!(
            self.is_clean(),
            "history writer stopped with undurable facts"
        );
        Ok(())
    }

    fn detect_stall(&self) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.error.is_some()
            || progress.effects.is_empty()
            || !progress
                .last_progress_at
                .is_some_and(|last| last.elapsed() >= NO_PROGRESS_WINDOW)
        {
            return;
        }
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault = Some(pl_protocol::studio::HistoryFault::NoProgress);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        progress.error = Some("history writer made no progress with queued facts".to_owned());
        progress.fault_recovered = false;
        progress.retry_requested = false;
        self.report(&progress);
    }
}

impl std::fmt::Debug for HistoryChannel {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryChannel")
            .finish_non_exhaustive()
    }
}

struct Inner {
    store: StudioStore,
    thread: pl_protocol::Thread,
    chat: pl_core::chat::Session,
    /// This writer incarnation's coordinator identity; see [`NEXT_WRITER_INCARNATION`].
    owner: usize,
    /// One durable history reader for the life of this writer.
    ///
    /// The history database is the single ordinal/identity allocator, so the writer opens it once
    /// instead of per effect; the pool has one connection, so every batch stays a short
    /// single-writer transaction and two consecutive effects cannot interleave their allocations.
    history: tokio::sync::OnceCell<crate::studio::storage::history::HistoryStore>,
    channel: Arc<HistoryChannel>,
    changed: Arc<tokio::sync::Notify>,
    call_observer_stop: tokio::sync::watch::Sender<bool>,
}

impl Drop for Inner {
    fn drop(&mut self) {
        self.call_observer_stop.send_replace(true);
    }
}

/// Cloneable sink attached to one core owner incarnation.
#[derive(Clone)]
pub(crate) struct ThreadStorageSink(Arc<Inner>);

/// One actual writer incarnation, retained through attachment and all close joins.
#[derive(Debug, Clone)]
pub(crate) struct ThreadStorageBinding {
    pub(crate) storage: pl_core::thread::cold::ColdStoreHandle,
    pub(crate) channel: Arc<HistoryChannel>,
}

impl std::fmt::Debug for ThreadStorageSink {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ThreadStorageSink")
            .field("thread_id", &self.0.thread.id)
            .finish_non_exhaustive()
    }
}

fn lock_progress(inner: &Inner) -> std::sync::MutexGuard<'_, Progress> {
    inner
        .channel
        .progress
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Encoded size of one effect, or `u64::MAX` when it cannot be encoded.
fn encoded_bytes(effect: &pl_core::thread::ThreadEffectBatch) -> u64 {
    effect
        .encode()
        .map_or(u64::MAX, |payload| payload.content().len() as u64)
}

/// Accepted output bytes that can transfer to the operation's durable fact.
fn retained_output_draw(progress: &Progress, operation: &str, want: u64) -> u64 {
    progress
        .operation_output
        .get(operation)
        .map_or(0, |output| output.retained().min(want))
}

/// Transfers already charged output to its producing operation's fact without charging twice.
/// Unrelated facts must fit the remaining budget; they cannot spend another operation's output.
/// The plan is computed before admission mutates either counter.
fn output_transfer_plan(
    progress: &Progress,
    funding: Option<&str>,
    bytes: u64,
) -> (Vec<(String, u64)>, u64) {
    let mut plan = Vec::new();
    let mut covered = 0_u64;
    if let Some(operation) = funding {
        let take = retained_output_draw(progress, operation, bytes);
        if take > 0 {
            covered += take;
            plan.push((operation.to_owned(), take));
        }
    }
    (plan, covered)
}

/// The writer's single durable history reader, opened on first use.
///
/// The handle comes from the per-Thread shared writer registry, so this sink's effect commit and a
/// live subscription's ordinal reservation share one ordered writer identity — one SQLite write
/// connection — instead of two independent writers racing for `history.sqlite`'s write lock. Reads
/// stay on their own read-only connections in WAL, so they are never queued behind this one.
async fn history_store(inner: &Inner) -> Result<crate::studio::storage::history::HistoryStore> {
    let opened = inner
        .history
        .get_or_try_init(|| async { inner.store.history(&inner.thread.id).await })
        .await?;
    Ok(opened.clone())
}

/// Publishes the current queue state so `wait_for_drain` and the product snapshot never report a
/// Thread as finished while an effect (and therefore its checkpoint) is still queued.
fn report(inner: &Inner, progress: &Progress) {
    inner.channel.report(progress);
    // The call recorder is one global writer shared by every Thread, so any owning writer can
    // publish its queue pressure; the coordinator stores the latest observation.
    let calls = inner.store.calls();
    inner
        .store
        .thread_persistence()
        .report_calls(calls.metrics());
    let pending = progress
        .effects
        .iter()
        .map(|queued| queued.sequence)
        .collect::<Vec<_>>();
    let pending_bytes = progress
        .effects
        .iter()
        .fold(0_u64, |total, queued| total.saturating_add(queued.bytes));
    // 每个待写 effect 自带它的候选 checkpoint，并与其在同一个事务落盘：队列非空就意味着历史与
    // checkpoint 都还 dirty，最老待写年龄因此只来自队列里每条 effect 自己的 saved_at。
    let pending_operations = progress.effects.len() as u64;
    let now = crate::studio::unix_seconds();
    let oldest_pending_age_millis = progress
        .effects
        .iter()
        .map(|queued| queued.write.checkpoint.saved_at)
        .map(|saved_at| {
            u64::try_from(now.saturating_sub(saved_at))
                .unwrap_or(0)
                .saturating_mul(1000)
        })
        .reduce(u64::min);
    let max_admitted = progress
        .effects
        .back()
        .map(|queued| queued.sequence)
        .unwrap_or(0);
    let dirty_revision = progress
        .effects
        .iter()
        .map(|queued| queued.write.checkpoint.state_revision)
        .max()
        .unwrap_or(progress.published_revision);
    let metrics = ThreadPersistenceMetrics {
        fault_generation: progress.fault_generation,
        fault: progress.fault,
        state_dirty_revision: dirty_revision,
        state_saving_revision: progress.saving_revision,
        state_durable_revision: progress.published_revision,
        history_admitted_sequence: max_admitted.max(progress.durable),
        history_durable_sequence: progress.durable,
        calls_admitted_sequence: progress.calls_admitted,
        calls_durable_sequence: progress.calls_durable,
        pending_operations,
        pending_bytes,
        in_flight_bytes: progress.in_flight_bytes,
        oldest_pending_age_millis,
        pressure_paused: progress.pressure_paused,
    };
    inner.store.thread_persistence().update(
        &inner.thread.id,
        inner.owner,
        pending,
        false,
        progress.error.clone(),
        metrics,
    );
}

fn clear_recovered_fault(progress: &mut Progress) {
    if progress.retry_requested
        && progress.durable >= progress.fault_target
        && progress.published_revision >= progress.fault_target
    {
        progress.error = None;
        progress.fault = None;
        progress.retry_requested = false;
        // The retry named this generation and the fixed target really landed, so an explicit
        // continue would be accepted now: that verified fact is what the UI is allowed to show.
        progress.fault_recovered = true;
    }
}

impl ThreadStorageSink {
    pub(crate) async fn new(
        store: StudioStore,
        thread: pl_protocol::Thread,
        restored_checkpoint: Option<&ThreadCheckpoint>,
    ) -> Result<Self> {
        let registered = store
            .catalog()
            .get(&thread.id)
            .context("Thread is not registered in the Studio catalog")?;
        anyhow::ensure!(
            registered.project_id == thread.project_id
                && store.workspaces().get(&thread.project_id).is_some(),
            "Thread {} Project identity is not registered in workspaces",
            thread.id
        );
        let owner = NEXT_WRITER_INCARNATION.fetch_add(1, Ordering::Relaxed);
        let registration = store.thread_persistence().claim(&thread.id, owner)?;
        let channel = registration.channel.clone();
        #[cfg(test)]
        {
            let gate = channel.initialization_gate.lock().unwrap().take();
            if let Some((entered, release)) = gate {
                let _ = entered.send(());
                let _ = release.await;
            }
        }
        let chat = store.chat_session(&thread.id).await?;
        chat.initialize_order_allocator().await?;
        let mut workers = channel.workers.lock().await;
        ensure!(
            !channel.stopping.is_cancelled(),
            "history writer is stopping"
        );
        // A preceding incarnation may still be finishing one write. Observe its committed
        // watermark and seed this incarnation while holding the channel's single-writer lease.
        let writer_lease = channel.step_lock.lock().await;
        let durable = store.history(&thread.id).await?.watermark().await?;
        let restored_fence = restored_checkpoint.map_or(0, |checkpoint| checkpoint.history_fence);
        ensure!(
            durable == restored_fence,
            "Thread {} history watermark {durable} does not match checkpoint fence {restored_fence}",
            thread.id
        );
        let (call_observer_stop, mut stop_observer) = tokio::sync::watch::channel(false);
        let inner = Arc::new(Inner {
            store,
            thread,
            chat,
            owner,
            history: tokio::sync::OnceCell::new(),
            changed: channel.changed.clone(),
            channel: channel.clone(),
            call_observer_stop,
        });
        // Report the shared queue only after this incarnation has initialized its durable fence.
        // Registration alone cannot discharge a predecessor's obligations: this report proves
        // which retained facts are adopted and which have already become durable.
        {
            let mut progress = lock_progress(&inner);
            progress.durable = progress.durable.max(durable);
            progress.published_revision = progress
                .published_revision
                .max(restored_checkpoint.map_or(0, |checkpoint| checkpoint.state_revision));
            report(&inner, &progress);
        }
        if let Ok(history) = history_store(&inner).await {
            publish_accounting(&inner, &history).await;
        }
        drop(writer_lease);
        let observer = Arc::downgrade(&inner);
        let calls = inner.store.calls().clone();
        let observer_stop = channel.stopping.clone();
        workers.push(tokio::spawn(async move {
            let mut durable_tickets = calls.subscribe_durable_ticket();
            loop {
                tokio::select! {
                    () = refresh_call_watermark(&calls, &observer) => {},
                    _ = stop_observer.changed() => break,
                    () = observer_stop.cancelled() => break,
                }
                tokio::select! {
                    Ok(()) = durable_tickets.changed() => {},
                    _ = tokio::time::sleep(Duration::from_secs(15)) => {
                        if let Some(inner) = observer.upgrade()
                            && let Ok(history) = history_store(&inner).await {
                            publish_accounting(&inner, &history).await;
                        }
                    },
                    _ = stop_observer.changed() => break,
                    () = observer_stop.cancelled() => break,
                }
            }
        }));
        let worker = inner.clone();
        let watchdog = Arc::downgrade(&inner);
        let watchdog_stop = channel.stopping.clone();
        workers.push(tokio::spawn(async move {
            while let Some(inner) = watchdog.upgrade() {
                inner.channel.detect_stall();
                drop(inner);
                tokio::select! {
                        () = tokio::time::sleep(Duration::from_secs(10)) => {},
                        () = watchdog_stop.cancelled() => break,
                }
            }
        }));
        workers.push(tokio::spawn(async move {
            let inner = worker;
            let _registration = registration;
            // 连续可重试失败的起点；任何一次成功的推进都清零。只有持续超过窗口才升级上报。
            let mut retrying_since: Option<Instant> = None;
            loop {
                // The task keeps the persistence owner alive while it owes facts, even when the
                // last Thread or GUI handle is dropped. Once clean it may release the connection.
                if inner.channel.stopping.is_cancelled() || Arc::strong_count(&inner) == 1 {
                    let progress = lock_progress(&inner);
                    if progress.effects.is_empty() && progress.error.is_none() {
                        return;
                    }
                }
                let paused = {
                    let progress = lock_progress(&inner);
                    progress.error.is_some()
                        && !progress.retry_requested
                        && progress.fault != Some(pl_protocol::studio::HistoryFault::QueueFull)
                };
                if paused {
                    // 通道可以把一个本 incarnation 自己没失败过的 Thread 标成失败：投影无法完成的
                    // 事实永远不会被交接，writer 因此既不写也不报错。协调器聚合的错误正是进程级
                    // drain 等待的那个事实，所以这里把通道的故障转成协调器可见的错误；否则暂停的
                    // 队列会把停机变成无界等待，而不是带着真实原因的显式失败。
                    {
                        let progress = lock_progress(&inner);
                        report(&inner, &progress);
                    }
                    tokio::select! {
                        () = inner.changed.notified() => {},
                        () = inner.channel.stopping.cancelled() => {},
                    }
                    continue;
                }
                match step(&inner).await {
                    Ok(Step::Progressed) => {
                        retrying_since = None;
                        continue;
                    }
                    Ok(Step::Idle) => {
                        // 无合并窗口：空闲只等下一次受理或重试通知，周期性醒来只为检测停顿。
                        tokio::select! {
                            () = tokio::time::sleep(Duration::from_secs(1)) => {}
                            () = inner.changed.notified() => {}
                            () = inner.channel.stopping.cancelled() => {}
                        }
                    }
                    Err(error) => {
                        let message = error.to_string();
                        let now = Instant::now();
                        let since = *retrying_since.get_or_insert(now);
                        if !is_retryable_write(&message)
                            || now.saturating_duration_since(since) >= RETRYABLE_BUSY_WINDOW
                        {
                            let kind = error
                                .downcast_ref::<ClassifiedWriteError>()
                                .map_or(pl_protocol::studio::HistoryFault::WriteFailed, |typed| {
                                    typed.kind
                                });
                            record_error(&inner, kind, message);
                            retrying_since = None;
                        } else {
                            note_absorbed_conflict(&inner);
                            tokio::select! {
                                () = tokio::time::sleep(Duration::from_secs(1)) => {},
                                () = inner.store.thread_persistence().retry_notified() => {},
                                () = inner.channel.stopping.cancelled() => {},
                            }
                        }
                    }
                }
            }
        }));
        drop(workers);
        Ok(Self(inner))
    }

    pub(crate) fn binding(&self) -> ThreadStorageBinding {
        ThreadStorageBinding {
            storage: pl_core::thread::cold::ColdStoreHandle::new(self.clone()),
            channel: self.0.channel.clone(),
        }
    }
}

async fn refresh_call_watermark(
    calls: &crate::studio::storage::calls::CallsStore,
    observer: &std::sync::Weak<Inner>,
) {
    let Some(inner) = observer.upgrade() else {
        return;
    };
    let id = inner.thread.id.clone();
    let store = inner.store.clone();
    drop(inner);
    #[cfg(feature = "benchmarks")]
    calls
        .observation()
        .increment(BenchMetric::ObserverWatermarkReadSql);
    #[cfg(feature = "benchmarks")]
    let observed_ticket = calls.durable_ticket();
    match calls.durable_effect_sequence(&id).await {
        Ok(sequence) => {
            let Some(inner) = observer.upgrade() else {
                return;
            };
            let mut progress = lock_progress(&inner);
            if sequence > progress.calls_durable {
                progress.calls_durable = sequence;
                progress.calls_admitted = progress.calls_admitted.max(sequence);
                report(&inner, &progress);
            }
            #[cfg(feature = "benchmarks")]
            calls
                .observation()
                .observer_refreshed(&id, observed_ticket, Ok(sequence));
        }
        Err(error) => {
            #[cfg(feature = "benchmarks")]
            calls
                .observation()
                .observer_refreshed(&id, observed_ticket, Err(error.to_string()));
            calls.mark_statistics_gap();
            tracing::warn!(thread_id = id, %error, "call watermark could not be read");
            store.thread_persistence().report_calls(calls.metrics());
        }
    }
}

/// Performs one unit of durable work.
async fn step(inner: &Inner) -> Result<Step> {
    let _single_writer = inner.channel.step_lock.lock().await;
    {
        let progress = lock_progress(inner);
        // Another attached writer may have failed while this worker waited for step_lock.
        // The pre-lock loop check is not permission to retry that newly published generation.
        if progress.error.is_some()
            && !progress.retry_requested
            && progress.fault != Some(pl_protocol::studio::HistoryFault::QueueFull)
        {
            return Ok(Step::Idle);
        }
    }
    // 每个 effect 与它自己的候选 checkpoint 在同一次事务落盘：队列顺序即提交顺序，不再有单独的
    // checkpoint 选择、合并窗口或发布步骤。
    let next_effect = lock_progress(inner).effects.front().map(|queued| {
        (
            queued.sequence,
            queued.write.clone(),
            queued.prepared.clone(),
        )
    });
    let Some((sequence, write, prepared)) = next_effect else {
        return Ok(Step::Idle);
    };
    // The Thread's live projection owner consumed this fact before the durable store may write it:
    // the writer commits the content that owner published instead of projecting the effect again, so
    // live and durable history can never disagree and durability never advances past a commit the
    // product has not published.
    let Some(prepared) = prepared else {
        return Ok(Step::Idle);
    };
    persist_effect(inner, sequence, &write, &prepared).await?;
    let mut progress = lock_progress(inner);
    if let Some(committed) = progress.effects.pop_front() {
        let bytes = committed.bytes;
        let prepared_bytes = committed.prepared_bytes;
        ensure!(
            committed.sequence == sequence,
            "history queue head changed before acknowledgement"
        );
        progress.prepared_bytes = progress.prepared_bytes.saturating_sub(prepared_bytes);
        inner.channel.release_process_bytes(bytes);
        progress.durable = progress.durable.max(sequence);
        progress.last_progress_at = (!progress.effects.is_empty()).then(Instant::now);
    }
    clear_recovered_fault(&mut progress);
    report(inner, &progress);
    drop(progress);
    inner.changed.notify_one();
    #[cfg(test)]
    {
        // Publish only after the writer's own local and queued handles were both released.
        // A terminal producer may still pin them; the history test distinguishes that owner.
        drop(write);
        drop(prepared);
        inner.channel.effects_released.send_replace(sequence);
    }
    Ok(Step::Progressed)
}

/// Atomically writes one effect's history, its latest context increment and its checkpoint.
///
/// The committed content is the immutable batch the Thread's single live projection owner prepared
/// for exactly this commit. The writer therefore never projects the effect a second time — the whole
/// product body is projected once, published once and written once — and the identity/revision pair
/// it confirms is the pair that owner handed over. The candidate is the effect's own
/// `write.checkpoint`; its cumulative usage is folded here, bound to the transaction and only
/// published to hot readers once the transaction succeeded.
async fn publish_accounting(
    inner: &Inner,
    history: &crate::studio::storage::history::HistoryStore,
) {
    #[cfg(feature = "benchmarks")]
    inner
        .store
        .calls()
        .observation()
        .increment(BenchMetric::AccountingRead);
    match history.accounting().await {
        Ok(Some(accounting)) => {
            use super::calls::{PurposeUsageProjection, SessionUsageProjection};
            let projection = SessionUsageProjection {
                root_thread_id: inner.thread.root_thread_id.clone(),
                thread_id: inner.thread.id.clone(),
                revision: accounting.revision,
                has_unpriced_usage: accounting.has_unpriced_usage,
                purpose_costs: accounting
                    .purpose_costs
                    .into_iter()
                    .map(|(purpose, estimated_costs)| PurposeUsageProjection {
                        purpose,
                        estimated_costs,
                    })
                    .collect(),
            };
            if let Err(error) = inner.store.calls().replace_session_usage(projection) {
                inner.store.calls().mark_statistics_gap();
                tracing::warn!(%error, "累计统计投影暂未更新，可靠会话累计值已保存");
            }
        }
        Ok(None) => {}
        Err(error) => {
            tracing::warn!(%error, "读取累计统计投影失败");
        }
    }
}

async fn persist_effect(
    inner: &Inner,
    sequence: u64,
    write: &ThreadWrite,
    projected: &PreparedEffect,
) -> Result<()> {
    ensure!(
        projected.sequence == sequence,
        "prepared history batch {sequence} was handed over as {}",
        projected.sequence
    );
    // 累计摘要按 effect 顺序折叠一次：从 writer 的运行值 clone，折叠本 effect 的绝对增量，放进该
    // effect 自己的 checkpoint，与它的历史事实在同一事务落盘。折叠只作用于 clone，事务失败时运行
    // 值不变，因此热读看到的总量绝不领先于已落库的 checkpoint。
    let summary = {
        let progress = lock_progress(inner);
        let mut summary = progress.usage.clone();
        crate::studio::thread_projection::fold_effect_accounting(&mut summary, &write.effect)?;
        summary
    };
    let mut checkpoint = write.checkpoint.clone();
    checkpoint.state.usage_summary = summary.clone();
    // 统一 blob fence：checkpoint 引用的附件 blob 必须已经 durable，才允许提交引用它们的事务。
    let referenced = crate::studio::thread_projection::referenced_attachment_ids(&checkpoint.state);
    {
        let mut progress = lock_progress(inner);
        #[cfg(feature = "benchmarks")]
        inner
            .store
            .calls()
            .observation()
            .increment(BenchMetric::EffectEncode);
        progress.in_flight_bytes = encoded_bytes(&write.effect);
        progress.saving_revision = checkpoint.state_revision;
        report(inner, &progress);
    }
    inner
        .store
        .blob_fence(&inner.thread.id, &referenced)
        .await
        .map_err(|error| classified(pl_protocol::studio::HistoryFault::BlobFailed, error))?;
    let history = history_store(inner).await?;
    // 一个事务同时写：effect 的历史事实（含重放身份索引）、effect.context 增量对应的最新上下文、
    // pruned checkpoint 以及 history watermark。任一步失败即整体回滚，绝不会出现"历史已推进但
    // checkpoint 未落盘"或反过来的半提交状态。
    let committed = history
        .commit_checkpoint_effect(
            &checkpoint,
            &write.effect,
            EffectCommit {
                items: &projected.items,
                rolled_back_turns: &rolled_back_turns(&write.checkpoint.state),
                identities: &durable_input_identities(&inner.thread.id, &write.checkpoint.state),
                messages: &admitted_message_identities(&write.effect),
                receipts: &{
                    #[cfg(feature = "benchmarks")]
                    inner
                        .store
                        .calls()
                        .observation()
                        .increment(BenchMetric::ReceiptExtraction);
                    fact_receipts(&write.effect, projected)?
                },
                tasks: &write.effect.tasks,
                deliveries: &write.effect.deliveries,
                delivery_repairs: &write.effect.delivery_repairs,
                attempt: write.effect.attempt.as_ref(),
            },
        )
        .await;
    {
        let mut progress = lock_progress(inner);
        progress.saving_revision = 0;
    }
    committed?;
    super::state::clear_checkpoint_recovery(&inner.thread.id);
    publish_accounting(inner, &history).await;
    // The writer confirms exactly the identity and revision this transaction committed, which is the
    // same batch the Thread's live projection published into the shared session before the handoff
    // reached this queue. No body is read back and no second content cache exists, so the saved
    // watermark can never drift from the published content.
    for item in &projected.items {
        inner.chat.confirm_saved(&item.id, item.revision);
    }
    if let Some(attempt) = &write.effect.attempt
        && !matches!(attempt.outcome, pl_core::thread::AttemptOutcome::Running)
    {
        // Only a terminal attempt releases speculative previews: a delayed Running save can arrive
        // after newer current/failed observations were published, and owns none of those bodies.
        // Never release an identity this transaction just
        // confirmed: the durable row owns that content and its window position even if the session
        // never saw the terminal publication or a slow producer published one more revision of it.
        inner.chat.drop_previews_with_prefix_except(
            &crate::studio::thread_projection::presentation_preview_prefix(&attempt.attempt_id),
            projected.items.iter().map(|item| item.id.as_str()),
        );
    }
    // 调用统计始终是独立的 best-effort：它与历史/checkpoint 事务无关，失败只影响可丢诊断。
    let statistics_admitted = inner.store.calls().try_admit_effect(&write.effect);
    // 事务成功后才发布运行值、已落库 revision 和用量累计。
    inner
        .store
        .thread_persistence()
        .set_usage(&inner.thread.id, summary.clone());
    {
        let mut progress = lock_progress(inner);
        if statistics_admitted {
            progress.calls_admitted = progress.calls_admitted.max(sequence);
        }
        progress.usage = summary;
        progress.published_revision = progress.published_revision.max(checkpoint.state_revision);
        progress.in_flight_bytes = 0;
        progress.pressure_paused = write.checkpoint.state.persistence.pressure_paused;
        report(inner, &progress);
    }
    Ok(())
}

/// Minimal durable identities of the messages one effect admitted.
///
/// The writer stores them in the same transaction as the effect's history, so a delivery that left
/// core's resident window can still be adjudicated from the per-Thread index. The digest comes from
/// core's own message digest over the frozen source/body/context fields, which is exactly what the
/// host recomputes when it repeats a delivery, so an identical repeat returns the original sequence
/// and a different body is rejected instead of delivered twice.
fn admitted_message_identities(
    effect: &pl_core::thread::ThreadEffectBatch,
) -> Vec<MessageIdentityWrite> {
    effect
        .inbox
        .iter()
        .map(|record| MessageIdentityWrite {
            message_id: record.message.id.clone(),
            item_id: crate::studio::thread_projection::order::message_id(&record.message.id),
            sequence: record.sequence,
            digest: Some(record.message.digest()),
        })
        .collect()
}

/// Minimal identities of every input this commit must be able to answer for.
///
/// A terminal input keeps its receipt so a repeated submission is answered after the resident
/// identity window (and the attachment drafts it referenced) are gone. A still-pending continuation
/// control is written too: its admission is the whole point of the operation, so the receipt has to
/// be readable before the input is consumed, while consuming and discarding later only move its
/// state forward in the same row.
///
/// A control input has no host prompt body, so its request digest binds the Thread and the
/// continuation it was admitted for instead of a payload that does not exist.
fn durable_input_identities(thread_id: &str, snapshot: &ThreadSnapshot) -> Vec<InputIdentityWrite> {
    use pl_core::thread::input::{InputPurpose, InputState};
    snapshot
        .inputs
        .iter()
        .filter(|record| {
            record.state != InputState::Pending
                || record.input.purpose == InputPurpose::Continuation
        })
        .map(|record| {
            let control = record
                .continuation
                .as_ref()
                .filter(|_| record.input.purpose == InputPurpose::Continuation);
            let mut entry = crate::studio::storage::state::InputIdentityEntry::new(
                pl_core::thread::input::input_identity(record),
                record.accepted_sequence,
            );
            if control.is_some() {
                // The frozen route revision and the admission revision belong to the first
                // admission; the write path preserves them, so only a first write fills them in.
                entry.expected_model_route_revision = frozen_route_revision(snapshot);
                entry.continuation_admission_revision = Some(record.revision);
            }
            InputIdentityWrite {
                entry,
                request_digest: match control {
                    Some(continuation) => Some(
                        crate::studio::thread_projection::continuation_request_digest(
                            thread_id,
                            &continuation.point_id,
                            frozen_route_revision(snapshot),
                        ),
                    ),
                    None => crate::studio::thread_projection::saved_prompt_request_digest(
                        &record.input.payload,
                    ),
                },
                presentation: crate::studio::thread_projection::input_presentation(record),
            }
        })
        .collect()
}

/// Route revision this Thread had when the control input was first written.
///
/// A control input is only admitted after the caller's frozen revision matched the saved one under
/// the same lifecycle lock, so the value the identity index keeps is the request's own frozen fact;
/// it is never rewritten by a later commit.
fn frozen_route_revision(snapshot: &ThreadSnapshot) -> Option<u64> {
    crate::studio::model_route::route_record(snapshot, false)
        .ok()
        .flatten()
        .map(|(record, _)| record.revision)
}

fn record_error(inner: &Inner, kind: pl_protocol::studio::HistoryFault, message: String) {
    {
        let mut progress = lock_progress(inner);
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        progress.retry_requested = false;
        progress.fault = Some(kind);
        progress.error = Some(message);
        progress.fault_recovered = false;
        // A failed publication is no longer being serialized; the retained checkpoint stays queued
        // for retry, and the metric must not keep reporting it as actively saving.
        progress.saving_revision = 0;
        report(inner, &progress);
    }
    inner.changed.notify_one();
}

/// Keeps the observable metrics honest while one retryable conflict is absorbed.
///
/// The failed step is no longer writing, so the in-flight byte gauge must not keep claiming a write
/// in progress; the queued effects stay counted, so the process-wide drain still waits and this
/// incarnation never looks settled. No error is published, so `pressure()`/`cold_error` stay clear
/// and the next model admission is not failed by a conflict the writer is still resolving.
fn note_absorbed_conflict(inner: &Inner) {
    let mut progress = lock_progress(inner);
    progress.in_flight_bytes = 0;
    progress.saving_revision = 0;
    report(inner, &progress);
}

impl ColdStore for ThreadStorageSink {
    fn reserve_observed_item(&self, thread_id: &str, item_id: &str) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence owner mismatch")),
            });
        }
        self.0
            .chat
            .reserve_order_in_memory(item_id)
            .map(|_| ())
            .map_err(|source| ColdStoreError {
                source: Box::new(source),
            })
    }

    fn subscribe_pressure(&self, thread_id: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        (thread_id == self.0.thread.id).then(|| self.0.channel.pressure_changed.subscribe())
    }

    fn reserve_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        max_bytes: u64,
    ) -> Result<u64, ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(cold_error("Thread persistence owner mismatch"));
        }
        self.0
            .channel
            .reserve_operation_output(operation_id, max_bytes)
            .ok_or_else(|| {
                // No headroom is backpressure, not a failed save: the caller waits at a storage
                // safety point and retries, and the Thread resumes by itself once the budget frees
                // up. Latching a hard fault here would turn a transient wait into a pause that only
                // an explicit resume could release.
                cold_error(&format!(
                    "reliable budget exhausted reserving operation {operation_id}"
                ))
            })
    }

    fn charge_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(cold_error("Thread persistence owner mismatch"));
        }
        // The typed refusal a ceiling cannot hold must reach the caller unchanged: it is what makes
        // the producer cancel the call with the bytes it already has instead of buffering output
        // this process could not retain.
        self.0
            .channel
            .charge_operation_output(operation_id, accepted_bytes)
    }

    fn release_operation_output(&self, thread_id: &str, operation_id: &str) {
        if thread_id == self.0.thread.id {
            self.0.channel.release_operation_output(operation_id);
        }
    }

    fn pressure(&self, thread_id: &str) -> StoragePressure {
        if thread_id != self.0.thread.id {
            return StoragePressure {
                error: Some(storage_error("Thread persistence owner mismatch")),
                ..Default::default()
            };
        }
        let progress = lock_progress(&self.0);
        // The Thread's budget covers every resident body this Thread presents, and one of them only
        // once: the effects still queued, the prepared product batches the reliable handoff still
        // retains (the writer's queue length alone would under-report a Thread whose projection is
        // already done but whose save is not), the bodies its live projection and report accumulator
        // keep after their batch became durable, and the accepted bytes retained by in-flight
        // model/tool output. Those accepted bytes are what a Thread about to publish its result
        // holds; leaving them out would report a Thread as idle while a call is buffering its answer.
        let reserved = progress
            .operation_output
            .values()
            .fold(0_u64, |total, output| {
                total.saturating_add(output.retained())
            });
        let bytes = progress
            .effects
            .iter()
            .fold(progress.prepared_bytes, |total, queued| {
                total.saturating_add(queued.bytes)
            })
            .saturating_add(progress.projection_bytes)
            .saturating_add(self.0.channel.delivery_bytes.load(Ordering::Acquire))
            .saturating_add(reserved);
        StoragePressure {
            thread_bytes: bytes,
            store_bytes: self.0.channel.process_bytes.load(Ordering::Acquire),
            // Typed durability receipt: the owner releases the live effect window from this at a
            // storage safety point instead of waiting for an explicit `flush` command.
            durable_sequence: progress.durable,
            // Typed fault category: the history channel already classifies its own failure, so no
            // consumer has to read the error text to know what failed.
            fault: progress.fault.map(storage_fault_kind),
            fault_generation: progress.fault_generation,
            // The writer's own recovery receipt, named by generation: `fault_recovered` means the
            // retry of *this* generation reached the fixed durable target, so the owner can require
            // that exact verdict before releasing the fault it holds instead of accepting an older
            // generation's success.
            recovered_generation: progress
                .fault_recovered
                .then_some(progress.fault_generation),
            error: progress.error.as_deref().map(storage_error),
        }
    }

    fn admit(&self, thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if self.0.channel.stopping.is_cancelled() {
            return Err(cold_error("history writer is stopped"));
        }
        if thread_id != self.0.thread.id
            || write.effect.thread_id != thread_id
            || write.checkpoint.thread_id != thread_id
            || write.effect.sequence != write.checkpoint.state_revision
            || write.checkpoint.history_fence != write.effect.sequence
        {
            // A contract failure is terminal for this sink and never a transient conflict: publish it
            // so `pressure().error` — the one report core mirrors into its own storage latch — agrees
            // with the error this call returns instead of letting the latch look recovered.
            record_error(
                &self.0,
                pl_protocol::studio::HistoryFault::WriteFailed,
                "Thread persistence ticket mismatch".to_owned(),
            );
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence ticket mismatch")),
            });
        }
        let sequence = write.effect.sequence;
        #[cfg(feature = "benchmarks")]
        self.0
            .store
            .calls()
            .observation()
            .increment(BenchMetric::EffectEncode);
        let bytes = encoded_bytes(&write.effect);
        let mut progress = lock_progress(&self.0);
        if progress.stopped {
            return Err(cold_error("history writer is stopped"));
        }
        if sequence > progress.durable
            && !progress
                .effects
                .iter()
                .any(|queued| queued.sequence == sequence)
        {
            let queued_bytes = progress
                .effects
                .iter()
                .fold(0_u64, |total, queued| total.saturating_add(queued.bytes));
            // The fact takes over the bytes of its own operation's reservation instead of being
            // charged next to them; only bytes not already charged need new headroom.
            let (transfer, covered) =
                output_transfer_plan(&progress, write.output_claim.as_deref(), bytes);
            let added = bytes.saturating_sub(covered);
            if progress.effects.len() >= MAX_HISTORY_BATCHES
                || queued_bytes
                    .checked_add(bytes)
                    .is_none_or(|total| total > MAX_HISTORY_THREAD_BYTES)
                || (added > 0 && !self.0.channel.reserve(added))
            {
                let message =
                    format!("history queue full for Thread {thread_id} at write_seq {sequence}");
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(pl_protocol::studio::HistoryFault::QueueFull);
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                report(&self.0, &progress);
                return Err(cold_error(&message));
            }
            for (operation, taken) in transfer {
                if let Some(output) = progress.operation_output.get_mut(&operation) {
                    output.transferred += taken;
                }
            }
            progress.effects.push_back(QueuedEffect {
                sequence,
                write: Arc::new(write.clone()),
                bytes,
                // The projection owner takes this entry over from the same queue, in this order.
                prepared: None,
                prepared_bytes: 0,
            });
            progress.last_progress_at.get_or_insert_with(Instant::now);
        }
        // 首次受理从 checkpoint 继承已折叠的累计摘要，然后只折叠本 incarnation 的新 effect。
        if progress.usage.applied_sequence == 0
            && write.checkpoint.state.usage_summary.applied_sequence > 0
        {
            progress.usage = write.checkpoint.state.usage_summary.clone();
        }
        progress.pressure_paused = write.checkpoint.state.persistence.pressure_paused;
        report(&self.0, &progress);
        drop(progress);
        self.0.changed.notify_one();
        Ok(())
    }

    async fn flush(&self, thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence owner mismatch")),
            });
        }
        // 固定目标只需等待它自己的 effect durable：checkpoint 与该 effect 在同一事务落盘，所以
        // durable 前进即意味着目标 checkpoint 也已提交，不再有独立的发布水位要等。
        self.0.changed.notify_one();
        let coordinator = self.0.store.thread_persistence().clone();
        let mut progress = coordinator.subscribe();
        // 第二个失败来源是可靠受理通道自己的状态：一个投影无法完成的事实永远到不了协调器的
        // 水位，只有通道会带着投影的真实原因报告它。只等协调器会把这种失败变成永久挂起，
        // 因此两处都必须唤醒这次屏障。
        let mut status = self.0.channel.subscribe();
        loop {
            {
                let local = lock_progress(&self.0);
                // The effect and its checkpoint commit atomically, so durable covers both: a released
                // owner never leaves an effect whose checkpoint is not yet committed behind.
                if local.durable >= sequence {
                    return Ok(());
                }
                if let Some(error) = local.error.clone() {
                    return Err(ColdStoreError {
                        source: Box::new(std::io::Error::other(error)),
                    });
                }
            }
            tokio::select! {
                changed = progress.changed() => {
                    changed.map_err(|_| ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "Thread persistence progress channel closed",
                        )),
                    })?;
                }
                changed = status.changed() => {
                    changed.map_err(|_| ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "Thread history status channel closed",
                        )),
                    })?;
                }
            }
        }
    }

    fn read_tool_task(
        &self,
        thread_id: &str,
        task_id: &str,
    ) -> impl std::future::Future<
        Output = Result<Option<pl_core::thread::cold::DurableToolTask>, ColdStoreError>,
    > + Send {
        let store = self.0.store.clone();
        let owner = self.0.thread.id.clone();
        let task_id = task_id.to_owned();
        async move {
            if thread_id != owner {
                return Err(cold_error("Thread persistence owner mismatch"));
            }
            store
                .history(&owner)
                .await
                .map_err(|error| cold_error(&error.to_string()))?
                .tool_task(&task_id)
                .await
                .map_err(|error| cold_error(&error.to_string()))
        }
    }
}

/// Durable receipts for the terminal interaction/permission facts one effect committed.
///
/// The receipt payload is the committed core record itself (its stable serde encoding is the
/// source of the digest) and its revision is the record's own revision, so a repeated terminal
/// command can be answered with the same receipt while a conflicting payload for one revision
/// fails the effect transaction instead of overwriting the accepted fact.
fn fact_receipts(
    effect: &pl_core::thread::ThreadEffectBatch,
    prepared: &PreparedEffect,
) -> Result<Vec<crate::studio::storage::history::FactReceiptWrite>> {
    let mut receipts = Vec::new();
    for fact in &prepared.review_delivery {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: fact.message.id.clone(),
            revision: 1,
            kind: "reviewDeliveryException",
            payload: serde_json::to_string(fact)?,
        });
    }
    if let Some(message) = &prepared.parent_report {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: message.id.clone(),
            revision: 1,
            kind: "parentReport",
            payload: serde_json::to_string(message)?,
        });
    }
    for record in effect.interactions.iter() {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: crate::studio::thread_projection::order::receipt_id(
                "interaction",
                &record.request.id,
            ),
            revision: record.revision,
            kind: "interaction",
            payload: serde_json::to_string(record)?,
        });
    }
    for record in effect.permissions.iter() {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: crate::studio::thread_projection::order::receipt_id("permission", &record.id),
            revision: record.revision,
            kind: "permission",
            payload: serde_json::to_string(record)?,
        });
    }
    Ok(receipts)
}

fn rolled_back_turns(snapshot: &ThreadSnapshot) -> std::collections::BTreeSet<String> {
    let mut removed = std::collections::BTreeSet::new();
    for replacement in snapshot.context_replacements.iter() {
        if replacement.reason != pl_core::thread::ContextReplacementReason::Rewind {
            continue;
        }
        let retained = replacement
            .current
            .records
            .iter()
            .filter_map(|record| record.turn_id.as_ref())
            .collect::<std::collections::BTreeSet<_>>();
        for record in replacement.previous.records.iter() {
            if let Some(turn) = &record.turn_id
                && !retained.contains(turn)
            {
                removed.insert(turn.clone());
            }
        }
    }
    removed
}

fn storage_error(message: &str) -> Arc<ColdStoreError> {
    Arc::new(ColdStoreError {
        source: Box::new(std::io::Error::other(message.to_owned())),
    })
}

/// The protocol's typed history fault as the core storage fault the owner mirrors.
///
/// Both sides are already typed values: this is a rename, not a classification. Core therefore never
/// sees an error string that it would have to interpret to know what failed.
fn storage_fault_kind(
    fault: pl_protocol::studio::HistoryFault,
) -> pl_core::thread::cold::StorageFaultKind {
    use pl_core::thread::cold::StorageFaultKind;
    use pl_protocol::studio::HistoryFault;
    match fault {
        HistoryFault::QueueFull => StorageFaultKind::QueueFull,
        HistoryFault::WriteFailed => StorageFaultKind::WriteFailed,
        HistoryFault::WriterUnavailable => StorageFaultKind::WriterUnavailable,
        HistoryFault::NoProgress => StorageFaultKind::NoProgress,
        HistoryFault::CheckpointFailed => StorageFaultKind::CheckpointFailed,
        HistoryFault::BlobFailed => StorageFaultKind::BlobFailed,
    }
}

/// One typed cold-store failure without the shared-error wrapper.
fn cold_error(message: &str) -> ColdStoreError {
    ColdStoreError {
        source: Box::new(std::io::Error::other(message.to_owned())),
    }
}

#[cfg(test)]
pub(crate) mod storage_fault_tests {
    use super::*;
    use crate::studio::storage::history::chat_item;
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        model::{
            DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
            ModelToolCall, PreparedModelCall,
        },
        thread::{
            ModelStepLimit, ThreadEffectBatch, ThreadHandle, ThreadSnapshot, TurnInput,
            TurnOutcome, TurnRecord, TurnState,
            cold::ColdStoreHandle,
            input::{InputChange, InputRecord, InputState, ThreadInput},
            task::TaskStatus,
        },
        tool::{
            ToolOutput,
            opaque::{CallContext, Registration, Tool, ToolError},
        },
    };
    use sea_orm::{ConnectionTrait, Database};
    use tokio::sync::{Notify, mpsc};
    use tokio_util::sync::CancellationToken;

    #[derive(Debug)]
    struct ConcurrentModel(Arc<AtomicUsize>);

    impl ModelSession for ConcurrentModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            self.0.fetch_add(1, Ordering::Relaxed);
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("running both tools"),
                    }],
                    tool_calls: ["first", "second"]
                        .into_iter()
                        .map(|id| ModelToolCall {
                            rejection: None,
                            call_id: id.to_owned(),
                            tool_id: id.to_owned(),
                            arguments: OpaquePayload::text(id),
                        })
                        .collect(),
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[derive(Debug)]
    struct ConcurrentTool {
        started: mpsc::UnboundedSender<String>,
        release: Arc<Notify>,
        executions: Arc<Mutex<Vec<String>>>,
    }

    impl Tool for ConcurrentTool {
        async fn execute(
            &self,
            input: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            self.executions
                .lock()
                .unwrap()
                .push(context.call_id.clone());
            self.started.send(context.call_id).unwrap();
            self.release.notified().await;
            Ok(ToolOutput::new(
                input.clone(),
                vec![ContextContent::Text {
                    text: Arc::from(input.content()),
                }],
            ))
        }
    }

    pub(crate) fn ticket(thread_id: &str, sequence: u64) -> ThreadWrite {
        let state = ThreadSnapshot {
            commit_sequence: sequence,
            ..Default::default()
        };
        ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread_id.to_owned(),
                sequence,
                committed_at: 1,
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread_id.to_owned(), sequence, state),
            output_claim: None,
        }
    }

    fn ticket_referencing_attachment(
        thread_id: &str,
        attachment: &crate::studio::AttachmentRecord,
    ) -> Result<ThreadWrite> {
        let mut write = ticket(thread_id, 1);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: "attached-input".to_owned(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({
                        "text": "attached",
                        "presentation": "visible",
                        "attachments": [attachment],
                    })
                    .to_string(),
                )?,
                context: Vec::new(),
            },
            ordinal: 1,
            revision: 1,
            state: InputState::Pending,
        };
        write.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Ok(write)
    }

    fn test_thread(thread_id: &str) -> pl_protocol::Thread {
        let mut thread = pl_protocol::Thread::placeholder(thread_id);
        thread.project_id = "project-test".into();
        thread.agent_path = thread_id.to_owned();
        thread.root_thread_id = thread_id.to_owned();
        thread
    }

    pub(crate) async fn register_test_thread(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
    ) -> Result<()> {
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

    async fn sink(thread_id: &str) -> Result<(tempfile::TempDir, StudioStore, ThreadStorageSink)> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread(thread_id);
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread, None).await?;
        spawn_live_projection(&sink);
        Ok((temp, store, sink))
    }

    pub(crate) struct CloseFactoryFixture {
        pub(crate) factory: crate::studio::StudioThreadFactory,
        pub(in crate::studio) writer: crate::studio::agent_host::ThreadWriteBehindWriter,
        pub(crate) config: crate::config::ConfigRuntime,
        pub(crate) events: crate::studio::ProductEventBus,
        store: StudioStore,
        worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    }
    impl CloseFactoryFixture {
        pub(crate) async fn unpublished_workspace(
            &self,
            id: &str,
            root: &std::path::Path,
        ) -> Result<crate::thread_assembler::WorkspacePreparationOwner> {
            use crate::studio::agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
            let usage = self
                .worktrees
                .reserve_workspace(id, WorkspaceEndpoint::Local)?;
            let identity = WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                dunce::canonicalize(root)?.to_string_lossy().into_owned(),
            )?;
            self.worktrees.assign_workspace(&usage, identity.clone())?;
            self.store.bind_workspace_identity(id, &identity).await?;
            self.worktrees.preserve_workspace_resources(id, identity);
            let files = root.join(pl_tool::workspace::SessionFiles::new(id).root());
            tokio::fs::create_dir_all(files.join("scratch")).await?;
            tokio::fs::write(files.join("scratch/prepared"), b"unpublished owned file").await?;
            let preparation = crate::thread_assembler::WorkspacePreparationOwner::default();
            preparation.retain(&usage);
            Ok(preparation)
        }
        pub(crate) fn workspace_is_busy(&self, id: &str) -> bool {
            self.worktrees.ensure_thread_workspace_idle(id).is_err()
        }
        pub(crate) fn install(
            &self,
            owner: &crate::thread_assembler::StudioThreadAssembler,
        ) -> Result<()> {
            let performance = crate::studio::ModelPerformanceOwner::new(
                self.store.clone(),
                self.events.clone(),
                "close-fault-fixture".into(),
            );
            owner.set_agent_services(
                self.config.clone(),
                self.store.clone(),
                self.events.clone(),
                self.factory.clone(),
                performance,
                crate::studio::StudioRecoveryRegistry::new(),
            )?;
            Ok(())
        }
        pub(crate) async fn shutdown(&self) -> Result<()> {
            self.writer.shutdown().await?;
            Ok(())
        }
    }

    pub(crate) fn close_factory(store: &StudioStore) -> Result<CloseFactoryFixture> {
        use crate::studio::thread_factory::{StudioThreadFactory, StudioThreadServices};
        let writer = crate::studio::agent_host::ThreadWriteBehindWriter::new(store.clone());
        let events = crate::studio::ProductEventBus::new(store.clone(), writer.clone());
        let config = crate::config::ConfigRuntime::initialize(crate::config::ConfigStore::new(
            crate::config::ConfigPaths::from_config_dir(
                store.paths().home().join("isolated-test-config"),
            ),
        ))?;
        let source = crate::worker_assets::RemoteHelperSource::External;
        let bots =
            crate::bots::BotRuntime::new(store.paths().clone(), config.clone(), events.clone())?;
        let worktrees =
            crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
        let factory = StudioThreadFactory::new(StudioThreadServices {
            store: store.clone(),
            worktrees: worktrees.clone(),
            product_events: events.clone(),
            config_runtime: config.clone(),
            mcp_runtime: pl_tool::mcp::McpRuntime::new(pl_tool::mcp::McpConnector::default())
                .handle(),
            lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry::new(),
            skills: crate::studio::runtime::SkillCatalogRuntime::new(
                events.clone(),
                store.paths().home().join("isolated-test-skills"),
            ),
            thread_modes: config.thread_mode_manager(),
            ssh_manager: Arc::new(crate::worker_assets::ssh_manager(&source)),
            helper_source: source,
            bots,
        });
        Ok(CloseFactoryFixture {
            factory,
            writer,
            config,
            events,
            store: store.clone(),
            worktrees,
        })
    }

    #[tokio::test]
    async fn close_intent_preserves_inherited_and_actual_assignment_for_subdirectory_projects()
    -> Result<()> {
        use crate::agent::worktree::{WorktreeManager, WorktreeOwnership};
        use crate::studio::agent_host::worktree_lease::{
            WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
            WorktreeLeaseState,
        };
        use pl_protocol::{
            AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, AgentWorktreeSnapshot,
        };
        async fn register(
            store: &StudioStore,
            thread: &pl_protocol::Thread,
            project_root: &std::path::Path,
        ) -> Result<()> {
            let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
                crate::studio::store::directory::ProjectDirectoryRecord {
                    id: thread.project_id.clone(),
                    name: "Subdirectory Project".into(),
                    path: project_root.to_string_lossy().into_owned(),
                    ssh_alias: None,
                    created_at: 1,
                    updated_at: 1,
                    last_opened_at: None,
                    closed: false,
                },
            );
            delta.thread_upserts.push(thread.clone());
            store.persist_directory_summaries(&delta).await
        }
        let temp = tempfile::tempdir()?;
        let repository = temp.path().join("repository");
        let project_root = repository.join("subdirectory");
        tokio::fs::create_dir_all(&project_root).await?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let mut root = test_thread("root-local");
        root.workspace_path = project_root.to_string_lossy().into_owned();
        register(&store, &root, &project_root).await?;
        let mut root_worktree = test_thread("root-worktree");
        root_worktree.workspace_mode = pl_protocol::ThreadWorkspaceMode::Worktree;
        let root_site = WorktreeManager::allocate_path(
            &repository,
            &root_worktree.id,
            &WorktreeOwnership::Session {
                thread_id: root_worktree.id.clone(),
            },
        );
        root_worktree.workspace_path = root_site.to_string_lossy().into_owned();
        register(&store, &root_worktree, &project_root).await?;
        let child_site = WorktreeManager::allocate_path(
            &repository,
            &root.id,
            &WorktreeOwnership::Child {
                child_id: "worktree-owner".into(),
            },
        );
        let child_receipt = AgentWorktreeSnapshot {
            repository_root: repository.to_string_lossy().into_owned(),
            path: child_site.to_string_lossy().into_owned(),
            base_commit: "a".repeat(40),
        };
        let mut cases = Vec::new();
        for (id, parent, mode, assigned, receipt, reviewed) in [
            (
                "worktree-owner",
                &root,
                AgentWorkspaceMode::Worktree,
                &child_site,
                Some(child_receipt.clone()),
                None,
            ),
            (
                "review-owner",
                &root,
                AgentWorkspaceMode::Review,
                &child_site,
                Some(child_receipt.clone()),
                Some(pl_protocol::AgentReviewTargetSnapshot {
                    baseline: None,
                    feedback: None,
                    agent_id: "worktree-owner".into(),
                }),
            ),
            (
                "directory-owner",
                &root,
                AgentWorkspaceMode::Directory,
                &project_root,
                None,
                None,
            ),
            (
                "session-directory-owner",
                &root_worktree,
                AgentWorkspaceMode::Directory,
                &root_site,
                None,
                None,
            ),
        ] {
            tokio::fs::create_dir_all(assigned).await?;
            let mut thread = test_thread(id);
            thread.parent_thread_id = Some(parent.id.clone());
            thread.root_thread_id = parent.id.clone();
            thread.workspace_path = parent.workspace_path.clone();
            thread.workspace_mode = parent.workspace_mode;
            register(&store, &thread, &project_root).await?;
            let assignment = AgentWorkspaceAssignmentSnapshot {
                mode,
                project_root: project_root.to_string_lossy().into_owned(),
                root: assigned.to_string_lossy().into_owned(),
                writable_paths: None,
                worktree: receipt,
                review_target: reviewed,
            };
            cases.push((thread, assignment));
        }
        store
            .persist_directory_summaries(
                &crate::studio::store::directory::DirectoryDelta::upsert_project(
                    crate::studio::store::directory::ProjectDirectoryRecord {
                        id: "project-test".into(),
                        name: "Subdirectory Project".into(),
                        path: project_root.to_string_lossy().into_owned(),
                        ssh_alias: None,
                        created_at: 1,
                        updated_at: 1,
                        last_opened_at: None,
                        closed: false,
                    },
                ),
            )
            .await?;
        let project = store.read_project("project-test").await?.unwrap();
        let fixture = close_factory(&store)?;
        for (owner, kind, root_id, path) in [
            (
                "worktree-owner",
                WorktreeLeaseOwnerKind::Child,
                root.id.as_str(),
                child_site.clone(),
            ),
            (
                root_worktree.id.as_str(),
                WorktreeLeaseOwnerKind::Session,
                root_worktree.id.as_str(),
                root_site.clone(),
            ),
        ] {
            let mut lease = WorktreeLease {
                revision: 1,
                state: WorktreeLeaseState::Prepared,
                owner_kind: kind,
                owner_thread_id: owner.into(),
                root_thread_id: root_id.into(),
                project_id: "project-test".into(),
                ssh_alias: None,
                repository_root: repository.to_string_lossy().into_owned(),
                path: path.to_string_lossy().into_owned(),
                base_commit: "a".repeat(40),
            };
            fixture.worktrees.record_durable(lease.clone()).await?;
            lease.transition(WorktreeLeaseState::Active);
            fixture.worktrees.record_durable(lease).await?;
        }
        for (thread, assignment) in cases {
            store.prepare_session_manifest(&thread).await?;
            let execution = std::path::Path::new(&assignment.root)
                .join(pl_tool::workspace::SessionFiles::new(&thread.id).root());
            tokio::fs::create_dir_all(&execution).await?;
            tokio::fs::write(execution.join("owned"), b"exact owner").await?;
            let identity =
                WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, assignment.root.clone())?;
            store.bind_workspace_identity(&thread.id, &identity).await?;
            let core =
                pl_core::thread::ThreadHandle::resume_without_model(thread.id.clone(), None)?;
            core.mutate_extensions(vec![
                pl_core::thread::extensions::ExtensionMutation::Put {
                    id: crate::studio::workspace_receipt::EXTENSION.into(),
                    expected_revision: None,
                    payload: crate::studio::workspace_receipt::to_payload(&assignment)
                        .map_err(anyhow::Error::msg)?,
                },
                pl_core::thread::extensions::ExtensionMutation::Put {
                    id: "studio.project".into(),
                    expected_revision: None,
                    payload: pl_core::context::OpaquePayload::new(
                        "pl.studio.project",
                        1,
                        serde_json::to_string(&project)?,
                    )?,
                },
            ])
            .await?;
            let close = fixture
                .factory
                .begin_child_close(&thread, Some(&core.snapshot()), false)
                .await?;
            if assignment.mode == AgentWorkspaceMode::Worktree {
                let owned = close.worktree.as_ref().context("actual owned worktree")?;
                assert_eq!(owned.lease.path, assignment.root);
                assert_eq!(owned.identity, identity);
                assert_ne!(thread.workspace_path, owned.lease.path);
            } else {
                assert!(
                    close.worktree.is_none(),
                    "directory/review must not acquire deletion ownership"
                );
            }
            assert_eq!(
                tokio::fs::read(execution.join("owned")).await?,
                b"exact owner"
            );
            let repeated = fixture
                .factory
                .begin_child_close(&thread, None, false)
                .await?;
            assert_eq!(close, repeated);
            core.close().await?;
        }
        fixture.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn unknown_old_close_candidates_preserve_source_and_refuse_new_delete_authority()
    -> Result<()> {
        use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let parent = test_thread("legacy-parent");
        register_test_thread(&store, &parent).await?;
        let mut child = test_thread("legacy-child");
        child.parent_thread_id = Some(parent.id.clone());
        child.root_thread_id = parent.id.clone();
        child.workspace_path = parent.workspace_path.clone();
        register_test_thread(&store, &child).await?;
        let source = store
            .registered_session_paths(&child.id)?
            .root()
            .join("retained-evidence");
        tokio::fs::create_dir_all(source.parent().unwrap()).await?;
        tokio::fs::write(&source, b"original history and attachments").await?;
        let payload = r#"{"unknownOriginalCloseFacts":true}"#;
        let hash = pl_core::context::content_hash(payload.as_bytes());
        store.database().execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "INSERT INTO studio_objects(owner_kind,owner_id,object_kind,schema_version,revision,payload_json,payload_hash,updated_at) VALUES ('thread',?,'agentRetirement',99,1,?,?,1)",
            [child.id.clone().into(), payload.to_owned().into(), hash.clone().into()])).await?;
        let fixture = close_factory(&store)?;
        assert!(
            store
                .ensure_agent_execution_allowed(&child.id)
                .await
                .is_err()
        );
        assert!(
            fixture
                .factory
                .begin_child_close(&child, None, true)
                .await
                .is_err()
        );
        assert!(store.agent_close(&child.id).await?.is_none());
        let row = store.database().query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "SELECT schema_version,payload_json,payload_hash FROM studio_objects WHERE owner_id=? AND object_kind='agentRetirement'",
            [child.id.into()])).await?.context("preserved unknown object")?;
        assert_eq!(row.try_get::<i64>("", "schema_version")?, 99);
        assert_eq!(row.try_get::<String>("", "payload_json")?, payload);
        assert_eq!(row.try_get::<String>("", "payload_hash")?, hash);
        assert_eq!(
            tokio::fs::read(source).await?,
            b"original history and attachments"
        );
        fixture.shutdown().await?;
        Ok(())
    }

    /// Replaces the former whole-resource retirement case with the actual close/storage contract:
    /// save ACKs, live borrowers, content protection, retained history/refs and replacement safety.
    #[tokio::test]
    async fn close_worktree_preserves_original_history_refs_and_terminal_replacements() -> Result<()>
    {
        use crate::agent::worktree::{
            LocalWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
        };
        use crate::studio::agent_close::AgentWorktreeCleanup;
        use crate::studio::agent_host::worktree_lease::{
            WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
            WorktreeLeaseState,
        };
        use pl_core::context::ResourceReader;
        use pl_core::thread::{ThreadHandle, cold::ColdStoreHandle, extensions::ExtensionMutation};

        async fn git(root: &std::path::Path, args: &[&str]) -> Result<String> {
            let output = tokio::process::Command::new("git")
                .args(args)
                .current_dir(root)
                .output()
                .await?;
            anyhow::ensure!(
                output.status.success(),
                "git {args:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            Ok(String::from_utf8(output.stdout)?.trim().to_owned())
        }
        let temp = tempfile::tempdir()?;
        let repository = temp.path().join("repository");
        tokio::fs::create_dir_all(&repository).await?;
        git(&repository, &["init", "--quiet"]).await?;
        git(&repository, &["config", "user.name", "Close fixture"]).await?;
        git(
            &repository,
            &["config", "user.email", "close@example.invalid"],
        )
        .await?;
        tokio::fs::write(repository.join(".gitignore"), b".anywork/\n").await?;
        tokio::fs::write(repository.join("tracked"), b"committed").await?;
        git(&repository, &["add", ".gitignore", "tracked"]).await?;
        git(
            &repository,
            &["commit", "--quiet", "-m", "fixture baseline"],
        )
        .await?;
        let repository = dunce::canonicalize(repository)?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let mut parent = test_thread("close-parent");
        parent.workspace_path = repository.to_string_lossy().into_owned();
        register_test_thread(&store, &parent).await?;
        let mut child = test_thread("close-owned-child");
        child.parent_thread_id = Some(parent.id.clone());
        child.root_thread_id = parent.id.clone();
        child.workspace_path = parent.workspace_path.clone();
        register_test_thread(&store, &child).await?;
        let fixture = close_factory(&store)?;
        let manager = WorktreeManager::new(
            repository.clone(),
            Arc::new(LocalWorktreeBackend::default()),
        );
        let ownership = WorktreeOwnership::Child {
            child_id: child.id.clone(),
        };
        let head = manager.resolve_head(&repository).await?;
        let mut lease = WorktreeLease {
            revision: 1,
            state: WorktreeLeaseState::Prepared,
            owner_kind: WorktreeLeaseOwnerKind::Child,
            owner_thread_id: child.id.clone(),
            root_thread_id: parent.id.clone(),
            project_id: child.project_id.clone(),
            ssh_alias: None,
            repository_root: parent.workspace_path.clone(),
            path: WorktreeManager::allocate_path(&repository, &parent.id, &ownership)
                .to_string_lossy()
                .into_owned(),
            base_commit: head.clone(),
        };
        fixture.worktrees.record_durable(lease.clone()).await?;
        let handle = manager
            .create(WorktreeCreateSpec {
                repo_root: repository.clone(),
                root_thread_id: parent.id.clone(),
                ownership,
                base_commit: head,
            })
            .await?;
        lease.transition(WorktreeLeaseState::Active);
        fixture.worktrees.record_durable(lease.clone()).await?;
        let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, lease.path.clone())?;
        store.bind_workspace_identity(&child.id, &identity).await?;
        store
            .bind_workspace_identity(
                &parent.id,
                &WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    parent.workspace_path.clone(),
                )?,
            )
            .await?;
        let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
            mode: pl_protocol::AgentWorkspaceMode::Worktree,
            project_root: parent.workspace_path.clone(),
            root: lease.path.clone(),
            writable_paths: None,
            review_target: None,
            worktree: Some(pl_protocol::AgentWorktreeSnapshot {
                repository_root: lease.repository_root.clone(),
                path: lease.path.clone(),
                base_commit: lease.base_commit.clone(),
            }),
        };
        let core = ThreadHandle::resume_without_model(child.id.clone(), None)?;
        let sink = ThreadStorageSink::new(store.clone(), child.clone(), None).await?;
        spawn_live_projection(&sink);
        core.attach_storage(ColdStoreHandle::new(sink)).await?;
        core.mutate_extensions(vec![ExtensionMutation::Put {
            id: crate::studio::workspace_receipt::EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::workspace_receipt::to_payload(&assignment)
                .map_err(anyhow::Error::msg)?,
        }])
        .await?;
        let resources =
            crate::resource_store::FileResourceStore::new(store.session_resources_dir(&child.id)?);
        let reference = resources
            .retain_bytes(
                Arc::from(&b"reliable original attachment"[..]),
                "text/plain",
            )
            .await?;
        let independent_files =
            repository.join(pl_tool::workspace::SessionFiles::new(&parent.id).root());
        tokio::fs::create_dir_all(&independent_files).await?;
        tokio::fs::write(
            independent_files.join("retained"),
            b"independent session files",
        )
        .await?;
        let borrower = fixture
            .worktrees
            .reserve_workspace("active-reviewer", WorkspaceEndpoint::Local)?;
        fixture
            .worktrees
            .assign_workspace(&borrower, identity.clone())?;
        fixture
            .factory
            .begin_child_close(&child, Some(&core.snapshot()), false)
            .await?;
        crate::studio::agent_close::commit(&core).await?;
        core.close().await?;
        store
            .thread_persistence()
            .history_channel(&child.id)
            .stop_and_join()
            .await?;
        let history = store.history(&child.id).await?;
        let saved = serde_json::to_vec(&history.checkpoint().await?)?;
        fixture.factory.finish_child_execution(&child).await?;
        let (blocked, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(blocked.execution_closed);
        assert!(
            error
                .context("active borrower must block")?
                .message
                .contains("active-reviewer")
        );
        assert!(matches!(
            blocked.worktree_cleanup,
            AgentWorktreeCleanup::Failed { .. }
        ));
        drop(borrower);
        tokio::fs::write(handle.path.join("tracked"), b"uncommitted child work").await?;
        let (dirty, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(error.is_some());
        assert!(matches!(
            dirty.worktree_cleanup,
            AgentWorktreeCleanup::Failed { .. }
        ));
        assert!(tokio::fs::try_exists(&handle.path).await?);
        git(&handle.path, &["add", "tracked"]).await?;
        git(
            &handle.path,
            &["commit", "--quiet", "-m", "undelivered child work"],
        )
        .await?;
        let before_refusal_head = git(&handle.path, &["rev-parse", "HEAD"]).await?;
        // Detached creation owns no branch. An independently created business ref must survive
        // close even when the child checks it out after its ownership was frozen.
        let retained_branch = "retained-business";
        git(&handle.path, &["switch", "-c", retained_branch]).await?;
        let (_, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(
            error
                .context("undelivered HEAD must block default close")?
                .message
                .contains("not contained")
        );
        assert!(
            store.agent_close(&child.id).await?.unwrap().git.is_none(),
            "content refusal must precede the destructive grant, preserving a force retry"
        );
        fixture
            .factory
            .begin_child_close(&child, None, true)
            .await?;
        git(&repository, &["worktree", "lock", &lease.path]).await?;
        let (_, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(
            error
                .context("Git lock must still block force")?
                .message
                .contains("locked")
        );
        assert!(
            !store
                .agent_close(&child.id)
                .await?
                .unwrap()
                .git
                .unwrap()
                .removal_started,
            "a confirmed Git refusal plus the original remaining site permits a fresh attempt"
        );
        // A previous attempt's expected HEAD is content authorization, not permanent identity.
        tokio::fs::write(
            handle.path.join("tracked"),
            b"advanced after confirmed refusal",
        )
        .await?;
        git(&handle.path, &["add", "tracked"]).await?;
        git(
            &handle.path,
            &["commit", "--quiet", "-m", "advance after refused removal"],
        )
        .await?;
        let retained_head = git(&handle.path, &["rev-parse", "HEAD"]).await?;
        assert_ne!(retained_head, before_refusal_head);
        git(&repository, &["worktree", "unlock", &lease.path]).await?;
        let (removed, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(error.is_none(), "{error:?}");
        assert_eq!(
            removed.worktree_cleanup,
            AgentWorktreeCleanup::Removed {
                path: lease.path.clone()
            }
        );
        assert!(!tokio::fs::try_exists(&handle.path).await?);
        assert_eq!(
            git(&repository, &["rev-parse", retained_branch]).await?,
            retained_head
        );
        assert_eq!(serde_json::to_vec(&history.checkpoint().await?)?, saved);
        assert_eq!(
            &*resources.read(reference, Default::default()).await?,
            b"reliable original attachment"
        );
        assert_eq!(
            tokio::fs::read(independent_files.join("retained")).await?,
            b"independent session files"
        );
        git(
            &repository,
            &["worktree", "add", &lease.path, retained_branch],
        )
        .await?;
        let (repeated, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(
            error.is_some(),
            "a terminal grant must not delete a replacement"
        );
        assert_eq!(repeated.worktree_cleanup, removed.worktree_cleanup);
        assert!(tokio::fs::try_exists(&handle.path).await?);
        fixture
            .factory
            .restore_workspace_admission(
                crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
            )
            .await?;
        assert!(tokio::fs::try_exists(&handle.path).await?);
        assert!(
            store
                .ensure_agent_execution_allowed(&child.id)
                .await
                .is_err()
        );
        assert!(history.checkpoint().await?.is_some());
        // A fresh process hydrates the top-level lease after it reads the close record. The old
        // preserved ownership must not resurrect a physical borrow once this result is terminal.
        let restarted = close_factory(&store)?;
        restarted
            .factory
            .restore_workspace_admission(
                crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
            )
            .await?;
        let container = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            repository.to_string_lossy().into_owned(),
        )?;
        let seal = restarted.worktrees.try_seal_workspace(
            "new-container-owner",
            container.clone(),
            &std::collections::BTreeSet::new(),
        )?;
        restarted
            .worktrees
            .release_workspace_seal("new-container-owner", &container)?;
        drop(seal);
        assert!(
            store
                .ensure_agent_execution_allowed(&child.id)
                .await
                .is_err()
        );
        restarted.shutdown().await?;
        fixture.shutdown().await?;
        Ok(())
    }

    /// Physical binding persistence and live admission share exact identities. The domain seal's
    /// producer still owns the grant ACK proof; this component does not execute a full close/Git.
    #[tokio::test]
    async fn saved_workspace_identity_keeps_preparers_and_pending_cleanup_until_release()
    -> Result<()> {
        use crate::studio::agent_host::{
            ThreadWriteBehindWriter,
            worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity, WorktreeLeaseOwner},
        };
        use std::collections::BTreeSet;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let root = temp.path().join("repository");
        let workspace = root.join(".anywork/worktrees/root-a/child-w");
        tokio::fs::create_dir_all(&workspace).await?;
        let canonical = dunce::canonicalize(&workspace)?;
        let identity = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            canonical.to_string_lossy().into_owned(),
        )?;
        store.bind_workspace_identity("child-w", &identity).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let owner = WorktreeLeaseOwner::new(writer.clone());
        let preparing = owner.reserve_workspace("root-b-preparer", WorkspaceEndpoint::Local)?;
        let foreign_owner = WorktreeLeaseOwner::new(writer.clone());
        let foreign =
            foreign_owner.reserve_workspace("foreign-preparer", WorkspaceEndpoint::Local)?;
        assert!(
            owner.assign_workspace(&foreign, identity.clone()).is_err(),
            "equal serials from different runtime owners must not alias"
        );
        drop(foreign);
        let closing = BTreeSet::from(["child-w".into(), "review-r".into()]);
        assert!(
            owner
                .try_seal_workspace("child-w", identity.clone(), &closing)
                .err()
                .unwrap()
                .to_string()
                .contains("root-b-preparer")
        );
        // An assigned ancestor root does not borrow every worktree below its pool forever.
        owner.assign_workspace(
            &preparing,
            WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                dunce::canonicalize(&root)?.to_string_lossy().into_owned(),
            )?,
        )?;
        let external = owner.reserve_workspace("other-project-root", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&external, identity.clone())?;
        assert!(
            owner
                .try_seal_workspace("child-w", identity.clone(), &closing)
                .err()
                .unwrap()
                .to_string()
                .contains("other-project-root")
        );
        drop(external);
        let binding = owner.reserve_workspace("review-r", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&binding, identity.clone())?;
        let observer_owner = binding.clone();
        owner.preserve_workspace_resources("review-r", identity.clone());
        let seal = owner.try_seal_workspace("child-w", identity.clone(), &closing)?;
        seal.durable()?;
        drop(binding); // Forgetting the binding does not join the actual observer owner.
        assert!(owner.ensure_thread_workspace_idle("review-r").is_err());
        assert!(owner.begin_workspace_removal("child-w", &identity).is_err());
        drop(observer_owner);
        owner.ensure_thread_workspace_idle("review-r")?;
        // A real failed cleanup obligation still blocks independently of active runtime tokens.
        assert!(
            owner
                .begin_workspace_removal("child-w", &identity)
                .err()
                .unwrap()
                .to_string()
                .contains("review-r")
        );
        owner.release_workspace_resources("review-r", &identity)?;
        // The physical seal is distinct from the agent execution seal and ends at a reliable
        // terminal result; retained SessionFiles alone must not keep a stopped review active.
        let removal = owner.begin_workspace_removal("child-w", &identity)?;
        assert!(
            owner
                .reserve_workspace("new-preparer", WorkspaceEndpoint::Local)
                .is_err()
        );
        drop(removal);
        drop(seal);
        let rejected = owner.reserve_workspace("late-borrower", WorkspaceEndpoint::Local)?;
        assert!(owner.assign_workspace(&rejected, identity.clone()).is_err());
        drop(rejected);
        let reopened = StudioStore::open(store.paths().database()).await?;
        let frozen = reopened.workspace_identity("child-w").await?.unwrap();
        assert_eq!(frozen, identity);
        assert!(
            reopened
                .bind_workspace_identity(
                    "child-w",
                    &WorkspaceIdentity::canonical(
                        WorkspaceEndpoint::Local,
                        dunce::canonicalize(&root)?.to_string_lossy().into_owned()
                    )?
                )
                .await
                .is_err()
        );
        // Alias and credential spelling do not split one endpoint/path into two physical sites.
        let first = pl_tool::remote::SshServerProfile {
            alias: "one".into(),
            host_name: "host.example".into(),
            port: 22,
            username: "user".into(),
            identity_file: Some("key-one".into()),
        };
        let second = pl_tool::remote::SshServerProfile {
            alias: "two".into(),
            identity_file: Some("key-two".into()),
            ..first.clone()
        };
        let ssh_a = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::from_profile(Some(&first)),
            "/repo/.anywork/worktrees/root-a/remote-w".into(),
        )?;
        let ssh_b = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::from_profile(Some(&second)),
            ssh_a.root.clone(),
        )?;
        let remote_borrower = owner.reserve_workspace("remote-root-b", ssh_b.endpoint.clone())?;
        owner.assign_workspace(&remote_borrower, ssh_b.clone())?;
        assert!(
            owner
                .try_seal_workspace("remote-w", ssh_a.clone(), &BTreeSet::new())
                .err()
                .unwrap()
                .to_string()
                .contains("remote-root-b")
        );
        drop(remote_borrower);
        let pending = owner.try_seal_workspace("remote-w", ssh_a.clone(), &BTreeSet::new())?;
        drop(pending); // Losing the waiting handle cannot adjudicate an unconfirmed product write.
        let late = owner.reserve_workspace("remote-late", ssh_b.endpoint.clone())?;
        assert!(owner.assign_workspace(&late, ssh_b.clone()).is_err());
        // This fixture sent no grant and started no removal, so explicitly release its known seal.
        owner.release_workspace_seal("remote-w", &ssh_a)?;
        owner.assign_workspace(&late, ssh_b)?;
        // Ordinary archive/failed preparation holds a reversible removal, not a permanent seal.
        let independent = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            root.join("independent").to_string_lossy().into_owned(),
        )?;
        let temporary = owner.reserve_workspace("ordinary-preparer", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&temporary, independent.clone())?;
        let still_owned = temporary.clone();
        assert!(
            owner
                .begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))
                .is_err()
        );
        drop(still_owned);
        let cleanup =
            owner.begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))?;
        assert!(
            owner
                .reserve_workspace("during-cleanup", WorkspaceEndpoint::Local)
                .is_err()
        );
        drop(cleanup);
        owner.assign_workspace(&temporary, independent.clone())?;
        let cleanup =
            owner.begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))?;
        cleanup.complete();
        drop(temporary);
        let restored = owner.reserve_workspace("ordinary-restored", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&restored, independent)?;
        writer.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn cancelled_sink_initialization_releases_its_claim_before_worker_registration()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread("cancelled-sink-initialization");
        register_test_thread(&store, &thread).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let (entered, waiting) = tokio::sync::oneshot::channel();
        let (_release, released) = tokio::sync::oneshot::channel();
        *channel.initialization_gate.lock().unwrap() = Some((entered, released));
        let opening_store = store.clone();
        let opening_thread = thread.clone();
        let opening = tokio::spawn(async move {
            ThreadStorageSink::new(opening_store, opening_thread, None).await
        });
        waiting.await?;
        opening.abort();
        assert!(opening.await.unwrap_err().is_cancelled());
        channel.stop_and_join().await?;
        let replacement = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        assert!(!Arc::ptr_eq(&channel, &replacement.0.channel));
        assert!(Arc::ptr_eq(
            &replacement.0.channel,
            &store.thread_persistence().history_channel(&thread.id)
        ));
        replacement.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_replacement_claim_cannot_lose_its_channel_to_predecessor_release() -> Result<()> {
        for retain_pending in [false, true] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let thread = test_thread("overlapping-channel-release");
            register_test_thread(&store, &thread).await?;
            let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
            let previous_channel = previous.0.channel.clone();
            let write_gate = if retain_pending {
                Some(previous_channel.step_lock.lock().await)
            } else {
                None
            };
            if retain_pending {
                previous.admit(&thread.id, ticket(&thread.id, 1))?;
            }
            let wake = previous.0.changed.clone();
            let (waiting, release) = store.thread_persistence().arm_release_gate();
            let stopped_writer = if retain_pending {
                let writer = previous_channel
                    .workers
                    .lock()
                    .await
                    .pop()
                    .context("registered predecessor writer")?;
                writer.abort();
                Some(writer)
            } else {
                None
            };
            drop(previous);
            wake.notify_one();
            tokio::time::timeout(Duration::from_secs(5), waiting).await??;
            drop(write_gate);
            let replacement = tokio::time::timeout(
                Duration::from_secs(5),
                ThreadStorageSink::new(store.clone(), thread.clone(), None),
            )
            .await;
            release.send(())?;
            if let Some(writer) = stopped_writer {
                assert!(writer.await.unwrap_err().is_cancelled());
            }
            let replacement = replacement??;
            if !retain_pending {
                previous_channel.stop_and_join().await?;
            }
            assert!(
                Arc::ptr_eq(
                    &replacement.0.channel,
                    &store.thread_persistence().history_channel(&thread.id)
                ),
                "predecessor release must not remove the new incarnation's channel"
            );
            assert!(
                replacement.0.channel.subscribe().borrow().fault.is_none(),
                "a predecessor cannot publish WriterUnavailable after its successor initialized"
            );
            spawn_live_projection(&replacement);
            if !retain_pending {
                replacement.admit(&thread.id, ticket(&thread.id, 1))?;
            }
            tokio::time::timeout(Duration::from_secs(5), replacement.flush(&thread.id, 1))
                .await??;
            assert_eq!(store.history(&thread.id).await?.watermark().await?, 1);
            replacement.0.channel.stop_and_join().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_cancelled_replacement_cannot_acknowledge_its_predecessors_pending_facts()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread("cancelled-queue-adoption");
        register_test_thread(&store, &thread).await?;
        let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = previous.0.channel.clone();
        let write_gate = channel.step_lock.lock().await;
        previous.admit(&thread.id, ticket(&thread.id, 1))?;
        let mut previous_flush = Box::pin(previous.flush(&thread.id, 1));
        assert!(futures::poll!(previous_flush.as_mut()).is_pending());
        let (entered, waiting) = tokio::sync::oneshot::channel();
        let (_release, released) = tokio::sync::oneshot::channel();
        *channel.initialization_gate.lock().unwrap() = Some((entered, released));
        let opening_store = store.clone();
        let opening_thread = thread.clone();
        let opening = tokio::spawn(async move {
            ThreadStorageSink::new(opening_store, opening_thread, None).await
        });
        waiting.await?;
        let writer = channel
            .workers
            .lock()
            .await
            .pop()
            .context("registered writer")?;
        writer.abort();
        assert!(writer.await.unwrap_err().is_cancelled());
        opening.abort();
        assert!(opening.await.unwrap_err().is_cancelled());
        assert!(
            store.thread_persistence().snapshot().pending_commits > 0,
            "an initializer cannot acknowledge queue adoption merely by claiming its identity"
        );
        assert!(store.thread_persistence().wait_for_drain().await.is_err());
        assert_eq!(store.history(&thread.id).await?.watermark().await?, 0);
        assert!(
            matches!(
                futures::poll!(previous_flush.as_mut()),
                std::task::Poll::Ready(Err(_))
            ),
            "the old sink's pending flush must receive the unavailable-writer failure"
        );
        drop(previous_flush);
        let unavailable = channel.subscribe().borrow().clone();
        assert_eq!(
            unavailable.fault,
            Some(pl_protocol::studio::HistoryFault::WriterUnavailable)
        );
        assert!(unavailable.error.is_some());
        assert_eq!(unavailable.committed_sequence, 0);
        assert_eq!(unavailable.queued_records, 1);
        drop(write_gate);
        drop(previous);

        let replacement = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        assert!(Arc::ptr_eq(&channel, &replacement.0.channel));
        spawn_live_projection(&replacement);
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history(&thread.id, unavailable.fault_generation),
        )
        .await??;
        tokio::time::timeout(Duration::from_secs(5), replacement.flush(&thread.id, 1)).await??;
        assert_eq!(store.history(&thread.id).await?.watermark().await?, 1);
        let recovered = channel.subscribe().borrow().clone();
        assert_eq!(recovered.committed_sequence, 1);
        assert_eq!(recovered.queued_records, 0);
        assert!(recovered.fault.is_none());
        assert!(recovered.error.is_none());
        assert_eq!(
            replacement.pressure(&thread.id).recovered_generation,
            Some(unavailable.fault_generation)
        );
        store.thread_persistence().wait_for_drain().await?;
        replacement.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn stopped_writer_joins_survive_cancelled_waiters_and_history_reopens() -> Result<()> {
        let id = "retirement-writer-join";
        let (_temp, store, sink) = sink(id).await?;
        let channel = sink.0.channel.clone();
        let write_gate = channel.step_lock.lock().await;
        sink.admit(id, ticket(id, 1))?;
        assert!(channel.stop_and_join().await.is_err());
        assert!(
            !channel.stopping.is_cancelled(),
            "pending facts must keep their writer"
        );
        drop(write_gate);
        tokio::time::timeout(Duration::from_secs(5), sink.flush(id, 1)).await??;
        let history = store.history(id).await?;
        let saved = history.checkpoint().await?.context("durable checkpoint")?;
        let (release, released) = tokio::sync::oneshot::channel();
        channel.workers.lock().await.push(tokio::spawn(async move {
            let _ = released.await;
        }));
        let waiter_channel = channel.clone();
        let waiter = tokio::spawn(async move { waiter_channel.stop_and_join().await });
        channel.stopping.cancelled().await;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        assert!(
            !channel.workers.lock().await.is_empty(),
            "cancelled waits cannot lose join ownership"
        );
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("controlled worker lost its owner"))?;
        tokio::time::timeout(Duration::from_secs(5), channel.stop_and_join()).await??;
        assert!(channel.workers.lock().await.is_empty());
        channel.stop_and_join().await?;
        assert!(
            sink.admit(id, ticket(id, 2)).is_err(),
            "old sinks cannot resume writing"
        );
        assert_eq!(history.watermark().await?, saved.history_fence);
        let reopened = ThreadStorageSink::new(store.clone(), test_thread(id), Some(&saved)).await?;
        spawn_live_projection(&reopened);
        assert!(!Arc::ptr_eq(&channel, &reopened.0.channel));
        reopened.admit(id, ticket(id, 2))?;
        tokio::time::timeout(Duration::from_secs(5), reopened.flush(id, 2)).await??;
        assert_eq!(history.watermark().await?, 2);
        reopened.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn review_exception_cas_is_atomic_and_budget_survives_writer_replacement() -> Result<()> {
        use crate::thread_assembler::{
            agent_review::{ReviewDeliverySource, ReviewForward, ReviewForwardReason},
            review_delivery::ReviewDeliveryException,
        };
        use pl_core::thread::extensions::ExtensionMutation;
        let id = "review-cas-history";
        let (_temp, store, sink) = sink(id).await?;
        let thread = ThreadHandle::resume_without_model(id.into(), None)?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: "fixture-original-source".into(),
                expected_revision: None,
                payload: OpaquePayload::text("original durable source"),
            }])
            .await?;
        tokio::time::timeout(Duration::from_secs(5), thread.flush()).await??;
        let history = store.history(id).await?;
        let terminal = history.watermark().await?;
        let body_budget = 256 * 1024;
        let retained = store
            .thread_persistence()
            .retain_review_delivery(id, body_budget)?;
        let fact = ReviewDeliveryException::from_forward(
            id,
            "saved-turn",
            None,
            terminal,
            "executor",
            ReviewDeliverySource::Reconciliation,
            &ReviewForward::Unconfirmed {
                message_id: crate::thread_assembler::agent_review::review_message_id(
                    id,
                    "saved-turn",
                    terminal,
                ),
                reason: ReviewForwardReason::RecoveryRequiresScheduling,
            },
        )
        .context("exception fixture")?
        .into_fact()?;
        let path = store
            .session_paths("project-test", id)?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared("CREATE TRIGGER reject_review_cas BEFORE INSERT ON history_fact_receipts WHEN NEW.kind='reviewDeliveryException' BEGIN SELECT RAISE(ABORT,'controlled review CAS failure'); END").await?;
        let mut status = sink.0.channel.subscribe();
        let records = thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: fact.extension_id(),
                expected_revision: None,
                payload: fact.encode()?,
            }])
            .await?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        assert!(
            history
                .review_delivery_exception(&fact.message.id)
                .await?
                .is_none()
        );
        assert_eq!(history.watermark().await?, terminal);
        assert!(
            !history
                .checkpoint()
                .await?
                .unwrap()
                .state
                .extensions
                .contains_key(&fact.extension_id())
        );
        assert!(thread.flush().await.is_err());
        let failed = status.borrow().clone();
        db.execute_unprepared("DROP TRIGGER reject_review_cas")
            .await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history(id, failed.fault_generation),
        )
        .await??;
        tokio::time::timeout(Duration::from_secs(5), thread.flush()).await??;
        assert_eq!(
            history
                .review_delivery_exception(&fact.message.id)
                .await?
                .unwrap()
                .message
                .digest(),
            fact.message.digest()
        );
        assert!(
            history
                .checkpoint()
                .await?
                .unwrap()
                .state
                .extensions
                .contains_key(&fact.extension_id())
        );
        thread
            .mutate_extensions(vec![ExtensionMutation::Delete {
                id: fact.extension_id(),
                expected_revision: records[&fact.extension_id()].revision,
            }])
            .await?;
        thread.close().await?;
        sink.0.channel.stop_and_join().await?;
        let checkpoint = history
            .checkpoint()
            .await?
            .context("closed CAS source checkpoint")?;
        assert!(
            !checkpoint
                .state
                .extensions
                .contains_key(&fact.extension_id())
        );
        let reopened =
            ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
        spawn_live_projection(&reopened);
        assert!(!Arc::ptr_eq(&sink.0.channel, &reopened.0.channel));
        assert!(sink.0.channel.shares_delivery_budget(&reopened.0.channel));
        assert!(reopened.pressure(id).thread_bytes >= body_budget);
        let before = reopened.0.channel.process_bytes.load(Ordering::Acquire);
        assert!(
            store
                .thread_persistence()
                .retain_review_delivery(id, MAX_HISTORY_THREAD_BYTES)
                .is_err()
        );
        assert_eq!(
            reopened.0.channel.process_bytes.load(Ordering::Acquire),
            before
        );
        drop(retained);
        assert!(!reopened.0.channel.has_delivery_bytes());
        let resumed = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
        resumed
            .attach_storage(ColdStoreHandle::new(reopened.clone()))
            .await?;
        resumed.close().await?;
        reopened.0.channel.stop_and_join().await?;
        assert_eq!(
            history
                .review_delivery_exception(&fact.message.id)
                .await?
                .unwrap()
                .message
                .digest(),
            fact.message.digest()
        );
        assert!(
            store
                .thread_persistence()
                .retained_history_channel(id)
                .is_none()
        );
        Ok(())
    }

    #[tokio::test]
    async fn worker_join_failure_remains_a_failure_after_retry() -> Result<()> {
        let (_temp, _store, sink) = sink("retirement-worker-failure").await?;
        let channel = sink.0.channel.clone();
        channel.workers.lock().await.push(tokio::spawn(async {
            panic!("controlled storage worker failure");
        }));
        assert!(channel.stop_and_join().await.is_err());
        assert!(channel.workers.lock().await.is_empty());
        assert!(
            channel.stop_and_join().await.is_err(),
            "retry cannot erase an observed worker failure"
        );
        Ok(())
    }

    #[tokio::test]
    async fn explicit_close_intent_is_atomic_retryable_and_survives_owner_shutdown() -> Result<()> {
        use pl_core::thread::extensions::ExtensionMutation;
        let id = "close-intent-storage";
        let (_temp, store, sink) = sink(id).await?;
        let thread = ThreadHandle::resume_without_model(id.into(), None)?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        let route = pl_model::config::ModelRouteConfig {
            account_id: pl_model::config::AccountId::new("frozen-account")?,
            model_id: "frozen-model".into(),
            effort: None,
        };
        thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::model_route::encode(&route)?,
            }])
            .await?;
        thread.flush().await?;
        let history = store.history(id).await?;
        let before = history.checkpoint().await?.context("saved baseline")?;
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &store.session_paths("project-test", id)?.history_database(),
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_close_intent BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'controlled close intent rejection'); END",
        )
        .await?;
        let rejected = tokio::time::timeout(
            Duration::from_secs(5),
            crate::studio::agent_close::commit(&thread),
        )
        .await?;
        assert!(
            rejected.is_err(),
            "a rejected checkpoint cannot acknowledge explicit closure"
        );
        let unchanged = history.checkpoint().await?.context("retained checkpoint")?;
        assert_eq!(
            serde_json::to_vec(&unchanged)?,
            serde_json::to_vec(&before)?
        );
        assert_eq!(history.watermark().await?, before.history_fence);
        assert!(!crate::studio::agent_close::is_explicitly_closed(
            &unchanged.state
        )?);
        let generation = sink.0.channel.subscribe().borrow().fault_generation;
        db.execute_unprepared("DROP TRIGGER reject_close_intent")
            .await?;
        store
            .thread_persistence()
            .retry_history(id, generation)
            .await?;
        crate::studio::agent_close::commit(&thread).await?;
        thread.close().await?;
        let saved = history.checkpoint().await?.context("closed checkpoint")?;
        assert_eq!(
            saved.state.lifecycle,
            pl_core::thread::ThreadLifecycle::Closed
        );
        assert!(crate::studio::agent_close::is_explicitly_closed(
            &saved.state
        )?);
        assert_eq!(
            saved.state.extensions[crate::studio::model_route::MODEL_ROUTE_EXTENSION],
            before.state.extensions[crate::studio::model_route::MODEL_ROUTE_EXTENSION]
        );
        assert_eq!(saved.history_fence, history.watermark().await?);
        drop(history);
        let reloaded = crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
            &store,
            &test_thread(id),
        )
        .await?
        .context("reopened canonical checkpoint")?;
        assert!(crate::studio::agent_close::is_explicitly_closed(
            &reloaded.state
        )?);
        assert_eq!(reloaded.history_fence, saved.history_fence);
        assert_eq!(
            reloaded.state.extensions[crate::studio::agent_close::EXTENSION],
            saved.state.extensions[crate::studio::agent_close::EXTENSION]
        );
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn a_reopened_studio_sink_accepts_a_thread_with_durable_history() -> Result<()> {
        let id = "reopened-durable-thread";
        let temp = tempfile::tempdir()?;
        // Native paths remain literal, including URI-looking characters and deep data roots.
        let database = temp
            .path()
            .join("存储 %2F #")
            .join("nested".repeat(16))
            .join("studio/v2/studio.sqlite");
        let store = StudioStore::open(&database).await?;
        let thread = test_thread(id);
        register_test_thread(&store, &thread).await?;
        let original = ThreadStorageSink::new(store.clone(), thread, None).await?;
        spawn_live_projection(&original);
        let write = ticket(id, 1);
        let checkpoint = write.checkpoint.clone();
        original.admit(id, write)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            original.flush(id, 1),
            || channel_facts(&original),
        )
        .await??;
        drop(original);
        drop(store);

        let reopened_store = StudioStore::open(&database).await?;
        assert!(
            ThreadStorageSink::new(reopened_store.clone(), test_thread(id), None,)
                .await
                .is_err(),
            "history ahead of the checkpoint must not silently skip effects"
        );
        let reopened =
            ThreadStorageSink::new(reopened_store, test_thread(id), Some(&checkpoint)).await?;
        spawn_live_projection(&reopened);
        let resumed = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
        resumed
            .attach_storage(ColdStoreHandle::new(reopened.clone()))
            .await?;
        assert_eq!(reopened.pressure(id).durable_sequence, 1);
        await_durable(
            Duration::from_secs(5),
            "reopened durable barrier",
            resumed.flush(),
            || String::from("the reopened owner never reached its durable ticket"),
        )
        .await??;
        resumed.close().await?;
        let saved = reopened
            .0
            .store
            .history(id)
            .await?
            .checkpoint()
            .await?
            .context("owner shutdown checkpoint")?;
        assert_eq!(
            saved.state.lifecycle,
            pl_core::thread::ThreadLifecycle::Closed
        );
        assert!(
            !crate::studio::agent_close::is_explicitly_closed(&saved.state)?,
            "ordinary shutdown must not seal future execution"
        );
        let restored = ThreadHandle::resume_without_model(id.into(), Some(saved))?;
        assert_eq!(
            restored.snapshot().lifecycle,
            pl_core::thread::ThreadLifecycle::Open
        );
        assert!(!crate::studio::agent_close::is_explicitly_closed(
            &restored.snapshot()
        )?);
        restored.close().await?;
        Ok(())
    }

    /// The projection an observation worker would own: empty until the test hands it the admitted
    /// facts, which it folds and hands back to the reliable channel exactly like the production owner.
    fn live_projection() -> crate::studio::thread_projection::LiveProjection {
        crate::studio::thread_projection::LiveProjection::new()
    }

    /// Takes the admitted facts over exactly as the Thread's live projection owner does.
    ///
    /// The Studio runtime installs that owner during Thread assembly, and the history writer refuses
    /// to save a fact no projection holds. These tests exercise the writer on its own, so they drive
    /// the same production projection against the same reliable admission channel: one projection per
    /// commit, published shape unchanged, only the caller differs.
    pub(crate) fn spawn_live_projection(sink: &ThreadStorageSink) {
        drop(spawn_projection(
            sink.0.store.clone(),
            sink.0.thread.clone(),
        ));
    }

    /// Drives the real projection for an assembler-installed sink without downcasting its erased
    /// ColdStoreHandle or retaining that writer incarnation after its core/observer have ended.
    pub(crate) fn spawn_live_projection_for_thread(
        store: StudioStore,
        id: &str,
    ) -> tokio::task::JoinHandle<()> {
        let thread = store
            .catalog()
            .get(id)
            .expect("registered projection Thread")
            .to_thread();
        spawn_projection(store, thread)
    }

    fn spawn_projection(
        store: StudioStore,
        thread: pl_protocol::Thread,
    ) -> tokio::task::JoinHandle<()> {
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store
            .thread_persistence()
            .chat_session(&thread.id)
            .expect("initialized writer Session");
        tokio::spawn(async move {
            let mut projection = live_projection();
            let mut failed = std::collections::BTreeSet::new();
            // Wake on the channel's own status watch, never on the channel's `Notify`: the history
            // writer is the one task that waits on that `Notify`, and a second waiter would consume
            // the single wakeup permit a recovery notification hands out.
            let mut updates = channel.subscribe();
            loop {
                if channel.stopping.is_cancelled() {
                    return;
                }
                if let Some(write) = channel.next_unprojected() {
                    let sequence = write.effect.sequence;
                    if failed.contains(&sequence) {
                        tokio::time::sleep(Duration::from_millis(5)).await;
                        continue;
                    }
                    // A reliable-output repair can name an identity this bounded window released; the
                    // production observation owner reads that committed body back and folds it in, so
                    // the harness drives the same step instead of skipping a fact the writer must save.
                    if !write.effect.delivery_repairs.is_empty() {
                        let seeded = match store.history(&thread.id).await {
                            Ok(history) => crate::studio::thread_projection::seed_repaired_targets(
                                &mut projection,
                                &history,
                                &write.effect,
                            )
                            .await
                            .map_err(|error| error.to_string()),
                            Err(error) => Err(error.to_string()),
                        };
                        if let Err(error) = seeded {
                            failed.insert(sequence);
                            channel.fail_projection(sequence, error);
                            continue;
                        }
                    }
                    match projection.project_committed(
                        &chat,
                        &thread,
                        &write.effect,
                        &write.checkpoint.state,
                    ) {
                        Ok(prepared) => {
                            channel.prepare(prepared);
                        }
                        // The writer never projects, so failing here is what the running Studio sees
                        // from its observation worker: the fact is reported and the barrier fails
                        // closed with the projection's own reason.
                        Err(error) => {
                            failed.insert(sequence);
                            channel.fail_projection(sequence, error.to_string());
                        }
                    }
                    continue;
                }
                tokio::select! {
                    changed = updates.changed() => if changed.is_err() { return; },
                    () = channel.stopping.cancelled() => return,
                }
            }
        })
    }

    /// Save the original terminal report in the same real effect/checkpoint transaction as Studio.
    /// No parent owner is needed; recovery must later prove its independently missing receipt.
    pub(crate) async fn save_terminal_report(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
        message: pl_core::thread::inbox::ThreadMessage,
    ) -> Result<()> {
        let checkpoint = store.history(&thread.id).await?.checkpoint().await?;
        let sink =
            ThreadStorageSink::new(store.clone(), thread.clone(), checkpoint.as_ref()).await?;
        let sequence = checkpoint
            .as_ref()
            .map_or(1, |checkpoint| checkpoint.history_fence + 1);
        let mut terminal = ticket(&thread.id, sequence);
        if let Some(checkpoint) = checkpoint {
            terminal.checkpoint.state = checkpoint.state;
            terminal.checkpoint.state.commit_sequence = sequence;
        }
        let turn = TurnRecord {
            turn_id: "original-terminal-turn".into(),
            input_id: None,
            state: TurnState::Finished(TurnOutcome::Completed),
            model_steps: 0,
            elapsed_ms: None,
        };
        terminal.checkpoint.state.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
        terminal.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut terminal.effect).turn = Some(turn);
        let mut prepared = live_projection().project_committed(
            &sink.0.chat,
            thread,
            &terminal.effect,
            &terminal.checkpoint.state,
        )?;
        Arc::get_mut(&mut prepared)
            .context("new prepared effect unexpectedly shared")?
            .parent_report = Some(Arc::new(message));
        sink.admit(&thread.id, terminal)?;
        sink.0.channel.prepare(prepared);
        sink.flush(&thread.id, sequence).await?;
        sink.0.channel.stop_and_join().await
    }

    /// One ticket whose effect commits a visible prompt item, i.e. the shortest effect that projects
    /// a durable body the writer must confirm.
    fn visible_input_ticket(thread_id: &str, sequence: u64, input_id: &str) -> Result<ThreadWrite> {
        let mut write = ticket(thread_id, sequence);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: sequence,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: input_id.to_owned(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "hello".into(),
                }],
            },
            ordinal: sequence,
            revision: sequence,
            state: InputState::Consumed {
                turn_id: "visible-turn".into(),
                attempt_id: "attempt".into(),
            },
        };
        write.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Ok(write)
    }

    /// The projected body of `visible_input_ticket`'s item as the live projection would publish it.
    fn visible_input_item(
        thread_id: &str,
        input_id: &str,
        revision: u64,
    ) -> pl_protocol::ThreadItem {
        pl_protocol::ThreadItem::new(
            input_id.to_owned(),
            thread_id.to_owned(),
            "visible-turn".to_owned(),
            revision,
            revision,
            1,
            1,
            pl_protocol::ThreadItemState::Text(pl_protocol::ThreadTextItem::new(
                pl_protocol::ThreadTextChannel::User,
                "hello".into(),
                Vec::new(),
                pl_protocol::ThreadContentLifecycle::completed(1),
            )),
        )
    }

    /// One streaming body revision of `item_id`, always at the same placement `order`.
    ///
    /// Two calls with the same `order` and increasing `revision` are exactly what a re-projected
    /// identity looks like: the same window slot whose content version advanced, never a new item.
    fn revised_preview(
        thread_id: &str,
        item_id: &str,
        order: u64,
        revision: u64,
        text: &str,
    ) -> Result<pl_core::chat::ChatItem> {
        chat_item(
            pl_protocol::ThreadItem::new(
                item_id.to_owned(),
                thread_id.to_owned(),
                "visible-turn".to_owned(),
                order,
                revision,
                1,
                1,
                pl_protocol::ThreadItemState::Text(pl_protocol::ThreadTextItem::new(
                    pl_protocol::ThreadTextChannel::User,
                    text.to_owned(),
                    Vec::new(),
                    pl_protocol::ThreadContentLifecycle::streaming(),
                )),
            ),
            false,
        )
    }

    /// The item the shared session currently shows for `item_id`.
    async fn shown_item(chat: &pl_core::chat::Session, item_id: &str) -> pl_core::chat::ChatItem {
        chat.page(pl_core::chat::ChatPageRequest::latest().with_limit(100))
            .await
            .expect("the preview page is readable")
            .items
            .into_iter()
            .find(|item| item.item_id == item_id)
            .expect("the identity stays inside the bounded preview page")
    }

    /// The writer never reads a committed body back to publish it.
    ///
    /// The Thread's live projection publishes the body into the shared chat session, and the writer
    /// commits exactly the batch that owner handed over: it confirms that identity and revision
    /// instead of reading a second body copy back from SQLite. The saved watermark therefore advances
    /// on the published content, and no second content cache exists to drift from it.
    #[tokio::test]
    async fn committed_identity_is_confirmed_into_the_shared_session_without_a_body_readback()
    -> Result<()> {
        let id = "writer-confirmation";
        let (_temp, store, sink) = sink(id).await?;
        let chat = store.chat_session(id).await?;

        // The live projection publishes the body; the reliable handoff then commits that same batch.
        chat.publish_preview(chat_item(
            visible_input_item(id, "projected-first", 1),
            false,
        )?)?;
        sink.admit(id, visible_input_ticket(id, 1, "projected-first")?)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush(id, 1),
            || channel_facts(&sink),
        )
        .await??;
        let published = shown_item(&chat, "projected-first").await;
        assert!(
            published.saved,
            "the committed identity confirms the body the projection already published"
        );
        Ok(())
    }

    /// A commit the Thread's projection owner has not handed over is never written.
    ///
    /// This is what makes "the owner released this effect from its window" imply "the projection
    /// published it": the durable watermark cannot move past a fact no projection took over, so a
    /// released commit is always one the product already has. The sink below is built without the
    /// test projection, so nothing takes the fact over until the test hands it in itself.
    #[tokio::test]
    async fn a_commit_without_a_projection_handoff_is_never_saved() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("no-handoff")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("no-handoff"), None).await?;
        let write = ticket("no-handoff", 1);
        sink.admit("no-handoff", write.clone())?;
        assert!(
            tokio::time::timeout(Duration::from_millis(200), sink.flush("no-handoff", 1))
                .await
                .is_err(),
            "an unprojected commit must not reach a durable barrier"
        );
        let unprojected = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(unprojected.committed_sequence, 0);
        assert_eq!(unprojected.queued_records, 1);
        assert_eq!(store.history("no-handoff").await?.watermark().await?, 0);

        let chat = store.chat_session("no-handoff").await?;
        let mut projection = live_projection();
        let prepared = projection.project_committed(
            &chat,
            &sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
        )?;
        sink.0.channel.prepare(prepared);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("no-handoff", 1),
            || channel_facts(&sink),
        )
        .await??;
        assert_eq!(store.history("no-handoff").await?.watermark().await?, 1);
        Ok(())
    }

    #[tokio::test]
    async fn hidden_consumed_input_keeps_turn_history_complete_after_body_pruning() -> Result<()> {
        let (_temp, store, sink) = sink("hidden-input").await?;
        let input_id = "interaction:confirmed:continuation";
        let turn_id = "turn-after-confirmation";
        let mut accepted = ticket("hidden-input", 1);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: input_id.into(),
                payload: OpaquePayload::new(
                    "pl.studio.interaction-continuation",
                    1,
                    serde_json::json!({"interactionId":"confirmed","presentation":"hidden"})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "answer".into(),
                }],
            },
            ordinal: 1,
            revision: 2,
            state: InputState::Consumed {
                turn_id: turn_id.into(),
                attempt_id: "attempt-1".into(),
            },
        };
        accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        sink.admit("hidden-input", accepted)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("hidden-input", 1),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history("hidden-input").await?;
        assert!(history.existing_items([input_id.into()]).await?.is_empty());
        assert!(history.input_identity(input_id).await?.is_some());

        let mut later = ticket("hidden-input", 2);
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: Some(input_id.into()),
            turn_id: turn_id.into(),
            state: TurnState::Running,
            model_steps: 0,
        };
        later.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut later.effect).turn = Some(turn);
        sink.admit("hidden-input", later)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 2),
            sink.flush("hidden-input", 2),
            || channel_facts(&sink),
        )
        .await??;
        assert_eq!(history.watermark().await?, 2);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn missing_visible_input_item_still_blocks_history() -> Result<()> {
        // A Thread re-activated after its durable timeline lost a visible input body. The projection
        // that installs now has never folded that input — it is a fresh owner, exactly like a Thread
        // whose earlier incarnation committed the input — so the effect that still references it must
        // fail closed instead of committing a timeline with a hole.
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("missing-visible")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("missing-visible"), None).await?;
        let mut accepted = ticket("missing-visible", 1);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: "visible-input".into(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "hello".into(),
                }],
            },
            ordinal: 1,
            revision: 2,
            state: InputState::Consumed {
                turn_id: "visible-turn".into(),
                attempt_id: "attempt".into(),
            },
        };
        accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        // The incarnation that committed the input projects and hands it over normally.
        let chat = store.chat_session("missing-visible").await?;
        sink.admit("missing-visible", accepted.clone())?;
        let mut owner = live_projection();
        let prepared = owner.project_committed(
            &chat,
            &sink.0.thread,
            &accepted.effect,
            &accepted.checkpoint.state,
        )?;
        sink.0.channel.prepare(prepared);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("missing-visible", 1),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history("missing-visible").await?;
        let path = store
            .session_paths("project-test", "missing-visible")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared("DELETE FROM history_items WHERE item_id='visible-input'")
            .await?;

        // The owner this Thread gets on re-activation never folded the input, and the durable row
        // the projection would resolve it from is gone.
        spawn_live_projection(&sink);
        let mut later = ticket("missing-visible", 2);
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: Some("visible-input".into()),
            turn_id: "visible-turn".into(),
            state: TurnState::Running,
            model_steps: 0,
        };
        later.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut later.effect).turn = Some(turn);
        sink.admit("missing-visible", later)?;
        let error = await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 2),
            sink.flush("missing-visible", 2),
            || channel_facts(&sink),
        )
        .await
        .context("a torn projection must fail the durable barrier instead of hanging")?
        .expect_err("a visible input without its item must fail closed");
        assert!(
            error
                .to_string()
                .contains("missing the committed input item")
        );
        assert_eq!(history.watermark().await?, 1);
        Ok(())
    }

    #[tokio::test]
    async fn unconsumed_input_survives_failed_preparation_and_a_new_turn() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "unconsumed-retry";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection();
        let mut input = consumed_visible_input("pending-input", "second-turn", 1)?;
        input.state = InputState::Pending;
        let mut accepted = ticket(id, 1);
        accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut accepted.effect).inputs =
            Arc::from([InputChange::Accepted(input.clone())]);
        drive_live_projection(&mut projection, &chat, &sink, id, accepted)?;
        // Both runs publish a Turn before model preparation consumes anything. The first one
        // failed preparation, so the same pending identity legitimately enters the second run.
        for (sequence, turn_id, turn_state) in [
            (2, "first-turn", TurnState::Running),
            (
                3,
                "first-turn",
                TurnState::Failed {
                    description: "model preparation rejected media".into(),
                    model_failure: None,
                },
            ),
            (4, "second-turn", TurnState::Running),
        ] {
            let mut turn = turn_record(turn_id, "pending-input", turn_state);
            if sequence == 3 {
                turn.elapsed_ms = Some(1);
            }
            let mut write = ticket(id, sequence);
            write.checkpoint.state.inputs = Arc::from([input.clone()]);
            write.checkpoint.state.turns = Arc::from([turn.clone()]);
            Arc::make_mut(&mut write.effect).turn = Some(turn);
            drive_live_projection(&mut projection, &chat, &sink, id, write)?;
            await_durable(
                Duration::from_secs(5),
                &format!("commit {}", sequence),
                sink.flush(id, sequence),
                || channel_facts(&sink),
            )
            .await??;
            let saved = store
                .history(id)
                .await?
                .existing_items(["pending-input".into()])
                .await?;
            assert!(saved["pending-input"].turn_id.is_empty());
        }
        input.state = InputState::Consumed {
            turn_id: "second-turn".into(),
            attempt_id: "attempt".into(),
        };
        input.revision += 1;
        let mut consumed = ticket(id, 5);
        consumed.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut consumed.effect).inputs = Arc::from([InputChange::Transition {
            id: input.input.id.clone(),
            revision: input.revision,
            state: input.state.clone(),
        }]);
        drive_live_projection(&mut projection, &chat, &sink, id, consumed)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 5),
            sink.flush(id, 5),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history(id).await?;
        let saved = history.existing_items(["pending-input".into()]).await?;
        assert_eq!(saved["pending-input"].turn_id, "second-turn");
        assert_eq!(history.watermark().await?, 5);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    /// One visible, already-consumed input record owned by `turn_id`.
    ///
    /// This is exactly what core's consuming commit leaves behind: the input is `Consumed`, so it has
    /// a visible timeline item whose `turn_id` is the Turn it opened.
    fn consumed_visible_input(id: &str, turn_id: &str, sequence: u64) -> Result<InputRecord> {
        Ok(InputRecord {
            continuation: None,
            accepted_sequence: sequence,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: id.to_owned(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "hello".into(),
                }],
            },
            ordinal: sequence,
            revision: sequence,
            state: InputState::Consumed {
                turn_id: turn_id.to_owned(),
                attempt_id: "attempt".to_owned(),
            },
        })
    }

    /// One Turn record naming `input_id` as the input that opened it.
    fn turn_record(turn_id: &str, input_id: &str, state: TurnState) -> TurnRecord {
        TurnRecord {
            elapsed_ms: None,
            input_id: Some(input_id.to_owned()),
            turn_id: turn_id.to_owned(),
            state,
            model_steps: 0,
        }
    }

    /// One provider output item with a single text part, as a model receipt reports it.
    ///
    /// The multi-item stress response is exactly a long list of these: one stable identity per
    /// provider item, all delivered inside one model step.
    fn provider_presentation_part(
        index: usize,
    ) -> pl_model::completion::CompletionPresentationItem {
        use pl_model::completion::{
            CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
            CompletionPresentationPartKind,
        };
        CompletionPresentationItem {
            provider_item_id: format!("stress-item-{index}"),
            output_index: Some(index as u32),
            kind: CompletionPresentationItemKind::Text(pl_protocol::trace::TraceTextChannel::Final),
            parts: vec![CompletionPresentationPart {
                content_index: 0,
                provider_part_id: Some(format!("stress-part-{index}")),
                kind: CompletionPresentationPartKind::OutputText,
                text: format!("chunk-{index}"),
            }],
        }
    }

    /// The snapshot attempt and the matching effect update for one committed step of `parts` parts.
    ///
    /// The receipt is the model crate's own `pl.model.assistant` frame — the same payload a real
    /// adapter writes — so the projection itemizes it through its public receipt reader instead of a
    /// test-only shape.
    fn committed_parts_attempt(
        turn_id: &str,
        attempt_id: &str,
        parts: usize,
    ) -> Result<(
        pl_core::thread::RequestAttempt,
        pl_core::thread::journal::AttemptUpdate,
    )> {
        committed_presentation_attempt(
            turn_id,
            attempt_id,
            (0..parts).map(provider_presentation_part).collect(),
        )
    }

    fn committed_presentation_attempt(
        turn_id: &str,
        attempt_id: &str,
        presentation_items: Vec<pl_model::completion::CompletionPresentationItem>,
    ) -> Result<(
        pl_core::thread::RequestAttempt,
        pl_core::thread::journal::AttemptUpdate,
    )> {
        let receipt = pl_model::runtime::ModelResponseReceipt {
            binding: pl_model::runtime::ModelCallBinding {
                account_id: "fixture".into(),
                model_id: "fixture-model".into(),
                protocol: pl_model::protocol::ProtocolKind::OpenAiCompatible,
                wire_api: pl_model::protocol::WireApi::ChatCompletions,
                isolation: "test".into(),
                purpose: "test".into(),
                context_window: None,
                max_context_window: None,
                auto_compact_limit: None,
            },
            response: pl_model::completion::CompletionResponse {
                replay: None,
                response_id: None,
                content: None,
                reasoning_content: None,
                tool_calls: Vec::new(),
                responses_context_items: Vec::new(),
                presentation_items,
                orchestration: Default::default(),
                timing: None,
                accounting: Default::default(),
                model: "fixture-model".into(),
                model_observation: None,
                observation: Default::default(),
            },
        };
        // The durable assistant frame is exactly this pair of receipt and tool bindings.
        #[derive(serde::Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Frame<'a> {
            receipt: &'a pl_model::runtime::ModelResponseReceipt,
            bindings: Vec<ModelToolCall>,
        }
        let frame = OpaquePayload::new(
            "pl.model.assistant",
            // 与 pl-model 当前 `pl.model.assistant` 帧版本一致（该常量不对外重导出）。
            4,
            serde_json::to_string(&Frame {
                receipt: &receipt,
                bindings: Vec::new(),
            })?,
        )?;
        let output = ModelStepOutput {
            attempt_id: attempt_id.to_owned(),
            base_context_revision: 0,
            content: vec![ContextContent::Opaque { payload: frame }],
            tool_calls: Vec::new(),
            private_context: None,
            usage: Default::default(),
        };
        let tools: Arc<[pl_core::model::ModelToolDeclaration]> =
            Arc::from(Vec::<pl_core::model::ModelToolDeclaration>::new());
        let attempt = pl_core::thread::RequestAttempt::new(
            turn_id.to_owned(),
            attempt_id.to_owned(),
            0,
            pl_core::thread::AttemptStatus::Committed,
        );
        let update = pl_core::thread::journal::AttemptUpdate {
            request_metadata: None,
            usage_binding: None,
            tool_projection: None,
            turn_id: turn_id.to_owned(),
            attempt_id: attempt_id.to_owned(),
            retry_of: None,
            input_revision: 0,
            tools,
            outcome: pl_core::thread::AttemptOutcome::Committed(output),
            input_estimate: None,
        };
        Ok((attempt, update))
    }

    /// Hands one admitted fact to the production live projection and to the writer, exactly as the
    /// Thread's observation worker does: admit, take the owed fact over, project it, hand the batch
    /// back. The writer saves only what this owner handed over, so a `flush` afterwards is the same
    /// durable barrier the product uses.
    fn drive_live_projection(
        projection: &mut crate::studio::thread_projection::LiveProjection,
        chat: &pl_core::chat::Session,
        sink: &ThreadStorageSink,
        thread_id: &str,
        write: ThreadWrite,
    ) -> Result<()> {
        sink.admit(thread_id, write)?;
        let write = sink
            .0
            .channel
            .next_unprojected()
            .context("the admitted fact is owed a projection")?;
        let (_, prepared) = projection.advance(
            chat,
            &sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
            true,
        )?;
        assert!(sink.0.channel.prepare(prepared));
        Ok(())
    }

    /// A delayed Running acknowledgement must not retire provider observations published after
    /// its batch was prepared. The writer step lock fixes the interleaving without timing sleeps.
    #[tokio::test]
    async fn running_save_ack_preserves_later_failed_and_current_observations() -> Result<()> {
        use pl_core::{
            chat::{PresentationPart, presentation_item_id},
            model::{
                ActiveModelProgress, ModelProgressSender, ModelTextChannel, ObservedItemKind,
                ObservedPart, ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
            },
            thread::{AttemptOutcome, AttemptStatus},
        };

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "running-save-ack";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection();
        let (mut attempt, mut update) = committed_parts_attempt("turn", "attempt", 0)?;
        attempt.status = AttemptStatus::Running;
        update.outcome = AttemptOutcome::Running;
        let mut write = ticket(id, 1);
        write.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut write.effect).attempt = Some(update);
        let mut state = write.checkpoint.state.clone();

        let locked = sink.0.channel.step_lock.lock().await;
        drive_live_projection(&mut projection, &chat, &sink, id, write)?;
        let sender = ModelProgressSender::detached(1024);
        let part = |text: &str| {
            ObservedPart::new(ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: Arc::from("same-provider-id"),
                output_index: Some(0),
                item_kind: ObservedItemKind::Text(ModelTextChannel::Final),
                part: ObservedPartKind::OutputText,
                content_index: 0,
            }))
            .authorized(text)
        };
        sender.edit_parts(|parts| parts.push(part("failed body")));
        sender.begin_recovery(5, Arc::from("connection interrupted"))?;
        sender.edit_parts(|parts| parts.push(part("current body")));
        state.model_progress = Some(ActiveModelProgress {
            attempt_id: "attempt".into(),
            progress: sender.latest(),
        });
        projection.stream(&chat, &sink.0.thread, &state, 1).await?;
        let failed_id = presentation_item_id(
            "attempt",
            0,
            "same-provider-id",
            Some(PresentationPart::OutputText(0)),
        );
        let current_id = presentation_item_id(
            "attempt",
            1,
            "same-provider-id",
            Some(PresentationPart::OutputText(0)),
        );
        let failed = shown_item(&chat, &failed_id).await;
        let current = shown_item(&chat, &current_id).await;
        drop(locked);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush(id, 1),
            || channel_facts(&sink),
        )
        .await??;

        // No further provider update is needed to keep either identity visible after the save ack.
        let saved_window = chat
            .page(pl_core::chat::ChatPageRequest::latest().with_limit(100))
            .await?
            .items;
        assert_eq!(
            saved_window
                .iter()
                .find(|item| item.item_id == failed_id)
                .context("Running save acknowledgement removed the failed observation")?,
            &failed
        );
        assert_eq!(
            saved_window
                .iter()
                .find(|item| item.item_id == current_id)
                .context("Running save acknowledgement removed the current observation")?,
            &current
        );
        assert!(
            store
                .history(id)
                .await?
                .existing_items([failed_id, current_id])
                .await?
                .is_empty(),
            "Running saved only its prepared start facts, not these later observations"
        );
        Ok(())
    }

    #[tokio::test]
    async fn parent_message_keeps_identity_until_consumed_and_saved() -> Result<()> {
        use pl_core::thread::inbox::{InboxRecord, ThreadMessage};

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "child-message";
        let mut thread = test_thread(id);
        thread.parent_thread_id = Some("parent".into());
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread, None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection();
        let record = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                kind: pl_core::context::AgentMessageKind::Report,
                id: "initial:spawn".into(),
                source_id: "agent:parent".into(),
                payload: OpaquePayload::text("implement the assigned task"),
                context: Vec::new(),
            },
        };
        let item_id = crate::studio::thread_projection::order::message_id(&record.message.id);
        let mut accepted = ticket(id, 1);
        accepted.checkpoint.state.inbox = Arc::from([record.clone()]);
        Arc::make_mut(&mut accepted.effect).inbox = Arc::from([record.clone()]);
        drive_live_projection(&mut projection, &chat, &sink, id, accepted.clone())?;
        let original = shown_item(&chat, &item_id).await;
        // Re-observation before consumption must not invent a new content version.
        projection.advance(
            &chat,
            &sink.0.thread,
            &accepted.effect,
            &accepted.checkpoint.state,
            true,
        )?;
        assert_eq!(
            shown_item(&chat, &item_id).await.revision,
            original.revision
        );

        let (attempt, update) = committed_parts_attempt("child-turn", "child-attempt", 1)?;
        let mut consumed = ticket(id, 2);
        consumed.checkpoint.state.consumed_messages = 1;
        consumed.checkpoint.state.inbox = Arc::from([record]);
        consumed.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut consumed.effect).attempt = Some(update);
        Arc::make_mut(&mut consumed.effect).consumed_messages = Some(1);
        drive_live_projection(&mut projection, &chat, &sink, id, consumed)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 2),
            sink.flush(id, 2),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history(id).await?;
        let saved = history.existing_items([item_id.clone()]).await?;
        let item = saved.get(&item_id).context("saved parent message")?;
        assert_eq!(item.ordinal, original.order);
        assert_eq!(item.turn_id, "child-turn");
        assert!(item.revision > original.revision);
        assert!(
            matches!(item.state(), pl_protocol::ThreadItemState::Text(text)
            if text.channel() == pl_protocol::ThreadTextChannel::ParentAgent
                && text.text() == "implement the assigned task")
        );
        assert_eq!(history.watermark().await?, 2);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);

        // A saved but unconsumed follow-up has no Turn. Reinstall the projection from its
        // durable identity before consuming it, as activation does for an idle child.
        let mut followup = ticket(id, 3);
        followup.checkpoint.state.consumed_messages = 1;
        let mut record = accepted.checkpoint.state.inbox[0].clone();
        record.sequence = 2;
        record.message.id = "followup".into();
        followup.checkpoint.state.inbox = Arc::from([record.clone()]);
        Arc::make_mut(&mut followup.effect).inbox = Arc::from([record.clone()]);
        drive_live_projection(&mut projection, &chat, &sink, id, followup)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 3),
            sink.flush(id, 3),
            || channel_facts(&sink),
        )
        .await??;
        let followup_id = crate::studio::thread_projection::order::message_id(&record.message.id);
        let saved = history.existing_items([followup_id.clone()]).await?;
        let original = saved[&followup_id].clone();
        projection = live_projection();
        projection.seed(saved.into_values().collect(), Default::default());
        let (attempt, update) = committed_parts_attempt("next-turn", "next-attempt", 1)?;
        let mut consumed = ticket(id, 4);
        consumed.checkpoint.state.consumed_messages = 2;
        consumed.checkpoint.state.inbox = Arc::from([record]);
        consumed.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut consumed.effect).attempt = Some(update);
        Arc::make_mut(&mut consumed.effect).consumed_messages = Some(2);
        drive_live_projection(&mut projection, &chat, &sink, id, consumed)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 4),
            sink.flush(id, 4),
            || channel_facts(&sink),
        )
        .await??;
        let saved = history.existing_items([followup_id.clone()]).await?;
        assert_eq!(saved[&followup_id].ordinal, original.ordinal);
        assert_eq!(saved[&followup_id].turn_id, "next-turn");
        assert!(saved[&followup_id].revision > original.revision);
        assert_eq!(history.watermark().await?, 4);
        Ok(())
    }

    /// A live Turn survives a retained window smaller than the response it produced.
    ///
    /// The live projection is a bounded observation owner: it releases a Turn's oldest facts by
    /// ordinal once that Turn commits more identities than `LIVE_ITEM_WINDOW`. A Turn's own input is
    /// the identity core keeps referencing from *every* later effect of that Turn — above all its
    /// terminal one, whose checkpoint has already pruned the consumed body and carries only the
    /// minimal `turns[].input_id` — while it is also the oldest fact the Turn ever created. Numbering
    /// the window purely by ordinal therefore evicted exactly that identity, the terminal effect then
    /// resolved the pruned input as a hole and the durable barrier failed closed with
    /// `MissingDurableInput`: the multi-item stress fault. The window must bound only *optional*
    /// retained history; the minimal identity a live Turn still references is not optional.
    ///
    /// Keeping an identity without keeping its content version is not enough: the Turn's own item is
    /// re-projected by the same later effects, so a window that released it made the re-projection
    /// restart at revision 1, and the durable row rejected the new payload as a revision conflict.
    /// Identity and version have to survive together.
    ///
    /// This drives the production `advance` path over the same reliable handoff the observation
    /// worker uses, with no GUI subscriber: the projection publishes into the shared session and
    /// hands the batch to the writer exactly like the owner. The pressure is a real provider receipt
    /// with more presentation parts than the window holds, not a fabricated per-Turn input queue.
    #[tokio::test]
    async fn a_live_turn_input_survives_a_window_smaller_than_its_parts() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("window-input")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("window-input"), None).await?;
        let thread_id = "window-input";
        let turn_id = "long-turn";
        let attempt_id = "long-attempt";
        let input_id = "input-under-the-window";
        let chat = store.chat_session(thread_id).await?;
        let mut projection = live_projection();

        // Commit 1: the Turn's own opening input. Every later commit's checkpoint has pruned the
        // consumed body from `state.inputs` and keeps only the minimal `turns[].input_id`.
        let input = consumed_visible_input(input_id, turn_id, 1)?;
        let mut opening = ticket(thread_id, 1);
        opening.checkpoint.state.inputs = Arc::from([input.clone()]);
        opening.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Arc::make_mut(&mut opening.effect).turn =
            Some(turn_record(turn_id, input_id, TurnState::Running));
        drive_live_projection(&mut projection, &chat, &sink, thread_id, opening)?;

        // Commit 2: one model step whose receipt itemizes more provider parts than the window holds.
        // That pushes the Turn's own oldest facts out of the ordinal window.
        let parts = crate::studio::thread_projection::LIVE_ITEM_WINDOW + 8;
        let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, parts)?;
        let mut step = ticket(thread_id, 2);
        step.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        step.checkpoint.state.attempts = Arc::from([attempt.clone()]);
        Arc::make_mut(&mut step.effect).attempt = Some(update);
        drive_live_projection(&mut projection, &chat, &sink, thread_id, step)?;

        // Commit 3: the Turn's terminal effect. Its checkpoint names the input without carrying its
        // body, and it re-projects the Turn item, so both the input identity and the Turn's content
        // version have to resolve from the projection's own memory.
        let finished = || {
            turn_record(
                turn_id,
                input_id,
                TurnState::Finished(TurnOutcome::Completed),
            )
        };
        let mut terminal = ticket(thread_id, 3);
        terminal.checkpoint.state.turns = Arc::from([finished()]);
        terminal.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut terminal.effect).turn = Some(finished());
        drive_live_projection(&mut projection, &chat, &sink, thread_id, terminal)?;

        // Every fact is handed over, so the durable barrier reaches the terminal commit with no
        // fault, and the rows a long Turn produced are complete instead of a hole or a revision
        // conflict.
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 3),
            sink.flush(thread_id, 3),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history(thread_id).await?;
        assert_eq!(history.watermark().await?, 3);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        assert!(history.input_identity(input_id).await?.is_some());
        let turn_item_id = crate::studio::thread_projection::order::turn_id(turn_id);
        let last_part_id = crate::studio::thread_projection::order::presentation_id(
            attempt_id,
            0,
            &format!("stress-item-{}", parts - 1),
            Some(crate::studio::thread_projection::order::PresentationPart::OutputText(0)),
        );
        let mut rows = history
            .existing_items([
                input_id.to_owned(),
                turn_item_id.clone(),
                last_part_id.clone(),
            ])
            .await?;
        let input_row = rows
            .remove(input_id)
            .expect("the live Turn's consumed input stays a complete durable row");
        match input_row.state() {
            pl_protocol::ThreadItemState::Text(text) => assert_eq!(text.text(), "hello"),
            other => panic!("the input row keeps its visible body, got {other:?}"),
        }
        let turn_row = rows
            .remove(&turn_item_id)
            .expect("the Turn row is re-projected onto its own content version");
        match turn_row.state() {
            pl_protocol::ThreadItemState::Turn(turn) => {
                assert!(matches!(turn.state(), pl_protocol::TurnState::Completed(_)))
            }
            other => panic!("the Turn row keeps its Turn state, got {other:?}"),
        }
        let part_row = rows
            .remove(&last_part_id)
            .expect("the receipt's provider parts are durable rows");
        match part_row.state() {
            pl_protocol::ThreadItemState::Text(text) => {
                assert_eq!(text.text(), format!("chunk-{}", parts - 1).as_str())
            }
            other => panic!("the provider part keeps its text, got {other:?}"),
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_cold_owner_seeds_the_same_terminal_turn_the_live_projection_publishes() -> Result<()>
    {
        // A Thread re-activated after its last Turn finished has no live frame left for that fact:
        // the authoritative snapshot carries only the active Turn and `turnCompleted` is broadcast
        // once. The owner therefore seeds its retained last-Turn fact from durable history on the
        // install path. This drives that cold read over real committed rows and proves it agrees with
        // the live projection the frame would have used — same identity, same revision, same state —
        // while a Turn that is still running (or not yet durable) is never reported as finished.
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("cold-turn")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("cold-turn"), None).await?;
        let thread_id = "cold-turn";
        let turn_id = "terminal-turn";
        let input_id = "cold-input";
        let chat = store.chat_session(thread_id).await?;
        let mut projection = live_projection();

        // A Thread whose history was never written reads as "no finished Turn" instead of creating a
        // database, so this cold read can never make the live path wait on the writer.
        assert!(
            store
                .history_for("project-test", "never-written")
                .await?
                .newest_terminal_turn()
                .await?
                .is_none()
        );

        // Commit 1: the Turn opens and is durable, but it is still running — the cold seed must not
        // mistake the newest Turn row for a finished one.
        let input = consumed_visible_input(input_id, turn_id, 1)?;
        let mut opening = ticket(thread_id, 1);
        opening.checkpoint.state.inputs = Arc::from([input.clone()]);
        opening.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Arc::make_mut(&mut opening.effect).turn =
            Some(turn_record(turn_id, input_id, TurnState::Running));
        drive_live_projection(&mut projection, &chat, &sink, thread_id, opening)?;
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 1),
            sink.flush(thread_id, 1),
            || channel_facts(&sink),
        )
        .await??;
        assert!(
            store
                .history(thread_id)
                .await?
                .newest_terminal_turn()
                .await?
                .is_none()
        );
        let history = store.history(thread_id).await?;
        let admitted = history.latest_turn_at(1).await?.context("admitted Turn")?;
        assert_eq!(admitted.id, turn_id);
        assert!(!admitted.state.is_terminal());
        assert!(history.latest_turn_at(0).await.is_err());
        assert!(history.latest_turn_at(2).await.is_err());

        // Intervening commits advance the execution clock without changing the Turn item.
        // A terminal frame must outrank running frames even when its item content version is small.
        for sequence in 2..=10 {
            let mut intermediate = ticket(thread_id, sequence);
            intermediate.checkpoint.state.turns =
                Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
            drive_live_projection(&mut projection, &chat, &sink, thread_id, intermediate)?;
        }
        // Commit 11: the Turn finishes. The live projection of that same effect is the fact the frame
        // carried; the durable row the writer commits has to recover the identical Turn.
        let finished = || {
            turn_record(
                turn_id,
                input_id,
                TurnState::Finished(TurnOutcome::Completed),
            )
        };
        let mut terminal = ticket(thread_id, 11);
        terminal.checkpoint.state.turns = Arc::from([finished()]);
        Arc::make_mut(&mut terminal.effect).turn = Some(finished());
        let prepared = projection.project_committed(
            &chat,
            &test_thread(thread_id),
            &terminal.effect,
            &terminal.checkpoint.state,
        )?;
        let live = crate::studio::thread_projection::prepared_terminal_turn(&prepared)
            .context("the live projection must carry the finished Turn")?;
        drive_live_projection(&mut projection, &chat, &sink, thread_id, terminal)?;
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 11),
            sink.flush(thread_id, 11),
            || channel_facts(&sink),
        )
        .await??;

        let cold = store
            .history(thread_id)
            .await?
            .newest_terminal_turn()
            .await?
            .context("the durable history must carry the finished Turn")?;
        assert_eq!(
            live.revision, 11,
            "terminal frame must use the execution clock"
        );
        assert_eq!(cold.id, live.id);
        assert_eq!(cold.revision, live.revision);
        assert_eq!(cold.state, live.state);
        let saved = history.checkpoint().await?.context("durable checkpoint")?;
        assert!(saved.state.turns.is_empty(), "terminal Turns must retire");
        assert_eq!(
            history.latest_turn_at(saved.history_fence).await?,
            Some(live.clone())
        );

        // A later running admission must outrank the saved terminal. Evaluation cannot use the
        // terminal-only seed as a shortcut, even while that older terminal remains readable.
        let next_id = "newer-running-turn";
        let next_input = consumed_visible_input("newer-input", next_id, 12)?;
        let mut next = ticket(thread_id, 12);
        next.checkpoint.state.inputs = Arc::from([next_input.clone()]);
        next.checkpoint.state.turns =
            Arc::from([turn_record(next_id, "newer-input", TurnState::Running)]);
        Arc::make_mut(&mut next.effect).inputs = Arc::from([InputChange::Accepted(next_input)]);
        Arc::make_mut(&mut next.effect).turn =
            Some(turn_record(next_id, "newer-input", TurnState::Running));
        drive_live_projection(&mut projection, &chat, &sink, thread_id, next)?;
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 12),
            sink.flush(thread_id, 12),
            || channel_facts(&sink),
        )
        .await??;
        let latest = history.latest_turn_at(12).await?.context("latest Turn")?;
        assert_eq!(latest.id, next_id);
        assert!(!latest.state.is_terminal());
        assert_eq!(history.newest_terminal_turn().await?, Some(cold));
        assert!(history.latest_turn_at(11).await.is_err());
        Ok(())
    }

    #[tokio::test]
    async fn retained_budget_counts_the_bodies_the_live_projection_holds() {
        // A running Turn retains tool arguments, terminal results, attachment metadata and opaque
        // payloads. Charging only text and reasoning would leave the largest resident bodies outside
        // the Thread's reliable budget, so the estimate has to cover every category payload.
        let arguments = "a".repeat(4096);
        let result = "r".repeat(8192);
        let artifact = "z".repeat(2048);
        let raw_content = "p".repeat(1024);
        let failure = "f".repeat(256);
        let attachment = pl_protocol::ThreadAttachment {
            id: "artifact-attachment".to_owned(),
            modality: pl_protocol::AttachmentModality::File,
            media_type: "application/octet-stream".to_owned(),
            filename: Some("artifact.bin".to_owned()),
            width: None,
            height: None,
            byte_size: 64 * 1024 * 1024,
        };
        let tool = pl_protocol::ThreadItem::new(
            "tool-item".to_owned(),
            "retained-budget".to_owned(),
            "turn".to_owned(),
            1,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    "call".to_owned(),
                    "shell".to_owned(),
                    arguments.clone(),
                ),
                pl_protocol::ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                    1,
                    pl_protocol::ThreadToolOutput::new(
                        result.clone(),
                        vec![attachment.clone()],
                        vec![serde_json::json!({"stdout": artifact.clone()})],
                        Some(0),
                    ),
                )),
            )),
        );
        let raw = pl_protocol::ThreadItem::new(
            "raw-item".to_owned(),
            "retained-budget".to_owned(),
            "turn".to_owned(),
            2,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
                vec![pl_protocol::ThreadRawPayload {
                    format: "pl.model.receipt".to_owned(),
                    version: 1,
                    content: raw_content.clone(),
                }],
                String::new(),
                1,
            )),
        );
        let failed_text = pl_protocol::ThreadItem::new(
            "failed-text".to_owned(),
            "retained-budget".to_owned(),
            "turn".to_owned(),
            3,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Text(pl_protocol::ThreadTextItem::new(
                pl_protocol::ThreadTextChannel::Commentary,
                "visible".to_owned(),
                vec![attachment],
                pl_protocol::ThreadContentLifecycle::failed(1, failure.clone()),
            )),
        );
        let bytes = crate::studio::thread_projection::retained_bytes(&[tool, raw, failed_text]);
        let bodies =
            (arguments.len() + result.len() + artifact.len() + raw_content.len() + failure.len())
                as u64;
        assert!(
            bytes >= bodies,
            "retained budget {bytes} must cover the {bodies} resident body bytes"
        );
    }

    #[tokio::test]
    async fn projection_gauge_is_part_of_the_thread_budget() -> Result<()> {
        let (_temp, _store, sink) = sink("projection-budget").await?;
        // The projection owner keeps a Turn's retained bodies and its report accumulator resident
        // after their batch became durable. The Thread's budget therefore reads the owner's absolute
        // gauge, and releasing the owner's tables releases the budget with them.
        sink.0.channel.set_projection_bytes(8192);
        assert_eq!(sink.pressure("projection-budget").thread_bytes, 8192);
        assert_eq!(sink.0.channel.subscribe().borrow().queued_bytes, 8192);
        sink.0.channel.set_projection_bytes(0);
        assert_eq!(sink.pressure("projection-budget").thread_bytes, 0);
        assert_eq!(sink.0.channel.subscribe().borrow().queued_bytes, 0);
        Ok(())
    }

    #[tokio::test]
    async fn operation_output_reservation_returns_to_baseline_across_rounds() -> Result<()> {
        // Idle operations must not spend their hypothetical maximum output. More than sixteen
        // parallel tools with tiny output must run without exhausting the 256 MiB process budget.
        let (_temp, _store, sink) = sink("operation-budget").await?;
        let channel = &sink.0.channel;
        let baseline = channel.process_bytes.load(Ordering::Acquire);
        for index in 0..32 {
            assert_eq!(
                channel.reserve_operation_output(&format!("idle-{index}"), 16 * 1024 * 1024),
                Some(16 * 1024 * 1024)
            );
        }
        assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
        for index in 0..32 {
            channel.release_operation_output(&format!("idle-{index}"));
        }
        for round in 0..4_u64 {
            let operation = format!("task:call-{round}");
            let granted = channel
                .reserve_operation_output(&operation, 4096)
                .expect("the empty budget funds the reservation");
            assert_eq!(granted, 4096);
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline,
                "a ceiling without produced bytes consumes no resident budget"
            );
            channel.charge_operation_output(&operation, 1024)?;
            channel.charge_operation_output(&operation, 1024)?;
            assert!(channel.charge_operation_output(&operation, 4097).is_err());
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline + 1024
            );
            channel.release_operation_output(&operation);
            channel.release_operation_output(&operation);
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline,
                "a finished call releases all accepted bytes"
            );
        }
        Ok(())
    }

    /// The whole reserve/complete/refuse/recover cycle of parallel in-flight operations.
    ///
    /// Four operations reserve the process budget down to its last byte, which is exactly the state
    /// where charging an admitted fact *next to* the reservation that produced it would need space
    /// that does not exist: every result would be refused, no result could be handed over, and the
    /// reservations would be held forever waiting for the queue they themselves block. The rule under
    /// test is the transfer instead — the bytes a reservation covers become the fact's own charge, so
    /// a fully reserved process still hands its facts over — together with the boundaries that stay
    /// real: an uncovered fact is refused with a typed fault instead of being admitted over budget,
    /// the refused fact is handed over unchanged once its Thread's ceiling comes back, and the
    /// process gauge returns to the baseline once everything is durable.
    #[tokio::test]
    async fn parallel_reservations_transfer_into_their_facts_without_deadlock() -> Result<()> {
        // No test projection here: nothing takes the admitted facts over until the test hands them
        // in itself, so the durable watermark cannot drain the queue while the reservations are
        // still charged and every step below is deterministic.
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("output-transfer")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("output-transfer"), None).await?;
        let channel = &sink.0.channel;
        let baseline = channel.process_bytes.load(Ordering::Acquire);
        // A quarter of the process budget each: four in-flight calls leave no headroom at all.
        let reservation = MAX_HISTORY_PROCESS_BYTES / 4;
        let operations = (0..4)
            .map(|index| format!("task:parallel-{index}"))
            .collect::<Vec<_>>();
        for operation in &operations {
            let granted = channel
                .reserve_operation_output(operation, reservation)
                .expect("the empty budget funds a quarter of itself");
            assert_eq!(granted, reservation);
            channel.charge_operation_output(operation, reservation)?;
        }
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            MAX_HISTORY_PROCESS_BYTES,
            "the reservations alone fill the process budget"
        );
        assert!(
            channel
                .reserve_operation_output("task:one-too-many", reservation)
                .is_none(),
            "a call that the reliable budget cannot fund is backpressure, never a silent grant"
        );

        // A fact no reservation covers is refused while there is no headroom and no projection holds
        // a queued fact that could free any: typed backpressure, nothing dropped, ticket untouched.
        let uncovered = visible_input_ticket("output-transfer", 5, "input-uncovered")?;
        sink.admit("output-transfer", uncovered.clone())
            .expect_err("an unfunded fact cannot be admitted into a full budget");
        let refused = channel.subscribe().borrow().clone();
        assert_eq!(
            refused.fault,
            Some(pl_protocol::studio::HistoryFault::QueueFull)
        );

        // Every call returns: its result is admitted while the process budget is still full, which
        // only works because the reservation it was made under is transferred onto the fact.
        for (index, operation) in operations.iter().enumerate() {
            let sequence = index as u64 + 1;
            let mut write =
                visible_input_ticket("output-transfer", sequence, &format!("input-{index}"))?;
            write.output_claim = Some(operation.clone());
            sink.admit("output-transfer", write)
                .expect("the reservation funds the fact it was made for");
        }
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            MAX_HISTORY_PROCESS_BYTES,
            "transferring a reservation onto a fact adds no second charge for the same output"
        );

        // Recovery: the first call ends, so its remaining ceiling comes back and the very same
        // ticket is admitted unchanged; the rest of the calls end too.
        channel.release_operation_output(&operations[0]);
        sink.admit("output-transfer", uncovered)?;
        for operation in &operations[1..] {
            channel.release_operation_output(operation);
        }

        // The Thread's own projection owner hands the admitted facts over in admission order, which
        // is what lets the writer save them; then the fixed fault generation is retried and every
        // fact is durable.
        let mut projection = live_projection();
        while let Some(write) = channel.next_unprojected() {
            let prepared = projection.project_committed(
                &sink.0.chat,
                &sink.0.thread,
                &write.effect,
                &write.checkpoint.state,
            )?;
            assert!(channel.prepare(prepared));
        }
        tokio::time::timeout(
            Duration::from_secs(10),
            store
                .thread_persistence()
                .retry_history("output-transfer", refused.fault_generation),
        )
        .await??;
        assert_eq!(
            store.history("output-transfer").await?.watermark().await?,
            5
        );
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            baseline,
            "once every fact is durable and every call ended, the process gauge is back to baseline"
        );
        let drained = channel.subscribe().borrow().clone();
        assert!(drained.error.is_none() && drained.fault.is_none());
        Ok(())
    }

    #[tokio::test]
    async fn queue_pressure_keeps_the_original_ticket_until_retry_and_commit() -> Result<()> {
        let (_temp, store, sink) = sink("queue-pressure").await?;
        let write = ticket("queue-pressure", 1);
        sink.0
            .channel
            .process_bytes
            .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
        assert!(sink.admit("queue-pressure", write.clone()).is_err());
        let fault = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(
            fault.fault,
            Some(pl_protocol::studio::HistoryFault::QueueFull)
        );
        assert_eq!(fault.admitted_sequence, 0);
        assert_eq!(fault.queued_records, 0);
        sink.0.channel.process_bytes.store(0, Ordering::Release);
        sink.admit("queue-pressure", write)?;
        assert!(sink.flush("queue-pressure", 1).await.is_err());
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("queue-pressure", fault.fault_generation),
        )
        .await??;
        assert_eq!(store.history("queue-pressure").await?.watermark().await?, 1);
        let recovered = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(recovered.queued_records, 0);
        assert_eq!(recovered.fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn sqlite_rejection_retains_the_real_writer_queue_until_recovery() -> Result<()> {
        let (_temp, store, sink) = sink("sqlite-rejection").await?;
        sink.admit("sqlite-rejection", ticket("sqlite-rejection", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("sqlite-rejection", 1),
            || channel_facts(&sink),
        )
        .await??;
        let path = store
            .session_paths("project-test", "sqlite-rejection")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled writer rejection'); END",
        )
        .await?;
        let mut status = sink.0.channel.subscribe();
        sink.admit("sqlite-rejection", ticket("sqlite-rejection", 2))?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        assert_eq!(failed.queued_records, 1);
        assert_eq!(
            store.history("sqlite-rejection").await?.watermark().await?,
            1
        );
        assert!(sink.flush("sqlite-rejection", 2).await.is_err());
        db.execute_unprepared("DROP TRIGGER reject_history").await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("sqlite-rejection", failed.fault_generation),
        )
        .await??;
        assert_eq!(
            store.history("sqlite-rejection").await?.watermark().await?,
            2
        );
        let recovered = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(recovered.queued_records, 0);
        assert_eq!(recovered.fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn concurrent_tool_results_survive_a_real_writer_failure_without_reexecution()
    -> Result<()> {
        let (_temp, store, sink) = sink("concurrent-results").await?;
        let requests = Arc::new(AtomicUsize::new(0));
        let thread = ThreadHandle::start(
            "concurrent-results".into(),
            DynModelSession::new(ConcurrentModel(requests.clone())),
        )?;
        let (started, mut starts) = mpsc::unbounded_channel();
        let executions = Arc::new(Mutex::new(Vec::new()));
        let releases: Vec<_> = (0..2).map(|_| Arc::new(Notify::new())).collect();
        thread
            .register_tools(
                ["first", "second"]
                    .into_iter()
                    .zip(releases.iter())
                    .map(|(id, release)| {
                        Registration::new(
                            id.into(),
                            OpaquePayload::text(format!("Tool {id}")),
                            ConcurrentTool {
                                started: started.clone(),
                                release: release.clone(),
                                executions: executions.clone(),
                            },
                        )
                    })
                    .collect::<Result<Vec<_>, _>>()?,
            )
            .await?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        let turn = TurnInput {
            turn_id: "both-running".into(),
            attempt_prefix: "both-running".into(),
            content: vec![ContextContent::Text {
                text: Arc::from("start"),
            }],
            max_model_steps: ModelStepLimit::Limited(1.try_into()?),
            cancellation: CancellationToken::new(),
        };
        let runner = tokio::spawn({
            let thread = thread.clone();
            async move { thread.run_turn(turn).await }
        });
        tokio::time::timeout(Duration::from_secs(10), async {
            let mut started = [starts.recv().await, starts.recv().await];
            started.sort();
            assert_eq!(started, [Some("first".into()), Some("second".into())]);
        })
        .await?;
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), runner)
                .await???
                .outcome,
            TurnOutcome::StepLimit
        );
        thread.flush().await?;
        let baseline = store
            .history("concurrent-results")
            .await?
            .watermark()
            .await?;
        let path = store
            .session_paths("project-test", "concurrent-results")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled concurrent rejection'); END",
        )
        .await?;

        for release in &releases {
            release.notify_one();
        }
        let mut snapshots = thread.subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let snapshot = snapshots.next().await.unwrap();
                if snapshot.terminal_tasks.len()
                    + snapshot
                        .tasks
                        .values()
                        .filter(|task| task.status != TaskStatus::Running)
                        .count()
                    == 2
                {
                    break;
                }
            }
        })
        .await?;
        let mut status = sink.0.channel.subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        assert!(failed.queued_records >= 2);
        assert_eq!(
            store
                .history("concurrent-results")
                .await?
                .watermark()
                .await?,
            baseline
        );
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        assert_eq!(*executions.lock().unwrap(), ["first", "second"]);

        db.execute_unprepared("DROP TRIGGER reject_history").await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("concurrent-results", failed.fault_generation),
        )
        .await??;
        thread.flush().await?;
        let history = store.history("concurrent-results").await?;
        assert_eq!(
            history.watermark().await?,
            thread.snapshot().commit_sequence
        );
        for id in ["first", "second"] {
            let fact = history.tool_task(&format!("task:{id}")).await?.unwrap();
            assert_eq!(fact.task.call_id, id);
            assert_eq!(fact.delivery.unwrap().call_id, id);
        }
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        assert_eq!(executions.lock().unwrap().len(), 2);
        thread.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn committed_batch_is_replayed_after_ack_is_lost() -> Result<()> {
        let (_temp, store, sink) = sink("lost-ack").await?;
        // The Thread's projection owner hands the batch over before the writer may write it. The test
        // drives that one write directly, under the step lock, so it can lose the acknowledgement while
        // the queue entry stays — exactly the retry the writer has to make idempotent.
        let write = ticket("lost-ack", 1);
        let chat = store.chat_session("lost-ack").await?;
        let mut projection = live_projection();
        let prepared = projection.project_committed(
            &chat,
            &sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
        )?;
        let locked = sink.0.channel.step_lock.lock().await;
        sink.admit("lost-ack", write.clone())?;
        persist_effect(&sink.0, 1, &write, &prepared).await?;
        assert_eq!(store.history("lost-ack").await?.watermark().await?, 1);
        assert_eq!(sink.0.channel.subscribe().borrow().queued_records, 1);
        sink.0.channel.mark_unavailable(|| true);
        let unavailable = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(
            unavailable.fault,
            Some(pl_protocol::studio::HistoryFault::WriterUnavailable)
        );
        assert!(sink.flush("lost-ack", 1).await.is_err());
        drop(locked);
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("lost-ack", unavailable.fault_generation),
        )
        .await??;
        assert_eq!(store.history("lost-ack").await?.watermark().await?, 1);
        let status = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(status.queued_records, 0);
        assert_eq!(status.fault, None);
        let mut persistence = store.thread_persistence().subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let row = store
                    .thread_persistence()
                    .queue_snapshot()
                    .threads
                    .into_iter()
                    .find(|row| row.thread_id == "lost-ack")
                    .context("missing live Thread persistence row")?;
                if row.calls_admitted_sequence == Some(1) && row.calls_durable_sequence == Some(1) {
                    break Ok::<_, anyhow::Error>(());
                }
                persistence.changed().await?;
            }
        })
        .await??;
        Ok(())
    }

    /// A rejected commit rolls back the effect's history, its latest context and its checkpoint
    /// together, so the writer never advances the history watermark to a revision whose checkpoint
    /// the very same transaction failed to store — the atomicity the old split write could not give.
    #[tokio::test]
    async fn a_rejected_atomic_commit_never_advances_history_without_its_checkpoint() -> Result<()>
    {
        let (_temp, store, sink) = sink("atomic-failure").await?;
        // Commit one effect first so the history database exists, then reject the second one's whole
        // transaction from the watermark update that every atomic commit performs.
        sink.admit("atomic-failure", ticket("atomic-failure", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("atomic-failure", 1),
            || channel_facts(&sink),
        )
        .await??;
        let path = store
            .session_paths("project-test", "atomic-failure")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_watermark BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled atomic rejection'); END",
        )
        .await?;
        let mut status = sink.0.channel.subscribe();
        sink.admit("atomic-failure", ticket("atomic-failure", 2))?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        // Nothing of the rejected revision is durable: the watermark stays on the previously
        // committed effect and the effect is retained in order for retry.
        assert_eq!(failed.committed_sequence, 1);
        assert_eq!(failed.queued_records, 1);
        assert_eq!(store.history("atomic-failure").await?.watermark().await?, 1);
        assert!(sink.flush("atomic-failure", 2).await.is_err());
        db.execute_unprepared("DROP TRIGGER reject_watermark")
            .await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("atomic-failure", failed.fault_generation),
        )
        .await??;
        assert_eq!(store.history("atomic-failure").await?.watermark().await?, 2);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn missing_blob_blocks_checkpoint_until_the_same_attachment_is_durable() -> Result<()> {
        use pl_core::context::ResourceReader as _;
        use sha2::Digest as _;

        let (temp, store, sink) = sink("blob-fence").await?;
        let session = store.session_paths("project-test", "blob-fence")?;
        let source = temp.path().join("attachment-draft");
        let bytes = b"restored";
        tokio::fs::write(&source, bytes).await?;
        let draft = crate::studio::store::attachment::AttachmentDraftObject {
            draft_id: "draft-1".to_owned(),
            modality: pl_protocol::studio::StudioAttachmentModality::File,
            media_type: "text/plain".to_owned(),
            filename: "attachment.txt".to_owned(),
            storage_path: source,
            byte_size: bytes.len() as u64,
            content_sha256: hex::encode(sha2::Sha256::digest(bytes)),
            width: None,
            height: None,
            initial_remote_url: None,
        };
        let attachment = store
            .promote_attachment_drafts("blob-fence", &[draft])
            .await?
            .pop()
            .context("promoted attachment is missing")?;
        let reference = store.retain_attachment_resource(&attachment).await?;
        let blob = session.root().join(&attachment.blob_relative_path);
        tokio::fs::remove_file(&blob).await?;
        let resources = crate::resource_store::FileResourceStore::new(session.resources_dir());
        assert_eq!(
            resources
                .read(reference, tokio_util::sync::CancellationToken::new())
                .await?
                .as_ref(),
            bytes
        );
        store.record_attachments(vec![attachment.clone()]).await?;
        let mut status = sink.0.channel.subscribe();
        sink.admit(
            "blob-fence",
            ticket_referencing_attachment("blob-fence", &attachment)?,
        )?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::BlobFailed)
        );
        // The blob fence runs before the atomic commit, so the missing blob blocks both the effect's
        // history and its checkpoint: the watermark stays untouched until the blob is durable.
        assert_eq!(failed.committed_sequence, 0);
        assert_eq!(failed.queued_records, 1);
        assert!(sink.flush("blob-fence", 1).await.is_err());
        tokio::fs::create_dir_all(blob.parent().expect("blob has a parent")).await?;
        tokio::fs::write(&blob, bytes).await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("blob-fence", failed.fault_generation),
        )
        .await??;
        assert_eq!(store.history("blob-fence").await?.watermark().await?, 1);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn closing_the_chat_and_sink_does_not_release_pending_history() -> Result<()> {
        let (_temp, store, sink) = sink("closed-view").await?;
        sink.admit("closed-view", ticket("closed-view", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("closed-view", 1),
            || channel_facts(&sink),
        )
        .await??;
        let chat = store.chat_session("closed-view").await?;
        let path = store
            .session_paths("project-test", "closed-view")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled closed-view rejection'); END",
        )
        .await?;
        let channel = store.thread_persistence().history_channel("closed-view");
        let mut updates = channel.subscribe();
        sink.admit("closed-view", ticket("closed-view", 2))?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while updates.borrow_and_update().fault.is_none() {
                updates.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let generation = updates.borrow().fault_generation;
        drop(chat);
        drop(sink);
        assert_eq!(channel.subscribe().borrow().queued_records, 1);
        assert_eq!(store.history("closed-view").await?.watermark().await?, 1);
        db.execute_unprepared("DROP TRIGGER reject_history").await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("closed-view", generation),
        )
        .await??;
        assert_eq!(store.history("closed-view").await?.watermark().await?, 2);
        assert_eq!(channel.subscribe().borrow().queued_records, 0);
        Ok(())
    }

    #[tokio::test]
    async fn stopped_statistics_consumer_never_blocks_history_or_checkpoint() -> Result<()> {
        let (_temp, store, sink) = sink("statistics-gap").await?;
        store.calls().stop_best_effort();
        assert!(
            !store
                .calls()
                .try_admit_effect(&ticket("statistics-gap", 1).effect)
        );
        store
            .thread_persistence()
            .report_calls(store.calls().metrics());
        assert!(store.thread_persistence().queue_snapshot().statistics_gap);
        sink.admit("statistics-gap", ticket("statistics-gap", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("statistics-gap", 1),
            || channel_facts(&sink),
        )
        .await??;
        assert_eq!(store.history("statistics-gap").await?.watermark().await?, 1);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        assert!(store.thread_persistence().queue_snapshot().statistics_gap);
        Ok(())
    }

    #[tokio::test]
    async fn crashed_statistics_consumer_does_not_block_history_and_restarts() -> Result<()> {
        let (_temp, store, sink) = sink("statistics-crash").await?;
        let calls = store.calls();
        calls.panic_on_next_mutation();
        assert!(calls.try_admit_effect(&ticket("statistics-crash", 1).effect));
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if calls
                    .last_error()
                    .is_some_and(|message| message.contains("terminated unexpectedly"))
                {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("call writer did not report the injected worker exit")?;
        assert!(calls.statistics_gap());
        let dropped_ticket = calls.admitted_ticket();
        assert!(calls.try_admit_effect(&ticket("statistics-crash", 2).effect));
        let resumed_ticket = calls.admitted_ticket();
        assert!(resumed_ticket > dropped_ticket);

        sink.admit("statistics-crash", ticket("statistics-crash", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("statistics-crash", 1),
            || channel_facts(&sink),
        )
        .await
        .context("history flush stalled after the call writer exit")??;
        assert_eq!(
            store.history("statistics-crash").await?.watermark().await?,
            1
        );
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if calls.durable_ticket() >= resumed_ticket {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("call writer did not advance the resumed ticket")?;
        assert!(calls.statistics_gap());
        Ok(())
    }

    #[tokio::test]
    async fn stale_fault_generation_cannot_resume_a_new_queue_failure() -> Result<()> {
        let (_temp, store, sink) = sink("fault-generation").await?;
        for sequence in [1, 2] {
            sink.0
                .channel
                .process_bytes
                .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
            let write = ticket("fault-generation", sequence);
            assert!(sink.admit("fault-generation", write.clone()).is_err());
            let failed = sink.0.channel.subscribe().borrow().clone();
            assert_eq!(failed.fault_generation, sequence);
            if sequence == 2 {
                assert!(sink.0.channel.retry(1).is_err());
                assert_eq!(sink.0.channel.subscribe().borrow().fault_generation, 2);
            }
            sink.0.channel.process_bytes.store(0, Ordering::Release);
            sink.admit("fault-generation", write)?;
            tokio::time::timeout(
                Duration::from_secs(5),
                store
                    .thread_persistence()
                    .retry_history("fault-generation", sequence),
            )
            .await??;
        }
        assert_eq!(
            store.history("fault-generation").await?.watermark().await?,
            2
        );
        Ok(())
    }

    /// The continue entry the UI reads is exactly the Thread owner's readiness, with nothing else
    /// able to light it.
    ///
    /// The writer reports watermarks and the typed fault generation, but no readiness of its own:
    /// the owner can still owe a newer fault while a writer has long since written an older retry, so
    /// the projection takes the owner's single verdict — byte for byte — instead of combining
    /// anything a writer reports. `resume_required` stays a separate fact: readiness never releases
    /// the latch by itself.
    #[test]
    fn can_resume_is_exactly_the_owners_readiness() {
        use crate::studio::thread_projection::storage_state;

        let mut owner = ThreadSnapshot::default();
        owner.persistence.resume_required = true;
        owner.persistence.fault_generation = 2;

        // A writer that is already past this generation's fault — it reports the same generation with
        // no error and fully admitted watermarks — still cannot offer a continue the owner refuses.
        let writer = pl_protocol::ThreadPersistenceSnapshot {
            fault_generation: 2,
            history_admitted_sequence: Some(9),
            history_durable_sequence: Some(9),
            last_error: None,
            ..pl_protocol::ThreadPersistenceSnapshot::default()
        };
        let storage = storage_state(&owner, &writer);
        assert!(storage.resume_required);
        assert!(
            !storage.can_resume,
            "only the owner's own generation-matched readiness may enable the continue"
        );
        assert_eq!(
            storage.accepted_sequence,
            Some(9),
            "the writer's own watermarks still reach the UI as facts"
        );

        // The owner's verified readiness is the fact, whatever else the writer reports.
        owner.persistence.resume_ready = true;
        assert!(storage_state(&owner, &writer).can_resume);
    }

    /// One `(identity, content version)` pair is one canonical payload, even when the same fact is
    /// projected a second time.
    ///
    /// The projection owner folds an admitted fact once, but the same effect can legitimately reach
    /// the projection again — a commit the owner's snapshot already carried, a durable step retried
    /// after a real writer failure, or a re-subscription. Every pass must deliver the *same bytes*
    /// for a `(item_id, revision)` pair: a pass that restamped the projection clock would hand the
    /// durable writer two different payloads under one version, which the store's own revision fence
    /// rejects as a real save fault instead of the idempotent rewrite it is. This pins that a repeat
    /// projection reuses the version, placement and timestamps of the payload it already delivered.
    #[tokio::test]
    async fn reprojecting_an_unchanged_effect_keeps_one_canonical_payload() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("stable-payload")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("stable-payload"), None).await?;
        let chat = store.chat_session("stable-payload").await?;
        // The commit sequence is deliberately far above the item's own content version, so a sequence
        // leaking into the version shows up as a value change instead of a coincidence.
        let write = visible_input_ticket("stable-payload", 9, "stable-input")?;
        let mut projection = live_projection();
        let first = projection.project_committed(
            &chat,
            &sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
        )?;
        let second = projection.project_committed(
            &chat,
            &sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
        )?;
        assert_eq!(
            first.items[0].revision, 1,
            "a first delivery takes the projection's own content version, not the commit sequence"
        );
        assert_eq!(
            serde_json::to_vec(&first.items)?,
            serde_json::to_vec(&second.items)?,
            "a repeat projection of an unchanged fact is byte-identical, so one version never names two payloads"
        );
        Ok(())
    }

    /// The durable row carries the item's own **content version**, never the effect sequence that
    /// committed it, and a cold read of the same history file observes the same value.
    ///
    /// A save receipt is a fact about one exact `(identity, content version)` pair. Substituting the
    /// commit sequence for the version would let an acknowledgement vouch for a payload the store
    /// never wrote, so both ends are pinned here: the shared session confirms exactly the revision
    /// the projection published, and a separate history handle — the cold path, which decodes the
    /// durable row itself instead of reading live projection state — returns that same revision.
    #[tokio::test]
    async fn the_durable_row_keeps_the_items_own_content_version_across_a_cold_read() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("revision-fence")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("revision-fence"), None).await?;
        let chat = store.chat_session("revision-fence").await?;
        // The commit sequence is deliberately far above the item's first content version: the
        // projection decides the content version, and the writer has to store that exact value.
        let write = visible_input_ticket("revision-fence", 9, "revision-input")?;
        // No test projection task here: the test hands the one fact over itself, exactly like the
        // Thread's observation worker, so the publish/hand-off/confirm order is deterministic.
        let mut projection = live_projection();
        // Advance through real, contiguous empty commits; a large write sequence cannot be
        // invented independently of the checkpoint's history fence.
        for sequence in 1..9 {
            let seed = ticket("revision-fence", sequence);
            let prepared = projection.project_committed(
                &chat,
                &sink.0.thread,
                &seed.effect,
                &seed.checkpoint.state,
            )?;
            sink.admit("revision-fence", seed)?;
            sink.0.channel.prepare(prepared);
        }
        let prepared = projection.project_committed(
            &chat,
            &sink.0.thread,
            &write.effect,
            &write.checkpoint.state,
        )?;
        // The projection publishes before it hands the same immutable batch to the reliable queue.
        for item in &prepared.items {
            chat.publish(chat_item(item.clone(), false)?)?;
        }
        sink.admit("revision-fence", write)?;
        sink.0.channel.prepare(prepared);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 9),
            sink.flush("revision-fence", 9),
            || channel_facts(&sink),
        )
        .await??;

        let published = shown_item(&chat, "revision-input").await;
        // The real allocation entry point is pinned, not just "different from the commit sequence":
        // a fresh projection's first delivery of a new identity is that identity's content version 1.
        assert_eq!(
            published.revision, 1,
            "a first delivery takes the projection's own content version, not the commit sequence"
        );
        assert_ne!(
            published.revision, 9,
            "a content version is the item's own fact, never the commit sequence"
        );
        assert!(
            published.saved,
            "the writer confirms exactly the revision the projection published"
        );

        let path = store
            .session_paths("project-test", "revision-fence")?
            .root()
            .join("history.sqlite");
        let cold =
            crate::studio::storage::history::HistoryStore::open(&path, "revision-fence").await?;
        let durable = cold.items_for_turn("visible-turn").await?;
        assert_eq!(durable.len(), 1);
        assert_eq!(durable[0].id, "revision-input");
        assert_eq!(
            durable[0].revision, published.revision,
            "the persisted row carries the same content version the live projection confirmed"
        );
        Ok(())
    }

    /// An acknowledgement for a revision the identity already left behind confirms nothing.
    ///
    /// The save watermark is a fact about one exact payload. A receipt that names an older content
    /// version must not mark the newer body durable: the newer payload stays unsaved until its own
    /// revision is acknowledged, so a late receipt can never stand in for a write that never
    /// happened.
    #[tokio::test]
    async fn an_acknowledgement_of_an_older_revision_never_confirms_the_newer_payload() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("stale-ack")).await?;
        let chat = store.chat_session("stale-ack").await?;

        chat.publish_preview(revised_preview("stale-ack", "revised", 1, 1, "first body")?)?;
        chat.publish_preview(revised_preview(
            "stale-ack",
            "revised",
            1,
            2,
            "second body",
        )?)?;
        assert_eq!(shown_item(&chat, "revised").await.revision, 2);

        // The stale receipt names revision 1 while the identity already advanced to revision 2.
        chat.confirm_saved("revised", 1);
        assert!(
            !shown_item(&chat, "revised").await.saved,
            "an acknowledgement of a revision the identity left behind confirms nothing"
        );

        chat.confirm_saved("revised", 2);
        assert!(
            shown_item(&chat, "revised").await.saved,
            "only the exact published revision becomes the saved watermark"
        );
        Ok(())
    }

    /// The archive duty a real command capture owes after its append failed.
    ///
    /// It re-materializes the accepted chunk through the real local backend and then archives the
    /// fragment with the real content-addressed store, so the reference the retry names is a genuine
    /// durable resource and not a stand-in.
    #[derive(Debug)]
    struct CaptureRepairObligation {
        backend: pl_tool::command::LocalCommandBackend,
        archive: crate::resource_store::FileResourceStore,
        capture_file: std::path::PathBuf,
        call_id: String,
        committed_len: u64,
        pending: Vec<u8>,
        retries: Arc<AtomicUsize>,
    }

    impl pl_core::thread::cold::OutputRetryObligation for CaptureRepairObligation {
        fn identity(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn retry(&self) -> pl_core::thread::cold::OutputRetryFuture<'_> {
            Box::pin(async move {
                self.retries.fetch_add(1, Ordering::SeqCst);
                // The real backend truncates the fragment back to its committed offset and re-appends
                // exactly the accepted chunk with the same framing a successful append would produce,
                // so a repeated retry reproduces the same bytes instead of appending them twice.
                pl_tool::command::CommandBackend::repair_output_chunk(
                    &self.backend,
                    &self.capture_file,
                    pl_tool::command::CommandCaptureStream::Stdout,
                    self.committed_len,
                    &self.pending,
                )
                .await
                .map_err(|error| pl_core::thread::cold::ColdStoreError {
                    source: Box::new(std::io::Error::other(error.to_string())),
                })?;
                let reference = self
                    .archive
                    .retain_command_capture(&self.capture_file)
                    .await
                    .map_err(|error| pl_core::thread::cold::ColdStoreError {
                        source: Box::new(error),
                    })?;
                Ok(pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(
                    pl_core::thread::cold::OutputRepair {
                        call_id: self.call_id.clone(),
                        reference,
                    },
                ))
            })
        }
        fn received_bytes(&self) -> u64 {
            self.committed_len.saturating_add(self.pending.len() as u64)
        }
        fn location(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn kind(&self) -> pl_core::thread::cold::StorageFaultKind {
            pl_core::thread::cold::StorageFaultKind::WriteFailed
        }
    }

    /// A command whose capture append really failed, so its archive still owes the accepted bytes.
    #[derive(Debug)]
    struct FailedAppendCaptureTool {
        backend: pl_tool::command::LocalCommandBackend,
        archive: crate::resource_store::FileResourceStore,
        capture_file: std::path::PathBuf,
        committed_len: u64,
        pending: Vec<u8>,
        retries: Arc<AtomicUsize>,
        created: Arc<Mutex<Vec<Arc<CaptureRepairObligation>>>>,
    }

    impl Tool for FailedAppendCaptureTool {
        async fn execute(
            &self,
            input: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            let obligation = Arc::new(CaptureRepairObligation {
                backend: self.backend.clone(),
                archive: self.archive.clone(),
                capture_file: self.capture_file.clone(),
                call_id: context.call_id.clone(),
                committed_len: self.committed_len,
                pending: self.pending.clone(),
                retries: self.retries.clone(),
            });
            self.created.lock().unwrap().push(obligation.clone());
            let source = pl_core::thread::cold::ColdStoreError {
                source: Box::new(std::io::Error::other("capture append failed")),
            };
            let fault = pl_core::thread::cold::OutputStorageFault::new(
                pl_core::thread::cold::StorageFaultKind::WriteFailed,
                Arc::new(source),
            )
            .with_obligation(obligation);
            Err(ToolError::new(fault).with_output(ToolOutput::new(
                input.clone(),
                vec![ContextContent::Text {
                    text: Arc::from("accepted so far"),
                }],
            )))
        }
    }

    #[derive(Debug)]
    struct CaptureModel;

    impl ModelSession for CaptureModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("calling capture"),
                    }],
                    tool_calls: vec![ModelToolCall {
                        rejection: None,
                        call_id: "capture-1".to_owned(),
                        tool_id: "capture".to_owned(),
                        arguments: OpaquePayload::text("capture"),
                    }],
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    /// The owner facts one stuck wait is diagnosed from, so a timeout names a stage instead of a bare
    /// deadline and a real owner bug is not masked by a longer one.
    fn stage_facts(snapshot: &ThreadSnapshot) -> String {
        format!(
            "fault={:?} generation={} phase={:?} obligations={} resume_required={} resume_ready={} \
             commit={} durable={}",
            snapshot.persistence.fault,
            snapshot.persistence.fault_generation,
            snapshot.persistence.execution_phase,
            snapshot.persistence.output_obligations.len(),
            snapshot.persistence.resume_required,
            snapshot.persistence.resume_ready,
            snapshot.commit_sequence,
            snapshot.persistence.durable_sequence,
        )
    }

    /// A best-effort snapshot of the reliable channel taken when one durable barrier expires.
    ///
    /// It reports the watermarks, the queue, the published fault and the oldest effect no projection
    /// has taken over yet, so an expired budget is accompanied by the facts the wait was measured
    /// against instead of only `deadline has elapsed`. The values are read from live state and may
    /// already reflect concurrent progress: they are not an atomic snapshot of one instant, and
    /// `unprojected` names only the earliest effect that is unprepared at the moment of the read.
    /// Neither its presence nor its absence decides on its own whether a stall came from scheduling,
    /// IO, a lock or a logic defect — those fields are evidence for a later judgement, not a verdict.
    fn channel_facts(sink: &ThreadStorageSink) -> String {
        let channel = &sink.0.channel;
        let facts = {
            let status = channel.subscribe();
            let status = status.borrow();
            format!(
                "durable={} admitted={} queued={} ({} bytes) fault={:?} generation={} error={:?}",
                status.committed_sequence,
                status.admitted_sequence,
                status.queued_records,
                status.queued_bytes,
                status.fault,
                status.fault_generation,
                status.error,
            )
        };
        let unprojected = channel
            .next_unprojected()
            .map(|write| write.effect.sequence);
        format!("{facts} unprojected={unprojected:?}")
    }

    /// Awaits the supplied future under the caller's timeout budget.
    ///
    /// On expiry, appends the caller-provided diagnostic text without inferring a cause.
    async fn await_durable<T>(
        budget: Duration,
        stage: &str,
        future: impl std::future::Future<Output = T>,
        describe: impl FnOnce() -> String,
    ) -> Result<T> {
        match tokio::time::timeout(budget, future).await {
            Ok(value) => Ok(value),
            Err(_) => anyhow::bail!("`{stage}` did not land: {}", describe()),
        }
    }

    /// Waits until the authoritative snapshot satisfies `predicate`, tagging `stage` on timeout.
    ///
    /// The subscription yields the current snapshot first, so a boundary that already landed is observed
    /// without waiting for an unrelated new frame — the exact shape of the earlier hang — and the timeout
    /// reports the stage and the last owner facts so the production cause is located, not hidden.
    async fn await_stage(
        thread: &ThreadHandle,
        stage: &str,
        predicate: impl Fn(&ThreadSnapshot) -> bool,
    ) -> Result<ThreadSnapshot> {
        let mut snapshots = thread.subscribe();
        let reached = tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = snapshots.next().await.expect("thread stays observable");
                if predicate(&snapshot) {
                    return snapshot;
                }
            }
        })
        .await;
        reached.map_err(|_| {
            anyhow::anyhow!(
                "stage `{stage}` was not reached: {}",
                stage_facts(&thread.snapshot())
            )
        })
    }

    /// The reference a repaired capture stored reaches the durable tool result, not just memory.
    ///
    /// The append failed after the fragment already held a partial write, so the retry must repair
    /// the fragment through the real local backend before archiving it: the archived bytes are the
    /// accepted content, verbatim and without duplication. The writer must then record that reference
    /// on the tool identity it was committed under — on the projected item *and* on the delivery
    /// history keeps — so the UI and a cold reopen can both locate the complete output, and the pause
    /// must stay closed until the archive really landed.
    #[tokio::test]
    async fn a_repaired_capture_reference_reaches_the_durable_tool_result() -> Result<()> {
        use pl_core::context::ResourceReader;
        use pl_core::thread::cold::OutputRetryObligation as _;

        let (temp, store, sink) = sink("archive-repair").await?;
        let resources_root = temp.path().join("resources");
        std::fs::create_dir_all(&resources_root)?;
        let archive = crate::resource_store::FileResourceStore::new(resources_root);
        let backend = pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf());

        let capture_file = temp.path().join("capture.fragment");
        let committed = b"accepted line one\n".to_vec();
        let pending = b"accepted line two".to_vec();
        // The failed append left the fragment short of the bytes already accepted and published live:
        // a few bytes of the pending chunk were written, without their framing and without the rest.
        let mut partial = committed.clone();
        partial.extend_from_slice(&pending[..4]);
        std::fs::write(&capture_file, &partial)?;
        let mut expected = committed.clone();
        expected.extend_from_slice(&pending);

        let retries = Arc::new(AtomicUsize::new(0));
        let created: Arc<Mutex<Vec<Arc<CaptureRepairObligation>>>> =
            Arc::new(Mutex::new(Vec::new()));
        let thread =
            ThreadHandle::start("archive-repair".into(), DynModelSession::new(CaptureModel))?;
        thread
            .register_tools(vec![Registration::new(
                "capture".into(),
                OpaquePayload::text("Tool capture"),
                FailedAppendCaptureTool {
                    backend,
                    archive: archive.clone(),
                    capture_file: capture_file.clone(),
                    committed_len: committed.len() as u64,
                    pending: pending.clone(),
                    retries: retries.clone(),
                    created: created.clone(),
                },
            )?])
            .await?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;

        let runner = tokio::spawn({
            let thread = thread.clone();
            async move {
                thread
                    .run_turn(TurnInput {
                        turn_id: "capture-turn".into(),
                        attempt_prefix: "capture".into(),
                        content: vec![ContextContent::Text {
                            text: Arc::from("run capture"),
                        }],
                        max_model_steps: ModelStepLimit::Limited(
                            std::num::NonZeroU32::new(1).expect("positive model step limit"),
                        ),
                        cancellation: CancellationToken::new(),
                    })
                    .await
            }
        });
        let faulted = await_stage(&thread, "typed storage fault latch", |snapshot| {
            snapshot.persistence.resume_required
        })
        .await?;
        assert_eq!(
            faulted.persistence.fault,
            Some(pl_core::thread::cold::StorageFaultKind::WriteFailed)
        );
        let generation = faulted.persistence.fault_generation;
        assert_eq!(
            faulted.persistence.output_obligations.len(),
            1,
            "the failed capture owes exactly one archive obligation"
        );
        assert!(
            !faulted.persistence.resume_ready,
            "a failed archive must not offer a continue before its bytes are stored"
        );

        // The requirement is that the owed obligation blocks continuation, not that the Turn reaches
        // one particular phase: with a one-step limit the Turn may simply end after the fault, and no
        // later phase frame is guaranteed to be published. Stopping the driver and refusing the
        // explicit continue while the obligation is still owed proves the real boundary.
        drop(runner);
        assert!(
            !thread.snapshot().persistence.output_obligations.is_empty(),
            "the failed capture is still owed before the retry: {}",
            stage_facts(&thread.snapshot())
        );
        assert!(
            thread.resume_storage(generation).await.is_err(),
            "the pause stays closed until the archive obligation is re-stored"
        );

        thread.retry_output_storage().await?;
        thread.flush().await?;
        assert_eq!(
            retries.load(Ordering::SeqCst),
            1,
            "the real repair and archive run exactly once for the failed capture"
        );

        let history = store.history("archive-repair").await?;
        let fact = history
            .tool_task("task:capture-1")
            .await?
            .context("the committed tool task is durable")?;
        let delivery = fact.delivery.context("the committed delivery is durable")?;
        let reference = delivery
            .delivered_context
            .iter()
            .find_map(|content| match content {
                ContextContent::Resource { reference } => Some(reference.clone()),
                _ => None,
            })
            .context("the repaired reference is recorded on the committed delivery")?;
        assert!(
            reference.id().starts_with("pl.studio.resource:"),
            "the delivery records the real content-addressed archive reference"
        );
        let stored_bytes =
            ResourceReader::read(&archive, reference.clone(), CancellationToken::new()).await?;
        assert_eq!(
            stored_bytes.as_ref(),
            expected.as_slice(),
            "the archive stores the accepted bytes verbatim, once, without the partial write"
        );
        let items = history.items_for_turn("capture-turn").await?;
        let output = items
            .iter()
            .find_map(|item| match item.state() {
                pl_protocol::ThreadItemState::Tool(tool) => tool.terminal_output(),
                _ => None,
            })
            .context("the repaired call keeps its durable terminal result")?;
        let referenced = serde_json::to_value(&reference)?;
        assert_eq!(
            output
                .output_artifacts()
                .iter()
                .filter(|artifact| *artifact == &referenced)
                .count(),
            1,
            "the durable item carries the repaired reference exactly once"
        );

        // Off-window stage: the bounded live window is not a save authority. A window that never saw
        // the commit — no GUI open, a slow reader, or a rolled-over window — must still project the
        // repair from the already-committed body, so the canonical item and its content version come
        // from the single projection owner and the durable row is a pure confirmation. A second,
        // already-committed tool identity with no reference yet is written through the writer's own
        // durable commit path, then repaired by a fresh window that has to read it back.
        // The durable identity the single projection owner derives from the call id, kept identical to
        // `order::tool_id` so the owner's own history lookup finds exactly this committed row.
        // This is a separate cold fixture, not an out-of-band mutation of the live writer's
        // database: its artificial sequence must not invalidate the live recovery checkpoint.
        let history = crate::studio::storage::history::HistoryStore::open(
            &temp.path().join("off-window.sqlite"),
            "archive-repair",
        )
        .await?;
        let off_window_id = format!("tool:{}:capture-2", "capture-2".len());
        let off_window_item = pl_protocol::ThreadItem::new(
            off_window_id.clone(),
            "archive-repair".to_owned(),
            "capture-turn".to_owned(),
            41,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    "capture-2".to_owned(),
                    "capture".to_owned(),
                    "{}".to_owned(),
                ),
                pl_protocol::ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                    1,
                    pl_protocol::ThreadToolOutput::new(
                        "accepted so far".to_owned(),
                        Vec::new(),
                        Vec::new(),
                        None,
                    ),
                )),
            )),
        );
        history
            .commit_effect(
                1_000_000,
                EffectCommit {
                    items: std::slice::from_ref(&off_window_item),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let repair_only = ThreadEffectBatch {
            thread_id: "archive-repair".to_owned(),
            sequence: 1,
            committed_at: 1,
            delivery_repairs: Arc::from([pl_core::thread::cold::OutputRepair {
                call_id: "capture-2".to_owned(),
                reference: reference.clone(),
            }]),
            ..Default::default()
        };
        let mut off_window = crate::studio::thread_projection::LiveProjection::new();
        crate::studio::thread_projection::seed_repaired_targets(
            &mut off_window,
            &history,
            &repair_only,
        )
        .await?;
        assert!(
            off_window.holds_terminal_tool(&off_window_id),
            "the off-window repair reads the committed body back before projecting it"
        );
        let chat = store.chat_session("archive-repair").await?;
        let packaged = off_window.project_committed(
            &chat,
            &test_thread("archive-repair"),
            &repair_only,
            &ThreadSnapshot::default(),
        )?;
        let repackaged = packaged
            .items
            .iter()
            .find(|item| item.id == off_window_id)
            .context("the off-window repair is projected at its original identity")?;
        assert_eq!(
            repackaged.ordinal, off_window_item.ordinal,
            "the supplement keeps the committed position instead of taking a new one"
        );
        assert_eq!(
            repackaged.revision,
            off_window_item.revision + 1,
            "the single projection owner assigns the content version; the writer never invents one"
        );
        let repackaged_output = match repackaged.state() {
            pl_protocol::ThreadItemState::Tool(tool) => tool.terminal_output(),
            _ => None,
        }
        .context("the off-window supplement keeps the terminal tool result")?;
        assert_eq!(
            repackaged_output
                .output_artifacts()
                .iter()
                .filter(|artifact| *artifact == &referenced)
                .count(),
            1,
            "the off-window projection appends the reference exactly once"
        );

        // The caller can only continue once the obligation and its repair really landed.
        thread.resume_storage(generation).await?;
        assert!(!thread.snapshot().persistence.resume_required);

        // A repeated retry reproduces the same bytes and the same reference instead of appending twice.
        let obligation = created
            .lock()
            .unwrap()
            .first()
            .cloned()
            .expect("the tool created its obligation");
        let again = obligation.retry().await?;
        let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(repaired) = again else {
            anyhow::bail!("the repeated retry must name the same repaired reference");
        };
        assert_eq!(repaired.reference, reference);
        assert_eq!(
            std::fs::read(&capture_file)?,
            expected,
            "repeating the repair reproduces the fragment instead of duplicating the chunk"
        );
        assert_eq!(retries.load(Ordering::SeqCst), 2);
        thread.close().await?;
        Ok(())
    }

    /// Re-materializes a whole multi-chunk capture plan through the real local backend, then archives
    /// the fragment: the same shape core retries for a failed command capture.
    #[derive(Debug)]
    struct CapturePlanObligation {
        backend: pl_tool::command::LocalCommandBackend,
        archive: crate::resource_store::FileResourceStore,
        capture_file: std::path::PathBuf,
        call_id: String,
        plan: pl_tool::command::CaptureRepair,
        retries: Arc<AtomicUsize>,
    }

    impl pl_core::thread::cold::OutputRetryObligation for CapturePlanObligation {
        fn identity(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn retry(&self) -> pl_core::thread::cold::OutputRetryFuture<'_> {
            Box::pin(async move {
                self.retries.fetch_add(1, Ordering::SeqCst);
                // Replay the plan in acceptance order: one truncation back to the backend-confirmed
                // offset, then every accepted chunk re-appended with its own framing.
                let mut confirmed = self.plan.confirmed;
                for chunk in &self.plan.chunks {
                    let capture = match chunk.stream {
                        pl_tool::command::CommandCaptureStream::Stdout => self.capture_file.clone(),
                        pl_tool::command::CommandCaptureStream::Stderr => {
                            self.capture_file.with_file_name("stderr.log")
                        }
                    };
                    let committed_len = pl_tool::command::CommandBackend::repair_output_chunk(
                        &self.backend,
                        &capture,
                        chunk.stream,
                        confirmed.get(chunk.stream),
                        &chunk.pending,
                    )
                    .await
                    .map_err(|error| {
                        pl_core::thread::cold::ColdStoreError {
                            source: Box::new(std::io::Error::other(error.to_string())),
                        }
                    })?;
                    confirmed.set(chunk.stream, committed_len);
                }
                let reference = self
                    .archive
                    .retain_command_capture(&self.capture_file)
                    .await
                    .map_err(|error| pl_core::thread::cold::ColdStoreError {
                        source: Box::new(error),
                    })?;
                Ok(pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(
                    pl_core::thread::cold::OutputRepair {
                        call_id: self.call_id.clone(),
                        reference,
                    },
                ))
            })
        }
        fn received_bytes(&self) -> u64 {
            self.plan.confirmed.total()
        }
        fn location(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn kind(&self) -> pl_core::thread::cold::StorageFaultKind {
            pl_core::thread::cold::StorageFaultKind::WriteFailed
        }
    }

    /// Two streams' accepted chunks survive one reader's partial capture write.
    ///
    /// The first stdout append failed after writing part of its chunk, and the stderr reader had
    /// already accepted (and published) a chunk. Both must be re-materialized verbatim, once, in
    /// acceptance order: the second append must not land past the fault, and a repeated retry must not
    /// duplicate or truncate either chunk. The archived reference must read back the whole fragment.
    #[tokio::test]
    async fn a_two_stream_capture_repair_replays_every_accepted_chunk_once() -> Result<()> {
        use pl_core::context::ResourceReader;
        use pl_core::thread::cold::OutputRetryObligation as _;

        let temp = tempfile::tempdir()?;
        let resources_root = temp.path().join("resources");
        std::fs::create_dir_all(&resources_root)?;
        let archive = crate::resource_store::FileResourceStore::new(resources_root);
        let backend = pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf());

        // The committed offset comes from the real backend's confirmed writes, not a hand-computed or
        // swallowed fragment length: prepare the header, then append the chunk the capture already
        // stored. That returned length is exactly what a repair truncates back to.
        let target = pl_tool::command::CommandBackend::output_target(
            &backend,
            "session",
            "exec",
            "capture-2",
            "capture",
        )
        .await?;
        pl_tool::command::CommandBackend::prepare_output(
            &backend,
            &target,
            "capture",
            "/tmp",
            pl_tool::command::MAX_CAPTURE_BYTES,
        )
        .await?;
        let capture_file = target.capture_file().to_path_buf();
        let committed = b"committed line\n".to_vec();
        let committed_len = pl_tool::command::CommandBackend::append_output_chunk(
            &backend,
            &target,
            pl_tool::command::CommandCaptureStream::Stdout,
            &committed,
        )
        .await?;
        let committed_prefix = std::fs::read(&capture_file)?;
        assert_eq!(
            committed_len,
            committed_prefix.len() as u64,
            "the repair offset is the backend-confirmed fragment length"
        );

        let stdout_pending = b"first failed stdout chunk".to_vec();
        let stderr_pending = b"second stream accepted chunk".to_vec();
        // The failed append left its framing and a few bytes of its chunk past the confirmed offset;
        // the stderr chunk was accepted and published before the fault, so it is still owed.
        {
            use std::io::Write as _;
            let mut fragment = std::fs::OpenOptions::new()
                .append(true)
                .open(&capture_file)?;
            fragment.write_all(b"=== STDOUT ===\n")?;
            fragment.write_all(&stdout_pending[..7])?;
        }

        let expected = {
            let mut expected = committed_prefix;
            expected.extend_from_slice(&stdout_pending);
            expected
        };

        let retries = Arc::new(AtomicUsize::new(0));
        let obligation = Arc::new(CapturePlanObligation {
            backend,
            archive: archive.clone(),
            capture_file: capture_file.clone(),
            call_id: "capture-2".to_owned(),
            plan: pl_tool::command::CaptureRepair {
                confirmed: pl_tool::command::CommandCaptureOffsets {
                    stdout: committed_len,
                    stderr: 0,
                },
                chunks: vec![
                    pl_tool::command::CaptureRepairChunk {
                        stream: pl_tool::command::CommandCaptureStream::Stdout,
                        pending: Arc::from(stdout_pending.clone()),
                    },
                    pl_tool::command::CaptureRepairChunk {
                        stream: pl_tool::command::CommandCaptureStream::Stderr,
                        pending: Arc::from(stderr_pending.clone()),
                    },
                ],
            },
            retries: retries.clone(),
        });

        let first = obligation.retry().await?;
        assert_eq!(
            std::fs::read(capture_file.with_file_name("stderr.log"))?,
            stderr_pending
        );
        let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(first) = first else {
            anyhow::bail!("the repair must name the stored reference");
        };
        assert_eq!(
            std::fs::read(&capture_file)?,
            expected,
            "the retry stores both accepted chunks verbatim, in order, without the partial write"
        );
        let stored =
            ResourceReader::read(&archive, first.reference.clone(), CancellationToken::new())
                .await?;
        assert_eq!(
            stored.as_ref(),
            expected.as_slice(),
            "the archived reference reads back the whole accepted fragment"
        );

        let again = obligation.retry().await?;
        let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(again) = again else {
            anyhow::bail!("the repeated retry must name the same stored reference");
        };
        assert_eq!(again.reference, first.reference);
        assert_eq!(
            std::fs::read(&capture_file)?,
            expected,
            "the repeated retry reproduces the same fragment instead of duplicating a chunk"
        );
        assert_eq!(retries.load(Ordering::SeqCst), 2);
        Ok(())
    }

    use pl_tool::command::CommandBackend as _;

    /// A command backend whose capture append is held and then failed, over in-memory IO.
    ///
    /// The read/repair and header capabilities delegate to a real [`pl_tool::command::LocalCommandBackend`],
    /// but `spawn` hands back a [`pl_tool::command::ManagedCommand`] over duplex pipes the test feeds
    /// directly, and `append_output_chunk` waits for a gate and then fails like a real disk write error.
    /// That makes the operation's single writer task — not a hand-made plan — the thing that observes the
    /// fault.
    struct ScriptedCaptureBackend {
        inner: pl_tool::command::LocalCommandBackend,
        stdout: std::sync::Mutex<Option<pl_tool::command::CommandReader>>,
        stderr: std::sync::Mutex<Option<pl_tool::command::CommandReader>>,
        exit: Arc<Notify>,
        gate: Arc<Notify>,
    }

    impl std::fmt::Debug for ScriptedCaptureBackend {
        fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter
                .debug_struct("ScriptedCaptureBackend")
                .finish_non_exhaustive()
        }
    }

    impl pl_tool::command::CommandBackend for ScriptedCaptureBackend {
        type Error = pl_protocol::PureError;

        fn capture_ownership(&self) -> pl_tool::command::CommandCaptureOwnership {
            self.inner.capture_ownership()
        }
        fn capture_storage_cost(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
            stream: pl_tool::command::CommandCaptureStream,
            chunk: &[u8],
        ) -> u64 {
            self.inner.capture_storage_cost(target, stream, chunk)
        }

        async fn resolve_cwd(
            &self,
            cwd: Option<&std::path::Path>,
            allow_workspace_escape: bool,
        ) -> Result<String, Self::Error> {
            self.inner.resolve_cwd(cwd, allow_workspace_escape).await
        }

        async fn output_target(
            &self,
            session_id: &str,
            tool_id: &str,
            call_id: &str,
            command: &str,
        ) -> Result<pl_tool::command::CommandOutputTarget, Self::Error> {
            self.inner
                .output_target(session_id, tool_id, call_id, command)
                .await
        }

        async fn spawn(
            &self,
            _request: pl_tool::command::CommandSpawnRequest,
        ) -> Result<pl_tool::command::ManagedCommand, Self::Error> {
            let stdout = self.stdout.lock().expect("stdout reader").take();
            let stderr = self.stderr.lock().expect("stderr reader").take();
            let exit = self.exit.clone();
            Ok(pl_tool::command::ManagedCommand::new(
                None,
                pl_tool::command::CommandIo {
                    stdin: None,
                    stdout,
                    stderr,
                },
                move |_cancellation| async move {
                    exit.notified().await;
                    Ok(pl_tool::command::CommandExit {
                        supervision_failure: None,
                        signal: None,
                        capture_failure: None,
                        exit_code: Some(0),
                        capture: None,
                    })
                },
            ))
        }

        async fn prepare_output(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
            command: &str,
            working_directory: &str,
            capture_limit_bytes: u64,
        ) -> Result<u64, Self::Error> {
            self.inner
                .prepare_output(target, command, working_directory, capture_limit_bytes)
                .await
        }

        async fn append_output_chunk(
            &self,
            _target: &pl_tool::command::CommandOutputTarget,
            _stream: pl_tool::command::CommandCaptureStream,
            _chunk: &[u8],
        ) -> Result<u64, Self::Error> {
            // Hold the operation's single writer until the test has confirmed both streams' accepted
            // chunks, then fail the append the way a real capture write error would.
            self.gate.notified().await;
            Err(pl_protocol::PureError::ToolExecutionFailed {
                tool: "exec".to_owned(),
                error: "capture append failed".to_owned(),
            })
        }

        async fn repair_output_chunk(
            &self,
            capture_file: &std::path::Path,
            stream: pl_tool::command::CommandCaptureStream,
            committed_len: u64,
            chunk: &[u8],
        ) -> Result<u64, Self::Error> {
            self.inner
                .repair_output_chunk(capture_file, stream, committed_len, chunk)
                .await
        }

        async fn publish_output(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
        ) -> Result<(), Self::Error> {
            self.inner.publish_output(target).await
        }

        async fn collect_output_artifacts(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
            sizes: pl_tool::command::CommandOutputSizes,
        ) -> Result<Vec<serde_json::Value>, Self::Error> {
            self.inner.collect_output_artifacts(target, sizes).await
        }
    }

    /// Signals once both command streams have published an accepted chunk.
    #[derive(Debug, Default)]
    struct BothStreamsSeen {
        stdout: AtomicUsize,
        stderr: AtomicUsize,
        both: Notify,
    }

    impl pl_tool::command::CommandOutputObserver for BothStreamsSeen {
        fn output_chunk(
            &self,
            stream: pl_tool::command::CommandOutputStream,
            chunk: &[u8],
            _revision: u64,
        ) {
            let counter = match stream {
                pl_tool::command::CommandOutputStream::Stdout => &self.stdout,
                pl_tool::command::CommandOutputStream::Stderr => &self.stderr,
            };
            counter.fetch_add(chunk.len().max(1), Ordering::SeqCst);
            if self.stdout.load(Ordering::SeqCst) > 0 && self.stderr.load(Ordering::SeqCst) > 0 {
                self.both.notify_one();
            }
        }
    }

    /// The real command lifecycle retains and replays a two-stream capture fault.
    ///
    /// This drives the operation, not a hand-made plan: both readers accept *and publish* a chunk from
    /// their stream, the operation's single writer is held until then and only then fails its append,
    /// and the scripted process then exits. So the retained repair plan must hold both streams' accepted
    /// chunks, the terminal result must not be a success, and replaying the plan through the real local
    /// backend must archive exactly those bytes under one reference that reads back whole.
    #[tokio::test]
    async fn a_two_stream_capture_fault_is_retained_and_replayed_by_the_lifecycle() -> Result<()> {
        use pl_core::context::ResourceReader;

        let temp = tempfile::tempdir()?;
        let resources_root = temp.path().join("resources");
        std::fs::create_dir_all(&resources_root)?;
        let archive = crate::resource_store::FileResourceStore::new(resources_root);

        let (mut stdout_writer, stdout_reader) = tokio::io::duplex(1024);
        let (mut stderr_writer, stderr_reader) = tokio::io::duplex(1024);
        let gate = Arc::new(Notify::new());
        let exit = Arc::new(Notify::new());
        let backend = ScriptedCaptureBackend {
            inner: pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf()),
            stdout: std::sync::Mutex::new(Some(
                Box::pin(stdout_reader) as pl_tool::command::CommandReader
            )),
            stderr: std::sync::Mutex::new(Some(
                Box::pin(stderr_reader) as pl_tool::command::CommandReader
            )),
            exit: exit.clone(),
            gate: gate.clone(),
        };
        let manager = Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
            backend,
        )));

        let seen = Arc::new(BothStreamsSeen::default());
        let observer: Arc<dyn pl_tool::command::CommandOutputObserver> = seen.clone();
        let request = pl_tool::command::CommandStartRequest {
            command: "scripted".to_owned(),
            cwd: Some(temp.path().to_path_buf()),
            allow_workspace_escape: false,
            timeout: Duration::from_secs(30),
            yield_time: Duration::ZERO,
            max_output_chars: 4096,
            session_id: "two-stream-lifecycle".to_owned(),
            tool_id: "task-two-stream-lifecycle".to_owned(),
            call_id: "task-two-stream-lifecycle".to_owned(),
            cancellation_token: None,
            output_observer: Some(observer),
        };
        let runner = {
            let manager = manager.clone();
            tokio::spawn(
                async move { manager.run_task("task-two-stream-lifecycle", request).await },
            )
        };

        tokio::io::AsyncWriteExt::write_all(&mut stdout_writer, b"OUT-1\n").await?;
        tokio::io::AsyncWriteExt::write_all(&mut stderr_writer, b"ERR-1\n").await?;
        tokio::time::timeout(Duration::from_secs(30), seen.both.notified())
            .await
            .context("both streams should have published an accepted chunk")?;

        // Both accepted chunks are queued in the one plan; now let the held append fail for real, then
        // close the streams and exit the scripted process so the operation settles.
        gate.notify_one();
        drop(stdout_writer);
        drop(stderr_writer);
        exit.notify_one();

        let snapshot = match tokio::time::timeout(Duration::from_secs(30), runner).await {
            Ok(Ok(Ok(snapshot))) => snapshot,
            Ok(Ok(Err(error))) => {
                anyhow::bail!("the operation returned an error instead of a snapshot: {error}")
            }
            Ok(Err(error)) => anyhow::bail!("the operation task failed: {error}"),
            Err(_) => {
                anyhow::bail!("the operation never settled: the capture writer did not drain")
            }
        };

        assert!(
            matches!(
                &snapshot.output_failure,
                Some(pl_tool::command::CommandCaptureFailure::Write { .. })
            ),
            "the real append failure must surface as a typed capture write failure: {:?}",
            snapshot.output_failure
        );
        assert!(
            snapshot.state.final_result().is_some(),
            "the snapshot is only returned once the operation settled"
        );
        assert!(
            !matches!(
                snapshot.state.final_result(),
                Some(pl_tool::command::CommandProcessFinalResult::Succeeded { .. })
            ),
            "a capture write failure must never be reported as a successful command"
        );

        let plan = snapshot
            .capture_repair()
            .cloned()
            .context("both accepted chunks must stay owed after the failed append")?;
        assert_eq!(
            plan.chunks.len(),
            2,
            "both streams' accepted chunks are retained"
        );
        assert!(
            plan.chunks.iter().any(|chunk| {
                chunk.stream == pl_tool::command::CommandCaptureStream::Stdout
                    && &chunk.pending[..] == b"OUT-1\n".as_slice()
            }),
            "the stdout chunk is retained verbatim"
        );
        assert!(
            plan.chunks.iter().any(|chunk| {
                chunk.stream == pl_tool::command::CommandCaptureStream::Stderr
                    && &chunk.pending[..] == b"ERR-1\n".as_slice()
            }),
            "the stderr chunk is retained verbatim"
        );

        // Replay the plan through the real local backend and archive it: the stored reference must read
        // back exactly the accepted bytes, in acceptance order, with the failed append left off.
        let real = pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf());
        let mut confirmed = plan.confirmed;
        for chunk in &plan.chunks {
            let capture = match chunk.stream {
                pl_tool::command::CommandCaptureStream::Stdout => &snapshot.capture_file,
                pl_tool::command::CommandCaptureStream::Stderr => &snapshot.stderr_capture_file,
            };
            let committed_len = real
                .repair_output_chunk(
                    capture,
                    chunk.stream,
                    confirmed.get(chunk.stream),
                    &chunk.pending,
                )
                .await?;
            confirmed.set(chunk.stream, committed_len);
        }
        let reference = archive
            .retain_command_capture(&snapshot.capture_file)
            .await?;
        let stored = ResourceReader::read(&archive, reference, CancellationToken::new()).await?;
        let stored = String::from_utf8_lossy(stored.as_ref());
        assert!(
            stored.contains("OUT-1"),
            "the archive keeps the stdout chunk: {stored}"
        );
        let stderr_reference = archive
            .retain_command_capture(&snapshot.stderr_capture_file)
            .await?;
        let stderr =
            ResourceReader::read(&archive, stderr_reference, CancellationToken::new()).await?;
        assert_eq!(stderr.as_ref(), b"ERR-1\n");
        assert_eq!(stored.as_ref(), "OUT-1\n");

        Ok(())
    }
}
